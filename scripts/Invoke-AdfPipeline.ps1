[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $ResourceGroupName,

    [Parameter(Mandatory)]
    [string] $PipelineName,

    [hashtable] $Parameters = @{},

    [ValidateRange(1, 180)]
    [int] $TimeoutMinutes = 30
)

$ErrorActionPreference = 'Stop'
$requestFile = $null

function Test-EquivalentParameterValue {
    param(
        [AllowNull()] $Expected,
        [AllowNull()] $Actual
    )

    if ($null -eq $Expected -or $null -eq $Actual) {
        return $null -eq $Expected -and $null -eq $Actual
    }

    $expectedText = [string]$Expected
    $actualText = [string]$Actual
    $expectedDate = [DateTimeOffset]::MinValue
    $actualDate = [DateTimeOffset]::MinValue
    $isExpectedDate = [DateTimeOffset]::TryParse(
        $expectedText,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AssumeUniversal,
        [ref]$expectedDate
    )
    $isActualDate = [DateTimeOffset]::TryParse(
        $actualText,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AssumeUniversal,
        [ref]$actualDate
    )
    if ($isExpectedDate -and $isActualDate -and $expectedText -match '^\d{4}-\d{2}-\d{2}T') {
        return $expectedDate.UtcDateTime -eq $actualDate.UtcDateTime
    }

    return [string]::Equals($expectedText, $actualText, [StringComparison]::Ordinal)
}

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

try {
    $requestFile = Join-Path ([IO.Path]::GetTempPath()) "novamart-adf-run-$([guid]::NewGuid().ToString('N')).json"
    # ADF's createRun REST API requires pipeline parameters at the JSON root.
    $request = $Parameters
    [IO.File]::WriteAllText($requestFile, ($request | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))

    $runId = az rest `
        --method post `
        --uri "https://management.azure.com${factoryResourceId}/pipelines/$PipelineName/createRun?api-version=2018-06-01" `
        --body "@$requestFile" `
        --query runId `
        --output tsv
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($runId)) {
        throw "Could not start pipeline $PipelineName."
    }

    Write-Host "Started $PipelineName. Run ID: $runId"
    $deadline = [DateTime]::UtcNow.AddMinutes($TimeoutMinutes)
    $consecutivePollFailures = 0
    $parametersVerified = $Parameters.Count -eq 0
    do {
        Start-Sleep -Seconds 15
        $runJson = az rest `
            --method get `
            --uri "https://management.azure.com${factoryResourceId}/pipelineruns/${runId}?api-version=2018-06-01" `
            --output json 2>$null
        if ($LASTEXITCODE -ne 0) {
            $consecutivePollFailures++
            if ($consecutivePollFailures -ge 5) {
                throw "Could not read pipeline run $runId after 5 consecutive attempts. The Azure run continues independently; rerun Get-AdfRunDiagnostics.ps1 with this run ID when connectivity returns."
            }
            Write-Warning "Azure status polling temporarily failed ($consecutivePollFailures/5); retrying without restarting the pipeline."
            continue
        }
        $consecutivePollFailures = 0
        $run = $runJson | ConvertFrom-Json
        if (-not $parametersVerified) {
            foreach ($parameterName in $Parameters.Keys) {
                $actualProperty = $run.parameters.PSObject.Properties[$parameterName]
                if (-not $actualProperty -or -not (Test-EquivalentParameterValue -Expected $Parameters[$parameterName] -Actual $actualProperty.Value)) {
                    $actualValue = if ($actualProperty) { $actualProperty.Value } else { '<missing>' }
                    throw "ADF parameter verification failed for '$parameterName'. Requested '$($Parameters[$parameterName])', Azure received '$actualValue'. Run ID: $runId"
                }
            }
            $parametersVerified = $true
            Write-Host "  Azure accepted $($Parameters.Count) supplied pipeline parameter(s)."
        }
        Write-Host "  $([DateTime]::UtcNow.ToString('HH:mm:ss')) UTC - $($run.status)"
    }
    while ($run.status -in @('Queued', 'InProgress', 'Canceling') -and [DateTime]::UtcNow -lt $deadline)

    if ($run.status -in @('Queued', 'InProgress', 'Canceling')) {
        throw "Pipeline $PipelineName exceeded the $TimeoutMinutes-minute wait limit. Run ID: $runId"
    }
    if ($run.status -ne 'Succeeded') {
        & (Join-Path $PSScriptRoot 'Get-AdfRunDiagnostics.ps1') `
            -ResourceGroupName $ResourceGroupName `
            -RunId $runId
        throw "Pipeline $PipelineName finished with status $($run.status). Run ID: $runId. Message: $($run.message)"
    }

    Write-Host "Pipeline $PipelineName PASSED. Run ID: $runId" -ForegroundColor Green
}
finally {
    if ($requestFile -and (Test-Path -LiteralPath $requestFile)) {
        Remove-Item -LiteralPath $requestFile -Force
    }
}
