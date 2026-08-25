/* Diagnostic summary printed before deterministic acceptance assertions. */

SET NOCOUNT ON;

SELECT
    (SELECT COUNT_BIG(*) FROM dbo.DimProduct) AS Products,
    (SELECT COUNT_BIG(*) FROM dbo.DimStore) AS Stores,
    (SELECT COUNT_BIG(*) FROM dbo.StgCustomer) AS StagedCustomers,
    (SELECT COUNT_BIG(*) FROM dbo.DimCustomer) AS CustomerVersions,
    (SELECT COUNT_BIG(*) FROM dbo.DimCustomer WHERE IsCurrent = 1) AS CurrentCustomers,
    (SELECT COUNT_BIG(*) FROM dbo.FactSales) AS SalesFacts,
    (SELECT COUNT_BIG(*) FROM dbo.FileMetadata) AS SalesFiles,
    (SELECT COUNT_BIG(*) FROM dbo.LoadingError WHERE ErrorMessage LIKE '%sales_20260727.csv%') AS MalformedRowLogs,
    (SELECT COUNT_BIG(*) FROM dbo.PipelineExecution WHERE EndTime IS NULL OR [Status] NOT IN ('Success', 'Failure')) AS IncompleteAuditRows,
    (SELECT WatermarkValue FROM dbo.LoadWatermark WHERE TableName = 'FactSales') AS SalesWatermark;

SELECT
    CustomerID,
    COUNT_BIG(*) AS VersionCount,
    SUM(CASE WHEN IsCurrent = 1 THEN 1 ELSE 0 END) AS CurrentVersionCount,
    MIN(EffectiveFrom) AS FirstEffectiveFrom,
    MAX(EffectiveFrom) AS LatestEffectiveFrom
FROM dbo.DimCustomer
GROUP BY CustomerID
HAVING COUNT_BIG(*) <> 1
    OR SUM(CASE WHEN IsCurrent = 1 THEN 1 ELSE 0 END) <> 1
ORDER BY CustomerID;

SELECT CustomerID, City, LoyaltyTier, IsCurrent, EffectiveFrom, EffectiveTo
FROM dbo.DimCustomer
WHERE CustomerID IN (12, 13, 25, 26, 39)
ORDER BY CustomerID, EffectiveFrom;
