using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;

namespace SnapBrief.App;

/// <summary>
/// The wizard of the first run: language, the capture shortcut, startup and the taskbar, and an
/// animated hint about the whole scenario. Four steps live in one grid and are shown by index.
/// It is a window of its own rather than a page of the settings dialog: the strip hides itself
/// before this runs, and a window owned by a hidden window would end up behind everything.
/// </summary>
public partial class OnboardingWindow : Window
{
    /// <summary>Bumping this shows the wizard again to everyone who has already seen the older one.</summary>
    internal const int CurrentVersion = 1;
    private const int StepCount = 4;
    private readonly HotkeySettings _settings;
    private readonly Storyboard _hint;
    private string _appliedCaptureId;
    private string _language;
    private bool _hintRunning;
    private int _step;

    /// <summary>
    /// Applies what the wizard has collected (the shortcut is registered here, so a conflict is
    /// reported before the user leaves the step) and returns the error to show, or null.
    /// </summary>
    public Func<HotkeySettings, string?>? TryApply { get; init; }

    public OnboardingWindow(HotkeySettings settings)
    {
        _settings = settings;
        _appliedCaptureId = settings.CaptureId;
        _language = SuggestedLanguage(settings);
        InitializeComponent();
        _hint = (Storyboard)FindResource("HintLoop");
        CaptureField.HotkeyId = settings.CaptureId;
        CaptureField.HotkeyChanged += (_, _) => { ErrorText.Visibility = Visibility.Collapsed; HintKeyText.Text = HotkeySettings.Find(CaptureField.HotkeyId).Label; };
        HintKeyText.Text = HotkeySettings.Find(settings.CaptureId).Label;
        RussianCard.IsChecked = _language == "ru";
        EnglishCard.IsChecked = _language == "en";
        RussianCard.Checked += (_, _) => SelectLanguage("ru");
        EnglishCard.Checked += (_, _) => SelectLanguage("en");
        LoadStartupState();
        ShowStep(0);
        ApplyLanguage(_language);
        // Shown while the strip is still hidden: without this the wizard can open behind the window
        // the user was working in.
        Loaded += (_, _) => Activate();
    }

    /// <summary>
    /// The wizard opens once per version: a machine without a settings file has never seen it, and a
    /// newer version shows it again. A demo or a smoke run never shows it.
    /// </summary>
    internal static bool ShouldShowOnboarding(bool settingsFileExists, HotkeySettings settings, bool demo) =>
        !demo && (!settingsFileExists || settings.OnboardingVersion < CurrentVersion);

    /// <summary>The languages of the neighbouring alphabet suggest Russian, everything else English.</summary>
    internal static string LanguageForCulture(string twoLetterIsoLanguageName) =>
        twoLetterIsoLanguageName is "ru" or "uk" or "be" ? "ru" : "en";

    // A repeat run from the tray opens on what the user has chosen before; the first run guesses.
    private static string SuggestedLanguage(HotkeySettings settings) =>
        settings.OnboardingVersion >= CurrentVersion
            ? settings.Language == "en" ? "en" : "ru"
            : LanguageForCulture(CultureInfo.CurrentUICulture.TwoLetterISOLanguageName);

    internal int Step => _step;
    internal string SelectedLanguage => _language;

    // The step caption is built in code, so it is rebuilt every time the window is translated.
    internal void ApplyLanguage(string language)
    {
        _language = language;
        UiLanguage.Apply(this, language);
        CaptureField.ApplyLanguage(language);
        RefreshStepCaption();
    }

    internal void GoToStep(int index) => ShowStep(index);

    private void SelectLanguage(string language)
    {
        if (_language == language) return;
        ApplyLanguage(language);
    }

    private void ShowStep(int index)
    {
        _step = Math.Clamp(index, 0, StepCount - 1);
        ErrorText.Visibility = Visibility.Collapsed;
        var panels = new[] { Step1, Step2, Step3, Step4 };
        for (var i = 0; i < panels.Length; i++) panels[i].Visibility = i == _step ? Visibility.Visible : Visibility.Collapsed;
        var last = _step == StepCount - 1;
        BackButton.Visibility = _step == 0 ? Visibility.Collapsed : Visibility.Visible;
        NextButton.Visibility = last ? Visibility.Collapsed : Visibility.Visible;
        StartButton.Visibility = last ? Visibility.Visible : Visibility.Collapsed;
        NextButton.IsDefault = !last;
        StartButton.IsDefault = last;
        RefreshStepCaption();
        // The loop only runs while its step is on screen.
        if (last && !_hintRunning) { _hint.Begin(this, true); _hintRunning = true; }
        else if (!last && _hintRunning) { _hint.Stop(this); _hintRunning = false; }
    }

    private void RefreshStepCaption() =>
        StepText.Text = string.Format(UiLanguage.Text("Шаг {0} из {1}", _language), _step + 1, StepCount);

    private void LoadStartupState()
    {
        try { StartupBox.IsChecked = WindowsStartupService.IsEnabled(); }
        catch { StartupBox.IsEnabled = false; }
    }

    // Only the three fields the wizard owns are new; everything else travels from the file it was
    // opened with, and the strip merges the candidate into the file as it is at that moment.
    private HotkeySettings Candidate(string captureId) =>
        _settings with { CaptureId = captureId, Language = _language, OnboardingVersion = CurrentVersion };

    // The shortcut is applied when the user leaves its step and again at the finish: the wizard has
    // no "cancel", so what is on screen is what the settings file gets.
    private bool Apply(string captureId)
    {
        var error = TryApply?.Invoke(Candidate(captureId));
        if (error is not null)
        {
            ErrorText.Text = UiLanguage.Text(error, _language);
            ErrorText.Visibility = Visibility.Visible;
            return false;
        }
        _appliedCaptureId = captureId;
        return true;
    }

    private bool ApplyStartup()
    {
        if (!StartupBox.IsEnabled) return true;
        try { WindowsStartupService.SetEnabled(StartupBox.IsChecked == true); return true; }
        catch (Exception ex)
        {
            ErrorText.Text = $"{UiLanguage.Text("Не удалось изменить автозапуск", _language)}: {ex.Message}";
            ErrorText.Visibility = Visibility.Visible;
            return false;
        }
    }

    private void OnBack(object sender, RoutedEventArgs e) => ShowStep(_step - 1);

    private void OnNext(object sender, RoutedEventArgs e)
    {
        if (_step == 1 && !Apply(CaptureField.HotkeyId)) return;
        ShowStep(_step + 1);
    }

    private void OnStart(object sender, RoutedEventArgs e)
    {
        if (!Apply(CaptureField.HotkeyId) || !ApplyStartup()) return;
        Close();
    }

    // The cross is "skip": the wizard counts as passed, so it does not come back on the next start.
    // The shortcut written is the last one that was actually registered, never a conflicting one the
    // user typed and left behind.
    private void OnSkip(object sender, RoutedEventArgs e)
    {
        Apply(_appliedCaptureId);
        Close();
    }

    private void OnHeaderDrag(object sender, MouseButtonEventArgs e) { if (e.LeftButton == MouseButtonState.Pressed) DragMove(); }

    // Windows blocks pinning to the taskbar from an application, so the step explains the manual
    // path and only opens the folder with the shortcut the user has to right-click.
    private void OnShowShortcut(object sender, RoutedEventArgs e)
    {
        try
        {
            Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{ShortcutPath()}\"") { UseShellExecute = true });
        }
        catch (Exception ex)
        {
            ErrorText.Text = $"{UiLanguage.Text("Не удалось открыть папку с ярлыком", _language)}: {ex.Message}";
            ErrorText.Visibility = Visibility.Visible;
        }
    }

    internal static string ShortcutPath()
    {
        var desktop = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), "SnapBrief.lnk");
        if (File.Exists(desktop)) return desktop;
        var startMenu = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), "SnapBrief", "SnapBrief.lnk");
        return File.Exists(startMenu) ? startMenu : Environment.ProcessPath ?? desktop;
    }

    // Smoke probe: the wizard is built, laid out, translated both ways and walked through every
    // step, so a broken template or a string without an English pair fails the run.
    internal static OnboardingWindow RunOnboardingProbe(HotkeySettings settings)
    {
        var window = new OnboardingWindow(settings);
        window.Measure(new Size(620, 600));
        window.Arrange(new Rect(0, 0, 620, 600));
        for (var step = 0; step < StepCount; step++)
        {
            window.GoToStep(step);
            window.UpdateLayout();
        }
        window.ApplyLanguage("en");
        var cyrillic = new System.Text.RegularExpressions.Regex("[А-Яа-яЁё]");
        foreach (var text in WizardStrings(window))
            if (cyrillic.IsMatch(text))
                throw new InvalidOperationException($"The English onboarding wizard still shows Russian text: \"{text}\".");
        window.ApplyLanguage("ru");
        window.GoToStep(0);
        return window;
    }

    // The two language cards name the languages themselves and stay as they are in both languages,
    // so they are the one part of the window the Cyrillic sweep skips.
    private static IEnumerable<string> WizardStrings(OnboardingWindow window)
    {
        var visited = new HashSet<DependencyObject>();
        var found = new List<string>();
        void Walk(DependencyObject item)
        {
            if (ReferenceEquals(item, window.LanguageRow) || !visited.Add(item)) return;
            if (item is FrameworkElement { ToolTip: string tip }) found.Add(tip);
            if (item is ContentControl { Content: string caption }) found.Add(caption);
            if (item is TextBlock text) found.Add(text.Text);
            foreach (var child in LogicalTreeHelper.GetChildren(item)) if (child is DependencyObject dependency) Walk(dependency);
            if (item is Visual)
                for (var i = 0; i < VisualTreeHelper.GetChildrenCount(item); i++) Walk(VisualTreeHelper.GetChild(item, i));
        }
        Walk(window);
        return found;
    }
}
