using System.Windows;
using SnapBrief.App;

namespace SnapBrief.App.Imaging.Tests;

// The box of a caption is measured, not guessed: everything that finds a mark under the pointer
// works on these numbers, and they are the same numbers the export draws with.
public sealed class TextMarkMetricsTests
{
    [Fact]
    public void Measure_GivesAWideBoxForAWordAndAtLeastTheHeightOfTheLetters()
    {
        var size = TextMarkMetrics.Measure("Привет", 32);

        Assert.True(size.Width > size.Height, $"A word must be wider than it is tall, it measured {size.Width}x{size.Height}.");
        Assert.True(size.Height >= 32);
    }

    [Fact]
    public void Measure_ReadsCyrillicAndLatinAlike()
    {
        var cyrillic = TextMarkMetrics.Measure("Привет", 20);
        var latin = TextMarkMetrics.Measure("Hello", 20);

        Assert.True(cyrillic.Width > 0);
        Assert.True(latin.Width > 0);
        Assert.True(TextMarkMetrics.Measure("Привет, мир", 20).Width > cyrillic.Width);
    }

    [Fact]
    public void Measure_OfNothingIsStillABoxWithRoomForACaret()
    {
        var size = TextMarkMetrics.Measure(string.Empty, 20);

        Assert.True(size.Width > 0);
        Assert.True(size.Height >= 20);
    }

    [Fact]
    public void Measure_GrowsWithTheSizeOfTheLetters()
    {
        Assert.True(TextMarkMetrics.Measure("Привет", 48).Width > TextMarkMetrics.Measure("Привет", 16).Width);
    }

    [Theory]
    [InlineData(0, TextMarkMetrics.MinimumFontSize)]
    [InlineData(4, TextMarkMetrics.MinimumFontSize)]
    [InlineData(20, 20)]
    [InlineData(400, TextMarkMetrics.MaximumFontSize)]
    public void Clamp_BringsASizeNobodyCanDrawBackIntoRange(double stored, double expected)
    {
        Assert.Equal(expected, TextMarkMetrics.Clamp(stored));
    }

    [Fact]
    public void Clamp_TakesANumberThatIsNotANumberBackToTheDefault()
    {
        Assert.Equal(TextMarkMetrics.DefaultFontSize, TextMarkMetrics.Clamp(double.NaN));
        Assert.Equal(TextMarkMetrics.DefaultFontSize, TextMarkMetrics.Clamp(double.PositiveInfinity));
    }

    [Fact]
    public void Fit_PutsTheSecondPointRightOfAndBelowTheAnchorWithoutMovingIt()
    {
        var mark = new AnnotationItem { Kind = EditorTool.Text, Points = [new Point(40, 60)], Text = "Привет", FontSize = 24 };

        TextMarkMetrics.Fit(mark);

        Assert.Equal(new Point(40, 60), mark.Points[0]);
        Assert.Equal(2, mark.Points.Count);
        Assert.True(mark.Points[1].X > mark.Points[0].X);
        Assert.True(mark.Points[1].Y > mark.Points[0].Y);
    }

    [Fact]
    public void Fit_FollowsTheSizeOfTheLettersAndTheirNumber()
    {
        var small = new AnnotationItem { Kind = EditorTool.Text, Points = [new Point(0, 0)], Text = "Привет", FontSize = 12 };
        var large = new AnnotationItem { Kind = EditorTool.Text, Points = [new Point(0, 0)], Text = "Привет", FontSize = 48 };
        var longer = new AnnotationItem { Kind = EditorTool.Text, Points = [new Point(0, 0)], Text = "Привет, мир", FontSize = 12 };

        TextMarkMetrics.Fit(small);
        TextMarkMetrics.Fit(large);
        TextMarkMetrics.Fit(longer);

        Assert.True(large.Points[1].Y > small.Points[1].Y);
        Assert.True(longer.Points[1].X > small.Points[1].X);
    }

    // Every field of a mark has to survive a copy, and this one is the newest of them: a field the
    // clone forgets is a field that disappears on the first undo.
    [Fact]
    public void A_copy_of_a_mark_keeps_the_pattern_of_its_stroke()
    {
        var dashed = new AnnotationItem
        {
            Kind = EditorTool.Rectangle,
            Points = [new Point(10, 10), new Point(80, 40)],
            LineStyle = SnapBrief.Core.Models.AnnotationLineStyle.Dashed
        };

        Assert.Equal(SnapBrief.Core.Models.AnnotationLineStyle.Dashed, dashed.Clone().LineStyle);
        // And the way to the session and back is the same two steps the editor takes.
        var core = dashed.ToCore(800, 600);
        Assert.Equal(SnapBrief.Core.Models.AnnotationLineStyle.Dashed, core.LineStyle);
        Assert.Equal(SnapBrief.Core.Models.AnnotationLineStyle.Dashed, AnnotationItem.FromCore(core, 800, 600).LineStyle);
    }

    [Fact]
    public void Fit_LeavesAMarkThatIsNotACaptionAlone()
    {
        var frame = new AnnotationItem { Kind = EditorTool.Rectangle, Points = [new Point(10, 10), new Point(80, 40)] };

        TextMarkMetrics.Fit(frame);

        Assert.Equal(new Point(80, 40), frame.Points[1]);
    }
}
