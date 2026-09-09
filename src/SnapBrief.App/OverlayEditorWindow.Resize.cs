using System;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using SnapBrief.App.Controls;
using SnapBrief.Core.Editing;
using SnapBrief.Core.Models;

namespace SnapBrief.App;

public partial class OverlayEditorWindow
{
    private readonly Thumb[] _captureHandles = new Thumb[4];
    private readonly Border _resizeOutline = new()
    {
        BorderBrush = new SolidColorBrush(Color.FromRgb(47, 140, 255)),
        BorderThickness = new Thickness(2), IsHitTestVisible = false,
        Visibility = Visibility.Collapsed
    };
    private BitmapSource? _resizeSource;
    private Rect _resizeSourceRect;
    private Rect _resizeOriginalRect;
    private int _captureResizeCorner = -1;

    internal static async Task RunCaptureResizeProbeAsync(SessionWorkspace workspace, CaptureItem source)
    {
        var frame = new DesktopFrame(source.Image, 0, 0, source.Image.PixelWidth, source.Image.PixelHeight);
        var window = new OverlayEditorWindow(workspace, frame, 0, source) { Width = 1920, Height = 1080 };
        window.Measure(new Size(1920, 1080));
        window.Arrange(new Rect(0, 0, 1920, 1080));
        window._cropRect = new Rect(0, 0, 1920, 1080);
        window.SetupEditor();
        if (window._captureHandles.Any(handle => handle.Visibility != Visibility.Visible || handle.Width < 20))
            throw new InvalidOperationException("Capture corner handles are missing.");
        var original = window._capture!.Annotations[0].Points[0];
        var id = window._capture.Annotations[0].Id;
        var note = window._capture.Annotations[0].Note;
        await window.ApplyCaptureResizeAsync(new Rect(100, 50, 1700, 950));
        if (window._capture.Image.PixelWidth != 1700 || window._capture.Image.PixelHeight != 950 ||
            (window._capture.Annotations[0].Points[0] - new Point(original.X - 100, original.Y - 50)).Length > .01 ||
            window._capture.Annotations[0].Id != id || window._capture.Annotations[0].Note != note)
            throw new InvalidOperationException("Capture resize lost dimensions, annotation position, identity or note.");
        window.OnUndoClick(window, new RoutedEventArgs());
        if (window._capture.Image.PixelWidth != 1920 || (window._capture.Annotations[0].Points[0] - original).Length > .01)
            throw new InvalidOperationException("Capture resize undo failed.");
        window.OnRedoClick(window, new RoutedEventArgs());
        if (window._capture.Image.PixelWidth != 1700) throw new InvalidOperationException("Capture resize redo failed.");
        await window.ApplyCaptureResizeAsync(new Rect(0, 0, 1920, 1080));
        if (window._capture.Image.PixelWidth != 1920 || (window._capture.Annotations[0].Points[0] - original).Length > .01)
            throw new InvalidOperationException("Capture expansion failed.");
        window.DeleteCreatedSourcesExcept(null);
    }
    private void InitializeCaptureHandles()
    {
        CaptureHandleLayer.Children.Add(_resizeOutline);
        for (var i = 0; i < 4; i++)
        {
            var corner = i;
            var visual = new FrameworkElementFactory(typeof(Border));
            visual.SetValue(WidthProperty, 8d);
            visual.SetValue(HeightProperty, 8d);
            visual.SetValue(Border.BackgroundProperty, Brushes.White);
            visual.SetValue(Border.BorderBrushProperty, _resizeOutline.BorderBrush);
            visual.SetValue(Border.BorderThicknessProperty, new Thickness(1.5));
            visual.SetValue(Border.CornerRadiusProperty, new CornerRadius(2));
            var hitArea = new FrameworkElementFactory(typeof(Grid));
            hitArea.SetValue(Panel.BackgroundProperty, Brushes.Transparent);
            hitArea.AppendChild(visual);
            var handle = new Thumb
            {
                Width = 22, Height = 22, Visibility = Visibility.Collapsed,
                Cursor = i is 0 or 2 ? Cursors.SizeNWSE : Cursors.SizeNESW,
                Template = new ControlTemplate(typeof(Thumb)) { VisualTree = hitArea },
                ToolTip = "Изменить границы снимка"
            };
            System.Windows.Automation.AutomationProperties.SetName(handle, $"Угол снимка {i + 1}");
            handle.DragStarted += (_, _) =>
            {
                if (_capture is null || _busyCrop) { handle.CancelDrag(); return; }
                _captureResizeCorner = corner;
                _resizeOriginalRect = _cropRect;
                _resizeOutline.Visibility = Visibility.Visible;
                UpdateCaptureHandles();
            };
            handle.DragDelta += (_, _) =>
            {
                if (_captureResizeCorner < 0) return;
                _cropRect = ResizeGeometry.Resize(_resizeOriginalRect, corner, Mouse.GetPosition(this), _resizeSourceRect, 12);
                UpdateShade();
                UpdateCaptureHandles();
            };
            handle.DragCompleted += OnCaptureResizeCompleted;
            _captureHandles[i] = handle;
            CaptureHandleLayer.Children.Add(handle);
        }
    }

    private void UpdateCaptureHandles()
    {
        if (_capture is null) return;
        if (_resizeSource is null)
        {
            // Expansion can reveal only pixels already captured, never a newer desktop.
            _resizeSource = _isNew ? _frame.Image : _capture.Image;
            _resizeSourceRect = _isNew ? new Rect(0, 0, ActualWidth, ActualHeight) : _cropRect;
        }
        var corners = ResizeGeometry.Corners(_cropRect);
        for (var i = 0; i < _captureHandles.Length; i++)
        {
            var handle = _captureHandles[i];
            handle.Visibility = Visibility.Visible;
            Canvas.SetLeft(handle, Math.Clamp(corners[i].X - 11, 0, Math.Max(0, ActualWidth - 22)));
            Canvas.SetTop(handle, Math.Clamp(corners[i].Y - 11, 0, Math.Max(0, ActualHeight - 22)));
        }
        Canvas.SetLeft(_resizeOutline, _cropRect.Left);
        Canvas.SetTop(_resizeOutline, _cropRect.Top);
        _resizeOutline.Width = _cropRect.Width;
        _resizeOutline.Height = _cropRect.Height;
    }

    private async void OnCaptureResizeCompleted(object sender, DragCompletedEventArgs e)
    {
        if (_captureResizeCorner < 0 || _capture is null || _resizeSource is null) return;
        _captureResizeCorner = -1;
        _resizeOutline.Visibility = Visibility.Collapsed;
        var requestedRect = _cropRect;
        _cropRect = _resizeOriginalRect;
        if (e.Canceled || requestedRect == _resizeOriginalRect)
        {
            UpdateCropVisual();
            return;
        }
        await ApplyCaptureResizeAsync(requestedRect);
    }
    private async Task ApplyCaptureResizeAsync(Rect requestedRect)
    {
        if (_capture is null || _resizeSource is null) return;
        _busyCrop = true;
        var before = SnapshotState();
        try
        {
            var sx = _resizeSource.PixelWidth / _resizeSourceRect.Width;
            var sy = _resizeSource.PixelHeight / _resizeSourceRect.Height;
            var left = Math.Clamp((int)Math.Round((requestedRect.Left - _resizeSourceRect.Left) * sx), 0, _resizeSource.PixelWidth - 1);
            var top = Math.Clamp((int)Math.Round((requestedRect.Top - _resizeSourceRect.Top) * sy), 0, _resizeSource.PixelHeight - 1);
            var right = Math.Clamp((int)Math.Round((requestedRect.Right - _resizeSourceRect.Left) * sx), left + 1, _resizeSource.PixelWidth);
            var bottom = Math.Clamp((int)Math.Round((requestedRect.Bottom - _resizeSourceRect.Top) * sy), top + 1, _resizeSource.PixelHeight);
            var pixels = new Int32Rect(left, top, right - left, bottom - top);
            var image = new CroppedBitmap(_resizeSource, pixels);
            image.Freeze();
            var path = await _workspace.SaveDerivedImageAsync(image);
            _createdSourcePaths.Add(path);
            if (_closed) { DeleteCreatedSourcesExcept(null); return; }

            var inSource = _capture.DeepClone();
            var sourceOffset = new Vector((_cropRect.Left - _resizeSourceRect.Left) * sx, (_cropRect.Top - _resizeSourceRect.Top) * sy);
            var scaleX = _cropRect.Width * sx / _capture.Image.PixelWidth;
            var scaleY = _cropRect.Height * sy / _capture.Image.PixelHeight;
            foreach (var mark in inSource.Annotations)
                foreach (var segment in new[] { mark.Points }.Concat(mark.AdditionalPathSegments))
                    for (var i = 0; i < segment.Count; i++)
                        segment[i] = new Point(segment[i].X * scaleX, segment[i].Y * scaleY) + sourceOffset;
            inSource.Image = _resizeSource;
            var normalized = new NormalizedRect((double)left / _resizeSource.PixelWidth, (double)top / _resizeSource.PixelHeight,
                (double)pixels.Width / _resizeSource.PixelWidth, (double)pixels.Height / _resizeSource.PixelHeight);
            var result = CaptureCropper.Crop(inSource.ToCore(), normalized, path, pixels.Width, pixels.Height);
            var updated = CaptureItem.FromCore(result.CroppedCapture, image);
            updated.DisplayLabel = _capture.DisplayLabel;
            updated.IsSelected = _capture.IsSelected;
            _capture = updated;
            _cropRect = new Rect(_resizeSourceRect.Left + left / sx, _resizeSourceRect.Top + top / sy, pixels.Width / sx, pixels.Height / sy);
            _undo.Push(before);
            _redo.Clear();
            SetupEditor();
            RebuildChips();
            UpdateShade();
        }
        catch (Exception ex)
        {
            RestoreState(before);
            Hint.Visibility = Visibility.Visible;
            ((TextBlock)Hint.Child).Text = $"Не удалось изменить границы снимка: {ex.Message}";
        }
        finally { _busyCrop = false; }
    }
}
