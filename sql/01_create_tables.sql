/* ============================================================================
   NovaMart Data Platform � Azure SQL Database schema
   Run this FIRST against your Azure SQL Database (e.g. sqldb-novamart-dev).
   Creates the staging + dimensional + fact tables the pipelines load into.
   ============================================================================ */

/* Required by SQL Server for filtered indexes and deterministic DDL. */
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
GO

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

/* Snapshot staging is truncated and reloaded by df_scd_customer. */
IF OBJECT_ID('dbo.StgCustomer') IS NULL
CREATE TABLE dbo.StgCustomer (
    CustomerID    INT           NOT NULL,
    FirstName     NVARCHAR(60),
    LastName      NVARCHAR(60),
    Email         NVARCHAR(120),
    City          NVARCHAR(80),
    LoyaltyTier   NVARCHAR(20)
);
GO

/* Idempotency and SCD integrity constraints.  These are safe to rerun. */
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.FactSales') AND name = 'UX_FactSales_OrderID'
)
    CREATE UNIQUE INDEX UX_FactSales_OrderID ON dbo.FactSales (OrderID);
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.DimCustomer') AND name = 'UX_DimCustomer_Current'
)
    CREATE UNIQUE INDEX UX_DimCustomer_Current
        ON dbo.DimCustomer (CustomerID)
        WHERE IsCurrent = 1;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.DimCustomer') AND name = 'IX_DimCustomer_BusinessDate'
)
    CREATE INDEX IX_DimCustomer_BusinessDate
        ON dbo.DimCustomer (CustomerID, EffectiveFrom, EffectiveTo);
GO
