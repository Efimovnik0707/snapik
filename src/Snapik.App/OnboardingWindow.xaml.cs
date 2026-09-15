using System;
using System.Collections.Generic;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using Drawing = System.Drawing;
using WinForms = System.Windows.Forms;

namespace Snapik.App;

/// <summary>
/// The wizard of the first run: language, the capture shortcut, startup and the taskbar, and an
/// animated hint about the whole scenario. Four steps live in one grid and are shown by index.
/// It is a window of its own rather than a page of the settings dialog: the strip hides itself
/// before this runs, and a window owned by a hidden window would end up behind everything.
/// </summary>
public partial class OnboardingWindow : Window
{
    /// <summary>Bumping this shows the wizard again to everyone who has already seen the older one.</summary>
    internal const int CurrentVersion = 3;
    private const int StepCount = 5;
    private readonly HotkeySettings _settings;
    // The tray opens the slides alone: no language, no shortcut, no steps, one "Done" button.
    private readonly bool _howToOnly;
    private string _appliedCaptureId;
    // The free combination the chip of step 2 offers, or null while nothing refuses the current one.
    private string? _suggestedCaptureId;
    // The theme, the accent and the language the wizard opened with, to go back to if the user skips
    // the setup. The language is one of the three: the switch of step 1 writes it into the candidate
    // like everything else, and "Skip setup" has to touch nothing at all.
    private readonly string _openedTheme;
    private readonly string _openedAccent;
    private readonly string _openedLanguage;
    private string _language;
    private int _step;
    // Whether "Get started" or "Skip setup" is closing the window, so that every other way of closing
    // it can be answered as a skip.
    private bool _closedByButton;

    /// <summary>
    /// Applies what the wizard has collected (the shortcut is registered here, so a conflict is
    /// reported before the user leaves the step) and returns the error to show, or null.
    /// </summary>
    public Func<HotkeySettings, string?>? TryApply { get; init; }

    /// <summary>
    /// Marks the wizard as passed. It runs when the window is gone, whatever closed it, and it is
    /// deliberately separate from <see cref="TryApply"/>: a shortcut that could not be registered
    /// keeps the user on its step, but must not bring the whole wizard back on every start.
    /// </summary>
    public Action? MarkPassed { get; init; }

    /// <summary>Writes a line into the startup log; the wizard has no log of its own.</summary>
    public Action<string>? Trace { get; init; }

    public OnboardingWindow(HotkeySettings settings, bool howToOnly = false, bool settingsFileExists = true)
    {
        _settings = settings;
        _howToOnly = howToOnly;
        _appliedCaptureId = settings.CaptureId;
        _language = SuggestedLanguage(settingsFileExists, settings, CultureInfo.CurrentUICulture.TwoLetterISOLanguageName);
        _openedLanguage = _language;
        InitializeComponent();
        CaptureField.HotkeyId = settings.CaptureId;
        CaptureField.HotkeyChanged += (_, _) =>
        {
            ErrorText.Visibility = Visibility.Collapsed;
            RefreshCaptureConflict();
        };
        // The look the wizard was opened with: "Skip setup" puts it back, whatever step 4 was playing
        // with, and the candidate carries what is on screen at the end.
        _openedTheme = settings.Theme;
        _openedAccent = settings.AccentId;
        Appearance.SelectedTheme = settings.Theme;
        Appearance.SelectedAccent = settings.AccentId;
        RussianSegment.Checked += (_, _) => SelectLanguage("ru");
        EnglishSegment.Checked += (_, _) => SelectLanguage("en");
        // The slides from the tray hide the startup step, and reading the registry for a step nobody
        // sees puts an error in the log (and the "unavailable" line on that hidden step) for nothing.
        if (!howToOnly) { LoadStartupState(); LoadPinState(); }
        if (howToOnly) StartButton.Content = UiLanguage.Text("Готово", _language);
        ShowStep(howToOnly ? StepCount - 1 : 0);
        ApplyLanguage(_language);
        // Shown while the strip is still hidden: without this the wizard can open behind the window
        // the user was working in. The slides get the focus as soon as the window has one to give:
        // opened from the tray the wizard is nothing but the slides, and the arrow keys have to
        // reach them from the first moment.
        Loaded += (_, _) => { Activate(); if (_step == StepCount - 1) HowTo.Focus(); };
    }

    /// <summary>
    /// The wizard opens on the monitor the user is on, not on the primary one, and never taller than
    /// the working area of that monitor. It is done here rather than in Loaded: the handle the scale
    /// of the monitor is read through exists by now, and the window has not been drawn yet. The one
    /// corner of the window is asked for here too, for the same reason: it needs the handle.
    /// </summary>
    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        var handle = new WindowInteropHelper(this).Handle;
        Trace?.Invoke($"Onboarding corners: rounded={DwmWindowCorners.Round(handle)}");
        try
        {
            // The scale is taken from the monitor the window is going to and not from the one it was
            // created on: with two monitors of different scales the second answer is the wrong one,
            // and the wizard ends up either taller than the working area or clamped to a scrollbar.
            var work = WinForms.Screen.FromPoint(WinForms.Cursor.Position).WorkingArea;
            PlaceOn(handle, work, MonitorMetrics.Scale(work.Left, work.Top), "opened");
        }
        catch (Exception ex) { Trace?.Invoke($"Onboarding placement: {ex}"); }
    }

    // Whether the window has already answered the first WM_DPICHANGED; the second one and everything
    // after it belongs to whoever is dragging the window between monitors.
    private bool _placed;

    /// <summary>
    /// Moving the window to a monitor of another scale makes Windows send WM_DPICHANGED, and WPF
    /// re-lays the window out by the rectangle it proposes, which moves the centre by a few pixels.
    /// That is evened out once, by the scale the window now really has, and never again.
    /// </summary>
    protected override void OnDpiChanged(DpiScale oldDpi, DpiScale newDpi)
    {
        base.OnDpiChanged(oldDpi, newDpi);
        if (_placed) return;
        _placed = true;
        try
        {
            var handle = new WindowInteropHelper(this).Handle;
            PlaceOn(handle, WinForms.Screen.FromHandle(handle).WorkingArea, VisualTreeHelper.GetDpi(this).DpiScaleX, "re-aligned");
        }
        catch (Exception ex) { Trace?.Invoke($"Onboarding placement: {ex}"); }
    }

    // The position is set in physical pixels through SetWindowPos rather than through Left and Top:
    // those two are read in the scale of the monitor the window belongs to at that moment, and that
    // is exactly the monitor this is trying to leave.
    private void PlaceOn(IntPtr handle, Drawing.Rectangle work, double scale, string reason)
    {
        MaxHeight = UsefulHeight(work.Height, scale, MinimumUsefulHeight);
        var height = Math.Min(Height, MaxHeight);
        SetWindowPos(handle, IntPtr.Zero,
            CenteredStart(work.Left, work.Width, Width, scale),
            CenteredStart(work.Top, work.Height, height, scale),
            0, 0, SwpNoSize | SwpNoZOrder | SwpNoActivate);
        Trace?.Invoke($"Onboarding placement: {reason} on monitor={work}, scale={scale}, MaxHeight={MaxHeight}, height={height}");
    }

    /// <summary>
    /// Where the window starts along one axis, in physical pixels: the working area of the monitor it
    /// opens on, less the window itself measured at the scale of that monitor. Arithmetic on its own,
    /// so the half of the placement that can be checked without a second monitor is checked.
    /// </summary>
    internal static int CenteredStart(int workStart, int workLength, double windowLength, double scale) =>
        workStart + (int)Math.Round((workLength - windowLength * (scale > 0 ? scale : 1)) / 2);

    private const int SwpNoSize = 0x0001;
    private const int SwpNoZOrder = 0x0004;
    private const int SwpNoActivate = 0x0010;

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWindowPos(IntPtr hwnd, IntPtr insertAfter, int x, int y, int width, int height, int flags);

    /// <summary>Below this the wizard would be a strip of chrome; the content scrolls instead.</summary>
    private const double MinimumUsefulHeight = 360;

    /// <summary>
    /// How tall the wizard may be on a monitor whose working area is <paramref name="workAreaDevice"/>
    /// physical pixels high at <paramref name="scale"/>: that height in the units the window is
    /// placed in, less a finger of air, and never below <paramref name="minimum"/>. Arithmetic on its
    /// own, so the half of the placement that can be checked without a monitor is checked.
    /// </summary>
    internal static double UsefulHeight(double workAreaDevice, double scale, double minimum) =>
        Math.Max(minimum, workAreaDevice / (scale > 0 ? scale : 1) - 40);

    // The window can go away without any button: the cross, Alt+F4, the taskbar, "Get started".
    // Every one of them counts as "seen", and every one of them has to release the loop of step 4 —
    // stopping it is not enough, the clock it left on this window has to be removed as well.
    protected override void OnClosed(EventArgs e)
    {
        WelcomeScene.Halt();
        HowTo.Stop();
        MarkPassed?.Invoke();
        base.OnClosed(e);
    }

    /// <summary>
    /// The wizard opens once per version: a machine without a settings file has never seen it, and a
    /// newer version shows it again. A demo or a smoke run never shows it.
    /// </summary>
    internal static bool ShouldShowOnboarding(bool settingsFileExists, HotkeySettings settings, bool demo) =>
        !demo && (!settingsFileExists || settings.OnboardingVersion < CurrentVersion);

    /// <summary>A Russian system gives Russian, every other locale gives English: the interface has
    /// two languages, and a Ukrainian or Spanish user is not served by guessing Russian for them.</summary>
    internal static string LanguageForCulture(string twoLetterIsoLanguageName) =>
        twoLetterIsoLanguageName == "ru" ? "ru" : "en";

    /// <summary>
    /// The language the wizard opens in. The locale is a guess, and it is only made where there is
    /// nothing to go on: no settings file, nothing chosen in it. A machine that already has one
    /// keeps what it holds, whatever the locale is and whatever <see cref="CurrentVersion"/> says —
    /// bumping that version brings the wizard back to everyone, and it must not re-language the
    /// application behind the user, least of all in the slides from the tray, where there is no
    /// switch to put it right.
    /// </summary>
    internal static string SuggestedLanguage(bool settingsFileExists, HotkeySettings settings, string cultureLanguage)
    {
        var chosen = settings.Language is "ru" or "en" ? settings.Language : null;
        var seen = settingsFileExists || settings.OnboardingVersion > 0;
        return seen && chosen is not null ? chosen : LanguageForCulture(cultureLanguage);
    }

    internal int Step => _step;
    internal string SelectedLanguage => _language;

    // The step caption is built in code, so it is rebuilt every time the window is translated. The
    // switch in the header follows the language whoever calls this has chosen, including the guess
    // made for the first run.
    internal void ApplyLanguage(string language)
    {
        _language = language;
        RussianSegment.IsChecked = language == "ru";
        EnglishSegment.IsChecked = language == "en";
        UiLanguage.Apply(this, language);
        CaptureField.ApplyLanguage(language);
        WelcomeScene.ApplyLanguage(language);
        Appearance.ApplyLanguage(language);
        HowTo.ApplyLanguage(language);
        RefreshStepCaption();
        RefreshCaptureConflict();
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
        var panels = new[] { Step1, Step2, Step3, Step4, Step5 };
        for (var i = 0; i < panels.Length; i++) panels[i].Visibility = i == _step ? Visibility.Visible : Visibility.Collapsed;
        var last = _step == StepCount - 1;
        // The switch is asked for once and belongs to the first step alone; it is held by its own
        // visibility rather than by the panel around it, so that the slides from the tray hide it too.
        LanguageToggle.Visibility = _step == 0 ? Visibility.Visible : Visibility.Collapsed;
        BackButton.Visibility = _step == 0 ? Visibility.Collapsed : Visibility.Visible;
        NextButton.Visibility = last ? Visibility.Collapsed : Visibility.Visible;
        StartButton.Visibility = last ? Visibility.Visible : Visibility.Collapsed;
        NextButton.IsDefault = !last;
        StartButton.IsDefault = last;
        RefreshStepCaption();
        NextButton.IsEnabled = true;
        RefreshCaptureConflict();
        // The slides only run while their step is on screen, and they take the focus with them, so
        // the arrows reach them however the step was arrived at. The scene of the first step is the
        // same: a loop nobody is looking at keeps repainting a hidden panel.
        if (_step == 0) WelcomeScene.Play();
        else WelcomeScene.Halt();
        if (last) { HowTo.Start(); HowTo.Focus(); }
        else HowTo.Stop();
        if (!_howToOnly) return;
        // Everything the tray does not need: the wizard is only the slides here, and its one button
        // says "Done" instead of "Get started".
        BackButton.Visibility = Visibility.Collapsed;
        NextButton.Visibility = Visibility.Collapsed;
        StepText.Visibility = Visibility.Collapsed;
        SkipLink.Visibility = Visibility.Collapsed;
    }

    /// <summary>
    /// Left and Right step through the slides while the last step is on screen, and say so by
    /// returning true; on the other steps they belong to whatever has the focus. The keys never
    /// move the wizard between its steps: only "Back", "Next" and the last button do that, and an
    /// arrow at the end of the slides does nothing at all. The smoke run calls this directly, a
    /// real key event needs a shown window with a handle behind it.
    /// </summary>
    internal bool HandleNavigationKey(Key key)
    {
        if (_step != StepCount - 1 || key is not (Key.Left or Key.Right)) return false;
        HowTo.Step(key == Key.Left ? -1 : 1);
        return true;
    }

    protected override void OnPreviewKeyDown(KeyEventArgs e)
    {
        if (HandleNavigationKey(e.Key)) e.Handled = true;
        base.OnPreviewKeyDown(e);
    }

    /// <summary>
    /// What the shortcut of the step is refused for, as the Russian key of the message, or null when
    /// nothing refuses it. The rules are the shared ones (W0-8); the wizard only asks them.
    /// </summary>
    private string? CaptureRefusal()
    {
        var id = CaptureField.HotkeyId;
        if (HotkeyRules.TryParseCustom(id, out var modifiers, out var virtualKey) &&
            HotkeyRules.IsSystemReserved((ModifierKeys)modifiers, virtualKey))
            return "Это сочетание занято Windows";
        // The fullscreen shortcut only holds its combination while its own switch is on: off, it keeps
        // the default id in the file and would otherwise refuse the same combination on a clean install.
        return _settings.FullscreenSaveEnabled && HotkeyRules.SameGesture(id, _settings.FullscreenSaveId)
            ? "Уже занято"
            : null;
    }

    // The refusal is shown under the field, "Next" stops until it is gone, and a free combination is
    // offered beside it, so that the user is never left to invent one.
    private void RefreshCaptureConflict()
    {
        var refusal = CaptureRefusal();
        CaptureConflictText.Text = refusal is null ? string.Empty : UiLanguage.Text(refusal, _language);
        CaptureConflictText.Visibility = refusal is null ? Visibility.Collapsed : Visibility.Visible;
        _suggestedCaptureId = refusal is null ? null : HotkeyRules.SuggestFree([_settings.FullscreenSaveId, _settings.PasteId]);
        SuggestChipText.Text = _suggestedCaptureId is null
            ? string.Empty
            : string.Format(UiLanguage.Text("Предложить: {0}", _language), HotkeySettings.Find(_suggestedCaptureId).Label);
        SuggestChip.Visibility = _suggestedCaptureId is null ? Visibility.Collapsed : Visibility.Visible;
        if (_step == 1) NextButton.IsEnabled = refusal is null;
    }

    private void OnSuggestFreeShortcut(object sender, MouseButtonEventArgs e)
    {
        if (_suggestedCaptureId is null) return;
        // The field reports what the user records, never what is written into it, so the refusal is
        // asked about again here.
        CaptureField.HotkeyId = _suggestedCaptureId;
        RefreshCaptureConflict();
    }

    private void RefreshStepCaption() =>
        StepText.Text = string.Format(UiLanguage.Text("Шаг {0} из {1}", _language), _step + 1, StepCount);

    // The registry key of the startup entry can be closed to us (a policy, a locked profile). The
    // step still explains the taskbar, and the checkbox says why it cannot be used instead of
    // going quietly grey.
    private void LoadStartupState()
    {
        try { StartupBox.IsChecked = WindowsStartupService.IsEnabled(); }
        catch (Exception ex)
        {
            StartupBox.IsEnabled = false;
            StartupUnavailableText.Visibility = Visibility.Visible;
            Trace?.Invoke($"Onboarding startup state: {ex}");
        }
    }

    // Only the three fields the wizard owns are new; everything else travels from the file it was
    // opened with, and the strip merges the candidate into the file as it is at that moment.
    private HotkeySettings Candidate(string captureId) =>
        _settings with
        {
            CaptureId = captureId, Language = _language, OnboardingVersion = CurrentVersion,
            Theme = Appearance.SelectedTheme, AccentId = Appearance.SelectedAccent
        };

    // The shortcut is applied when the user leaves its step and again at the finish: the wizard has
    // no "cancel", so what is on screen is what the settings file gets.
    // The candidate carries the language of the wizard, so what comes back is already in it.
    private bool Apply(string captureId)
    {
        var error = TryApply?.Invoke(Candidate(captureId));
        if (error is not null)
        {
            ErrorText.Text = error;
            ErrorText.Visibility = Visibility.Visible;
            return false;
        }
        _appliedCaptureId = captureId;
        return true;
    }

    // What the card says before anything is pressed: the icon may be on the taskbar already (then the
    // button has nothing to do), or this machine may have no way of putting it there (then the three
    // lines take the place of the button straight away).
    private void LoadPinState()
    {
        try
        {
            if (TaskbarPinService.IsPinned()) { ShowPinned(); return; }
            if (!TaskbarPinService.CanTry()) ShowPinInstructions();
        }
        catch (Exception ex) { Trace?.Invoke($"Onboarding pin state: {ex}"); }
    }

    private async void OnPinToTaskbar(object sender, RoutedEventArgs e)
    {
        PinButton.IsEnabled = false;
        var result = await TaskbarPinService.TryPinAsync(Trace);
        PinButton.IsEnabled = true;
        if (result is TaskbarPinService.PinResult.Pinned or TaskbarPinService.PinResult.AlreadyPinned) ShowPinned();
        else ShowPinInstructions();
    }

    private void ShowPinned()
    {
        PinButton.Visibility = Visibility.Collapsed;
        PinInstructions.Visibility = Visibility.Collapsed;
        PinDone.Visibility = Visibility.Visible;
        PinSubtitle.Text = UiLanguage.Text("Готово: иконка Snapik теперь на панели задач", _language);
        PinSubtitle.SetResourceReference(ForegroundProperty, "PinnedBrush");
    }

    private void ShowPinInstructions()
    {
        PinButton.Visibility = Visibility.Collapsed;
        PinDone.Visibility = Visibility.Collapsed;
        PinInstructions.Visibility = Visibility.Visible;
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
        if (_step == 1 && (CaptureRefusal() is not null || !Apply(CaptureField.HotkeyId))) return;
        ShowStep(_step + 1);
    }

    private void OnStart(object sender, RoutedEventArgs e)
    {
        // Nothing was collected in the slides-only mode, so nothing is written back from it.
        if (!_howToOnly && (!Apply(CaptureField.HotkeyId) || !ApplyStartup())) return;
        _closedByButton = true;
        Close();
    }

    // The cross is "skip": the wizard counts as passed, so it does not come back on the next start.
    // The shortcut written is the last one that was actually registered, never a conflicting one the
    // user typed and left behind.
    private void OnSkip(object sender, RoutedEventArgs e)
    {
        _closedByButton = true;
        SkipSetup();
        Close();
    }

    // Alt+F4 and the taskbar close the window without touching either button, and they mean the same
    // as "Skip setup": the theme of step 4 is applied to the running application as it is clicked,
    // and leaving it applied but unsaved would repaint the session for a setup nobody finished.
    protected override void OnClosing(System.ComponentModel.CancelEventArgs e)
    {
        if (!_closedByButton) SkipSetup();
        base.OnClosing(e);
    }

    private void SkipSetup()
    {
        if (_howToOnly) return;
        // Step 4 repaints the application as it is clicked, so skipping the setup has to paint it
        // back: what was tried out was never chosen. A wizard nobody painted in repaints nothing:
        // the look of the application is not the wizard's to set on the way out.
        if (Appearance.SelectedTheme != _openedTheme || Appearance.SelectedAccent != _openedAccent)
        {
            Appearance.SelectedTheme = _openedTheme;
            Appearance.SelectedAccent = _openedAccent;
            ThemeService.Apply(_openedTheme, _openedAccent);
        }
        // The switch of step 1 changes the language of the running application at once, and the
        // candidate carries whatever it is at the end. Skipping the setup puts the language back the
        // same way the theme goes back: nothing the wizard was played with is kept.
        if (_language != _openedLanguage) ApplyLanguage(_openedLanguage);
        Apply(_appliedCaptureId);
    }

    // The text at the bottom left and the cross in the header mean the same thing and do the same
    // thing; the text says it in words, and says it on every step.
    private void OnSkipLink(object sender, MouseButtonEventArgs e) => OnSkip(sender, e);

    // "Minimize" is the window, not the wizard: nothing is applied and nothing is marked, the window
    // goes to the taskbar and comes back from it.
    private void OnMinimize(object sender, RoutedEventArgs e) => WindowState = WindowState.Minimized;

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

    // The two segments of the switch name the languages themselves and stay as they are in both
    // languages, so they are the one part of the window the Cyrillic sweep skips.
    private static IEnumerable<string> WizardStrings(OnboardingWindow window)
    {
        var visited = new HashSet<DependencyObject>();
        var found = new List<string>();
        void Walk(DependencyObject item)
        {
            if (ReferenceEquals(item, window.LanguageToggle) || !visited.Add(item)) return;
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
