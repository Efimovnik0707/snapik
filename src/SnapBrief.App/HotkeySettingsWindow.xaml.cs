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
    /// <summary>Shift + Print Screen, what "save the whole screen" carries until it is changed.</summary>
    public const string DefaultFullscreenSaveId = "custom:4:44";
    public string FullscreenSaveId { get; init; } = DefaultFullscreenSaveId;
    public bool ShowNotifications { get; init; } = true;
    public bool RememberRegion { get; init; }
    public bool CaptureCursor { get; init; }
    public bool AutoSaveCaptures { get; init; }
    public bool PlaySounds { get; init; } = true;
    /// <summary>How loud the interface sounds are, 0..100; each sound keeps its own gain on top.</summary>
    public int SoundVolume { get; init; } = SettingsMigration.DefaultSoundVolume;
    /// <summary>The schema version of this file; 0 is a file written before versions existed.</summary>
    public int SettingsVersion { get; init; }
    public bool StackTopmost { get; init; } = true;
    /// <summary>
    /// The width of the strip window in pixels; the visible card is 20 px narrower. Read back
    /// clamped to the minimum and to the working area of the monitor the strip opens on, less the
    /// gap it keeps at the edge; there is no number above that.
    /// </summary>
    public double StackWidth { get; init; } = Controls.StripResizeGeometry.DefaultWidth;
    /// <summary>
    /// The height of the capture list inside the strip, in pixels, not the height of the window:
    /// the window is on SizeToContent and derives its height from this one. Read back clamped to
    /// the minimum and to the working area of the monitor the strip opens on, less the chrome of
    /// the window, so that all of it fits on that screen.
    /// </summary>
    public double StackHeight { get; init; } = Controls.StripResizeGeometry.DefaultListHeight;
    public bool ClearStackAfterPaste { get; init; }
    /// <summary>
    /// Whether clearing the strip and leaving the application ask before the captures of the session
    /// are deleted. Written only by the "Do not ask again" box of that dialog: the settings window
    /// does not show it. A file written before this key gets the question, as every older file does.
    /// </summary>
    public bool ConfirmSessionDiscard { get; init; } = true;
    public string AnnotationColor { get; init; } = "#FF3B30";
    /// <summary>Which set of twelve colours the editor offers: standard, pastel or neon.</summary>
    public string AnnotationPalette { get; init; } = "standard";
    /// <summary>Which half of the pencil capsule is armed: pen or highlight.</summary>
    public string AnnotationPencil { get; init; } = "pen";
    public double AnnotationThickness { get; init; } = 4;
    /// <summary>The width of the highlighter stroke, in image pixels; it has a scale of its own.</summary>
    public double AnnotationHighlightThickness { get; init; } = 16;
    /// <summary>The size a caption is typed in, in image pixels; read back clamped to 8..96.</summary>
    public double AnnotationFontSize { get; init; } = 20;
    /// <summary>The frame the editor draws by default: rectangle, rounded or ellipse.</summary>
    public string AnnotationShape { get; init; } = "rectangle";
    /// <summary>How that frame is filled by default: none, solid, translucent or blur.</summary>
    public string AnnotationFill { get; init; } = "none";
    /// <summary>The colour inside that frame; empty means "the colour of the outline".</summary>
    public string AnnotationFillColor { get; init; } = string.Empty;
    /// <summary>Whether that frame carries an outline at all; a solid fill without one conceals.</summary>
    public bool AnnotationOutline { get; init; } = true;
    public string SaveFormat { get; init; } = "png";
    public int JpegQuality { get; init; } = 92;
    public string SaveDirectory { get; init; } = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyPictures), "SnapBrief");
    /// <summary>Where "Save package…" wrote the last time; empty means "wherever single captures go".</summary>
    public string PackageSaveDirectory { get; init; } = string.Empty;
    public bool PackageCreateSubfolder { get; init; } = true;
    public string Language { get; init; } = "ru";
    /// <summary>The version of the first run wizard this file has already seen; 0 means "never".</summary>
    public int OnboardingVersion { get; init; }
    public string Theme { get; init; } = "dark";
    public string AccentId { get; init; } = "blue";
    /// <summary>
    /// The colours the "own" annotation palette holds, newest first; empty until one is picked. Read
    /// back with anything that is not a "#RRGGBB" triple dropped and the row cut to twelve, so a
    /// hand-edited file cannot hand the editor a palette it cannot paint.
    ///
    /// The only member of this record that is an array, and an array compares by reference: two
    /// settings carrying the same colours in two arrays are not equal to each other. An empty row is
    /// always the one instance below, so the common case compares as it always did; anything that
    /// has to compare filled rows compares the colours themselves.
    /// </summary>
    public string[] CustomPaletteColors { get; init; } = NoPaletteColors;
    /// <summary>How many colours the "own" palette keeps.</summary>
    public const int MaxCustomPaletteColors = 12;
    private static readonly string[] NoPaletteColors = [];
    public HotkeyGesture FullscreenSaveGesture => Find(FullscreenSaveId, DefaultFullscreenSaveId).Gesture;
    // A method rather than a property: everything the record exposes as a property is written into
    // settings.json, and this one is a fallback, not a preference of its own.
    public string PackageDirectory() => string.IsNullOrWhiteSpace(PackageSaveDirectory) ? SaveDirectory : PackageSaveDirectory;

    /// <summary>The version every file written by this build carries; see <see cref="Migrate"/>.</summary>
    public const int CurrentSettingsVersion = SettingsMigration.CurrentVersion;

    // The defaults are the source of every settings object the application builds, so they carry the
    // current version: a file this build wrote is never migrated again.
    public static HotkeySettings Default { get; } = new("ctrl-alt-s", "ctrl-alt-v") { SettingsVersion = CurrentSettingsVersion };

    /// <summary>
    /// Brings a file written by an older build up to the current version. Today it is one rule: the
    /// volume that used to be the default becomes the new one, and anything the user picked is left
    /// alone. Applied while loading, and written back once, so it cannot run on every start.
    /// </summary>
    internal static HotkeySettings Migrate(HotkeySettings stored) =>
        SettingsMigration.NeedsMigration(stored.SettingsVersion)
            ? stored with
            {
                SoundVolume = SettingsMigration.SoundVolume(stored.SettingsVersion, stored.SoundVolume),
                SettingsVersion = CurrentSettingsVersion
            }
            : stored;
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
    public HotkeyGesture PasteGesture => Find(PasteId, Default.PasteId).Gesture;

    public static HotkeySettings Load(string path) => TryLoad(path, out var settings) ? settings : Default;

    // A missing file means "nothing saved yet" and may be overwritten with defaults; a file that
    // exists but does not parse must be left alone, otherwise one bad read wipes every preference.
    // This is a read and nothing else: SessionWorkspace.Preferences reads on every capture, and a
    // read that writes would rewrite settings.json with the keys of this build alone.
    public static bool TryLoad(string path, out HotkeySettings settings) => TryRead(path, out settings, out _);

    private static bool TryRead(string path, out HotkeySettings settings, out bool migrated)
    {
        settings = Default;
        migrated = false;
        try
        {
            if (!File.Exists(path)) return true;
            var content = File.ReadAllText(path);
            // A file truncated to nothing (or to blanks) carries no preferences: it is "nothing saved yet" too.
            if (string.IsNullOrWhiteSpace(content)) return true;
            if (JsonSerializer.Deserialize<HotkeySettings>(content) is not { } stored) return false;
            // JSON without the hotkey ids builds a record with empty ones, and every Find over them would fail.
            if (string.IsNullOrEmpty(stored.CaptureId) || string.IsNullOrEmpty(stored.PasteId)) return false;
            // An id that must not be registered is replaced by the default of its own shortcut here,
            // not only where the shortcut is read: otherwise the file goes on holding "custom:0:37"
            // for good while the window shows "Ctrl + Alt + S", and the Mac port, with rules of its
            // own, reads the same file differently. A valid id resolves to itself, so a healthy file
            // comes out of this unchanged and is not written back.
            settings = Migrate(stored) with
            {
                CaptureId = Find(stored.CaptureId).Id,
                PasteId = Find(stored.PasteId, Default.PasteId).Id,
                FullscreenSaveId = Find(stored.FullscreenSaveId, DefaultFullscreenSaveId).Id,
                CustomPaletteColors = KeepPaletteColors(stored.CustomPaletteColors)
            };
            migrated = settings != stored;
            return true;
        }
        catch { return false; }
    }

    /// <summary>
    /// Reads the file and writes back what the migration changed, so an older file is brought up to
    /// date once instead of on every read. The start of the application is the only caller: it is
    /// the one moment where writing to the settings file is a deliberate step.
    /// </summary>
    internal static HotkeySettings LoadAndMigrate(string path)
    {
        if (!TryRead(path, out var settings, out var migrated)) return Default;
        if (migrated)
        {
            try { settings.Save(path); }
            catch { /* A file that cannot be written is still a file that can be read from. */ }
        }
        return settings;
    }

    // Written through a neighbouring temporary file: a write interrupted halfway must not leave
    // a truncated file where every preference lived, because such a file no longer loads. The name
    // of that file carries the process id, so a second SnapBrief (or a smoke run against the same
    // directory) writes its own; a write that failed takes its temporary file with it.
    public void Save(string path)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        RemoveAbandonedTemporaries(path);
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

    // A write that died with its process (a crash, the machine going down) leaves its temporary file
    // behind for good, and nothing else ever touches it. The name carries the process id, so the
    // ones whose process is gone can be dropped before a new write adds another; the unsuffixed name
    // an older version wrote goes the same way.
    private static void RemoveAbandonedTemporaries(string path)
    {
        try
        {
            var directory = Path.GetDirectoryName(path)!;
            var name = Path.GetFileName(path);
            foreach (var candidate in Directory.EnumerateFiles(directory, $"{name}.*"))
            {
                // The pattern also matches through the short 8.3 names Windows keeps, and the file
                // itself: only a real ".<something>.tmp" tail on top of the full name is a leftover.
                var fileName = Path.GetFileName(candidate);
                if (fileName.Length <= name.Length || !fileName.StartsWith(name, StringComparison.OrdinalIgnoreCase)) continue;
                var suffix = fileName[name.Length..];
                if (suffix == ".tmp") { Delete(candidate); continue; }
                if (!suffix.StartsWith('.') || !suffix.EndsWith(".tmp", StringComparison.Ordinal)) continue;
                if (!int.TryParse(suffix[1..^".tmp".Length], out var processId)) continue;
                if (processId != Environment.ProcessId && IsRunning(processId)) continue;
                Delete(candidate);
            }
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }

        static bool IsRunning(int processId)
        {
            try { using var process = System.Diagnostics.Process.GetProcessById(processId); return !process.HasExited; }
            catch (ArgumentException) { return false; }
            catch (InvalidOperationException) { return false; }
            // A process we are not allowed to look at is a process that exists.
            catch { return true; }
        }

        static void Delete(string file)
        {
            try { File.Delete(file); } catch (IOException) { } catch (UnauthorizedAccessException) { }
        }
    }

    // A file that holds nothing wrong comes back as the very array it was read with, so a healthy
    // file is not counted as migrated and is not written back.
    private static string[] KeepPaletteColors(string[]? colours)
    {
        if (colours is null || colours.Length == 0) return NoPaletteColors;
        var kept = colours.Where(IsHexColour).Take(MaxCustomPaletteColors).ToArray();
        if (kept.Length == 0) return NoPaletteColors;
        return kept.Length == colours.Length ? colours : kept;
    }

    private static bool IsHexColour(string? value)
    {
        if (value is not { Length: 7 } || value[0] != '#') return false;
        for (var i = 1; i < value.Length; i++)
            if (!Uri.IsHexDigit(value[i])) return false;
        return true;
    }

    /// <summary>
    /// The choice a stored id stands for. An id that must not be registered falls back to the
    /// default of the shortcut it was read for, which is why the fallback is an argument: the
    /// capture, the fullscreen save and the paste each have a different one, and answering all
    /// three with the capture shortcut would make two of them collide with it.
    /// </summary>
    public static HotkeyChoice Find(string id) => Find(id, Default.CaptureId);

    public static HotkeyChoice Find(string id, string fallbackId) =>
        Resolve(id) ?? Resolve(fallbackId) ?? Choices[0];

    private static HotkeyChoice? Resolve(string id)
    {
        var preset = Choices.FirstOrDefault(c => c.Id == id);
        if (preset is not null) return preset;
        // A stored "custom:0:<key>" is nonsense for every key but the two that stand alone, and a
        // stored id that ends with a modifier is nonsense outright; both are answered with the
        // default. Builds before this one let the field record them, and a settings file holding one
        // would otherwise go on taking those keys from the whole machine at every start. Nothing is
        // written back here, reading never writes; the file itself is put right in TryRead.
        if (HotkeyRules.TryParseCustom(id, out var modifiers, out var key))
        {
            var flags = (HotkeyModifiers)modifiers;
            var label = string.Empty;
            if (flags.HasFlag(HotkeyModifiers.Control)) label += "Ctrl + ";
            if (flags.HasFlag(HotkeyModifiers.Alt)) label += "Alt + ";
            if (flags.HasFlag(HotkeyModifiers.Shift)) label += "Shift + ";
            if (flags.HasFlag(HotkeyModifiers.Windows)) label += "Win + ";
            label += key == 0x13 ? "Pause / Break" : key == 0x2C ? "Print Screen" : KeyInterop.KeyFromVirtualKey(key).ToString();
            return new HotkeyChoice(id, label, new HotkeyGesture(flags | HotkeyModifiers.NoRepeat, key));
        }
        return null;
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
        VolumeSlider.Value = Math.Clamp(settings.SoundVolume, 0, 100);
        SoundsBox.Checked += (_, _) => UpdateVolume();
        SoundsBox.Unchecked += (_, _) => UpdateVolume();
        UpdateVolume();
        ClearStackBox.IsChecked = settings.ClearStackAfterPaste;
        FormatBox.SelectedIndex = settings.SaveFormat == "jpeg" ? 1 : 0;
        QualitySlider.Value = Math.Clamp(settings.JpegQuality, 1, 100);
        DirectoryBox.Text = settings.SaveDirectory;
        LanguageBox.SelectedIndex = settings.Language == "en" ? 1 : 0;
        SelectedTheme = ThemeService.NormalizeTheme(settings.Theme);
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
                Background = new SolidColorBrush((Color)ThemeService.LoadAccent(accent)["AccentColor"]),
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

    /// <summary>
    /// The theme this window will save. It opens on the one the file carries, normalised, so a value
    /// nothing answers to is healed by a save instead of being kept; the appearance tab sets it.
    /// </summary>
    internal string SelectedTheme { get; set; } = ThemeService.DefaultTheme;

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

    // The volume belongs to the sounds: with them off there is nothing to make quieter.
    private void UpdateVolume() => VolumeRow.Visibility = SoundsBox.IsChecked == true ? Visibility.Visible : Visibility.Collapsed;

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
                PlaySounds = SoundsBox.IsChecked == true, SoundVolume = (int)VolumeSlider.Value,
                ClearStackAfterPaste = ClearStackBox.IsChecked == true,
                SaveFormat = FormatBox.SelectedIndex == 1 ? "jpeg" : "png",
                JpegQuality = (int)QualitySlider.Value, SaveDirectory = directory,
                Theme = SelectedTheme, AccentId = SelectedAccent,
                Language = LanguageBox.SelectedIndex == 1 ? "en" : "ru"
            };
            var error = TryApply?.Invoke(Result);
            if (error is not null) throw new InvalidOperationException(error);
            DialogResult = true;
        }
        catch (Exception ex) { ErrorText.Text = UiLanguage.Text(ex.Message, _language); ErrorText.Visibility = Visibility.Visible; Result = null; }
    }
}
