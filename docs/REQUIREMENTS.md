# Definition-of-done matrix

| Story | Implementation | Live evidence |
|---|---|---|
| NMDP-101 | Key Vault-secret linked services; generic CSV/SQL datasets; `/adf` Git root | Connection tests and feature commit |
| NMDP-102 | Parent list/filter/iterate; child Copy lineage; file delete + unique index | First/retry counts and lineage |
| NMDP-103 | Start Lookup, Set Variable, Copy-output end procedure | Complete audit rows |
| NMDP-104 | Product collection/brand mapping and explicit store mapping | 16 products, 8 stores |
| NMDP-105 | Watermark Lookup/filter/update | 412 first run; unchanged retry |
| NMDP-106 | Mapping Data Flow typed snapshot load + transactional SCD2 apply | 70 total, 65 current, history rows |
| NMDP-107 | Skip diagnostics, checked branch, explicit Copy failure logging | Malformed error and good rows |
| NMDP-108 | HTTP Logic App and recipient-driven child notification | Forced-failure email |
| NMDP-109 | Daily and BlobCreated triggers; Tumbling Window documented | Schedule/event runs |
| NMDP-110 | Annotations, user properties, diagnostics, KQL, alert/action group | Monitor/KQL/fired alert |
| NMDP-111 | Bicep DEV/PROD; `adf_publish` ARM CI/CD with overrides | Release and PROD change |

All repository artifacts are implemented. “Live evidence” requires the target tenant and follows `DEPLOYMENT.md`.
