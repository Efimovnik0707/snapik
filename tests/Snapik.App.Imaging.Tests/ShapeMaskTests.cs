using Snapik.App.Imaging;
using Snapik.Core.Models;

namespace Snapik.App.Imaging.Tests;

public sealed class ShapeMaskTests
{
    [Fact]
    public void Coverage_OfARectangleIsWholeEverywhereInItsBox()
    {
        Assert.Equal(1, ShapeMask.Coverage(AnnotationShape.Rectangle, 100, 60, 0, 0));
        Assert.Equal(1, ShapeMask.Coverage(AnnotationShape.Rectangle, 100, 60, 50, 30));
        Assert.Equal(1, ShapeMask.Coverage(AnnotationShape.Rectangle, 100, 60, 99, 59));
    }

    [Fact]
    public void Coverage_OfAnEllipseIsWholeInTheCentreAndNoneInTheCornerOfItsBox()
    {
        Assert.Equal(1, ShapeMask.Coverage(AnnotationShape.Ellipse, 100, 60, 50, 30));
        Assert.Equal(0, ShapeMask.Coverage(AnnotationShape.Ellipse, 100, 60, 0, 0));
        Assert.Equal(0, ShapeMask.Coverage(AnnotationShape.Ellipse, 100, 60, 99, 59));
    }

    [Fact]
    public void Coverage_OfAnEllipseFadesOverOnePixelAtItsEdge()
    {
        // The edge is smoothed by the signed distance, so an oval blur does not come out jagged: the
        // partly covered pixels form a band one pixel wide along the outline, and nowhere else.
        var partial = (from y in Enumerable.Range(0, 60)
                       from x in Enumerable.Range(0, 100)
                       select ShapeMask.Coverage(AnnotationShape.Ellipse, 100, 60, x, y))
            .Count(coverage => coverage > 0.05 && coverage < 0.95);
        Assert.InRange(partial, 60, 600);
    }

    [Fact]
    public void Coverage_OfARoundedFrameCutsOnlyItsCorners()
    {
        Assert.Equal(1, ShapeMask.Coverage(AnnotationShape.Rounded, 100, 60, 50, 30));
        // The middle of every side stays inside, only the corners are taken away.
        Assert.Equal(1, ShapeMask.Coverage(AnnotationShape.Rounded, 100, 60, 50, 0));
        Assert.Equal(1, ShapeMask.Coverage(AnnotationShape.Rounded, 100, 60, 0, 30));
        Assert.Equal(0, ShapeMask.Coverage(AnnotationShape.Rounded, 100, 60, 0, 0));
    }

    [Theory]
    [InlineData(100, 60, 14)]
    [InlineData(40, 20, 5)]
    [InlineData(8, 200, 2)]
    public void CornerRadius_FollowsTheShorterSideUpToFourteenPixels(double width, double height, double expected) =>
        Assert.Equal(expected, ShapeMask.CornerRadius(width, height));

    [Fact]
    public void Coverage_OfAnEmptyBoxIsNone()
    {
        Assert.Equal(0, ShapeMask.Coverage(AnnotationShape.Ellipse, 0, 60, 0, 0));
        Assert.Equal(0, ShapeMask.Coverage(AnnotationShape.Rectangle, 100, 0, 0, 0));
    }
}
