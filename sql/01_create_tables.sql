/* ============================================================================
   NovaMart Data Platform � Azure SQL Database schema
   Run this FIRST against your Azure SQL Database (e.g. sqldb-novamart-dev).
   Creates the staging + dimensional + fact tables the pipelines load into.
   ============================================================================ */

/* ---------- Reference / dimension tables ---------- */
IF OBJECT_ID('dbo.DimStore') IS NULL
CREATE TABLE dbo.DimStore (
    StoreID     INT          NOT NULL PRIMARY KEY,
    StoreName   NVARCHAR(100) NOT NULL,
    City        NVARCHAR(80),
    [State]     NVARCHAR(10),
    Country     NVARCHAR(10),
    LoadedAt    DATETIME2     DEFAULT SYSUTCDATETIME()
);
GO

IF OBJECT_ID('dbo.DimProduct') IS NULL
CREATE TABLE dbo.DimProduct (
    SKU          NVARCHAR(20)  NOT NULL PRIMARY KEY,
    ProductName  NVARCHAR(150) NOT NULL,
    Category     NVARCHAR(60),
    ListPrice    DECIMAL(10,2),
    Brand        NVARCHAR(60),
    LoadedAt     DATETIME2      DEFAULT SYSUTCDATETIME()
);
GO

/* Customer dimension � target for the Slowly Changing Dimension (SCD) exercise.
   Includes SCD Type 2 tracking columns. */
IF OBJECT_ID('dbo.DimCustomer') IS NULL
CREATE TABLE dbo.DimCustomer (
    CustomerSK    INT IDENTITY(1,1) PRIMARY KEY,   -- surrogate key
    CustomerID    INT           NOT NULL,          -- business key
    FirstName     NVARCHAR(60),
    LastName      NVARCHAR(60),
    Email         NVARCHAR(120),
    City          NVARCHAR(80),
    LoyaltyTier   NVARCHAR(20),
    IsCurrent     BIT           NOT NULL DEFAULT 1,
    EffectiveFrom DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    EffectiveTo   DATETIME2     NULL
);
GO

/* ---------- Fact table (daily sales land here) ---------- */
IF OBJECT_ID('dbo.FactSales') IS NULL
CREATE TABLE dbo.FactSales (
    OrderID        BIGINT       NOT NULL,
    OrderTimestamp DATETIME2     NOT NULL,
    StoreID        INT,
    CustomerID     INT,
    SKU            NVARCHAR(20),
    Quantity       INT,
    UnitPrice      DECIMAL(10,2),
    DiscountPct    INT,
    LineTotal      DECIMAL(12,2),
    -- audit / lineage columns populated by ADF expressions
    SourceFileName NVARCHAR(260),
    PipelineRunId  NVARCHAR(50),
    RunSeqNo       INT,
    LoadedAt       DATETIME2     DEFAULT SYSUTCDATETIME()
);
GO
