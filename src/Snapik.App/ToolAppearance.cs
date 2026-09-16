using System;
using System.Collections.Generic;
using System.Text.Json.Serialization;
using System.Windows.Media;
using Snapik.Core.Models;

namespace Snapik.App;

/// <summary>
/// What one tool of the markup panel is set to. Every tool keeps its own set, so a red dashed frame
/// and a yellow highlighter live side by side instead of overwriting one colour between them.
/// </summary>
internal sealed record ToolAppearance
{
    /// <summary>The red the panel starts with; <see cref="OverlayEditorWindow"/> holds the same one,
    /// and it is written here because the window it lives on cannot be reached from a test.</summary>
    internal static readonly Color DefaultColor = Color.FromRgb(255, 59, 48);
    internal const double DefaultThickness = 4;

    internal Color Color { get; init; } = DefaultColor;
    internal double Thickness { get; init; } = DefaultThickness;
    internal AnnotationLineStyle LineStyle { get; init; } = AnnotationLineStyle.Solid;
    internal AnnotationFill Fill { get; init; } = AnnotationFill.None;
    // null = "as the outline": the same meaning AnnotationItem.FillColor and session.json carry.
    internal Color? FillColor { get; init; }
    internal double FontSize { get; init; } = TextMarkMetrics.DefaultFontSize;
    internal string ArrowStyle { get; init; } = "straight";
    internal AnnotationShape Shape { get; init; } = AnnotationShape.Rectangle;
}

/// <summary>
/// The shape one tool takes in settings.json. A record of its own rather than
/// <see cref="ToolAppearance"/> itself: the file holds colours as "#RRGGBB" and enumerations by
/// their names, and the settings record is public while the appearance is not.
/// </summary>
public sealed record ToolAppearanceEntry
{
    [JsonPropertyName("color")] public string? Color { get; init; }
    [JsonPropertyName("thickness")] public double? Thickness { get; init; }
    [JsonPropertyName("lineStyle")] public string? LineStyle { get; init; }
    [JsonPropertyName("fill")] public string? Fill { get; init; }
    [JsonPropertyName("fillColor")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? FillColor { get; init; }
    [JsonPropertyName("fontSize")] public double? FontSize { get; init; }
    [JsonPropertyName("arrowStyle")] public string? ArrowStyle { get; init; }
    [JsonPropertyName("shape")] public string? Shape { get; init; }
}

/// <summary>
/// The settings file on one side and the six sets of the panel on the other. The old common keys
/// (<c>AnnotationColor</c> and the three beside it) stay and go on being written as a mirror of the
/// frame, the highlighter and the caption, so a file written here is read whole by 1.5.0; a file
/// without the new key hands every tool those same old values, and opens exactly as it looked.
/// </summary>
internal static class ToolAppearanceStore
{
    /// <summary>The six tools that carry settings of their own; the rest borrow the frame's.</summary>
    internal static readonly EditorTool[] Tools =
    [
        EditorTool.Rectangle, EditorTool.Arrow, EditorTool.Pen,
        EditorTool.Highlight, EditorTool.Text, EditorTool.Blur
    ];

    internal static Dictionary<EditorTool, ToolAppearance> Read(HotkeySettings settings)
    {
        var color = ParseColor(settings.AnnotationColor, ToolAppearance.DefaultColor);
        var kept = new Dictionary<EditorTool, ToolAppearance>();
        foreach (var tool in Tools)
            kept[tool] = new ToolAppearance
            {
                Color = color,
                Thickness = tool == EditorTool.Highlight ? settings.AnnotationHighlightThickness : settings.AnnotationThickness,
                FontSize = settings.AnnotationFontSize
            };
        if (settings.ToolAppearance is { Count: > 0 } stored)
            foreach (var pair in stored)
            {
                // A tool this build does not know, or a null entry left by a hand-edited file, is
                // passed over in silence: a file from a newer build must not break an older one.
                if (pair.Value is not { } entry || !TryParseTool(pair.Key, out var tool)) continue;
                kept[tool] = Apply(entry, kept[tool]);
            }
        return kept;
    }

    internal static HotkeySettings Write(HotkeySettings settings, IReadOnlyDictionary<EditorTool, ToolAppearance> tools)
    {
        var written = new Dictionary<string, ToolAppearanceEntry>(StringComparer.Ordinal);
        foreach (var tool in Tools)
            if (tools.TryGetValue(tool, out var kept)) written[NameOf(tool)] = EntryOf(kept);
        var mirrored = settings with { ToolAppearance = written };
        // The mirror 1.5.0 reads: the colour and the thickness of the frame, the thickness of the
        // highlighter and the size of the letters. A tool that is not handed over keeps its number.
        if (tools.TryGetValue(EditorTool.Rectangle, out var frame))
            mirrored = mirrored with { AnnotationColor = Hex(frame.Color), AnnotationThickness = frame.Thickness };
        if (tools.TryGetValue(EditorTool.Highlight, out var highlight))
            mirrored = mirrored with { AnnotationHighlightThickness = highlight.Thickness };
        if (tools.TryGetValue(EditorTool.Text, out var text))
            mirrored = mirrored with { AnnotationFontSize = text.FontSize };
        return mirrored;
    }

    private static ToolAppearance Apply(ToolAppearanceEntry entry, ToolAppearance fallback) => new()
    {
        Color = ParseColor(entry.Color, fallback.Color),
        Thickness = entry.Thickness is { } thickness && double.IsFinite(thickness) ? thickness : fallback.Thickness,
        LineStyle = ParseEnum(entry.LineStyle, fallback.LineStyle),
        Fill = ParseEnum(entry.Fill, fallback.Fill),
        FillColor = string.IsNullOrWhiteSpace(entry.FillColor) ? null : ParseColor(entry.FillColor, fallback.Color),
        FontSize = entry.FontSize is { } size && double.IsFinite(size) ? size : fallback.FontSize,
        ArrowStyle = string.IsNullOrWhiteSpace(entry.ArrowStyle) ? fallback.ArrowStyle : entry.ArrowStyle,
        Shape = ParseEnum(entry.Shape, fallback.Shape)
    };

    private static ToolAppearanceEntry EntryOf(ToolAppearance kept) => new()
    {
        Color = Hex(kept.Color),
        Thickness = kept.Thickness,
        LineStyle = NameOf(kept.LineStyle),
        Fill = NameOf(kept.Fill),
        FillColor = kept.FillColor is { } fill ? Hex(fill) : null,
        FontSize = kept.FontSize,
        ArrowStyle = kept.ArrowStyle,
        Shape = NameOf(kept.Shape)
    };

    private static bool TryParseTool(string? name, out EditorTool tool)
    {
        tool = default;
        if (!Enum.TryParse(name, ignoreCase: true, out EditorTool parsed)) return false;
        tool = parsed;
        return Array.IndexOf(Tools, parsed) >= 0;
    }

    private static TEnum ParseEnum<TEnum>(string? value, TEnum fallback) where TEnum : struct, Enum =>
        // A number is not a name: "2" in a hand-edited file falls back instead of picking a member.
        !string.IsNullOrWhiteSpace(value) && !char.IsDigit(value[0]) &&
        Enum.TryParse<TEnum>(value, ignoreCase: true, out var parsed) ? parsed : fallback;

    // The names of the enumeration members in camel case, the way the rest of the files write them.
    private static string NameOf<TEnum>(TEnum value) where TEnum : struct, Enum => CamelCase(value.ToString()!);

    private static string NameOf(EditorTool tool) => CamelCase(tool.ToString());

    private static string CamelCase(string name) => char.ToLowerInvariant(name[0]) + name[1..];

    private static string Hex(Color color) => $"#{color.R:X2}{color.G:X2}{color.B:X2}";

    private static Color ParseColor(string? value, Color fallback)
    {
        try { return !string.IsNullOrWhiteSpace(value) && ColorConverter.ConvertFromString(value) is Color color ? color : fallback; }
        catch (Exception) { return fallback; }
    }
}

/// <summary>Which capsule the properties block shows beside the colour of the tool in hand.</summary>
internal enum SecondCapsule { None, Line, FontSize, Shape }

/// <summary>What the properties block of the panel shows, and whether it answers at all.</summary>
internal readonly record struct InspectorView(bool Stroke, bool FillSwatch, SecondCapsule Second, bool Enabled);

/// <summary>
/// Whose settings the properties block shows, and which of them it shows. Two pure rules, away from
/// the window: the block is redrawn on every selection and on every tool, and both answers have to
/// be the same wherever they are asked for.
/// </summary>
internal static class EditorInspector
{
    internal static InspectorView InspectorViewOf(EditorTool tool) => tool switch
    {
        EditorTool.Rectangle => new(true, true, SecondCapsule.Line, true),
        EditorTool.Arrow => new(true, false, SecondCapsule.Line, true),
        EditorTool.Pen => new(true, false, SecondCapsule.Line, true),
        // The highlighter has a colour and a thickness; the pattern of a stroke it has none of.
        EditorTool.Highlight => new(true, false, SecondCapsule.Line, true),
        EditorTool.Text => new(true, false, SecondCapsule.FontSize, true),
        // The blur has a shape and nothing else: the colours are hidden, not switched off.
        EditorTool.Blur => new(false, false, SecondCapsule.Shape, true),
        // No tool of the panel draws a conceal any more, but a mark of one read out of an old
        // session can be selected, and then the block belongs to that mark: it is a filled region
        // and shows what a region shows. Reached through InspectedTool alone, never through a hand.
        EditorTool.Conceal => new(true, true, SecondCapsule.Line, true),
        // Select, eraser, crop and comment carry no settings, so the block is there but dead.
        _ => new(true, true, SecondCapsule.Line, false)
    };

    /// <summary>A mark that is selected owns the block; with nothing selected it is the tool in hand.</summary>
    internal static EditorTool InspectedTool(AnnotationItem? selected, EditorTool armed) => selected?.Kind ?? armed;
}
