/* NovaMart deterministic data acceptance assertions. Run after both customer
   snapshots and the initial + idempotency sales-ingestion runs complete. */

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF (SELECT COUNT_BIG(*) FROM dbo.DimProduct) <> 16
    THROW 51001, 'Acceptance failed: DimProduct must contain 16 rows.', 1;

IF (SELECT COUNT_BIG(*) FROM dbo.DimStore) <> 8
    THROW 51002, 'Acceptance failed: DimStore must contain 8 rows.', 1;

IF (SELECT COUNT_BIG(*) FROM dbo.DimCustomer) <> 70
    THROW 51003, 'Acceptance failed: DimCustomer must contain 70 historical rows.', 1;

IF (SELECT COUNT_BIG(*) FROM dbo.DimCustomer WHERE IsCurrent = 1) <> 65
    THROW 51004, 'Acceptance failed: DimCustomer must contain 65 current rows.', 1;

IF EXISTS (
    SELECT expected.CustomerID
    FROM (VALUES (12), (13), (25), (26), (39)) AS expected(CustomerID)
    LEFT JOIN dbo.DimCustomer AS customer
      ON customer.CustomerID = expected.CustomerID
    GROUP BY expected.CustomerID
    HAVING COUNT(customer.CustomerSK) <> 2
       OR SUM(CASE WHEN customer.IsCurrent = 1 THEN 1 ELSE 0 END) <> 1
)
    THROW 51005, 'Acceptance failed: each changed customer must have two versions and one current version.', 1;

IF EXISTS (
    SELECT CustomerID
    FROM dbo.DimCustomer
    GROUP BY CustomerID
    HAVING SUM(CASE WHEN IsCurrent = 1 THEN 1 ELSE 0 END) <> 1
)
    THROW 51006, 'Acceptance failed: every customer must have exactly one current version.', 1;

IF (SELECT COUNT_BIG(*) FROM dbo.StgCustomer) <> 65
    THROW 51007, 'Acceptance failed: StgCustomer must contain the 65-row latest snapshot.', 1;

IF (SELECT COUNT_BIG(*) FROM dbo.FactSales) <> 412
    THROW 51008, 'Acceptance failed: FactSales must contain 412 valid rows.', 1;

IF EXISTS (
    SELECT OrderID
    FROM dbo.FactSales
    GROUP BY OrderID
    HAVING COUNT_BIG(*) > 1
)
    THROW 51009, 'Acceptance failed: duplicate FactSales OrderID values exist.', 1;

IF EXISTS (
    SELECT 1
    FROM dbo.FactSales
    WHERE SourceFileName IS NULL OR PipelineRunId IS NULL OR RunSeqNo IS NULL
)
    THROW 51010, 'Acceptance failed: FactSales lineage columns contain NULL.', 1;

IF (SELECT COUNT_BIG(*) FROM dbo.FileMetadata) <> 8
    THROW 51011, 'Acceptance failed: FileMetadata must contain all 8 sales files.', 1;

IF EXISTS (
    SELECT 1
    FROM dbo.PipelineExecution
    WHERE EndTime IS NULL OR [Status] NOT IN ('Success', 'Failure')
)
    THROW 51012, 'Acceptance failed: an audit record is incomplete.', 1;

IF NOT EXISTS (
    SELECT 1
    FROM dbo.LoadingError
    WHERE ErrorMessage LIKE '%sales_20260727.csv%'
      AND ErrorMessage LIKE '%Rejected 1 malformed row%'
)
    THROW 51013, 'Acceptance failed: the malformed sales row was not logged.', 1;

IF NOT EXISTS (
    SELECT 1
    FROM dbo.LoadWatermark
    WHERE TableName = 'FactSales'
      AND WatermarkValue = (SELECT MAX(OrderTimestamp) FROM dbo.FactSales)
      AND CONVERT(date, WatermarkValue) = CONVERT(date, '2026-07-27')
)
    THROW 51014, 'Acceptance failed: FactSales watermark does not match the latest loaded timestamp.', 1;

SELECT
    'PASSED' AS AcceptanceStatus,
    (SELECT COUNT_BIG(*) FROM dbo.DimProduct) AS Products,
    (SELECT COUNT_BIG(*) FROM dbo.DimStore) AS Stores,
    (SELECT COUNT_BIG(*) FROM dbo.DimCustomer) AS CustomerVersions,
    (SELECT COUNT_BIG(*) FROM dbo.DimCustomer WHERE IsCurrent = 1) AS CurrentCustomers,
    (SELECT COUNT_BIG(*) FROM dbo.FactSales) AS SalesFacts,
    (SELECT COUNT_BIG(*) FROM dbo.FileMetadata) AS SalesFiles,
    (SELECT COUNT_BIG(*) FROM dbo.LoadingError WHERE ErrorMessage LIKE '%sales_20260727.csv%') AS MalformedRowLogs,
    (SELECT WatermarkValue FROM dbo.LoadWatermark WHERE TableName = 'FactSales') AS SalesWatermark;
