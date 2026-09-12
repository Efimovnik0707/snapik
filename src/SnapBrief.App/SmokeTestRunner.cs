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
        CaptureFeedbackSound.VerifyWaveHeaders();
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
            AutoSaveCaptures = true, PlaySounds = false,
            CaptureEnabled = false, FullscreenSaveEnabled = true, FullscreenSaveId = "custom:4:44",
            RememberRegion = true, CaptureCursor = true, ShowNotifications = false, StackTopmost = false, ClearStackAfterPaste = true,
            AnnotationColor = "#FF4D4F", AnnotationThickness = 9,
            SaveFormat = "jpeg", JpegQuality = 73, SaveDirectory = root, Language = "en"
        };
        customSettings.Save(customSettingsPath);
        var restoredSettings = HotkeySettings.Load(customSettingsPath);
        if (restoredSettings != customSettings || restoredSettings.FullscreenSaveGesture.VirtualKey != 44)
            throw new InvalidOperationException("Local capture preferences did not survive a settings round trip.");
        if (OverlayEditorWindow.ParseAnnotationColor(restoredSettings.AnnotationColor) != Color.FromRgb(255, 77, 79) ||
            OverlayEditorWindow.ParseAnnotationColor("not a colour") != OverlayEditorWindow.DefaultAnnotationColor)
            throw new InvalidOperationException("Stored annotation colour must be read back, an invalid one must fall back to the default.");
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
        if (settingsWindow.QualitySlider.Visibility != Visibility.Visible)
            throw new InvalidOperationException("JPEG quality must be visible while the JPEG format is selected.");
        settingsWindow.FormatBox.SelectedIndex = 0;
        if (settingsWindow.QualitySlider.Visibility != Visibility.Collapsed)
            throw new InvalidOperationException("JPEG quality must be hidden while the PNG format is selected.");
        if ((Controls.ButtonChrome.GetHoverBackground(settingsWindow.SaveButton) as SolidColorBrush)?.Color != ((SolidColorBrush)settingsWindow.FindResource("AccentHoverBrush")).Color ||
            (Controls.ButtonChrome.GetPressedBackground(settingsWindow.SaveButton) as SolidColorBrush)?.Color != ((SolidColorBrush)settingsWindow.FindResource("AccentPressedBrush")).Color)
            throw new InvalidOperationException("The primary button must keep the accent while hovered and pressed.");
        foreach (var (russian, english) in new[]
        {
            ("Настройки", "Settings"), ("Настройки клавиш", "Shortcut settings"), ("Сделать скриншот", "Take a screenshot"),
            ("Скриншот всего экрана в папку", "Save the whole screen to a folder"), ("Предлагать ту же область, что в прошлый раз", "Offer the same area as last time"),
            ("Показывать курсор мыши на скриншоте", "Show the mouse pointer in the screenshot"), ("Звуки", "Sounds"),
            ("Показывать уведомления", "Show notifications"), ("Закрыть", "Close")
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

        Controls.AnnotationCanvas.VerifyBlurPreview(captures[0].Image);
        Controls.AnnotationCanvas.VerifyHoverManipulation(captures[0].Image);
        WithoutBindingErrors("The preview window", () => ResolveTriggerBindings(CapturePreviewWindow.RunPreviewProbe(captures[0])));
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
        var noteProbe = OverlayEditorWindow.RunNoteAffordanceProbe(captures[0]);
        var noteProbeCore = noteProbe.ToCore();
        var noteProbeLabel = SnapBrief.Core.Exporting.CaptureLabels.ForNotedAnnotations("A", noteProbeCore).SingleOrDefault();
        await using var noteProbePng = new MemoryStream();
        await new WpfExportImageRenderer().RenderAsync(noteProbeCore,
            new SnapBrief.Core.Exporting.ExportImageContext("A", 0, Path.GetFullPath(Path.Combine(workspace.SessionDirectory, noteProbe.SourcePath))),
            noteProbePng, default);
        var paths = prepared.GetImagePathsInOrder();
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
            && freshSessionPersisted;
        success = success
            && noteProbe.Annotations.Single(a => a.Kind == EditorTool.Comment).Note == "Контекстная заметка"
            && noteProbeLabel.DisplayLabel == "A1"
            && noteProbePng.Length > 0;
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
