using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
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
    public bool ClearStackAfterPaste { get; init; }
    public string AnnotationColor { get; init; } = "#2F8CFF";
    public double AnnotationThickness { get; init; } = 4;
    public string SaveFormat { get; init; } = "png";
    public int JpegQuality { get; init; } = 92;
    public string SaveDirectory { get; init; } = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyPictures), "SnapBrief");
    public string Language { get; init; } = "ru";
    /// <summary>The version of the first run wizard this file has already seen; 0 means "never".</summary>
    public int OnboardingVersion { get; init; }
    public string Theme { get; init; } = "dark";
    public string AccentId { get; init; } = "blue";
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

    public static HotkeySettings Load(string path) => TryLoad(path, out var settings) ? settings : Default;

    // A missing file means "nothing saved yet" and may be overwritten with defaults; a file that
    // exists but does not parse must be left alone, otherwise one bad read wipes every preference.
    public static bool TryLoad(string path, out HotkeySettings settings)
    {
        settings = Default;
        try
        {
            if (!File.Exists(path)) return true;
            var content = File.ReadAllText(path);
            // A file truncated to nothing (or to blanks) carries no preferences: it is "nothing saved yet" too.
            if (string.IsNullOrWhiteSpace(content)) return true;
            if (JsonSerializer.Deserialize<HotkeySettings>(content) is not { } stored) return false;
            // JSON without the hotkey ids builds a record with empty ones, and every Find over them would fail.
            if (string.IsNullOrEmpty(stored.CaptureId) || string.IsNullOrEmpty(stored.PasteId)) return false;
            settings = stored;
            return true;
        }
        catch { return false; }
    }

    // Written through a neighbouring temporary file: a write interrupted halfway must not leave
    // a truncated file where every preference lived, because such a file no longer loads. The name
    // of that file carries the process id, so a second SnapBrief (or a smoke run against the same
    // directory) writes its own; a write that failed takes its temporary file with it.
    public void Save(string path)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var temporary = $"{path}.{Environment.ProcessId}.tmp";
        try
        {
            File.WriteAllText(temporary, JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true }));
            File.Move(temporary, path, overwrite: true);
        }
        catch
        {
            try { File.Delete(temporary); } catch (IOException) { } catch (UnauthorizedAccessException) { }
            throw;
        }
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
    private string _language;
    public Func<HotkeySettings, string?>? TryApply { get; init; }
    public HotkeySettings? Result { get; private set; }

    public HotkeySettingsWindow(HotkeySettings settings, bool showPasteSettings = false)
    {
        _original = settings;
        _language = settings.Language;
        InitializeComponent();
        CaptureField.HotkeyId = settings.CaptureId;
        FullscreenField.HotkeyId = settings.FullscreenSaveId;
        CaptureEnabledBox.IsChecked = settings.CaptureEnabled;
        FullscreenEnabledBox.IsChecked = settings.FullscreenSaveEnabled;
        NotificationsBox.IsChecked = settings.ShowNotifications;
        RememberBox.IsChecked = settings.RememberRegion;
        CursorBox.IsChecked = settings.CaptureCursor;
        AutoSaveBox.IsChecked = settings.AutoSaveCaptures;
        SoundsBox.IsChecked = settings.PlaySounds;
        ClearStackBox.IsChecked = settings.ClearStackAfterPaste;
        FormatBox.SelectedIndex = settings.SaveFormat == "jpeg" ? 1 : 0;
        QualitySlider.Value = Math.Clamp(settings.JpegQuality, 1, 100);
        DirectoryBox.Text = settings.SaveDirectory;
        LanguageBox.SelectedIndex = settings.Language == "en" ? 1 : 0;
        BuildAccentRow(settings.AccentId);
        QualitySlider.ValueChanged += (_, _) => UpdateQuality();
        FormatBox.SelectionChanged += (_, _) => UpdateQuality();
        // The captions built in code follow the language picked in this window, not the one it opened with.
        LanguageBox.SelectionChanged += (_, _) => _language = LanguageBox.SelectedIndex == 1 ? "en" : "ru";
        UpdateQuality();
        Loaded += (_, _) => ApplyLanguage(settings.Language);
    }

    // The swatches show the accents themselves, so their colours are read from the accent
    // dictionaries rather than written down a second time here.
    private void BuildAccentRow(string? accentId)
    {
        var selected = ThemeService.Normalize(accentId);
        foreach (var accent in ThemeService.Accents)
        {
            var dot = new RadioButton
            {
                Style = (Style)FindResource("AccentDot"), Tag = accent, GroupName = "Accent",
                Background = new SolidColorBrush((Color)ThemeService.Load(accent)["AccentColor"]),
                IsChecked = accent == selected
            };
            AccentRow.Children.Add(dot);
        }
        RefreshAccentNames();
    }

    // A swatch has no caption of its own, so the screen reader gets one built in code; it is rebuilt
    // with the window, because the name of the colour is translated as well.
    private void RefreshAccentNames()
    {
        foreach (var dot in AccentRow.Children.OfType<RadioButton>())
            if (dot.Tag is string accent)
                System.Windows.Automation.AutomationProperties.SetName(dot,
                    string.Format(UiLanguage.Text("Акцент: {0}", _language), UiLanguage.Text(accent, _language)));
    }

    internal string SelectedAccent =>
        AccentRow.Children.OfType<RadioButton>().FirstOrDefault(dot => dot.IsChecked == true)?.Tag as string ?? ThemeService.DefaultAccent;

    // The quality caption is built in code, so it has to be rebuilt every time the window is translated.
    internal void ApplyLanguage(string language)
    {
        _language = language;
        UiLanguage.Apply(this, language);
        CaptureField.ApplyLanguage(language);
        FullscreenField.ApplyLanguage(language);
        RefreshAccentNames();
        UpdateQuality();
    }

    private void UpdateQuality()
    {
        QualityLabel.Visibility = QualitySlider.Visibility = FormatBox.SelectedIndex == 1 ? Visibility.Visible : Visibility.Collapsed;
        QualityLabel.Text = string.Format(UiLanguage.Text("Качество JPEG: {0} % (меньше, легче файл)", _language), (int)QualitySlider.Value);
    }

    private void OnClose(object sender, RoutedEventArgs e) => Close();

    // The field records the key itself; the window only clears the error it may still show and
    // moves the focus off the field, so tabbing back into it is what starts the next recording.
    private void OnHotkeyChanged(object? sender, EventArgs e)
    {
        ErrorText.Visibility = Visibility.Collapsed;
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
                throw new InvalidOperationException(UiLanguage.Text("Укажите папку сохранения.", _language));
            var directory = Path.GetFullPath(DirectoryBox.Text);
            Result = _original with
            {
                CaptureId = CaptureField.HotkeyId, FullscreenSaveId = FullscreenField.HotkeyId,
                CaptureEnabled = CaptureEnabledBox.IsChecked == true,
                FullscreenSaveEnabled = FullscreenEnabledBox.IsChecked == true,
                ShowNotifications = NotificationsBox.IsChecked == true,
                RememberRegion = RememberBox.IsChecked == true, CaptureCursor = CursorBox.IsChecked == true,
                AutoSaveCaptures = AutoSaveBox.IsChecked == true,
                PlaySounds = SoundsBox.IsChecked == true,
                ClearStackAfterPaste = ClearStackBox.IsChecked == true,
                SaveFormat = FormatBox.SelectedIndex == 1 ? "jpeg" : "png",
                JpegQuality = (int)QualitySlider.Value, SaveDirectory = directory, AccentId = SelectedAccent,
                Language = LanguageBox.SelectedIndex == 1 ? "en" : "ru"
            };
            var error = TryApply?.Invoke(Result);
            if (error is not null) throw new InvalidOperationException(error);
            DialogResult = true;
        }
        catch (Exception ex) { ErrorText.Text = UiLanguage.Text(ex.Message, _language); ErrorText.Visibility = Visibility.Visible; Result = null; }
    }
}
