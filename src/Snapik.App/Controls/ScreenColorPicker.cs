using System;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;

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
        var overlay = new Window
        {
            WindowStyle = WindowStyle.None, AllowsTransparency = true, ShowInTaskbar = false,
            Topmost = true, ResizeMode = ResizeMode.NoResize, Cursor = Cursors.Cross,
            Left = SystemParameters.VirtualScreenLeft, Top = SystemParameters.VirtualScreenTop,
            Width = SystemParameters.VirtualScreenWidth, Height = SystemParameters.VirtualScreenHeight,
            // Not Transparent: a window with nothing in it takes no clicks, and this one is here to
            // take them. One percent of black is invisible and still hit-testable.
            Background = new SolidColorBrush(Color.FromArgb(1, 0, 0, 0)),
            Owner = owner
        };
        overlay.MouseMove += (_, _) => { if (screen.ColorUnderCursor() is { } colour) preview(colour); };
        overlay.MouseLeftButtonUp += (_, _) => { picked = screen.ColorUnderCursor(); overlay.Close(); };
        overlay.KeyDown += (_, key) => { if (key.Key == Key.Escape) { picked = null; overlay.Close(); } };
        overlay.Loaded += (_, _) => { overlay.Activate(); Mouse.Capture(overlay, CaptureMode.SubTree); };
        overlay.ShowDialog();
        return picked;
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

        internal Color? ColorUnderCursor()
        {
            if (!GetCursorPos(out var point)) return null;
            // MONITOR_DEFAULTTONULL: the corners of the virtual screen that no monitor covers hold no
            // colour, and the preview keeps what it had.
            if (MonitorFromPoint(point, 0) == IntPtr.Zero) return null;
            int x = point.X - _left, y = point.Y - _top;
            if (x < 0 || y < 0 || x >= _bitmap.Width || y >= _bitmap.Height) return null;
            var pixel = _bitmap.GetPixel(x, y);
            return Color.FromRgb(pixel.R, pixel.G, pixel.B);
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
