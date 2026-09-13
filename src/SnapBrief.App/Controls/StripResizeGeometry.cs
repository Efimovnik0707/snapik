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

    // The height of the strip is the height of the capture list: the window lives on
    // SizeToContent="Height", and a height written to the window itself is overwritten by the next
    // layout pass. The card (78 px) and the overlap (48 px) stay as they are, the visible part of
    // the list is what grows.
    internal const double MinimumListHeight = 180;
    internal const double MaximumListHeight = 720;
    internal const double DefaultListHeight = 372;

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
    /// A list height from the settings file: out of range is clamped, nonsense falls back to the
    /// default. The working area is a ceiling of its own, so a height stored on a large monitor does
    /// not open a strip taller than the screen it comes back on.
    /// </summary>
    internal static double ClampListHeight(double height, double workHeight)
    {
        var ceiling = double.IsFinite(workHeight) && workHeight > 0
            ? Math.Max(MinimumListHeight, Math.Min(MaximumListHeight, workHeight))
            : MaximumListHeight;
        return double.IsFinite(height) ? Math.Clamp(height, MinimumListHeight, ceiling) : Math.Min(DefaultListHeight, ceiling);
    }

    /// <summary>
    /// The height of the capture list after a drag of <paramref name="delta"/> pixels downwards. The
    /// top edge stays where it was, so the strip grows down; <paramref name="chromeHeight"/> is
    /// everything of the window that is not the list (header, button, toast, paddings), and it keeps
    /// the bottom of the window inside <paramref name="workBottom"/>.
    /// </summary>
    internal static double ResizeListHeight(double listHeight, double delta, double chromeHeight, double top, double workBottom)
    {
        if (!double.IsFinite(listHeight)) listHeight = DefaultListHeight;
        if (!double.IsFinite(delta)) delta = 0;
        var available = workBottom - top - Math.Max(0, chromeHeight);
        var ceiling = Math.Max(MinimumListHeight, Math.Min(MaximumListHeight, available));
        return Math.Clamp(listHeight + delta, MinimumListHeight, ceiling);
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
