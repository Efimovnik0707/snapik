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
            foreach (var annotation in capture.Annotations.Where(a => a.Kind is not (AnnotationKind.Blur or AnnotationKind.Redaction)))
                DrawAnnotation(dc, annotation, image.PixelWidth, image.PixelHeight, null, HeaderHeight, drawShape: true);
            foreach (var annotation in capture.Annotations.Where(a => a.Kind == AnnotationKind.Redaction))
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

    private static BitmapSource ApplyBlurAnnotations(BitmapSource source, CoreCaptureItem capture)
    {
        BitmapSource result = source;
        foreach (var item in capture.Annotations.Where(a => a.Kind == AnnotationKind.Blur && a.Points.Length > 1))
        {
            var left = Math.Clamp((int)Math.Floor(Math.Min(item.Points[0].X, item.Points[1].X) * source.PixelWidth), 0, source.PixelWidth);
            var top = Math.Clamp((int)Math.Floor(Math.Min(item.Points[0].Y, item.Points[1].Y) * source.PixelHeight), 0, source.PixelHeight);
            var right = Math.Clamp((int)Math.Ceiling(Math.Max(item.Points[0].X, item.Points[1].X) * source.PixelWidth), left, source.PixelWidth);
            var bottom = Math.Clamp((int)Math.Ceiling(Math.Max(item.Points[0].Y, item.Points[1].Y) * source.PixelHeight), top, source.PixelHeight);
            result = RegionBlur.Apply(result, new Int32Rect(left, top, right - left, bottom - top), Math.Clamp((int)Math.Round(item.Thickness * 3), 4, 36));
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
            var lineBrush = item.Kind == AnnotationKind.Highlight
                ? new SolidColorBrush(Color.FromArgb(90, color.R, color.G, color.B))
                : brush;
            var linePen = new Pen(lineBrush, item.Kind == AnnotationKind.Highlight ? item.Thickness * 4 : item.Thickness)
            { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round, LineJoin = PenLineJoin.Round };
            foreach (var segment in item.GetPathSegments())
                for (var i = 1; i < segment.Length; i++) dc.DrawLine(linePen, P(segment[i - 1]), P(segment[i]));
        }
        else if (drawShape && item.Points.Length > 1)
        {
            var start = P(item.Points[0]);
            var end = P(item.Points[1]);
            var rect = new Rect(start, end);
            switch (item.Kind)
            {
                case AnnotationKind.Rectangle: dc.DrawRectangle(null, pen, rect); break;
                case AnnotationKind.Redaction: dc.DrawRectangle(Brushes.Black, null, rect); break;
                case AnnotationKind.Text: DrawText(dc, item.Text, Math.Max(16, item.Thickness * 4.5), FontWeights.SemiBold, brush, start); break;
                case AnnotationKind.Arrow:
                    SnapBrief.App.Imaging.ArrowDrawing.Draw(dc, start, end, brush, item.Thickness, item.ArrowStyle);
                    break;
            }
        }

        if (!string.IsNullOrEmpty(displayLabel))
        {
            var anchor = P(item.Points[0]);
            var diameter = Math.Max(34, displayLabel.Length * 9 + 16);
            var center = new Point(anchor.X, Math.Max(diameter / 2 + 2, anchor.Y - diameter / 2 - 4));
            dc.DrawEllipse(new SolidColorBrush(Color.FromRgb(47, 140, 255)), null, center, diameter / 2, diameter / 2);
            var label = new FormattedText(displayLabel, System.Globalization.CultureInfo.CurrentUICulture, FlowDirection.LeftToRight,
                new Typeface(new FontFamily("Segoe UI"), FontStyles.Normal, FontWeights.Bold, FontStretches.Normal), 13, Brushes.White, 1);
            dc.DrawText(label, new Point(center.X - label.Width / 2, center.Y - label.Height / 2));
        }
    }

    private static void DrawText(DrawingContext dc, string text, double size, FontWeight weight, Brush brush, Point point)
    {
        var formatted = new FormattedText(text, System.Globalization.CultureInfo.CurrentUICulture, FlowDirection.LeftToRight,
            new Typeface(new FontFamily("Segoe UI"), FontStyles.Normal, weight, FontStretches.Normal), size, brush, 1);
        dc.DrawText(formatted, point);
    }
}
