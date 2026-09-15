using System.Text;
using Snapik.App;

namespace Snapik.App.Imaging.Tests;

public sealed class SingleInstanceActivationTests
{
    [Fact]
    public void ProtocolAcceptsOnlyExactShowCommand()
    {
        Assert.True(SingleInstanceActivation.IsShowCommand(Encoding.ASCII.GetBytes("SHOW\n")));
        Assert.False(SingleInstanceActivation.IsShowCommand(Encoding.ASCII.GetBytes("SHOW")));
        Assert.False(SingleInstanceActivation.IsShowCommand(Encoding.ASCII.GetBytes("SHOW\r\n")));
        Assert.False(SingleInstanceActivation.IsShowCommand(Encoding.ASCII.GetBytes("SHOW\nanything")));
        Assert.False(SingleInstanceActivation.IsShowCommand(Encoding.ASCII.GetBytes("OPEN\n")));
    }

    [Fact]
    public void PipeIsRestrictedToCurrentUser() =>
        Assert.True(SingleInstanceActivation.UsesCurrentUserOnly);
}
