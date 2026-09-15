using System.Windows.Media;
using Snapik.App;
using Snapik.Core.Models;
using CoreAnnotation = Snapik.Core.Models.AnnotationItem;

namespace Snapik.App.Imaging.Tests;

// "hasOutline" is read but never written any more: false on a rectangle means "a solid fill of one
// colour", and everywhere else the field is ignored.
public sealed class LegacyOutlineTests
{
    private static CoreAnnotation Legacy(AnnotationKind kind, bool? hasOutline, string? fillColor = null) =>
        CoreAnnotation.Create(kind, [new NormalizedPoint(0.1, 0.1), new NormalizedPoint(0.4, 0.4)], strokeColor: "#FFFF3B30") with
        {
            LegacyHasOutline = hasOutline,
            FillColor = fillColor
        };

    [Fact]
    public void A_frame_written_without_an_outline_takes_the_colour_of_its_stroke()
    {
        var mark = AnnotationItem.FromCore(Legacy(AnnotationKind.Rectangle, false), 1000, 800);

        Assert.Equal(AnnotationFill.Solid, mark.Fill);
        Assert.Equal(Color.FromRgb(0xFF, 0x3B, 0x30), mark.FillColor);
    }

    [Fact]
    public void A_frame_written_without_an_outline_keeps_a_fill_colour_of_its_own()
    {
        var mark = AnnotationItem.FromCore(Legacy(AnnotationKind.Rectangle, false, "#FF101820"), 1000, 800);

        Assert.Equal(AnnotationFill.Solid, mark.Fill);
        Assert.Equal(Color.FromRgb(0x10, 0x18, 0x20), mark.FillColor);
    }

    [Theory]
    [InlineData(true)]
    [InlineData(null)]
    public void A_frame_with_the_flag_set_or_missing_reads_as_an_empty_one(bool? hasOutline)
    {
        var mark = AnnotationItem.FromCore(Legacy(AnnotationKind.Rectangle, hasOutline), 1000, 800);

        Assert.Equal(AnnotationFill.None, mark.Fill);
        Assert.Null(mark.FillColor);
    }

    [Fact]
    public void An_arrow_written_without_an_outline_is_left_alone()
    {
        var mark = AnnotationItem.FromCore(Legacy(AnnotationKind.Arrow, false), 1000, 800);

        Assert.Equal(EditorTool.Arrow, mark.Kind);
        Assert.Equal(AnnotationFill.None, mark.Fill);
        Assert.Null(mark.FillColor);
    }
}
