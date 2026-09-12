using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Windows;
using System.Windows.Input;
using SnapBrief.Windows;

namespace SnapBrief.App;

public sealed record HotkeyChoice(string Id, string Label, HotkeyGesture Gesture);

public sealed record HotkeySettings(string CaptureId, string PasteId)
{
    public bool CaptureEnabled { get; init; } = true;
    public bool FullscreenSaveEnabled { get; init; }
    public string FullscreenSaveId { get; init; } = "custom:4:44";
    public bool ShowNotifications { get; init; } = true;
    public bool RememberRegion { get; init; }
    public bool CaptureCursor { get; init; }
    public bool AutoSaveCaptures { get; init; }
    public bool PlaySounds { get; init; } = true;
    public bool StackTopmost { get; init; } = true;
    public string AnnotationColor { get; init; } = "#2F8CFF";
    public double AnnotationThickness { get; init; } = 4;
    public string SaveFormat { get; init; } = "png";
    public int JpegQuality { get; init; } = 90;
    public string SaveDirectory { get; init; } = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyPictures), "SnapBrief");
    public string Language { get; init; } = "ru";
    public HotkeyGesture FullscreenSaveGesture => Find(FullscreenSaveId).Gesture;

    public static HotkeySettings Default { get; } = new("ctrl-alt-s", "ctrl-alt-v");
    public static IReadOnlyList<HotkeyChoice> Choices { get; } =
    [
        new("ctrl-alt-s", "Ctrl + Alt + S", new(HotkeyModifiers.Control | HotkeyModifiers.Alt | HotkeyModifiers.NoRepeat, 0x53)),
        new("ctrl-shift-s", "Ctrl + Shift + S", new(HotkeyModifiers.Control | HotkeyModifiers.Shift | HotkeyModifiers.NoRepeat, 0x53)),
        new("alt-s", "Alt + S", new(HotkeyModifiers.Alt | HotkeyModifiers.NoRepeat, 0x53)),
        new("print-screen", "Print Screen", new(HotkeyModifiers.NoRepeat, 0x2C)),
        new("ctrl-alt-v", "Ctrl + Alt + V", new(HotkeyModifiers.Control | HotkeyModifiers.Alt | HotkeyModifiers.NoRepeat, 0x56)),
        new("ctrl-shift-v", "Ctrl + Shift + V", new(HotkeyModifiers.Control | HotkeyModifiers.Shift | HotkeyModifiers.NoRepeat, 0x56)),
        new("alt-v", "Alt + V", new(HotkeyModifiers.Alt | HotkeyModifiers.NoRepeat, 0x56))
    ];
    public static IReadOnlyList<HotkeyChoice> PasteChoices { get; } =
        System.Linq.Enumerable.Where(Choices, choice => choice.Id != "print-screen").ToArray();

    public HotkeyGesture CaptureGesture => Find(CaptureId).Gesture;
    public HotkeyGesture PasteGesture => Find(PasteId).Gesture;

    public static HotkeySettings Load(string path)
    {
        try { return File.Exists(path) ? JsonSerializer.Deserialize<HotkeySettings>(File.ReadAllText(path)) ?? Default : Default; }
        catch { return Default; }
    }

    public void Save(string path)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true }));
    }

    public static HotkeyChoice Find(string id)
    {
        var preset = Choices.FirstOrDefault(c => c.Id == id);
        if (preset is not null) return preset;
        var parts = id.Split(':');
        if (parts.Length == 3 && parts[0] == "custom" && uint.TryParse(parts[1], out var modifiers) &&
            uint.TryParse(parts[2], out var key) && key is > 0 and < 255 &&
            (modifiers & ~15u) == 0)
        {
            var flags = (HotkeyModifiers)modifiers;
            var label = string.Empty;
            if (flags.HasFlag(HotkeyModifiers.Control)) label += "Ctrl + ";
            if (flags.HasFlag(HotkeyModifiers.Alt)) label += "Alt + ";
            if (flags.HasFlag(HotkeyModifiers.Shift)) label += "Shift + ";
            if (flags.HasFlag(HotkeyModifiers.Windows)) label += "Win + ";
            label += key == 0x13 ? "Pause / Break" : key == 0x2C ? "Print Screen" : KeyInterop.KeyFromVirtualKey((int)key).ToString();
            return new HotkeyChoice(id, label, new HotkeyGesture(flags | HotkeyModifiers.NoRepeat, (ushort)key));
        }
        return Choices[0];
    }
}

public partial class HotkeySettingsWindow : Window
{
    private readonly HotkeySettings _original;
    private string _captureId;
    private string _fullscreenId;
    private System.Windows.Controls.TextBox? _recordingBox;
    public Func<HotkeySettings, string?>? TryApply { get; init; }
    public HotkeySettings? Result { get; private set; }

    public HotkeySettingsWindow(HotkeySettings settings, bool showPasteSettings = false)
    {
        _original = settings;
        _captureId = settings.CaptureId;
        _fullscreenId = settings.FullscreenSaveId;
        InitializeComponent();
        CaptureBox.Text = HotkeySettings.Find(_captureId).Label;
        FullscreenBox.Text = HotkeySettings.Find(_fullscreenId).Label;
        CaptureEnabledBox.IsChecked = settings.CaptureEnabled;
        FullscreenEnabledBox.IsChecked = settings.FullscreenSaveEnabled;
        NotificationsBox.IsChecked = settings.ShowNotifications;
        RememberBox.IsChecked = settings.RememberRegion;
        CursorBox.IsChecked = settings.CaptureCursor;
        AutoSaveBox.IsChecked = settings.AutoSaveCaptures;
        SoundsBox.IsChecked = settings.PlaySounds;
        FormatBox.SelectedIndex = settings.SaveFormat == "jpeg" ? 1 : 0;
        QualitySlider.Value = Math.Clamp(settings.JpegQuality, 1, 100);
        DirectoryBox.Text = settings.SaveDirectory;
        LanguageBox.SelectedIndex = settings.Language == "en" ? 1 : 0;
        Loaded += (_, _) => UiLanguage.Apply(this, settings.Language);
    }

    private void BeginRecording(System.Windows.Controls.TextBox box)
    {
        _recordingBox = box;
        box.Text = UiLanguage.Text("Нажмите клавишу…", _original.Language);
        ErrorText.Visibility = Visibility.Collapsed;
    }
    private void OnBeginRecording(object sender, KeyboardFocusChangedEventArgs e) => BeginRecording((System.Windows.Controls.TextBox)sender);
    private void OnBeginRecordingClick(object sender, MouseButtonEventArgs e) => BeginRecording((System.Windows.Controls.TextBox)sender);
    private static bool IsModifier(Key key) => key is Key.LeftCtrl or Key.RightCtrl or Key.LeftAlt or Key.RightAlt or Key.LeftShift or Key.RightShift or Key.LWin or Key.RWin;
    private void OnCaptureKeyUp(object sender, KeyEventArgs e)
    {
        if (_recordingBox is null) return;
        var key = e.Key == Key.System ? e.SystemKey : e.Key;
        e.Handled = true;
        if (key is Key.Pause or Key.Snapshot || IsModifier(key)) RecordKey(key);
    }
    private void OnCaptureKeyDown(object sender, KeyEventArgs e)
    {
        if (_recordingBox is null) return;
        e.Handled = true;
        var key = e.Key == Key.System ? e.SystemKey : e.Key == Key.ImeProcessed ? e.ImeProcessedKey : e.Key;
        if (!IsModifier(key)) RecordKey(key);
    }
    private void RecordKey(Key key)
    {
        var vk = KeyInterop.VirtualKeyFromKey(key);
        if (vk is <= 0 or >= 255 || _recordingBox is null) return;
        uint modifiers = 0;
        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Control)) modifiers |= (uint)HotkeyModifiers.Control;
        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Alt)) modifiers |= (uint)HotkeyModifiers.Alt;
        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Shift)) modifiers |= (uint)HotkeyModifiers.Shift;
        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Windows)) modifiers |= (uint)HotkeyModifiers.Windows;
        var id = $"custom:{modifiers}:{vk}";
        if (ReferenceEquals(_recordingBox, CaptureBox)) _captureId = id; else _fullscreenId = id;
        _recordingBox.Text = HotkeySettings.Find(id).Label;
        _recordingBox = null;
        SaveButton.Focus();
    }
    private void OnBrowseDirectory(object sender, RoutedEventArgs e)
    {
        var dialog = new Microsoft.Win32.OpenFolderDialog { InitialDirectory = Directory.Exists(DirectoryBox.Text) ? DirectoryBox.Text : Environment.GetFolderPath(Environment.SpecialFolder.MyPictures) };
        if (dialog.ShowDialog(this) == true) DirectoryBox.Text = dialog.FolderName;
    }
    private void OnHeaderDrag(object sender, MouseButtonEventArgs e) { if (e.LeftButton == MouseButtonState.Pressed) DragMove(); }
    private void OnSave(object sender, RoutedEventArgs e)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(DirectoryBox.Text))
                throw new InvalidOperationException(UiLanguage.Text("Укажите папку сохранения.", _original.Language));
            var directory = Path.GetFullPath(DirectoryBox.Text);
            Result = _original with
            {
                CaptureId = _captureId, FullscreenSaveId = _fullscreenId,
                CaptureEnabled = CaptureEnabledBox.IsChecked == true,
                FullscreenSaveEnabled = FullscreenEnabledBox.IsChecked == true,
                ShowNotifications = NotificationsBox.IsChecked == true,
                RememberRegion = RememberBox.IsChecked == true, CaptureCursor = CursorBox.IsChecked == true,
                AutoSaveCaptures = AutoSaveBox.IsChecked == true,
                PlaySounds = SoundsBox.IsChecked == true,
                SaveFormat = FormatBox.SelectedIndex == 1 ? "jpeg" : "png",
                JpegQuality = (int)QualitySlider.Value, SaveDirectory = directory,
                Language = LanguageBox.SelectedIndex == 1 ? "en" : "ru"
            };
            var error = TryApply?.Invoke(Result);
            if (error is not null) throw new InvalidOperationException(error);
            DialogResult = true;
        }
        catch (Exception ex) { ErrorText.Text = UiLanguage.Text(ex.Message, _original.Language); ErrorText.Visibility = Visibility.Visible; Result = null; }
    }
}
