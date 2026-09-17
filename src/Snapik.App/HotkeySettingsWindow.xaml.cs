using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Windows;
using System.Windows.Input;
using System.Windows.Threading;
using Snapik.Windows;

namespace Snapik.App;

public partial class HotkeySettingsWindow : Window
{
    private readonly HotkeySettings _original;
    private string _language;
    public Func<HotkeySettings, string?>? TryApply { get; init; }
    public HotkeySettings? Result { get; private set; }

    /// <summary>
    /// The link of the settings that asks for the wizard again. The window only says so; opening it
    /// belongs to whoever opened the settings, because the wizard has to outlive them.
    /// </summary>
    internal bool OnboardingRequested { get; private set; }

    public HotkeySettingsWindow(HotkeySettings settings, bool showPasteSettings = false)
    {
        _original = settings;
        _language = settings.Language;
        InitializeComponent();
        CaptureField.HotkeyId = settings.CaptureId;
        FullscreenField.HotkeyId = settings.FullscreenSaveId;
        // The two fields of this window are each other's neighbours: a combination one of them
        // holds is refused in the other while it is being pressed.
        CaptureField.ConflictsWith = [FullscreenField];
        FullscreenField.ConflictsWith = [CaptureField];
        CaptureEnabledBox.IsChecked = settings.CaptureEnabled;
        FullscreenEnabledBox.IsChecked = settings.FullscreenSaveEnabled;
        // A shortcut switched off has no combination to show, and the chip beside it offers one.
        CaptureEnabledBox.Checked += (_, _) => UpdateShortcutState();
        CaptureEnabledBox.Unchecked += (_, _) => UpdateShortcutState();
        FullscreenEnabledBox.Checked += (_, _) => UpdateShortcutState();
        FullscreenEnabledBox.Unchecked += (_, _) => UpdateShortcutState();
        UpdateShortcutState();
        LoadStartupState();
        NotificationsBox.IsChecked = settings.ShowNotifications;
        AutoSaveBox.IsChecked = settings.AutoSaveCaptures;
        SoundsBox.IsChecked = settings.PlaySounds;
        VolumeSlider.Value = Math.Clamp(settings.SoundVolume, 0, 100);
        // Subscribed after the value is put in, so that opening the window is not itself a change and
        // does not play anything. A slider is moved by dragging, by a click on its track and by the
        // arrow keys, and only the first of the three ends with a drag event: the moment the user let
        // go is therefore read as a pause, one timer restarted on every change.
        VolumeSlider.ValueChanged += (_, _) => { UpdateVolumeCaption(); _volumePreview.Stop(); _volumePreview.Start(); };
        _volumePreview.Tick += (_, _) => { _volumePreview.Stop(); PreviewVolume(); };
        SoundsBox.Checked += (_, _) => UpdateVolume();
        SoundsBox.Unchecked += (_, _) => UpdateVolume();
        UpdateVolume();
        UpdateVolumeCaption();
        ClearStackBox.IsChecked = settings.ClearStackAfterPaste;
        FormatBox.SelectedIndex = settings.SaveFormat == "jpeg" ? 1 : 0;
        QualitySlider.Value = Math.Clamp(settings.JpegQuality, 1, 100);
        DirectoryBox.Text = settings.SaveDirectory;
        RussianSegment.IsChecked = settings.Language != "en";
        EnglishSegment.IsChecked = settings.Language == "en";
        AppearanceTab.SelectedTheme = ThemeService.NormalizeTheme(settings.Theme);
        AppearanceTab.SelectedAccent = ThemeService.Normalize(settings.AccentId);
        // The row of annotation palettes is the same preference the popover of the editor holds, so
        // it is read and written as the editor reads and writes it.
        AppearanceTab.SelectedPalette = OverlayEditorWindow.ParseAnnotationPalette(settings.AnnotationPalette).Id;
        QualitySlider.ValueChanged += (_, _) => UpdateQuality();
        FormatBox.SelectionChanged += (_, _) => UpdateQuality();
        // The captions built in code follow the language picked in this window, not the one it opened with.
        RussianSegment.Checked += (_, _) => _language = "ru";
        EnglishSegment.Checked += (_, _) => _language = "en";
        UpdateQuality();
        Loaded += (_, _) => ApplyLanguage(settings.Language);
        // The appearance tab repaints the application while it is being looked at and saves nothing;
        // walking away from the window has to put back the pair it was opened with.
        Closed += (_, _) =>
        {
            // A tick owed to a value nobody saved must not arrive after the window is gone.
            _volumePreview.Stop();
            if (Result is null) ThemeService.Apply(_original.Theme, _original.AccentId);
        };
    }

    // The startup entry is a registry value, not a preference of the settings file: it is read when
    // the window opens and written when it saves. A profile that keeps the key closed to us (a
    // policy, a locked account) leaves the box disabled with a line saying so, the way the wizard
    // does, instead of offering a switch that does nothing.
    private void LoadStartupState()
    {
        try { StartupBox.IsChecked = WindowsStartupService.IsEnabled(); }
        catch (Exception)
        {
            StartupBox.IsEnabled = false;
            StartupUnavailableText.Visibility = Visibility.Visible;
        }
    }

    private void ApplyStartup()
    {
        if (!StartupBox.IsEnabled) return;
        try { WindowsStartupService.SetEnabled(StartupBox.IsChecked == true); }
        catch (Exception ex)
        {
            throw new InvalidOperationException($"{UiLanguage.Text("Не удалось изменить автозапуск", _language)}: {ex.Message}");
        }
    }

    /// <summary>
    /// The theme this window will save. It opens on the one the file carries, normalised, so a value
    /// nothing answers to is healed by a save instead of being kept; the appearance tab holds it.
    /// </summary>
    internal string SelectedTheme => AppearanceTab.SelectedTheme;

    internal string SelectedAccent => AppearanceTab.SelectedAccent;

    // The quality caption is built in code, so it has to be rebuilt every time the window is translated.
    internal void ApplyLanguage(string language)
    {
        _language = language;
        UiLanguage.Apply(this, language);
        CaptureField.ApplyLanguage(language);
        FullscreenField.ApplyLanguage(language);
        UpdateShortcutState();
        AppearanceTab.ApplyLanguage(language);
        UpdateQuality();
        // The walk of UiLanguage.Apply rewrites the text of every TextBlock that is not bound, so the
        // number beside the slider is put back after it, the way the quality caption is.
        UpdateVolumeCaption();
    }

    /// <summary>
    /// The combinations the chip has offered and Windows refused to register. A shortcut another
    /// application holds fails at the registration and nowhere earlier, so the queue learns about it
    /// only after a save was attempted, and the chip moves on to the next candidate.
    /// </summary>
    private readonly List<string> _refusedByWindows = [];

    /// <summary>The combination the chip put into the field, if the user took one.</summary>
    private string? _suggested;

    /// <summary>
    /// The pause that stands for "the slider was let go": every change restarts it, and when it runs
    /// out the tick is played on the volume the slider holds. Nothing is saved by it.
    /// </summary>
    private readonly DispatcherTimer _volumePreview = new() { Interval = TimeSpan.FromMilliseconds(150) };

    // What the chip offers: the first combination of the queue that neither field holds and nothing
    // has refused. Null means the queue is exhausted and the chip has nothing to say.
    private string? SuggestedShortcut() =>
        HotkeyRules.SuggestFree([CaptureField.HotkeyId, .. _refusedByWindows]);

    // A shortcut that is switched off shows "not assigned", and the one for the whole screen also
    // shows the chip that switches it on.
    private void UpdateShortcutState()
    {
        CaptureField.IsAssigned = CaptureEnabledBox.IsChecked == true;
        FullscreenField.IsAssigned = FullscreenEnabledBox.IsChecked == true;
        var suggestion = FullscreenField.IsAssigned ? null : SuggestedShortcut();
        SuggestChip.Visibility = suggestion is null ? Visibility.Collapsed : Visibility.Visible;
        if (suggestion is null) return;
        var label = HotkeySettings.Find(suggestion, HotkeySettings.DefaultFullscreenSaveId).Label;
        SuggestChip.Tag = suggestion;
        SuggestChip.Content = string.Format(UiLanguage.Text("Предложить: {0}", _language), label);
    }

    // Print Screen is held by the snipping tool on most of Windows 11, and nothing says so until the
    // registration fails. A combination the chip put there and Windows would not take is dropped
    // again: the shortcut goes back to "not assigned" and the chip offers the next candidate.
    private void RefuseSuggestion()
    {
        if (FullscreenEnabledBox.IsChecked != true || _suggested is null ||
            !HotkeyRules.SameGesture(FullscreenField.HotkeyId, _suggested)) return;
        _refusedByWindows.Add(_suggested);
        FullscreenEnabledBox.IsChecked = false;
        UpdateShortcutState();
    }

    private void OnSuggestShortcut(object sender, RoutedEventArgs e)
    {
        if (SuggestChip.Tag is not string suggestion) return;
        _suggested = suggestion;
        FullscreenField.HotkeyId = suggestion;
        FullscreenEnabledBox.IsChecked = true;
        ErrorText.Visibility = Visibility.Collapsed;
        UpdateShortcutState();
    }

    // The volume belongs to the sounds: with them off there is nothing to make quieter, and a tick
    // owed to the slider is dropped instead of arriving after the sounds were switched off.
    private void UpdateVolume()
    {
        var audible = SoundsBox.IsChecked == true;
        VolumeRow.Visibility = audible ? Visibility.Visible : Visibility.Collapsed;
        if (!audible) _volumePreview.Stop();
    }

    // The number the slider is worth, in the shape the quality caption already uses: a space before
    // the sign, and the same text in both languages.
    private void UpdateVolumeCaption() => VolumeValueLabel.Text = $"{(int)VolumeSlider.Value} %";

    // The tick of the volume being chosen: the settings of the window with the sounds on and the
    // value the slider holds, and nothing of it is written to the file. The row is only on screen
    // while the sounds are on, so the preview cannot switch them on behind the user's back.
    private void PreviewVolume() =>
        UiSoundService.Tick(_original with { PlaySounds = true, SoundVolume = (int)VolumeSlider.Value });

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
        // A combination pressed into a field that was switched off is a request for that shortcut:
        // it would otherwise be recorded and go on showing "not assigned".
        if (ReferenceEquals(sender, CaptureField)) CaptureEnabledBox.IsChecked = true;
        if (ReferenceEquals(sender, FullscreenField)) FullscreenEnabledBox.IsChecked = true;
        UpdateShortcutState();
        SaveButton.Focus();
    }
    private void OnBrowseDirectory(object sender, RoutedEventArgs e)
    {
        var dialog = new Microsoft.Win32.OpenFolderDialog { InitialDirectory = Directory.Exists(DirectoryBox.Text) ? DirectoryBox.Text : Environment.GetFolderPath(Environment.SpecialFolder.MyPictures) };
        if (dialog.ShowDialog(this) == true) DirectoryBox.Text = dialog.FolderName;
    }
    private void OnHeaderDrag(object sender, MouseButtonEventArgs e) { if (e.LeftButton == MouseButtonState.Pressed) DragMove(); }

    // The link asks for the wizard and leaves; the strip opens it, because two modal windows one on
    // top of the other are not what the user asked for. The result is "false" and not "true": edits
    // made in the dialog and not saved are dropped, so the wizard reads the file from the disk and
    // shows one state instead of two.
    private void OnRunOnboarding(object sender, MouseButtonEventArgs e)
    {
        OnboardingRequested = true;
        DialogResult = false;
    }

    private void OnSave(object sender, RoutedEventArgs e)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(DirectoryBox.Text))
                throw new InvalidOperationException(UiLanguage.Text("Укажите папку сохранения.", _language));
            // A shortcut recorded before the neighbouring field took it is caught here, by the
            // gesture the two ids parse to, and not by the registration: Windows only refuses the
            // second one while both are switched on, and its message blames another application.
            if (CaptureEnabledBox.IsChecked == true && FullscreenEnabledBox.IsChecked == true &&
                HotkeyRules.SameGesture(CaptureField.HotkeyId, FullscreenField.HotkeyId))
            {
                CaptureField.ShowConflict();
                FullscreenField.ShowConflict();
                throw new InvalidOperationException("Одно сочетание на два действия. Поменяй одно из них.");
            }
            var directory = Path.GetFullPath(DirectoryBox.Text);
            Result = _original with
            {
                CaptureId = CaptureField.HotkeyId, FullscreenSaveId = FullscreenField.HotkeyId,
                CaptureEnabled = CaptureEnabledBox.IsChecked == true,
                FullscreenSaveEnabled = FullscreenEnabledBox.IsChecked == true,
                ShowNotifications = NotificationsBox.IsChecked == true,
                // RememberRegion and CaptureCursor have no row of their own any more: the two
                // preferences travel from the file this window was opened with, untouched.
                AutoSaveCaptures = AutoSaveBox.IsChecked == true,
                PlaySounds = SoundsBox.IsChecked == true, SoundVolume = (int)VolumeSlider.Value,
                ClearStackAfterPaste = ClearStackBox.IsChecked == true,
                SaveFormat = FormatBox.SelectedIndex == 1 ? "jpeg" : "png",
                JpegQuality = (int)QualitySlider.Value, SaveDirectory = directory,
                Theme = SelectedTheme, AccentId = SelectedAccent, AnnotationPalette = AppearanceTab.SelectedPalette,
                Language = EnglishSegment.IsChecked == true ? "en" : "ru"
            };
            ApplyStartup();
            var error = TryApply?.Invoke(Result);
            if (error is not null) { RefuseSuggestion(); throw new InvalidOperationException(error); }
            DialogResult = true;
        }
        catch (Exception ex) { ErrorText.Text = UiLanguage.Text(ex.Message, _language); ErrorText.Visibility = Visibility.Visible; Result = null; }
    }

    /// <summary>
    /// The smoke check of the save block: one combination written into both fields is refused, both
    /// of them go red and nothing is saved. The same keys are given as a preset and as a custom id,
    /// so the check also proves the comparison is by gesture and not by text.
    /// </summary>
    internal static void RunSettingsRulesProbe(HotkeySettings settings)
    {
        // A clean installation: the shortcut of the whole screen is off, the field says so, and the
        // chip offers the first combination of the queue.
        var clean = new HotkeySettingsWindow(HotkeySettings.Default);
        clean.ApplyLanguage("ru");
        if (clean.FullscreenField.IsAssigned || clean.SuggestChip.Visibility != Visibility.Visible ||
            (string?)clean.SuggestChip.Content != "Предложить: Print Screen")
            throw new InvalidOperationException("A shortcut that is off must say so and be offered a free combination.");
        clean.OnSuggestShortcut(clean.SuggestChip, new RoutedEventArgs());
        if (clean.FullscreenEnabledBox.IsChecked != true || clean.FullscreenField.HotkeyId != "print-screen" ||
            clean.SuggestChip.Visibility != Visibility.Collapsed)
            throw new InvalidOperationException("The chip must switch the shortcut on with the combination it offers.");
        // Windows refused to register it: the offer is withdrawn and the queue moves on.
        clean.RefuseSuggestion();
        if (clean.FullscreenEnabledBox.IsChecked != false || clean.SuggestChip.Visibility != Visibility.Visible ||
            (string?)clean.SuggestChip.Content != $"Предложить: {HotkeySettings.Find(HotkeySettings.DefaultFullscreenSaveId).Label}")
            throw new InvalidOperationException("A suggestion Windows refused must give way to the next candidate.");

        var window = new HotkeySettingsWindow(settings);
        window.ApplyLanguage("ru");
        window.CaptureField.HotkeyId = "ctrl-alt-s";
        window.FullscreenField.HotkeyId = "custom:3:83";
        window.CaptureEnabledBox.IsChecked = true;
        window.FullscreenEnabledBox.IsChecked = true;
        window.OnSave(window, new RoutedEventArgs());
        if (window.Result is not null || window.DialogResult is not null)
            throw new InvalidOperationException("One combination for two actions must not be saved.");
        if (!window.CaptureField.ShowsConflict || !window.FullscreenField.ShowsConflict)
            throw new InvalidOperationException("One combination for two actions must turn both fields red.");
        if (window.ErrorText.Visibility != Visibility.Visible ||
            window.ErrorText.Text != "Одно сочетание на два действия. Поменяй одно из них.")
            throw new InvalidOperationException("One combination for two actions must be explained under the tabs.");

        // The link asks for the wizard and saves nothing: the flag the strip reads goes up, and the
        // settings the user was typing stay where they were, unsaved. The window of the probe was
        // never shown as a dialog, so WPF refuses the "false" the link hands back after that; the
        // refusal is the only part of the link a run without a screen cannot see.
        var tour = new HotkeySettingsWindow(settings);
        try { tour.OnRunOnboarding(tour.RunOnboardingLink, new MouseButtonEventArgs(Mouse.PrimaryDevice, 0, MouseButton.Left)); }
        catch (InvalidOperationException) { }
        if (!tour.OnboardingRequested || tour.Result is not null)
            throw new InvalidOperationException("The link to the wizard must ask for it and save nothing.");
    }
}
