<#
.SYNOPSIS
    Script to create a new Dev Drive on a Dev Box image.

.DESCRIPTION
    Creates a Dev Drive either as a new VHDX or by resizing the C: partition.
    See https://learn.microsoft.com/en-us/windows/dev-drive/ for background.

    Adapted from the dev-drive task at
    https://github.com/dstamand-msft/Devbox-Customizations/tree/main/Tasks/dev-drive
    (Author: Dominique St-Amand, MIT-style example).
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, HelpMessage = "Type of Dev Drive to create. 'vhdx' or 'resize'.")]
    [ValidateSet("vhdx", "resize")]
    [string]$Type,

    [Parameter(Mandatory = $true, HelpMessage = "The drive letter to mount the Dev Drive to.")]
    [ValidatePattern("^[A-Z]$")]
    [string]$DriveLetter,

    [Parameter(Mandatory = $true, HelpMessage = "The size of the Dev Drive in MB.")]
    [int]$DriveSize
)

$ErrorActionPreference = "Stop"

switch ($Type) {
    "vhdx" {
        # Inspired by https://gist.github.com/lawndoc/ea03e2ee0f4d64162669d1b5e997ec77
        $drivePath    = Join-Path "C:\" "VHDX"
        $vhdxFilePath = Join-Path $drivePath "devdrive.vhdx"

        if (Test-Path $vhdxFilePath) {
            Write-Error "ERROR: $vhdxFilePath already exists! Aborting..."
            exit 1
        }
        if (Test-Path "$($DriveLetter):") {
            Write-Error "ERROR: Drive letter $($DriveLetter): is already in use! Aborting..."
            exit 1
        }

        # Image build runs as SYSTEM (no user profile), so use a known temp directory.
        $tmpDir = Join-Path "C:\" "Temp"
        if (-not (Test-Path $tmpDir)) {
            New-Item $tmpDir -Type Directory -Force | Out-Null
        }

        $diskPartFile = Join-Path -Path $tmpDir -ChildPath "diskpart_devdrive.txt"

        Write-Output "[*] Writing diskpart configuration..."
        $diskPartFileData  = "create vdisk file='$vhdxFilePath' maximum=$DriveSize type=expandable`n"
        $diskPartFileData += "select vdisk file='$vhdxFilePath'`n"
        $diskPartFileData += "attach vdisk`n"
        $diskPartFileData += "create partition primary`n"
        $diskPartFileData += "format fs=refs label='Dev Drive' quick`n"
        $diskPartFileData += "assign letter=$($DriveLetter)`n"

        $diskPartFileData | Out-File -Encoding ascii -FilePath $diskPartFile -Force

        Write-Output "[*] Creating Dev Drive VHDX at $vhdxFilePath..."
        if (-not (Test-Path $drivePath)) {
            New-Item $drivePath -Type Directory -Force | Out-Null
        }

        diskpart /s "$diskPartFile"
        Format-Volume -DriveLetter $DriveLetter -DevDrive

        if (-not (Test-Path "$($DriveLetter):")) {
            Write-Error "ERROR: Failed to create ReFS vdisk for Dev Drive..."
            exit 1
        }

        Write-Output "[*] Verifying Dev Drive trust..."
        fsutil devdrv query "$($DriveLetter):"

        # Dev Drive VHDX does not re-mount on reboot without help.
        # See https://github.com/microsoft/devhome/issues/1903
        $script  = "# Mounts the Dev Drive VHDX at boot.`n"
        $script += "`$devDriveTaskFile = Join-Path `$Env:Temp `"devdrivetask.txt`"`n"
        $script += "`$task  = `"select vdisk file='$vhdxFilePath'``n`"`n"
        $script += "`$task += `"attach vdisk``n`"`n"
        $script += "`$task | Out-File -Encoding ascii -FilePath `$devDriveTaskFile -Force`n"
        $script += "Start-Process -FilePath `"diskpart.exe`" -ArgumentList `"/s `$devDriveTaskFile`" -NoNewWindow -Wait"

        $script | Out-File -Encoding ascii -FilePath (Join-Path $drivePath "devdrivetask.ps1") -Force

        $taskname        = "Mount Dev Drive"
        $taskdescription = "Make sure Dev Drive is mounted after reboots"
        $taskTrigger     = New-ScheduledTaskTrigger -AtStartup
        $taskAction      = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass .\devdrivetask.ps1" -WorkingDirectory $drivePath
        $taskSettings    = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        Register-ScheduledTask -TaskName $taskname -Description $taskdescription -Action $taskAction -Trigger $taskTrigger -Settings $taskSettings -User "System" -RunLevel Highest

        Write-Output "[*] Done."
    }
    "resize" {
        if ($DriveSize -lt 51200) {
            Write-Error "ERROR: The minimum size for a resize-based Dev Drive is 50GB (51200 MB)."
            exit 1
        }
        $partition           = Get-Partition -DiskNumber 0 | Where-Object { $_.Type -eq "Basic" }
        $driveSizeInMB       = [math]::Floor($partition.Size / (1024 * 1024))
        $newDriveSizeInMB    = $driveSizeInMB - $DriveSize
        $newDriveSizeInBytes = $newDriveSizeInMB * 1024 * 1024
        $driveSizeInBytes    = $DriveSize * 1024 * 1024

        Resize-Partition -DiskNumber 0 -PartitionNumber $partition.PartitionNumber -Size $newDriveSizeInBytes
        New-Partition  -DiskNumber 0 -Size $driveSizeInBytes -DriveLetter $DriveLetter
        Format-Volume  -DriveLetter $DriveLetter -DevDrive -NewFileSystemLabel "Dev Drive"
    }
}
