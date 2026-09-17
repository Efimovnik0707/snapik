using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Snapik.Core.Exporting;
using Snapik.Core.Models;
using Snapik.App.Imaging;
using CoreCaptureItem = Snapik.Core.Models.CaptureItem;

namespace Snapik.App;

public sealed class WpfExportImageRenderer : IExportImageRenderer
{
    private const int HeaderHeight = 48;
    // The field the picture stands on when a badge was carried off it: the same dark the editor
    // shows beside the capture, so a badge on the field reads as a badge and not as a cut-off one.
    private static readonly Brush FieldBrush = new SolidColorBrush(Color.FromRgb(0x2A, 0x31, 0x40));

    /// <summary>
    /// The field the badges of a capture ask for around it, in the pixels of the capture. Every
    /// badge that was never dragged asks for nothing, and a picture whose badges all stand inside
    /// it is exported byte for byte as it was before the field existed.
    /// </summary>
    internal static ExportMargin MarginsOf(CoreCaptureItem capture, string displayLabel, int width, int height) =>
        NoteBadgeGeometry.ExportMargins(
            CaptureLabels.ForNotedAnnotations(displayLabel, capture)
                .Where(noted => !noted.Annotation.Points.IsDefaultOrEmpty)
                .Select(noted => (noted.Annotation.Points[0], noted.Annotation.NoteOffset, noted.DisplayLabel)),
            width, height);

    /// <summary>
    /// Where the capture itself begins inside the exported picture: the header stands above it and
    /// the field the badges asked for is around it. Everything measured in the pixels of the
    /// capture — a mark, a badge, the leader between them — is counted from this one point.
    /// </summary>
    internal static Point CaptureOrigin(ExportMargin margin) => new(margin.Left, HeaderHeight + margin.Top);

    public Task RenderAsync(CoreCaptureItem capture, ExportImageContext context, Stream destination, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var image = LoadBitmap(context.SourceImagePath);
        var margin = MarginsOf(capture, context.DisplayLabel, image.PixelWidth, image.PixelHeight);
        var origin = CaptureOrigin(margin);
        var sheet = new Size(margin.Left + image.PixelWidth + margin.Right,
                             HeaderHeight + margin.Top + image.PixelHeight + margin.Bottom);
        var visual = new DrawingVisual();
        using (var dc = visual.RenderOpen())
        {
            // The field first, under everything: with no field at all it is covered whole by the
            // header and the picture, and the exported bytes are the ones of the round before.
            dc.DrawRectangle(FieldBrush, null, new Rect(0, 0, sheet.Width, sheet.Height));
            dc.DrawRectangle(Brushes.White, null, new Rect(0, 0, sheet.Width, HeaderHeight));
            var bounds = new Rect(origin.X, origin.Y, image.PixelWidth, image.PixelHeight);
            dc.DrawImage(ApplyBlurAnnotations(image, capture), bounds);
            DrawCaptureBadge(dc, context.DisplayLabel);

            var labels = CaptureLabels.ForNotedAnnotations(context.DisplayLabel, capture)
                .ToDictionary(x => x.Annotation.Id, x => x.DisplayLabel);
            foreach (var annotation in capture.Annotations.Where(a => a.Kind != AnnotationKind.Blur && !HasOpaqueFill(a)))
                DrawAnnotation(dc, annotation, image.PixelWidth, image.PixelHeight, null, origin, drawShape: true);
            foreach (var annotation in capture.Annotations.Where(HasOpaqueFill))
                DrawAnnotation(dc, annotation, image.PixelWidth, image.PixelHeight, null, origin, drawShape: true);
            foreach (var annotation in capture.Annotations)
                DrawAnnotation(dc, annotation, image.PixelWidth, image.PixelHeight, labels.GetValueOrDefault(annotation.Id), origin, drawShape: false);
        }

        var rendered = new RenderTargetBitmap((int)sheet.Width, (int)sheet.Height, 96, 96, PixelFormats.Pbgra32);
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
        // The export runs off the UI thread, and a frame still belongs to the decoder that made it:
        // the copy owns its pixels, so the stream closes here and nothing reaches back for them.
        return Imaging.FrameCopy.Detach(decoder.Frames[0]);
    }

    private static void DrawCaptureBadge(DrawingContext dc, string label)
    {
        var badge = new Rect(12, 8, 34, 32);
        dc.DrawRoundedRectangle(new SolidColorBrush(Color.FromRgb(23, 32, 51)), null, badge, 7, 7);
        DrawText(dc, label, 16, FontWeights.Bold, Brushes.White, new Point(23, 13));
        DrawText(dc, "SNAPIK · СНИМОК", 12, FontWeights.SemiBold, new SolidColorBrush(Color.FromRgb(94, 104, 122)), new Point(57, 16));
    }

    // The same two rules the editor canvas draws by: an opaque region goes over everything else, and
    // a blur is baked into the picture whether it came from the blur tool or from a region filled
    // with blur.
    // The redaction kind is kept here on purpose: the editor turns one into a filled region as it
    // reads it, but a mark that reached the renderer another way must still hide what is under it.
    private static bool HasOpaqueFill(Snapik.Core.Models.AnnotationItem item) =>
        item.Kind == AnnotationKind.Redaction || (item.Kind == AnnotationKind.Rectangle && item.Fill == AnnotationFill.Solid);

    private static bool IsBlurred(Snapik.Core.Models.AnnotationItem item) =>
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

    private static void DrawAnnotation(DrawingContext dc, Snapik.Core.Models.AnnotationItem item, int width, int height, string? displayLabel, Point origin, bool drawShape)
    {
        if (item.Points.IsDefaultOrEmpty) return;
        Point P(NormalizedPoint p) => new(origin.X + p.X * width, origin.Y + p.Y * height);
        var color = (Color)ColorConverter.ConvertFromString(item.StrokeColor);
        var brush = new SolidColorBrush(color);
        // The same pattern the editor draws with, and the same units: the dashes of a DashStyle are
        // thicknesses of the pen, so nothing has to be scaled from the screen to the picture.
        var pen = Snapik.App.Imaging.StrokePattern.Apply(
            new Pen(brush, item.Thickness) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round, LineJoin = PenLineJoin.Round },
            Snapik.App.Imaging.StrokePattern.Of(item.Kind, item.LineStyle));

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
                    var ownFill = ParseFillColor(item.FillColor);
                    // The same rule as on the canvas: the outline keeps the colour of the mark, a
                    // blurred one has none, and the pen only lends its thickness and its pattern.
                    var outline = Controls.AnnotationRules.OutlineColorOf(item.Fill, color);
                    var outlinePen = outline is { } oc ? new Pen(new SolidColorBrush(oc), pen.Thickness) { DashStyle = pen.DashStyle } : null;
                    Controls.AnnotationCanvas.DrawBoxShape(dc, Controls.AnnotationCanvas.ShapeFillBrush(ownFill ?? color, item.Fill),
                        outlinePen, item.Shape, rect, 1);
                    break;
                case AnnotationKind.Redaction: dc.DrawRectangle(Brushes.Black, null, rect); break;
                // The size the caption was typed in, in the pixels of the capture, and the same
                // family the editor draws with: the letters in the PNG are the letters on screen.
                case AnnotationKind.Text:
                    DrawText(dc, item.Text, TextMarkMetrics.Clamp(item.FontSize), FontWeights.Normal, brush, start, TextMarkMetrics.FamilyName);
                    break;
                case AnnotationKind.Arrow:
                    Snapik.App.Imaging.ArrowDrawing.Draw(dc, start, end, brush, item.Thickness, item.ArrowStyle,
                        Snapik.App.Imaging.StrokePattern.Of(item.Kind, item.LineStyle));
                    break;
            }
        }

        if (!string.IsNullOrEmpty(displayLabel))
        {
            var badgeBrush = AccentPalette.Brush;
            var badge = ExportBadge(item, displayLabel, width, height, origin);
            // The pill the user dragged moved this badge: the picture the agent receives shows the
            // same place, with one hair line back to the mark. A comment is led from the dot it is
            // pinned by, the way the editor leads it, and the dot itself is drawn here: without it
            // the line broke off in mid-air. Everything that has to grow with the badge grows by the
            // one scale — the thickness of the line, the dot and its rim.
            if (item.NoteOffset is not null)
            {
                var isComment = item.Kind == AnnotationKind.Comment;
                var scale = NoteBadgeGeometry.ExportScale(displayLabel);
                var anchor = ExportAnchor(item, width, height, origin);
                Rect outline;
                if (isComment) outline = new Rect(anchor, anchor);
                else
                {
                    var points = item.GetPathSegments().SelectMany(segment => segment).Concat(item.Points).ToArray();
                    outline = new Rect(
                        new Point(origin.X + points.Min(point => point.X) * width, origin.Y + points.Min(point => point.Y) * height),
                        new Point(origin.X + points.Max(point => point.X) * width, origin.Y + points.Max(point => point.Y) * height));
                }
                if (NoteBadgeGeometry.TryLeader(outline, badge, out var from, out var to,
                        isComment ? NoteBadgeGeometry.AnchorRadius * scale : 0))
                    dc.DrawLine(new Pen(badgeBrush, NoteBadgeGeometry.ExportLeaderThickness(displayLabel)), from, to);
                // The dot after the line, as on screen, so the line does not lie over the circle.
                if (isComment)
                    dc.DrawEllipse(badgeBrush, new Pen(Brushes.White, 1.5 * scale), anchor,
                        NoteBadgeGeometry.AnchorRadius * scale, NoteBadgeGeometry.AnchorRadius * scale);
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

    // Where a mark is pinned, in the pixels of the exported picture. The badge hangs off this point
    // and the dot of a comment is drawn on it; on two copies of the sum they would drift apart.
    private static Point ExportAnchor(Snapik.Core.Models.AnnotationItem item, int width, int height, Point origin) =>
        new(origin.X + item.Points[0].X * width, origin.Y + item.Points[0].Y * height);

    // The same circle the editor canvas shows, in the pixels of the exported picture.
    internal static NoteBadge ExportBadge(Snapik.Core.Models.AnnotationItem item, string displayLabel, int width, int height, Point origin)
    {
        var anchor = ExportAnchor(item, width, height, origin);
        var offset = item.NoteOffset is { } shift ? new Vector(shift.X * width, shift.Y * height) : default;
        // Nothing holds the badge under the header any more: the field between the two is exactly
        // where a badge carried off the top of the capture is meant to go.
        return NoteBadgeGeometry.Export(anchor, displayLabel, offset, double.NegativeInfinity);
    }

    private static void DrawText(DrawingContext dc, string text, double size, FontWeight weight, Brush brush, Point point, string family = "Segoe UI")
    {
        var formatted = new FormattedText(text, System.Globalization.CultureInfo.CurrentUICulture, FlowDirection.LeftToRight,
            new Typeface(new FontFamily(family), FontStyles.Normal, weight, FontStretches.Normal), size, brush, 1);
        dc.DrawText(formatted, point);
    }
}
