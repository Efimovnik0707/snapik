using System;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;

namespace SnapBrief.App;

public partial class OverlayEditorWindow
{
    private bool _syncingAppearance;
    private OverlaySnapshot? _appearanceBefore;
    private bool _appearanceChanged;
    private bool _appearanceDefaultsChanged;
    internal static readonly Color DefaultAnnotationColor = Color.FromRgb(47, 140, 255);
    internal const double DefaultAnnotationThickness = 4;
    private static bool HasColor(EditorTool tool) => tool is EditorTool.Rectangle or EditorTool.Arrow or EditorTool.Pen or EditorTool.Highlight or EditorTool.Text;
    private static bool HasStroke(EditorTool tool) => HasColor(tool) && tool != EditorTool.Text;

    private void OpenAppearance()
    {
        if (AppearancePopup.IsOpen) { AppearancePopup.IsOpen = false; return; }
        if (_capture is null) return;
        _appearanceBefore = SnapshotState();
        _appearanceChanged = false;
        if (ColorPalette.Children.Count == 0)
        {
            foreach (var hex in new[] { "#2F8CFF", "#FF4D4F", "#FFBE2E", "#28BE80", "#AF81FF", "#FF79B7", "#FFFFFF", "#000000", "#00C8DC", "#FF8C42", "#9BA7B8", "#7754D9" })
            {
                var color = (Color)ColorConverter.ConvertFromString(hex);
                var swatch = new Button { Width = 34, MinWidth = 34, Height = 34, Margin = new Thickness(3), Padding = new Thickness(4), Tag = color,
                    Style = (Style)FindResource("OverlayButton"), ToolTip = hex,
                    Content = new Ellipse { Width = 22, Height = 22, Fill = new SolidColorBrush(color), Stroke = new SolidColorBrush(Color.FromRgb(120, 130, 146)), StrokeThickness = 1 } };
                System.Windows.Automation.AutomationProperties.SetName(swatch, hex);
                swatch.Click += (_, _) => ApplyAppearance(color, null);
                ColorPalette.Children.Add(swatch);
            }
        }
        SyncAppearance();
        AppearancePopup.IsOpen = true;
    }

    private void SyncAppearance()
    {
        if (AppearanceButton is null || StrokeSlider is null) return;
        _syncingAppearance = true;
        ArrowOptionsButton.ToolTip = UiLanguage.Text("Стиль стрелки");
        CommentToolButton.Background = Surface.Tool == EditorTool.Comment ? (Brush)FindResource("AccentSoftBrush") : Brushes.Transparent;
        UndoButton.IsEnabled = _undo.Count > 0;
        RedoButton.IsEnabled = _redo.Count > 0;
        var selected = Surface.SelectedAnnotation;
        var tool = selected?.Kind ?? Surface.Tool;
        var color = selected?.Color ?? _activeColor;
        var thickness = selected?.Thickness ?? _activeThickness;
        AppearanceButton.IsEnabled = HasColor(tool);
        ColorSwatch.Fill = new SolidColorBrush(color);
        AppearanceValue.Text = HasStroke(tool) ? $"{thickness:0} px" : "";
        ColorHex.Text = $"#{color.R:X2}{color.G:X2}{color.B:X2}";
        ColorHex.BorderBrush = new SolidColorBrush(Color.FromRgb(70, 83, 102));
        StrokeSlider.IsEnabled = HasStroke(tool);
        StrokeSlider.Value = Math.Clamp(thickness, 1, 16);
        StrokeValue.Text = HasStroke(tool) ? $"{thickness:0} px" : "—";
        StrokePreview.Stroke = new SolidColorBrush(color);
        StrokePreview.StrokeThickness = thickness;
        StrokePreview.Visibility = HasStroke(tool) ? Visibility.Visible : Visibility.Hidden;
        foreach (Button swatch in ColorPalette.Children)
            swatch.BorderBrush = (Color)swatch.Tag == color ? Brushes.White : Brushes.Transparent;
        var extra = Surface.Tool is EditorTool.Pen or EditorTool.Highlight or EditorTool.Conceal;
        MoreToolsButton.Background = extra ? (Brush)FindResource("AccentSoftBrush") : Brushes.Transparent;
        MoreToolsButton.ToolTip = extra ? $"{UiLanguage.Text("Ещё инструменты")} · {EditorShortcuts.Caption(Surface.Tool)}" : UiLanguage.Text("Ещё инструменты");
        _syncingAppearance = false;
    }

    private void ApplyAppearance(Color? color, double? thickness)
    {
        var selected = Surface.SelectedAnnotation;
        var tool = selected?.Kind ?? Surface.Tool;
        if (color is { } c && HasColor(tool)) { _appearanceDefaultsChanged |= c != _activeColor; _activeColor = c; Surface.ActiveColor = c; if (selected is not null) { selected.Color = c; _appearanceChanged = true; } }
        if (thickness is { } t && HasStroke(tool)) { _appearanceDefaultsChanged |= t != _activeThickness; _activeThickness = t; Surface.ActiveThickness = t; if (selected is not null) { selected.Thickness = t; _appearanceChanged = true; } }
        Surface.InvalidateVisual();
        SyncAppearance();
    }

    private void OnStrokeChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (!_syncingAppearance && AppearancePopup?.IsOpen == true) ApplyAppearance(null, Math.Round(e.NewValue));
    }
    private void ApplyHex()
    {
        var value = ColorHex.Text.Trim();
        if (value.StartsWith('#')) value = value[1..];
        if (value.Length == 6 && uint.TryParse(value, System.Globalization.NumberStyles.HexNumber, null, out var rgb))
            ApplyAppearance(Color.FromRgb((byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb), null);
        else ColorHex.BorderBrush = new SolidColorBrush(Color.FromRgb(255, 110, 110));
    }
    private void OnHexLostFocus(object sender, KeyboardFocusChangedEventArgs e) { if (!_syncingAppearance) ApplyHex(); }
    private void OnHexKeyDown(object sender, KeyEventArgs e) { if (e.Key == Key.Enter) { ApplyHex(); e.Handled = true; } }
    private void OnAppearanceKeyDown(object sender, KeyEventArgs e) { if (e.Key == Key.Escape) { AppearancePopup.IsOpen = false; e.Handled = true; } }
    private void OnCloseAppearance(object sender, RoutedEventArgs e) => AppearancePopup.IsOpen = false;
    private void OnAppearanceClosed(object? sender, EventArgs e)
    {
        if (_appearanceChanged && _appearanceBefore is not null && _capture is not null)
        {
            _undo.Push(_appearanceBefore); _redo.Clear(); _lastSnapshot = SnapshotState();
        }
        _appearanceBefore = null; _appearanceChanged = false;
        FlushAppearanceDefaults();
        SyncAppearance();
        Surface.Focus();
    }

    // The popover normally writes the defaults when it closes, but a window completed by the global
    // capture hotkey never raises Popup.Closed, so the editor flushes them while closing as well.
    private void FlushAppearanceDefaults()
    {
        if (!_appearanceDefaultsChanged) return;
        _appearanceDefaultsChanged = false;
        SaveAppearanceDefaults();
    }

    // The editor window is created again for every capture, so the last picked colour
    // and thickness live in the settings file and become the defaults for the next one.
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
                AnnotationThickness = Math.Clamp(_activeThickness, 1, 16)
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
}
