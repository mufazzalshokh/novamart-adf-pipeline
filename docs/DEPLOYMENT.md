# Deployment and test runbook

## 1. Prerequisites

- Azure Owner, or Contributor plus User Access Administrator.
- Azure CLI, PowerShell 7, and `sqlcmd`.
- Azure DevOps project/repo, ARM service connection, environments, and variable groups.
- A real alert address and Microsoft 365 account for Logic App connector consent.

Never place passwords, callback URLs, or connection strings in Git.

## 2. Validate and provision

```powershell
pwsh ./scripts/Validate-Artifacts.ps1
az login
$sqlPassword = Read-Host 'SQL administrator password' -AsSecureString
pwsh ./scripts/Deploy-Foundation.ps1 `
  -SubscriptionId '<subscription-guid>' `
  -SqlAdministratorLogin 'novamartadmin' `
  -SqlAdministratorPassword $sqlPassword `
  -AlertEmailAddress 'real-oncall@company.com' `
  -NamePrefix 'youruniqueid' `
  -Location 'eastus'
```

This creates isolated DEV and PROD groups. Record each factory name, Key Vault URL, storage resource ID, and Logic App callback URL. The script uploads the supplied fixture.

For each environment, open `office365-<environment>` → **Edit API connection → Authorize → Save**. OAuth consent cannot be automated.

## 3. Initialize Azure SQL

Temporarily allow your client IP, then run against each database:

```powershell
sqlcmd -S 'tcp:<server>.database.windows.net,1433' -d sqldb-novamart -U novamartadmin -P '<runtime-secret>' -i sql/01_create_tables.sql
sqlcmd -S 'tcp:<server>.database.windows.net,1433' -d sqldb-novamart -U novamartadmin -P '<runtime-secret>' -i sql/02_create_logging.sql
sqlcmd -S 'tcp:<server>.database.windows.net,1433' -d sqldb-novamart -U novamartadmin -P '<runtime-secret>' -i sql/03_create_procedures.sql
```

Replace placeholder `dbo.EmailRecipient` rows, then remove the client firewall rule.

## 4. Connect DEV to Azure DevOps Git

Configure the DEV factory with Azure DevOps Git, collaboration branch `main`, publish branch `adf_publish`, and root `/adf`. Import existing resources.

The JSON under `adf/factory/` must match the actual factory. If needed, rename the file/top-level `name` and set `location` before import. Set:

- Key Vault URL in `ls_keyvault.baseUrl`, `ls_adls_kv.keyVaultUrl`, and `ls_sql_kv.keyVaultUrl`.
- Factory `logicAppCallbackUrl` to the DEV callback URL.
- `tr_event_sales.typeProperties.scope` to the DEV storage resource ID.

Validate, commit via a feature branch/PR, and **Publish**. Confirm the two generated ARM files appear in `adf_publish`.

## 5. Configure Azure DevOps release

Create `novamart-dev` and `novamart-prod` variable groups:

| Variable | Value |
|---|---|
| `azureSubscriptionId` | Subscription GUID |
| `azureLocation` | e.g. `eastus` |
| `resourceGroupName` | Exact environment resource group |
| `dataFactoryName` | Exact Bicep output |
| `adfPublishFolder` | Folder containing generated ARM, normally DEV factory name |
| `keyVaultUrl` | `https://<vault>.vault.azure.net/` |
| `logicAppCallbackUrl` | Callback URL; mark secret |
| `storageAccountResourceId` | Full ARM ID |

Create service connection `sc-novamart-azure` (or edit YAML) and add PROD approval. The pipeline validates, stops triggers, deploys ARM incrementally, then starts triggers. PROD remains non-Git.

ADF parameter names depend on the actual factory. Compare the first generated parameters file to YAML `overrideParameters` and adjust names once if ADF generated different identifiers.

## 6. Functional acceptance test

1. Keep triggers stopped.
2. Run `pl_dimensions_load`: expect 16 products and 8 stores.
3. Run `pl_customer_scd` with `customers_20260720.csv` / `2026-07-20T00:00:00Z`: expect 60 current rows.
4. Run it with `customers_20260727.csv` / `2026-07-27T00:00:00Z`: expect 70 total, 65 current, and two versions for customers 12, 13, 25, 26, and 39.
5. Run `pl_sales_ingest_daily` with empty `triggerFileName`: expect 412 compatible facts and one malformed-row error.
6. Run it again: zero selected files and still 412 facts.
7. Run `sql/04_validation_queries.sql`; every “no rows” check must be empty.
8. Force a Copy failure in DEV using a temporary bad sink table. Confirm SQL error logging and email, then revert.
9. Test a short schedule, restore daily 06:00 UTC, then test BlobCreated with a new dated CSV.
10. Run the KQL and confirm the independent alert fired.
11. Publish an annotation change and verify the Azure DevOps release promotes it to PROD.

## 7. Production activation

Verify PROD SQL, secrets, recipients, callback URL, event scope, diagnostics, alert, and Office connector. Run a manual smoke test before enabling triggers and capture `docs/EVIDENCE.md`.
