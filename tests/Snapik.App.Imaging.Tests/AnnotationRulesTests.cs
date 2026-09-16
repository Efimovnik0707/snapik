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

    [Fact]
    public void A_press_of_the_mouse_is_named_in_one_order_for_every_tool()
    {
        // A drag of the picture beats everything, and the two tools that draw over whatever lies
        // under them answer before the marks do.
        Assert.Equal(AnnotationRules.PressTarget.Pan, Target(EditorTool.Rectangle, panning: true, onObject: true));
        Assert.Equal(AnnotationRules.PressTarget.Erase, Target(EditorTool.Eraser, onObject: true));
        Assert.Equal(AnnotationRules.PressTarget.CropDraft, Target(EditorTool.Crop, onObject: true));
        // A caption and a comment open for typing on the second click; a frame is only selected.
        Assert.Equal(AnnotationRules.PressTarget.Activate, Target(EditorTool.Select, clickCount: 2, onObject: true, activatable: true));
        Assert.Equal(AnnotationRules.PressTarget.Object, Target(EditorTool.Select, clickCount: 2, onObject: true));
        // The anchor of a comment answers to any tool, then the corners of the selected mark.
        Assert.Equal(AnnotationRules.PressTarget.CommentAnchor, Target(EditorTool.Arrow, onAnchor: true, onObject: true));
        Assert.Equal(AnnotationRules.PressTarget.ResizeHandle, Target(EditorTool.Arrow, onSelectedHandle: true, onObject: true));
        Assert.Equal(AnnotationRules.PressTarget.Object, Target(EditorTool.Conceal, onObject: true));
        Assert.Equal(AnnotationRules.PressTarget.Empty, Target(EditorTool.Rectangle));
    }

    private static AnnotationRules.PressTarget Target(EditorTool tool, bool panning = false, int clickCount = 1,
        bool onAnchor = false, bool onSelectedHandle = false, bool onObject = false, bool activatable = false) =>
        AnnotationRules.PressTargetOf(tool, panning, clickCount, onAnchor, onSelectedHandle, onObject, activatable);
}
