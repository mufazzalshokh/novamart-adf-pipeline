[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('dev', 'prod')]
    [string] $Environment,

    [Parameter(Mandatory)]
    [string] $ResourceGroupName,

    [string] $ArmFolder = '.tools/adf-arm-live',

    [switch] $WhatIf
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$parameterFile = $null
$globalParameterFile = $null
$callback = $null

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI is required.'
}

$subscriptionId = az account show --query id --output tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($subscriptionId)) {
    throw 'Azure CLI is not authenticated. Run az login and retry.'
}

$resolvedArmFolder = if ([IO.Path]::IsPathRooted($ArmFolder)) {
    $ArmFolder
}
else {
    Join-Path $repositoryRoot $ArmFolder
}

$templateFile = Join-Path $resolvedArmFolder 'ARMTemplateForFactory.json'
$baseParameterFile = Join-Path $resolvedArmFolder 'ARMTemplateParametersForFactory.json'
if (-not (Test-Path -LiteralPath $templateFile) -or -not (Test-Path -LiteralPath $baseParameterFile)) {
    throw "ADF ARM export not found in $resolvedArmFolder. Run the official ADF export first."
}

$factoryName = az resource list --resource-group $ResourceGroupName --resource-type 'Microsoft.DataFactory/factories' --query '[0].name' --output tsv
$keyVaultName = az resource list --resource-group $ResourceGroupName --resource-type 'Microsoft.KeyVault/vaults' --query '[0].name' --output tsv
$storageId = az resource list --resource-group $ResourceGroupName --resource-type 'Microsoft.Storage/storageAccounts' --query '[0].id' --output tsv
$logicAppName = az resource list --resource-group $ResourceGroupName --resource-type 'Microsoft.Logic/workflows' --query '[0].name' --output tsv

if (@($factoryName, $keyVaultName, $storageId, $logicAppName) | Where-Object { [string]::IsNullOrWhiteSpace($_) }) {
    throw "Could not discover exactly one ADF, Key Vault, Storage account, and Logic App in $ResourceGroupName."
}

try {
    $parameters = Get-Content -Raw -LiteralPath $baseParameterFile | ConvertFrom-Json
    $keyVaultUrl = "https://$keyVaultName.vault.azure.net/"
    $parameters.parameters.factoryName.value = $factoryName
    $parameters.parameters.ls_keyvault_properties_parameters_baseUrl_defaultValue.value = $keyVaultUrl
    $parameters.parameters.ls_adls_kv_properties_parameters_keyVaultUrl_defaultValue.value = $keyVaultUrl
    $parameters.parameters.ls_sql_kv_properties_parameters_keyVaultUrl_defaultValue.value = $keyVaultUrl
    $parameters.parameters.tr_event_sales_properties_typeProperties_scope.value = $storageId

    $parameterFile = Join-Path ([IO.Path]::GetTempPath()) "novamart-adf-$([guid]::NewGuid().ToString('N')).parameters.json"
    [IO.File]::WriteAllText($parameterFile, ($parameters | ConvertTo-Json -Depth 30), [Text.UTF8Encoding]::new($false))

    $operation = if ($WhatIf) { 'what-if' } else { 'create' }
    $deploymentName = "novamart-adf-$Environment-$(Get-Date -Format yyyyMMddHHmmss)"
    az deployment group $operation `
        --resource-group $ResourceGroupName `
        --name $deploymentName `
        --template-file $templateFile `
        --parameters "@$parameterFile" `
        --output none

    if ($LASTEXITCODE -ne 0) {
        throw "ADF $operation failed."
    }

    if ($WhatIf) {
        Write-Host "ADF $($Environment.ToUpperInvariant()) What-If PASSED. No resources were changed." -ForegroundColor Green
        return
    }

    $triggerResourceId = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Logic/workflows/$logicAppName/triggers/manual"
    $callback = az rest `
        --method post `
        --uri "https://management.azure.com${triggerResourceId}/listCallbackUrl?api-version=2016-06-01" `
        --query value `
        --output tsv
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($callback)) {
        throw 'Could not retrieve the Logic App callback URL.'
    }

    $globalParameterPayload = @{
        properties = @{
            globalParameters = @{
                environment = @{ type = 'String'; value = $Environment.ToUpperInvariant() }
                logicAppCallbackUrl = @{ type = 'String'; value = $callback }
            }
        }
    }
    $globalParameterFile = Join-Path ([IO.Path]::GetTempPath()) "novamart-adf-$([guid]::NewGuid().ToString('N')).global-parameters.json"
    [IO.File]::WriteAllText($globalParameterFile, ($globalParameterPayload | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))

    $factoryResourceId = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.DataFactory/factories/$factoryName"
    az rest `
        --method patch `
        --uri "https://management.azure.com${factoryResourceId}?api-version=2018-06-01" `
        --body "@$globalParameterFile" `
        --output none
    if ($LASTEXITCODE -ne 0) {
        throw 'ADF global-parameter update failed.'
    }

    $resourceSegments = [ordered]@{
        linkedServices = 3
        datasets = 3
        dataflows = 1
        pipelines = 6
        triggers = 2
    }
    foreach ($segment in $resourceSegments.Keys) {
        $response = az rest --method get --uri "https://management.azure.com${factoryResourceId}/${segment}?api-version=2018-06-01" --output json | ConvertFrom-Json
        $actualCount = @($response.value).Count
        if ($actualCount -ne $resourceSegments[$segment]) {
            throw "ADF verification failed for $segment. Expected $($resourceSegments[$segment]), found $actualCount."
        }
        Write-Host "  $segment`: $actualCount"
    }

    $triggerResponse = az rest --method get --uri "https://management.azure.com${factoryResourceId}/triggers?api-version=2018-06-01" --output json | ConvertFrom-Json
    $startedTriggers = @($triggerResponse.value | Where-Object { $_.properties.runtimeState -eq 'Started' })
    if ($startedTriggers.Count -gt 0) {
        throw "Triggers must remain stopped for testing: $($startedTriggers.name -join ', ')"
    }

    Write-Host "ADF $($Environment.ToUpperInvariant()) deployment PASSED for $factoryName. Triggers remain stopped." -ForegroundColor Green
}
finally {
    $callback = $null
    if ($parameterFile -and (Test-Path -LiteralPath $parameterFile)) {
        Remove-Item -LiteralPath $parameterFile -Force
    }
    if ($globalParameterFile -and (Test-Path -LiteralPath $globalParameterFile)) {
        Remove-Item -LiteralPath $globalParameterFile -Force
    }
}
