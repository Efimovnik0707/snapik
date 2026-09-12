using System;
using System.Windows;
using System.Windows.Media;

namespace SnapBrief.App.Imaging;

internal static class ArrowDrawing
{
    // The shaft as a polyline, for the hit test of the move handle: a straight arrow is the segment
    // itself, a curved one is the same quadratic curve the drawing uses, sampled.
    internal static Point[] Shaft(Point start, Point end, string style)
    {
        if (style != "curved") return [start, end];
        var vector = end - start;
        var control = new Point((start.X + end.X) / 2 - vector.Y * .25, (start.Y + end.Y) / 2 + vector.X * .25);
        var points = new Point[17];
        for (var i = 0; i < points.Length; i++)
        {
            var t = (double)i / (points.Length - 1);
            var inverse = 1 - t;
            points[i] = new Point(
                inverse * inverse * start.X + 2 * inverse * t * control.X + t * t * end.X,
                inverse * inverse * start.Y + 2 * inverse * t * control.Y + t * t * end.Y);
        }
        return points;
    }

    internal static void Draw(DrawingContext dc, Point start, Point end, Brush brush, double thickness, string style)
    {
        var length = (end - start).Length;
        if (length < .01) return;
        var direction = start - end;
        var pen = new Pen(brush, thickness * (style == "bold" ? 2 : 1)) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round, LineJoin = PenLineJoin.Round };
        if (style == "curved")
        {
            var vector = end - start;
            var control = new Point((start.X + end.X) / 2 - vector.Y * .25, (start.Y + end.Y) / 2 + vector.X * .25);
            var curve = new StreamGeometry();
            using (var ctx = curve.Open()) { ctx.BeginFigure(start, false, false); ctx.QuadraticBezierTo(control, end, true, false); }
            dc.DrawGeometry(null, pen, curve);
            direction = control - end;
        }
        else dc.DrawLine(pen, start, end);
        direction.Normalize();
        var side = new Vector(-direction.Y, direction.X);
        var size = Math.Min(length * .7, Math.Max(10, pen.Thickness * 3.2));
        var halfWidth = size * (style == "wide" ? .85 : .45);
        var head = new StreamGeometry();
        using (var ctx = head.Open()) { ctx.BeginFigure(end, true, true); ctx.LineTo(end + direction * size + side * halfWidth, true, false); ctx.LineTo(end + direction * size - side * halfWidth, true, false); }
        dc.DrawGeometry(brush, null, head);
    }
}
