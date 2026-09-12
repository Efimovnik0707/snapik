using System;
using System.Collections.Generic;
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
            RememberRegion = true, CaptureCursor = true, ShowNotifications = false, StackTopmost = false,
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
        var settingsWindow = new HotkeySettingsWindow(restoredSettings);
        UiLanguage.Apply(settingsWindow, "en");
        settingsWindow.Measure(new Size(530, 480));
        settingsWindow.Arrange(new Rect(0, 0, 530, 480));
        UiLanguage.Apply(settingsWindow, "ru");
        if (UiLanguage.Text("Настройки", "en") != "Settings" || UiLanguage.Text("Settings", "ru") != "Настройки")
            throw new InvalidOperationException("Settings language switching failed.");
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
        CapturePreviewWindow.RunPreviewProbe(captures[0]);
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
        var decoded = paths.Select(SessionWorkspace.LoadBitmap).ToArray();
        var sourceFirst = captures[0].Image;
        var sourceCorner = PixelAt(sourceFirst, sourceFirst.PixelWidth - 1, sourceFirst.PixelHeight - 1);
        var exportedCorner = PixelAt(decoded[0], decoded[0].PixelWidth - 1, decoded[0].PixelHeight - 1);
        var redactionPixel = PixelAt(decoded[2], 1250, 48 + 760);
        var sourceBlurPixel = PixelAt(captures[2].Image, 1010, 700);
        var exportedBlurPixel = PixelAt(decoded[2], 1010, 48 + 700);
        var redactionLabelHasLightInk = HasLightPixel(decoded[2], 1048, 48 + 615, 70, 35);
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
            && paths.All(File.Exists)
            && decoded.All(bitmap => bitmap.PixelWidth == 1920 && bitmap.PixelHeight == 1128)
            && sourceCorner.SequenceEqual(exportedCorner)
            && redactionPixel[3] == 255 && redactionPixel[0] < 8 && redactionPixel[1] < 8 && redactionPixel[2] < 8
            && !sourceBlurPixel.SequenceEqual(exportedBlurPixel)
            && redactionLabelHasLightInk
            && prepared.Manifest.PromptText.Contains("Увеличить кнопку", StringComparison.Ordinal)
            && prepared.Manifest.PromptText.Contains("Снимок C", StringComparison.Ordinal)
            && prepared.Manifest.PromptText.Contains("C1: Уточнить подпись", StringComparison.Ordinal)
            && prepared.Manifest.NoteCount == 5
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
