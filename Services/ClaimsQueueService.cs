using ClaimsQueueManager.Data;
using ClaimsQueueManager.DTOs;
using ClaimsQueueManager.Models;
using Microsoft.EntityFrameworkCore;

namespace ClaimsQueueManager.Services;

public interface IClaimsQueueService
{
    Task<PagedResult<TaskListItem>> ListAsync(string queueCode, int page, int pageSize, CancellationToken ct);
    Task<ReviewTaskResult?> GetNextAsync(string queueCode, string username, CancellationToken ct);
    Task<ReviewTaskResult> ReviewAsync(int taskId, string username, CancellationToken ct);
    Task ReleaseAsync(int taskId, string username, CancellationToken ct);
    Task ForwardAsync(int taskId, string username, string targetUsername, CancellationToken ct);
    Task CompleteAsync(int taskId, string username, CompleteRequest request, CancellationToken ct);
}

public class ClaimsQueueService : IClaimsQueueService
{
    private readonly ClaimsDbContext _db;
    private readonly IConfiguration _config;
    public ClaimsQueueService(ClaimsDbContext db, IConfiguration config) { _db = db; _config = config; }
    private static DateTime UtcNow() => DateTime.UtcNow;
    //private async Task<AppUser> User(string username, CancellationToken ct) => await _db.AppUsers.SingleAsync(x => x.Username == username, ct);

    private async Task<AppUser> User(string username, CancellationToken ct)
    {
        var user = await _db.AppUsers
            .SingleOrDefaultAsync(x => x.Username == username, ct);

        if (user == null)
            throw new KeyNotFoundException("User '" + username + "' was not found.");

        return user;
    }
    public async Task<PagedResult<TaskListItem>> ListAsync(string queueCode, int page, int pageSize, CancellationToken ct)
    {
        page = Math.Max(1, page); pageSize = Math.Clamp(pageSize, 1, 200);
        var q = _db.ReviewTasks.AsNoTracking().Where(t => t.Status == "Open" && t.Queue.QueueCode == queueCode);
        var total = await q.CountAsync(ct);
        var items = await q.OrderBy(t => t.Priority).ThenBy(t => t.DueDate).ThenBy(t => t.Claim.ClaimNumber)
            .Skip((page - 1) * pageSize).Take(pageSize)
            .Select(t => new TaskListItem(t.TaskId, t.Claim.ClaimNumber, t.Queue.QueueName, t.Priority, t.DueDate,
                t.AssignedToUser == null ? null : t.AssignedToUser.Username,
                t.AssignedByUser == null ? null : t.AssignedByUser.Username,
                t.LockedByUser == null ? null : t.LockedByUser.Username, t.LockedOn)).ToListAsync(ct);
        return new PagedResult<TaskListItem>(items, page, pageSize, total);
    }

    public async Task<ReviewTaskResult?> GetNextAsync(string queueCode, string username, CancellationToken ct)
    {
        var now = UtcNow();
        var q = _db.ReviewTasks.AsNoTracking().Where(t => t.Status == "Open" && t.Queue.QueueCode == queueCode &&
            (t.AssignedToUserId == null || t.AssignedToUser!.Username == username) &&
            (t.LockExpiresOn == null || t.LockExpiresOn < now || t.LockedByUserId == null || t.LockedByUser!.Username == username));
        return await q.OrderByDescending(t => t.AssignedToUserId != null && t.AssignedToUser!.Username == username)
            .ThenBy(t => t.Priority).ThenBy(t => t.DueDate).ThenBy(t => t.Claim.ClaimNumber)
            .Select(t => new ReviewTaskResult(t.TaskId, t.Claim.ClaimNumber, t.Queue.QueueName, t.Priority, t.DueDate,
                t.AssignedToUser == null ? null : t.AssignedToUser.Username,
                t.LockedByUser == null ? null : t.LockedByUser.Username, t.LockExpiresOn)).FirstOrDefaultAsync(ct);
    }

    public async Task<ReviewTaskResult> ReviewAsync(int taskId, string username, CancellationToken ct)
    {
        var user = await User(username, ct); var now = UtcNow();
        var task = await _db.ReviewTasks.Include(t => t.Claim).Include(t => t.Queue).Include(t => t.AssignedToUser).FirstOrDefaultAsync(t => t.TaskId == taskId, ct)
            ?? throw new KeyNotFoundException("Review task was not found.");
        if (task.Status != "Open") throw new InvalidOperationException("Task is already closed.");
        if (task.AssignedToUserId.HasValue && task.AssignedToUserId.Value != user.UserId) throw new InvalidOperationException("Task is assigned to another reviewer.");
        if (task.LockedByUserId.HasValue && task.LockedByUserId.Value != user.UserId && task.LockExpiresOn.HasValue && task.LockExpiresOn.Value >= now) throw new LockConflictException("Task is currently locked by another reviewer.");
        task.LockedByUserId = user.UserId; task.LockedOn = now; task.LockExpiresOn = now.AddMinutes(_config.GetValue("LockSettings:DurationMinutes", 15));
        _db.ReviewTaskEvents.Add(new ReviewTaskEvent { TaskId = task.TaskId, ClaimId = task.ClaimId, QueueId = task.QueueId, UserId = user.UserId, EventType = "ReviewAcquired", EventAt = now, ActiveFrom = now });
        try { await _db.SaveChangesAsync(ct); }
        catch (DbUpdateConcurrencyException) { throw new LockConflictException("Another reviewer acquired this task first."); }
        return new ReviewTaskResult(task.TaskId, task.Claim.ClaimNumber, task.Queue.QueueName, task.Priority, task.DueDate, task.AssignedToUser?.Username, username, task.LockExpiresOn);
    }



    public async Task ReleaseAsync(
    int taskId,
    string username,
    CancellationToken ct)
    {
        var user = await User(username, ct);

        var task = await _db.ReviewTasks
            .FirstOrDefaultAsync(t => t.TaskId == taskId, ct);

        if (task == null)
            throw new KeyNotFoundException("Review task was not found.");

        if (task.Status != "Open")
            throw new InvalidOperationException("Task is already closed.");

        if (task.LockedByUserId != user.UserId)
            throw new InvalidOperationException(
                "Only the reviewer holding the lock can release this task.");

        // Save the value before clearing the lock.
        var lockedOn = task.LockedOn;
        var now = UtcNow();

        task.LockedByUserId = null;
        task.LockedOn = null;
        task.LockExpiresOn = null;

        _db.ReviewTaskEvents.Add(new ReviewTaskEvent
        {
            TaskId = task.TaskId,
            ClaimId = task.ClaimId,
            QueueId = task.QueueId,
            UserId = user.UserId,
            EventType = "Released",
            EventAt = now,
            ActiveFrom = lockedOn,
            ActiveTo = now
        });

        await _db.SaveChangesAsync(ct);
    }
    public async Task ForwardAsync(
        int taskId,
        string username,
        string targetUsername,
        CancellationToken ct)
    {
        var user = await User(username, ct);
        var target = await User(targetUsername, ct);

        var task = await _db.ReviewTasks
            .FirstOrDefaultAsync(t => t.TaskId == taskId, ct);

        if (task == null)
            throw new KeyNotFoundException("Review task was not found.");

        if (task.Status != "Open")
            throw new InvalidOperationException("Task is already closed.");

        if (task.LockedByUserId != user.UserId)
            throw new InvalidOperationException(
                "Task must be locked by the forwarding reviewer.");

        if (target.Role != "Reviewer")
            throw new InvalidOperationException(
                "The target user must be a reviewer.");

        if (target.UserId == user.UserId)
            throw new InvalidOperationException(
                "A task cannot be forwarded to the same reviewer.");

        var now = UtcNow();

        task.AssignedToUserId = target.UserId;
        task.AssignedByUserId = user.UserId;

        // Forwarding releases the current user's lock.
        task.LockedByUserId = null;
        task.LockedOn = null;
        task.LockExpiresOn = null;

        _db.ReviewTaskEvents.Add(new ReviewTaskEvent
        {
            TaskId = taskId,
            ClaimId = task.ClaimId,
            QueueId = task.QueueId,
            UserId = user.UserId,
            EventType = "Forwarded",
            EventAt = now,
            Note = "Forwarded to " + target.Username
        });

        await _db.SaveChangesAsync(ct);
    }

    public async Task CompleteAsync(
        int taskId,
        string username,
        CompleteRequest request,
        CancellationToken ct)
    {
        var user = await User(username, ct);

        var task = await _db.ReviewTasks
            .FirstOrDefaultAsync(t => t.TaskId == taskId, ct);

        if (task == null)
            throw new KeyNotFoundException("Review task was not found.");

        if (task.Status != "Open")
            throw new InvalidOperationException("Task is already closed.");

        var now = UtcNow();

        if (task.LockedByUserId != user.UserId)
            throw new InvalidOperationException(
                "Task must have an active lock held by the caller.");

        if (!task.LockExpiresOn.HasValue ||
            task.LockExpiresOn.Value < now)
            throw new InvalidOperationException(
                "The task lock has expired. Please review the task again.");

        if (request == null ||
            string.IsNullOrWhiteSpace(request.Outcome))
            throw new ArgumentException("Outcome is required.");

        var outcome = request.Outcome.Trim();

        await using var tx =
            await _db.Database.BeginTransactionAsync(ct);

        if (outcome.Equals("Pend", StringComparison.OrdinalIgnoreCase))
        {
            var pend = await _db.Queues
                .SingleOrDefaultAsync(q => q.QueueCode == "PEND", ct);

            if (pend == null)
                throw new KeyNotFoundException(
                    "Pend queue was not found.");

            task.QueueId = pend.QueueId;
            task.Outcome = "Pend";
            task.Note = request.Note;

            task.LockedByUserId = null;
            task.LockedOn = null;
            task.LockExpiresOn = null;

            _db.ReviewTaskEvents.Add(new ReviewTaskEvent
            {
                TaskId = task.TaskId,
                ClaimId = task.ClaimId,
                QueueId = pend.QueueId,
                UserId = user.UserId,
                EventType = "Pended",
                Outcome = "Pend",
                Note = request.Note,
                EventAt = now
            });
        }
        else
        {
            string completedOutcome;

            if (outcome.Equals("Approve",
                StringComparison.OrdinalIgnoreCase))
            {
                completedOutcome = "Approve";
            }
            else if (outcome.Equals("PartialDenial",
                StringComparison.OrdinalIgnoreCase))
            {
                completedOutcome = "PartialDenial";
            }
            else if (outcome.Equals("Deny",
                StringComparison.OrdinalIgnoreCase))
            {
                completedOutcome = "Deny";
            }
            else
            {
                throw new ArgumentException(
                    "Outcome must be Approve, PartialDenial, Deny or Pend.");
            }

            var originalQueueId = task.QueueId;

            task.Status = "Closed";
            task.Outcome = completedOutcome;
            task.ClosedAt = now;
            task.ClosedByUserId = user.UserId;
            task.Note = request.Note;

            task.LockedByUserId = null;
            task.LockedOn = null;
            task.LockExpiresOn = null;

            _db.ReviewTaskEvents.Add(new ReviewTaskEvent
            {
                TaskId = task.TaskId,
                ClaimId = task.ClaimId,
                QueueId = originalQueueId,
                UserId = user.UserId,
                EventType = "Completed",
                Outcome = completedOutcome,
                Note = request.Note,
                EventAt = now
            });

            // Deny closes all other open review tasks
            // belonging to the same claim.
            if (completedOutcome == "Deny")
            {
                var siblings = await _db.ReviewTasks
                    .Where(t =>
                        t.ClaimId == task.ClaimId &&
                        t.TaskId != task.TaskId &&
                        t.Status == "Open")
                    .ToListAsync(ct);

                foreach (var sibling in siblings)
                {
                    sibling.Status = "Closed";
                    sibling.Outcome = "SystemClosed";
                    sibling.ClosedAt = now;
                    sibling.ClosedByUserId = null;

                    sibling.LockedByUserId = null;
                    sibling.LockedOn = null;
                    sibling.LockExpiresOn = null;

                    _db.ReviewTaskEvents.Add(new ReviewTaskEvent
                    {
                        TaskId = sibling.TaskId,
                        ClaimId = sibling.ClaimId,
                        QueueId = sibling.QueueId,
                        UserId = user.UserId,
                        EventType = "SystemClosed",
                        Outcome = "SystemClosed",
                        Note = "Closed by denial on task " +
                               taskId + ".",
                        EventAt = now
                    });
                }
            }
        }

        await _db.SaveChangesAsync(ct);
        await tx.CommitAsync(ct);
    }
}

public class LockConflictException : Exception { public LockConflictException(string message) : base(message) { } }
