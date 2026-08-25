/* ============================================================================
   NovaMart Data Platform � Stored procedures
   Run this THIRD. These are called from ADF Stored Procedure / Lookup activities.
   ============================================================================ */

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;
GO

/* Start a run: insert a "Started" row and return the new RunSeqNo.
   Call from a Lookup activity ("First row only") and read firstRow.RunSeqNo. */
CREATE OR ALTER PROCEDURE dbo.LogPipelineStart
    @PipelineName  NVARCHAR(200),
    @PipelineRunId NVARCHAR(50),
    @Comments      NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.PipelineExecution (PipelineName, PipelineRunId, [Status], Comments, StartTime)
    VALUES (@PipelineName, @PipelineRunId, 'Started', @Comments, SYSUTCDATETIME());
    SELECT CAST(SCOPE_IDENTITY() AS INT) AS RunSeqNo;
END;
GO

/* Close out a run with final status + row counts. */
CREATE OR ALTER PROCEDURE dbo.LogPipelineEnd
    @RunSeqNo   INT,
    @Status     NVARCHAR(20),
    @RowsRead   BIGINT = NULL,
    @RowsCopied BIGINT = NULL,
    @FilesRead  INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.PipelineExecution
       SET [Status] = @Status,
           RowsRead = @RowsRead,
           RowsCopied = @RowsCopied,
           FilesRead = @FilesRead,
           EndTime = SYSUTCDATETIME()
     WHERE RunSeqNo = @RunSeqNo;
END;
GO

/* Insert file metadata captured from a Get Metadata activity. */
CREATE OR ALTER PROCEDURE dbo.InsertFileMetadata
    @FileName   NVARCHAR(260),
    @ModifiedAt DATETIME2
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.FileMetadata
       SET ModifiedAt = @ModifiedAt,
           UpdatedAt = SYSUTCDATETIME()
     WHERE FileName = @FileName;

    IF @@ROWCOUNT = 0
        INSERT INTO dbo.FileMetadata (FileName, ModifiedAt) VALUES (@FileName, @ModifiedAt);
END;
GO

/* Record an error from a failure dependency branch. */
CREATE OR ALTER PROCEDURE dbo.InsertLoadingError
    @PipelineName  NVARCHAR(200),
    @PipelineRunId NVARCHAR(50),
    @ActivityName  NVARCHAR(200),
    @ErrorMessage  NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.LoadingError (PipelineName, PipelineRunId, ActivityName, ErrorMessage)
    VALUES (@PipelineName, @PipelineRunId, @ActivityName, @ErrorMessage);
END;
GO

/* Advance the incremental-load watermark after a successful load. */
CREATE OR ALTER PROCEDURE dbo.UpdateWatermark
    @TableName NVARCHAR(200),
    @NewValue  DATETIME2
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.LoadWatermark SET WatermarkValue = @NewValue WHERE TableName = @TableName;
    IF @@ROWCOUNT = 0
        INSERT INTO dbo.LoadWatermark (TableName, WatermarkValue) VALUES (@TableName, @NewValue);
END;
GO

/* Delete only the rows owned by one source file before it is copied again.
   This makes a retry deterministic without truncating other days. */
CREATE OR ALTER PROCEDURE dbo.DeleteSalesBySourceFile
    @SourceFileName NVARCHAR(260)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DELETE FROM dbo.FactSales WHERE SourceFileName = @SourceFileName;
END;
GO

/* Apply a fully landed customer snapshot as one atomic SCD Type 2 transaction. */
CREATE OR ALTER PROCEDURE dbo.ApplyCustomerSCD2
    @EffectiveFrom DATETIME2
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
    BEGIN TRANSACTION;

    UPDATE currentVersion
       SET currentVersion.IsCurrent = 0,
           currentVersion.EffectiveTo = @EffectiveFrom
      FROM dbo.DimCustomer AS currentVersion
      JOIN dbo.StgCustomer AS snapshot
        ON snapshot.CustomerID = currentVersion.CustomerID
     WHERE currentVersion.IsCurrent = 1
       AND (
            ISNULL(currentVersion.FirstName, '')   <> ISNULL(snapshot.FirstName, '') OR
            ISNULL(currentVersion.LastName, '')    <> ISNULL(snapshot.LastName, '') OR
            ISNULL(currentVersion.Email, '')       <> ISNULL(snapshot.Email, '') OR
            ISNULL(currentVersion.City, '')        <> ISNULL(snapshot.City, '') OR
            ISNULL(currentVersion.LoyaltyTier, '') <> ISNULL(snapshot.LoyaltyTier, '')
       );

    INSERT INTO dbo.DimCustomer
        (CustomerID, FirstName, LastName, Email, City, LoyaltyTier, IsCurrent, EffectiveFrom, EffectiveTo)
    SELECT snapshot.CustomerID, snapshot.FirstName, snapshot.LastName, snapshot.Email,
           snapshot.City, snapshot.LoyaltyTier, 1, @EffectiveFrom, NULL
      FROM dbo.StgCustomer AS snapshot
      LEFT JOIN dbo.DimCustomer AS currentVersion
        ON currentVersion.CustomerID = snapshot.CustomerID
       AND currentVersion.IsCurrent = 1
     WHERE currentVersion.CustomerSK IS NULL;

    COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO
