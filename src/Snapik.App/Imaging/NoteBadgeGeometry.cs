using System;
using System.Windows;

namespace Snapik.App.Imaging;

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
