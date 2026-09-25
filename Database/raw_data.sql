/* =============================================================================
   Claims Queue Manager — Starter Schema & Seed Data
   Target: SQL Server 2019+   (PostgreSQL conversion notes at the bottom)

   WHAT THIS IS
   ------------
   Reference data and fixtures so you don't spend your time box inventing test
   data. Run this once against an empty database.

   WHAT YOU MAY CHANGE
   -------------------
   - review_task: treat this as a STARTING POINT. Add, rename, or remove
     columns; split it into multiple tables; normalize it differently. If you
     change it, update the seed INSERTs accordingly.
   - Indexes: only primary keys and a couple of FK indexes are defined here.
     Choosing the right indexes for the selection query is part of the exercise.

   WHAT YOU SHOULD NOT CHANGE
   --------------------------
   - queue, app_user, claim, user_session and their seeded rows. We use these
     to compare submissions, and several scenarios below depend on the exact
     claim numbers and priorities.

   WHAT IS DELIBERATELY MISSING
   ----------------------------
   - Any event / audit / history table. Designing that is part of the
     assignment. See the "Data Capture" section of the assignment brief.
   - Any authentication or authorization structures. Out of scope.

   NOTE ON HISTORICAL DATA
   -----------------------
   The closed tasks seeded below are enough to make "tasks completed per day"
   and "SLA compliance" return non-empty results immediately. They do NOT
   contain open/first-viewed history. Metrics that depend on events (e.g. time
   from queue entry to first review) only need to work for activity generated
   by your running application. You do not need to backfill anything.
============================================================================= */

SET NOCOUNT ON;
GO

/* ---------------------------------------------------------------------------
   1. Schema
--------------------------------------------------------------------------- */

IF OBJECT_ID('dbo.review_task', 'U')  IS NOT NULL DROP TABLE dbo.review_task;
IF OBJECT_ID('dbo.user_session', 'U') IS NOT NULL DROP TABLE dbo.user_session;
IF OBJECT_ID('dbo.claim', 'U')        IS NOT NULL DROP TABLE dbo.claim;
IF OBJECT_ID('dbo.app_user', 'U')     IS NOT NULL DROP TABLE dbo.app_user;
IF OBJECT_ID('dbo.queue', 'U')        IS NOT NULL DROP TABLE dbo.queue;
GO

CREATE TABLE dbo.queue (
    queue_id     INT           NOT NULL IDENTITY(1,1) PRIMARY KEY,
    queue_code   VARCHAR(20)   NOT NULL UNIQUE,
    queue_name   NVARCHAR(100) NOT NULL
);
GO

CREATE TABLE dbo.app_user (
    user_id      INT           NOT NULL IDENTITY(1,1) PRIMARY KEY,
    username     VARCHAR(50)   NOT NULL UNIQUE,   -- value passed in X-User-Id header
    display_name NVARCHAR(100) NOT NULL,
    role         VARCHAR(20)   NOT NULL           -- 'Reviewer' | 'Supervisor'
);
GO

CREATE TABLE dbo.claim (
    claim_id        INT            NOT NULL IDENTITY(1,1) PRIMARY KEY,
    claim_number    CHAR(10)       NOT NULL UNIQUE,  -- zero-padded; lexical order == numeric order
    member_id       VARCHAR(20)    NOT NULL,
    provider_id     VARCHAR(20)    NOT NULL,
    billed_amount   DECIMAL(12,2)  NOT NULL,
    service_from    DATE           NOT NULL,
    service_to      DATE           NOT NULL,
    received_on     DATETIME2(0)   NOT NULL
);
GO

/*  The unit of work is a REVIEW TASK: one claim in one queue.
    A claim with three open tasks is being worked in three queues, potentially
    by three different reviewers at the same time. Locks are held on a task,
    not on a claim. See the assignment brief for the full definition. */
CREATE TABLE dbo.review_task (
    task_id              INT           NOT NULL IDENTITY(1,1) PRIMARY KEY,
    claim_id             INT           NOT NULL REFERENCES dbo.claim(claim_id),
    queue_id             INT           NOT NULL REFERENCES dbo.queue(queue_id),

    priority             TINYINT       NOT NULL,   -- 1 = highest ... 5 = lowest
    due_date             DATETIME2(0)  NOT NULL,

    assigned_to_user_id  INT           NULL REFERENCES dbo.app_user(user_id),
    assigned_by_user_id  INT           NULL REFERENCES dbo.app_user(user_id),

    status               VARCHAR(20)   NOT NULL,   -- 'Open' | 'Closed'
    outcome              VARCHAR(30)   NULL,       -- NULL while open; see note below

    locked_by_user_id    INT           NULL REFERENCES dbo.app_user(user_id),
    locked_on            DATETIME2(0)  NULL,
    lock_expires_on      DATETIME2(0)  NULL,

    created_at           DATETIME2(0)  NOT NULL,   -- when the task entered the queue
    closed_at            DATETIME2(0)  NULL,
    closed_by_user_id    INT           NULL REFERENCES dbo.app_user(user_id),
    note                 NVARCHAR(500) NULL,

    CONSTRAINT ck_review_task_priority CHECK (priority BETWEEN 1 AND 5)
);
GO

/*  Outcome values used by this seed script:
      'Approve'        - Complete - Approve
      'PartialDenial'  - Complete - Partial Denial
      'Deny'           - Complete - Deny
      'Pend'           - reviewer pended the task
      'SystemClosed'   - closed as a side effect of another task's outcome
    You may change this vocabulary. If you do, say why in your README. */

CREATE INDEX ix_review_task_queue_status ON dbo.review_task (queue_id, status);
CREATE INDEX ix_review_task_claim        ON dbo.review_task (claim_id);
GO

/*  Sessions are seeded, not managed by your application. Authentication is out
    of scope, so nothing you build needs to write to this table. It exists so
    the login-duration and idle-time metrics have something to query against. */
CREATE TABLE dbo.user_session (
    session_id   INT          NOT NULL IDENTITY(1,1) PRIMARY KEY,
    user_id      INT          NOT NULL REFERENCES dbo.app_user(user_id),
    started_at   DATETIME2(0) NOT NULL,
    ended_at     DATETIME2(0) NULL           -- NULL = still logged in
);
GO


/* ---------------------------------------------------------------------------
   2. Reference data
--------------------------------------------------------------------------- */

SET IDENTITY_INSERT dbo.queue ON;
INSERT INTO dbo.queue (queue_id, queue_code, queue_name) VALUES
    (1, 'DUP',   N'Duplicate Check'),
    (2, 'AUTH',  N'Authorization Matching'),
    (3, 'CASE',  N'Case Rate'),
    (4, 'BENE',  N'Benefit Included in Another Service'),
    (5, 'PEND',  N'Pend'),
    (6, 'OTHER', N'Other');
SET IDENTITY_INSERT dbo.queue OFF;
GO

SET IDENTITY_INSERT dbo.app_user ON;
INSERT INTO dbo.app_user (user_id, username, display_name, role) VALUES
    (1, 'sfranklin',  N'Sarah Franklin',  'Supervisor'),
    (2, 'ereyes',     N'Elena Reyes',     'Reviewer'),
    (3, 'jchen',      N'Jason Chen',      'Reviewer'),
    (4, 'mkowalski',  N'Marta Kowalski',  'Reviewer'),
    (5, 'apatel',     N'Arjun Patel',     'Reviewer'),
    (6, 'dnguyen',    N'Dana Nguyen',     'Reviewer'),
    (7, 'lbecker',    N'Luis Becker',     'Reviewer'),
    (8, 'tosei',      N'Tom Osei',        'Reviewer');
SET IDENTITY_INSERT dbo.app_user OFF;
GO


/* ---------------------------------------------------------------------------
   3. Claims

   Claim numbers are deliberately NOT in claim_id order. "Lowest claim number"
   in the selection rules means claim_number, not claim_id.
--------------------------------------------------------------------------- */

DECLARE @today DATE = CAST(SYSUTCDATETIME() AS DATE);

SET IDENTITY_INSERT dbo.claim ON;
INSERT INTO dbo.claim (claim_id, claim_number, member_id, provider_id, billed_amount, service_from, service_to, received_on) VALUES
    ( 1, '0000418822', 'M00102341', 'P4471',  1240.00, DATEADD(day,-40,@today), DATEADD(day,-40,@today), DATEADD(day,-12,SYSUTCDATETIME())),
    ( 2, '0000418799', 'M00119088', 'P2210',   380.50, DATEADD(day,-38,@today), DATEADD(day,-38,@today), DATEADD(day,-12,SYSUTCDATETIME())),
    ( 3, '0000419044', 'M00102341', 'P4471',  1240.00, DATEADD(day,-40,@today), DATEADD(day,-40,@today), DATEADD(day,-11,SYSUTCDATETIME())),
    ( 4, '0000418501', 'M00133702', 'P8815', 18750.00, DATEADD(day,-52,@today), DATEADD(day,-45,@today), DATEADD(day,-14,SYSUTCDATETIME())),
    ( 5, '0000419310', 'M00140556', 'P3390',  6420.75, DATEADD(day,-30,@today), DATEADD(day,-28,@today), DATEADD(day,-10,SYSUTCDATETIME())),
    ( 6, '0000418640', 'M00151223', 'P1104',   225.00, DATEADD(day,-36,@today), DATEADD(day,-36,@today), DATEADD(day,-13,SYSUTCDATETIME())),
    ( 7, '0000419127', 'M00133702', 'P8815',  9300.00, DATEADD(day,-44,@today), DATEADD(day,-41,@today), DATEADD(day,-11,SYSUTCDATETIME())),
    ( 8, '0000418355', 'M00160914', 'P5528',   790.25, DATEADD(day,-33,@today), DATEADD(day,-33,@today), DATEADD(day,-15,SYSUTCDATETIME())),
    ( 9, '0000419488', 'M00172380', 'P6641',  3110.00, DATEADD(day,-29,@today), DATEADD(day,-27,@today), DATEADD(day, -9,SYSUTCDATETIME())),
    (10, '0000418913', 'M00119088', 'P2210',   380.50, DATEADD(day,-38,@today), DATEADD(day,-38,@today), DATEADD(day,-12,SYSUTCDATETIME())),
    (11, '0000418277', 'M00184455', 'P7702',   615.00, DATEADD(day,-47,@today), DATEADD(day,-47,@today), DATEADD(day,-16,SYSUTCDATETIME())),
    (12, '0000419602', 'M00190017', 'P8815', 24100.00, DATEADD(day,-26,@today), DATEADD(day,-14,@today), DATEADD(day, -8,SYSUTCDATETIME())),
    (13, '0000418734', 'M00151223', 'P1104',   225.00, DATEADD(day,-36,@today), DATEADD(day,-36,@today), DATEADD(day,-13,SYSUTCDATETIME())),
    (14, '0000419255', 'M00203118', 'P3390',  1875.40, DATEADD(day,-31,@today), DATEADD(day,-31,@today), DATEADD(day,-10,SYSUTCDATETIME())),
    (15, '0000418088', 'M00211946', 'P4471',   455.00, DATEADD(day,-55,@today), DATEADD(day,-55,@today), DATEADD(day,-18,SYSUTCDATETIME())),
    (16, '0000419731', 'M00224503', 'P9963',  7240.00, DATEADD(day,-22,@today), DATEADD(day,-19,@today), DATEADD(day, -7,SYSUTCDATETIME())),
    (17, '0000418566', 'M00230877', 'P5528',   980.00, DATEADD(day,-42,@today), DATEADD(day,-42,@today), DATEADD(day,-14,SYSUTCDATETIME())),
    (18, '0000419166', 'M00184455', 'P7702',   615.00, DATEADD(day,-47,@today), DATEADD(day,-47,@today), DATEADD(day,-11,SYSUTCDATETIME())),
    (19, '0000418401', 'M00246330', 'P1104',  2050.00, DATEADD(day,-34,@today), DATEADD(day,-34,@today), DATEADD(day,-15,SYSUTCDATETIME())),
    (20, '0000419845', 'M00250192', 'P6641',   140.75, DATEADD(day,-20,@today), DATEADD(day,-20,@today), DATEADD(day, -6,SYSUTCDATETIME())),
    (21, '0000418955', 'M00261408', 'P9963', 11890.00, DATEADD(day,-27,@today), DATEADD(day,-21,@today), DATEADD(day,-12,SYSUTCDATETIME())),
    (22, '0000419399', 'M00272561', 'P2210',   505.00, DATEADD(day,-25,@today), DATEADD(day,-25,@today), DATEADD(day, -9,SYSUTCDATETIME())),
    (23, '0000418190', 'M00280074', 'P3390',  3320.00, DATEADD(day,-50,@today), DATEADD(day,-48,@today), DATEADD(day,-17,SYSUTCDATETIME())),
    (24, '0000419520', 'M00293815', 'P5528',   865.00, DATEADD(day,-23,@today), DATEADD(day,-23,@today), DATEADD(day, -8,SYSUTCDATETIME()));
SET IDENTITY_INSERT dbo.claim OFF;
GO


/* ---------------------------------------------------------------------------
   4. Review tasks

   Scenario map (used by the reviewing engineer — leave the data alone):

     A. Tie on priority AND due date -> must break on claim_number.
        Queue DUP, tasks 1 & 2 (same priority 3, same due date). Task 1
        (claim 0000418277) must sort ahead of task 2 (claim 0000418822).
        Note these sit mid-queue, so this only shows up if the full ordering
        is correct — not just the first row.
     B. Assignment outranks priority.
        Queue AUTH: task 10 is priority 5 assigned to 'ereyes'; task 16 is
        priority 2 assigned to 'jchen'; task 11 is priority 1 unassigned.
        Get Next returns task 10 for ereyes, task 16 for jchen, and task 11
        for every other reviewer.
     C. Expired lock must be selectable again.
        Queue CASE, task 20 — locked by mkowalski, expired 25 minutes ago.
        It is the highest-ranked CASE task, so a correct implementation
        returns it and an implementation that only checks locked_by does not.
     D. Live lock must be skipped.
        Queue CASE, task 21 — locked by apatel, expires in ~10 minutes.
     E. Deny cascade, no locks involved.
        Claim 0000419310 (claim_id 5) has open tasks in DUP, AUTH and BENE.
     F. Deny cascade while a sibling is actively locked by someone else.
        Claim 0000419602 (claim_id 12): open in DUP (free) and CASE (locked
        live by dnguyen). Denying the DUP task must do something sensible with
        the locked CASE task — this case is intentional.
     G. Past-due open tasks exist, for backlog and SLA queries.
     H. Closed tasks across today and yesterday, some inside SLA and some
        outside, for the completion-count and SLA queries.
--------------------------------------------------------------------------- */

DECLARE @now DATETIME2(0) = SYSUTCDATETIME();

SET IDENTITY_INSERT dbo.review_task ON;

-- --- Scenario A: exact tie down to claim_number ------------------------------
INSERT INTO dbo.review_task
 (task_id, claim_id, queue_id, priority, due_date, assigned_to_user_id, assigned_by_user_id, status, outcome, locked_by_user_id, locked_on, lock_expires_on, created_at, closed_at, closed_by_user_id, note)
VALUES
 (  1, 11, 1, 3, DATEADD(hour,  36, @now), NULL, NULL, 'Open', NULL, NULL, NULL, NULL, DATEADD(hour, -30, @now), NULL, NULL, NULL),
 (  2,  1, 1, 3, DATEADD(hour,  36, @now), NULL, NULL, 'Open', NULL, NULL, NULL, NULL, DATEADD(hour, -28, @now), NULL, NULL, NULL);

-- --- Duplicate Check: general backlog ----------------------------------------
INSERT INTO dbo.review_task
 (task_id, claim_id, queue_id, priority, due_date, assigned_to_user_id, assigned_by_user_id, status, outcome, locked_by_user_id, locked_on, lock_expires_on, created_at, closed_at, closed_by_user_id, note)
VALUES
 (  3,  3, 1, 2, DATEADD(hour,  20, @now), NULL, NULL, 'Open', NULL, NULL, NULL, NULL, DATEADD(hour, -26, @now), NULL, NULL, NULL),
 (  4, 10, 1, 4, DATEADD(hour,  60, @now), NULL, NULL, 'Open', NULL, NULL, NULL, NULL, DATEADD(hour, -22, @now), NULL, NULL, NULL),
 (  5, 13, 1, 4, DATEADD(hour,  60, @now), NULL, NULL, 'Open', NULL, NULL, NULL, NULL, DATEADD(hour, -21, @now), NULL, NULL, NULL),
 (  6, 18, 1, 1, DATEADD(hour,  -6, @now), NULL, NULL, 'Open', NULL, NULL, NULL, NULL, DATEADD(hour, -44, @now), NULL, NULL, NULL),   -- past due
 (  7,  5, 1, 2, DATEADD(hour,  14, @now), NULL, NULL, 'Open', NULL, NULL, NULL, NULL, DATEADD(hour, -19, @now), NULL, NULL, NULL),   -- scenario E
 (  8, 12, 1, 2, DATEADD(hour,  18, @now), NULL, NULL, 'Open', NULL, NULL, NULL, NULL, DATEADD(hour, -17, @now), NULL, NULL, NULL),   -- scenario F
 (  9, 15, 1, 5, DATEADD(hour,  90, @now),    7,    1, 'Open', NULL, NULL, NULL, NULL, DATEADD(hour, -34, @now), NULL, NULL, N'Forwarded from initial triage.');

-- --- Scenario B: Authorization Matching, assignment vs priority --------------
INSERT INTO dbo.review_task
 (task_id, claim_id, queue_id, priority, due_date, assigned_to_user_id, assigned_by_user_id, status, outcome, locked_by_user_id, locked_on, lock_expires_on, created_at, closed_at, closed_by_user_id, note)
VALUES
 ( 10, 17, 2, 5, DATEADD(hour, 100, @now),    2,    1, 'Open', NULL, NULL, NULL, NULL, DATEADD(hour, -33, @now), NULL, NULL, N'Assigned to Elena - provider relationship.'),
 ( 11,  8, 2, 1, DATEADD(hour,   9, @now), NULL, NULL, 'Open', NULL, NULL, NULL, NULL, DATEADD(hour, -31, @now), NULL, NULL, NULL),
 ( 12,  5, 2, 2, DATEADD(hour,  14, @now), NULL, NULL, 'Open', NULL, NULL, NULL, NULL, DATEADD(hour, -19, @now), NULL, NULL, NULL),   -- scenario E
 ( 13, 19, 2, 3, DATEADD(hour,  40, @now), NULL, NULL, 'Open', NULL, NULL, NULL, NULL, DATEADD(hour, -27, @now), NULL, NULL, NULL),
 ( 14, 22, 2, 3, DATEADD(hour,  40, @now), NULL, NULL, 'Open', NULL, NULL, NULL, NULL, DATEADD(hour, -15, @now), NULL, NULL, NULL),
 ( 15,  2, 2, 4, DATEADD(hour,  -2, @now), NULL, NULL, 'Open', NULL, NULL, NULL, NULL, DATEADD(hour, -49, @now), NULL, NULL, NULL),   -- past due
 ( 16, 24, 2, 2, DATEADD(hour,  30, @now),    3,    1, 'Open', NULL, NULL, NULL, NULL, DATEADD(hour, -12, @now), NULL, NULL, NULL);

-- --- Case Rate: includes the two lock scenarios (C and D) --------------------
INSERT INTO dbo.review_task
 (task_id, claim_id, queue_id, priority, due_date, assigned_to_user_id, assigned_by_user_id, status, outcome, locked_by_user_id, locked_on, lock_expires_on, created_at, closed_at, closed_by_user_id, note)
VALUES
 ( 20,  4, 3, 1, DATEADD(hour,   8, @now), NULL, NULL, 'Open', NULL,    4, DATEADD(minute, -40, @now), DATEADD(minute, -25, @now), DATEADD(hour, -38, @now), NULL, NULL, NULL),  -- C: lock expired
 ( 21, 21, 3, 1, DATEADD(hour,  11, @now), NULL, NULL, 'Open', NULL,    5, DATEADD(minute,  -5, @now), DATEADD(minute,  10, @now), DATEADD(hour, -24, @now), NULL, NULL, NULL),  -- D: lock live
 ( 22, 12, 3, 2, DATEADD(hour,  18, @now), NULL, NULL, 'Open', NULL,    6, DATEADD(minute,  -3, @now), DATEADD(minute,  12, @now), DATEADD(hour, -17, @now), NULL, NULL, NULL),  -- F: locked sibling
 ( 23,  7, 3, 3, DATEADD(hour,  46, @now), NULL, NULL, 'Open', NULL, NULL, NULL, NULL, DATEADD(hour, -29, @now), NULL, NULL, NULL),
 ( 24, 16, 3, 4, DATEADD(hour,  70, @now), NULL, NULL, 'Open', NULL, NULL, NULL, NULL, DATEADD(hour, -13, @now), NULL, NULL, NULL),
 ( 25, 23, 3, 5, DATEADD(hour, 120, @now), NULL, NULL, 'Open', NULL, NULL, NULL, NULL, DATEADD(hour, -41, @now), NULL, NULL, NULL);

-- --- Benefit Included --------------------------------------------------------
INSERT INTO dbo.review_task
 (task_id, claim_id, queue_id, priority, due_date, assigned_to_user_id, assigned_by_user_id, status, outcome, locked_by_user_id, locked_on, lock_expires_on, created_at, closed_at, closed_by_user_id, note)
VALUES
 ( 30,  5, 4, 2, DATEADD(hour,  14, @now), NULL, NULL, 'Open', NULL, NULL, NULL, NULL, DATEADD(hour, -19, @now), NULL, NULL, NULL),   -- scenario E
 ( 31,  6, 4, 3, DATEADD(hour,  33, @now), NULL, NULL, 'Open', NULL, NULL, NULL, NULL, DATEADD(hour, -25, @now), NULL, NULL, NULL),
 ( 32, 14, 4, 1, DATEADD(hour,  -4, @now), NULL, NULL, 'Open', NULL, NULL, NULL, NULL, DATEADD(hour, -51, @now), NULL, NULL, NULL),   -- past due
 ( 33, 20, 4, 4, DATEADD(hour,  80, @now),    6,    1, 'Open', NULL, NULL, NULL, NULL, DATEADD(hour, -10, @now), NULL, NULL, NULL),
 ( 34,  9, 4, 3, DATEADD(hour,  33, @now), NULL, NULL, 'Open', NULL, NULL, NULL, NULL, DATEADD(hour, -16, @now), NULL, NULL, NULL);

-- --- Pend and Other ----------------------------------------------------------
INSERT INTO dbo.review_task
 (task_id, claim_id, queue_id, priority, due_date, assigned_to_user_id, assigned_by_user_id, status, outcome, locked_by_user_id, locked_on, lock_expires_on, created_at, closed_at, closed_by_user_id, note)
VALUES
 ( 40, 15, 5, 3, DATEADD(hour,  55, @now), NULL, NULL, 'Open', NULL, NULL, NULL, NULL, DATEADD(hour, -20, @now), NULL, NULL, N'Awaiting medical records from provider.'),
 ( 41, 23, 5, 2, DATEADD(hour,  26, @now), NULL, NULL, 'Open', NULL, NULL, NULL, NULL, DATEADD(hour, -35, @now), NULL, NULL, N'Pended pending authorization lookup.'),
 ( 42, 20, 6, 4, DATEADD(hour,  72, @now), NULL, NULL, 'Open', NULL, NULL, NULL, NULL, DATEADD(hour, -14, @now), NULL, NULL, NULL),
 ( 43, 22, 6, 5, DATEADD(hour, 110, @now), NULL, NULL, 'Open', NULL, NULL, NULL, NULL, DATEADD(hour, -11, @now), NULL, NULL, NULL);

-- --- Scenario H: closed history (today and yesterday) ------------------------
INSERT INTO dbo.review_task
 (task_id, claim_id, queue_id, priority, due_date, assigned_to_user_id, assigned_by_user_id, status, outcome, locked_by_user_id, locked_on, lock_expires_on, created_at, closed_at, closed_by_user_id, note)
VALUES
 ( 50,  1, 2, 2, DATEADD(hour, -20, @now), NULL, NULL, 'Closed', 'Approve',       NULL, NULL, NULL, DATEADD(hour, -46, @now), DATEADD(hour, -26, @now), 2, NULL),
 ( 51,  2, 1, 3, DATEADD(hour, -18, @now), NULL, NULL, 'Closed', 'Deny',          NULL, NULL, NULL, DATEADD(hour, -45, @now), DATEADD(hour, -24, @now), 2, N'Exact duplicate of 0000418799.'),
 ( 52,  6, 1, 3, DATEADD(hour, -30, @now), NULL, NULL, 'Closed', 'PartialDenial', NULL, NULL, NULL, DATEADD(hour, -47, @now), DATEADD(hour, -27, @now), 3, NULL),
 ( 53,  8, 4, 1, DATEADD(hour, -33, @now), NULL, NULL, 'Closed', 'Approve',       NULL, NULL, NULL, DATEADD(hour, -50, @now), DATEADD(hour, -35, @now), 3, NULL),
 ( 54,  9, 2, 2, DATEADD(hour, -12, @now), NULL, NULL, 'Closed', 'Approve',       NULL, NULL, NULL, DATEADD(hour, -40, @now), DATEADD(hour,  -9, @now), 4, NULL),   -- missed SLA
 ( 55, 11, 3, 4, DATEADD(hour, -15, @now), NULL, NULL, 'Closed', 'Approve',       NULL, NULL, NULL, DATEADD(hour, -39, @now), DATEADD(hour, -19, @now), 4, NULL),
 ( 56, 13, 2, 3, DATEADD(hour,  -8, @now), NULL, NULL, 'Closed', 'PartialDenial', NULL, NULL, NULL, DATEADD(hour, -37, @now), DATEADD(hour,  -3, @now), 5, NULL),   -- missed SLA
 ( 57, 14, 1, 2, DATEADD(hour,  -5, @now), NULL, NULL, 'Closed', 'Approve',       NULL, NULL, NULL, DATEADD(hour, -28, @now), DATEADD(hour,  -6, @now), 5, NULL),
 ( 58, 16, 4, 3, DATEADD(hour,  -4, @now), NULL, NULL, 'Closed', 'Deny',          NULL, NULL, NULL, DATEADD(hour, -23, @now), DATEADD(hour,  -5, @now), 6, NULL),
 ( 59, 16, 2, 3, DATEADD(hour,  -4, @now), NULL, NULL, 'Closed', 'SystemClosed',  NULL, NULL, NULL, DATEADD(hour, -23, @now), DATEADD(hour,  -5, @now), NULL, N'Closed by denial on task 58.'),
 ( 60, 17, 1, 4, DATEADD(hour,  -2, @now), NULL, NULL, 'Closed', 'Approve',       NULL, NULL, NULL, DATEADD(hour, -18, @now), DATEADD(hour,  -4, @now), 6, NULL),
 ( 61, 19, 4, 2, DATEADD(hour,  -1, @now), NULL, NULL, 'Closed', 'Approve',       NULL, NULL, NULL, DATEADD(hour, -16, @now), DATEADD(hour,  -2, @now), 7, NULL),
 ( 62, 21, 1, 3, DATEADD(hour,   1, @now), NULL, NULL, 'Closed', 'Approve',       NULL, NULL, NULL, DATEADD(hour, -14, @now), DATEADD(minute, -75, @now), 7, NULL),
 ( 63, 24, 3, 2, DATEADD(hour,   2, @now), NULL, NULL, 'Closed', 'PartialDenial', NULL, NULL, NULL, DATEADD(hour, -13, @now), DATEADD(minute, -40, @now), 2, NULL),
 ( 64,  4, 1, 1, DATEADD(hour,   3, @now), NULL, NULL, 'Closed', 'Approve',       NULL, NULL, NULL, DATEADD(hour, -12, @now), DATEADD(minute, -20, @now), 3, NULL);

SET IDENTITY_INSERT dbo.review_task OFF;
GO


/* ---------------------------------------------------------------------------
   5. User sessions

   Seeded only. Your application does not need to write here. Present so the
   login-duration / idle-time metrics have a table to join against.
--------------------------------------------------------------------------- */

DECLARE @s DATETIME2(0) = SYSUTCDATETIME();

INSERT INTO dbo.user_session (user_id, started_at, ended_at) VALUES
    (2, DATEADD(hour, -50, @s), DATEADD(hour, -42, @s)),
    (3, DATEADD(hour, -50, @s), DATEADD(hour, -43, @s)),
    (4, DATEADD(hour, -49, @s), DATEADD(hour, -41, @s)),
    (5, DATEADD(hour, -48, @s), DATEADD(hour, -41, @s)),
    (6, DATEADD(hour, -49, @s), DATEADD(hour, -40, @s)),
    (7, DATEADD(hour, -47, @s), DATEADD(hour, -40, @s)),
    (2, DATEADD(hour,  -7, @s), NULL),
    (3, DATEADD(hour,  -7, @s), NULL),
    (4, DATEADD(hour,  -6, @s), NULL),
    (5, DATEADD(hour,  -6, @s), NULL),
    (6, DATEADD(hour,  -5, @s), NULL),
    (7, DATEADD(hour,  -5, @s), DATEADD(hour, -1, @s)),
    (1, DATEADD(hour,  -8, @s), NULL);
GO


/* ---------------------------------------------------------------------------
   6. Sanity check
--------------------------------------------------------------------------- */

SELECT q.queue_code,
       SUM(CASE WHEN t.status = 'Open'   THEN 1 ELSE 0 END) AS open_tasks,
       SUM(CASE WHEN t.status = 'Closed' THEN 1 ELSE 0 END) AS closed_tasks
FROM dbo.queue q
LEFT JOIN dbo.review_task t ON t.queue_id = q.queue_id
GROUP BY q.queue_code
ORDER BY q.queue_code;
GO


/* =============================================================================
   PostgreSQL conversion notes

     IDENTITY(1,1)          ->  GENERATED BY DEFAULT AS IDENTITY
     SET IDENTITY_INSERT    ->  not needed; afterwards run
                                SELECT setval(pg_get_serial_sequence('review_task','task_id'),
                                              (SELECT MAX(task_id) FROM review_task));
     DATETIME2(0)           ->  timestamp(0)
     TINYINT                ->  smallint
     NVARCHAR(n) / N'...'   ->  varchar(n) / '...'
     SYSUTCDATETIME()       ->  (now() AT TIME ZONE 'utc')
     DATEADD(hour, -3, x)   ->  x - interval '3 hours'
     DROP the GO batch separators.

   All timestamps are UTC. Decide and document how you handle day boundaries
   for the per-day metrics.
============================================================================= */