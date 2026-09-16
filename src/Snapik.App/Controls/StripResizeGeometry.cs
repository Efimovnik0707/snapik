using System;
using System.Windows;

namespace Snapik.App.Controls;

/// <summary>
/// The width of the strip, dragged by its left edge. The right edge is fixed while the drag lasts,
/// so the card grows into the screen instead of walking away from it. Sizes are window sizes: the
/// visible card is 20 px narrower, that margin carries the shadow.
/// </summary>
internal static class StripResizeGeometry
{
    /// <summary>
    /// The transparent field around the panel that carries the shadow of the window: a blur radius
    /// of 24 and a depth of 5 need 12 + 5 = 17 px, and 20 is the round number above that. It is the
    /// margin of the shell, of the capsule and of the grips.
    /// </summary>
    internal const double ShadowMargin = 20;

    /// <summary>The panel the user sees: the window without the field under its shadow.</summary>
    internal const double MinimumPanelWidth = 204;

    internal const double MinimumWidth = MinimumPanelWidth + 2 * ShadowMargin;
    internal const double DefaultWidth = MinimumWidth;

    /// <summary>
    /// The gap the strip keeps between itself and the right edge of the working area. It is also
    /// the ceiling of the width: a strip as wide as the whole working area would have to start
    /// outside of it to keep that gap. The field under the shadow is the gap that is seen now, so
    /// this one is zero and the panel still stands 20 px away from the edge.
    /// </summary>
    internal const double EdgeGap = 0;

    /// <summary>The two paddings between the panel and a card: the shell and the capture list.</summary>
    internal const double ShellPadding = 10;

    /// <summary>
    /// The paddings of the capture list are not the same on both sides: the right one carries the
    /// scroll bar, which stands over the cards and needs a field of its own, and the left one gives
    /// the four pixels back so that the card keeps the 168 px of the reference shot.
    /// </summary>
    internal const double ListPaddingLeft = 4;
    internal const double ListPaddingRight = 12;

    /// <summary>The card of a capture inside a window of that width: 168 px at 244.</summary>
    internal static double CardWidth(double windowWidth) =>
        windowWidth - 2 * ShadowMargin - 2 * ShellPadding - ListPaddingLeft - ListPaddingRight;

    /// <summary>The hint that stands where the list is while the strip holds nothing.</summary>
    internal const double EmptyListHeight = 92;

    internal const double ListTopPadding = 14;
    internal const double ListBottomPadding = 8;

    /// <summary>A card and the part of it the next card lies over; the difference is the pitch.</summary>
    internal const double CardHeight = 78;
    internal const double CardOverlap = 48;
    internal const double CardPitch = CardHeight - CardOverlap;

    /// <summary>
    /// The height the capture list wants for <paramref name="count"/> cards, and the ceiling the
    /// corner grip has written into the settings. The grip sets the ceiling, not the height: a list
    /// of two cards is 130 tall whatever the settings say, and it stops growing at the ceiling.
    /// <see cref="MinimumListHeight"/> is no floor here — it belongs to the stored number alone,
    /// otherwise a single capture would open a list of 180 instead of 100.
    /// </summary>
    internal static double ListHeightForCount(int count, double cap)
    {
        if (count <= 0) return EmptyListHeight;
        var content = ListTopPadding + (count - 1) * CardPitch + CardHeight + ListBottomPadding;
        var ceiling = double.IsFinite(cap) && cap > 0 ? cap : DefaultListHeight;
        return Math.Min(content, ceiling);
    }

    /// <summary>
    /// The left edge of the capsule, so that it keeps the right edge of the strip it came from
    /// rather than the edge of the monitor: both windows carry the same field under their shadow,
    /// so the sides the user sees line up.
    /// </summary>
    internal static double CapsuleLeft(double stripLeft, double stripWidth, double capsuleWidth) =>
        stripLeft + stripWidth - capsuleWidth;

    /// <summary>
    /// The rectangle the strip had before the capsule, moved back into the working area only when it
    /// no longer fits: a strip dragged away from the edge stays where the user left it.
    /// </summary>
    internal static Rect RestoreRect(Rect stored, Rect work)
    {
        if (!work.IsEmpty && work.Width > 0 && work.Height > 0 && !work.Contains(stored))
        {
            var x = Math.Min(Math.Max(stored.X, work.Left), Math.Max(work.Left, work.Right - stored.Width));
            var y = Math.Min(Math.Max(stored.Y, work.Top), Math.Max(work.Top, work.Bottom - stored.Height));
            return new Rect(x, y, stored.Width, stored.Height);
        }
        return stored;
    }

    // The height of the strip is the height of the capture list: the window lives on
    // SizeToContent="Height", and a height written to the window itself is overwritten by the next
    // layout pass. The card (78 px) and the overlap (48 px) stay as they are, the visible part of
    // the list is what grows. The list carries that height outright rather than as a maximum: with
    // a maximum a short strip is shorter than the number it holds, the window stops following the
    // corner grip, and the drag moves nothing until the tenth capture. There is no number above:
    // the working area of the monitor is the only ceiling.
    internal const double MinimumListHeight = 180;
    internal const double DefaultListHeight = 372;

    /// <summary>
    /// Everything of the strip window that is not the list: the header, the capture button, the
    /// toast, the status line and the paddings of the card. The window measures its own before the
    /// first drag; this is the figure used until there is something to measure, and it is on the
    /// generous side on purpose — a list clamped a little short still fits on the screen.
    /// </summary>
    internal const double EstimatedChromeHeight = 160;

    /// <summary>
    /// A width from the settings file. The ceiling is the working area of the monitor the strip
    /// opens on, less the gap it keeps at the edge, so a width dragged out on a large monitor is
    /// pulled back in on a small one; nonsense falls back to the default. When the working area is
    /// unknown there is no ceiling, only the minimum.
    /// </summary>
    internal static double ClampWidth(double width, double workWidth)
    {
        var ceiling = double.IsFinite(workWidth) && workWidth > 0
            ? Math.Max(MinimumWidth, workWidth - EdgeGap)
            : double.PositiveInfinity;
        if (!double.IsFinite(width)) return Math.Min(DefaultWidth, ceiling);
        return Math.Clamp(width, MinimumWidth, ceiling);
    }

    /// <summary>
    /// The left edge and the width for a pointer that has travelled <paramref name="pointerDelta"/>
    /// pixels from where it was when the drag began, measured against <paramref name="startWidth"/>,
    /// the width the strip had at that same moment. Both figures come from the start of the drag on
    /// purpose: a delta added to the width of the moment keeps the travel already spent beyond a
    /// clamp, and the strip then ignores the whole way back until the pointer has given that travel
    /// up again. The strip never crosses <paramref name="leftLimit"/>, the left edge of the working
    /// area it sits in.
    /// </summary>
    internal static (double Left, double Width) WidthFromStart(double right, double startWidth, double pointerDelta, double leftLimit)
    {
        if (!double.IsFinite(startWidth)) startWidth = DefaultWidth;
        if (!double.IsFinite(pointerDelta)) pointerDelta = 0;
        var allowed = Math.Max(MinimumWidth, right - leftLimit);
        var resized = Math.Clamp(startWidth - pointerDelta, MinimumWidth, allowed);
        return (right - resized, resized);
    }

    /// <summary>
    /// A list height from the settings file: out of range is clamped, nonsense falls back to the
    /// default. What comes out is the ceiling the list grows to, not the height it is given — that
    /// one is <see cref="ListHeightForCount"/>, and the stored number only stops it.
    /// The working area is a ceiling of its own, and the window is taller than its list by
    /// <paramref name="chromeHeight"/>, so a height stored on a large monitor opens a window that
    /// still fits on the screen it comes back on, together with the corner grip that resizes it.
    /// </summary>
    internal static double ClampListHeight(double height, double workHeight, double chromeHeight)
    {
        var chrome = double.IsFinite(chromeHeight) && chromeHeight > 0 ? chromeHeight : EstimatedChromeHeight;
        var ceiling = double.IsFinite(workHeight) && workHeight > 0
            ? Math.Max(MinimumListHeight, workHeight - chrome)
            : double.PositiveInfinity;
        return Math.Clamp(double.IsFinite(height) ? height : DefaultListHeight, MinimumListHeight, ceiling);
    }

    /// <summary>
    /// The height of the capture list for a pointer that has travelled <paramref name="pointerDelta"/>
    /// pixels downwards from where it was when the drag began, measured against
    /// <paramref name="startListHeight"/>, the height the list had at that same moment — the way back
    /// from a clamp then moves the strip on the first pixel. The top edge stays where it was, so the
    /// strip grows down; <paramref name="chromeHeight"/> is everything of the window that is not the
    /// list (header, button, toast, paddings), and it keeps the bottom of the window inside
    /// <paramref name="workBottom"/>.
    /// </summary>
    internal static double ListHeightFromStart(double startListHeight, double pointerDelta, double chromeHeight, double top, double workBottom)
    {
        if (!double.IsFinite(startListHeight)) startListHeight = DefaultListHeight;
        if (!double.IsFinite(pointerDelta)) pointerDelta = 0;
        var available = workBottom - top - Math.Max(0, chromeHeight);
        var ceiling = Math.Max(MinimumListHeight, available);
        return Math.Clamp(startListHeight + pointerDelta, MinimumListHeight, ceiling);
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
