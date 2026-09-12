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

    [Theory]
    [InlineData(240, 240)]
    [InlineData(40, StripResizeGeometry.MinimumWidth)]
    [InlineData(900, StripResizeGeometry.MaximumWidth)]
    [InlineData(double.NaN, StripResizeGeometry.DefaultWidth)]
    public void A_stored_width_is_clamped_and_nonsense_falls_back(double stored, double expected) =>
        Assert.Equal(expected, StripResizeGeometry.ClampWidth(stored));
}
