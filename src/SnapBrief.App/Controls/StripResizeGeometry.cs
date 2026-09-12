using System;
using System.Windows;

namespace SnapBrief.App.Controls;

/// <summary>
/// The width of the strip, dragged by its left edge. The right edge is fixed while the drag lasts,
/// so the card grows into the screen instead of walking away from it. Sizes are window sizes: the
/// visible card is 20 px narrower, that margin carries the shadow.
/// </summary>
internal static class StripResizeGeometry
{
    internal const double MinimumWidth = 200;
    internal const double MaximumWidth = 380;
    internal const double DefaultWidth = 208;

    /// <summary>A width from the settings file: out of range is clamped, nonsense falls back to the default.</summary>
    internal static double ClampWidth(double width) =>
        double.IsFinite(width) ? Math.Clamp(width, MinimumWidth, MaximumWidth) : DefaultWidth;

    /// <summary>
    /// The new left edge and width for a drag of <paramref name="delta"/> pixels. The strip never
    /// crosses <paramref name="leftLimit"/>, the left edge of the working area it sits in.
    /// </summary>
    internal static (double Left, double Width) Resize(double right, double width, double delta, double leftLimit)
    {
        var allowed = Math.Clamp(right - leftLimit, MinimumWidth, MaximumWidth);
        var resized = Math.Clamp(width - delta, MinimumWidth, allowed);
        return (right - resized, resized);
    }

    /// <summary>
    /// A working area read from the monitor, in pixels, in the units the window is placed in. The
    /// strip may live on a second monitor with a scale of its own, and the placement and the drag
    /// limit must both come from that one, not from the primary screen.
    /// </summary>
    internal static Rect ToDeviceIndependent(Rect area, double dpiScaleX, double dpiScaleY)
    {
        var scaleX = dpiScaleX > 0 ? dpiScaleX : 1;
        var scaleY = dpiScaleY > 0 ? dpiScaleY : 1;
        return new Rect(area.X / scaleX, area.Y / scaleY, area.Width / scaleX, area.Height / scaleY);
    }
}
