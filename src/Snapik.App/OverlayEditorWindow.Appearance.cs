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
    // The tools drawn with a stroke, written out and depending on nothing else: a caption has a size
    // instead of a thickness, and a comment pin has neither.
    private static bool HasStroke(EditorTool tool) => tool is EditorTool.Rectangle or EditorTool.Arrow or EditorTool.Pen or EditorTool.Highlight;
    // The frame is shared by a region and by a blur: one shape is remembered for both. What stands
    // inside the frame belongs to the region alone, a blur has its own picture inside it.
    private static bool HasShape(EditorTool tool) => tool is EditorTool.Rectangle or EditorTool.Blur;
    private static bool HasFill(EditorTool tool) => tool == EditorTool.Rectangle;
    // The size of the letters belongs to a caption, and to nothing else on the panel.
    private static bool HasFontSize(EditorTool tool) => tool == EditorTool.Text;
    // The pattern of a stroke belongs to the marks that are drawn with one: the frame and the oval,
    // the arrow and the pencil. The highlighter is left out on purpose — a dashed highlighter falls
    // apart into blots.
    private static bool HasLineStyle(EditorTool tool) => Imaging.StrokePattern.Participates(tool);

    // A palette is twelve colours plus the five of them that sit on the panel, one click away. The
    // sets are picked in the popover and remembered between captures; replacing the colours of a set
    // is one array and no code.
    internal sealed record PaletteSet(string Id, string NameKey, string[] Colors, string[] Quick);

    internal static readonly PaletteSet[] Palettes =
    [
        new("standard", "Стандартная",
            ["#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#32ADE6", "#007AFF", "#AF52DE", "#FF2D55", "#FFFFFF", "#000000", "#8E8E93", "#A2845E"],
            ["#FF3B30", "#FFCC00", "#34C759", "#007AFF", "#FFFFFF"]),
        new("pastel", "Пастель",
            ["#2F8CFF", "#FF4D4F", "#FFBE2E", "#28BE80", "#AF81FF", "#FF79B7", "#FFFFFF", "#000000", "#00C8DC", "#FF8C42", "#9BA7B8", "#7754D9"],
            ["#2F8CFF", "#FF4D4F", "#FFBE2E", "#28BE80", "#FFFFFF"]),
        // The own palette holds no colours of its own: they are the ones the user picked, they live
        // in the settings file, and PaletteFor puts them in.
        new("custom", "Своя", [], [])
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

    internal static PaletteSet CustomPalette(System.Collections.Generic.IEnumerable<string> colours)
    {
        var kept = colours.Take(HotkeySettings.MaxCustomPaletteColors).ToArray();
        return new PaletteSet("custom", "Своя", kept, [.. kept.Take(5)]);
    }

    /// <summary>The colours of the own palette, newest first, as this window has them.</summary>
    private readonly System.Collections.Generic.List<string> _customColors = [];

    // Called from the constructor: the palette of the next capture is the one the file carries, and
    // the own colours come with it.
    private void InitializePalette(HotkeySettings preferences)
    {
        _customColors.AddRange(preferences.CustomPaletteColors);
        _activePalette = PaletteFor(preferences);
    }

    // The thickness the panel works on: the highlighter keeps one of its own, everything else with a
    // stroke shares the other, which is what the common thickness button was asked to do.
    internal static double[] ThicknessPresetsFor(EditorTool tool) =>
        tool == EditorTool.Highlight ? HighlightThicknessPresets : ThicknessPresets;

    internal double ActiveThicknessFor(EditorTool tool) =>
        tool == EditorTool.Highlight ? _activeHighlightThickness : _activeThickness;

    private void SetActiveThickness(EditorTool tool, double value)
    {
        if (tool == EditorTool.Highlight)
        {
            _appearanceDefaultsChanged |= value != _activeHighlightThickness;
            _activeHighlightThickness = value;
        }
        else
        {
            _appearanceDefaultsChanged |= value != _activeThickness;
            _activeThickness = value;
        }
        Surface.ActiveThickness = ActiveThicknessFor(Surface.Tool);
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

    private void OpenLineStyle()
    {
        if (LineStylePopup.IsOpen) { LineStylePopup.IsOpen = false; return; }
        if (_capture is null) return;
        _appearanceBefore = SnapshotState();
        _appearanceChanged = false;
        SyncAppearance();
        LineStylePopup.IsOpen = true;
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

    // The row of five dots on the panel: the quick row of the active palette, one click instead of
    // two. The circle beside it still opens the full popover.
    private void BuildColorDots()
    {
        ColorDots.Children.Clear();
        foreach (var hex in _activePalette.Quick)
        {
            var color = (Color)ColorConverter.ConvertFromString(hex);
            var dot = new Ellipse
            {
                Width = 14, Height = 14, Fill = new SolidColorBrush(color),
                Stroke = new SolidColorBrush(Color.FromRgb(120, 130, 146)), StrokeThickness = 1
            };
            var button = new Button
            {
                Width = 22, MinWidth = 22, Height = 22, Margin = new Thickness(1, 0, 1, 0), Padding = new Thickness(0),
                Style = (Style)FindResource("OverlayButton"), Tag = color, Content = dot, ToolTip = hex
            };
            System.Windows.Automation.AutomationProperties.SetName(button, hex);
            button.Click += (_, _) => ApplyQuickColor(color);
            ColorDots.Children.Add(button);
        }
    }

    private void SyncAppearance()
    {
        if (AppearanceButton is null || StrokeSlider is null) return;
        _syncingAppearance = true;
        ArrowMenuButton.ToolTip = UiLanguage.Text("Стиль стрелки");
        ShapeMenuButton.ToolTip = UiLanguage.Text("Фигура");
        UndoButton.IsEnabled = _undo.Count > 0;
        RedoButton.IsEnabled = _redo.Count > 0;
        var selected = Surface.SelectedAnnotation;
        var tool = selected?.Kind ?? Surface.Tool;
        var color = selected?.Color ?? _activeColor;
        var thickness = selected?.Thickness ?? ActiveThicknessFor(tool);
        // The next mark takes the thickness of the tool in the hand, not of the mark under the cursor.
        Surface.ActiveThickness = ActiveThicknessFor(Surface.Tool);
        var fillColor = (selected is not null ? selected.FillColor : _activeFillColor) ?? color;
        // The circle on the panel and the dots beside it carry the colour of the mark itself; what
        // stands inside a frame has a row of its own in the fill popover. There is one active colour
        // and every tool takes it, so neither the circle nor the dots are ever dimmed.
        ColorSwatch.Fill = new SolidColorBrush(color);
        // A tool without a stroke leaves the last thickness on the button, dimmed by the disabled
        // state of the style: an empty caption is what used to make the panel jump.
        ThicknessButton.IsEnabled = HasStroke(tool);
        ThicknessButton.Content = $"{(HasStroke(tool) ? thickness : ActiveThicknessFor(tool)):0} px";
        // The pattern of the mark under the hand, or of the next one; a tool without a pattern keeps
        // the last sample on the button, dimmed by the disabled state, the way the thickness does.
        var lineStyle = selected is not null && HasLineStyle(selected.Kind) ? selected.LineStyle : _activeLineStyle;
        LineStyleButton.IsEnabled = HasLineStyle(tool);
        LineStyleGlyph.StrokeDashArray = DashesOf(lineStyle);
        LineStyleGlyph.StrokeDashCap = lineStyle == AnnotationLineStyle.Dotted ? PenLineCap.Round : PenLineCap.Flat;
        LineStylePreview.Stroke = new SolidColorBrush(color);
        LineStylePreview.StrokeThickness = Math.Min(24, thickness);
        LineStylePreview.StrokeDashArray = DashesOf(lineStyle);
        LineStylePreview.StrokeDashCap = lineStyle == AnnotationLineStyle.Dotted ? PenLineCap.Round : PenLineCap.Flat;
        foreach (var segment in LineStyleRow.Children.OfType<System.Windows.Controls.Primitives.ToggleButton>())
            segment.IsChecked = segment.Tag is string name && string.Equals(name, lineStyle.ToString(), StringComparison.Ordinal);
        ColorHex.Text = $"#{color.R:X2}{color.G:X2}{color.B:X2}";
        ColorHex.BorderBrush = new SolidColorBrush(Color.FromRgb(70, 83, 102));
        var highlighting = tool == EditorTool.Highlight;
        StrokeSlider.IsEnabled = HasStroke(tool);
        StrokeSlider.Minimum = highlighting ? MinimumHighlightThickness : 1;
        StrokeSlider.Maximum = highlighting ? MaximumHighlightThickness : 16;
        StrokeSlider.Value = Math.Clamp(thickness, StrokeSlider.Minimum, StrokeSlider.Maximum);
        StrokeValue.Text = HasStroke(tool) ? $"{thickness:0} px" : "—";
        StrokePreview.Stroke = new SolidColorBrush(color);
        // The preview shows what the stroke will look like, inside a box 36 px tall: a highlighter
        // that wide is drawn with its own transparency and its own square ends.
        StrokePreview.StrokeThickness = Math.Min(24, thickness);
        StrokePreview.Opacity = highlighting ? Controls.AnnotationCanvas.HighlightOpacity : 1;
        StrokePreview.StrokeStartLineCap = StrokePreview.StrokeEndLineCap = highlighting ? PenLineCap.Square : PenLineCap.Round;
        StrokePreview.Visibility = HasStroke(tool) ? Visibility.Visible : Visibility.Hidden;
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
        // The dots paint the colour of the mark, the same one the circle on the panel shows, so the
        // one that is ringed is the one that matches it.
        foreach (Button dot in ColorDots.Children)
            ((Ellipse)dot.Content).Stroke = (Color)dot.Tag == color
                ? Brushes.White
                : new SolidColorBrush(Color.FromRgb(120, 130, 146));
        // The size of a caption: the button carries it, the popover shows it, and the canvas takes
        // it for the next one.
        var fontSize = selected?.FontSize ?? _activeFontSize;
        Surface.ActiveFontSize = _activeFontSize;
        FontSizeButton.IsEnabled = HasFontSize(tool);
        FontSizeButton.Content = $"{(HasFontSize(tool) ? fontSize : _activeFontSize):0} px";
        FontSizeValue.Text = $"{fontSize:0} px";
        FontSizeSlider.Value = TextMarkMetrics.Clamp(fontSize);
        FontSizePreview.FontSize = Math.Min(44, TextMarkMetrics.Clamp(fontSize));
        FontSizePreview.Foreground = new SolidColorBrush(color);
        foreach (System.Windows.Controls.Primitives.ToggleButton preset in FontSizePresetRow.Children)
            preset.IsChecked = preset.Tag is string sizeTag &&
                double.TryParse(sizeTag, System.Globalization.CultureInfo.InvariantCulture, out var presetSize) &&
                Math.Abs(presetSize - fontSize) < 0.001;
        var fill = selected?.Fill ?? Surface.ActiveFill;
        FillRow.IsEnabled = HasFill(tool);
        FillNoneSegment.IsChecked = fill == AnnotationFill.None;
        FillSolidSegment.IsChecked = fill == AnnotationFill.Solid;
        FillTranslucentSegment.IsChecked = fill == AnnotationFill.Translucent;
        FillBlurSegment.IsChecked = fill == AnnotationFill.Blur;
        // A blurred region shows the picture under it: it has no colour of its own to pick.
        FillPalette.IsEnabled = HasFill(tool) && fill is AnnotationFill.Solid or AnnotationFill.Translucent;
        // The button of the fill is dimmed only while a mark that cannot be filled is selected: with
        // another tool in the hand it arms the region itself, so it must stay pressable.
        FillButton.IsEnabled = selected is null || HasFill(selected.Kind);
        FillValue.Text = UiLanguage.Text(FillName(fill));
        FillButtonPreview.Fill = fill switch
        {
            AnnotationFill.Solid => new SolidColorBrush(fillColor),
            AnnotationFill.Translucent => new SolidColorBrush(Color.FromArgb(0x40, fillColor.R, fillColor.G, fillColor.B)),
            AnnotationFill.Blur => (Brush)FindResource("BlurFillPreview"),
            _ => Brushes.Transparent
        };
        _syncingAppearance = false;
    }

    private void ApplyAppearance(Color? color, double? thickness, AnnotationShape? shape = null, AnnotationFill? fill = null,
        string? arrowStyle = null, Color? fillColor = null, double? fontSize = null,
        AnnotationLineStyle? lineStyle = null)
    {
        var selected = Surface.SelectedAnnotation;
        var tool = selected?.Kind ?? Surface.Tool;
        // One active colour, taken whatever is in the hand: a colour picked with the comment tool
        // armed is the colour the next frame is drawn with, instead of being thrown away.
        if (color is { } c) { _appearanceDefaultsChanged |= c != _activeColor; _activeColor = c; Surface.ActiveColor = c; if (selected is not null) { selected.Color = c; _appearanceChanged = true; } }
        if (thickness is { } t && HasStroke(tool)) { SetActiveThickness(tool, t); if (selected is not null) { selected.Thickness = t; _appearanceChanged = true; } }
        if (shape is { } s && HasShape(tool)) { _appearanceDefaultsChanged |= s != _activeShape; _activeShape = s; Surface.ActiveShape = s; if (selected is not null) { selected.Shape = s; _appearanceChanged = true; } }
        if (fill is { } f && HasFill(tool)) { _appearanceDefaultsChanged |= f != _activeFill; _activeFill = f; Surface.ActiveFill = f; if (selected is not null) { selected.Fill = f; _appearanceChanged = true; } }
        if (fillColor is { } fc && HasFill(tool)) { _appearanceDefaultsChanged |= fc != _activeFillColor; _activeFillColor = fc; Surface.ActiveFillColor = fc; if (selected is not null) { selected.FillColor = fc; _appearanceChanged = true; } }
        if (arrowStyle is { } style && tool == EditorTool.Arrow) { Surface.ActiveArrowStyle = style; if (selected is not null) { selected.ArrowStyle = style; _appearanceChanged = true; } }
        if (lineStyle is { } line && HasLineStyle(tool)) { _activeLineStyle = line; Surface.ActiveLineStyle = line; if (selected is not null) { selected.LineStyle = line; _appearanceChanged = true; } }
        if (fontSize is { } size && HasFontSize(tool))
        {
            size = TextMarkMetrics.Clamp(size);
            _appearanceDefaultsChanged |= size != _activeFontSize;
            _activeFontSize = size;
            Surface.ActiveFontSize = size;
            if (selected is not null)
            {
                selected.FontSize = size;
                // The box of a caption is its letters, and they just changed size.
                TextMarkMetrics.Fit(selected);
                _appearanceChanged = true;
            }
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

    private void OnFillButtonClick(object sender, RoutedEventArgs e)
    {
        if (_capture is null) return;
        // The fill belongs to a region: with another tool in the hand and nothing selected the
        // button arms the region first, the way a pick in the shape menu does.
        if (Surface.SelectedAnnotation is null && !HasFill(Surface.Tool)) SelectToolMode(EditorTool.Rectangle);
        OpenFill();
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
        var before = _activeColor;
        AppearancePopup.IsOpen = false;
        var picked = Controls.ScreenColorPicker.Pick(this, ApplyPickedColor);
        // Given up on: the colour the dropper walked over goes back to the one it started with.
        ApplyPickedColor(picked ?? before);
        OpenAppearance();
    }

    // The "+" beside the HEX field: the colour in force joins the own palette from wherever it was
    // picked, and the row on screen stays the one the user is looking at.
    private void OnAddColorClick(object sender, RoutedEventArgs e) => RememberCustomColor(_activeColor);

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
        foreach (var palette in new[] { Palettes[0], Palettes[1], CustomPalette(_customColors) })
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
            ColorPalette.Children.Count != HotkeySettings.MaxCustomPaletteColors ||
            ColorDots.Children.Count != 2)
            throw new InvalidOperationException("A colour picked again must rise in the row instead of filling a second cell.");
        for (var step = 0; step < HotkeySettings.MaxCustomPaletteColors + 2; step++)
            RememberCustomColor(Color.FromRgb((byte)(10 + step), 0x20, 0x30));
        if (_customColors.Count != HotkeySettings.MaxCustomPaletteColors ||
            ColorPalette.Children.OfType<Button>().Count() != HotkeySettings.MaxCustomPaletteColors ||
            ColorDots.Children.Count != 5)
            throw new InvalidOperationException("The own palette must hold twelve colours and no more, with five of them on the panel.");
        // The markers paint the mark, and the HEX field beside them shows the same colour.
        Spectrum.PickInHue(new Point(8, 0));
        Spectrum.PickInSquare(new Point(160, 0));
        if (_activeColor != Color.FromRgb(0xFF, 0x00, 0x00) || ColorHex.Text != "#FF0000")
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
        BuildColorDots();
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
    private void OnLineStyleKeyDown(object sender, KeyEventArgs e) { if (e.Key == Key.Escape) { LineStylePopup.IsOpen = false; e.Handled = true; } }
    private void OnFillKeyDown(object sender, KeyEventArgs e) { if (e.Key == Key.Escape) { FillPopup.IsOpen = false; e.Handled = true; } }
    private void OnFontSizeKeyDown(object sender, KeyEventArgs e) { if (e.Key == Key.Escape) { FontSizePopup.IsOpen = false; e.Handled = true; } }
    private void OnCloseAppearance(object sender, RoutedEventArgs e) => AppearancePopup.IsOpen = false;

    // What Escape gives up, in order: an open popover, then the selection, and only with nothing
    // left to give up, the capture itself. The mark being drawn is taken by the canvas before the
    // window is asked at all.
    internal enum EscapeStep { Popover, Comment, Selection, Capture }

    internal EscapeStep NextEscapeStep() =>
        ShortcutSheetPopup.IsOpen || AppearancePopup.IsOpen || ThicknessPopup.IsOpen || LineStylePopup.IsOpen || FillPopup.IsOpen || FontSizePopup.IsOpen ? EscapeStep.Popover
        : Surface.Tool == EditorTool.Comment ? EscapeStep.Comment
        : Surface.SelectedAnnotation is not null ? EscapeStep.Selection
        : EscapeStep.Capture;

    private void ClosePopovers()
    {
        AppearancePopup.IsOpen = false;
        ThicknessPopup.IsOpen = false;
        LineStylePopup.IsOpen = false;
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
    // settings file: the colour, the thickness, the size of the letters, the palette and the pencil.
    // The frame, its fill and the colour of that fill are not remembered; every capture starts with
    // a rectangle, an outline and nothing inside it.
    private void SaveAppearanceDefaults()
    {
        try
        {
            var path = _workspace.SettingsPath;
            // Load-modify-write over a file that exists but cannot be read would drop every other setting.
            if (!HotkeySettings.TryLoad(path, out var stored)) return;
            var settings = stored with
            {
                AnnotationColor = $"#{_activeColor.R:X2}{_activeColor.G:X2}{_activeColor.B:X2}",
                AnnotationThickness = Math.Clamp(_activeThickness, 1, 16),
                AnnotationHighlightThickness = Math.Clamp(_activeHighlightThickness, MinimumHighlightThickness, MaximumHighlightThickness),
                AnnotationFontSize = TextMarkMetrics.Clamp(_activeFontSize),
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
