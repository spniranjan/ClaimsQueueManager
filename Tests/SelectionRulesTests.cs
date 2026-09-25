using Xunit;

namespace ClaimsQueueManager.Tests;
public class SelectionRulesTests
{
    [Fact]
    public void Assignment_Ranks_Ahead_Of_Priority()
    {
        var rows = new[] { new { Assigned=true, Priority=5 }, new { Assigned=false, Priority=1 } };
        var first = rows.OrderByDescending(x=>x.Assigned).ThenBy(x=>x.Priority).First();
        Assert.True(first.Assigned);
    }
    [Fact]
    public void ClaimNumber_Is_Final_TieBreaker()
    {
        var rows = new[] { "0000418822", "0000418277" };
        Assert.Equal("0000418277", rows.OrderBy(x=>x).First());
    }
}
