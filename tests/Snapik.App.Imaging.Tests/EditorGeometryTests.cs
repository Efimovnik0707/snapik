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
    public void A_capture_of_two_monitors_is_fitted_by_its_width() =>
        Assert.Equal(0.312, EditorGeometry.Fit(3840, 1125, BoxWidth, BoxHeight), 3);

    [Fact]
    public void A_tall_imported_file_is_fitted_by_its_height() =>
        Assert.Equal(0.247, EditorGeometry.Fit(1080, 2400, BoxWidth, BoxHeight), 3);

    [Fact]
    public void A_capture_smaller_than_the_box_is_not_scaled() =>
        Assert.Equal(1, EditorGeometry.Fit(100, 100, BoxWidth, BoxHeight));

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

    // The working area of a 1920x1080 monitor at 125 %, the one every number of this round was
    // written against, and the panel one row tall and two rows tall.
    private static readonly Rect Work = new(0, 0, 1536, 824);
    private static readonly Size OneRowPanel = new(1000, 50);
    private static readonly Size TwoRowPanel = new(780, 94);

    [Fact]
    public void A_capture_that_fits_under_the_panel_opens_at_its_own_size()
    {
        // 1420 fits 1536 - 16 and 700 fits 824 - 16 - 50 - 10: the capture that opened at 85 %.
        var placed = EditorGeometry.PlaceCapture(new Size(1420, 700), Work, OneRowPanel);
        Assert.Equal(new Size(1420, 700), placed.Size);
    }

    [Fact]
    public void A_capture_too_tall_for_the_room_left_by_the_panel_is_fitted_by_its_height()
    {
        var placed = EditorGeometry.PlaceCapture(new Size(1420, 900), Work, OneRowPanel);
        Assert.Equal(748, placed.Height, 3);
        Assert.Equal(1420 * (748d / 900), placed.Width, 3);
    }

    [Fact]
    public void A_capture_of_two_monitors_is_fitted_by_its_width_into_the_working_area()
    {
        var placed = EditorGeometry.PlaceCapture(new Size(3840, 1125), Work, OneRowPanel);
        Assert.Equal(1520, placed.Width, 3);
    }

    [Fact]
    public void A_second_row_of_the_panel_takes_the_capture_off_its_own_size()
    {
        // 720 fits under one row (824 - 16 - 50 - 10 = 748) and does not fit under two
        // (824 - 16 - 94 - 10 = 704), which is the honest border between the two shapes.
        Assert.Equal(new Size(1420, 720), EditorGeometry.PlaceCapture(new Size(1420, 720), Work, OneRowPanel).Size);
        Assert.True(EditorGeometry.PlaceCapture(new Size(1420, 720), Work, TwoRowPanel).Height < 720);
    }

    [Fact]
    public void The_comments_panel_takes_its_width_off_the_capture()
    {
        // The working area the editor counts with the comments panel out: 797 wide.
        var narrow = new Rect(0, 0, 797, 576);
        var placed = EditorGeometry.PlaceCapture(new Size(900, 400), narrow, OneRowPanel);
        Assert.True(placed.Width < 900);
        Assert.Equal(781, placed.Width, 3);
    }

    [Fact]
    public void The_capture_keeps_its_margin_and_the_room_the_panel_needs()
    {
        foreach (var image in new[] { new Size(1420, 700), new Size(3840, 1125), new Size(1080, 2400), new Size(80, 60) })
        {
            var placed = EditorGeometry.PlaceCapture(image, Work, OneRowPanel);
            Assert.True(placed.Left >= Work.Left - 0.001 && placed.Right <= Work.Right + 0.001);
            Assert.True(placed.Top >= Work.Top + 8 - 0.001);
            Assert.True(placed.Bottom + 10 + OneRowPanel.Height <= Work.Bottom + 0.001);
        }
    }

    [Theory]
    // The blocks of the reference shot: the tools, the properties block of a fixed 176 and the
    // buttons on the right. 1077 is the free width without the comments panel, 781 with it.
    [InlineData(1077, false)]
    [InlineData(781, true)]
    public void The_panel_wraps_only_when_one_row_does_not_fit(double freeWidth, bool twoRows) =>
        Assert.Equal(twoRows ? ToolbarRows.Two : ToolbarRows.One,
            ToolbarLayout.Measure(new Size(430, 36), new Size(176, 36), new Size(220, 36), freeWidth).Rows);

    [Fact]
    public void Two_rows_are_taller_by_a_row_and_the_gap_between_them()
    {
        var one = ToolbarLayout.Measure(new Size(430, 36), new Size(176, 36), new Size(220, 36), 1077);
        var two = ToolbarLayout.Measure(new Size(430, 36), new Size(176, 36), new Size(220, 36), 781);
        Assert.Equal(one.Size.Height + 36 + 7, two.Size.Height);
        Assert.True(two.Size.Width <= 781);
    }

    [Fact]
    public void The_number_of_rows_does_not_depend_on_the_tool_in_hand()
    {
        // The properties block is one width for every tool, so the shape of the panel is one too.
        foreach (var height in new[] { 30d, 36d, 40d })
            Assert.Equal(ToolbarRows.One,
                ToolbarLayout.Measure(new Size(430, 36), new Size(176, height), new Size(220, 36), 1077).Rows);
    }

    [Fact]
    public void A_panel_that_has_nowhere_outside_to_go_stays_off_the_capture_unless_it_may_overlap()
    {
        var work = new Rect(0, 0, 1536, 824);
        var crop = new Rect(0, 0, 1536, 824);
        var size = new Size(460, 50);
        Assert.False(ToolbarLayout.PlaceToolbar(crop, work, size, [], mayOverlap: false).IntersectsWith(new Rect(0, 0, 1536, 760)));
        Assert.True(ToolbarLayout.PlaceToolbar(crop, work, size, [], mayOverlap: true).IntersectsWith(crop));
    }

    [Fact]
    public void The_panel_goes_under_the_capture_while_there_is_room_for_it()
    {
        var work = new Rect(0, 0, 1920, 1080);
        var crop = new Rect(500, 400, 540, 120);
        var placed = ToolbarLayout.PlaceToolbar(crop, work, new Size(460, 50), [], mayOverlap: false);
        Assert.Equal(crop.Bottom + 10, placed.Top);
        Assert.False(placed.IntersectsWith(crop));
    }
}
