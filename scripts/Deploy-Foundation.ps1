[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $SubscriptionId,
    [Parameter(Mandatory)] [string] $SqlAdministratorLogin,
    [Parameter(Mandatory)] [securestring] $SqlAdministratorPassword,
    [Parameter(Mandatory)] [string] $AlertEmailAddress,
    [string] $NamePrefix = 'novamart',
    [string] $Location = 'eastus'
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI is required. Install it, run az login, and rerun this script.'
}

az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) { throw 'Could not select the Azure subscription.' }

$passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SqlAdministratorPassword)
try {
    $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer)
    $deploymentJson = az deployment sub create `
        --name "novamart-foundation-$(Get-Date -Format yyyyMMddHHmmss)" `
        --location $Location `
        --template-file (Join-Path $repositoryRoot 'infra/main.bicep') `
        --parameters namePrefix=$NamePrefix location=$Location sqlAdministratorLogin=$SqlAdministratorLogin sqlAdministratorPassword=$plainPassword alertEmailAddress=$AlertEmailAddress `
        --output json
    if ($LASTEXITCODE -ne 0) { throw 'Foundation deployment failed.' }
}
finally {
    if ($passwordPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer)
    }
    $plainPassword = $null
}

$deployment = $deploymentJson | ConvertFrom-Json
$environments = $deployment.properties.outputs.environments.value

foreach ($environment in $environments) {
    Write-Host "Uploading sample data to $($environment.environment) storage account $($environment.storageAccountName)..."
    az storage blob upload-batch `
        --account-name $environment.storageAccountName `
        --auth-mode key `
        --destination 'landing/source_data' `
        --source (Join-Path $repositoryRoot 'source_data') `
        --overwrite true `
        --output none
    if ($LASTEXITCODE -ne 0) { throw "Source upload failed for $($environment.environment)." }

    $workflowResourceId = "/subscriptions/$SubscriptionId/resourceGroups/$($environment.resourceGroup)/providers/Microsoft.Logic/workflows/$($environment.logicAppName)/triggers/manual"
    $callback = az rest `
        --method post `
        --uri "https://management.azure.com${workflowResourceId}/listCallbackUrl?api-version=2016-06-01" `
        --query value `
        --output tsv

    Write-Host "Environment $($environment.environment) ready:"
    Write-Host "  ADF: $($environment.dataFactoryName)"
    Write-Host "  Key Vault URL: https://$($environment.keyVaultName).vault.azure.net/"
    Write-Host "  Storage event scope: /subscriptions/$SubscriptionId/resourceGroups/$($environment.resourceGroup)/providers/Microsoft.Storage/storageAccounts/$($environment.storageAccountName)"
    Write-Host "  Logic App callback URL (store as a secret pipeline variable): $callback"
}

Write-Warning 'Authorize each Office 365 API connection in Azure Portal before testing failure email; OAuth consent cannot be completed non-interactively.'
Write-Host 'Next: run sql/01 through sql/03 against each database, publish DEV, and configure the Azure DevOps variable groups described in docs/DEPLOYMENT.md.'
