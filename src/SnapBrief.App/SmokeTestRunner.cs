using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Text.Json;
using System.Windows;
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
            AnnotationColor = "#FF4D4F", AnnotationThickness = 9, AnnotationShape = "ellipse", AnnotationFill = "translucent",
            SaveFormat = "jpeg", JpegQuality = 73, SaveDirectory = root, Language = "en",
            PackageSaveDirectory = Path.Combine(root, "packages"), PackageCreateSubfolder = false,
            Theme = "dark", AccentId = "violet", OnboardingVersion = OnboardingWindow.CurrentVersion
        };
        customSettings.Save(customSettingsPath);
        var restoredSettings = HotkeySettings.Load(customSettingsPath);
        if (restoredSettings != customSettings || restoredSettings.FullscreenSaveGesture.VirtualKey != 44 ||
            restoredSettings.OnboardingVersion != OnboardingWindow.CurrentVersion)
            throw new InvalidOperationException("Local capture preferences did not survive a settings round trip.");
        // The wizard is shown once per version: never seen (no file, or an older version) opens it,
        // the current version does not, and a demo run never does.
        if (!OnboardingWindow.ShouldShowOnboarding(false, HotkeySettings.Default, false) ||
            !OnboardingWindow.ShouldShowOnboarding(true, HotkeySettings.Default, false) ||
            OnboardingWindow.ShouldShowOnboarding(true, restoredSettings, false) ||
            OnboardingWindow.ShouldShowOnboarding(false, HotkeySettings.Default, true))
            throw new InvalidOperationException("The first run wizard is shown once per version, and never in a demo run.");
        if (OnboardingWindow.LanguageForCulture("uk") != "ru" || OnboardingWindow.LanguageForCulture("be") != "ru" ||
            OnboardingWindow.LanguageForCulture("ru") != "ru" || OnboardingWindow.LanguageForCulture("es") != "en")
            throw new InvalidOperationException("The suggested language must follow the system locale.");
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
            .Select(accent => ThemeService.Load(accent).Keys.Cast<object>().Select(key => key.ToString()!).OrderBy(key => key, StringComparer.Ordinal).ToArray())
            .ToArray();
        if (accentKeys.Any(keys => !keys.SequenceEqual(accentKeys[0])))
            throw new InvalidOperationException("The accent dictionaries must all define the same keys.");
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
        var onboarding = WithoutBindingErrors("The onboarding window", () =>
        {
            var window = OnboardingWindow.RunOnboardingProbe(restoredSettings);
            ResolveTriggerBindings(window);
            return window;
        });
        if (onboarding.Step != 0 || onboarding.SelectedLanguage != "ru" ||
            onboarding.Step1.Visibility != Visibility.Visible || onboarding.Step4.Visibility != Visibility.Collapsed)
            throw new InvalidOperationException("The wizard must come back to its first step after the probe.");
        if (onboarding.HintKeyText.Text != HotkeySettings.Find(restoredSettings.CaptureId).Label ||
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
            ("SnapBrief — Лента снимков", "SnapBrief — Capture strip")
        })
            if (UiLanguage.Text(russian, "en") != english || UiLanguage.Text(english, "ru") != russian)
                throw new InvalidOperationException($"Settings language switching failed for \"{russian}\".");
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
            capture.Annotations.Add(new AnnotationItem
            {
                Kind = i == 2 ? EditorTool.Conceal : i == 1 ? EditorTool.Rectangle : EditorTool.Arrow,
                Points = [new Point(1050, 650), new Point(1520, 880)],
                Note = annotationNotes[i],
                Color = Color.FromRgb(49, 92, 245),
                Thickness = 6
            });
            if (i == 2)
            {
                capture.Annotations.Add(new AnnotationItem
                {
                    Kind = EditorTool.Blur,
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

        Controls.AnnotationCanvas.VerifyBlurPreview(captures[0].Image);
        Controls.AnnotationCanvas.VerifyHoverManipulation(captures[0].Image);
        var preview = WithoutBindingErrors("The preview window", () =>
        {
            var window = CapturePreviewWindow.RunPreviewProbe(captures[0]);
            ResolveTriggerBindings(window);
            return window;
        });
        // The probe returns the window because its own checks read it; nothing reads it here.
        preview.Close();
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
        var redactionLabelHasLightInk = HasLightPixel(decoded[2], 1048, 48 + 615, 70, 35);
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
        var success = paths.Count == 3
            && preparedFilesOnDisk
            && decoded.All(bitmap => bitmap.PixelWidth == 1920 && bitmap.PixelHeight == 1128)
            && sourceCorner.SequenceEqual(exportedCorner)
            && redactionPixel[3] == 255 && redactionPixel[0] < 8 && redactionPixel[1] < 8 && redactionPixel[2] < 8
            && !sourceBlurPixel.SequenceEqual(exportedBlurPixel)
            && redactionLabelHasLightInk
            && prepared.Manifest.PromptText.Contains("Увеличить кнопку", StringComparison.Ordinal)
            && prepared.Manifest.PromptText.Contains("Снимок C", StringComparison.Ordinal)
            && prepared.Manifest.PromptText.Contains("C1: Уточнить подпись", StringComparison.Ordinal)
            && prepared.Manifest.NoteCount == 5
            && sentFlagPersisted
            && translucentOvalExported
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
