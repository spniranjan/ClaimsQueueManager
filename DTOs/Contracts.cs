namespace ClaimsQueueManager.DTOs;

public record TaskListItem(int TaskId, string ClaimNumber, string Queue, byte Priority, DateTime DueDate,
    string? AssignedTo, string? AssignedBy, string? LockedBy, DateTime? LockedOn);

public record ReviewTaskResult(int TaskId, string ClaimNumber, string Queue, byte Priority, DateTime DueDate,
    string? AssignedTo, string? LockedBy, DateTime? LockExpiresOn);

public record ForwardRequest(string Username);
public record CompleteRequest(string Outcome, string? Note);
public record PagedResult<T>(IReadOnlyList<T> Items, int Page, int PageSize, int TotalCount);
