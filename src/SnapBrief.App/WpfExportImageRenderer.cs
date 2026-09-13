using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using SnapBrief.Core.Exporting;
using SnapBrief.Core.Models;
using SnapBrief.App.Imaging;
using CoreCaptureItem = SnapBrief.Core.Models.CaptureItem;

namespace SnapBrief.App;

public sealed class WpfExportImageRenderer : IExportImageRenderer
{
    private const int HeaderHeight = 48;

    public Task RenderAsync(CoreCaptureItem capture, ExportImageContext context, Stream destination, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var image = LoadBitmap(context.SourceImagePath);
        var visual = new DrawingVisual();
        using (var dc = visual.RenderOpen())
        {
            dc.DrawRectangle(Brushes.White, null, new Rect(0, 0, image.PixelWidth, HeaderHeight));
            var bounds = new Rect(0, HeaderHeight, image.PixelWidth, image.PixelHeight);
            dc.DrawImage(ApplyBlurAnnotations(image, capture), bounds);
            DrawCaptureBadge(dc, context.DisplayLabel);

            var labels = CaptureLabels.ForNotedAnnotations(context.DisplayLabel, capture)
                .ToDictionary(x => x.Annotation.Id, x => x.DisplayLabel);
            foreach (var annotation in capture.Annotations.Where(a => a.Kind != AnnotationKind.Blur && !HasOpaqueFill(a)))
                DrawAnnotation(dc, annotation, image.PixelWidth, image.PixelHeight, null, HeaderHeight, drawShape: true);
            foreach (var annotation in capture.Annotations.Where(HasOpaqueFill))
                DrawAnnotation(dc, annotation, image.PixelWidth, image.PixelHeight, null, HeaderHeight, drawShape: true);
            foreach (var annotation in capture.Annotations)
                DrawAnnotation(dc, annotation, image.PixelWidth, image.PixelHeight, labels.GetValueOrDefault(annotation.Id), HeaderHeight, drawShape: false);
        }

        var rendered = new RenderTargetBitmap(image.PixelWidth, image.PixelHeight + HeaderHeight, 96, 96, PixelFormats.Pbgra32);
        rendered.Render(visual);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(rendered));
        encoder.Save(destination);
        return Task.CompletedTask;
    }

    private static BitmapSource LoadBitmap(string path)
    {
        using var stream = File.OpenRead(path);
        var decoder = BitmapDecoder.Create(stream, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad);
        var frame = decoder.Frames[0];
        frame.Freeze();
        return frame;
    }

    private static void DrawCaptureBadge(DrawingContext dc, string label)
    {
        var badge = new Rect(12, 8, 34, 32);
        dc.DrawRoundedRectangle(new SolidColorBrush(Color.FromRgb(23, 32, 51)), null, badge, 7, 7);
        DrawText(dc, label, 16, FontWeights.Bold, Brushes.White, new Point(23, 13));
        DrawText(dc, "SNAPBRIEF · СНИМОК", 12, FontWeights.SemiBold, new SolidColorBrush(Color.FromRgb(94, 104, 122)), new Point(57, 16));
    }

    // The same two rules the editor canvas draws by: an opaque region goes over everything else, and
    // a blur is baked into the picture whether it came from the blur tool or from a region filled
    // with blur.
    // The redaction kind is kept here on purpose: the editor turns one into a filled region as it
    // reads it, but a mark that reached the renderer another way must still hide what is under it.
    private static bool HasOpaqueFill(SnapBrief.Core.Models.AnnotationItem item) =>
        item.Kind == AnnotationKind.Redaction || (item.Kind == AnnotationKind.Rectangle && item.Fill == AnnotationFill.Solid);

    private static bool IsBlurred(SnapBrief.Core.Models.AnnotationItem item) =>
        item.Kind == AnnotationKind.Blur || (item.Kind == AnnotationKind.Rectangle && item.Fill == AnnotationFill.Blur);

    private static BitmapSource ApplyBlurAnnotations(BitmapSource source, CoreCaptureItem capture)
    {
        BitmapSource result = source;
        foreach (var item in capture.Annotations.Where(a => IsBlurred(a) && a.Points.Length > 1))
        {
            var left = Math.Clamp((int)Math.Floor(Math.Min(item.Points[0].X, item.Points[1].X) * source.PixelWidth), 0, source.PixelWidth);
            var top = Math.Clamp((int)Math.Floor(Math.Min(item.Points[0].Y, item.Points[1].Y) * source.PixelHeight), 0, source.PixelHeight);
            var right = Math.Clamp((int)Math.Ceiling(Math.Max(item.Points[0].X, item.Points[1].X) * source.PixelWidth), left, source.PixelWidth);
            var bottom = Math.Clamp((int)Math.Ceiling(Math.Max(item.Points[0].Y, item.Points[1].Y) * source.PixelHeight), top, source.PixelHeight);
            var region = new Int32Rect(left, top, right - left, bottom - top);
            result = RegionBlur.Apply(result, region, RegionBlur.RadiusFor(region.Width, region.Height), item.Shape);
        }
        return result;
    }

    private static void DrawAnnotation(DrawingContext dc, SnapBrief.Core.Models.AnnotationItem item, int width, int height, string? displayLabel, int offsetY, bool drawShape)
    {
        if (item.Points.IsDefaultOrEmpty) return;
        Point P(NormalizedPoint p) => new(p.X * width, p.Y * height + offsetY);
        var color = (Color)ColorConverter.ConvertFromString(item.StrokeColor);
        var brush = new SolidColorBrush(color);
        var pen = new Pen(brush, item.Thickness) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round, LineJoin = PenLineJoin.Round };

        if (drawShape && item.Kind is (AnnotationKind.Freehand or AnnotationKind.Highlight))
        {
            // The same geometry and the same transparency the editor draws with: one stroke, laid
            // down once, so a joint is no darker than the middle of a segment.
            var stroke = Controls.AnnotationCanvas.StrokeGeometry(
                item.GetPathSegments().Select(segment => (IReadOnlyList<NormalizedPoint>)segment), P);
            if (item.Kind == AnnotationKind.Highlight)
                Controls.AnnotationCanvas.DrawHighlightStroke(dc, stroke, brush, item.Thickness);
            else dc.DrawGeometry(null, pen, stroke);
        }
        else if (drawShape && item.Points.Length > 1)
        {
            var start = P(item.Points[0]);
            var end = P(item.Points[1]);
            var rect = new Rect(start, end);
            switch (item.Kind)
            {
                case AnnotationKind.Rectangle:
                    var fillColor = ParseFillColor(item.FillColor) ?? color;
                    Controls.AnnotationCanvas.DrawBoxShape(dc, Controls.AnnotationCanvas.ShapeFillBrush(fillColor, item.Fill),
                        item.HasOutline ? pen : null, item.Shape, rect, 1);
                    break;
                case AnnotationKind.Redaction: dc.DrawRectangle(Brushes.Black, null, rect); break;
                // The size the caption was typed in, in the pixels of the capture, and the same
                // family the editor draws with: the letters in the PNG are the letters on screen.
                case AnnotationKind.Text:
                    DrawText(dc, item.Text, TextMarkMetrics.Clamp(item.FontSize), FontWeights.Normal, brush, start, TextMarkMetrics.FamilyName);
                    break;
                case AnnotationKind.Arrow:
                    SnapBrief.App.Imaging.ArrowDrawing.Draw(dc, start, end, brush, item.Thickness, item.ArrowStyle);
                    break;
            }
        }

        if (!string.IsNullOrEmpty(displayLabel))
        {
            var badgeBrush = new SolidColorBrush(Color.FromRgb(47, 140, 255));
            var badge = ExportBadge(item, displayLabel, width, height, offsetY);
            // The pill the user dragged moved this badge: the picture the agent receives shows the
            // same place, with one hair line back to the mark.
            if (item.NoteOffset is not null)
            {
                var points = item.GetPathSegments().SelectMany(segment => segment).Concat(item.Points).ToArray();
                var outline = new Rect(
                    new Point(points.Min(point => point.X) * width, points.Min(point => point.Y) * height + offsetY),
                    new Point(points.Max(point => point.X) * width, points.Max(point => point.Y) * height + offsetY));
                if (NoteBadgeGeometry.TryLeader(outline, badge, out var from, out var to))
                    dc.DrawLine(new Pen(badgeBrush, NoteBadgeGeometry.ExportLeaderThickness(displayLabel)), from, to);
            }
            dc.DrawEllipse(badgeBrush, null, badge.Center, badge.Radius, badge.Radius);
            var label = new FormattedText(displayLabel, System.Globalization.CultureInfo.CurrentUICulture, FlowDirection.LeftToRight,
                new Typeface(new FontFamily("Segoe UI"), FontStyles.Normal, FontWeights.Bold, FontStretches.Normal), 13, Brushes.White, 1);
            dc.DrawText(label, new Point(badge.Center.X - label.Width / 2, badge.Center.Y - label.Height / 2));
        }
    }

    // A fill colour that cannot be read means "the colour of the outline": the mark is still drawn.
    private static Color? ParseFillColor(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        try { return ColorConverter.ConvertFromString(value) is Color color ? color : null; }
        catch (Exception) { return null; }
    }

    // The same circle the editor canvas shows, in the pixels of the exported picture.
    internal static NoteBadge ExportBadge(SnapBrief.Core.Models.AnnotationItem item, string displayLabel, int width, int height, int offsetY)
    {
        var anchor = new Point(item.Points[0].X * width, item.Points[0].Y * height + offsetY);
        var offset = item.NoteOffset is { } shift ? new Vector(shift.X * width, shift.Y * height) : default;
        // The badge stops below the white header instead of climbing into it.
        return NoteBadgeGeometry.Export(anchor, displayLabel, offset, HeaderHeight + 2);
    }

    private static void DrawText(DrawingContext dc, string text, double size, FontWeight weight, Brush brush, Point point, string family = "Segoe UI")
    {
        var formatted = new FormattedText(text, System.Globalization.CultureInfo.CurrentUICulture, FlowDirection.LeftToRight,
            new Typeface(new FontFamily(family), FontStyles.Normal, weight, FontStretches.Normal), size, brush, 1);
        dc.DrawText(formatted, point);
    }
}
