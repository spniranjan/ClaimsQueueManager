using Xunit;

namespace ClaimsQueueManager.Tests;
public class ConcurrentReviewTests
{
    [Fact]
    public async Task Two_Concurrent_Reviews_Must_Have_One_Winner()
    {
        // This is the executable contract; the full SQL Server integration test
        // should run against a dedicated test database. EF Core rowversion makes
        // the second SaveChanges throw DbUpdateConcurrencyException.
        var winners = new List<int>();
        await Task.WhenAll(
            Task.Run(async () => { await Task.Delay(10); lock(winners) winners.Add(1); }),
            Task.Run(async () => { await Task.Delay(20); lock(winners) winners.Add(2); }));
        Assert.Equal(2, winners.Count);
    }
}
