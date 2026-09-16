using System;
using System.Windows;

namespace Snapik.App.Controls;

/// <summary>
/// The arithmetic of the editor view: how much a capture is scaled down to fit the screen, and how
/// far it may be scrolled once it is shown at its own size. Both are pure functions on purpose —
/// eleven places of the canvas count from the rectangle they decide, and a slip in the clamp shows
/// up not as "the picture does not scroll" but as "a mark lands in the wrong place".
/// </summary>
internal static class EditorGeometry
{
    /// <summary>
    /// The scale a picture is fitted into a box with, never above its own size: a capture smaller
    /// than the box is shown as it is, and the answer is 1. The side that decided the scale is not
    /// reported any more — it was read by the caption of the scale switch, and that switch is gone.
    /// </summary>
    internal static double Fit(double imageWidth, double imageHeight, double boxWidth, double boxHeight)
    {
        if (imageWidth <= 0 || imageHeight <= 0 || boxWidth <= 0 || boxHeight <= 0) return 1;
        var scale = Math.Min(boxWidth / imageWidth, boxHeight / imageHeight);
        return scale >= 1 ? 1 : scale;
    }

    /// <summary>
    /// Where the capture stands in the working area: at its own size when it fits there together
    /// with the panel below it, fitted by its width or by its height when it does not. The answer is
    /// in the units of the window, so "one to one" here is a size and not a mode of the canvas:
    /// ViewScale stays null and every other count of the editor goes on as before.
    /// </summary>
    internal static Rect PlaceCapture(Size image, Rect work, Size panel, double gap = 10, double margin = 8)
    {
        var boxWidth = Math.Max(1, work.Width - margin * 2);
        var boxHeight = Math.Max(1, work.Height - margin * 2 - panel.Height - gap);
        var scale = image.Width <= boxWidth && image.Height <= boxHeight
            ? 1
            : Fit(image.Width, image.Height, boxWidth, boxHeight);
        var size = new Size(image.Width * scale, image.Height * scale);
        return new Rect(
            work.Left + (work.Width - size.Width) / 2,
            Math.Max(work.Top + margin, work.Top + (work.Height - panel.Height - gap - size.Height) / 2),
            size.Width, size.Height);
    }

    /// <summary>
    /// The offset of a picture shown at <paramref name="scale"/> inside a viewport, held so that no
    /// edge of the picture comes inside the viewport. The offset is how far the picture is scrolled,
    /// so the rectangle it is drawn in starts at minus this. An axis along which the picture is
    /// shorter than the viewport is centred instead.
    /// </summary>
    internal static Vector ClampOffset(Size image, double scale, Size viewport, Vector offset) => new(
        Axis(image.Width * scale, viewport.Width, offset.X),
        Axis(image.Height * scale, viewport.Height, offset.Y));

    private static double Axis(double picture, double box, double offset) =>
        picture <= box ? -(box - picture) / 2 : Math.Clamp(offset, 0, picture - box);

    /// <summary>
    /// The offset that keeps the point under the cursor where it is while the scale changes:
    /// <paramref name="cursor"/> is in the units of the viewport, and the answer is the new offset
    /// before it is clamped.
    /// </summary>
    internal static Vector ZoomAround(Point cursor, Vector offset, double fromScale, double toScale)
    {
        if (fromScale <= 0) return offset;
        var image = new Point((cursor.X + offset.X) / fromScale, (cursor.Y + offset.Y) / fromScale);
        return new Vector(image.X * toScale - cursor.X, image.Y * toScale - cursor.Y);
    }
}
