# Design note

## Architecture and conventions

NovaMart uses ADLS Gen2 as the immutable landing boundary, Azure Data Factory for orchestration and transformation, and Azure SQL Database for facts, dimensions, and operational control data. Key Vault owns both connection strings. ADF's system-assigned identity receives Key Vault Secrets User and Storage Blob Data Contributor. DEV is Git-linked; PROD is publish-only and accepts generated ARM through Azure DevOps.

Names follow `pl_<area>_<action>`, `df_<action>`, `ds_<type>_<generic>`, `ls_<service>`, and `tr_<type>_<pipeline>`. Pipelines have requirement/area annotations. Copy activities expose source/sink/run user properties. Global parameters identify the environment and carry the deployment-specific Logic App callback URL.

## Metadata-driven sales ingestion

`pl_sales_ingest_daily` lists sales `childItems`, reads `dbo.LoadWatermark`, and filters correctly named CSVs. A schedule run selects filename dates strictly later than the watermark. An event run selects the filename from `@triggerBody().fileName`; downstream idempotency makes replay safe.

Each item runs `pl_sales_load_file`, giving every file an independent audit row and failure boundary. The child:

1. Calls `dbo.LogPipelineStart`, stores `RunSeqNo`, and captures blob `lastModified`.
2. Deletes only rows with that `SourceFileName`; retrying a day never truncates another day.
3. Copies to `dbo.FactSales`, adding `SourceFileName`, `PipelineRunId`, and `RunSeqNo`.
4. Skips incompatible rows, writes Copy diagnostics to `adf-copy-logs`, and records skipped counts in `dbo.LoadingError`. A genuine Copy failure logs the activity error and invokes notification.
5. Calls `dbo.LogPipelineEnd` with Copy `rowsRead` and `rowsCopied`.

After all children, the parent reads `MAX(OrderTimestamp)` and calls `dbo.UpdateWatermark`. The next schedule run selects no files. A unique `OrderID` index is the final duplicate guard.

## Dimensions and history

`pl_dimensions_load` uses repeatable SQL upserts. Product Copy selects the `products` JSON collection and maps `attributes.brand`; store Copy has an explicit five-column mapping.

`df_scd_customer` performs typed snapshot ingestion into `StgCustomer`. The next activity calls `dbo.ApplyCustomerSCD2`, which compares the snapshot to current versions and atomically expires changed rows before inserting changed/new versions; unchanged rows are untouched. Keeping both writes in one SQL transaction avoids partial SCD state if a second data-flow sink fails. A filtered unique index guarantees one current version per `CustomerID`, and effective time is parameterized for deterministic backfills.

## Reliability, security, and operations

The malformed sample is treated as a data-quality event: compatible rows load, the bad row is observable, and good files continue. Infrastructure/Copy failures use explicit failure branches, persist the message, and call `pl_notify_failure`, which queries the active on-call list and POSTs the required contract per address.

ADF diagnostics use resource-specific Log Analytics tables. A scheduled-query alert on `ADFPipelineRun` independently notifies an action group, protecting against failures before SQL or the notification child can run.

Daily schedule suits normal operation; BlobCreated supplies low latency. A Tumbling Window trigger fits regulated backfills or strict interval dependency/retry semantics: parameterize `windowStart/windowEnd`, filter business dates to the closed interval, and use rerun-from-failed-window. It is not active beside daily/event triggers to avoid duplicate orchestration.

## Assumptions

- Landing preserves the supplied `source_data/` hierarchy.
- Filename dates drive discovery; `OrderTimestamp` drives the persisted watermark.
- `OrderID` is globally unique. History-aware reporting joins the customer key where order time is within `[EffectiveFrom, EffectiveTo)`.
- Exercise SQL access uses TLS plus the Azure-services firewall rule. Production should use managed private endpoints and managed-identity SQL authentication.
- Office 365 API authorization is a one-time human OAuth consent step.
