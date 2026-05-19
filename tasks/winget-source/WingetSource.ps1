[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $Name,

    [Parameter(Mandatory = $true)]
    [string] $Source,

    [Parameter()]
    [string] $HeaderName = "x-functions-key",

    [Parameter()]
    [string] $HeaderValue,

    [Parameter()]
    [string] $TrustLevel = "trusted",

    [Parameter()]
    [string] $RemoveDefaultSources = "false"
)

###################################################################################################
#
# PowerShell configurations
#

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

###################################################################################################
#
# Functions
#

function Get-WingetPath {
    # During image build the task runs as SYSTEM, where the per-user WindowsApps
    # winget.exe isn't always on PATH. Probe the well-known install locations.
    $command = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $candidates = @(
        "$Env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe",
        "$Env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe"
    )

    foreach ($pattern in $candidates) {
        $match = Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending |
            Select-Object -First 1
        if ($match) { return $match.FullName }
    }

    throw "winget.exe was not found on this image. Ensure the App Installer package is provisioned."
}

function Invoke-Winget {
    param([string[]] $Arguments)

    Write-Host "winget $($Arguments -join ' ')"
    & $script:Winget @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "winget exited with code $LASTEXITCODE"
    }
}

###################################################################################################
#
# Main
#

$script:Winget = Get-WingetPath
Write-Host "Using winget at: $script:Winget"

# Detect unresolved Dev Box secret placeholders. If we see "{{...}}" here, the
# Dev Box service did not substitute the Key Vault secret URI and the literal
# string would be sent as the auth header value. Fail fast with a clear message
# instead of letting winget return an opaque "Failed to open the added source".
foreach ($pair in @(
    @{ Name = "Source";       Value = $Source },
    @{ Name = "HeaderValue";  Value = $HeaderValue },
    @{ Name = "HeaderName";   Value = $HeaderName }
)) {
    if ($pair.Value -match '{{.*}}') {
        throw "Parameter '$($pair.Name)' still contains an unresolved '{{...}}' placeholder: '$($pair.Value)'. Ensure the dev center's managed identity has 'Key Vault Secrets User' on the target Key Vault and the secret URI is correct."
    }
}

# Accept any pending source agreements so non-interactive use doesn't block.
Invoke-Winget @("settings", "--enable", "LocalManifestFiles") 2>$null | Out-Null

# Remove an existing registration with the same name so this task is idempotent.
$existing = & $script:Winget source list 2>$null
if ($LASTEXITCODE -eq 0 -and $existing -match [Regex]::Escape($Name)) {
    Write-Host "Removing existing source '$Name' before re-adding."
    & $script:Winget source remove --name $Name | Out-Null
}

$addArgs = @("source", "add", "--name", $Name, "--arg", $Source, "--type", "Microsoft.Rest", "--accept-source-agreements")

if ($HeaderValue) {
    if (-not $HeaderName) {
        throw "HeaderName must be provided when HeaderValue is set."
    }
    $headerJson = (@{ $HeaderName = $HeaderValue } | ConvertTo-Json -Compress)
    $addArgs += @("--header", $headerJson)
}

if ($TrustLevel) {
    $addArgs += @("--trust-level", $TrustLevel)
}

Invoke-Winget $addArgs

if ($RemoveDefaultSources -eq "true") {
    foreach ($default in @("winget", "msstore")) {
        Write-Host "Removing default source '$default'."
        & $script:Winget source remove --name $default 2>$null | Out-Null
    }
}

Write-Host "Winget source '$Name' registered successfully."
