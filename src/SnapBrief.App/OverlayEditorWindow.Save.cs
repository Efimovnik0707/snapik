using System;
using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media.Imaging;
using Microsoft.Win32;
using SnapBrief.Core.Exporting;

namespace SnapBrief.App;

public partial class OverlayEditorWindow
{
    private async void OnSaveImageClick(object sender, RoutedEventArgs e)
    {
        if (_capture is null || _busyCrop || _captureResizeCorner >= 0 || Surface.IsMouseCaptured) return;
        _busyCrop = true;
        var wasTopmost = Topmost;
        try
        {
            var settings = _workspace.Preferences;
            var dialog = new SaveFileDialog
            {
                Title = UiLanguage.Text("Сохранить на компьютер (Ctrl+S)"),
                Filter = "PNG (*.png)|*.png|JPEG (*.jpg;*.jpeg)|*.jpg;*.jpeg",
                FilterIndex = settings.SaveFormat == "jpeg" ? 2 : 1,
                DefaultExt = settings.SaveFormat == "jpeg" ? ".jpg" : ".png",
                FileName = Path.GetFileNameWithoutExtension(LocalImageSave.NewPath(settings)),
                InitialDirectory = Directory.Exists(settings.SaveDirectory) ? settings.SaveDirectory : Environment.GetFolderPath(Environment.SpecialFolder.MyPictures),
                AddExtension = true, OverwritePrompt = true
            };
            Topmost = false;
            if (dialog.ShowDialog(this) != true) return;
            var extension = Path.GetExtension(dialog.FileName).ToLowerInvariant();
            var format = extension is ".jpg" or ".jpeg" ? "jpeg" : "png";
            if (extension is not (".png" or ".jpg" or ".jpeg")) throw new InvalidOperationException("Выберите PNG или JPEG.");
            await LocalImageSave.WriteAsync(Surface.RenderAnnotated(), dialog.FileName, format, settings.JpegQuality, true);
            RememberCurrentRegion();
            if (Application.Current.MainWindow is EdgeStackWindow stack) stack.NotifySaved();
        }
        catch (Exception ex) { Hint.Visibility = Visibility.Visible; ((TextBlock)Hint.Child).Text = ex.Message; }
        finally { _busyCrop = false; if (!_closed) { Topmost = wasTopmost; Activate(); } }
    }

    private sealed record SavedRegion(int Left, int Top, int Width, int Height, double X, double Y, double W, double H);

    private void RememberCurrentRegion()
    {
        if (!_isNew || !_workspace.Preferences.RememberRegion || _cropRect.IsEmpty || ActualWidth <= 0 || ActualHeight <= 0) return;
        try
        {
            var region = new SavedRegion(_frame.Left, _frame.Top, _frame.PixelWidth, _frame.PixelHeight,
                _cropRect.X / ActualWidth, _cropRect.Y / ActualHeight, _cropRect.Width / ActualWidth, _cropRect.Height / ActualHeight);
            Directory.CreateDirectory(Path.GetDirectoryName(_workspace.RegionPath)!);
            File.WriteAllText(_workspace.RegionPath, JsonSerializer.Serialize(region));
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    private async void RestoreLastRegion()
    {
        if (!_workspace.Preferences.RememberRegion || !File.Exists(_workspace.RegionPath)) return;
        _busyCrop = true;
        try
        {
            var r = JsonSerializer.Deserialize<SavedRegion>(File.ReadAllText(_workspace.RegionPath));
            if (r is null || r.Left != _frame.Left || r.Top != _frame.Top || r.Width != _frame.PixelWidth || r.Height != _frame.PixelHeight ||
                !double.IsFinite(r.X + r.Y + r.W + r.H) || r.X < 0 || r.Y < 0 || r.W <= 0 || r.H <= 0 || r.X + r.W > 1.00001 || r.Y + r.H > 1.00001) return;
            var x = Math.Clamp((int)Math.Round(r.X * r.Width), 0, r.Width - 1);
            var y = Math.Clamp((int)Math.Round(r.Y * r.Height), 0, r.Height - 1);
            var pixels = new Int32Rect(x, y, Math.Clamp((int)Math.Round(r.W * r.Width), 1, r.Width - x), Math.Clamp((int)Math.Round(r.H * r.Height), 1, r.Height - y));
            var image = new CroppedBitmap(_frame.Image, pixels); image.Freeze();
            _capture = await _workspace.AddImageAsync(image);
            _createdSourcePaths.Add(_capture.SourcePath);
            if (_closed) { DeleteCreatedSourcesExcept(null); return; }
            _cropRect = new Rect(r.X * ActualWidth, r.Y * ActualHeight, r.W * ActualWidth, r.H * ActualHeight);
            _capture.DisplayLabel = CaptureLabels.ForIndex(_captureIndex);
            SetupEditor();
        }
        catch (Exception) { _cropRect = Rect.Empty; UpdateCropVisual(); }
        finally { _busyCrop = false; }
    }
}

