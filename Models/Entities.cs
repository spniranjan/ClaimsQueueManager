namespace ClaimsQueueManager.Models;

public class QueueEntity
{
    public int QueueId { get; set; }
    public string QueueCode { get; set; } = null!;
    public string QueueName { get; set; } = null!;
    public ICollection<ReviewTask> ReviewTasks { get; set; } = new List<ReviewTask>();
}

public class AppUser
{
    public int UserId { get; set; }
    public string Username { get; set; } = null!;
    public string DisplayName { get; set; } = null!;
    public string Role { get; set; } = null!;
}

public class Claim
{
    public int ClaimId { get; set; }
    public string ClaimNumber { get; set; } = null!;
    public string MemberId { get; set; } = null!;
    public string ProviderId { get; set; } = null!;
    public decimal BilledAmount { get; set; }
    public DateTime ServiceFrom { get; set; }
    public DateTime ServiceTo { get; set; }
    public DateTime ReceivedOn { get; set; }
    public ICollection<ReviewTask> ReviewTasks { get; set; } = new List<ReviewTask>();
}

public class ReviewTask
{
    public int TaskId { get; set; }
    public int ClaimId { get; set; }
    public int QueueId { get; set; }
    public byte Priority { get; set; }
    public DateTime DueDate { get; set; }
    public int? AssignedToUserId { get; set; }
    public int? AssignedByUserId { get; set; }
    public string Status { get; set; } = null!;
    public string? Outcome { get; set; }
    public int? LockedByUserId { get; set; }
    public DateTime? LockedOn { get; set; }
    public DateTime? LockExpiresOn { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? ClosedAt { get; set; }
    public int? ClosedByUserId { get; set; }
    public string? Note { get; set; }
    public byte[] RowVersion { get; set; } = Array.Empty<byte>();

    public Claim Claim { get; set; } = null!;
    public QueueEntity Queue { get; set; } = null!;
    public AppUser? AssignedToUser { get; set; }
    public AppUser? AssignedByUser { get; set; }
    public AppUser? LockedByUser { get; set; }
    public AppUser? ClosedByUser { get; set; }
}

public class UserSession
{
    public int SessionId { get; set; }
    public int UserId { get; set; }
    public DateTime StartedAt { get; set; }
    public DateTime? EndedAt { get; set; }
}

public class ReviewTaskEvent
{
    public long EventId { get; set; }
    public int TaskId { get; set; }
    public int? ClaimId { get; set; }
    public int? QueueId { get; set; }
    public int? UserId { get; set; }
    public string EventType { get; set; } = null!;
    public string? Outcome { get; set; }
    public string? Note { get; set; }
    public DateTime EventAt { get; set; }
    public DateTime? ActiveFrom { get; set; }
    public DateTime? ActiveTo { get; set; }
}
