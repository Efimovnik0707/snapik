using System.Windows;
using Snapik.App.Controls;

namespace Snapik.App.Imaging.Tests;

public sealed class EditorGeometryTests
{
    // The box is the one a 1920×1080 monitor at 125 % leaves the editor: 1198×593 device
    // independent units, the numbers the analysis of this round was written against.
    private const double BoxWidth = 1198;
    private const double BoxHeight = 593;

    [Fact]
    public void A_capture_of_two_monitors_is_fitted_by_its_width()
    {
        var fit = EditorGeometry.Fit(3840, 1125, BoxWidth, BoxHeight);
        Assert.Equal(FitBound.Width, fit.BoundBy);
        Assert.Equal(0.312, fit.Scale, 3);
    }

    [Fact]
    public void A_tall_imported_file_is_fitted_by_its_height()
    {
        var fit = EditorGeometry.Fit(1080, 2400, BoxWidth, BoxHeight);
        Assert.Equal(FitBound.Height, fit.BoundBy);
        Assert.Equal(0.247, fit.Scale, 3);
    }

    [Fact]
    public void A_capture_that_fits_as_it_is_has_nothing_to_switch_between()
    {
        var fit = EditorGeometry.Fit(100, 100, BoxWidth, BoxHeight);
        Assert.Equal(FitBound.None, fit.BoundBy);
        Assert.Equal(1, fit.Scale);
    }

    [Fact]
    public void The_offset_never_lets_an_edge_of_the_picture_inside_the_viewport()
    {
        var image = new Size(3840, 1125);
        var viewport = new Size(1200, 600);
        // Dragged past the left edge and past the right one: both stop where the picture ends.
        Assert.Equal(new Vector(0, 0), EditorGeometry.ClampOffset(image, 1, viewport, new Vector(-400, -400)));
        Assert.Equal(new Vector(2640, 525), EditorGeometry.ClampOffset(image, 1, viewport, new Vector(9000, 9000)));
        Assert.Equal(new Vector(1000, 300), EditorGeometry.ClampOffset(image, 1, viewport, new Vector(1000, 300)));
    }

    [Fact]
    public void An_axis_shorter_than_the_viewport_is_centred()
    {
        // 3840×1125 at a quarter is 960×281: both sides are shorter than the viewport, so whatever
        // the offset was, the picture stands in the middle of it.
        var offset = EditorGeometry.ClampOffset(new Size(3840, 1125), 0.25, new Size(1200, 600), new Vector(500, -500));
        Assert.Equal(new Vector(-120, -159.375), offset);
    }

    [Fact]
    public void The_point_under_the_cursor_stays_where_it_is_while_the_scale_changes()
    {
        var image = new Size(3840, 1125);
        // A viewport both sides of the picture are longer than: with an axis at its end the clamp
        // is what holds the picture, and the point under the cursor is allowed to travel.
        var viewport = new Size(1200, 400);
        var cursor = new Point(800, 200);
        var from = 0.5;
        var offset = EditorGeometry.ClampOffset(image, from, viewport, new Vector(400, 100));
        // The pixel of the capture the cursor stands on before the wheel is turned.
        var before = new Point((cursor.X + offset.X) / from, (cursor.Y + offset.Y) / from);
        var to = from * 1.1;
        var zoomed = EditorGeometry.ClampOffset(image, to, viewport, EditorGeometry.ZoomAround(cursor, offset, from, to));
        var after = new Point((cursor.X + zoomed.X) / to, (cursor.Y + zoomed.Y) / to);
        Assert.Equal(before.X, after.X, 1);
        Assert.Equal(before.Y, after.Y, 1);
        Assert.True((before - after).Length <= 0.5);
    }
}
