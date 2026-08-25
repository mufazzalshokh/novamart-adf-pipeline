# NovaMart Azure Data Factory Data Platform

Production-oriented implementation of the [NovaMart Azure Data Factory assignment](NovaMart_ADF_Project.md). The repository contains the complete factory source, Azure infrastructure, database objects, monitoring query, CI/CD pipeline, sample feeds, automated checks, and an evidence checklist.

## What is implemented

- Key Vault-backed ADLS and Azure SQL linked services; no connection credential is committed.
- Reusable parameterized CSV and SQL table datasets.
- Metadata-driven sales discovery (`Get Metadata` → `Filter` → `ForEach`) with filename-date watermarking.
- Per-file idempotency, audit `RunSeqNo`, lineage columns, Copy row counts, malformed-row logs, and failure notification.
- Product JSON flattening, explicit store mapping, and customer SCD Type 2 Mapping Data Flow.
- Reusable recipient-driven Logic App notification child pipeline.
- Daily schedule and BlobCreated sales triggers.
- DEV/PROD Bicep infrastructure, diagnostics, KQL, Azure Monitor alert, and Azure DevOps ARM promotion.

## Repository map

| Path | Purpose |
|---|---|
| `adf/` | Git-mode ADF source: services, datasets, pipelines, data flow, triggers |
| `infra/` | Subscription-level Bicep for isolated DEV and PROD platforms |
| `sql/` | Schema, control objects, procedures, acceptance queries |
| `source_data/` | Supplied one-week fixture |
| `scripts/` | Validation, secure deployment, run diagnostics, and live data assertions |
| `monitoring/` | Failed-pipeline KQL |
| `docs/` | Design, runbook, traceability matrix, evidence checklist |
| `azure-pipelines.yml` | Official ADF validation/export and incremental PROD deployment |

## Validated DEV results

- 16 products and 8 stores.
- 70 customer history rows, 65 current customers, and five demonstrated SCD2 changes.
- 412 valid sales facts from eight files, with one malformed row skipped and logged.
- An unchanged second sales run, proving watermark and file-level idempotency.
- Successful Gmail failure notification, Log Analytics ingestion, and an enabled Azure Monitor alert.

ADF triggers remain stopped by default. Production deployment is approval-gated in Azure DevOps, and trigger activation requires the explicit `startTriggers=true` variable.

## Start here

1. Run `pwsh ./scripts/Validate-Artifacts.ps1`.
2. Follow [Deployment and test runbook](docs/DEPLOYMENT.md).
3. Read the [design note](docs/DESIGN.md) and [requirement matrix](docs/REQUIREMENTS.md).
4. Capture live proof using [the evidence checklist](docs/EVIDENCE.md).

The code is deployable without changing pipeline logic. A live deployment requires an Azure subscription, Azure DevOps service connection, real alert address, runtime SQL credentials, and one-time Gmail connector authorization.
