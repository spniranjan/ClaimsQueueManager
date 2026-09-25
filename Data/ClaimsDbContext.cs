using ClaimsQueueManager.Models;
using Microsoft.EntityFrameworkCore;

namespace ClaimsQueueManager.Data;

public class ClaimsDbContext : DbContext
{
    public ClaimsDbContext(DbContextOptions<ClaimsDbContext> options) : base(options) { }
    public DbSet<QueueEntity> Queues => Set<QueueEntity>();
    public DbSet<AppUser> AppUsers => Set<AppUser>();
    public DbSet<Claim> Claims => Set<Claim>();
    public DbSet<ReviewTask> ReviewTasks => Set<ReviewTask>();
    public DbSet<UserSession> UserSessions => Set<UserSession>();
    public DbSet<ReviewTaskEvent> ReviewTaskEvents => Set<ReviewTaskEvent>();

    protected override void OnModelCreating(ModelBuilder b)
    {
        b.Entity<QueueEntity>(e => { e.ToTable("queue"); e.HasKey(x => x.QueueId); e.Property(x => x.QueueId).HasColumnName("queue_id"); e.Property(x => x.QueueCode).HasColumnName("queue_code").HasMaxLength(20).IsUnicode(false); e.Property(x => x.QueueName).HasColumnName("queue_name").HasMaxLength(100); });
        b.Entity<AppUser>(e => { e.ToTable("app_user"); e.HasKey(x => x.UserId); e.Property(x => x.UserId).HasColumnName("user_id"); e.Property(x => x.Username).HasColumnName("username").HasMaxLength(50).IsUnicode(false); e.Property(x => x.DisplayName).HasColumnName("display_name").HasMaxLength(100); e.Property(x => x.Role).HasColumnName("role").HasMaxLength(20).IsUnicode(false); });
        b.Entity<Claim>(e => { e.ToTable("claim"); e.HasKey(x => x.ClaimId); e.Property(x => x.ClaimId).HasColumnName("claim_id"); e.Property(x => x.ClaimNumber).HasColumnName("claim_number").HasMaxLength(10).IsFixedLength().IsUnicode(false); e.Property(x => x.MemberId).HasColumnName("member_id").HasMaxLength(20).IsUnicode(false); e.Property(x => x.ProviderId).HasColumnName("provider_id").HasMaxLength(20).IsUnicode(false); e.Property(x => x.BilledAmount).HasColumnName("billed_amount").HasPrecision(12,2); e.Property(x => x.ServiceFrom).HasColumnName("service_from").HasColumnType("date"); e.Property(x => x.ServiceTo).HasColumnName("service_to").HasColumnType("date"); e.Property(x => x.ReceivedOn).HasColumnName("received_on"); });
        b.Entity<ReviewTask>(e =>
        {
            e.ToTable("review_task"); e.HasKey(x => x.TaskId); e.Property(x => x.TaskId).HasColumnName("task_id"); e.Property(x => x.ClaimId).HasColumnName("claim_id"); e.Property(x => x.QueueId).HasColumnName("queue_id"); e.Property(x => x.Priority).HasColumnName("priority"); e.Property(x => x.DueDate).HasColumnName("due_date"); e.Property(x => x.AssignedToUserId).HasColumnName("assigned_to_user_id"); e.Property(x => x.AssignedByUserId).HasColumnName("assigned_by_user_id"); e.Property(x => x.Status).HasColumnName("status").HasMaxLength(20).IsUnicode(false); e.Property(x => x.Outcome).HasColumnName("outcome").HasMaxLength(30).IsUnicode(false); e.Property(x => x.LockedByUserId).HasColumnName("locked_by_user_id"); e.Property(x => x.LockedOn).HasColumnName("locked_on"); e.Property(x => x.LockExpiresOn).HasColumnName("lock_expires_on"); e.Property(x => x.CreatedAt).HasColumnName("created_at"); e.Property(x => x.ClosedAt).HasColumnName("closed_at"); e.Property(x => x.ClosedByUserId).HasColumnName("closed_by_user_id"); e.Property(x => x.Note).HasColumnName("note").HasMaxLength(500); e.Property(x => x.RowVersion).HasColumnName("row_version").IsRowVersion().IsConcurrencyToken();
            e.HasOne(x => x.Claim).WithMany(x => x.ReviewTasks).HasForeignKey(x => x.ClaimId).OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.Queue).WithMany(x => x.ReviewTasks).HasForeignKey(x => x.QueueId).OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.AssignedToUser).WithMany().HasForeignKey(x => x.AssignedToUserId).OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.AssignedByUser).WithMany().HasForeignKey(x => x.AssignedByUserId).OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.LockedByUser).WithMany().HasForeignKey(x => x.LockedByUserId).OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.ClosedByUser).WithMany().HasForeignKey(x => x.ClosedByUserId).OnDelete(DeleteBehavior.Restrict);
            e.HasIndex(x => new { x.QueueId, x.Status, x.Priority, x.DueDate, x.ClaimId }).HasDatabaseName("IX_review_task_GetNext");
            e.HasIndex(x => new { x.ClaimId, x.Status }).HasDatabaseName("IX_review_task_ClaimStatus");
        });
        b.Entity<UserSession>(e => { e.ToTable("user_session"); e.HasKey(x => x.SessionId); e.Property(x => x.SessionId).HasColumnName("session_id"); e.Property(x => x.UserId).HasColumnName("user_id"); e.Property(x => x.StartedAt).HasColumnName("started_at"); e.Property(x => x.EndedAt).HasColumnName("ended_at"); });
        b.Entity<ReviewTaskEvent>(e => { e.ToTable("review_task_event"); e.HasKey(x => x.EventId); e.Property(x => x.EventId).HasColumnName("event_id"); e.Property(x => x.TaskId).HasColumnName("task_id"); e.Property(x => x.ClaimId).HasColumnName("claim_id"); e.Property(x => x.QueueId).HasColumnName("queue_id"); e.Property(x => x.UserId).HasColumnName("user_id"); e.Property(x => x.EventType).HasColumnName("event_type").HasMaxLength(40).IsUnicode(false); e.Property(x => x.Outcome).HasColumnName("outcome").HasMaxLength(30).IsUnicode(false); e.Property(x => x.Note).HasColumnName("note").HasMaxLength(500); e.Property(x => x.EventAt).HasColumnName("event_at"); e.Property(x => x.ActiveFrom).HasColumnName("active_from"); e.Property(x => x.ActiveTo).HasColumnName("active_to"); e.HasIndex(x => new { x.TaskId, x.EventType, x.EventAt }); e.HasIndex(x => new { x.UserId, x.EventType, x.EventAt }); });
    }
}
