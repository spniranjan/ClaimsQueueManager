/* All timestamps are UTC. Active time = sum of ReviewAcquired-to-Release/Complete intervals. */
-- 1. Tasks completed per user per day
SELECT u.username, CAST(t.closed_at AS date) AS utc_day, COUNT(*) AS tasks_completed
FROM dbo.review_task t JOIN dbo.app_user u ON u.user_id=t.closed_by_user_id
WHERE t.status='Closed' AND t.outcome <> 'SystemClosed'
GROUP BY u.username, CAST(t.closed_at AS date) ORDER BY utc_day,u.username;

-- 2. SLA compliance
SELECT 100.0 * SUM(CASE WHEN closed_at <= due_date THEN 1 ELSE 0 END) / NULLIF(COUNT(*),0) AS sla_compliance_pct
FROM dbo.review_task WHERE status='Closed' AND outcome <> 'SystemClosed';

-- 3. Queue entry to first review: median and P90
WITH first_review AS (
 SELECT t.task_id,t.created_at,MIN(e.event_at) first_review_at
 FROM dbo.review_task t JOIN dbo.review_task_event e ON e.task_id=t.task_id AND e.event_type='ReviewAcquired'
 GROUP BY t.task_id,t.created_at
), d AS (
 SELECT DATEDIFF_BIG(SECOND,created_at,first_review_at) seconds_to_review FROM first_review
)
SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY seconds_to_review) OVER() AS median_seconds,
       PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY seconds_to_review) OVER() AS p90_seconds
FROM d;

-- 4. Completed in last hour by queue
SELECT q.queue_name, COUNT(*) completed_count FROM dbo.review_task t JOIN dbo.queue q ON q.queue_id=t.queue_id
WHERE t.status='Closed' AND t.closed_at >= DATEADD(hour,-1,SYSUTCDATETIME()) GROUP BY q.queue_name;

-- 5. Reviewer completion ranking by day
SELECT u.username, CAST(t.closed_at AS date) utc_day, COUNT(*) completions,
       DENSE_RANK() OVER(PARTITION BY CAST(t.closed_at AS date) ORDER BY COUNT(*) DESC) rank_no
FROM dbo.review_task t JOIN dbo.app_user u ON u.user_id=t.closed_by_user_id WHERE t.status='Closed' AND t.outcome<>'SystemClosed'
GROUP BY u.username,CAST(t.closed_at AS date);

-- 6. Average review duration per user/day
WITH durations AS (
 SELECT e.user_id,CAST(e.event_at AS date) utc_day,DATEDIFF_BIG(SECOND,e.active_from,e.active_to) seconds_active
 FROM dbo.review_task_event e WHERE e.event_type IN ('Released','Completed') AND e.active_from IS NOT NULL AND e.active_to IS NOT NULL
)
SELECT u.username,utc_day,AVG(CAST(seconds_active AS decimal(18,2))) avg_seconds FROM durations d JOIN dbo.app_user u ON u.user_id=d.user_id GROUP BY u.username,utc_day;

-- 7. Arrivals vs completions per hour, rolling 2-hour window
WITH hours AS (SELECT DATEADD(hour,DATEDIFF(hour,0,SYSUTCDATETIME())-1,0) hour_start UNION ALL SELECT DATEADD(hour,DATEDIFF(hour,0,SYSUTCDATETIME()),0)),
a AS (SELECT DATEADD(hour,DATEDIFF(hour,0,created_at),0) h,COUNT(*) n FROM dbo.review_task GROUP BY DATEADD(hour,DATEDIFF(hour,0,created_at),0)),
c AS (SELECT DATEADD(hour,DATEDIFF(hour,0,closed_at),0) h,COUNT(*) n FROM dbo.review_task WHERE closed_at IS NOT NULL GROUP BY DATEADD(hour,DATEDIFF(hour,0,closed_at),0))
SELECT h.hour_start,ISNULL(a.n,0) arrivals,ISNULL(c.n,0) completions FROM hours h LEFT JOIN a ON a.h=h.hour_start LEFT JOIN c ON c.h=h.hour_start ORDER BY h.hour_start;

-- 8. Top five reviewers (by completed tasks)
SELECT TOP (5) u.username,COUNT(*) completions FROM dbo.review_task t JOIN dbo.app_user u ON u.user_id=t.closed_by_user_id WHERE t.status='Closed' AND t.outcome<>'SystemClosed' GROUP BY u.username ORDER BY COUNT(*) DESC;

-- 9. Open backlog per queue
SELECT q.queue_name,COUNT(*) open_backlog FROM dbo.review_task t JOIN dbo.queue q ON q.queue_id=t.queue_id WHERE t.status='Open' GROUP BY q.queue_name;

-- 10. Reviewer idle-time approximation. Active time is lock intervals; logged-in time comes from seeded user_session.
WITH active AS (SELECT user_id,SUM(DATEDIFF_BIG(SECOND,active_from,active_to)) active_seconds FROM dbo.review_task_event WHERE active_from IS NOT NULL AND active_to IS NOT NULL GROUP BY user_id), login AS (SELECT user_id,SUM(DATEDIFF_BIG(SECOND,started_at,COALESCE(ended_at,SYSUTCDATETIME()))) login_seconds FROM dbo.user_session GROUP BY user_id)
SELECT u.username,ISNULL(a.active_seconds,0) active_seconds,login.login_seconds,100.0*ISNULL(a.active_seconds,0)/NULLIF(login.login_seconds,0) active_pct FROM dbo.app_user u JOIN login ON login.user_id=u.user_id LEFT JOIN active a ON a.user_id=u.user_id WHERE u.role='Reviewer';
