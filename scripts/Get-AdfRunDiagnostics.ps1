[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $ResourceGroupName,

    [Parameter(Mandatory)]
    [string] $RunId
)

$ErrorActionPreference = 'Stop'
$requestFile = $null

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI is required.'
}

$subscriptionId = az account show --query id --output tsv
$factoryName = az resource list `
    --resource-group $ResourceGroupName `
    --resource-type 'Microsoft.DataFactory/factories' `
    --query '[0].name' `
    --output tsv

if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($subscriptionId) -or [string]::IsNullOrWhiteSpace($factoryName)) {
    throw 'Could not discover the active subscription and Data Factory.'
}

$factoryResourceId = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.DataFactory/factories/$factoryName"
$run = az rest `
    --method get `
    --uri "https://management.azure.com${factoryResourceId}/pipelineruns/${RunId}?api-version=2018-06-01" `
    --output json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or -not $run) {
    throw "Could not read pipeline run $RunId."
}

try {
    $requestFile = Join-Path ([IO.Path]::GetTempPath()) "novamart-adf-activities-$([guid]::NewGuid().ToString('N')).json"
    $updatedAfter = ([DateTime]$run.runStart).ToUniversalTime().AddMinutes(-5).ToString('o')
    $runEnd = if ($run.runEnd) { ([DateTime]$run.runEnd).ToUniversalTime() } else { [DateTime]::UtcNow }
    $updatedBefore = $runEnd.AddMinutes(5).ToString('o')
    $request = @{ lastUpdatedAfter = $updatedAfter; lastUpdatedBefore = $updatedBefore }
    [IO.File]::WriteAllText($requestFile, ($request | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))

    $result = az rest `
        --method post `
        --uri "https://management.azure.com${factoryResourceId}/pipelineruns/${RunId}/queryActivityruns?api-version=2018-06-01" `
        --body "@$requestFile" `
        --output json | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) {
        throw "Could not query activities for pipeline run $RunId."
    }

    Write-Host "Pipeline: $($run.pipelineName)"
    Write-Host "Run ID:   $RunId"
    Write-Host "Status:   $($run.status)"
    @($result.value) |
        Sort-Object activityRunStart |
        Select-Object `
            @{ Name = 'Activity'; Expression = { $_.activityName } },
            @{ Name = 'Type'; Expression = { $_.activityType } },
            Status,
            @{ Name = 'ErrorCode'; Expression = { $_.error.errorCode } },
            @{ Name = 'Message'; Expression = { $_.error.message } } |
        Format-Table -Wrap -AutoSize
}
finally {
    if ($requestFile -and (Test-Path -LiteralPath $requestFile)) {
        Remove-Item -LiteralPath $requestFile -Force
    }
}
