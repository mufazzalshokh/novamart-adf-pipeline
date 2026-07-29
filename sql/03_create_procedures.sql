/* ============================================================================
   NovaMart Data Platform � Stored procedures
   Run this THIRD. These are called from ADF Stored Procedure / Lookup activities.
   ============================================================================ */

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
END;
GO
