using System.Windows;
using SnapBrief.App.Controls;

namespace SnapBrief.App.Imaging.Tests;

public sealed class StripResizeGeometryTests
{
    [Fact]
    public void Dragging_the_left_edge_keeps_the_right_edge_where_it_was()
    {
        Assert.Equal((1620d, 300d), StripResizeGeometry.Resize(1920, 260, -40, 0));
        Assert.Equal((1700d, 220d), StripResizeGeometry.Resize(1920, 260, 40, 0));
    }

    [Theory]
    [InlineData(-1000, StripResizeGeometry.MaximumWidth)]
    [InlineData(1000, StripResizeGeometry.MinimumWidth)]
    public void The_width_stays_inside_its_range(double delta, double expected)
    {
        var (left, width) = StripResizeGeometry.Resize(1920, 260, delta, 0);

        Assert.Equal(expected, width);
        Assert.Equal(1920 - expected, left);
    }

    [Fact]
    public void The_strip_does_not_grow_past_the_left_edge_of_the_working_area()
    {
        var (left, width) = StripResizeGeometry.Resize(1500, 260, -1000, 1250);

        Assert.Equal(250, width);
        Assert.Equal(1250, left);
    }

    [Fact]
    public void A_working_area_of_a_scaled_monitor_is_read_in_window_units()
    {
        var area = StripResizeGeometry.ToDeviceIndependent(new Rect(1920, 0, 2560, 1400), 1.25, 1.25);

        Assert.Equal(new Rect(1536, 0, 2048, 1120), area);
        Assert.Equal(new Rect(0, 0, 1920, 1040), StripResizeGeometry.ToDeviceIndependent(new Rect(0, 0, 1920, 1040), 0, 0));
    }

    [Fact]
    public void Dragging_the_corner_down_grows_the_list_and_leaves_the_top_edge_alone()
    {
        // 100 of the working area below the strip is the chrome of the window, so the list may take
        // the rest of it; a drag of 60 px takes 60 px of that.
        Assert.Equal(432, StripResizeGeometry.ResizeListHeight(372, 60, 100, 200, 1040));
        Assert.Equal(312, StripResizeGeometry.ResizeListHeight(372, -60, 100, 200, 1040));
    }

    [Theory]
    [InlineData(-1000, StripResizeGeometry.MinimumListHeight)]
    [InlineData(1000, StripResizeGeometry.MaximumListHeight)]
    public void The_list_height_stays_inside_its_range(double delta, double expected) =>
        Assert.Equal(expected, StripResizeGeometry.ResizeListHeight(372, delta, 100, 0, 2000));

    [Fact]
    public void The_list_stops_at_the_bottom_of_the_working_area()
    {
        // 1040 - 700 - 140 = 200 left for the list, even though the drag and the range would allow more.
        Assert.Equal(200, StripResizeGeometry.ResizeListHeight(372, 500, 140, 700, 1040));
        // A strip that is already lower than its own chrome still gets a usable list.
        Assert.Equal(StripResizeGeometry.MinimumListHeight, StripResizeGeometry.ResizeListHeight(372, 500, 140, 1000, 1040));
    }

    [Theory]
    [InlineData(300, 1040, 130, 300)]
    [InlineData(40, 1040, 130, StripResizeGeometry.MinimumListHeight)]
    [InlineData(900, 1040, 130, StripResizeGeometry.MaximumListHeight)]
    [InlineData(900, 500, 130, 370)]
    [InlineData(double.NaN, 1040, 130, StripResizeGeometry.DefaultListHeight)]
    // A chrome taller than the screen still leaves a list somebody can use.
    [InlineData(600, 300, 400, StripResizeGeometry.MinimumListHeight)]
    // Nothing measured yet: the estimate stands in for the chrome.
    [InlineData(900, 728, 0, 728 - StripResizeGeometry.EstimatedChromeHeight)]
    public void A_stored_list_height_is_clamped_by_the_range_and_by_the_screen(double stored, double workHeight, double chrome, double expected) =>
        Assert.Equal(expected, StripResizeGeometry.ClampListHeight(stored, workHeight, chrome));

    [Fact]
    public void A_stored_list_height_leaves_room_for_the_chrome_of_the_window()
    {
        // The laptop of the report: a working area of 728 px and a height of 720 stored on a big
        // monitor. The window is the list plus its chrome, and all of it has to fit on the screen,
        // or the corner grip that would bring it back is below the bottom edge.
        const double chrome = 130;
        var height = StripResizeGeometry.ClampListHeight(StripResizeGeometry.MaximumListHeight, 728, chrome);

        Assert.Equal(598, height);
        Assert.True(height + chrome <= 728);
    }

    [Theory]
    [InlineData(240, 240)]
    [InlineData(40, StripResizeGeometry.MinimumWidth)]
    [InlineData(900, StripResizeGeometry.MaximumWidth)]
    [InlineData(double.NaN, StripResizeGeometry.DefaultWidth)]
    public void A_stored_width_is_clamped_and_nonsense_falls_back(double stored, double expected) =>
        Assert.Equal(expected, StripResizeGeometry.ClampWidth(stored));
}
