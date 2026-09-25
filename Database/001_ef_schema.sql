/* Run after raw_data.sql. EF Core uses rowversion for optimistic concurrency. */
IF COL_LENGTH('dbo.review_task','row_version') IS NULL
BEGIN
    ALTER TABLE dbo.review_task ADD row_version ROWVERSION NOT NULL;
END
GO

IF OBJECT_ID('dbo.review_task_event','U') IS NULL
BEGIN
    CREATE TABLE dbo.review_task_event (
        event_id BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_review_task_event PRIMARY KEY,
        task_id INT NOT NULL,
        claim_id INT NULL,
        queue_id INT NULL,
        user_id INT NULL,
        event_type VARCHAR(40) NOT NULL,
        outcome VARCHAR(30) NULL,
        note NVARCHAR(500) NULL,
        event_at DATETIME2(0) NOT NULL,
        active_from DATETIME2(0) NULL,
        active_to DATETIME2(0) NULL,
        CONSTRAINT FK_review_task_event_task FOREIGN KEY(task_id) REFERENCES dbo.review_task(task_id),
        CONSTRAINT FK_review_task_event_claim FOREIGN KEY(claim_id) REFERENCES dbo.claim(claim_id),
        CONSTRAINT FK_review_task_event_queue FOREIGN KEY(queue_id) REFERENCES dbo.queue(queue_id),
        CONSTRAINT FK_review_task_event_user FOREIGN KEY(user_id) REFERENCES dbo.app_user(user_id)
    );
    CREATE INDEX IX_review_task_event_task_type_time ON dbo.review_task_event(task_id,event_type,event_at);
    CREATE INDEX IX_review_task_event_user_type_time ON dbo.review_task_event(user_id,event_type,event_at);
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='IX_review_task_GetNext' AND object_id=OBJECT_ID('dbo.review_task'))
    CREATE INDEX IX_review_task_GetNext ON dbo.review_task(queue_id,status,priority,due_date,claim_id) INCLUDE(assigned_to_user_id,locked_by_user_id,lock_expires_on);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='IX_review_task_ClaimStatus' AND object_id=OBJECT_ID('dbo.review_task'))
    CREATE INDEX IX_review_task_ClaimStatus ON dbo.review_task(claim_id,status);
GO
