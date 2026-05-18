[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $Name,

    [Parameter(Mandatory = $true)]
    [string] $Source,

    [Parameter()]
    [string] $User,

    [Parameter()]
    [string] $Password,

    [Parameter()]
    [string] $Priority,

    [Parameter()]
    [string] $DisableDefaultSource
)

###################################################################################################
#
# PowerShell configurations
#

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Choco = "$Env:ProgramData/chocolatey/choco.exe"

###################################################################################################
#
# Functions
#

function Ensure-Chocolatey {
    [CmdletBinding()]
    param(
        [string] $ChocoExePath
    )

    if (-not (Test-Path "$ChocoExePath")) {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        $installScriptPath = [System.IO.Path]::GetTempFileName() + ".ps1"
        Invoke-WebRequest -Uri 'https://chocolatey.org/install.ps1' -OutFile $installScriptPath

        try {
            powershell.exe -File $installScriptPath
        }
        finally {
            Remove-Item $installScriptPath
        }
    }
}

###################################################################################################
#
# Main
#

Write-Host "Ensuring Chocolatey is installed."
Ensure-Chocolatey -ChocoExePath "$Choco"

# Build argument list rather than a single string so the password is not echoed.
$arguments = @('source', 'add', '-n', $Name, '-s', $Source, '-y')

if ($Priority) {
    $arguments += @('--priority', $Priority)
}

if ($User -and $Password) {
    $arguments += @('-u', $User, '-p', $Password)
    Write-Host "Adding Chocolatey source '$Name' with credentials. Source: $Source"
}
else {
    Write-Host "Adding Chocolatey source '$Name' without credentials. Source: $Source"
}

# Run choco with arguments array; do not interpolate $Password into a logged string.
Write-Host "Running: choco source add -n '$Name' -s '$Source' (credentials: $(if ($User -and $Password) { 'yes' } else { 'no' }))"
$chocoOutput = & $Choco @arguments 2>&1
Write-Host "Choco output: $chocoOutput"
if ($LASTEXITCODE -ne 0) {
    Write-Host "FAILED: choco source add returned exit code $LASTEXITCODE"
    throw "Failed to add Chocolatey source '$Name'. Exit code: $LASTEXITCODE"
}
Write-Host "SUCCESS: Chocolatey source added"

# Verify the source was added
Write-Host "Verifying source was added..."
$sourceList = & $Choco source list 2>&1
Write-Host "Current Chocolatey sources:"
Write-Host $sourceList

if ($DisableDefaultSource -eq "true") {
    Write-Host "Disabling default community source (chocolatey)."
    & $Choco source disable -n=chocolatey | Out-Null
}

Write-Host "Chocolatey source '$Name' configured."
