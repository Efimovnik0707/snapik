using System;
using System.Windows;

namespace SnapBrief.App.Controls;

internal static class ResizeGeometry
{
    // Clockwise: top-left, top-right, bottom-right, bottom-left.
    internal static Point[] Corners(Rect bounds) => [bounds.TopLeft, bounds.TopRight, bounds.BottomRight, bounds.BottomLeft];

    internal static int HitCorner(Rect bounds, Point point, double radius)
    {
        var corners = Corners(bounds);
        for (var i = 0; i < corners.Length; i++)
            if ((corners[i] - point).Length <= radius) return i;
        return -1;
    }

    internal static Rect Resize(Rect original, int corner, Point point, Rect limit, double minimum)
    {
        var minimumX = Math.Min(minimum, original.Width);
        var minimumY = Math.Min(minimum, original.Height);
        var left = original.Left;
        var top = original.Top;
        var right = original.Right;
        var bottom = original.Bottom;
        if (corner is 0 or 3) left = Math.Clamp(point.X, limit.Left, right - minimumX);
        else right = Math.Clamp(point.X, left + minimumX, limit.Right);
        if (corner is 0 or 1) top = Math.Clamp(point.Y, limit.Top, bottom - minimumY);
        else bottom = Math.Clamp(point.Y, top + minimumY, limit.Bottom);
        return new Rect(new Point(left, top), new Point(right, bottom));
    }

    internal static Point Map(Point point, Rect original, Rect resized) => new(
        resized.Left + (point.X - original.Left) * resized.Width / Math.Max(1, original.Width),
        resized.Top + (point.Y - original.Top) * resized.Height / Math.Max(1, original.Height));
}
