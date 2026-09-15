using System;
using System.Runtime.InteropServices;

namespace Snapik.App;

/// <summary>
/// The rounded corners of a borderless window, asked of the desktop manager instead of drawn by the
/// window itself. Two contours, one from the window and one from the system, are what the round of
/// reports complained about.
/// </summary>
internal static class DwmWindowCorners
{
    private const int DwmwaWindowCornerPreference = 33;
    private const int DwmwcpRound = 2;

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);

    /// <summary>
    /// Asks the desktop manager to round the corners of the window. The build number is never
    /// checked: on Windows 10 the attribute answers E_INVALIDARG and the window stays square, which
    /// is exactly what it should do there.
    /// </summary>
    internal static bool Round(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero) return false;
        try
        {
            var preference = DwmwcpRound;
            return DwmSetWindowAttribute(hwnd, DwmwaWindowCornerPreference, ref preference, sizeof(int)) == 0;
        }
        catch (Exception ex) when (ex is DllNotFoundException or EntryPointNotFoundException)
        {
            return false;
        }
    }
}

/// <summary>
/// The scale of a monitor picked by a point on it. A window is placed before it has been shown, so
/// the scale of the monitor it is going to is read here and not off the window, which still belongs
/// to the monitor it was created on.
/// </summary>
internal static class MonitorMetrics
{
    private const int MonitorDefaultToNearest = 2;
    private const int MdtEffectiveDpi = 0;

    [DllImport("user32.dll")]
    private static extern IntPtr MonitorFromPoint(Point point, int flags);

    [DllImport("Shcore.dll")]
    private static extern int GetDpiForMonitor(IntPtr monitor, int type, out uint dpiX, out uint dpiY);

    [StructLayout(LayoutKind.Sequential)]
    private struct Point
    {
        public int X;
        public int Y;
    }

    /// <summary>The scale of the monitor the point lies on; 1.0 whenever the system does not answer.</summary>
    internal static double Scale(int x, int y)
    {
        try
        {
            var monitor = MonitorFromPoint(new Point { X = x, Y = y }, MonitorDefaultToNearest);
            if (monitor == IntPtr.Zero) return 1.0;
            return GetDpiForMonitor(monitor, MdtEffectiveDpi, out var dpiX, out _) == 0 && dpiX > 0 ? dpiX / 96.0 : 1.0;
        }
        catch (Exception ex) when (ex is DllNotFoundException or EntryPointNotFoundException)
        {
            return 1.0;
        }
    }
}
