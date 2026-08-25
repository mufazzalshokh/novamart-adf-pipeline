[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $SubscriptionId,
    [Parameter(Mandatory)] [string] $SqlAdministratorLogin,
    [Parameter(Mandatory)] [securestring] $SqlAdministratorPassword,
    [Parameter(Mandatory)] [string] $AlertEmailAddress,
    [ValidateLength(3, 10)]
    [ValidatePattern('^[a-z0-9]+$')]
    [string] $NamePrefix = 'novamart',
    [string] $Location = 'eastus',
    [string[]] $Environments = @('dev'),
    [switch] $EnableGmailAction,
    [switch] $WhatIf
)

$invalidEnvironments = @($Environments | Where-Object { $_ -notin @('dev', 'prod') })
if ($invalidEnvironments.Count -gt 0) {
    throw "Invalid environment value(s): $($invalidEnvironments -join ', '). Allowed values: dev, prod."
}

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$parameterFile = $null

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI is required. Install it, run az login, and rerun this script.'
}

az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) { throw 'Could not select the Azure subscription.' }

$passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SqlAdministratorPassword)
try {
    $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer)
    $parameterFile = Join-Path ([IO.Path]::GetTempPath()) "novamart-$([guid]::NewGuid().ToString('N')).parameters.json"
    $parameterDocument = [ordered]@{
        '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
        contentVersion = '1.0.0.0'
        parameters = [ordered]@{
            namePrefix = @{ value = $NamePrefix }
            location = @{ value = $Location }
            sqlAdministratorLogin = @{ value = $SqlAdministratorLogin }
            sqlAdministratorPassword = @{ value = $plainPassword }
            alertEmailAddress = @{ value = $AlertEmailAddress }
            environments = @{ value = @($Environments) }
            enableGmailAction = @{ value = [bool]$EnableGmailAction }
        }
    }
    $parameterJson = $parameterDocument | ConvertTo-Json -Depth 10
    [IO.File]::WriteAllText($parameterFile, $parameterJson, [Text.UTF8Encoding]::new($false))

    $deploymentOperation = if ($WhatIf) { 'what-if' } else { 'create' }
    $deploymentJson = az deployment sub $deploymentOperation `
        --name "novamart-foundation-$(Get-Date -Format yyyyMMddHHmmss)" `
        --location $Location `
        --template-file (Join-Path $repositoryRoot 'infra/main.bicep') `
        --parameters "@$parameterFile" `
        --output json
    if ($LASTEXITCODE -ne 0) { throw "Foundation deployment $deploymentOperation failed." }
}
finally {
    if ($passwordPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer)
    }
    $plainPassword = $null
    $parameterJson = $null
    if ($parameterFile -and (Test-Path -LiteralPath $parameterFile)) {
        Remove-Item -LiteralPath $parameterFile -Force
    }
}

if ($WhatIf) {
    $deploymentJson
    Write-Host 'What-if completed successfully. No Azure resources were created.'
    return
}

$deployment = $deploymentJson | ConvertFrom-Json
$deploymentEnvironmentOutput = $deployment.properties.outputs.environments.value

if ($deploymentEnvironmentOutput -is [System.Array]) {
    $deployedEnvironments = @($deploymentEnvironmentOutput)
}
elseif ($deploymentEnvironmentOutput.PSObject.Properties.Name -contains 'environment') {
    $deployedEnvironments = @($deploymentEnvironmentOutput)
}
else {
    $deployedEnvironments = @(
        $deploymentEnvironmentOutput.PSObject.Properties | ForEach-Object { $_.Value }
    )
}

foreach ($environment in $deployedEnvironments) {
    Write-Host "Uploading sample data to $($environment.environment) storage account $($environment.storageAccountName)..."
    az storage blob upload-batch `
        --account-name $environment.storageAccountName `
        --auth-mode key `
        --destination 'landing/source_data' `
        --source (Join-Path $repositoryRoot 'source_data') `
        --overwrite true `
        --output none
    if ($LASTEXITCODE -ne 0) { throw "Source upload failed for $($environment.environment)." }

    Write-Host "Environment $($environment.environment) ready:"
    Write-Host "  ADF: $($environment.dataFactoryName)"
    Write-Host "  Key Vault URL: https://$($environment.keyVaultName).vault.azure.net/"
    Write-Host "  Storage event scope: /subscriptions/$SubscriptionId/resourceGroups/$($environment.resourceGroup)/providers/Microsoft.Storage/storageAccounts/$($environment.storageAccountName)"
    Write-Host '  Logic App callback: retrieved internally by the ADF deployment helper; never printed.'
}

Write-Warning 'Authorize each Gmail API connection in Azure Portal before testing failure email; Google OAuth consent cannot be completed non-interactively.'
Write-Host 'Next: run sql/01 through sql/03 against each database, publish DEV, and configure the Azure DevOps variable groups described in docs/DEPLOYMENT.md.'
