using System;
using SnapBrief.Core.Models;

namespace SnapBrief.App.Imaging;

/// <summary>
/// How much of one pixel a frame covers inside its bounding box, from 0 (outside) to 1 (inside).
/// The blur of a region is mixed with the untouched picture by this number, so an oval blur is an
/// oval on screen and in the exported PNG: both renderers ask the same code.
/// </summary>
public static class ShapeMask
{
    /// <summary>The corner of a rounded frame never grows past this, in image pixels.</summary>
    public const double MaximumCornerRadius = 14;

    /// <summary>The radius the outline of a rounded frame is drawn with, in image pixels.</summary>
    public static double CornerRadius(double width, double height) =>
        Math.Min(MaximumCornerRadius, Math.Min(width, height) / 4);

    /// <summary>
    /// The coverage of the pixel at column <paramref name="x"/> and row <paramref name="y"/> of a
    /// box <paramref name="width"/> by <paramref name="height"/> pixels. The edge is smoothed over
    /// one pixel by the signed distance to the shape, so an oval does not come out jagged.
    /// </summary>
    public static double Coverage(AnnotationShape shape, double width, double height, double x, double y)
    {
        if (width <= 0 || height <= 0) return 0;
        if (shape == AnnotationShape.Rectangle) return 1;
        var centerX = x + 0.5 - width / 2;
        var centerY = y + 0.5 - height / 2;
        var distance = shape == AnnotationShape.Ellipse
            ? EllipseDistance(centerX, centerY, width / 2, height / 2)
            : RoundedDistance(centerX, centerY, width / 2, height / 2, CornerRadius(width, height));
        return Math.Clamp(0.5 - distance, 0, 1);
    }

    // The distance to an ellipse has no short exact form; this is the standard first-order estimate
    // of it, exact enough within the one pixel the edge is smoothed over.
    private static double EllipseDistance(double x, double y, double radiusX, double radiusY)
    {
        if (radiusX <= 0 || radiusY <= 0) return double.PositiveInfinity;
        var normalized = x * x / (radiusX * radiusX) + y * y / (radiusY * radiusY);
        var gradient = 2 * Math.Sqrt(
            x * x / (radiusX * radiusX * radiusX * radiusX) +
            y * y / (radiusY * radiusY * radiusY * radiusY));
        // The centre of the ellipse: no gradient to follow, and nothing near the edge either.
        return gradient <= double.Epsilon ? -Math.Min(radiusX, radiusY) : (normalized - 1) / gradient;
    }

    private static double RoundedDistance(double x, double y, double halfWidth, double halfHeight, double radius)
    {
        var cornerX = Math.Abs(x) - (halfWidth - radius);
        var cornerY = Math.Abs(y) - (halfHeight - radius);
        var outside = Math.Sqrt(Math.Max(cornerX, 0) * Math.Max(cornerX, 0) + Math.Max(cornerY, 0) * Math.Max(cornerY, 0));
        return outside + Math.Min(Math.Max(cornerX, cornerY), 0) - radius;
    }
}
