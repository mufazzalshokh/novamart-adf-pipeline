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
    'adf/pipeline/pl_master_daily.json',
    'adf/dataflow/df_scd_customer.json',
    'adf/trigger/tr_schedule_daily.json',
    'adf/trigger/tr_event_sales.json',
    'azure-pipelines.yml',
    'infra/main.bicep',
    'infra/platform.bicep',
    'scripts/Deploy-AdfArtifacts.ps1',
    'scripts/Invoke-AdfPipeline.ps1',
    'scripts/Get-AdfRunDiagnostics.ps1',
    'scripts/Test-NovaMartData.ps1',
    'sql/01_create_tables.sql',
    'sql/02_create_logging.sql',
    'sql/03_create_procedures.sql',
    'sql/06_acceptance_assertions.sql',
    'sql/05_data_summary.sql',
    'sql/04_validation_queries.sql'
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

$schemaSql = Get-Content -Raw -LiteralPath (Join-Path $repositoryRoot 'sql/01_create_tables.sql')
$filteredIndexPosition = $schemaSql.IndexOf('CREATE UNIQUE INDEX UX_DimCustomer_Current', [StringComparison]::OrdinalIgnoreCase)
foreach ($requiredSetting in @(
    'SET ANSI_NULLS ON',
    'SET ANSI_PADDING ON',
    'SET ANSI_WARNINGS ON',
    'SET ARITHABORT ON',
    'SET CONCAT_NULL_YIELDS_NULL ON',
    'SET QUOTED_IDENTIFIER ON',
    'SET NUMERIC_ROUNDABORT OFF'
)) {
    $settingPosition = $schemaSql.IndexOf($requiredSetting, [StringComparison]::OrdinalIgnoreCase)
    if ($settingPosition -lt 0 -or $settingPosition -gt $filteredIndexPosition) {
        $errors.Add("$requiredSetting must appear before the filtered index in sql/01_create_tables.sql")
    }
}

$loggingSql = Get-Content -Raw -LiteralPath (Join-Path $repositoryRoot 'sql/02_create_logging.sql')
if ($loggingSql -match '(?i)(you@yourdomain\.com|data-oncall@novamart\.example\.com)') {
    $errors.Add('sql/02_create_logging.sql must not seed fake active notification recipients.')
}

$masterPipelineRaw = Get-Content -Raw -LiteralPath (Join-Path $repositoryRoot 'adf/pipeline/pl_master_daily.json')
if ($masterPipelineRaw -match '"activity"\s*:\s*"Load Reference Dimensions"[^\]]*"Completed"') {
    $errors.Add('pl_master_daily must not continue to sales after the dimension pipeline fails.')
}

$salesPipelineRaw = Get-Content -Raw -LiteralPath (Join-Path $repositoryRoot 'adf/pipeline/pl_sales_ingest_daily.json')
foreach ($failureActivity in @('Fail Metadata Discovery', 'Fail Watermark Lookup', 'Fail Sales Batch')) {
    if ($salesPipelineRaw -notmatch [regex]::Escape('"name": "' + $failureActivity + '"')) {
        $errors.Add("pl_sales_ingest_daily must propagate failures through activity '$failureActivity'.")
    }
}

$dimensionPipelineRaw = Get-Content -Raw -LiteralPath (Join-Path $repositoryRoot 'adf/pipeline/pl_dimensions_load.json')
if ($dimensionPipelineRaw -notmatch '"collectionReference"\s*:\s*"\$\[''products''\]"' -or
    $dimensionPipelineRaw -match '"path"\s*:\s*"\$\[''(sku|productName|category|listPrice|attributes)''\]') {
    $errors.Add('Product mappings inside the products collection must use array-element-relative JSON paths.')
}

$pipelineRunnerRaw = Get-Content -Raw -LiteralPath (Join-Path $repositoryRoot 'scripts/Invoke-AdfPipeline.ps1')
if ($pipelineRunnerRaw -match '@\{\s*parameters\s*=\s*\$Parameters\s*\}' -or
    $pipelineRunnerRaw -notmatch '\$request\s*=\s*\$Parameters') {
    $errors.Add('Invoke-AdfPipeline.ps1 must send createRun parameters at the JSON root.')
}

$foundationHelperRaw = Get-Content -Raw -LiteralPath (Join-Path $repositoryRoot 'scripts/Deploy-Foundation.ps1')
if ($foundationHelperRaw -match 'Write-Host[^\r\n]*\$callback') {
    $errors.Add('Deploy-Foundation.ps1 must never print the Logic App callback URL.')
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
