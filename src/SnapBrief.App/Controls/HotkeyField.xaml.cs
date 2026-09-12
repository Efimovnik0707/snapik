using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using SnapBrief.Windows;

namespace SnapBrief.App.Controls;

/// <summary>
/// One hotkey as a row of key capsules with a hint beside them. Clicking it (or tabbing into it)
/// starts recording, and the first non-modifier key writes a new hotkey id in the same
/// "custom:{modifiers}:{virtualKey}" format the settings file has always used.
/// </summary>
public partial class HotkeyField : UserControl
{
    private const string IdleCaption = "Нажми, чтобы изменить";
    private const string RecordingCaption = "Нажмите своё сочетание клавиш";
    private static readonly Brush IdleBorder = new SolidColorBrush(Color.FromRgb(68, 80, 100));
    private static readonly Brush RecordingBorder = new SolidColorBrush(Color.FromRgb(122, 184, 255));
    private bool _recording;
    private string _language = UiLanguage.Current;

    public HotkeyField()
    {
        InitializeComponent();
        Refresh();
    }

    public static readonly DependencyProperty HotkeyIdProperty = DependencyProperty.Register(
        nameof(HotkeyId), typeof(string), typeof(HotkeyField),
        new PropertyMetadata(HotkeySettings.Default.CaptureId, (field, _) => ((HotkeyField)field).Refresh()));

    public string HotkeyId
    {
        get => (string)GetValue(HotkeyIdProperty);
        set => SetValue(HotkeyIdProperty, value);
    }

    /// <summary>Raised after the user records a new hotkey, never for a value set in code.</summary>
    public event EventHandler? HotkeyChanged;

    // The captions are built in code, so the field has to be told which language it is shown in.
    internal void ApplyLanguage(string language)
    {
        _language = language;
        Refresh();
    }

    private void Refresh()
    {
        if (KeyCaps is null) return;
        KeyCaps.Children.Clear();
        foreach (var part in HotkeyLabelParts.Split(HotkeySettings.Find(HotkeyId).Label)) KeyCaps.Children.Add(KeyCap(part));
        KeyCaps.Visibility = _recording ? Visibility.Collapsed : Visibility.Visible;
        Frame.BorderBrush = _recording ? RecordingBorder : IdleBorder;
        Caption.Text = UiLanguage.Text(_recording ? RecordingCaption : IdleCaption, _language);
    }

    private static Border KeyCap(string key) => new()
    {
        Margin = new Thickness(0, 0, 5, 0), Padding = new Thickness(7, 2, 7, 2), CornerRadius = new CornerRadius(5),
        Background = new SolidColorBrush(Color.FromRgb(37, 44, 54)),
        BorderBrush = new SolidColorBrush(Color.FromRgb(70, 83, 102)), BorderThickness = new Thickness(1),
        Child = new TextBlock { Text = key, FontSize = 11, FontWeight = FontWeights.SemiBold, Foreground = new SolidColorBrush(Color.FromRgb(238, 242, 248)) }
    };

    private void BeginRecording()
    {
        _recording = true;
        Refresh();
    }

    private void OnBeginRecording(object sender, KeyboardFocusChangedEventArgs e) => BeginRecording();
    private void OnBeginRecordingClick(object sender, MouseButtonEventArgs e) { Focus(); BeginRecording(); }
    // Focus can leave the field without a key ever arriving; the capsules must come back then.
    private void OnLostFocus(object sender, KeyboardFocusChangedEventArgs e) { _recording = false; Refresh(); }
    private static bool IsModifier(Key key) => key is Key.LeftCtrl or Key.RightCtrl or Key.LeftAlt or Key.RightAlt or Key.LeftShift or Key.RightShift or Key.LWin or Key.RWin;
    private void OnCaptureKeyUp(object sender, KeyEventArgs e)
    {
        if (!_recording) return;
        var key = e.Key == Key.System ? e.SystemKey : e.Key;
        e.Handled = true;
        if (key is Key.Pause or Key.Snapshot || IsModifier(key)) RecordKey(key);
    }
    private void OnCaptureKeyDown(object sender, KeyEventArgs e)
    {
        if (!_recording) return;
        e.Handled = true;
        var key = e.Key == Key.System ? e.SystemKey : e.Key == Key.ImeProcessed ? e.ImeProcessedKey : e.Key;
        if (!IsModifier(key)) RecordKey(key);
    }
    private void RecordKey(Key key)
    {
        var vk = KeyInterop.VirtualKeyFromKey(key);
        if (vk is <= 0 or >= 255 || !_recording) return;
        uint modifiers = 0;
        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Control)) modifiers |= (uint)HotkeyModifiers.Control;
        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Alt)) modifiers |= (uint)HotkeyModifiers.Alt;
        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Shift)) modifiers |= (uint)HotkeyModifiers.Shift;
        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Windows)) modifiers |= (uint)HotkeyModifiers.Windows;
        _recording = false;
        HotkeyId = $"custom:{modifiers}:{vk}";
        Refresh();
        HotkeyChanged?.Invoke(this, EventArgs.Empty);
    }
}
