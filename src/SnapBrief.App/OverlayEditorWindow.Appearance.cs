using System;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;
using SnapBrief.Core.Models;

namespace SnapBrief.App;

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
    internal static readonly double[] ThicknessPresets = [2, 4, 6, 8];
    private static bool HasColor(EditorTool tool) => tool is EditorTool.Rectangle or EditorTool.Arrow or EditorTool.Pen or EditorTool.Highlight or EditorTool.Text;
    private static bool HasStroke(EditorTool tool) => HasColor(tool) && tool != EditorTool.Text;
    // The frame is shared by a region and by a blur: one shape is remembered for both. What stands
    // inside the frame belongs to the region alone, a blur has its own picture inside it.
    private static bool HasShape(EditorTool tool) => tool is EditorTool.Rectangle or EditorTool.Blur;
    private static bool HasFill(EditorTool tool) => tool == EditorTool.Rectangle;

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
        // Until the palettes from the test come in, this set is a proposal and nothing else.
        new("neon", "Неон",
            ["#FF1744", "#FF6D00", "#FFEA00", "#C6FF00", "#00E676", "#1DE9B6", "#00E5FF", "#2979FF", "#651FFF", "#D500F9", "#FF4081", "#FFFFFF"],
            ["#FF1744", "#FFEA00", "#00E676", "#2979FF", "#FFFFFF"])
    ];

    // Which of the two circles of the popover the palette and the HEX field paint.
    private enum ColorTarget { Outline, Fill }
    private ColorTarget _colorTarget = ColorTarget.Outline;

    // What one click on the panel changes: the outline while the mark has one, the fill otherwise,
    // so a click stays meaningful for a black concealing box as well.
    private ColorTarget MainTarget
    {
        get
        {
            var selected = Surface.SelectedAnnotation;
            var tool = selected?.Kind ?? Surface.Tool;
            if (!HasFill(tool)) return ColorTarget.Outline;
            return (selected?.HasOutline ?? _activeHasOutline) ? ColorTarget.Outline : ColorTarget.Fill;
        }
    }

    private void OpenAppearance()
    {
        if (AppearancePopup.IsOpen) { AppearancePopup.IsOpen = false; return; }
        if (_capture is null) return;
        _appearanceBefore = SnapshotState();
        _appearanceChanged = false;
        _colorTarget = MainTarget;
        BuildColorPalette();
        SyncAppearance();
        AppearancePopup.IsOpen = true;
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

    // The twelve swatches of the active palette; rebuilt when another palette is picked.
    private void BuildColorPalette()
    {
        ColorPalette.Children.Clear();
        foreach (var hex in _activePalette.Colors)
        {
            var color = (Color)ColorConverter.ConvertFromString(hex);
            var swatch = new Button { Width = 34, MinWidth = 34, Height = 34, Margin = new Thickness(3), Padding = new Thickness(4), Tag = color,
                Style = (Style)FindResource("OverlayButton"), ToolTip = hex,
                Content = new Ellipse { Width = 22, Height = 22, Fill = new SolidColorBrush(color), Stroke = new SolidColorBrush(Color.FromRgb(120, 130, 146)), StrokeThickness = 1 } };
            System.Windows.Automation.AutomationProperties.SetName(swatch, hex);
            swatch.Click += (_, _) => ApplyPickedColor(color);
            ColorPalette.Children.Add(swatch);
        }
    }

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
        CommentToolButton.Background = Surface.Tool == EditorTool.Comment ? (Brush)FindResource("AccentSoftBrush") : Brushes.Transparent;
        UndoButton.IsEnabled = _undo.Count > 0;
        RedoButton.IsEnabled = _redo.Count > 0;
        var selected = Surface.SelectedAnnotation;
        var tool = selected?.Kind ?? Surface.Tool;
        var color = selected?.Color ?? _activeColor;
        var thickness = selected?.Thickness ?? _activeThickness;
        var outline = selected?.HasOutline ?? _activeHasOutline;
        var fillColor = (selected is not null ? selected.FillColor : _activeFillColor) ?? color;
        // The circle on the panel and the dots beside it work on the colour that is actually seen:
        // the outline while there is one, the fill of a frame without an outline.
        var mainColor = MainTarget == ColorTarget.Fill ? fillColor : color;
        var targetColor = _colorTarget == ColorTarget.Fill ? fillColor : color;
        AppearanceButton.IsEnabled = HasColor(tool);
        ColorSwatch.Fill = new SolidColorBrush(mainColor);
        // A tool without a stroke leaves the last thickness on the button, dimmed by the disabled
        // state of the style: an empty caption is what used to make the panel jump.
        ThicknessButton.IsEnabled = HasStroke(tool);
        ThicknessButton.Content = $"{(HasStroke(tool) ? thickness : _activeThickness):0} px";
        ColorHex.Text = $"#{targetColor.R:X2}{targetColor.G:X2}{targetColor.B:X2}";
        ColorHex.BorderBrush = new SolidColorBrush(Color.FromRgb(70, 83, 102));
        StrokeSlider.IsEnabled = HasStroke(tool);
        StrokeSlider.Value = Math.Clamp(thickness, 1, 16);
        StrokeValue.Text = HasStroke(tool) ? $"{thickness:0} px" : "—";
        StrokePreview.Stroke = new SolidColorBrush(color);
        StrokePreview.StrokeThickness = thickness;
        StrokePreview.Visibility = HasStroke(tool) ? Visibility.Visible : Visibility.Hidden;
        foreach (System.Windows.Controls.Primitives.ToggleButton preset in ThicknessPresetRow.Children)
            preset.IsChecked = preset.Tag is string tag && double.TryParse(tag, System.Globalization.CultureInfo.InvariantCulture, out var value) && Math.Abs(value - thickness) < 0.001;
        foreach (Button swatch in ColorPalette.Children)
            swatch.BorderBrush = (Color)swatch.Tag == targetColor ? Brushes.White : Brushes.Transparent;
        foreach (System.Windows.Controls.Primitives.ToggleButton segment in PaletteRow.Children)
            segment.IsChecked = (string)segment.Tag == _activePalette.Id;
        // The outline and the fill of a frame: their colours, the switch that hides the outline and
        // the four ways the inside of the frame can be filled.
        OutlineRow.IsEnabled = HasFill(tool);
        OutlineSegment.IsChecked = outline;
        OutlineSwatch.Fill = new SolidColorBrush(color);
        FillSwatch.Fill = new SolidColorBrush(fillColor);
        OutlineColorButton.BorderBrush = _colorTarget == ColorTarget.Outline ? Brushes.White : Brushes.Transparent;
        FillColorButton.BorderBrush = _colorTarget == ColorTarget.Fill ? Brushes.White : Brushes.Transparent;
        OutlineColorButton.IsEnabled = HasColor(tool);
        // The chevron half of a split button carries the state of its own tool, so the capsule
        // reads as one control.
        var accent = (Brush)FindResource("AccentSoftBrush");
        ShapeMenuButton.Background = Surface.Tool == EditorTool.Rectangle ? accent : Brushes.Transparent;
        ArrowMenuButton.Background = Surface.Tool == EditorTool.Arrow ? accent : Brushes.Transparent;
        ColorDots.IsEnabled = HasColor(tool);
        foreach (Button dot in ColorDots.Children)
            ((Ellipse)dot.Content).Stroke = (Color)dot.Tag == color
                ? Brushes.White
                : new SolidColorBrush(Color.FromRgb(120, 130, 146));
        var fill = selected?.Fill ?? Surface.ActiveFill;
        FillRow.IsEnabled = HasFill(tool);
        FillNoneSegment.IsChecked = fill == AnnotationFill.None;
        FillSolidSegment.IsChecked = fill == AnnotationFill.Solid;
        FillTranslucentSegment.IsChecked = fill == AnnotationFill.Translucent;
        FillBlurSegment.IsChecked = fill == AnnotationFill.Blur;
        // A blurred region shows the picture under it: it has no colour of its own to pick.
        FillColorButton.IsEnabled = HasFill(tool) && fill is AnnotationFill.Solid or AnnotationFill.Translucent;
        var extra = Surface.Tool is EditorTool.Pen or EditorTool.Highlight;
        MoreToolsButton.Background = extra ? (Brush)FindResource("AccentSoftBrush") : Brushes.Transparent;
        MoreToolsButton.ToolTip = extra ? $"{UiLanguage.Text("Ещё инструменты")} · {EditorShortcuts.Caption(Surface.Tool)}" : UiLanguage.Text("Ещё инструменты");
        _syncingAppearance = false;
    }

    private void ApplyAppearance(Color? color, double? thickness, AnnotationShape? shape = null, AnnotationFill? fill = null,
        string? arrowStyle = null, Color? fillColor = null, bool? hasOutline = null)
    {
        var selected = Surface.SelectedAnnotation;
        var tool = selected?.Kind ?? Surface.Tool;
        if (color is { } c && HasColor(tool)) { _appearanceDefaultsChanged |= c != _activeColor; _activeColor = c; Surface.ActiveColor = c; if (selected is not null) { selected.Color = c; _appearanceChanged = true; } }
        if (thickness is { } t && HasStroke(tool)) { _appearanceDefaultsChanged |= t != _activeThickness; _activeThickness = t; Surface.ActiveThickness = t; if (selected is not null) { selected.Thickness = t; _appearanceChanged = true; } }
        if (shape is { } s && HasShape(tool)) { _appearanceDefaultsChanged |= s != _activeShape; _activeShape = s; Surface.ActiveShape = s; if (selected is not null) { selected.Shape = s; _appearanceChanged = true; } }
        if (fill is { } f && HasFill(tool)) { _appearanceDefaultsChanged |= f != _activeFill; _activeFill = f; Surface.ActiveFill = f; if (selected is not null) { selected.Fill = f; _appearanceChanged = true; } }
        if (fillColor is { } fc && HasFill(tool)) { _appearanceDefaultsChanged |= fc != _activeFillColor; _activeFillColor = fc; Surface.ActiveFillColor = fc; if (selected is not null) { selected.FillColor = fc; _appearanceChanged = true; } }
        if (hasOutline is { } outline && HasFill(tool)) { _appearanceDefaultsChanged |= outline != _activeHasOutline; _activeHasOutline = outline; Surface.ActiveHasOutline = outline; if (selected is not null) { selected.HasOutline = outline; _appearanceChanged = true; } }
        if (arrowStyle is { } style && tool == EditorTool.Arrow) { Surface.ActiveArrowStyle = style; if (selected is not null) { selected.ArrowStyle = style; _appearanceChanged = true; } }
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

    // A colour picked in the popover paints whichever of the two circles is active; a colour picked
    // on the panel paints the one that is actually seen.
    private void ApplyPickedColor(Color color)
    {
        if (_colorTarget == ColorTarget.Fill) ApplyAppearance(null, null, fillColor: color);
        else ApplyAppearance(color, null);
    }

    private void ApplyQuickColor(Color color)
    {
        if (MainTarget == ColorTarget.Fill) ApplyAppearanceNow(null, null, fillColor: color);
        else ApplyAppearanceNow(color, null);
    }

    private void OnFillClick(object sender, RoutedEventArgs e)
    {
        if (_syncingAppearance || sender is not System.Windows.Controls.Primitives.ToggleButton { Tag: string tag } ||
            !Enum.TryParse<AnnotationFill>(tag, out var fill)) return;
        // Picking a coloured fill moves the target to it: the next colour is the one the user came for.
        _colorTarget = fill is AnnotationFill.Solid or AnnotationFill.Translucent ? ColorTarget.Fill : ColorTarget.Outline;
        ApplyAppearance(null, null, fill: fill);
    }

    private void OnOutlineClick(object sender, RoutedEventArgs e)
    {
        if (_syncingAppearance || sender is not System.Windows.Controls.Primitives.ToggleButton segment) return;
        ApplyAppearance(null, null, hasOutline: segment.IsChecked == true);
    }

    private void OnOutlineTargetClick(object sender, RoutedEventArgs e) { _colorTarget = ColorTarget.Outline; SyncAppearance(); }
    private void OnFillTargetClick(object sender, RoutedEventArgs e) { _colorTarget = ColorTarget.Fill; SyncAppearance(); }

    private void OnPaletteClick(object sender, RoutedEventArgs e)
    {
        if (_syncingAppearance || sender is not System.Windows.Controls.Primitives.ToggleButton { Tag: string id }) return;
        SelectPalette(ParseAnnotationPalette(id));
    }

    internal void SelectPalette(PaletteSet palette)
    {
        if (ReferenceEquals(palette, _activePalette)) { SyncAppearance(); return; }
        _activePalette = palette;
        _appearanceDefaultsChanged = true;
        BuildColorPalette();
        BuildColorDots();
        SyncAppearance();
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
            ApplyPickedColor(Color.FromRgb((byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb));
        else ColorHex.BorderBrush = new SolidColorBrush(Color.FromRgb(255, 110, 110));
    }
    private void OnHexLostFocus(object sender, KeyboardFocusChangedEventArgs e) { if (!_syncingAppearance) ApplyHex(); }
    private void OnHexKeyDown(object sender, KeyEventArgs e) { if (e.Key == Key.Enter) { ApplyHex(); e.Handled = true; } }
    private void OnAppearanceKeyDown(object sender, KeyEventArgs e) { if (e.Key == Key.Escape) { AppearancePopup.IsOpen = false; e.Handled = true; } }
    private void OnThicknessKeyDown(object sender, KeyEventArgs e) { if (e.Key == Key.Escape) { ThicknessPopup.IsOpen = false; e.Handled = true; } }
    private void OnCloseAppearance(object sender, RoutedEventArgs e) => AppearancePopup.IsOpen = false;
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

    // The editor window is created again for every capture, so the whole panel (colour, thickness,
    // shape and fill) lives in the settings file and becomes the defaults for the next one.
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
                AnnotationShape = _activeShape.ToString().ToLowerInvariant(),
                AnnotationFill = _activeFill.ToString().ToLowerInvariant(),
                AnnotationFillColor = _activeFillColor is { } fillColor ? $"#{fillColor.R:X2}{fillColor.G:X2}{fillColor.B:X2}" : string.Empty,
                AnnotationOutline = _activeHasOutline,
                AnnotationPalette = _activePalette.Id
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

    // A settings file written by hand, or by a build that knew other names, falls back to the frame
    // the editor started with. Only a name counts: Enum.TryParse also reads "2" as a value, and a
    // number in the file must not quietly become a shape.
    internal static AnnotationShape ParseAnnotationShape(string? value) =>
        Enum.TryParse<AnnotationShape>(value, ignoreCase: true, out var shape) &&
        string.Equals(shape.ToString(), value, StringComparison.OrdinalIgnoreCase) ? shape : AnnotationShape.Rectangle;

    // An empty value is a real preference: "the fill takes the colour of the outline". Only a value
    // that cannot be read at all falls back to it as well.
    internal static Color? ParseAnnotationFillColor(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        try { return ColorConverter.ConvertFromString(value) is Color color ? color : null; }
        catch (Exception) { return null; }
    }

    internal static AnnotationFill ParseAnnotationFill(string? value) =>
        Enum.TryParse<AnnotationFill>(value, ignoreCase: true, out var fill) &&
        string.Equals(fill.ToString(), value, StringComparison.OrdinalIgnoreCase) ? fill : AnnotationFill.None;

    // A palette written by hand, or by a build that knew other sets, falls back to the standard one.
    internal static PaletteSet ParseAnnotationPalette(string? value) =>
        Palettes.FirstOrDefault(palette => string.Equals(palette.Id, value, StringComparison.OrdinalIgnoreCase)) ?? Palettes[0];
}
