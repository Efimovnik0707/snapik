using System.Collections.Generic;
using System.Windows.Media;
using Snapik.App;
using Snapik.Core.Models;

namespace Snapik.App.Imaging.Tests;

// Every tool of the panel keeps its own colour, thickness and the rest, and the file they live in
// is still the file 1.5.0 reads: the old common keys are written beside the new dictionary.
public sealed class ToolAppearanceTests
{
    private static HotkeySettings Settings() => HotkeySettings.Default with
    {
        AnnotationColor = "#34C759",
        AnnotationThickness = 6,
        AnnotationHighlightThickness = 22,
        AnnotationFontSize = 28
    };

    [Fact]
    public void The_properties_block_shows_what_the_tool_has()
    {
        // The frames of the reference shot: what the block shows for each tool, and for which of
        // them it is there but dead.
        var expected = new Dictionary<EditorTool, InspectorView>
        {
            [EditorTool.Rectangle] = new(true, true, SecondCapsule.Line, true),
            [EditorTool.Arrow] = new(true, false, SecondCapsule.Line, true),
            [EditorTool.Pen] = new(true, false, SecondCapsule.Line, true),
            [EditorTool.Highlight] = new(true, false, SecondCapsule.Line, true),
            [EditorTool.Text] = new(true, false, SecondCapsule.FontSize, true),
            [EditorTool.Blur] = new(false, false, SecondCapsule.Shape, true),
            // No tool draws a conceal any more, but an old mark of one can be selected, and then the
            // block shows its fields, the way it does for any other filled region.
            [EditorTool.Conceal] = new(true, true, SecondCapsule.Line, true),
            [EditorTool.Comment] = new(true, true, SecondCapsule.Line, false),
            [EditorTool.Eraser] = new(true, true, SecondCapsule.Line, false),
            [EditorTool.Crop] = new(true, true, SecondCapsule.Line, false),
            [EditorTool.Select] = new(true, true, SecondCapsule.Line, false)
        };
        foreach (var (tool, view) in expected) Assert.Equal(view, EditorInspector.InspectorViewOf(tool));
    }

    [Fact]
    public void A_selected_mark_owns_the_block_and_an_empty_canvas_leaves_it_to_the_tool_in_hand()
    {
        var arrow = new AnnotationItem { Kind = EditorTool.Arrow };
        Assert.Equal(EditorTool.Arrow, EditorInspector.InspectedTool(arrow, EditorTool.Rectangle));
        Assert.Equal(EditorTool.Rectangle, EditorInspector.InspectedTool(null, EditorTool.Rectangle));
    }

    [Fact]
    public void A_file_without_the_new_key_hands_every_tool_the_old_common_values()
    {
        var tools = ToolAppearanceStore.Read(Settings());
        Assert.Equal(6, tools.Count);
        foreach (var tool in ToolAppearanceStore.Tools)
            Assert.Equal(Color.FromRgb(0x34, 0xC7, 0x59), tools[tool].Color);
        Assert.Equal(6, tools[EditorTool.Rectangle].Thickness);
        Assert.Equal(6, tools[EditorTool.Pen].Thickness);
        // The highlighter has a thickness of its own, and the caption a size of its own.
        Assert.Equal(22, tools[EditorTool.Highlight].Thickness);
        Assert.Equal(28, tools[EditorTool.Text].FontSize);
    }

    [Fact]
    public void A_file_with_the_new_key_is_read_by_it_and_a_tool_it_does_not_know_is_passed_over()
    {
        var settings = Settings() with
        {
            ToolAppearance = new Dictionary<string, ToolAppearanceEntry>
            {
                ["rectangle"] = new() { Color = "#FF3B30", Thickness = 9, LineStyle = "dashed", Fill = "translucent", FillColor = "#007AFF", Shape = "rounded" },
                ["highlight"] = new() { Color = "#FFCC00", Thickness = 16 },
                ["telepathy"] = new() { Color = "#000000" }
            }
        };
        var tools = ToolAppearanceStore.Read(settings);
        var frame = tools[EditorTool.Rectangle];
        Assert.Equal(Color.FromRgb(0xFF, 0x3B, 0x30), frame.Color);
        Assert.Equal(9, frame.Thickness);
        Assert.Equal(AnnotationLineStyle.Dashed, frame.LineStyle);
        Assert.Equal(AnnotationFill.Translucent, frame.Fill);
        Assert.Equal(Color.FromRgb(0x00, 0x7A, 0xFF), frame.FillColor);
        Assert.Equal(AnnotationShape.Rounded, frame.Shape);
        Assert.Equal(16, tools[EditorTool.Highlight].Thickness);
        // The tool without an entry falls back to the common keys, and the unknown one is dropped.
        Assert.Equal(6, tools[EditorTool.Pen].Thickness);
        Assert.Equal(6, tools.Count);
    }

    [Fact]
    public void What_was_written_comes_back_and_the_old_keys_mirror_the_frame()
    {
        // The scenario of the test report: a red dashed frame, a blue arrow, a yellow highlighter
        // and white letters, each with a number of its own.
        var written = new Dictionary<EditorTool, ToolAppearance>
        {
            [EditorTool.Rectangle] = new() { Color = Color.FromRgb(0xFF, 0x3B, 0x30), Thickness = 9, LineStyle = AnnotationLineStyle.Dashed, Fill = AnnotationFill.Translucent, Shape = AnnotationShape.Rounded },
            [EditorTool.Arrow] = new() { Color = Color.FromRgb(0x00, 0x7A, 0xFF), Thickness = 4, ArrowStyle = "curved" },
            [EditorTool.Pen] = new() { Color = Color.FromRgb(0xFF, 0x3B, 0x30), Thickness = 4 },
            [EditorTool.Highlight] = new() { Color = Color.FromRgb(0xFF, 0xCC, 0x00), Thickness = 16 },
            [EditorTool.Text] = new() { Color = Colors.White, FontSize = 32 },
            [EditorTool.Blur] = new() { Shape = AnnotationShape.Ellipse }
        };
        var saved = ToolAppearanceStore.Write(HotkeySettings.Default, written);
        // The mirror 1.5.0 reads.
        Assert.Equal("#FF3B30", saved.AnnotationColor);
        Assert.Equal(9, saved.AnnotationThickness);
        Assert.Equal(16, saved.AnnotationHighlightThickness);
        Assert.Equal(32, saved.AnnotationFontSize);
        var read = ToolAppearanceStore.Read(saved);
        foreach (var tool in ToolAppearanceStore.Tools)
            Assert.Equal(written[tool], read[tool]);
    }
}
