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
    [string] $KeyVaultName,

    [Parameter()]
    [string] $KeyVaultSecretName,

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

function Get-KeyVaultSecretViaMI {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $SecretUri
    )

    # Parse the vault URI and secret name from the full secret URI
    # Expected format: https://<vault-name>.vault.azure.net/secrets/<secret-name>
    if ($SecretUri -notmatch '^(https://[^/]+\.vault\.azure\.net)/secrets/([^/]+)') {
        throw "Invalid Key Vault secret URI format. Expected: https://<vault-name>.vault.azure.net/secrets/<secret-name>"
    }

    $vaultBaseUri = $Matches[1]
    $secretName = $Matches[2]

    Write-Host "Fetching secret '$secretName' from Key Vault using Managed Identity..."

    # Get access token from IMDS for Key Vault
    $tokenResponse = Invoke-RestMethod -Uri 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fvault.azure.net' `
        -Headers @{ 'Metadata' = 'true' } `
        -Method GET `
        -ErrorAction Stop

    $accessToken = $tokenResponse.access_token

    # Fetch the secret value from Key Vault
    $secretResponse = Invoke-RestMethod -Uri "$vaultBaseUri/secrets/${secretName}?api-version=7.4" `
        -Headers @{ 'Authorization' = "Bearer $accessToken" } `
        -Method GET `
        -ErrorAction Stop

    return $secretResponse.value
}

###################################################################################################
#
# Main
#

Write-Host "Ensuring Chocolatey is installed."
Ensure-Chocolatey -ChocoExePath "$Choco"

# Resolve password from Key Vault if vault name and secret name are provided.
if ($KeyVaultName -and $KeyVaultSecretName) {
    $secretUri = "https://${KeyVaultName}.vault.azure.net/secrets/${KeyVaultSecretName}"
    Write-Host "Resolving password from Azure Key Vault..."
    $Password = Get-KeyVaultSecretViaMI -SecretUri $secretUri
}

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
& $Choco @arguments | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Failed to add Chocolatey source '$Name'. Exit code: $LASTEXITCODE"
}

if ($DisableDefaultSource -eq "true") {
    Write-Host "Disabling default community source (chocolatey)."
    & $Choco source disable -n=chocolatey | Out-Null
}

Write-Host "Chocolatey source '$Name' configured."
