using System;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;
using Snapik.Core.Models;

namespace Snapik.App;

public partial class OverlayEditorWindow
{
    private bool _syncingAppearance;
    private OverlaySnapshot? _appearanceBefore;
    private bool _appearanceChanged;
    private bool _appearanceDefaultsChanged;
    // Red, the first colour of the standard palette: on a clean install the active colour has to
    // belong to the palette, otherwise no swatch is circled.
    internal static readonly Color DefaultAnnotationColor = Color.FromRgb(255, 59, 48);
    internal const double DefaultAnnotationThickness = 4;
    // The highlighter is measured in tens of pixels, not in units of them: its width, its presets
    // and the range of its slider are its own, and the button on the panel shows whichever is armed.
    internal const double DefaultHighlightThickness = 16;
    internal const double MinimumHighlightThickness = 4;
    internal const double MaximumHighlightThickness = 48;
    internal static readonly double[] ThicknessPresets = [2, 4, 6, 8];
    // The same three patterns the renderers draw, in the units the shapes of WPF use for a dash
    // array: multiples of the thickness, exactly as DashStyle counts them.
    private static DoubleCollection? DashesOf(AnnotationLineStyle style) => style switch
    {
        AnnotationLineStyle.Dashed => [3, 2],
        AnnotationLineStyle.Dotted => [0, 2],
        _ => null
    };
    internal static readonly double[] HighlightThicknessPresets = [8, 12, 16, 24];
    // What a tool of the panel may be set to, and whether the block answers at all, is one table now
    // (EditorInspector.InspectorViewOf) instead of five predicates by tool. The one rule that is not
    // in it is the pattern of a stroke: the highlighter carries a width but no dashes, because a
    // dashed highlighter falls apart into blots, and the renderers ask StrokePattern the same way.

    // A palette is twelve colours, picked in the popover and remembered between captures; replacing
    // the colours of a set is one array and no code. The quick row of five dots that used to stand
    // on the panel is gone with the dots: the twelve swatches of the popover are the row now.
    internal sealed record PaletteSet(string Id, string NameKey, string[] Colors);

    internal static readonly PaletteSet[] Palettes =
    [
        new("standard", "Стандартная",
            ["#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#32ADE6", "#007AFF", "#AF52DE", "#FF2D55", "#FFFFFF", "#000000", "#8E8E93", "#A2845E"]),
        new("pastel", "Пастель",
            ["#2F8CFF", "#FF4D4F", "#FFBE2E", "#28BE80", "#AF81FF", "#FF79B7", "#FFFFFF", "#000000", "#00C8DC", "#FF8C42", "#9BA7B8", "#7754D9"]),
        // Back as the fourth set, with the twelve colours it carried before it was taken out to make
        // room for the own one: the reference of this round draws four segments, not three.
        new("neon", "Неон",
            ["#FF1744", "#FF6D00", "#FFEA00", "#C6FF00", "#00E676", "#1DE9B6", "#00E5FF", "#2979FF", "#651FFF", "#D500F9", "#FF4081", "#FFFFFF"]),
        // The own palette holds no colours of its own: they are the ones the user picked, they live
        // in the settings file, and PaletteFor puts them in.
        new("custom", "Своя", [])
    ];

    /// <summary>
    /// The palette a settings file stands for. Everything but the own one is a set written down
    /// above; the own one is built out of the colours the file carries, newest first, with the five
    /// newest of them as the quick row on the panel.
    /// </summary>
    internal static PaletteSet PaletteFor(HotkeySettings settings) =>
        ParseAnnotationPalette(settings.AnnotationPalette) is { Id: "custom" }
            ? CustomPalette(settings.CustomPaletteColors)
            : ParseAnnotationPalette(settings.AnnotationPalette);

    internal static PaletteSet CustomPalette(System.Collections.Generic.IEnumerable<string> colours) =>
        new("custom", "Своя", [.. colours.Take(HotkeySettings.MaxCustomPaletteColors)]);

    /// <summary>The colours of the own palette, newest first, as this window has them.</summary>
    private readonly System.Collections.Generic.List<string> _customColors = [];

    // Called from the constructor: the palette of the next capture is the one the file carries, and
    // the own colours come with it.
    private void InitializePalette(HotkeySettings preferences)
    {
        _customColors.AddRange(preferences.CustomPaletteColors);
        _activePalette = PaletteFor(preferences);
    }

    // The thickness the panel works on: the highlighter counts in tens of pixels, everything else
    // with a stroke in units of them.
    internal static double[] ThicknessPresetsFor(EditorTool tool) =>
        tool == EditorTool.Highlight ? HighlightThicknessPresets : ThicknessPresets;

    /// <summary>
    /// The settings the panel shows and edits for a tool. Select, Eraser, Crop and Comment have none
    /// of their own: the block is there but dead for them (InspectorViewOf → Enabled is false), and
    /// Surface.Active* go on carrying what the next mark will be drawn with, which is the frame's
    /// set. A conceal is drawn by no tool at all, but an old mark of one can be selected, and then
    /// the block is alive and shows the fields of that mark, taken from the frame's set here.
    /// The dictionary is never indexed straight — this is the one door to it.
    /// </summary>
    private ToolAppearance AppearanceOf(EditorTool tool) =>
        _tools.TryGetValue(tool, out var kept) ? kept : _tools[EditorTool.Rectangle];

    // The frame and the blur share one shape, the way the reference says they do: it is kept on the
    // frame, and the blur is written from it so the settings file says the same thing.
    private AnnotationShape ActiveShape => AppearanceOf(EditorTool.Rectangle).Shape;

    // What the next mark is drawn with: the set of the tool in the hand, whatever is selected.
    private void SyncSurfaceDefaults()
    {
        var kept = AppearanceOf(Surface.Tool);
        Surface.ActiveColor = kept.Color;
        Surface.ActiveThickness = kept.Thickness;
        Surface.ActiveShape = ActiveShape;
        Surface.ActiveFill = kept.Fill;
        Surface.ActiveFillColor = kept.FillColor;
        Surface.ActiveLineStyle = kept.LineStyle;
        Surface.ActiveFontSize = kept.FontSize;
        Surface.ActiveArrowStyle = kept.ArrowStyle;
    }

    private void OpenAppearance()
    {
        if (AppearancePopup.IsOpen) { AppearancePopup.IsOpen = false; return; }
        if (_capture is null) return;
        _appearanceBefore = SnapshotState();
        _appearanceChanged = false;
        BuildColorPalette();
        SyncAppearance();
        AppearancePopup.IsOpen = true;
    }

    private void OpenFontSize()
    {
        if (FontSizePopup.IsOpen) { FontSizePopup.IsOpen = false; return; }
        if (_capture is null) return;
        _appearanceBefore = SnapshotState();
        _appearanceChanged = false;
        SyncAppearance();
        FontSizePopup.IsOpen = true;
    }

    private void OpenFill()
    {
        if (FillPopup.IsOpen) { FillPopup.IsOpen = false; return; }
        if (_capture is null) return;
        _appearanceBefore = SnapshotState();
        _appearanceChanged = false;
        BuildFillPalette();
        SyncAppearance();
        FillPopup.IsOpen = true;
    }

    private void OpenThickness()
    {
        if (ThicknessPopup.IsOpen) { ThicknessPopup.IsOpen = false; return; }
        if (_capture is null) return;
        _appearanceBefore = SnapshotState();
        _appearanceChanged = false;
        SyncAppearance();
        ThicknessPopup.IsOpen = true;
    }

    // The twelve swatches of the active palette; rebuilt when another palette is picked. The colour
    // popover paints the outline with them, the fill popover the inside of a region.
    private void BuildColorPalette() => BuildSwatches(ColorPalette, ApplyPickedColor);

    private void BuildFillPalette() => BuildSwatches(FillPalette, color => ApplyAppearance(null, null, fillColor: color));

    private void BuildSwatches(System.Windows.Controls.Panel host, Action<Color> pick)
    {
        host.Children.Clear();
        foreach (var hex in _activePalette.Colors)
        {
            var color = (Color)ColorConverter.ConvertFromString(hex);
            var swatch = new Button { Width = 34, MinWidth = 34, Height = 34, Margin = new Thickness(3), Padding = new Thickness(4), Tag = color,
                Style = (Style)FindResource("OverlayButton"), ToolTip = hex,
                Content = new Ellipse { Width = 22, Height = 22, Fill = new SolidColorBrush(color), Stroke = new SolidColorBrush(Color.FromRgb(120, 130, 146)), StrokeThickness = 1 } };
            System.Windows.Automation.AutomationProperties.SetName(swatch, hex);
            swatch.Click += (_, _) => pick(color);
            host.Children.Add(swatch);
        }
        // The own palette is as long as it has been filled; the rest of the row is drawn as empty
        // cells, so it keeps its shape while it fills up instead of growing under the spectrum.
        if (_activePalette.Id != "custom") return;
        for (var slot = _activePalette.Colors.Length; slot < HotkeySettings.MaxCustomPaletteColors; slot++)
            host.Children.Add(EmptySlot());
    }

    private static Border EmptySlot() => new()
    {
        Width = 34, Height = 34, Margin = new Thickness(3), Padding = new Thickness(4),
        Child = new Ellipse
        {
            Width = 22, Height = 22, Stroke = new SolidColorBrush(Color.FromRgb(70, 83, 102)),
            StrokeThickness = 1, StrokeDashArray = [2, 2]
        }
    };

    /// <summary>
    /// The panel as an inspector: what is selected owns the block, and with nothing selected it is
    /// the tool in the hand. Two capsules and no more — the colour of the outline with the square of
    /// the fill beside it, and the width and pattern of a stroke, the size of a caption or the shape
    /// of a blur. The block keeps one width under every tool, so the panel never jumps.
    /// </summary>
    private void SyncAppearance()
    {
        if (ColorCapsule is null || StrokeSlider is null) return;
        _syncingAppearance = true;
        ArrowMenuButton.ToolTip = UiLanguage.Text("Стиль стрелки");
        ShapeMenuButton.ToolTip = UiLanguage.Text("Фигура");
        UndoButton.IsEnabled = _undo.Count > 0;
        RedoButton.IsEnabled = _redo.Count > 0;
        var selected = Surface.SelectedAnnotation;
        var tool = EditorInspector.InspectedTool(selected, Surface.Tool);
        var view = EditorInspector.InspectorViewOf(tool);
        var kept = AppearanceOf(tool);
        var color = selected?.Color ?? kept.Color;
        var thickness = selected?.Thickness ?? kept.Thickness;
        // The pattern belongs to the marks drawn with one: the highlighter carries a width and no
        // dashes, and the rule lives in StrokePattern, where both renderers read it.
        var patterned = Imaging.StrokePattern.Participates(tool);
        var lineStyle = patterned ? selected?.LineStyle ?? kept.LineStyle : AnnotationLineStyle.Solid;
        var fill = selected?.Fill ?? kept.Fill;
        var fillColor = (selected is not null ? selected.FillColor : kept.FillColor) ?? color;
        var fontSize = selected?.FontSize ?? kept.FontSize;
        var shape = selected is not null && selected.Kind is EditorTool.Rectangle or EditorTool.Blur ? selected.Shape : ActiveShape;
        // What the next mark is drawn with is decided apart from what the block shows: the tool in
        // the hand owns it, whatever mark the pointer happens to have selected.
        SyncSurfaceDefaults();

        // The first capsule: the circle of the outline and the square of what stands inside it. A
        // blur has no colour at all, so the capsule is hidden and not dimmed; a tool with no settings
        // of its own keeps both capsules in place and switched off, and the panel holds its width.
        ColorCapsule.Visibility = view.Stroke ? Visibility.Visible : Visibility.Hidden;
        ColorCapsule.IsEnabled = view.Enabled;
        ColorCapsule.Opacity = view.Enabled ? 1 : 0.28;
        StrokeDot.Fill = new SolidColorBrush(color);
        FillSquare.Visibility = view.FillSwatch ? Visibility.Visible : Visibility.Collapsed;
        FillSquare.Background = fill switch
        {
            AnnotationFill.Solid => new SolidColorBrush(fillColor),
            AnnotationFill.Translucent => new SolidColorBrush(Color.FromArgb(0x40, fillColor.R, fillColor.G, fillColor.B)),
            _ => Brushes.Transparent
        };
        FillSquareBlur.Visibility = fill == AnnotationFill.Blur ? Visibility.Visible : Visibility.Collapsed;
        FillSquareNone.Visibility = fill == AnnotationFill.None ? Visibility.Visible : Visibility.Collapsed;

        // The second capsule: the width and the pattern of a stroke, the size of a caption, or the
        // shape a blur is cut in. One capsule for the three of them, as the reference draws it.
        LineCapsule.IsEnabled = view.Enabled;
        LineCapsule.Opacity = view.Enabled ? 1 : 0.28;
        LineCapsule.ToolTip = UiLanguage.Text(view.Second switch
        {
            SecondCapsule.FontSize => "Размер",
            SecondCapsule.Shape => "Фигура",
            _ => "Толщина"
        });
        LineCapsuleGlyph.Visibility = view.Second is SecondCapsule.FontSize or SecondCapsule.Shape ? Visibility.Visible : Visibility.Collapsed;
        LineCapsuleGlyph.Text = view.Second == SecondCapsule.FontSize ? "A" : "▢";
        LineCapsuleValue.Text = view.Second switch
        {
            SecondCapsule.FontSize => $"{fontSize:0} pt",
            SecondCapsule.Shape => UiLanguage.Text(ShapeName(shape)),
            _ => $"{thickness:0} px"
        };
        LineCapsuleSample.Visibility = view.Second == SecondCapsule.Line ? Visibility.Visible : Visibility.Collapsed;
        LineCapsuleSample.StrokeThickness = Math.Clamp(thickness, 1, 6);
        LineCapsuleSample.StrokeDashArray = DashesOf(lineStyle);
        LineCapsuleSample.StrokeDashCap = lineStyle == AnnotationLineStyle.Dotted ? PenLineCap.Round : PenLineCap.Flat;

        // The stroke popover: the palettes, the swatches, the spectrum and the HEX field, and under
        // them the width and the pattern the reference draws in the same sheet.
        ColorHex.Text = $"#{color.R:X2}{color.G:X2}{color.B:X2}";
        ColorHex.BorderBrush = new SolidColorBrush(Color.FromRgb(70, 83, 102));
        var highlighting = tool == EditorTool.Highlight;
        StrokeSlider.IsEnabled = view.Second == SecondCapsule.Line;
        StrokeSlider.Minimum = highlighting ? MinimumHighlightThickness : 1;
        StrokeSlider.Maximum = highlighting ? MaximumHighlightThickness : 16;
        StrokeSlider.Value = Math.Clamp(thickness, StrokeSlider.Minimum, StrokeSlider.Maximum);
        StrokeValue.Text = view.Second == SecondCapsule.Line ? $"{thickness:0} px" : "—";
        StrokePreview.Stroke = new SolidColorBrush(color);
        // The preview shows what the stroke will look like, inside a box 36 px tall: a highlighter
        // that wide is drawn with its own transparency and its own square ends.
        StrokePreview.StrokeThickness = Math.Min(24, thickness);
        StrokePreview.Opacity = highlighting ? Controls.AnnotationCanvas.HighlightOpacity : 1;
        StrokePreview.StrokeStartLineCap = StrokePreview.StrokeEndLineCap = highlighting ? PenLineCap.Square : PenLineCap.Round;
        StrokePreview.StrokeDashArray = DashesOf(lineStyle);
        StrokePreview.StrokeDashCap = lineStyle == AnnotationLineStyle.Dotted ? PenLineCap.Round : PenLineCap.Flat;
        StrokePreview.Visibility = view.Second == SecondCapsule.Line ? Visibility.Visible : Visibility.Hidden;
        LineStyleRow.IsEnabled = patterned;
        foreach (var segment in LineStyleRow.Children.OfType<System.Windows.Controls.Primitives.ToggleButton>())
            segment.IsChecked = segment.Tag is string name && string.Equals(name, lineStyle.ToString(), StringComparison.Ordinal);
        // The four presets are the presets of the tool in the hand, values, tooltips and all.
        var presets = ThicknessPresetsFor(tool);
        var segments = ThicknessPresetRow.Children.OfType<System.Windows.Controls.Primitives.ToggleButton>().ToArray();
        for (var i = 0; i < segments.Length && i < presets.Length; i++)
        {
            var value = presets[i];
            var caption = $"{value:0} px";
            segments[i].Tag = value.ToString(System.Globalization.CultureInfo.InvariantCulture);
            segments[i].ToolTip = caption;
            System.Windows.Automation.AutomationProperties.SetName(segments[i], caption);
            // A 24 px band would not fit a segment 30 px tall, so the drawing of a preset is capped.
            if (segments[i].Content is Rectangle bar)
            {
                bar.Height = Math.Min(20, value);
                bar.RadiusX = bar.RadiusY = Math.Min(20, value) / 2;
            }
            segments[i].IsChecked = Math.Abs(value - thickness) < 0.001;
        }
        // Only the filled cells are swatches: an empty cell of the own palette is a placeholder and
        // has no colour to compare against.
        foreach (var swatch in ColorPalette.Children.OfType<Button>())
            swatch.BorderBrush = (Color)swatch.Tag == color ? Brushes.White : Brushes.Transparent;
        foreach (var swatch in FillPalette.Children.OfType<Button>())
            swatch.BorderBrush = (Color)swatch.Tag == fillColor ? Brushes.White : Brushes.Transparent;
        // The spectrum and the eyedropper are two ways of picking a colour, not a property of one
        // palette: they stand under every set, and the spectrum shows the colour that is in force,
        // so the HEX field and the markers say the same thing.
        Spectrum.SelectedColor = color;
        foreach (System.Windows.Controls.Primitives.ToggleButton segment in PaletteRow.Children)
            segment.IsChecked = (string)segment.Tag == _activePalette.Id;
        // The chevron half of a split button carries the state of its own tool, so the capsule
        // reads as one control.
        var accent = (Brush)FindResource("AccentSoftBrush");
        ShapeMenuButton.Background = Surface.Tool == EditorTool.Rectangle ? accent : Brushes.Transparent;
        ArrowMenuButton.Background = Surface.Tool == EditorTool.Arrow ? accent : Brushes.Transparent;
        PenMenuButton.Background = Surface.Tool is EditorTool.Pen or EditorTool.Highlight ? accent : Brushes.Transparent;
        // The size of a caption: the capsule carries it, the popover shows it, and the canvas takes
        // it for the next one.
        FontSizeValue.Text = $"{fontSize:0} px";
        FontSizeSlider.Value = TextMarkMetrics.Clamp(fontSize);
        FontSizePreview.FontSize = Math.Min(44, TextMarkMetrics.Clamp(fontSize));
        FontSizePreview.Foreground = new SolidColorBrush(color);
        foreach (System.Windows.Controls.Primitives.ToggleButton preset in FontSizePresetRow.Children)
            preset.IsChecked = preset.Tag is string sizeTag &&
                double.TryParse(sizeTag, System.Globalization.CultureInfo.InvariantCulture, out var presetSize) &&
                Math.Abs(presetSize - fontSize) < 0.001;
        FillRow.IsEnabled = view.FillSwatch;
        FillNoneSegment.IsChecked = fill == AnnotationFill.None;
        FillSolidSegment.IsChecked = fill == AnnotationFill.Solid;
        FillTranslucentSegment.IsChecked = fill == AnnotationFill.Translucent;
        FillBlurSegment.IsChecked = fill == AnnotationFill.Blur;
        // A blurred region shows the picture under it: it has no colour of its own to pick.
        FillPalette.IsEnabled = view.FillSwatch && fill is AnnotationFill.Solid or AnnotationFill.Translucent;
        FillValue.Text = UiLanguage.Text(FillName(fill));
        _syncingAppearance = false;
    }

    // The short name of a shape, the one the line capsule carries for a blur.
    private static string ShapeName(AnnotationShape shape) => shape switch
    {
        AnnotationShape.Rounded => "Скруглённый",
        AnnotationShape.Ellipse => "Овал",
        _ => "Прямоугольник"
    };

    /// <summary>
    /// Rule 2 of the specification: with a mark selected the change goes into that mark and nowhere
    /// else; with nothing selected it goes into the tool it belongs to, and every mark that tool
    /// draws from now on carries it. A tool with no settings of its own takes nothing at all.
    /// </summary>
    private void ApplyAppearance(Color? color, double? thickness, AnnotationShape? shape = null, AnnotationFill? fill = null,
        string? arrowStyle = null, Color? fillColor = null, double? fontSize = null,
        AnnotationLineStyle? lineStyle = null)
    {
        var selected = Surface.SelectedAnnotation;
        var tool = EditorInspector.InspectedTool(selected, Surface.Tool);
        var view = EditorInspector.InspectorViewOf(tool);
        void Keep(Func<ToolAppearance, ToolAppearance> change)
        {
            if (!_tools.TryGetValue(tool, out var before)) return;
            var after = change(before);
            _appearanceDefaultsChanged |= after != before;
            _tools[tool] = after;
        }
        if (color is { } c && view.Stroke)
        {
            if (selected is not null) { selected.Color = c; _appearanceChanged = true; }
            else Keep(before => before with { Color = c });
        }
        if (thickness is { } t && view.Second == SecondCapsule.Line)
        {
            if (selected is not null) { selected.Thickness = t; _appearanceChanged = true; }
            else Keep(before => before with { Thickness = t });
        }
        // The shape belongs to the frame and to the blur, and to nothing else on the panel.
        if (shape is { } picked && tool is EditorTool.Rectangle or EditorTool.Blur)
        {
            if (selected is not null) { selected.Shape = picked; _appearanceChanged = true; }
            else
            {
                // One shape for the frame and the blur: it is kept on the frame and mirrored onto the
                // blur, so the settings file says the same thing whichever of the two wrote it.
                _appearanceDefaultsChanged |= ActiveShape != picked;
                _tools[EditorTool.Rectangle] = AppearanceOf(EditorTool.Rectangle) with { Shape = picked };
                _tools[EditorTool.Blur] = AppearanceOf(EditorTool.Blur) with { Shape = picked };
            }
        }
        if (fill is { } f && view.FillSwatch)
        {
            if (selected is not null) { selected.Fill = f; _appearanceChanged = true; }
            else Keep(before => before with { Fill = f });
        }
        if (fillColor is { } fc && view.FillSwatch)
        {
            if (selected is not null) { selected.FillColor = fc; _appearanceChanged = true; }
            else Keep(before => before with { FillColor = fc });
        }
        if (arrowStyle is { } style && tool == EditorTool.Arrow)
        {
            if (selected is not null) { selected.ArrowStyle = style; _appearanceChanged = true; }
            else Keep(before => before with { ArrowStyle = style });
        }
        if (lineStyle is { } line && Imaging.StrokePattern.Participates(tool))
        {
            if (selected is not null) { selected.LineStyle = line; _appearanceChanged = true; }
            else Keep(before => before with { LineStyle = line });
        }
        if (fontSize is { } size && view.Second == SecondCapsule.FontSize)
        {
            size = TextMarkMetrics.Clamp(size);
            if (selected is not null)
            {
                selected.FontSize = size;
                // The box of a caption is its letters, and they just changed size.
                TextMarkMetrics.Fit(selected);
                _appearanceChanged = true;
            }
            else Keep(before => before with { FontSize = size });
            ResizeTextEditor();
        }
        Surface.InvalidateVisual();
        SyncAppearance();
    }

    // A change made outside the popover and outside a menu has nothing to close after it: if it
    // touches a selected mark, its history entry goes in at once.
    private void ApplyAppearanceNow(Color? color, double? thickness, Color? fillColor = null)
    {
        var pushEntry = Surface.SelectedAnnotation is not null && _capture is not null && _appearanceBefore is null;
        if (pushEntry) { _undo.Push(SnapshotState()); _redo.Clear(); }
        ApplyAppearance(color, thickness, fillColor: fillColor);
        if (pushEntry) { _lastSnapshot = SnapshotState(); SyncAppearance(); }
    }

    // A colour picked in the colour popover and a colour picked on the panel mean the same thing,
    // the colour of the mark itself; what stands inside a frame is picked in the fill popover.
    private void ApplyPickedColor(Color color) => ApplyAppearance(color, null);

    private void ApplyQuickColor(Color color) => ApplyAppearanceNow(color, null);

    // The name of a fill, for the value beside the title of the popover; the same four words the
    // segments carry in their tooltips.
    private static string FillName(AnnotationFill fill) => fill switch
    {
        AnnotationFill.Solid => "Сплошная заливка",
        AnnotationFill.Translucent => "Полупрозрачная заливка",
        AnnotationFill.Blur => "Заливка размытием",
        _ => "Контур"
    };

    private void OnFontSizeClick(object sender, RoutedEventArgs e) => OpenFontSize();

    private void OnFontSizePresetClick(object sender, RoutedEventArgs e)
    {
        if (_syncingAppearance || sender is not System.Windows.Controls.Primitives.ToggleButton { Tag: string tag } ||
            !double.TryParse(tag, System.Globalization.CultureInfo.InvariantCulture, out var size)) return;
        ApplyAppearance(null, null, fontSize: size);
    }

    private void OnFontSizeChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (!_syncingAppearance && FontSizePopup?.IsOpen == true) ApplyAppearance(null, null, fontSize: Math.Round(e.NewValue));
    }

    // The press that began on the square inside the colour capsule, and nowhere else in it.
    private bool _fillSquarePressed;

    // The square inside the colour capsule takes the press before the capsule does, and the capsule
    // opens the fill popover instead of the stroke one on the click that follows: two properties of
    // the mark, two ways in. The press itself opens nothing. A Popup with StaysOpen="False" takes
    // the mouse the moment it opens, so a popover opened on the way down sees the button coming up
    // outside itself and closes again — it lived only while the button was held. Both popovers of
    // the capsule now open the same way the rest of the panel does: on the click.
    private void OnColorCapsuleDown(object sender, MouseButtonEventArgs e) => _fillSquarePressed = false;

    private void OnFillSquareDown(object sender, MouseButtonEventArgs e) => _fillSquarePressed = true;

    internal bool OpenFillFromSquare()
    {
        if (_capture is null || !ColorCapsule.IsEnabled) return false;
        // The fill belongs to a region: with another tool in the hand and nothing selected the
        // square arms the region first, the way a pick in the shape menu does.
        if (Surface.SelectedAnnotation is null && !EditorInspector.InspectorViewOf(Surface.Tool).FillSwatch)
            SelectToolMode(EditorTool.Rectangle);
        OpenFill();
        return true;
    }

    // The two capsules of the block, and the popover each of them opens. The line capsule carries
    // three things by turns, so it opens three: the width and the pattern of a stroke, the size of
    // a caption, or the menu of shapes the frame and the blur share.
    private void OnColorCapsuleClick(object sender, RoutedEventArgs e)
    {
        var onSquare = _fillSquarePressed;
        _fillSquarePressed = false;
        if (onSquare) OpenFillFromSquare();
        else OpenAppearance();
    }

    private void OnLineCapsuleClick(object sender, RoutedEventArgs e)
    {
        var tool = EditorInspector.InspectedTool(Surface.SelectedAnnotation, Surface.Tool);
        switch (EditorInspector.InspectorViewOf(tool).Second)
        {
            case SecondCapsule.FontSize: OpenFontSize(); break;
            case SecondCapsule.Shape: OpenToolMenu(BuildShapeMenu(LineCapsule)); break;
            default: OpenThickness(); break;
        }
    }

    private void OnFillClick(object sender, RoutedEventArgs e)
    {
        if (_syncingAppearance || sender is not System.Windows.Controls.Primitives.ToggleButton { Tag: string tag } ||
            !Enum.TryParse<AnnotationFill>(tag, out var fill)) return;
        ApplyAppearance(null, null, fill: fill);
    }

    private void OnPaletteClick(object sender, RoutedEventArgs e)
    {
        if (_syncingAppearance || sender is not System.Windows.Controls.Primitives.ToggleButton { Tag: string id }) return;
        SelectPalette(id == "custom" ? CustomPalette(_customColors) : ParseAnnotationPalette(id));
    }

    // The markers are dragged over a colour that is already on the canvas, so every move paints. The
    // row of saved colours is filled by the "+" beside the HEX field and by nothing else: a colour
    // dragged through the spectrum is a colour tried out, not a colour kept.
    private void OnSpectrumChanged(object? sender, EventArgs e)
    {
        if (_syncingAppearance) return;
        ApplyPickedColor(Spectrum.SelectedColor);
    }

    // The eyedropper takes a pixel from anywhere on the desktop. The popover is in the way of the
    // screen under it, so it is closed for the picking and opened again with the colour.
    private void OnEyedropperClick(object sender, RoutedEventArgs e)
    {
        var before = AppearanceOf(Surface.Tool).Color;
        AppearancePopup.IsOpen = false;
        var picked = Controls.ScreenColorPicker.Pick(this, ApplyPickedColor);
        // Given up on: the colour the dropper walked over goes back to the one it started with.
        ApplyPickedColor(picked ?? before);
        OpenAppearance();
    }

    // The "+" beside the HEX field: the colour in force joins the own palette from wherever it was
    // picked, and the row on screen stays the one the user is looking at.
    private void OnAddColorClick(object sender, RoutedEventArgs e) => RememberCustomColor(AppearanceOf(EditorInspector.InspectedTool(Surface.SelectedAnnotation, Surface.Tool)).Color);

    /// <summary>
    /// The smoke check of the own palette: the spectrum and the eyedropper stand under every set,
    /// the "+" beside the HEX field saves the colour in force from any of them, the row keeps its
    /// twelve cells from the first colour to the last, a colour picked twice rises instead of
    /// standing there twice, and the spectrum paints the mark.
    /// </summary>
    internal void RunCustomPaletteProbe()
    {
        // Every palette, the own one last: the two ways of picking a colour are not a property of a
        // set, so neither of them may disappear with the set under it.
        foreach (var palette in new[] { Palettes[0], Palettes[1], Palettes[2], CustomPalette(_customColors) })
        {
            SelectPalette(palette);
            if (SpectrumBlock.Visibility != Visibility.Visible || EyedropperButton.Visibility != Visibility.Visible)
                throw new InvalidOperationException($"The spectrum and the eyedropper must stand under the \"{palette.Id}\" palette as well.");
        }
        // The "+" saves from a palette that is not the own one, and leaves the row on screen alone.
        SelectPalette(Palettes[0]);
        ApplyPickedColor(Color.FromRgb(0x12, 0x34, 0x56));
        OnAddColorClick(AddColorButton, new RoutedEventArgs());
        if (_customColors.FirstOrDefault() != "#123456" || _activePalette.Id != "standard")
            throw new InvalidOperationException("The \"+\" must save the colour in force without changing the palette on screen.");
        _customColors.Clear();

        SelectPalette(CustomPalette(_customColors));
        if (CustomPaletteSegment.IsChecked != true ||
            ColorPalette.Children.Count != HotkeySettings.MaxCustomPaletteColors)
            throw new InvalidOperationException("The own palette must show a row of twelve cells.");
        RememberCustomColor(Color.FromRgb(0x2F, 0x8C, 0xFF));
        RememberCustomColor(Color.FromRgb(0xFF, 0x4D, 0x4F));
        RememberCustomColor(Color.FromRgb(0x2F, 0x8C, 0xFF));
        if (_customColors.Count != 2 || _customColors[0] != "#2F8CFF" ||
            ColorPalette.Children.OfType<Button>().Count() != 2 ||
            ColorPalette.Children.Count != HotkeySettings.MaxCustomPaletteColors)
            throw new InvalidOperationException("A colour picked again must rise in the row instead of filling a second cell.");
        for (var step = 0; step < HotkeySettings.MaxCustomPaletteColors + 2; step++)
            RememberCustomColor(Color.FromRgb((byte)(10 + step), 0x20, 0x30));
        if (_customColors.Count != HotkeySettings.MaxCustomPaletteColors ||
            ColorPalette.Children.OfType<Button>().Count() != HotkeySettings.MaxCustomPaletteColors)
            throw new InvalidOperationException("The own palette must hold twelve colours and no more.");
        // The markers paint the mark, and the HEX field beside them shows the same colour.
        Spectrum.PickInHue(new Point(8, 0));
        Spectrum.PickInSquare(new Point(160, 0));
        if (AppearanceOf(Surface.Tool).Color != Color.FromRgb(0xFF, 0x00, 0x00) || ColorHex.Text != "#FF0000")
            throw new InvalidOperationException("A colour picked in the spectrum must reach the mark and the HEX field.");
        _customColors.Clear();
        SelectPalette(Palettes[0]);
    }

    /// <summary>
    /// The row of saved colours: the newest goes first, a colour that is already in the row moves up
    /// instead of standing in it twice, and the row is never longer than the file allows. A colour
    /// may be added from any palette, and the palette on screen does not change under the hand: only
    /// the own row, when it is the one being shown, is rebuilt.
    /// </summary>
    private void RememberCustomColor(Color color)
    {
        var hex = $"#{color.R:X2}{color.G:X2}{color.B:X2}";
        _customColors.Remove(hex);
        _customColors.Insert(0, hex);
        if (_customColors.Count > HotkeySettings.MaxCustomPaletteColors)
            _customColors.RemoveRange(HotkeySettings.MaxCustomPaletteColors, _customColors.Count - HotkeySettings.MaxCustomPaletteColors);
        // The row lives in the settings file, so a colour added from another palette has to be
        // written out as well; SelectPalette does it for the own one on its way through.
        _appearanceDefaultsChanged = true;
        if (_activePalette.Id == "custom") SelectPalette(CustomPalette(_customColors));
    }

    internal void SelectPalette(PaletteSet palette)
    {
        if (ReferenceEquals(palette, _activePalette)) { SyncAppearance(); return; }
        _activePalette = palette;
        _appearanceDefaultsChanged = true;
        BuildColorPalette();
        BuildFillPalette();
        SyncAppearance();
    }

    private void OnLineStylePresetClick(object sender, RoutedEventArgs e)
    {
        if (_syncingAppearance || sender is not System.Windows.Controls.Primitives.ToggleButton { Tag: string tag } ||
            !Enum.TryParse<AnnotationLineStyle>(tag, out var style)) return;
        ApplyAppearance(null, null, lineStyle: style);
    }

    private void OnThicknessPresetClick(object sender, RoutedEventArgs e)
    {
        if (_syncingAppearance || sender is not System.Windows.Controls.Primitives.ToggleButton { Tag: string tag } ||
            !double.TryParse(tag, System.Globalization.CultureInfo.InvariantCulture, out var thickness)) return;
        ApplyAppearance(null, thickness);
    }

    private void OnStrokeChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (!_syncingAppearance && ThicknessPopup?.IsOpen == true) ApplyAppearance(null, Math.Round(e.NewValue));
    }
    private void ApplyHex()
    {
        var value = ColorHex.Text.Trim();
        if (value.StartsWith('#')) value = value[1..];
        if (value.Length == 6 && uint.TryParse(value, System.Globalization.NumberStyles.HexNumber, null, out var rgb))
        {
            var colour = Color.FromRgb((byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb);
            ApplyPickedColor(colour);
        }
        else ColorHex.BorderBrush = new SolidColorBrush(Color.FromRgb(255, 110, 110));
    }
    private void OnHexLostFocus(object sender, KeyboardFocusChangedEventArgs e) { if (!_syncingAppearance) ApplyHex(); }
    private void OnHexKeyDown(object sender, KeyEventArgs e) { if (e.Key == Key.Enter) { ApplyHex(); e.Handled = true; } }
    private void OnAppearanceKeyDown(object sender, KeyEventArgs e) { if (e.Key == Key.Escape) { AppearancePopup.IsOpen = false; e.Handled = true; } }
    private void OnThicknessKeyDown(object sender, KeyEventArgs e) { if (e.Key == Key.Escape) { ThicknessPopup.IsOpen = false; e.Handled = true; } }
    private void OnFillKeyDown(object sender, KeyEventArgs e) { if (e.Key == Key.Escape) { FillPopup.IsOpen = false; e.Handled = true; } }
    private void OnFontSizeKeyDown(object sender, KeyEventArgs e) { if (e.Key == Key.Escape) { FontSizePopup.IsOpen = false; e.Handled = true; } }
    private void OnCloseAppearance(object sender, RoutedEventArgs e) => AppearancePopup.IsOpen = false;

    // What Escape gives up, in order: an open popover, then the selection, and only with nothing
    // left to give up, the capture itself. The mark being drawn is taken by the canvas before the
    // window is asked at all.
    internal enum EscapeStep { Popover, ExpandedNote, Comment, Selection, Capture }

    internal EscapeStep NextEscapeStep() =>
        ShortcutSheetPopup.IsOpen || AppearancePopup.IsOpen || ThicknessPopup.IsOpen || FillPopup.IsOpen || FontSizePopup.IsOpen ? EscapeStep.Popover
        // A pill opened by pointing at a badge is given up before the tool in the hand is: it is
        // the thing on screen, and the hand that opened it expects Escape to close it.
        : _expandedChipId is not null ? EscapeStep.ExpandedNote
        : Surface.Tool == EditorTool.Comment ? EscapeStep.Comment
        : Surface.SelectedAnnotation is not null ? EscapeStep.Selection
        : EscapeStep.Capture;

    private void ClosePopovers()
    {
        AppearancePopup.IsOpen = false;
        ThicknessPopup.IsOpen = false;
        FillPopup.IsOpen = false;
        FontSizePopup.IsOpen = false;
        ShortcutSheetPopup.IsOpen = false;
    }
    private void OnAppearanceClosed(object? sender, EventArgs e)
    {
        CommitAppearanceEdit();
        Surface.Focus();
    }

    // One history entry for everything a popover or a tool menu changed while it was open.
    private void CommitAppearanceEdit()
    {
        if (_appearanceChanged && _appearanceBefore is not null && _capture is not null)
        {
            _undo.Push(_appearanceBefore); _redo.Clear(); _lastSnapshot = SnapshotState();
        }
        _appearanceBefore = null; _appearanceChanged = false;
        FlushAppearanceDefaults();
        SyncAppearance();
    }

    // The popover normally writes the defaults when it closes, but a window completed by the global
    // capture hotkey never raises Popup.Closed, so the editor flushes them while closing as well.
    private void FlushAppearanceDefaults()
    {
        if (!_appearanceDefaultsChanged) return;
        _appearanceDefaultsChanged = false;
        SaveAppearanceDefaults();
    }

    // The editor window is created again for every capture, so what the panel remembers lives in the
    // settings file. Rule 6: every tool remembers a set of its own, the frame its fill and the
    // colour of that fill among them — ToolAppearanceStore writes the six of them and the mirror
    // 1.5.0 reads. The palette, the own row of colours and the mode of the pencil are not by tool:
    // they are the state of the panel, and this is the one place that writes them, so they have to
    // go into the same record on their way out.
    private void SaveAppearanceDefaults()
    {
        try
        {
            var path = _workspace.SettingsPath;
            // Load-modify-write over a file that exists but cannot be read would drop every other setting.
            if (!HotkeySettings.TryLoad(path, out var stored)) return;
            var settings = ToolAppearanceStore.Write(stored, _tools) with
            {
                AnnotationPalette = _activePalette.Id,
                CustomPaletteColors = [.. _customColors],
                AnnotationPencil = _activePencil == EditorTool.Highlight ? "highlight" : "pen"
            };
            settings.Save(path);
        }
        catch (Exception) { /* a preference that cannot be written must not break the editor */ }
    }

    internal static Color ParseAnnotationColor(string? value)
    {
        try { return !string.IsNullOrWhiteSpace(value) && ColorConverter.ConvertFromString(value) is Color color ? color : DefaultAnnotationColor; }
        catch (Exception) { return DefaultAnnotationColor; }
    }

    // Anything but "highlight" leaves the capsule on the pen, the mode it has always started with.
    internal static EditorTool ParseAnnotationPencil(string? value) =>
        string.Equals(value, "highlight", StringComparison.OrdinalIgnoreCase) ? EditorTool.Highlight : EditorTool.Pen;

    // A palette written by hand, or by a build that knew other sets, falls back to the standard one.
    internal static PaletteSet ParseAnnotationPalette(string? value) =>
        Palettes.FirstOrDefault(palette => string.Equals(palette.Id, value, StringComparison.OrdinalIgnoreCase)) ?? Palettes[0];
}
