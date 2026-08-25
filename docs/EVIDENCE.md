# NovaMart validation evidence

Validated on 25 August 2026. Callback URLs, credentials, OAuth secrets, tokens, subscription identifiers, client IP addresses, and personal email addresses are intentionally excluded.

## Automated and live acceptance results

| Area | Verified result |
|---|---|
| Static validation | Bicep build passed; 18 ADF JSON artifacts passed cross-reference, required-file, fixture, and plaintext-credential checks |
| DEV artifacts | 3 linked services, 3 datasets, 1 mapping data flow, 6 pipelines, and 2 triggers deployed |
| DEV functional test | Dimensions, two customer snapshots, sales ingestion, idempotent rerun, deterministic SQL assertions, failure notification, diagnostics, and alerting passed |
| Azure DevOps release | Run `20260825.4` passed ADF validation/export, ARM validation, the protected PROD approval check, incremental deployment, and artifact-count verification |
| PROD artifacts | 3 linked services, 3 datasets, 1 mapping data flow, 6 pipelines, and 2 triggers deployed |
| PROD notification | Gmail BYOA connection reported `Enabled / Connected`; controlled Logic App notification run succeeded |
| PROD dimensions | `pl_dimensions_load` succeeded; assertions confirmed 16 products and 8 stores |
| PROD customer SCD2 | Both dated `pl_customer_scd` runs succeeded; assertions confirmed 70 historical rows, 65 current rows, and five changed customers with two versions |
| PROD sales | Initial and replayed `pl_sales_ingest_daily` runs succeeded; assertions confirmed 412 facts, 8 processed files, one deliberately malformed-row log, and no incomplete audit rows |
| Security state | Signed callback is injected only at deployment time; secrets are absent from Git; temporary client-IP SQL firewall rules were removed |
| Cost-safe handoff | DEV and PROD triggers remain stopped after acceptance; `startTriggers` is the reviewed CI/CD activation switch |

## Recorded ADF run identifiers

- PROD dimensions: `7ee52b60-3abc-44c7-b4f9-b0550eea6939`
- PROD customer snapshot 2026-07-20: `c39e2941-d483-4b5f-9ae6-bc36a1b8b392`
- PROD customer snapshot 2026-07-27: `2e238f56-6a11-4baf-89ae-fd1b7a0c6bb5`
- PROD initial sales ingestion: `951c97c2-3d06-4b58-84ed-357f37aec6e7`
- PROD idempotent sales replay: `9968ffce-307f-45fc-9ebc-bd47c77429d4`

## Optional screenshot pack

Store screenshots under `evidence/` only after redacting secrets and personal data:

- ADF Git configuration and feature branch
- Linked-service connection tests
- Initial and replayed sales runs
- SQL audit, lineage, malformed-row, and SCD2 results
- Failure email and Logic App run status
- Log Analytics query and Azure Monitor alert
- Successful Azure DevOps protected PROD release
- Public GitHub repository

The deterministic proof is reproducible with `scripts/Validate-Artifacts.ps1`, `scripts/Invoke-AdfPipeline.ps1`, `scripts/Get-AdfRunDiagnostics.ps1`, `scripts/Test-NovaMartData.ps1`, and `sql/04_validation_queries.sql`.
