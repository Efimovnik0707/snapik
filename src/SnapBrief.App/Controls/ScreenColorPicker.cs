using System;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;

namespace SnapBrief.App.Controls;

/// <summary>
/// The eyedropper: a colour taken from whatever is on the screen, SnapBrief included. A transparent
/// window is laid over every monitor to hold the pointer and the keyboard, and the pixel under the
/// cursor is read straight out of the screen device context. The coordinates are the physical
/// pixels the cursor is reported in, so nothing has to be scaled on a mixed-DPI desktop.
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
        overlay.MouseMove += (_, _) => { if (ColorUnderCursor() is { } colour) preview(colour); };
        overlay.MouseLeftButtonUp += (_, _) => { picked = ColorUnderCursor(); overlay.Close(); };
        overlay.KeyDown += (_, key) => { if (key.Key == Key.Escape) { picked = null; overlay.Close(); } };
        overlay.Loaded += (_, _) => { overlay.Activate(); Mouse.Capture(overlay, CaptureMode.SubTree); };
        overlay.ShowDialog();
        return picked;
    }

    internal static Color? ColorUnderCursor() => GetCursorPos(out var point) ? ColorAt(point.X, point.Y) : null;

    private static Color? ColorAt(int x, int y)
    {
        var screen = GetDC(IntPtr.Zero);
        if (screen == IntPtr.Zero) return null;
        try
        {
            var value = GetPixel(screen, x, y);
            // CLR_INVALID: the point is outside every monitor.
            if (value == 0xFFFFFFFF) return null;
            return Color.FromRgb((byte)(value & 0xFF), (byte)((value >> 8) & 0xFF), (byte)((value >> 16) & 0xFF));
        }
        finally { ReleaseDC(IntPtr.Zero, screen); }
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
    private static extern IntPtr GetDC(IntPtr window);

    [DllImport("user32.dll")]
    private static extern int ReleaseDC(IntPtr window, IntPtr deviceContext);

    [DllImport("gdi32.dll")]
    private static extern uint GetPixel(IntPtr deviceContext, int x, int y);
}
