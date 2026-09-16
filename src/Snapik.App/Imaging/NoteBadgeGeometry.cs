using System;
using System.Collections.Generic;
using System.Windows;
using Snapik.Core.Models;

namespace Snapik.App.Imaging;

/// <summary>The room the exported picture needs around itself, in its own pixels.</summary>
internal readonly record struct ExportMargin(int Left, int Top, int Right, int Bottom)
{
    internal static readonly ExportMargin None = default;

    internal bool IsEmpty => Left == 0 && Top == 0 && Right == 0 && Bottom == 0;
}

internal readonly record struct NoteBadge(Point Center, double Radius)
{
    internal bool Contains(Point point, double slack = 0) => (point - Center).Length <= Radius + slack;
}

// One place for the circle with the number of a noted mark. The editor canvas draws it, hit-tests
// it and places the note pill over it; the export renderer draws the same circle in image pixels.
// Both must agree, otherwise a note the user dragged would sit elsewhere in the exported PNG.
internal static class NoteBadgeGeometry
{
    internal static NoteBadge Screen(Point anchor, string label, Vector offset) =>
        Create(anchor, ScreenDiameter(label), offset, 3, double.NegativeInfinity);

    /// <summary>
    /// The same circle in the pixels of the exported picture. <paramref name="topMargin"/> is the
    /// first row the badge may touch: the export draws a white header the badge must stay under.
    /// </summary>
    internal static NoteBadge Export(Point anchor, string label, Vector offset, double topMargin) =>
        Create(anchor, ExportDiameter(label), offset, 4, topMargin);

    /// <summary>
    /// The leader of an exported badge, in pixels: the badge itself is drawn larger than the one on
    /// screen, so the line grows with it instead of thinning out to a thread, and never below 1 px.
    /// </summary>
    internal static double ExportLeaderThickness(string label) =>
        Math.Max(1, ExportDiameter(label) / ScreenDiameter(label));

    private static double ScreenDiameter(string label) => Math.Max(26, label.Length * 7 + 12);

    private static double ExportDiameter(string label) => Math.Max(34, label.Length * 9 + 16);

    private static NoteBadge Create(Point anchor, double diameter, Vector offset, double gap, double topMargin)
    {
        var center = new Point(
            anchor.X + offset.X,
            Math.Max(topMargin + diameter / 2, anchor.Y + offset.Y - diameter / 2 - gap));
        return new NoteBadge(center, diameter / 2);
    }

    /// <summary>
    /// The field around the capture that the badges dragged off it need. Counted in the pixels of
    /// the capture, without the header of the export: a badge left where it was born asks for
    /// nothing, and a picture whose badges all stand inside it comes out byte for byte as before.
    /// </summary>
    internal static ExportMargin ExportMargins(
        IEnumerable<(NormalizedPoint Anchor, NormalizedPoint? Offset, string Label)> badges, int width, int height)
    {
        double left = 0, top = 0, right = 0, bottom = 0;
        foreach (var (anchor, offset, label) in badges)
        {
            // A comment without a note carries no number, and no number means no badge to fit in.
            if (offset is not { } shift || string.IsNullOrEmpty(label)) continue;
            var radius = ExportDiameter(label) / 2 + Padding;
            var centerX = (anchor.X + shift.X) * width;
            var centerY = (anchor.Y + shift.Y) * height;
            left = Math.Max(left, radius - centerX);
            top = Math.Max(top, radius - centerY);
            right = Math.Max(right, centerX + radius - width);
            bottom = Math.Max(bottom, centerY + radius - height);
        }
        return new ExportMargin(Ceiling(left), Ceiling(top), Ceiling(right), Ceiling(bottom));

        static int Ceiling(double value) => value <= 0 ? 0 : (int)Math.Ceiling(value);
    }

    /// <summary>The room kept between a badge and the edge of the field it was given.</summary>
    private const double Padding = 8;

    // The thin leader between the mark and a badge the user moved away from it: it starts on the
    // outline of the mark and stops on the rim of the badge, so neither is covered by the line.
    internal static bool TryLeader(Rect bounds, NoteBadge badge, out Point from, out Point to)
    {
        from = new Point(
            Math.Clamp(badge.Center.X, bounds.Left, bounds.Right),
            Math.Clamp(badge.Center.Y, bounds.Top, bounds.Bottom));
        to = badge.Center;
        var direction = badge.Center - from;
        var length = direction.Length;
        if (length <= badge.Radius + 1) return false;
        direction /= length;
        to = badge.Center - direction * badge.Radius;
        return true;
    }
}
