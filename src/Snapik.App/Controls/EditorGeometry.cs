using System;
using System.Windows;

namespace Snapik.App.Controls;

/// <summary>Which side of the box stopped the picture from growing any further.</summary>
internal enum FitBound { None, Width, Height }

/// <summary>The scale the picture is shown at, and the side that decided it.</summary>
internal readonly record struct FitResult(double Scale, FitBound BoundBy);

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
    /// than the box is shown as it is and has nothing to switch between.
    /// </summary>
    internal static FitResult Fit(double imageWidth, double imageHeight, double boxWidth, double boxHeight)
    {
        if (imageWidth <= 0 || imageHeight <= 0 || boxWidth <= 0 || boxHeight <= 0) return new FitResult(1, FitBound.None);
        var byWidth = boxWidth / imageWidth;
        var byHeight = boxHeight / imageHeight;
        var scale = Math.Min(byWidth, byHeight);
        return scale >= 1 ? new FitResult(1, FitBound.None) : new FitResult(scale, byWidth < byHeight ? FitBound.Width : FitBound.Height);
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
