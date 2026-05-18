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

    Write-Host "=== KEY VAULT DEBUG START ==="
    Write-Host "Vault Base URI: $vaultBaseUri"
    Write-Host "Secret Name: $secretName"
    Write-Host "Full Secret URI: $SecretUri"

    # Get access token from IMDS for Key Vault
    Write-Host "Requesting access token from IMDS endpoint (http://169.254.169.254)..."
    try {
        $tokenResponse = Invoke-RestMethod -Uri 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fvault.azure.net' `
            -Headers @{ 'Metadata' = 'true' } `
            -Method GET `
            -ErrorAction Stop
        
        Write-Host "SUCCESS: Received access token from IMDS"
        Write-Host "Token type: $($tokenResponse.token_type)"
        Write-Host "Token expires in: $($tokenResponse.expires_in) seconds"
        Write-Host "Resource: $($tokenResponse.resource)"
        # Don't log the actual token for security, but confirm we got one
        if ($tokenResponse.access_token) {
            Write-Host "Access token length: $($tokenResponse.access_token.Length) characters"
        } else {
            Write-Host "WARNING: access_token is null or empty!"
        }
    }
    catch {
        Write-Host "FAILED: Could not get access token from IMDS"
        Write-Host "Error: $($_.Exception.Message)"
        Write-Host "Full exception: $_"
        throw
    }

    $accessToken = $tokenResponse.access_token

    # Fetch the secret value from Key Vault
    $secretUrl = "$vaultBaseUri/secrets/${secretName}?api-version=7.4"
    Write-Host "Fetching secret from Key Vault: $secretUrl"
    try {
        $secretResponse = Invoke-RestMethod -Uri $secretUrl `
            -Headers @{ 'Authorization' = "Bearer $accessToken" } `
            -Method GET `
            -ErrorAction Stop
        
        Write-Host "SUCCESS: Retrieved secret from Key Vault"
        Write-Host "Secret ID: $($secretResponse.id)"
        # Don't log the actual secret value, but confirm we got one
        if ($secretResponse.value) {
            Write-Host "Secret value length: $($secretResponse.value.Length) characters"
        } else {
            Write-Host "WARNING: Secret value is null or empty!"
        }
    }
    catch {
        Write-Host "FAILED: Could not retrieve secret from Key Vault"
        Write-Host "Error: $($_.Exception.Message)"
        Write-Host "Full exception: $_"
        throw
    }

    Write-Host "=== KEY VAULT DEBUG END ==="
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
    Write-Host "=== CHOCO SOURCE CONFIG ==="
    Write-Host "KeyVaultName parameter: $KeyVaultName"
    Write-Host "KeyVaultSecretName parameter: $KeyVaultSecretName"
    Write-Host "Constructed secret URI: $secretUri"
    Write-Host "Resolving password from Azure Key Vault..."
    $Password = Get-KeyVaultSecretViaMI -SecretUri $secretUri
    Write-Host "Password retrieved successfully (length: $($Password.Length) chars)"
} else {
    Write-Host "=== CHOCO SOURCE CONFIG ==="
    Write-Host "KeyVaultName: '$KeyVaultName'"
    Write-Host "KeyVaultSecretName: '$KeyVaultSecretName'"
    Write-Host "Key Vault not configured - using direct password if provided"
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
