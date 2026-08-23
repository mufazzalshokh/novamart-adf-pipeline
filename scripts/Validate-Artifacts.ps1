[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$errors = [System.Collections.Generic.List[string]]::new()

$requiredFiles = @(
    'adf/factory/novamart-adf-dev.json',
    'adf/linkedService/ls_keyvault.json',
    'adf/linkedService/ls_adls_kv.json',
    'adf/linkedService/ls_sql_kv.json',
    'adf/dataset/ds_csv_generic.json',
    'adf/dataset/ds_sql_table.json',
    'adf/pipeline/pl_sales_ingest_daily.json',
    'adf/pipeline/pl_sales_load_file.json',
    'adf/pipeline/pl_dimensions_load.json',
    'adf/pipeline/pl_customer_scd.json',
    'adf/pipeline/pl_notify_failure.json',
    'adf/dataflow/df_scd_customer.json',
    'adf/trigger/tr_schedule_daily.json',
    'adf/trigger/tr_event_sales.json',
    'azure-pipelines.yml',
    'infra/main.bicep',
    'infra/platform.bicep'
)

foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $repositoryRoot $relativePath))) {
        $errors.Add("Missing required artifact: $relativePath")
    }
}

$jsonFiles = Get-ChildItem -LiteralPath (Join-Path $repositoryRoot 'adf') -Filter '*.json' -Recurse
$knownReferences = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

foreach ($jsonFile in $jsonFiles) {
    try {
        $document = Get-Content -Raw -LiteralPath $jsonFile.FullName | ConvertFrom-Json
        if ($document.name) { [void]$knownReferences.Add([string]$document.name) }
    }
    catch {
        $errors.Add("Invalid JSON: $($jsonFile.FullName) - $($_.Exception.Message)")
    }
}

foreach ($jsonFile in $jsonFiles) {
    $raw = Get-Content -Raw -LiteralPath $jsonFile.FullName
    [regex]::Matches($raw, '"referenceName"\s*:\s*"([^"]+)"') | ForEach-Object {
        $reference = $_.Groups[1].Value
        if (-not $knownReferences.Contains($reference)) {
            $errors.Add("Unresolved reference '$reference' in $($jsonFile.FullName)")
        }
    }

    if ($raw -match '(?i)(AccountKey|Password)\s*=\s*[^@{]') {
        $errors.Add("Possible plaintext secret in $($jsonFile.FullName)")
    }
}

$pipelineFiles = Get-ChildItem -LiteralPath (Join-Path $repositoryRoot 'adf/pipeline') -Filter '*.json'
foreach ($pipelineFile in $pipelineFiles) {
    $pipeline = Get-Content -Raw -LiteralPath $pipelineFile.FullName | ConvertFrom-Json
    $topLevelNames = @($pipeline.properties.activities | ForEach-Object name)
    $duplicates = $topLevelNames | Group-Object | Where-Object Count -gt 1
    foreach ($duplicate in $duplicates) {
        $errors.Add("Duplicate top-level activity '$($duplicate.Name)' in $($pipelineFile.Name)")
    }
}

$salesFolder = Join-Path $repositoryRoot 'source_data/partner_drops/daily_sales'
$malformedRows = 0
Get-ChildItem -LiteralPath $salesFolder -Filter 'sales_*.csv' | ForEach-Object {
    $lines = Get-Content -LiteralPath $_.FullName
    if ($lines.Count -lt 2) { $errors.Add("Sales file is empty: $($_.Name)"); return }
    $expectedColumns = ($lines[0] -split ',').Count
    foreach ($line in $lines | Select-Object -Skip 1) {
        if (($line -split ',').Count -ne $expectedColumns) { $malformedRows++ }
    }
}

if ($malformedRows -lt 1) {
    $errors.Add('The test fixture no longer contains a malformed sales row; NMDP-107 cannot be demonstrated.')
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "Validated $($jsonFiles.Count) ADF JSON artifacts."
Write-Host "All cross-references resolve; required files exist; no obvious plaintext ADF credential was found."
Write-Host "Sample fixture check found $malformedRows deliberately malformed sales row(s)."
