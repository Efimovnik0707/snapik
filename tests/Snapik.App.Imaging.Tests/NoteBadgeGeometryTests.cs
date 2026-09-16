using System.Collections.Generic;
using Snapik.App.Imaging;
using Snapik.Core.Models;

namespace Snapik.App.Imaging.Tests;

// The field the exported picture needs so that a badge dragged off the capture is not cut away.
public sealed class NoteBadgeGeometryTests
{
    private const int Side = 1000;

    // The badge of a one-digit number: 34 px across, so 17 of radius, and 8 of padding beside it.
    private const int Reach = 17 + 8;

    private static ExportMargin Margins(params (NormalizedPoint Anchor, NormalizedPoint? Offset, string Label)[] badges) =>
        NoteBadgeGeometry.ExportMargins(badges, Side, Side);

    [Fact]
    public void A_capture_without_badges_needs_no_field() =>
        Assert.True(NoteBadgeGeometry.ExportMargins(new List<(NormalizedPoint, NormalizedPoint?, string)>(), Side, Side).IsEmpty);

    [Fact]
    public void A_badge_left_where_it_was_born_needs_no_field() =>
        Assert.Equal(ExportMargin.None, Margins((new NormalizedPoint(0, 0.5), null, "1")));

    [Fact]
    public void A_badge_moved_inside_the_capture_needs_no_field() =>
        Assert.Equal(ExportMargin.None, Margins((new NormalizedPoint(0.4, 0.5), new NormalizedPoint(0.1, 0.1), "1")));

    [Fact]
    public void A_badge_dragged_off_the_left_edge_asks_for_a_field_on_the_left() =>
        Assert.Equal(new ExportMargin(100 + Reach, 0, 0, 0), Margins((new NormalizedPoint(0, 0.5), new NormalizedPoint(-0.1, 0), "1")));

    [Fact]
    public void A_badge_dragged_off_the_right_edge_asks_for_a_field_on_the_right() =>
        Assert.Equal(new ExportMargin(0, 0, 100 + Reach, 0), Margins((new NormalizedPoint(1, 0.5), new NormalizedPoint(0.1, 0), "1")));

    [Fact]
    public void A_badge_dragged_above_the_capture_asks_for_a_field_on_top() =>
        Assert.Equal(new ExportMargin(0, 100 + Reach, 0, 0), Margins((new NormalizedPoint(0.5, 0), new NormalizedPoint(0, -0.1), "1")));

    [Fact]
    public void Two_badges_pulled_apart_ask_for_a_field_on_both_sides() =>
        Assert.Equal(new ExportMargin(100 + Reach, 0, 50 + Reach, 0), Margins(
            (new NormalizedPoint(0, 0.5), new NormalizedPoint(-0.1, 0), "1"),
            (new NormalizedPoint(1, 0.5), new NormalizedPoint(0.05, 0), "2")));

    [Fact]
    public void A_comment_without_a_number_carries_no_badge_and_asks_for_nothing() =>
        Assert.Equal(ExportMargin.None, Margins((new NormalizedPoint(0, 0.5), new NormalizedPoint(-0.1, 0), "")));

    [Fact]
    public void A_longer_number_asks_for_a_wider_field()
    {
        var one = Margins((new NormalizedPoint(0, 0.5), new NormalizedPoint(-0.1, 0), "1"));
        // "10" is 9 px per character plus 16, which is still under the floor of 34; "1234567" is not.
        var many = Margins((new NormalizedPoint(0, 0.5), new NormalizedPoint(-0.1, 0), "1234567"));
        Assert.True(many.Left > one.Left);
    }
}
