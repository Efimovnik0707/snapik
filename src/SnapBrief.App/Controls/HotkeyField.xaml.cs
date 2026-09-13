using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using SnapBrief.Windows;

namespace SnapBrief.App.Controls;

/// <summary>
/// One hotkey as a row of key capsules with a hint beside them. Clicking it (or tabbing into it)
/// starts recording, and the first non-modifier key held together with Ctrl, Alt, Shift or Win
/// writes a new hotkey id in the same "custom:{modifiers}:{virtualKey}" format the settings file has
/// always used. A key pressed alone is not a shortcut: it would be registered globally and taken
/// away from every other application, which is what a bare arrow recorded by a stray Tab did.
/// </summary>
public partial class HotkeyField : UserControl
{
    private const string IdleCaption = "Нажми, чтобы изменить";
    private const string RecordingCaption = "Нажмите своё сочетание клавиш";
    private const string NeedsModifierCaption = "Добавь Ctrl, Alt или Shift";
    private static readonly Brush IdleBorder = new SolidColorBrush(Color.FromRgb(68, 80, 100));
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
        // The recording border is the accent of the current theme, so it follows the accent the user
        // picks; a local value put back over it returns the field to its idle frame.
        if (_recording) Frame.SetResourceReference(Border.BorderBrushProperty, "FocusBrush");
        else Frame.BorderBrush = IdleBorder;
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
        // Only the two keys that are a shortcut on their own are taken on the way up, and only
        // because they never arrive on the way down. A modifier let go of is not a shortcut: with
        // Ctrl still held, releasing Shift used to be read as "Ctrl + LeftShift".
        if (key is Key.Pause or Key.Snapshot) RecordKey(key);
    }
    private void OnCaptureKeyDown(object sender, KeyEventArgs e)
    {
        if (!_recording) return;
        var key = e.Key == Key.System ? e.SystemKey : e.Key == Key.ImeProcessed ? e.ImeProcessedKey : e.Key;
        // Tab keeps walking the window instead of becoming a hotkey, and Escape leaves the recording
        // with the shortcut the field already had.
        if (key == Key.Tab) return;
        e.Handled = true;
        if (key == Key.Escape) { _recording = false; Refresh(); return; }
        if (!IsModifier(key)) RecordKey(key);
    }
    private void RecordKey(Key key) => RecordKey(key, PressedModifiers());

    private static uint PressedModifiers()
    {
        uint modifiers = 0;
        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Control)) modifiers |= (uint)HotkeyModifiers.Control;
        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Alt)) modifiers |= (uint)HotkeyModifiers.Alt;
        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Shift)) modifiers |= (uint)HotkeyModifiers.Shift;
        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Windows)) modifiers |= (uint)HotkeyModifiers.Windows;
        return modifiers;
    }

    // The modifiers are an argument rather than a reading of the keyboard, so the smoke run can hold
    // a combination the real keyboard is not holding. True means the shortcut was taken.
    internal bool RecordKey(Key key, uint modifiers)
    {
        var vk = KeyInterop.VirtualKeyFromKey(key);
        if (vk is <= 0 or >= 255 || !_recording) return false;
        // A modifier is what the shortcut is held together with, never what it ends with, whichever
        // way the key arrived here.
        if (HotkeyRules.IsModifierKey((ushort)vk)) return false;
        // Nothing is recorded and the recording goes on: the field asks for a modifier instead of
        // taking a key that would then belong to SnapBrief everywhere on the machine.
        if (modifiers == 0 && !HotkeyRules.IsShortcutOnItsOwn((ushort)vk))
        {
            Caption.Text = UiLanguage.Text(NeedsModifierCaption, _language);
            return false;
        }
        _recording = false;
        HotkeyId = $"custom:{modifiers}:{vk}";
        Refresh();
        HotkeyChanged?.Invoke(this, EventArgs.Empty);
        return true;
    }

    // Smoke probe: a key pressed alone is refused and asked for a modifier, the same key with one is
    // taken, and Print Screen stands on its own. Every capsule and caption is the real one, so the
    // probe also fails on a template that cannot be built.
    internal static void RunHotkeyFieldProbe(string language)
    {
        var field = new HotkeyField { HotkeyId = "ctrl-alt-s" };
        field.ApplyLanguage(language);
        field.Measure(new Size(360, 60));
        field.Arrange(new Rect(0, 0, 360, 60));
        field.BeginRecording();
        if (field.RecordKey(Key.Left, 0) || field.HotkeyId != "ctrl-alt-s")
            throw new InvalidOperationException("A bare key must not become a shortcut, and must leave the old one alone.");
        if (field.Caption.Text != UiLanguage.Text(NeedsModifierCaption, language))
            throw new InvalidOperationException("A bare key must be answered with a request for a modifier.");
        if (!field.RecordKey(Key.Left, (uint)HotkeyModifiers.Control) ||
            field.HotkeyId != $"custom:{(uint)HotkeyModifiers.Control}:{KeyInterop.VirtualKeyFromKey(Key.Left)}")
            throw new InvalidOperationException("The same key with a modifier must be recorded as it was pressed.");
        field.BeginRecording();
        // Ctrl held, Shift let go of: the released modifier must not become the key of the shortcut,
        // or every Ctrl+Shift on the machine would belong to SnapBrief from then on.
        var taken = field.HotkeyId;
        if (field.RecordKey(Key.LeftShift, (uint)HotkeyModifiers.Control) || field.HotkeyId != taken)
            throw new InvalidOperationException("A modifier let go of must not become the key of a shortcut.");
        if (!field.RecordKey(Key.Snapshot, 0) || field.HotkeyId != $"custom:0:{KeyInterop.VirtualKeyFromKey(Key.Snapshot)}")
            throw new InvalidOperationException("Print Screen is a shortcut on its own and must be taken without a modifier.");
    }
}
