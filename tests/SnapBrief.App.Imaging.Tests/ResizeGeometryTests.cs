using System.Windows;
using SnapBrief.App.Controls;

namespace SnapBrief.App.Imaging.Tests;

public sealed class ResizeGeometryTests
{
    [Theory]
    [InlineData(0, 10, 15, 10, 15, 110, 105)]
    [InlineData(1, 180, 15, 20, 15, 160, 105)]
    [InlineData(2, 180, 170, 20, 30, 160, 140)]
    [InlineData(3, 10, 170, 10, 30, 110, 140)]
    public void EachCornerKeepsOppositeCornerFixed(int corner, double x, double y, double left, double top, double width, double height)
    {
        Assert.Equal(new Rect(left, top, width, height), ResizeGeometry.Resize(
            new Rect(20, 30, 100, 90), corner, new Point(x, y), new Rect(0, 0, 200, 200), 12));
    }

    [Fact]
    public void ResizeClampsToCapturedPixelsAndPreventsInversion()
    {
        var original = new Rect(20, 30, 100, 90);
        Assert.Equal(new Rect(20, 30, 180, 170), ResizeGeometry.Resize(original, 2, new Point(500, 500), new Rect(0, 0, 200, 200), 12));
        Assert.Equal(new Rect(108, 108, 12, 12), ResizeGeometry.Resize(original, 0, new Point(500, 500), new Rect(0, 0, 200, 200), 12));
    }

    [Fact]
    public void CornerHitUsesDisplayPixelsAndMapsAllPathPoints()
    {
        var original = new Rect(20, 30, 100, 90);
        Assert.Equal(0, ResizeGeometry.HitCorner(original, new Point(23, 33), 10));
        Assert.Equal(-1, ResizeGeometry.HitCorner(original, new Point(70, 75), 10));
        Assert.Equal(new Point(100, 100), ResizeGeometry.Map(new Point(70, 75), original, new Rect(0, 0, 200, 200)));
    }
}
