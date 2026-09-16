using System.Windows.Media;
using Snapik.App.Controls;
using Snapik.Core.Models;

namespace Snapik.App.Imaging.Tests;

// The rules a mark keeps away from the canvas, so that both renderers answer the same.
public sealed class AnnotationRulesTests
{
    private static readonly Color Stroke = Color.FromRgb(0xFF, 0x3B, 0x30);

    [Fact]
    public void The_outline_keeps_the_colour_of_the_mark_whatever_stands_inside_it()
    {
        Assert.Equal(Stroke, AnnotationRules.OutlineColorOf(AnnotationFill.None, Stroke));
        Assert.Equal(Stroke, AnnotationRules.OutlineColorOf(AnnotationFill.Solid, Stroke));
        Assert.Equal(Stroke, AnnotationRules.OutlineColorOf(AnnotationFill.Translucent, Stroke));
        // A blurred region has no outline at all.
        Assert.Null(AnnotationRules.OutlineColorOf(AnnotationFill.Blur, Stroke));
    }
}
