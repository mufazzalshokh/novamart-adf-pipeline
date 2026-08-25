/* ============================================================================
   NovaMart Data Platform � Logging, control & notification objects
   Run this SECOND. Implements the audit-logging pattern taught in the course
   (LogPipelineStart / LogPipelineEnd returning a RunSeqNo) plus the metadata,
   error and email-recipient tables used by the orchestration scenarios.
   ============================================================================ */

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;
GO

/* ---------- Pipeline execution log (one row per run) ---------- */
IF OBJECT_ID('dbo.PipelineExecution') IS NULL
CREATE TABLE dbo.PipelineExecution (
    RunSeqNo       INT IDENTITY(1,1) PRIMARY KEY,
    PipelineName   NVARCHAR(200),
    PipelineRunId  NVARCHAR(50),
    [Status]       NVARCHAR(20),        -- Started / Success / Failure
    RowsRead       BIGINT NULL,
    RowsCopied     BIGINT NULL,
    FilesRead      INT NULL,
    Comments       NVARCHAR(500) NULL,
    StartTime      DATETIME2 DEFAULT SYSUTCDATETIME(),
    EndTime        DATETIME2 NULL
);
GO

/* ---------- File metadata captured by Get Metadata activity ---------- */
IF OBJECT_ID('dbo.FileMetadata') IS NULL
CREATE TABLE dbo.FileMetadata (
    FileMetadataID INT IDENTITY(1,1) PRIMARY KEY,
    FileName       NVARCHAR(260),
    ModifiedAt     DATETIME2,
    UpdatedAt      DATETIME2 DEFAULT SYSUTCDATETIME()
);
GO

/* ---------- Error capture for rejected rows / failed activities ---------- */
IF OBJECT_ID('dbo.LoadingError') IS NULL
CREATE TABLE dbo.LoadingError (
    ErrorID       INT IDENTITY(1,1) PRIMARY KEY,
    PipelineName  NVARCHAR(200),
    PipelineRunId NVARCHAR(50),
    ActivityName  NVARCHAR(200),
    ErrorMessage  NVARCHAR(MAX),
    LoggedAt      DATETIME2 DEFAULT SYSUTCDATETIME()
);
GO

/* ---------- Watermark table for incremental loads ---------- */
IF OBJECT_ID('dbo.LoadWatermark') IS NULL
CREATE TABLE dbo.LoadWatermark (
    TableName      NVARCHAR(200) PRIMARY KEY,
    WatermarkValue DATETIME2 NOT NULL
);
GO
IF NOT EXISTS (SELECT 1 FROM dbo.LoadWatermark WHERE TableName = 'FactSales')
    INSERT INTO dbo.LoadWatermark (TableName, WatermarkValue) VALUES ('FactSales', '2026-07-19T00:00:00');
GO

/* ---------- Email recipients for the failure-notification pipeline ---------- */
IF OBJECT_ID('dbo.EmailRecipient') IS NULL
CREATE TABLE dbo.EmailRecipient (
    RecipientID  INT IDENTITY(1,1) PRIMARY KEY,
    EmailAddress NVARCHAR(200) NOT NULL,
    Active       BIT DEFAULT 1
);
GO
/* No fake active recipients are seeded. Configure a real address at deployment time. */
