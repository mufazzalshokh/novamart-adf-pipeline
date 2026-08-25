[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $ResourceGroupName,

    [string] $DatabaseName = 'sqldb-novamart',

    [string] $SqlAdministratorLogin = 'novamartadmin',

    [Security.SecureString] $SqlAdministratorPassword
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot

foreach ($command in 'az', 'sqlcmd') {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "$command is required."
    }
}

if (-not $SqlAdministratorPassword) {
    $SqlAdministratorPassword = Read-Host "Enter the existing $SqlAdministratorLogin SQL password" -AsSecureString
}

$serverName = az resource list `
    --resource-group $ResourceGroupName `
    --resource-type 'Microsoft.Sql/servers' `
    --query '[0].name' `
    --output tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($serverName)) {
    throw "Could not discover an Azure SQL server in $ResourceGroupName."
}

$credential = [PSCredential]::new($SqlAdministratorLogin, $SqlAdministratorPassword)
$env:SQLCMDPASSWORD = $credential.GetNetworkCredential().Password

try {
    Write-Host 'Current NovaMart data state:' -ForegroundColor Cyan
    sqlcmd `
        -S "$serverName.database.windows.net" `
        -d $DatabaseName `
        -U $SqlAdministratorLogin `
        -N `
        -I `
        -b `
        -i (Join-Path $repositoryRoot 'sql/05_data_summary.sql')
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not read the NovaMart SQL data summary.'
    }

    Write-Host 'Running deterministic assertions:' -ForegroundColor Cyan
    sqlcmd `
        -S "$serverName.database.windows.net" `
        -d $DatabaseName `
        -U $SqlAdministratorLogin `
        -N `
        -I `
        -b `
        -i (Join-Path $repositoryRoot 'sql/06_acceptance_assertions.sql')
    if ($LASTEXITCODE -ne 0) {
        throw 'NovaMart SQL data acceptance FAILED.'
    }
    Write-Host 'NovaMart SQL data acceptance PASSED.' -ForegroundColor Green
}
finally {
    Remove-Item Env:SQLCMDPASSWORD -ErrorAction SilentlyContinue
    $credential = $null
}
