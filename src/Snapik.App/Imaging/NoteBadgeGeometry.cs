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
        Create(anchor, ExportDiameter(label), offset, ExportGap, topMargin);

    /// <summary>
    /// How much larger the exported badge is than the one on screen, never below 1. One number for
    /// everything that has to grow with the badge: the leader, the dot of a comment and its rim.
    /// </summary>
    internal static double ExportScale(string label) =>
        Math.Max(1, ExportDiameter(label) / ScreenDiameter(label));

    /// <summary>
    /// The leader of an exported badge, in pixels: the badge itself is drawn larger than the one on
    /// screen, so the line grows with it instead of thinning out to a thread, and never below 1 px.
    /// </summary>
    internal static double ExportLeaderThickness(string label) => ExportScale(label);

    private static double ScreenDiameter(string label) => Math.Max(26, label.Length * 7 + 12);

    private static double ExportDiameter(string label) => Math.Max(34, label.Length * 9 + 16);

    /// <summary>The air between the point of a mark and the rim of its badge in the export.</summary>
    private const double ExportGap = 4;

    /// <summary>The dot a comment is pinned by, on screen and, scaled by <see cref="ExportScale"/>,
    /// in the export. It lives here and not in the canvas because the leader has to start on its
    /// rim in all three drawers, and they would drift apart on two copies of the number.</summary>
    internal const double AnchorRadius = 5;

    private static NoteBadge Create(Point anchor, double diameter, Vector offset, double gap, double topMargin)
    {
        var center = new Point(
            anchor.X + offset.X,
            Math.Max(topMargin + diameter / 2, anchor.Y + offset.Y - diameter / 2 - gap));
        return new NoteBadge(center, diameter / 2);
    }

    /// <summary>
    /// The field around the capture that the badges need. Counted in the pixels of the capture,
    /// without the header of the export: a picture whose badges all stand inside it comes out byte
    /// for byte as before. A badge that was never dragged counts too — it is drawn above the point
    /// it belongs to, and a comment near the top edge hangs over the capture without any dragging.
    /// The centre is the one <see cref="Create"/> gives: the same lift of half a diameter and the
    /// gap, or the field would be measured from a circle nobody draws.
    /// </summary>
    internal static ExportMargin ExportMargins(
        IEnumerable<(NormalizedPoint Anchor, NormalizedPoint? Offset, string Label)> badges, int width, int height)
    {
        double left = 0, top = 0, right = 0, bottom = 0;
        foreach (var (anchor, offset, label) in badges)
        {
            // A comment without a number has no badge to fit in.
            if (string.IsNullOrEmpty(label)) continue;
            var shift = offset ?? new NormalizedPoint(0, 0);
            var diameter = ExportDiameter(label);
            var radius = diameter / 2 + Padding;
            var centerX = (anchor.X + shift.X) * width;
            var centerY = (anchor.Y + shift.Y) * height - diameter / 2 - ExportGap;
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
    // A comment has no outline to start from — its mark is the dot itself, so it passes the radius
    // of that dot as <paramref name="fromRadius"/> and a degenerate rectangle as the bounds: the
    // line then begins on the rim of the dot instead of in its middle. Zero keeps the old picture.
    internal static bool TryLeader(Rect bounds, NoteBadge badge, out Point from, out Point to, double fromRadius = 0)
    {
        from = new Point(
            Math.Clamp(badge.Center.X, bounds.Left, bounds.Right),
            Math.Clamp(badge.Center.Y, bounds.Top, bounds.Bottom));
        to = badge.Center;
        var direction = badge.Center - from;
        var length = direction.Length;
        if (length <= badge.Radius + fromRadius + 1) return false;
        direction /= length;
        from += direction * fromRadius;
        to = badge.Center - direction * badge.Radius;
        return true;
    }
}
