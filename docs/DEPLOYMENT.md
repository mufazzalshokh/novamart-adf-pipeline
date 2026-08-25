# Deployment and test runbook

## 1. Prerequisites

- Azure Owner, or Contributor plus User Access Administrator.
- Azure CLI, PowerShell 7, and `sqlcmd`.
- Azure DevOps project/repo, ARM service connection, environments, and variable groups.
- A real alert address and Google account for Gmail Logic App connector consent.

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
  -Location 'eastus' `
  -Environments dev `
  -WhatIf

# After reviewing the successful preview, run the actual DEV deployment.
pwsh ./scripts/Deploy-Foundation.ps1 `
  -SubscriptionId '<subscription-guid>' `
  -SqlAdministratorLogin 'novamartadmin' `
  -SqlAdministratorPassword $sqlPassword `
  -AlertEmailAddress 'real-oncall@company.com' `
  -NamePrefix 'youruniqueid' `
  -Location 'eastus' `
  -Environments dev
```

Deploy DEV first and verify it before spending credit on PROD. The command creates the isolated DEV group and uploads the supplied fixture. Record the factory name, Key Vault URL, storage resource ID, and Logic App name. Callback URLs are retrieved internally by deployment automation and must never be printed, committed, or stored in a non-secret variable. Near the CI/CD acceptance test, rerun the command with `-Environments prod` to create PROD.

The first deployment intentionally creates the HTTP workflow without its Gmail send action. For a personal Gmail account, delete the unauthorised placeholder `gmail` connection, open the Logic App designer, temporarily add **Gmail → Send email (V2)**, and create a connection named `gmail` with **Bring your own application**. The Google web OAuth client must allow both `https://global.consent.azure-apim.net/redirect` and the Gmail-specific `https://global.consent.azure-apim.net/redirect/gmail` redirect URI. Google displays a newly created client secret only once, so store it securely outside the repository. Save once so the connection persists, then rerun the deployment with `-EnableGmailAction`; Bicep replaces the temporary action but preserves the OAuth connection. OAuth consent cannot be automated. Keep the Google OAuth client in testing mode and add the sender as a test user.

## 3. Initialize Azure SQL

Temporarily allow your client IP, then run against each database:

Use `SQLCMDPASSWORD` so the password is not exposed in the process command line. Run scripts `01` through `03` with `sqlcmd -N -I -b`; every script is safe to rerun after a partial deployment. No fake notification recipients are seeded. Insert the real on-call address after initialization, then remove the temporary client firewall rule.

## 4. Connect DEV to Azure DevOps Git

Use Azure Repos as the ADF collaboration source and GitHub as the public portfolio mirror. Configure the DEV factory with Azure DevOps Git, collaboration branch `main`, publish branch `adf_publish`, and root `/adf`. Because this repository already contains the validated ADF source, leave **Import existing Data Factory resources to repository** unchecked. Importing live mode can overwrite reviewed JSON and can capture environment-only global-parameter values.

The JSON under `adf/factory/` must match the actual factory. If needed, rename the file/top-level `name` and set `location` before import. Set:

- Key Vault URL in `ls_keyvault.baseUrl`, `ls_adls_kv.keyVaultUrl`, and `ls_sql_kv.keyVaultUrl`.
- Keep factory `logicAppCallbackUrl` as `__SET_BY_DEPLOYMENT__`. Deployment automation retrieves and applies the callback at runtime; never commit the signed callback URL.
- `tr_event_sales.typeProperties.scope` to the DEV storage resource ID.

Validate, commit via a feature branch/PR, and **Publish**. Confirm the generated ARM files appear in `adf_publish`; retain this as ADF Publish evidence. The release pipeline independently validates and exports from `main`, so it does not depend on generated branches containing `azure-pipelines.yml`.

## 5. Configure Azure DevOps release

Create `novamart-dev` and `novamart-prod` variable groups:

| Variable | Value |
|---|---|
| `azureSubscriptionId` | Subscription GUID |
| `azureLocation` | e.g. `eastus` |
| `resourceGroupName` | Exact environment resource group |
| `dataFactoryName` | Exact Bicep output |
| `keyVaultUrl` | `https://<vault>.vault.azure.net/` |
| `logicAppName` | Exact Logic App workflow name; callback is retrieved at runtime |
| `storageAccountResourceId` | Full ARM ID |
| `startTriggers` | `false` until functional testing is complete |

Create service connection `sc-novamart-azure` (or edit YAML), create Azure DevOps environment `novamart-prod`, and add its manual approval check. The `main` pipeline uses Node.js 20 and Microsoft's ADF utility to validate/export source, validates the generated ARM against PROD, stops triggers, deploys incrementally, verifies artifact counts, and starts triggers only when `startTriggers=true`. PROD remains non-Git.

The checked-in ARM parameter definition fixes the expected override names. Treat a generated-name change as a reviewed code change rather than editing a live release.

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

Verify PROD SQL, secrets, recipients, callback URL, event scope, diagnostics, alert, and Gmail connector. Run a manual smoke test before enabling triggers and capture `docs/EVIDENCE.md`.
