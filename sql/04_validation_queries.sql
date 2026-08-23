/* NovaMart acceptance-test queries. Run after the ADF pipelines complete. */

-- One terminal audit record for every run; no rows should be returned.
SELECT *
FROM dbo.PipelineExecution
WHERE EndTime IS NULL OR [Status] NOT IN ('Success', 'Failure');

-- Idempotency: no order should occur more than once; no rows should be returned.
SELECT OrderID, COUNT(*) AS DuplicateCount
FROM dbo.FactSales
GROUP BY OrderID
HAVING COUNT(*) > 1;

-- Lineage must be complete; no rows should be returned.
SELECT *
FROM dbo.FactSales
WHERE SourceFileName IS NULL OR PipelineRunId IS NULL OR RunSeqNo IS NULL;

-- SCD2 evidence: Customer 12 changes city between the supplied snapshots.
SELECT CustomerID, City, LoyaltyTier, IsCurrent, EffectiveFrom, EffectiveTo
FROM dbo.DimCustomer
WHERE CustomerID IN (12, 13, 25, 26, 39)
ORDER BY CustomerID, EffectiveFrom;

-- Exactly one current version per customer; no rows should be returned.
SELECT CustomerID, SUM(CASE WHEN IsCurrent = 1 THEN 1 ELSE 0 END) AS CurrentVersions
FROM dbo.DimCustomer
GROUP BY CustomerID
HAVING SUM(CASE WHEN IsCurrent = 1 THEN 1 ELSE 0 END) <> 1;

-- The malformed 2026-07-27 row must be observable.
SELECT *
FROM dbo.LoadingError
WHERE ErrorMessage LIKE '%sales_20260727.csv%'
ORDER BY LoggedAt DESC;

-- Incremental state should reach 2026-07-27 after the sample is processed.
SELECT * FROM dbo.LoadWatermark WHERE TableName = 'FactSales';
