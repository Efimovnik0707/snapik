using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Text.Json;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;

namespace SnapBrief.App;

public static class SmokeTestRunner
{
    public static async Task<bool> RunAsync(string? explicitDataDirectory)
    {
        var root = explicitDataDirectory ?? Path.Combine(Path.GetTempPath(), "SnapBrief", $"smoke-{Guid.NewGuid():N}");
        var workspace = new SessionWorkspace(root);
        UiSoundService.VerifyAssets();
        var screen = new Rect(0, 0, 1920, 1080);
        foreach (var crop in new[] { new Rect(500, 400, 540, 120), new Rect(500, 940, 540, 130), new Rect(500, 0, 540, 120), new Rect(0, 0, 540, 1080) })
        {
            var toolbar = OverlayEditorWindow.PlaceToolbar(crop, screen, new Size(460, 50), []);
            if (toolbar.IntersectsWith(crop) || !screen.Contains(toolbar))
                throw new InvalidOperationException("Toolbar obscures a capture with available outside space.");
        }
        var customSettingsPath = Path.Combine(root, "custom-hotkey-smoke.json");
        var customSettings = new HotkeySettings("custom:6:75", HotkeySettings.Default.PasteId)
        {
            AutoSaveCaptures = true, PlaySounds = false, SoundVolume = 35,
            CaptureEnabled = false, FullscreenSaveEnabled = true, FullscreenSaveId = "custom:4:44",
            RememberRegion = true, CaptureCursor = true, ShowNotifications = false, StackTopmost = false, StackWidth = 240, ClearStackAfterPaste = true,
            ConfirmSessionDiscard = false, StackHeight = 300,
            AnnotationColor = "#FF4D4F", AnnotationThickness = 9, AnnotationHighlightThickness = 22, AnnotationFontSize = 28,
            AnnotationShape = "ellipse", AnnotationFill = "translucent",
            AnnotationFillColor = "#101820", AnnotationOutline = false, AnnotationPalette = "neon", AnnotationPencil = "highlight",
            SaveFormat = "jpeg", JpegQuality = 73, SaveDirectory = root, Language = "en",
            PackageSaveDirectory = Path.Combine(root, "packages"), PackageCreateSubfolder = false,
            Theme = "dark", AccentId = "violet", OnboardingVersion = OnboardingWindow.CurrentVersion,
            SettingsVersion = HotkeySettings.CurrentSettingsVersion
        };
        customSettings.Save(customSettingsPath);
        var restoredSettings = HotkeySettings.Load(customSettingsPath);
        if (restoredSettings != customSettings || restoredSettings.FullscreenSaveGesture.VirtualKey != 44 ||
            restoredSettings.OnboardingVersion != OnboardingWindow.CurrentVersion ||
            restoredSettings.SettingsVersion != HotkeySettings.CurrentSettingsVersion)
            throw new InvalidOperationException("Local capture preferences did not survive a settings round trip.");
        VerifySoundDefaults(root);
        VerifyStripIsBoundedByItsMonitor();
        // The wizard is shown once per version: never seen (no file, or an older version) opens it,
        // the current version does not, and a demo run never does.
        if (!OnboardingWindow.ShouldShowOnboarding(false, HotkeySettings.Default, false) ||
            !OnboardingWindow.ShouldShowOnboarding(true, HotkeySettings.Default, false) ||
            OnboardingWindow.ShouldShowOnboarding(true, restoredSettings, false) ||
            OnboardingWindow.ShouldShowOnboarding(false, HotkeySettings.Default, true))
            throw new InvalidOperationException("The first run wizard is shown once per version, and never in a demo run.");
        // Two languages, one rule: Russian for a Russian system, English for every other locale. The
        // neighbouring alphabets used to be sent to Russian, which is what a Ukrainian tester got.
        if (OnboardingWindow.LanguageForCulture("ru") != "ru" || OnboardingWindow.LanguageForCulture("uk") != "en" ||
            OnboardingWindow.LanguageForCulture("be") != "en" || OnboardingWindow.LanguageForCulture("es") != "en" ||
            OnboardingWindow.LanguageForCulture("en") != "en")
            throw new InvalidOperationException("The suggested language must follow the system locale.");
        // ...but only where there is nothing to go on. A machine that already has a settings file
        // keeps the language in it: raising the version of the wizard shows it to everyone again,
        // and it must not turn a chosen Russian interface English on a Spanish system, nor a chosen
        // English one Russian on a Russian system.
        var chosenEnglish = HotkeySettings.Default with { Language = "en", OnboardingVersion = 1 };
        var chosenRussian = HotkeySettings.Default with { Language = "ru", OnboardingVersion = 1 };
        var firstRun = HotkeySettings.Default with { OnboardingVersion = 0 };
        if (OnboardingWindow.SuggestedLanguage(true, chosenEnglish, "ru") != "en" ||
            OnboardingWindow.SuggestedLanguage(false, chosenEnglish, "es") != "en" ||
            OnboardingWindow.SuggestedLanguage(true, chosenRussian, "es") != "ru" ||
            OnboardingWindow.SuggestedLanguage(false, firstRun, "uk") != "en" ||
            OnboardingWindow.SuggestedLanguage(false, firstRun, "ru") != "ru")
            throw new InvalidOperationException("The wizard must open in the chosen language and guess from the locale only on a first run.");
        if (OverlayEditorWindow.ParseAnnotationColor(restoredSettings.AnnotationColor) != Color.FromRgb(255, 77, 79) ||
            OverlayEditorWindow.ParseAnnotationColor("not a colour") != OverlayEditorWindow.DefaultAnnotationColor)
            throw new InvalidOperationException("Stored annotation colour must be read back, an invalid one must fall back to the default.");
        // The shape and the fill of the frame are remembered next to the colour and the thickness,
        // so the whole panel comes back the same way for the next capture.
        if (OverlayEditorWindow.ParseAnnotationShape(restoredSettings.AnnotationShape) != SnapBrief.Core.Models.AnnotationShape.Ellipse ||
            OverlayEditorWindow.ParseAnnotationFill(restoredSettings.AnnotationFill) != SnapBrief.Core.Models.AnnotationFill.Translucent ||
            OverlayEditorWindow.ParseAnnotationShape("hexagon") != SnapBrief.Core.Models.AnnotationShape.Rectangle ||
            OverlayEditorWindow.ParseAnnotationFill("2") != SnapBrief.Core.Models.AnnotationFill.None)
            throw new InvalidOperationException("Stored frame shape and fill must be read back, unknown ones must fall back to the defaults.");
        // The colour inside the frame and the outline switch travel with them; an empty colour is the
        // preference "the fill takes the colour of the outline", not a broken value.
        if (OverlayEditorWindow.ParseAnnotationFillColor(restoredSettings.AnnotationFillColor) != Color.FromRgb(16, 24, 32) ||
            restoredSettings.AnnotationOutline ||
            OverlayEditorWindow.ParseAnnotationFillColor(string.Empty) is not null ||
            OverlayEditorWindow.ParseAnnotationFillColor("not a colour") is not null ||
            !HotkeySettings.Default.AnnotationOutline || HotkeySettings.Default.AnnotationFillColor != string.Empty)
            throw new InvalidOperationException("The stored fill colour and outline flag must be read back, with an outline and no own colour by default.");
        // The palette is remembered by its name; a name nobody knows falls back to the standard set,
        // and the colour the editor starts with has to belong to that set.
        if (OverlayEditorWindow.ParseAnnotationPalette(restoredSettings.AnnotationPalette).Id != "neon" ||
            OverlayEditorWindow.ParseAnnotationPalette("rainbow").Id != "standard" ||
            OverlayEditorWindow.ParseAnnotationPalette("1").Id != "standard" ||
            OverlayEditorWindow.ParseAnnotationPalette(null).Id != "standard" ||
            HotkeySettings.Default.AnnotationPalette != "standard" ||
            OverlayEditorWindow.Palettes.Length != 3 ||
            OverlayEditorWindow.Palettes.Any(palette => palette.Colors.Length != 12 || palette.Quick.Length != 5) ||
            !OverlayEditorWindow.Palettes[0].Colors.Contains(HotkeySettings.Default.AnnotationColor) ||
            OverlayEditorWindow.ParseAnnotationColor(HotkeySettings.Default.AnnotationColor) != OverlayEditorWindow.DefaultAnnotationColor)
            throw new InvalidOperationException("The stored palette must be read back, and the default colour must belong to the standard palette.");
        // The size a caption is typed in is remembered next to the colour and the widths.
        if (restoredSettings.AnnotationFontSize != 28 ||
            HotkeySettings.Default.AnnotationFontSize != TextMarkMetrics.DefaultFontSize ||
            TextMarkMetrics.Clamp(0) != TextMarkMetrics.MinimumFontSize ||
            TextMarkMetrics.Clamp(400) != TextMarkMetrics.MaximumFontSize ||
            TextMarkMetrics.Clamp(double.NaN) != TextMarkMetrics.DefaultFontSize)
            throw new InvalidOperationException("The size of a caption must be stored, and a size nobody can draw must be brought back into range.");
        // The highlighter carries a width of its own, next to the one every other stroke shares.
        if (restoredSettings.AnnotationHighlightThickness != 22 ||
            HotkeySettings.Default.AnnotationHighlightThickness != OverlayEditorWindow.DefaultHighlightThickness ||
            OverlayEditorWindow.HighlightThicknessPresets.Length != 4 ||
            OverlayEditorWindow.ThicknessPresetsFor(EditorTool.Highlight) != OverlayEditorWindow.HighlightThicknessPresets ||
            OverlayEditorWindow.ThicknessPresetsFor(EditorTool.Pen) != OverlayEditorWindow.ThicknessPresets)
            throw new InvalidOperationException("The width of the highlighter must be stored and offered apart from the one of the pencil.");
        // The half of the pencil capsule that was armed last comes back with the next capture.
        if (OverlayEditorWindow.ParseAnnotationPencil(restoredSettings.AnnotationPencil) != EditorTool.Highlight ||
            OverlayEditorWindow.ParseAnnotationPencil("marker") != EditorTool.Pen ||
            OverlayEditorWindow.ParseAnnotationPencil(null) != EditorTool.Pen ||
            HotkeySettings.Default.AnnotationPencil != "pen")
            throw new InvalidOperationException("The stored pencil mode must be read back, with the pen by default.");
        // The strip and the editor write the same file: every write starts from the file on disk.
        var mergeSettingsPath = Path.Combine(root, "merge-settings-smoke.json");
        (HotkeySettings.Default with { AnnotationColor = "#FF0000", AnnotationThickness = 7 }).Save(mergeSettingsPath);
        if (!HotkeySettings.TryLoad(mergeSettingsPath, out var beforeMerge))
            throw new InvalidOperationException("A settings file that was just written must load back.");
        (beforeMerge with { StackTopmost = !beforeMerge.StackTopmost }).Save(mergeSettingsPath);
        var mergedSettings = HotkeySettings.Load(mergeSettingsPath);
        if (mergedSettings.AnnotationColor != "#FF0000" || mergedSettings.AnnotationThickness != 7 ||
            mergedSettings.StackTopmost == HotkeySettings.Default.StackTopmost)
            throw new InvalidOperationException("Changing one setting must keep the annotation defaults written by the editor.");
        var brokenSettingsPath = Path.Combine(root, "broken-settings-smoke.json");
        await File.WriteAllTextAsync(brokenSettingsPath, "{ \"CaptureId\": ");
        if (HotkeySettings.TryLoad(brokenSettingsPath, out _))
            throw new InvalidOperationException("A settings file that cannot be parsed must not be reported as loaded.");
        if (!HotkeySettings.TryLoad(Path.Combine(root, "missing-settings-smoke.json"), out var missingSettings) ||
            missingSettings != HotkeySettings.Default)
            throw new InvalidOperationException("A missing settings file must load the defaults and stay writable.");
        var emptySettingsPath = Path.Combine(root, "empty-settings-smoke.json");
        await File.WriteAllTextAsync(emptySettingsPath, "   \r\n");
        if (!HotkeySettings.TryLoad(emptySettingsPath, out var emptySettings) || emptySettings != HotkeySettings.Default)
            throw new InvalidOperationException("A settings file with nothing in it must read as the defaults.");
        var idlessSettingsPath = Path.Combine(root, "idless-settings-smoke.json");
        await File.WriteAllTextAsync(idlessSettingsPath, "{}");
        if (HotkeySettings.TryLoad(idlessSettingsPath, out _))
            throw new InvalidOperationException("Settings without the hotkey ids must not be reported as loaded.");
        // The write goes through a neighbouring temporary file, and that file must not outlive it.
        var atomicSettingsPath = Path.Combine(root, "atomic-settings-smoke.json");
        HotkeySettings.Default.Save(atomicSettingsPath);
        (HotkeySettings.Default with { JpegQuality = 55 }).Save(atomicSettingsPath);
        if (Directory.EnumerateFiles(root, "atomic-settings-smoke.json*").Count() != 1 ||
            HotkeySettings.Load(atomicSettingsPath).JpegQuality != 55)
            throw new InvalidOperationException("An atomic settings write must leave exactly one file, with the newest content.");
        // The accent lives in a dictionary of its own and is swapped whole; every accent must carry
        // the same keys, otherwise a DynamicResource would resolve under one accent and not under another.
        ThemeService.Apply("dark", "teal");
        if ((Application.Current.Resources["AccentBrush"] as SolidColorBrush)?.Color != Color.FromRgb(43, 179, 163))
            throw new InvalidOperationException("Applying an accent must replace the accent brushes of the application.");
        var accentKeys = ThemeService.Accents
            .Select(accent => KeysOf(ThemeService.LoadAccent(accent)))
            .ToArray();
        if (accentKeys.Any(keys => !keys.SequenceEqual(accentKeys[0])))
            throw new InvalidOperationException("The accent dictionaries must all define the same keys.");
        // The palette of the theme is swapped whole in the same way, and answers to the same rule:
        // a key present in one palette and missing from another would resolve under one theme and
        // leave a DynamicResource unresolved under the next.
        var themeKeys = ThemeService.Themes.Select(theme => KeysOf(ThemeService.LoadTheme(theme))).ToArray();
        if (themeKeys.Any(keys => !keys.SequenceEqual(themeKeys[0])))
            throw new InvalidOperationException("The theme palettes must all define the same keys.");
        // A key declared both here and in the base dictionary would be a key the base dictionary
        // wins or loses by merge order alone, and the theme would be overruled without a word.
        var baseKeys = KeysOf(new ResourceDictionary { Source = new Uri("Themes/SnapBriefTheme.xaml", UriKind.Relative) });
        if (themeKeys[0].Intersect(baseKeys).Any())
            throw new InvalidOperationException("A palette key must not also be declared by the base dictionary.");
        ThemeService.Apply("sea", "blue");
        if (Application.Current.Resources["SurfaceBrush"] is not LinearGradientBrush sea ||
            sea.GradientStops.Count != 2 || sea.GradientStops[0].Color != Color.FromRgb(0x16, 0x3A, 0x44) ||
            sea.GradientStops[1].Color != Color.FromRgb(0x1B, 0x3A, 0x2C) ||
            Application.Current.Resources.MergedDictionaries.Count(entry => entry.Source?.OriginalString.Contains("/Palettes/", StringComparison.Ordinal) == true) != 1)
            throw new InvalidOperationException("Applying a theme must replace the previous palette, not add another one.");
        ThemeService.Apply("nothing-like-a-theme", "blue");
        if (ThemeService.CurrentTheme != "dark" || Application.Current.Resources["SurfaceBrush"] is not SolidColorBrush)
            throw new InvalidOperationException("A theme nothing answers to must fall back to the dark palette.");
        ThemeService.Apply("dark", "blue");
        if ((Application.Current.Resources["AccentBrush"] as SolidColorBrush)?.Color != Color.FromRgb(47, 140, 255) ||
            Application.Current.Resources.MergedDictionaries.Count(entry => entry.Source?.OriginalString.Contains("/Accents/", StringComparison.Ordinal) == true) != 1)
            throw new InvalidOperationException("Applying an accent must replace the previous accent dictionary, not add another one.");
        var settingsWindow = WithoutBindingErrors("The settings window", () =>
        {
            var window = new HotkeySettingsWindow(restoredSettings);
            window.ApplyLanguage("en");
            if (!window.QualityLabel.Text.StartsWith("JPEG quality", StringComparison.Ordinal))
                throw new InvalidOperationException("The JPEG quality caption must follow the language applied to the window.");
            window.Measure(new Size(530, 480));
            window.Arrange(new Rect(0, 0, 530, 480));
            ResolveTriggerBindings(window);
            window.ApplyLanguage("ru");
            if (!window.QualityLabel.Text.StartsWith("Качество JPEG", StringComparison.Ordinal))
                throw new InvalidOperationException("The JPEG quality caption must follow the language applied to the window.");
            return window;
        });
        // The volume follows the sounds: it is on screen only while they are on.
        if (settingsWindow.VolumeSlider.Value != 35 || settingsWindow.VolumeRow.Visibility != Visibility.Collapsed)
            throw new InvalidOperationException("The volume must hold the stored value and stay hidden while the sounds are off.");
        settingsWindow.SoundsBox.IsChecked = true;
        if (settingsWindow.VolumeRow.Visibility != Visibility.Visible)
            throw new InvalidOperationException("The volume must appear together with the sounds.");
        settingsWindow.SoundsBox.IsChecked = false;
        if (settingsWindow.QualitySlider.Visibility != Visibility.Visible)
            throw new InvalidOperationException("JPEG quality must be visible while the JPEG format is selected.");
        settingsWindow.FormatBox.SelectedIndex = 0;
        if (settingsWindow.QualitySlider.Visibility != Visibility.Collapsed)
            throw new InvalidOperationException("JPEG quality must be hidden while the PNG format is selected.");
        // The field owns the hotkey now: what is written into it comes back, and the label is shown
        // as one capsule per key.
        if (settingsWindow.SelectedAccent != "violet")
            throw new InvalidOperationException("The accent row must show the accent the settings were opened with.");
        settingsWindow.CaptureField.HotkeyId = "custom:2:65";
        if (settingsWindow.CaptureField.HotkeyId != "custom:2:65" || settingsWindow.CaptureField.KeyCaps.Children.Count != 2 ||
            settingsWindow.FullscreenField.KeyCaps.Children.Count != HotkeySettings.Find(restoredSettings.FullscreenSaveId).Label.Split(" + ").Length)
            throw new InvalidOperationException("The hotkey field must keep the id it is given and show one capsule per key.");
        if ((Controls.ButtonChrome.GetHoverBackground(settingsWindow.SaveButton) as SolidColorBrush)?.Color != ((SolidColorBrush)settingsWindow.FindResource("AccentHoverBrush")).Color ||
            (Controls.ButtonChrome.GetPressedBackground(settingsWindow.SaveButton) as SolidColorBrush)?.Color != ((SolidColorBrush)settingsWindow.FindResource("AccentPressedBrush")).Color)
            throw new InvalidOperationException("The primary button must keep the accent while hovered and pressed.");
        // The package dialog holds its own folder; without one it starts where single captures go.
        if (restoredSettings.PackageDirectory() != Path.Combine(root, "packages") ||
            HotkeySettings.Default.PackageDirectory() != HotkeySettings.Default.SaveDirectory)
            throw new InvalidOperationException("The package folder must be remembered, and fall back to the save folder.");
        WithoutBindingErrors("The save package window", () => SavePackageWindow.RunSavePackageProbe(restoredSettings));
        WithoutBindingErrors("The discard session window", () => DiscardSessionWindow.RunDiscardProbe(restoredSettings));
        var onboarding = WithoutBindingErrors("The onboarding window", () =>
        {
            var window = OnboardingWindow.RunOnboardingProbe(restoredSettings);
            ResolveTriggerBindings(window);
            return window;
        });
        if (onboarding.Step != 0 || onboarding.SelectedLanguage != "ru" ||
            onboarding.Step1.Visibility != Visibility.Visible || onboarding.Step4.Visibility != Visibility.Collapsed)
            throw new InvalidOperationException("The wizard must come back to its first step after the probe.");
        if (onboarding.HowTo.KeyLabel != HotkeySettings.Find(restoredSettings.CaptureId).Label ||
            onboarding.CaptureField.HotkeyId != restoredSettings.CaptureId)
            throw new InvalidOperationException("The wizard must open on the shortcut the settings hold, and the hint must show it.");
        onboarding.GoToStep(3);
        if (onboarding.Step4.Visibility != Visibility.Visible || onboarding.StepText.Text != "Шаг 4 из 4")
            throw new InvalidOperationException("The last step must show the animated hint and its own number.");
        // The wizard is built for the checks above and belongs to nobody afterwards; the probe cannot
        // close it itself, because those checks read the window it returns.
        onboarding.Close();
        // Whatever closes the window (here: nothing but Close itself, as Alt+F4 or the taskbar would
        // do) has to leave the wizard marked as passed, or the first run comes back on every start.
        WithoutBindingErrors("The how-to slides", Controls.HowToSlides.RunSlidesProbe);
        VerifyHowToOnlyWizard(restoredSettings);
        VerifySlideKeysStayInsideTheWizard(restoredSettings);
        VerifyAShortcutNeedsAModifier(restoredSettings, root);
        var closedWithoutButtons = false;
        var skipped = new OnboardingWindow(restoredSettings) { MarkPassed = () => closedWithoutButtons = true };
        skipped.Close();
        if (!closedWithoutButtons)
            throw new InvalidOperationException("Closing the wizard without pressing anything must mark it as passed.");
        foreach (var (russian, english) in new[]
        {
            ("Настройки", "Settings"), ("Настройки клавиш", "Shortcut settings"), ("Сделать скриншот", "Take a screenshot"),
            ("Скриншот всего экрана в папку", "Save the whole screen to a folder"), ("Предлагать ту же область, что в прошлый раз", "Offer the same area as last time"),
            ("Показывать курсор мыши на скриншоте", "Show the mouse pointer in the screenshot"), ("Звуки", "Sounds"),
            ("Показывать уведомления", "Show notifications"), ("Закрыть", "Close"), ("Громкость", "Volume"),
            ("Все снимки уже отправлены. Сделайте новый снимок.", "Every capture was already sent. Take a new one."),
            ("Все поддерживаемые", "All supported"), ("Выберите PNG или JPEG.", "Choose PNG or JPEG."),
            ("Как пользоваться", "How it works"), ("Шаг {0} из {1}", "Step {0} of {1}"), ("Начать", "Get started"),
            ("Нажми на поле и введи своё сочетание", "Click the field and press your own shortcut"),
            ("Эта клавиша уже занята. Освободите её в другом приложении или выберите другую.", "This shortcut is already taken. Free it in the other application or pick another one."),
            ("Показать ленту", "Show the strip"), ("Очистить ленту", "Clear the strip"),
            ("Удалить снимки сессии?", "Delete the captures of this session?"), ("Больше не спрашивать", "Do not ask again"),
            ("В ленте максимум 10 снимков. Отправьте или удалите лишние", "The strip holds at most 10 captures. Paste or delete some first."),
            ("Снимки этой сессии будут удалены. Чтобы сохранить, нажмите «Сохранить пакет…» в меню •••",
                "The captures of this session will be deleted. To keep them, use \"Save package…\" in the ••• menu."),
            ("SnapBrief — Лента снимков", "SnapBrief — Capture strip")
        })
            if (UiLanguage.Text(russian, "en") != english || UiLanguage.Text(english, "ru") != russian)
                throw new InvalidOperationException($"Settings language switching failed for \"{russian}\".");
        VerifyWizardTranslations();
        if (restoredSettings.CaptureGesture.VirtualKey != 75 ||
            restoredSettings.CaptureGesture.Modifiers != (SnapBrief.Windows.HotkeyModifiers.Control | SnapBrief.Windows.HotkeyModifiers.Shift | SnapBrief.Windows.HotkeyModifiers.NoRepeat) ||
            HotkeySettings.Find("print-screen").Gesture.VirtualKey != 0x2C ||
            HotkeySettings.Find("custom:0:19").Gesture.VirtualKey != 0x13 ||
            HotkeySettings.Find("custom:0:19").Label != "Pause / Break" ||
            HotkeySettings.Find("custom:999:13").Id != HotkeySettings.Default.CaptureId)
            throw new InvalidOperationException("Custom hotkey persistence or legacy settings compatibility failed.");
        var captures = new List<CaptureItem>();
        var annotationNotes = new[] { "Увеличить кнопку", "Перенести пункт выше", "Уточнить подпись" };
        for (var i = 0; i < 3; i++)
        {
            var source = i == 2 ? CreatePrivacyBitmap(1920, 1080) : SessionWorkspace.CreateDemoBitmap(i, 1920, 1080, i == 0 ? 144 : 96);
            var capture = await workspace.AddImageAsync(source);
            capture.Note = i == 2 ? "Текст обрезается" : string.Empty;
            // The third capture carries a mark read out of the old format: a "redaction" written by
            // a build that still had the conceal tool, migrated by the same code a stored session
            // goes through. Its exported pixels are checked below, so the read path stays covered.
            capture.Annotations.Add(i == 2
                ? AnnotationItem.FromCore(
                    SnapBrief.Core.Models.AnnotationItem.Create(
                        SnapBrief.Core.Models.AnnotationKind.Redaction,
                        [new SnapBrief.Core.Models.NormalizedPoint(1050d / 1920, 650d / 1080), new SnapBrief.Core.Models.NormalizedPoint(1520d / 1920, 880d / 1080)],
                        "#FF315CF5", 6, note: annotationNotes[i]),
                    1920, 1080)
                : new AnnotationItem
                {
                    Kind = i == 1 ? EditorTool.Rectangle : EditorTool.Arrow,
                    Points = [new Point(1050, 650), new Point(1520, 880)],
                    Note = annotationNotes[i],
                    Color = Color.FromRgb(49, 92, 245),
                    Thickness = 6
                });
            if (i == 2)
            {
                // An oval blur: the mask follows the shape of the region in both renderers, so the
                // corner of its bounding box has to come out of the export untouched.
                capture.Annotations.Add(new AnnotationItem
                {
                    Kind = EditorTool.Blur,
                    Shape = SnapBrief.Core.Models.AnnotationShape.Ellipse,
                    Points = [new Point(980, 620), new Point(1400, 900)],
                    Color = Color.FromRgb(47, 140, 255),
                    Thickness = 6
                });
            }
            captures.Add(capture);
        }

        // A region can be an oval with a translucent fill; the exported PNG has to show the blend
        // inside the oval and leave the corner of its box alone.
        captures[1].Annotations.Add(new AnnotationItem
        {
            Kind = EditorTool.Rectangle,
            Shape = SnapBrief.Core.Models.AnnotationShape.Ellipse,
            Fill = SnapBrief.Core.Models.AnnotationFill.Translucent,
            Points = [new Point(200, 200), new Point(600, 500)],
            Color = Color.FromRgb(255, 77, 79),
            Thickness = 6
        });

        // Concealing is a region with a solid black fill and no outline now, and a region can also be
        // filled with blur: both are checked on the exported PNG of the privacy capture below.
        captures[2].Annotations.Add(new AnnotationItem
        {
            Kind = EditorTool.Rectangle,
            Fill = SnapBrief.Core.Models.AnnotationFill.Solid,
            FillColor = Colors.Black,
            HasOutline = false,
            Points = [new Point(200, 600), new Point(600, 800)],
            Color = Color.FromRgb(255, 59, 48),
            Thickness = 6
        });
        captures[2].Annotations.Add(new AnnotationItem
        {
            Kind = EditorTool.Rectangle,
            Fill = SnapBrief.Core.Models.AnnotationFill.Blur,
            Points = [new Point(200, 200), new Point(600, 400)],
            Color = Color.FromRgb(255, 59, 48),
            Thickness = 6
        });

        VerifyLegacyRedactionReadsAsAFilledRegion();
        Controls.AnnotationCanvas.VerifyBlurPreview(captures[0].Image);
        Controls.AnnotationCanvas.VerifyBlurCache(captures[0].Image);
        Controls.AnnotationCanvas.VerifyHoverManipulation(captures[0].Image);
        Controls.AnnotationCanvas.VerifyGestureRules(captures[0].Image);
        Controls.AnnotationCanvas.VerifyTextMarkGeometry(captures[0].Image);
        await VerifyHighlighterStaysOneTone(root);
        await VerifyCaptionIsTheSameSizeOnScreenAndInExport(root);
        foreach (var format in new[] { "png", "jpeg" })
        {
            var imagePath = Path.Combine(root, "local-save." + (format == "jpeg" ? "jpg" : "png"));
            await LocalImageSave.WriteAsync(captures[0].Image, imagePath, format, 73, false);
            using var imageStream = File.OpenRead(imagePath);
            var decoder = System.Windows.Media.Imaging.BitmapDecoder.Create(imageStream,
                System.Windows.Media.Imaging.BitmapCreateOptions.None, System.Windows.Media.Imaging.BitmapCacheOption.OnLoad);
            if (decoder.Frames[0].PixelWidth != captures[0].Image.PixelWidth || decoder.Frames[0].PixelHeight != captures[0].Image.PixelHeight ||
                (format == "jpeg" && decoder is not System.Windows.Media.Imaging.JpegBitmapDecoder) ||
                (format == "png" && decoder is not System.Windows.Media.Imaging.PngBitmapDecoder))
                throw new InvalidOperationException("Local save encoded the wrong format or dimensions.");
        }
        var prepared = await workspace.PrepareAsync(captures, "Сохранить цвета", SnapBrief.Windows.TargetProfiles.CodexDesktop.Id);
        await OverlayEditorWindow.RunCaptureResizeProbeAsync(workspace, captures[0]);
        await OverlayEditorWindow.RunCaptureResizeProbeAsync(workspace, captures[2]);
        // The tooltip of the panel is built for real inside the probe, so the binding that fills its
        // key capsule is watched here like every other binding of the run.
        WithoutBindingErrors("The markup panel", () => OverlayEditorWindow.RunShortcutHintProbe(captures[0]));
        WithoutBindingErrors("The colour and thickness panel", () => OverlayEditorWindow.RunPanelProbe(captures[0]));
        WithoutBindingErrors("The comments panel", () => OverlayEditorWindow.RunCommentsPanelProbe(captures[0]));
        WithoutBindingErrors("The click beside the capture", () => OverlayEditorWindow.RunOutsideClickProbe(captures[0]));
        WithoutBindingErrors("The text tool", () => OverlayEditorWindow.RunTextMarkProbe(captures[0]));
        var noteProbe = OverlayEditorWindow.RunNoteAffordanceProbe(captures[0]);
        var noteProbeCore = noteProbe.ToCore();
        var noteProbeLabel = SnapBrief.Core.Exporting.CaptureLabels.ForNotedAnnotations("A", noteProbeCore).SingleOrDefault();
        await using var noteProbePng = new MemoryStream();
        await new WpfExportImageRenderer().RenderAsync(noteProbeCore,
            new SnapBrief.Core.Exporting.ExportImageContext("A", 0, Path.GetFullPath(Path.Combine(workspace.SessionDirectory, noteProbe.SourcePath))),
            noteProbePng, default);
        // The badge of the dragged note has to be in the exported PNG where the editor showed it.
        var movedNote = noteProbe.Annotations.Single(a => a.Kind == EditorTool.Comment);
        var movedBadge = WpfExportImageRenderer.ExportBadge(noteProbeCore.Annotations.Single(a => a.Id == movedNote.Id),
            noteProbeLabel.DisplayLabel, noteProbe.Image.PixelWidth, noteProbe.Image.PixelHeight, 48);
        noteProbePng.Position = 0;
        var noteProbeExport = System.Windows.Media.Imaging.BitmapFrame.Create(noteProbePng,
            System.Windows.Media.Imaging.BitmapCreateOptions.None, System.Windows.Media.Imaging.BitmapCacheOption.OnLoad);
        var movedBadgePixel = PixelAt(noteProbeExport, (int)Math.Round(movedBadge.Center.X), (int)Math.Round(movedBadge.Center.Y));
        var noteOffsetTravelled = movedNote.NoteOffset is { X: > 1 } &&
            movedBadgePixel[0] == 255 && movedBadgePixel[1] == 140 && movedBadgePixel[2] == 47;

        var paths = prepared.GetImagePathsInOrder();
        // The names the user sees in a saved package: a two-digit index and the letter of the capture.
        if (!prepared.Manifest.Images.Select(image => image.FileName).SequenceEqual(["01-A.png", "02-B.png", "03-C.png"]))
            throw new InvalidOperationException("The exported images must be named by index and letter.");
        // Checked here, before the pruning probe below drops this revision: the export directory of
        // the first package is exactly what the probe is expected to remove.
        var preparedFilesOnDisk = paths.All(File.Exists);
        var decoded = paths.Select(SessionWorkspace.LoadBitmap).ToArray();
        var sourceFirst = captures[0].Image;
        var sourceCorner = PixelAt(sourceFirst, sourceFirst.PixelWidth - 1, sourceFirst.PixelHeight - 1);
        var exportedCorner = PixelAt(decoded[0], decoded[0].PixelWidth - 1, decoded[0].PixelHeight - 1);
        var redactionPixel = PixelAt(decoded[2], 1250, 48 + 760);
        var sourceBlurPixel = PixelAt(captures[2].Image, 1010, 700);
        var exportedBlurPixel = PixelAt(decoded[2], 1010, 48 + 700);
        // The corner of the box of an oval blur is outside the oval and keeps the pixels it had.
        var ovalBlurCornerKept = PixelAt(captures[2].Image, 985, 625).SequenceEqual(PixelAt(decoded[2], 985, 48 + 625));
        var redactionLabelHasLightInk = HasLightPixel(decoded[2], 1048, 48 + 615, 70, 35);
        // The new way to conceal: a region with a solid black fill and no outline hides the picture
        // exactly as the removed tool did.
        var filledConcealPixel = PixelAt(decoded[2], 400, 48 + 700);
        var concealedByFill = filledConcealPixel[3] == 255 && filledConcealPixel[0] < 8 && filledConcealPixel[1] < 8 && filledConcealPixel[2] < 8;
        // A region filled with blur: the picture inside it is blurred and the outline is still drawn.
        var blurFillSourceCenter = PixelAt(captures[2].Image, 400, 300);
        var blurFillExportCenter = PixelAt(decoded[2], 400, 48 + 300);
        var blurFillOutlinePixel = PixelAt(decoded[2], 200, 48 + 300);
        var blurFilledRegionExported = !blurFillSourceCenter.SequenceEqual(blurFillExportCenter)
            && blurFillOutlinePixel[0] == 48 && blurFillOutlinePixel[1] == 59 && blurFillOutlinePixel[2] == 255;
        var ovalSourceCenter = PixelAt(captures[1].Image, 400, 350);
        var ovalExportCenter = PixelAt(decoded[1], 400, 48 + 350);
        var ovalSourceCorner = PixelAt(captures[1].Image, 205, 205);
        var ovalExportCorner = PixelAt(decoded[1], 205, 48 + 205);
        var translucentOvalExported = !ovalSourceCenter.SequenceEqual(ovalExportCenter)
            // Translucent, not solid: the fill colour itself would be exactly 79, 77, 255 in BGRA.
            && !(ovalExportCenter[0] == 79 && ovalExportCenter[1] == 77 && ovalExportCenter[2] == 255)
            // An oval, not a box: the corner of the bounding box keeps the pixels of the capture.
            && ovalSourceCorner.SequenceEqual(ovalExportCorner);
        // A pasted capture is not removed: it keeps its place in the strip with the sent flag, stays
        // out of the next package and gives its letter away to the captures that are still waiting.
        captures[0].IsSent = true;
        await workspace.SaveAsync(captures, "Сохранить цвета", SnapBrief.Windows.TargetProfiles.CodexDesktop.Id);
        var reloadedAfterSend = await new SessionWorkspace(root).LoadCurrentAsync();
        var stripLabels = SnapBrief.Core.Exporting.SentCaptureRules.StripLabels([.. captures.Select(capture => capture.IsSent)]);
        var packageAfterSend = SnapBrief.Core.Exporting.SentCaptureRules.ForPackage(captures, capture => capture.IsSent);
        var sentFlagPersisted = reloadedAfterSend.Count == 3
            && reloadedAfterSend[0].IsSent
            && !reloadedAfterSend[1].IsSent
            && packageAfterSend.Count == 2
            && packageAfterSend[0].Id == captures[1].Id
            && stripLabels[0] is null && stripLabels[1] == "A" && stripLabels[2] == "B";
        var preparedAfterSend = await workspace.PrepareAsync(captures, packageAfterSend, string.Empty, SnapBrief.Windows.TargetProfiles.CodexDesktop.Id);
        sentFlagPersisted = sentFlagPersisted
            && preparedAfterSend.Manifest.CaptureCount == 2
            && preparedAfterSend.Manifest.Images[0].DisplayLabel == "A"
            && preparedAfterSend.Manifest.PromptText.Contains("A1: Перенести пункт выше", StringComparison.Ordinal)
            && preparedAfterSend.Manifest.PromptText.Contains("B1: Уточнить подпись", StringComparison.Ordinal)
            && !preparedAfterSend.Manifest.PromptText.Contains("Снимок C", StringComparison.Ordinal);
        // Only the newest three revision directories survive a prepare, and they are the three
        // highest revision numbers rather than the three names that happen to sort last.
        var preparedRevisions = new List<int> { preparedAfterSend.Manifest.Revision };
        var latestExport = preparedAfterSend;
        for (var attempt = 0; attempt < 5; attempt++)
        {
            latestExport = await workspace.PrepareAsync(captures, packageAfterSend, string.Empty, SnapBrief.Windows.TargetProfiles.CodexDesktop.Id);
            preparedRevisions.Add(latestExport.Manifest.Revision);
        }
        var keptRevisions = Directory.EnumerateDirectories(Path.Combine(workspace.SessionDirectory, "exports"), "revision-*")
            .Select(path => int.Parse(Path.GetFileName(path).Split('-')[1], System.Globalization.CultureInfo.InvariantCulture))
            .Order()
            .ToArray();
        sentFlagPersisted = sentFlagPersisted
            && keptRevisions.SequenceEqual(preparedRevisions.TakeLast(3))
            && Directory.Exists(latestExport.RootDirectory);
        captures[0].IsSent = false;

        var previousSessionId = workspace.SessionId;
        var previousSessionDirectory = workspace.SessionDirectory;
        var previousSourcePath = Path.GetFullPath(Path.Combine(previousSessionDirectory, captures[0].SourcePath));
        await workspace.StartNewSessionAsync(captures, "Сохранить цвета", SnapBrief.Windows.TargetProfiles.CodexDesktop.Id);
        var freshSessionId = workspace.SessionId;
        var restartedWorkspace = new SessionWorkspace(root);
        var restartedCaptures = await restartedWorkspace.LoadCurrentAsync();
        var freshSessionPersisted = freshSessionId != previousSessionId
            && restartedWorkspace.SessionId == freshSessionId
            && restartedCaptures.Count == 0
            && string.IsNullOrEmpty(restartedWorkspace.RestoredGlobalNote)
            && restartedWorkspace.RestoredProfileId is null
            && File.Exists(Path.Combine(previousSessionDirectory, "session.json"))
            && File.Exists(previousSourcePath);
        // Rotation keeps the previous session on disk (the check right above); deleting is a call of
        // its own, and these two cover the deletion and the cleanup at the start of a run. Both work
        // in roots of their own, so they cannot touch the session this run is building.
        await VerifySessionPurgeAsync(Path.Combine(root, "purge-probe"));
        await VerifySessionDiscardAsync(Path.Combine(root, "discard-probe"));
        var success = paths.Count == 3
            && preparedFilesOnDisk
            && decoded.All(bitmap => bitmap.PixelWidth == 1920 && bitmap.PixelHeight == 1128)
            && sourceCorner.SequenceEqual(exportedCorner)
            && redactionPixel[3] == 255 && redactionPixel[0] < 8 && redactionPixel[1] < 8 && redactionPixel[2] < 8
            && !sourceBlurPixel.SequenceEqual(exportedBlurPixel)
            && ovalBlurCornerKept
            && redactionLabelHasLightInk
            && prepared.Manifest.PromptText.Contains("Увеличить кнопку", StringComparison.Ordinal)
            && prepared.Manifest.PromptText.Contains("Снимок C", StringComparison.Ordinal)
            && prepared.Manifest.PromptText.Contains("C1: Уточнить подпись", StringComparison.Ordinal)
            && prepared.Manifest.NoteCount == 5
            && sentFlagPersisted
            && translucentOvalExported
            && concealedByFill
            && blurFilledRegionExported
            && freshSessionPersisted;
        success = success
            && noteProbe.Annotations.Single(a => a.Kind == EditorTool.Comment).Note == "Контекстная заметка"
            && noteProbeLabel.DisplayLabel == "A1"
            && noteProbePng.Length > 0
            && noteOffsetTravelled;
        var result = new
        {
            success,
            prepared.Manifest.ExportId,
            prepared.Manifest.CaptureCount,
            prepared.Manifest.NoteCount,
            imagePaths = paths,
            prepared.Manifest.PromptText
        };
        Directory.CreateDirectory(root);
        await File.WriteAllTextAsync(Path.Combine(root, "smoke-test-result.json"), JsonSerializer.Serialize(result, new JsonSerializerOptions { WriteIndented = true }));
        return success;
    }

    // A highlighter lays its ink down once: the joint between two segments of a stroke must be
    // exactly as light as the middle of a segment, and that is what tells it from the pencil. Drawn
    // over white, where a second layer of transparent ink would show at once, and next to a pencil
    // stroke, which has to come out as the colour of the mark itself.
    private static async Task VerifyHighlighterStaysOneTone(string root)
    {
        var probeRoot = Path.Combine(root, "highlighter-probe");
        Directory.CreateDirectory(probeRoot);
        var stride = 400 * 4;
        var pixels = new byte[stride * 200];
        Array.Fill(pixels, (byte)255);
        var white = System.Windows.Media.Imaging.BitmapSource.Create(400, 200, 96, 96, PixelFormats.Bgra32, null, pixels, stride);
        white.Freeze();
        var imagePath = Path.Combine(probeRoot, "white.png");
        await LocalImageSave.WriteAsync(white, imagePath, "png", 92, false);

        SnapBrief.Core.Models.AnnotationItem Stroke(SnapBrief.Core.Models.AnnotationKind kind, double y) =>
            SnapBrief.Core.Models.AnnotationItem.Create(kind,
                [new(0.1, y), new(0.3, y), new(0.5, y), new(0.8, y)], "#FFFF3B30", 16);
        var capture = SnapBrief.Core.Models.CaptureItem.Create("source/white.png", 400, 200) with
        {
            Annotations = [Stroke(SnapBrief.Core.Models.AnnotationKind.Highlight, 0.35), Stroke(SnapBrief.Core.Models.AnnotationKind.Freehand, 0.75)]
        };
        await using var png = new MemoryStream();
        await new WpfExportImageRenderer().RenderAsync(capture,
            new SnapBrief.Core.Exporting.ExportImageContext("A", 0, imagePath), png, default);
        png.Position = 0;
        var exported = System.Windows.Media.Imaging.BitmapFrame.Create(png,
            System.Windows.Media.Imaging.BitmapCreateOptions.None, System.Windows.Media.Imaging.BitmapCacheOption.OnLoad);

        var middle = PixelAt(exported, 80, 48 + 70);
        var joint = PixelAt(exported, 120, 48 + 70);
        if (!middle.SequenceEqual(joint))
            throw new InvalidOperationException("The joint of a highlighter stroke came out darker than the middle of a segment.");
        if (middle[0] == 255 && middle[1] == 255 && middle[2] == 255)
            throw new InvalidOperationException("The highlighter left nothing on the capture.");
        if (middle[0] == 48 && middle[1] == 59 && middle[2] == 255)
            throw new InvalidOperationException("The highlighter must be transparent, not the colour of the mark itself.");
        var pencil = PixelAt(exported, 120, 48 + 150);
        if (pencil[0] != 48 || pencil[1] != 59 || pencil[2] != 255)
            throw new InvalidOperationException("The pencil must draw the colour of the mark, whole.");
        Directory.Delete(probeRoot, true);
    }

    // The letters of a caption are the same size on screen and in the exported PNG: the editor draws
    // them at the size of the mark scaled by the capture, the export at the size of the mark, and the
    // ink both of them leave is measured here against the same yardstick.
    private static async Task VerifyCaptionIsTheSameSizeOnScreenAndInExport(string root)
    {
        var probeRoot = Path.Combine(root, "caption-probe");
        Directory.CreateDirectory(probeRoot);
        var stride = 400 * 4;
        var pixels = new byte[stride * 200];
        Array.Fill(pixels, (byte)255);
        var white = System.Windows.Media.Imaging.BitmapSource.Create(400, 200, 96, 96, PixelFormats.Bgra32, null, pixels, stride);
        white.Freeze();
        var imagePath = Path.Combine(probeRoot, "white.png");
        await LocalImageSave.WriteAsync(white, imagePath, "png", 92, false);

        const string words = "Привет";
        const double fontSize = 32;
        var editorMark = new AnnotationItem
        {
            Kind = EditorTool.Text, Points = [new Point(40, 60)], Text = words, FontSize = fontSize,
            Color = Color.FromRgb(255, 59, 48)
        };
        TextMarkMetrics.Fit(editorMark);
        var canvas = new Controls.AnnotationCanvas
        {
            Image = white, Annotations = [editorMark], ImagePadding = 0, Width = 400, Height = 200
        };
        canvas.Measure(new Size(400, 200));
        canvas.Arrange(new Rect(0, 0, 400, 200));
        var onScreen = InkBounds(canvas.RenderAnnotated(), 0);

        var capture = SnapBrief.Core.Models.CaptureItem.Create("source/white.png", 400, 200) with
        {
            Annotations = [editorMark.ToCore(400, 200)]
        };
        await using var png = new MemoryStream();
        await new WpfExportImageRenderer().RenderAsync(capture,
            new SnapBrief.Core.Exporting.ExportImageContext("A", 0, imagePath), png, default);
        png.Position = 0;
        var exported = System.Windows.Media.Imaging.BitmapFrame.Create(png,
            System.Windows.Media.Imaging.BitmapCreateOptions.None, System.Windows.Media.Imaging.BitmapCacheOption.OnLoad);
        var inExport = InkBounds(exported, 48);

        var measured = TextMarkMetrics.Measure(words, fontSize);
        if (Math.Abs(onScreen.Width - inExport.Width) > 2 || Math.Abs(onScreen.Height - inExport.Height) > 2)
            throw new InvalidOperationException($"A caption came out {onScreen.Width}x{onScreen.Height} on screen and {inExport.Width}x{inExport.Height} in the export.");
        if (inExport.Width > measured.Width + 2 || inExport.Height > measured.Height + 2 || inExport.Height < fontSize / 2)
            throw new InvalidOperationException("The letters of a caption must fill the box the mark claims for them.");
        Directory.Delete(probeRoot, true);
    }

    // The box the ink of the picture takes, in pixels, below the header of the export.
    private static Rect InkBounds(System.Windows.Media.Imaging.BitmapSource bitmap, int offsetY)
    {
        var converted = new System.Windows.Media.Imaging.FormatConvertedBitmap(bitmap, PixelFormats.Bgra32, null, 0);
        var width = converted.PixelWidth;
        var height = converted.PixelHeight - offsetY;
        var stride = width * 4;
        var pixels = new byte[stride * height];
        converted.CopyPixels(new Int32Rect(0, offsetY, width, height), pixels, stride, 0);
        int left = width, top = height, right = -1, bottom = -1;
        for (var y = 0; y < height; y++)
        for (var x = 0; x < width; x++)
        {
            var offset = y * stride + x * 4;
            if (pixels[offset] > 240 && pixels[offset + 1] > 240 && pixels[offset + 2] > 240) continue;
            if (x < left) left = x;
            if (x > right) right = x;
            if (y < top) top = y;
            if (y > bottom) bottom = y;
        }
        if (right < 0) throw new InvalidOperationException("The caption left no ink on the picture at all.");
        return new Rect(left, top, right - left + 1, bottom - top + 1);
    }

    // The start of a run takes every session the previous run left in the root, together with the
    // pointer at the last one, and leaves everything else in that root alone.
    private static async Task VerifySessionPurgeAsync(string probeRoot)
    {
        Directory.CreateDirectory(probeRoot);
        var stale = new[] { Guid.NewGuid().ToString("N"), Guid.NewGuid().ToString("N") };
        foreach (var name in stale)
        {
            Directory.CreateDirectory(Path.Combine(probeRoot, name, "source"));
            await File.WriteAllTextAsync(Path.Combine(probeRoot, name, "session.json"), "{}");
        }
        await File.WriteAllTextAsync(Path.Combine(probeRoot, "current-session.txt"), stale[0]);
        await File.WriteAllTextAsync(Path.Combine(probeRoot, "settings.json"), "{}");
        await File.WriteAllTextAsync(Path.Combine(probeRoot, "keep-me.txt"), "Это не сессия");
        Directory.CreateDirectory(Path.Combine(probeRoot, "not-a-session"));

        await new SessionWorkspace(probeRoot).PurgePreviousSessionsAsync();

        if (stale.Any(name => Directory.Exists(Path.Combine(probeRoot, name))) ||
            File.Exists(Path.Combine(probeRoot, "current-session.txt")))
            throw new InvalidOperationException("A new run must remove every session the previous one left behind.");
        if (!File.Exists(Path.Combine(probeRoot, "settings.json")) ||
            !File.Exists(Path.Combine(probeRoot, "keep-me.txt")) ||
            !Directory.Exists(Path.Combine(probeRoot, "not-a-session")))
            throw new InvalidOperationException("The cleanup must leave everything in the sessions root that is not a session.");
    }

    // Clearing the strip and leaving the application delete the session directory with everything in
    // it and start an empty session instead.
    private static async Task VerifySessionDiscardAsync(string probeRoot)
    {
        var workspace = new SessionWorkspace(probeRoot);
        var capture = await workspace.AddImageAsync(SessionWorkspace.CreateDemoBitmap(0, 400, 300));
        await workspace.PrepareAsync([capture], string.Empty, null);
        var directory = workspace.SessionDirectory;
        var discardedId = workspace.SessionId;
        if (!Directory.Exists(Path.Combine(directory, "exports")))
            throw new InvalidOperationException("A prepared package must leave an exports directory for the deletion to take.");

        await workspace.DiscardCurrentSessionAsync();

        if (Directory.Exists(directory) || File.Exists(Path.Combine(probeRoot, "current-session.txt")))
            throw new InvalidOperationException("Discarding a session must take its directory and the pointer with it.");
        if (workspace.SessionId == discardedId || (await new SessionWorkspace(probeRoot).LoadCurrentAsync()).Count != 0)
            throw new InvalidOperationException("A discarded session must be replaced by an empty one.");
    }

    // One capture, one soft shutter: the quieter default and the file that goes with it. The volume
    // of a file written before versions existed is moved once, and only if it is the old default.
    private static void VerifySoundDefaults(string root)
    {
        if (HotkeySettings.Default.SoundVolume != 40)
            throw new InvalidOperationException("A machine that has never chosen must get the quiet default volume.");
        var loudPath = Path.Combine(root, "loud-settings-smoke.json");
        (HotkeySettings.Default with { SoundVolume = 60, SettingsVersion = 0 }).Save(loudPath);
        // Reading is reading: the preferences are read on every capture, and a read that rewrote the
        // file would drop every key this build does not know about, without anyone asking for it.
        var beforeRead = File.ReadAllText(loudPath);
        HotkeySettings.Load(loudPath);
        if (File.ReadAllText(loudPath) != beforeRead)
            throw new InvalidOperationException("Reading the settings must not write them back.");
        var migrated = HotkeySettings.LoadAndMigrate(loudPath);
        var kept = HotkeySettings.LoadAndMigrate(loudPath);
        if (File.ReadAllText(loudPath) == beforeRead)
            throw new InvalidOperationException("The start of the application must write the migrated settings back once.");
        var pickedPath = Path.Combine(root, "picked-settings-smoke.json");
        (HotkeySettings.Default with { SoundVolume = 75, SettingsVersion = 0 }).Save(pickedPath);
        var picked = HotkeySettings.LoadAndMigrate(pickedPath);
        if (migrated.SoundVolume != 40 || migrated.SettingsVersion != HotkeySettings.CurrentSettingsVersion ||
            kept.SoundVolume != 40 || picked.SoundVolume != 75 ||
            picked.SettingsVersion != HotkeySettings.CurrentSettingsVersion)
            throw new InvalidOperationException("The volume migration must move the old default once and leave a chosen value alone.");
        // The sound that was replaced must not survive next to the assembly, or the installer would
        // ship both and the old shutter would still be the one on disk.
        if (File.Exists(Path.Combine(AppContext.BaseDirectory, "Assets", "Audio", "shutter-2-050s.mp3")))
            throw new InvalidOperationException("The shutter that was replaced is still shipped next to the assembly.");
    }

    // The keys of a dictionary that is swapped whole, sorted so that two of them can be compared.
    private static string[] KeysOf(ResourceDictionary dictionary) =>
        dictionary.Keys.Cast<object>().Select(key => key.ToString()!).OrderBy(key => key, StringComparer.Ordinal).ToArray();

    // The strip is bounded by the monitor it opens on, not by a number: a width stored on a large
    // screen is pulled back inside the working area of a small one, and a drag that goes past the
    // screen stops at its edge. The strip itself has no smoke run (it needs a shown window and a
    // real monitor), so the geometry it is built on is checked here.
    private static void VerifyStripIsBoundedByItsMonitor()
    {
        const double work = 1920;
        var stretched = Controls.StripResizeGeometry.ClampWidth(5000, work);
        if (stretched != work - Controls.StripResizeGeometry.EdgeGap || stretched <= 900)
            throw new InvalidOperationException("The width of the strip must be bounded by the working area, and that leaves room for half a screen.");
        if (Controls.StripResizeGeometry.ClampWidth(1600, 1366) != 1356 ||
            Controls.StripResizeGeometry.ClampWidth(40, work) != Controls.StripResizeGeometry.MinimumWidth)
            throw new InvalidOperationException("A width stored on a large monitor must come back inside a small one, and the minimum must hold.");
        var (left, width) = Controls.StripResizeGeometry.Resize(work, 260, -2000, 0);
        if (width != work || left != 0)
            throw new InvalidOperationException("Dragging the strip past the screen must stop at the edge of the working area.");
        if (Controls.StripResizeGeometry.ResizeListHeight(372, 2000, 100, 0, 2000) != 1900)
            throw new InvalidOperationException("The height of the strip must be bounded by the working area, not by a number.");
    }

    // The tray opens the how-to slides on their own: the last step and nothing else, one button, and
    // no language switch — the language lives in the settings by then. Which is why the caption of
    // that one button is checked in both languages: there is nothing on this window to put it right.
    private static void VerifyHowToOnlyWizard(HotkeySettings settings)
    {
        foreach (var (language, caption) in new[] { ("ru", "Готово"), ("en", "Done") })
        {
            var wizard = WithoutBindingErrors("The how-to wizard", () =>
            {
                var window = new OnboardingWindow(settings with { Language = language }, howToOnly: true);
                window.Measure(new Size(620, 600));
                window.Arrange(new Rect(0, 0, 620, 600));
                window.UpdateLayout();
                return window;
            });
            var hidden = wizard.Step1.Visibility != Visibility.Visible && wizard.Step2.Visibility != Visibility.Visible &&
                wizard.Step3.Visibility != Visibility.Visible && wizard.LanguageToggle.Visibility != Visibility.Visible &&
                wizard.BackButton.Visibility != Visibility.Visible && wizard.NextButton.Visibility != Visibility.Visible &&
                wizard.StepText.Visibility != Visibility.Visible;
            var shown = wizard.Step4.Visibility == Visibility.Visible && wizard.StartButton.Visibility == Visibility.Visible &&
                wizard.HowTo.Slide == 0;
            var titled = wizard.SelectedLanguage == language && wizard.StartButton.Content as string == caption;
            wizard.Close();
            if (!hidden || !shown)
                throw new InvalidOperationException("The slides-only wizard must show the last step and hide the steps, the switch and the buttons.");
            if (!titled)
                throw new InvalidOperationException($"The slides-only wizard must open in the chosen language and say \"{caption}\" on its only button.");
        }
    }

    // A shortcut needs Ctrl, Alt, Shift or Win, and only Print Screen and Pause stand alone. The
    // field refuses to record anything else, and a "custom:0:<key>" already sitting in a settings
    // file (a bare arrow recorded by an older build) is read as the default instead of being
    // registered globally once more.
    private static void VerifyAShortcutNeedsAModifier(HotkeySettings settings, string root)
    {
        const string bareLeftArrow = "custom:0:37";
        if (HotkeySettings.Find(bareLeftArrow).Id != HotkeySettings.Choices[0].Id ||
            HotkeySettings.Find("custom:0:83").Id != HotkeySettings.Choices[0].Id)
            throw new InvalidOperationException("A stored shortcut without a modifier must be read as the default one.");
        // A shortcut that ends with a modifier: "Ctrl + LeftShift", which an older field wrote when
        // Shift was let go of with Ctrl still down.
        if (HotkeySettings.Find("custom:2:161").Id != HotkeySettings.Choices[0].Id)
            throw new InvalidOperationException("A stored shortcut that ends with a modifier must be read as the default one.");
        if (HotkeySettings.Find("custom:0:44").Gesture.VirtualKey != 0x2C ||
            HotkeySettings.Find("custom:0:19").Gesture.VirtualKey != 0x13 ||
            HotkeySettings.Find("custom:2:37").Id != "custom:2:37")
            throw new InvalidOperationException("Print Screen, Pause and any combination with a modifier must survive the read.");
        // Each shortcut falls back to its own default: answering all of them with the capture one
        // would give the fullscreen save the gesture of the capture, and the strip would then report
        // "This shortcut is already taken" about a shortcut the user never chose.
        var refused = HotkeySettings.Default with { CaptureId = bareLeftArrow, PasteId = bareLeftArrow, FullscreenSaveId = bareLeftArrow };
        if (refused.PasteGesture == refused.CaptureGesture || refused.FullscreenSaveGesture == refused.CaptureGesture ||
            HotkeySettings.Find(bareLeftArrow, HotkeySettings.Default.PasteId).Id != HotkeySettings.Default.PasteId ||
            HotkeySettings.Find(bareLeftArrow, HotkeySettings.DefaultFullscreenSaveId).Id != HotkeySettings.DefaultFullscreenSaveId)
            throw new InvalidOperationException("A refused id must fall back to the default of its own shortcut, not to the capture one.");
        // And the file is put right once, so that what it holds and what the window shows agree.
        var barePath = Path.Combine(root, "bare-shortcut-smoke.json");
        (HotkeySettings.Default with { CaptureId = bareLeftArrow }).Save(barePath);
        var healed = HotkeySettings.LoadAndMigrate(barePath);
        if (healed.CaptureId != HotkeySettings.Default.CaptureId || HotkeySettings.Load(barePath).CaptureId != HotkeySettings.Default.CaptureId)
            throw new InvalidOperationException("A settings file holding a refused shortcut must be put right when it is read.");
        WithoutBindingErrors("The hotkey field", () => Controls.HotkeyField.RunHotkeyFieldProbe("ru"));
        var wizard = WithoutBindingErrors("The wizard on a shortcut without a modifier", () =>
        {
            var window = new OnboardingWindow(settings with { CaptureId = bareLeftArrow });
            window.Measure(new Size(620, 600));
            window.Arrange(new Rect(0, 0, 620, 600));
            window.UpdateLayout();
            return window;
        });
        var label = wizard.HowTo.KeyLabel;
        wizard.Close();
        if (label != HotkeySettings.Choices[0].Label)
            throw new InvalidOperationException("A wizard opened on a shortcut without a modifier must show the default one on its capsule.");
    }

    // The arrow keys of the slides: they move one slide, they are eaten so that nothing else reads
    // them, they do nothing at the ends, and they never take the wizard off its step or off the
    // screen. A shortcut of a bare Left used to be registered globally, and the arrow then reached
    // the capture instead of the slides, which hid the wizard for good.
    // The handler is called directly: a real key event needs a PresentationSource, that is a window
    // shown with a handle of its own, and the smoke run shows nothing.
    private static void VerifySlideKeysStayInsideTheWizard(HotkeySettings settings)
    {
        var closed = false;
        var wizard = WithoutBindingErrors("The slide keys of the wizard", () =>
        {
            var window = new OnboardingWindow(settings, howToOnly: true);
            window.Measure(new Size(620, 600));
            window.Arrange(new Rect(0, 0, 620, 600));
            window.UpdateLayout();
            return window;
        });
        wizard.Closed += (_, _) => closed = true;
        var step = wizard.Step;
        if (!wizard.HandleNavigationKey(Key.Left) || wizard.HowTo.Slide != 0)
            throw new InvalidOperationException("The left arrow on the first slide must be eaten and leave the slide where it is.");
        if (!wizard.HandleNavigationKey(Key.Right) || wizard.HowTo.Slide != 1 || wizard.HowTo.AutoAdvancing)
            throw new InvalidOperationException("The right arrow must show the next slide and stop the automatic run.");
        for (var i = 0; i < Controls.HowToSlides.SlideCount; i++) wizard.HandleNavigationKey(Key.Right);
        if (wizard.HowTo.Slide != Controls.HowToSlides.SlideCount - 1)
            throw new InvalidOperationException("The right arrow on the last slide must stay on it instead of wrapping round.");
        if (wizard.HandleNavigationKey(Key.Down) || wizard.HandleNavigationKey(Key.Escape))
            throw new InvalidOperationException("Only the two arrows belong to the slides; every other key stays with the window.");
        if (wizard.Step != step || closed)
            throw new InvalidOperationException("The arrows must not move the wizard between its steps, and must not close it.");
        wizard.Close();
    }

    // The strings of the welcome step, and the rule that lets any of them travel back: the way from
    // English to Russian is a search by value, so two Russian keys sharing one English value would
    // send the wrong Russian string back.
    private static void VerifyWizardTranslations()
    {
        foreach (var (russian, english) in new[]
        {
            ("Добро пожаловать", "Welcome"), ("Язык интерфейса", "Interface language"),
            ("Первый снимок", "The first capture"), ("Обведи место", "Frame the spot"),
            ("Снимки остаются в ленте", "The captures stay in the strip"), ("Слайд {0} из {1}", "Slide {0} of {1}"),
            ("SnapBrief делает скриншот по твоей клавише и кладёт его в чат с ИИ вместе с комментариями.",
                "SnapBrief takes a screenshot on your own shortcut and puts it into an AI chat together with your comments.")
        })
            if (UiLanguage.Text(russian, "en") != english || UiLanguage.Text(english, "ru") != russian)
                throw new InvalidOperationException($"The wizard is not translated both ways for \"{russian}\".");
        var duplicate = UiLanguage.EnglishValues.GroupBy(value => value, StringComparer.Ordinal).FirstOrDefault(group => group.Count() > 1);
        if (duplicate is not null)
            throw new InvalidOperationException($"Two Russian strings share the English value \"{duplicate.Key}\", so one of them cannot come back.");
    }

    // A mark written by a build that still had the conceal tool comes back as a region with a solid
    // black fill and no outline, and is written back in that shape; the fill also survives the clone
    // the undo history is made of.
    private static void VerifyLegacyRedactionReadsAsAFilledRegion()
    {
        var legacy = SnapBrief.Core.Models.AnnotationItem.Create(SnapBrief.Core.Models.AnnotationKind.Redaction,
            [new SnapBrief.Core.Models.NormalizedPoint(0.1, 0.1), new SnapBrief.Core.Models.NormalizedPoint(0.4, 0.4)]);
        var migrated = AnnotationItem.FromCore(legacy, 1000, 800);
        if (migrated.Kind != EditorTool.Rectangle || migrated.Fill != SnapBrief.Core.Models.AnnotationFill.Solid ||
            migrated.FillColor != Colors.Black || migrated.HasOutline)
            throw new InvalidOperationException("A legacy redaction must read as a black region without an outline.");
        var written = migrated.ToCore(1000, 800);
        if (written.Kind != SnapBrief.Core.Models.AnnotationKind.Rectangle ||
            written.Fill != SnapBrief.Core.Models.AnnotationFill.Solid ||
            written.FillColor != "#FF000000" || written.HasOutline)
            throw new InvalidOperationException("A migrated redaction must be written back as a filled region without an outline.");
        var clone = migrated.Clone();
        if (clone.FillColor != migrated.FillColor || clone.HasOutline != migrated.HasOutline || clone.Fill != migrated.Fill)
            throw new InvalidOperationException("The fill of a region must survive the clone the undo history is made of.");
    }

    // A binding that cannot resolve its path is not an exception: WPF writes it to the trace and
    // leaves the control unstyled, so the smoke run listens for those records and fails on them.
    private static void WithoutBindingErrors(string what, Action action) => WithoutBindingErrors(what, () => { action(); return true; });

    private static T WithoutBindingErrors<T>(string what, Func<T> action)
    {
        T result;
        PresentationTraceSources.Refresh();
        var source = PresentationTraceSources.DataBindingSource;
        var listener = new BindingErrorListener();
        var previousLevel = source.Switch.Level;
        var errors = new List<string>();
        source.Switch.Level = SourceLevels.Error;
        source.Listeners.Add(listener);
        try { result = action(); }
        finally
        {
            // Detached from the trace source first, disposed only then: a listener disposed while the
            // source still holds it would keep receiving records.
            source.Listeners.Remove(listener);
            source.Switch.Level = previousLevel;
            errors.AddRange(listener.Errors);
            listener.Dispose();
        }
        if (errors.Count > 0)
            throw new InvalidOperationException($"{what} reported a binding error: {errors[0]}");
        return result;
    }

    // A binding inside a template trigger is evaluated only while the trigger is active, and a smoke
    // run has no mouse pointer: the same paths are resolved here against the button itself, so a path
    // that leads nowhere is written to the trace exactly as it would be on hover.
    private static void ResolveTriggerBindings(DependencyObject root)
    {
        if (root is System.Windows.Controls.Control { Template: { } template } control)
        {
            foreach (var setter in template.Triggers.OfType<Trigger>().SelectMany(trigger => trigger.Setters).OfType<Setter>())
                if (setter.Value is System.Windows.Data.Binding { RelativeSource.Mode: System.Windows.Data.RelativeSourceMode.TemplatedParent } binding)
                {
                    // The probe target takes anything (Tag is typed object), so a value of the wrong type
                    // cannot hide the path error behind a conversion one; the rest of the binding travels
                    // along, otherwise a converter or a fallback would change what the trace reports.
                    var probe = new FrameworkElement();
                    System.Windows.Data.BindingOperations.SetBinding(probe, FrameworkElement.TagProperty,
                        new System.Windows.Data.Binding
                        {
                            Path = binding.Path, Source = control,
                            Converter = binding.Converter, ConverterParameter = binding.ConverterParameter,
                            FallbackValue = binding.FallbackValue, TargetNullValue = binding.TargetNullValue
                        });
                    System.Windows.Data.BindingOperations.ClearBinding(probe, FrameworkElement.TagProperty);
                }
        }
        foreach (var child in System.Windows.LogicalTreeHelper.GetChildren(root))
            if (child is DependencyObject dependency) ResolveTriggerBindings(dependency);
    }

    private sealed class BindingErrorListener : TraceListener
    {
        private readonly System.Text.StringBuilder _pending = new();
        public List<string> Errors { get; } = [];
        public override void Write(string? message) => _pending.Append(message);
        public override void WriteLine(string? message)
        {
            _pending.Append(message);
            Errors.Add(_pending.ToString());
            _pending.Clear();
        }
    }

    private static System.Windows.Media.Imaging.BitmapSource CreatePrivacyBitmap(int width, int height)
    {
        var stride = width * 4;
        var pixels = new byte[stride * height];
        for (var y = 0; y < height; y++)
        for (var x = 0; x < width; x++)
        {
            var value = (byte)(((x / 8 + y / 8) & 1) == 0 ? 18 : 238);
            var offset = y * stride + x * 4;
            pixels[offset] = value;
            pixels[offset + 1] = value;
            pixels[offset + 2] = value;
            pixels[offset + 3] = 255;
        }
        var bitmap = System.Windows.Media.Imaging.BitmapSource.Create(width, height, 96, 96, PixelFormats.Bgra32, null, pixels, stride);
        bitmap.Freeze();
        return bitmap;
    }

    private static byte[] PixelAt(System.Windows.Media.Imaging.BitmapSource bitmap, int x, int y)
    {
        var converted = new System.Windows.Media.Imaging.FormatConvertedBitmap(bitmap, System.Windows.Media.PixelFormats.Bgra32, null, 0);
        var pixel = new byte[4];
        converted.CopyPixels(new Int32Rect(x, y, 1, 1), pixel, 4, 0);
        return pixel;
    }

    private static bool HasLightPixel(System.Windows.Media.Imaging.BitmapSource bitmap, int x, int y, int width, int height)
    {
        var converted = new System.Windows.Media.Imaging.FormatConvertedBitmap(bitmap, System.Windows.Media.PixelFormats.Bgra32, null, 0);
        var pixels = new byte[width * height * 4];
        converted.CopyPixels(new Int32Rect(x, y, width, height), pixels, width * 4, 0);
        for (var i = 0; i < pixels.Length; i += 4)
            if (pixels[i] > 210 && pixels[i + 1] > 210 && pixels[i + 2] > 210 && pixels[i + 3] == 255) return true;
        return false;
    }
}
