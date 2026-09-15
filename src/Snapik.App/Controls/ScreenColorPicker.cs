using System;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace Snapik.App.Controls;

/// <summary>
/// The eyedropper: a colour taken from whatever is on the screen, Snapik included. A transparent
/// window is laid over every monitor to hold the pointer and the keyboard, and the pixel under the
/// cursor is read out of a copy of the screen taken before that window was shown. The coordinates
/// are the physical pixels the cursor is reported in, so nothing has to be scaled on a mixed-DPI
/// desktop.
/// </summary>
internal static class ScreenColorPicker
{
    /// <summary>
    /// Runs the picking until a click or Escape. The colour under the cursor is handed to
    /// <paramref name="preview"/> on every move; the return value is the colour that was clicked, or
    /// null if the picking was given up, in which case the caller puts back what it had.
    /// </summary>
    internal static Color? Pick(Window owner, Action<Color> preview)
    {
        Color? picked = null;
        // The pixel is read from a copy of the screen taken before the overlay is laid over it: the
        // overlay has to answer the clicks, a window answers them only where it is not fully
        // transparent, and the one percent of black that makes it hit-testable darkens every channel
        // read through it by one.
        using var screen = ScreenCopy.Take();
        var canvas = new Canvas();
        var loupe = new Loupe(screen.Frozen());
        canvas.Children.Add(loupe.Capsule);
        var overlay = new Window
        {
            WindowStyle = WindowStyle.None, AllowsTransparency = true, ShowInTaskbar = false,
            Topmost = true, ResizeMode = ResizeMode.NoResize, Cursor = Cursors.Cross,
            Left = SystemParameters.VirtualScreenLeft, Top = SystemParameters.VirtualScreenTop,
            Width = SystemParameters.VirtualScreenWidth, Height = SystemParameters.VirtualScreenHeight,
            // Not Transparent: a window with nothing in it takes no clicks, and this one is here to
            // take them. One percent of black is invisible and still hit-testable.
            Background = new SolidColorBrush(Color.FromArgb(1, 0, 0, 0)),
            Owner = owner,
            Content = canvas
        };
        // Two sources of coordinates on purpose: the loupe stands where the event says the pointer
        // is, in the device independent units of the window, and it shows the pixels GetCursorPos
        // reports, in the physical pixels of the copy. Mixing the two is what breaks a mixed-DPI
        // desktop, and the reading below is the same one the colour itself comes from.
        overlay.MouseMove += (_, moved) =>
        {
            if (screen.ReadCursor() is not { } reading) { loupe.Hide(); return; }
            preview(reading.Colour);
            loupe.ShowAt(moved.GetPosition(canvas), reading.Pixel, reading.Colour, screen.ToCanvasWorkArea(canvas));
        };
        overlay.MouseLeftButtonUp += (_, _) => { picked = screen.ColorUnderCursor(); overlay.Close(); };
        overlay.KeyDown += (_, key) => { if (key.Key == Key.Escape) { picked = null; overlay.Close(); } };
        overlay.Loaded += (_, _) => { overlay.Activate(); Mouse.Capture(overlay, CaptureMode.SubTree); };
        overlay.ShowDialog();
        return picked;
    }

    /// <summary>
    /// The capsule beside the pointer: sixteen pixels of the screen copy blown up eight times, a
    /// grid over them, the pixel under the cursor squared off in the middle, and its HEX underneath.
    /// </summary>
    private sealed class Loupe
    {
        // Sixteen pixels across a hundred and twenty eight: one pixel of the screen is eight of the
        // loupe, which is the magnification the task asks for and what makes the grid land on whole
        // device independent units.
        private const int SourcePixels = 16;
        private const double Magnification = 8;
        private const double Side = SourcePixels * Magnification;

        private readonly BitmapSource _source;
        private readonly Image _image = new() { Width = Side, Height = Side };
        private readonly TextBlock _hex = new()
        {
            FontSize = 12, Foreground = new SolidColorBrush(Color.FromRgb(0xDC, 0xE3, 0xED)),
            HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 6, 0, 0)
        };

        internal Loupe(BitmapSource source)
        {
            _source = source;
            RenderOptions.SetBitmapScalingMode(_image, BitmapScalingMode.NearestNeighbor);
            var glass = new Grid { Width = Side, Height = Side, ClipToBounds = true };
            glass.Children.Add(_image);
            glass.Children.Add(new System.Windows.Shapes.Path
            {
                Data = GridLines(), Stroke = new SolidColorBrush(Color.FromArgb(0x33, 0xFF, 0xFF, 0xFF)),
                StrokeThickness = 1, SnapsToDevicePixels = true
            });
            // The pixel that will be taken, outlined twice: white outside and black inside, so the
            // square is seen on a white page and on a black one alike.
            foreach (var marker in new[]
            {
                new System.Windows.Shapes.Rectangle { Width = Magnification, Height = Magnification, Stroke = Brushes.White, StrokeThickness = 2 },
                new System.Windows.Shapes.Rectangle { Width = Magnification, Height = Magnification, Stroke = Brushes.Black, StrokeThickness = 1 }
            })
            {
                marker.HorizontalAlignment = HorizontalAlignment.Center;
                marker.VerticalAlignment = VerticalAlignment.Center;
                glass.Children.Add(marker);
            }
            var stack = new StackPanel();
            stack.Children.Add(glass);
            stack.Children.Add(_hex);
            Capsule = new Border
            {
                Background = new SolidColorBrush(Color.FromArgb(0xE6, 0x17, 0x1A, 0x20)),
                CornerRadius = new CornerRadius(8), Padding = new Thickness(6),
                Visibility = Visibility.Collapsed, IsHitTestVisible = false,
                Child = stack
            };
        }

        internal Border Capsule { get; }

        internal void Hide() => Capsule.Visibility = Visibility.Collapsed;

        internal void ShowAt(Point pointer, Point pixel, Color colour, Rect workArea)
        {
            // At the very edge of the copy the window of sixteen pixels is pushed back inside it, so
            // the loupe shows real pixels instead of a torn rectangle; the middle then stands up to
            // eight pixels away from the cursor, which is the last row of the screen.
            var left = (int)Math.Clamp(pixel.X - SourcePixels / 2, 0, Math.Max(0, _source.PixelWidth - SourcePixels));
            var top = (int)Math.Clamp(pixel.Y - SourcePixels / 2, 0, Math.Max(0, _source.PixelHeight - SourcePixels));
            var window = new Int32Rect(left, top, Math.Min(SourcePixels, _source.PixelWidth), Math.Min(SourcePixels, _source.PixelHeight));
            var cropped = new CroppedBitmap(_source, window);
            cropped.Freeze();
            _image.Source = cropped;
            _hex.Text = $"#{colour.R:X2}{colour.G:X2}{colour.B:X2}";
            Capsule.Visibility = Visibility.Visible;
            Capsule.UpdateLayout();
            var size = new Size(Math.Max(Capsule.ActualWidth, Side), Math.Max(Capsule.ActualHeight, Side));
            // Twenty pixels down and to the right of the pointer, mirrored to the other side when
            // the capsule would leave the monitor the pointer stands on.
            const double gap = 20;
            var x = pointer.X + gap + size.Width > workArea.Right ? pointer.X - gap - size.Width : pointer.X + gap;
            var y = pointer.Y + gap + size.Height > workArea.Bottom ? pointer.Y - gap - size.Height : pointer.Y + gap;
            Canvas.SetLeft(Capsule, Math.Max(workArea.Left, x));
            Canvas.SetTop(Capsule, Math.Max(workArea.Top, y));
        }

        private static Geometry GridLines()
        {
            var geometry = new StreamGeometry();
            using (var context = geometry.Open())
                for (var step = 1; step < SourcePixels; step++)
                {
                    var at = step * Magnification;
                    context.BeginFigure(new Point(at, 0), false, false);
                    context.LineTo(new Point(at, Side), true, false);
                    context.BeginFigure(new Point(0, at), false, false);
                    context.LineTo(new Point(Side, at), true, false);
                }
            geometry.Freeze();
            return geometry;
        }
    }

    /// <summary>
    /// The whole virtual screen as it stood when the picking began, with the corner it starts at, so
    /// that the cursor position can be turned into a pixel of the copy.
    /// </summary>
    private sealed class ScreenCopy : IDisposable
    {
        private readonly System.Drawing.Bitmap _bitmap;
        private readonly int _left;
        private readonly int _top;

        private ScreenCopy(System.Drawing.Bitmap bitmap, int left, int top)
        {
            _bitmap = bitmap;
            _left = left;
            _top = top;
        }

        internal static ScreenCopy Take()
        {
            // SM_XVIRTUALSCREEN and its neighbours: the rectangle around every monitor, in the same
            // physical pixels the cursor is reported in.
            int left = GetSystemMetrics(76), top = GetSystemMetrics(77);
            int width = Math.Max(GetSystemMetrics(78), 1), height = Math.Max(GetSystemMetrics(79), 1);
            var bitmap = new System.Drawing.Bitmap(width, height, System.Drawing.Imaging.PixelFormat.Format32bppPArgb);
            using (var graphics = System.Drawing.Graphics.FromImage(bitmap))
                graphics.CopyFromScreen(left, top, 0, 0, new System.Drawing.Size(width, height), System.Drawing.CopyPixelOperation.SourceCopy);
            return new ScreenCopy(bitmap, left, top);
        }

        internal Color? ColorUnderCursor() => ReadCursor()?.Colour;

        /// <summary>
        /// The pixel the cursor stands on, in the coordinates of the copy, and its colour. Null where
        /// no monitor covers the cursor: the corners of the virtual screen hold no colour, and both
        /// the preview and the loupe keep what they had.
        /// </summary>
        internal (Point Pixel, Color Colour)? ReadCursor()
        {
            if (!GetCursorPos(out var point)) return null;
            // MONITOR_DEFAULTTONULL: see above.
            if (MonitorFromPoint(point, 0) == IntPtr.Zero) return null;
            int x = point.X - _left, y = point.Y - _top;
            if (x < 0 || y < 0 || x >= _bitmap.Width || y >= _bitmap.Height) return null;
            var pixel = _bitmap.GetPixel(x, y);
            return (new Point(x, y), Color.FromRgb(pixel.R, pixel.G, pixel.B));
        }

        /// <summary>
        /// The copy as one frozen picture, for the loupe: two hundred and fifty six GetPixel calls on
        /// every movement of the mouse are what a CroppedBitmap of this saves.
        /// </summary>
        internal BitmapSource Frozen()
        {
            var locked = _bitmap.LockBits(new System.Drawing.Rectangle(0, 0, _bitmap.Width, _bitmap.Height),
                System.Drawing.Imaging.ImageLockMode.ReadOnly, System.Drawing.Imaging.PixelFormat.Format32bppPArgb);
            try
            {
                var source = BitmapSource.Create(_bitmap.Width, _bitmap.Height, 96, 96, PixelFormats.Pbgra32, null,
                    locked.Scan0, locked.Stride * _bitmap.Height, locked.Stride);
                source.Freeze();
                return source;
            }
            finally { _bitmap.UnlockBits(locked); }
        }

        /// <summary>
        /// The working area of the monitor under the cursor, in the units the overlay lays its
        /// children out in. The copy spans every monitor in physical pixels and the overlay spans the
        /// same rectangle in device independent ones, so one ratio takes the working area across;
        /// on a desktop of mixed scales that ratio is an approximation, and it is only used to decide
        /// which side of the pointer the loupe stands on.
        /// </summary>
        internal Rect ToCanvasWorkArea(FrameworkElement canvas)
        {
            var work = System.Windows.Forms.Screen.FromPoint(System.Windows.Forms.Cursor.Position).WorkingArea;
            var scaleX = _bitmap.Width <= 0 ? 1 : canvas.ActualWidth / _bitmap.Width;
            var scaleY = _bitmap.Height <= 0 ? 1 : canvas.ActualHeight / _bitmap.Height;
            return new Rect((work.Left - _left) * scaleX, (work.Top - _top) * scaleY, work.Width * scaleX, work.Height * scaleY);
        }

        public void Dispose() => _bitmap.Dispose();
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT
    {
        public int X;
        public int Y;
    }

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetCursorPos(out POINT point);

    [DllImport("user32.dll")]
    private static extern int GetSystemMetrics(int index);

    [DllImport("user32.dll")]
    private static extern IntPtr MonitorFromPoint(POINT point, uint flags);
}
