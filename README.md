# Healthcare Claims Queue Manager - EF Core

ASP.NET Core 8 + EF Core 8 + SQL Server implementation of the supplied assignment.

## Run
1. Create an empty SQL Server database named `ClaimsQueue`.
2. Run `Database/raw_data.sql`.
3. Run `Database/001_ef_schema.sql`.
4. Update `appsettings.json` connection string.
5. `dotnet restore && dotnet build && dotnet run`.
6. Open `/` for the basic UI or `/swagger` in Development.

## Design decisions
- Get Next is read-only and never acquires a lock, matching the assignment.
- Review uses EF Core optimistic concurrency with SQL Server `rowversion`. Two simultaneous Review calls can load the same version, but only one SaveChanges succeeds; the other returns HTTP 409.
- Default lock duration is 15 minutes and is configurable in appsettings.
- Expired locks confer no ownership.
- Forward requires the caller to hold the active lock and releases that lock after forwarding. This prevents the original reviewer retaining control after handing work to another reviewer.
- Forward targets a reviewer; queue membership is not separately modeled in the supplied schema, so any seeded reviewer may be selected.
- Deny closes all other open sibling tasks for the same claim. Those sibling completions are attributed as `SystemClosed` and do not count as reviewer completions.
- If a sibling is actively locked when Deny occurs, Deny still closes it because the assignment requires all other open tasks for the same claim to close. The event records the denial-caused system close.
- Pend moves the existing task to the PEND queue, clears its lock, retains its due date/SLA clock, and records a Pend event.
- Get Next works on Pend as an ordinary queue because the brief does not exclude it.
- All timestamps are UTC.
- Active time is defined as the sum of lock intervals from ReviewAcquired until Release/Completed. Expired locks without a release event are not counted as completed active intervals.

## Schema additions
`review_task.row_version` supports EF Core optimistic concurrency. `review_task_event` captures queue-entry/review/completion activity needed for metrics. The supplied queue, claim, app_user and user_session structures are otherwise left unchanged.

## Intentionally not built
Authentication, authorization framework, dashboards, adjudication rules, deployment and SPA UI are out of scope in the assignment.

## Production follow-up
For ~2 million open tasks, I would benchmark the Get Next query with production data distribution, consider filtered indexes for Open tasks, add structured logging/telemetry, and use integration tests against SQL Server rather than only provider mocks.
