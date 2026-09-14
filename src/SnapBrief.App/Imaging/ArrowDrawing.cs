using System;
using System.Windows;
using System.Windows.Media;

namespace SnapBrief.App.Imaging;

internal static class ArrowDrawing
{
    // How far a curved arrow bends: the hit test and the drawing read it from here, so the line the
    // user grabs is the line they see.
    internal static Point ControlPoint(Point start, Point end)
    {
        var vector = end - start;
        return new Point((start.X + end.X) / 2 - vector.Y * .25, (start.Y + end.Y) / 2 + vector.X * .25);
    }

    // The shaft as a polyline, for the hit test of the move handle: a straight arrow is the segment
    // itself, a curved one is the same quadratic curve the drawing uses, sampled.
    internal static Point[] Shaft(Point start, Point end, string style)
    {
        if (style != "curved") return [start, end];
        var control = ControlPoint(start, end);
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

    // The pattern belongs to the shaft alone: a dashed head would read as a broken arrow, and the
    // head is a filled geometry rather than a stroke in any case.
    internal static void Draw(DrawingContext dc, Point start, Point end, Brush brush, double thickness, string style,
        SnapBrief.Core.Models.AnnotationLineStyle lineStyle = SnapBrief.Core.Models.AnnotationLineStyle.Solid)
    {
        var length = (end - start).Length;
        if (length < .01) return;
        var direction = start - end;
        var pen = StrokePattern.Apply(
            new Pen(brush, thickness * (style == "bold" ? 2 : 1)) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round, LineJoin = PenLineJoin.Round },
            lineStyle);
        if (style == "curved")
        {
            var control = ControlPoint(start, end);
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
