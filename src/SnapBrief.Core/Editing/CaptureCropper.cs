using System.Collections.Immutable;
using SnapBrief.Core.Models;

namespace SnapBrief.Core.Editing;

public readonly record struct NormalizedRect(double X, double Y, double Width, double Height)
{
    public double Left => X;
    public double Top => Y;
    public double Right => X + Width;
    public double Bottom => Y + Height;
}

public sealed record CropResult(
    CaptureItem PreviousCapture,
    CaptureItem CroppedCapture,
    ImmutableArray<Guid> RemovedAnnotationIds);

public static class CaptureCropper
{
    private const double Epsilon = 1e-12;

    public static CropResult Crop(
        CaptureItem source,
        NormalizedRect cropBounds,
        string croppedSourceImagePath,
        int croppedPixelWidth,
        int croppedPixelHeight)
    {
        ArgumentNullException.ThrowIfNull(source);
        ValidateCrop(cropBounds, croppedSourceImagePath, croppedPixelWidth, croppedPixelHeight);

        var retained = ImmutableArray.CreateBuilder<AnnotationItem>();
        var removed = ImmutableArray.CreateBuilder<Guid>();
        foreach (var annotation in source.Annotations)
        {
            if (annotation.Kind is AnnotationKind.Freehand or AnnotationKind.Highlight)
            {
                var croppedSegments = CropPolyline(annotation.GetPathSegments(), cropBounds);
                if (croppedSegments.IsEmpty)
                {
                    removed.Add(annotation.Id);
                }
                else
                {
                    retained.Add(annotation with
                    {
                        Points = croppedSegments[0],
                        PathSegments = croppedSegments.Length > 1 ? croppedSegments : []
                    });
                }
                continue;
            }

            var croppedPoints = annotation.Kind switch
            {
                AnnotationKind.Arrow => CropLine(annotation.Points, cropBounds),
                AnnotationKind.Rectangle or AnnotationKind.Text or AnnotationKind.Redaction or AnnotationKind.Blur or AnnotationKind.Comment =>
                    CropBox(annotation.Points, cropBounds),
                _ => ImmutableArray<NormalizedPoint>.Empty
            };

            if (croppedPoints.IsEmpty)
            {
                removed.Add(annotation.Id);
            }
            else
            {
                retained.Add(annotation with { Points = croppedPoints });
            }
        }

        var retainedIds = retained.Select(annotation => annotation.Id).ToHashSet();
        for (var i = 0; i < retained.Count; i++)
            if (retained[i].ParentAnnotationId is { } parentId && !retainedIds.Contains(parentId))
                retained[i] = retained[i] with { ParentAnnotationId = null };

        // The badge offset is normalized against the image, and the crop makes the image smaller:
        // the same shift in pixels is a bigger fraction of the cropped picture.
        for (var i = 0; i < retained.Count; i++)
            if (retained[i].NoteOffset is { } offset)
                retained[i] = retained[i] with
                {
                    NoteOffset = new NormalizedPoint(offset.X / cropBounds.Width, offset.Y / cropBounds.Height)
                };

        var cropped = source with
        {
            SourceImagePath = croppedSourceImagePath,
            PixelWidth = croppedPixelWidth,
            PixelHeight = croppedPixelHeight,
            Annotations = retained.ToImmutable()
        };
        return new CropResult(source, cropped, removed.ToImmutable());
    }

    private static ImmutableArray<NormalizedPoint> CropLine(
        ImmutableArray<NormalizedPoint> points,
        NormalizedRect crop)
    {
        if (points.Length < 2 || !TryClipSegment(points[0], points[1], crop, out var start, out var end) ||
            Distance(start, end) <= Epsilon)
        {
            return ImmutableArray<NormalizedPoint>.Empty;
        }

        return [MapToCrop(start, crop), MapToCrop(end, crop)];
    }

    private static ImmutableArray<NormalizedPoint> CropBox(
        ImmutableArray<NormalizedPoint> points,
        NormalizedRect crop)
    {
        if (points.Length < 2)
        {
            return ImmutableArray<NormalizedPoint>.Empty;
        }

        var left = Math.Max(Math.Min(points[0].X, points[1].X), crop.Left);
        var top = Math.Max(Math.Min(points[0].Y, points[1].Y), crop.Top);
        var right = Math.Min(Math.Max(points[0].X, points[1].X), crop.Right);
        var bottom = Math.Min(Math.Max(points[0].Y, points[1].Y), crop.Bottom);
        if (right - left <= Epsilon || bottom - top <= Epsilon)
        {
            return ImmutableArray<NormalizedPoint>.Empty;
        }

        return [MapToCrop(new(left, top), crop), MapToCrop(new(right, bottom), crop)];
    }

    private static ImmutableArray<ImmutableArray<NormalizedPoint>> CropPolyline(
        ImmutableArray<ImmutableArray<NormalizedPoint>> paths,
        NormalizedRect crop)
    {
        var runs = new List<List<NormalizedPoint>>();
        foreach (var points in paths)
        {
            List<NormalizedPoint>? current = null;
            for (var index = 1; index < points.Length; index++)
            {
                if (!TryClipSegment(points[index - 1], points[index], crop, out var start, out var end) ||
                    Distance(start, end) <= Epsilon)
                {
                    FinishRun(ref current, runs);
                    continue;
                }

                if (current is null || Distance(current[^1], start) > Epsilon)
                {
                    FinishRun(ref current, runs);
                    current = [start];
                }
                if (Distance(current[^1], end) > Epsilon)
                {
                    current.Add(end);
                }
            }
            FinishRun(ref current, runs);
        }

        return runs
            .Where(run => run.Count >= 2)
            .Where(run => PolylineLength(run) > Epsilon)
            .Select(run => run.Select(point => MapToCrop(point, crop)).ToImmutableArray())
            .ToImmutableArray();
    }

    private static void FinishRun(ref List<NormalizedPoint>? current, List<List<NormalizedPoint>> runs)
    {
        if (current is { Count: >= 2 })
        {
            runs.Add(current);
        }
        current = null;
    }

    private static bool TryClipSegment(
        NormalizedPoint start,
        NormalizedPoint end,
        NormalizedRect crop,
        out NormalizedPoint clippedStart,
        out NormalizedPoint clippedEnd)
    {
        var deltaX = end.X - start.X;
        var deltaY = end.Y - start.Y;
        var minimum = 0d;
        var maximum = 1d;

        if (!ClipTest(-deltaX, start.X - crop.Left, ref minimum, ref maximum) ||
            !ClipTest(deltaX, crop.Right - start.X, ref minimum, ref maximum) ||
            !ClipTest(-deltaY, start.Y - crop.Top, ref minimum, ref maximum) ||
            !ClipTest(deltaY, crop.Bottom - start.Y, ref minimum, ref maximum))
        {
            clippedStart = default;
            clippedEnd = default;
            return false;
        }

        clippedStart = new(start.X + minimum * deltaX, start.Y + minimum * deltaY);
        clippedEnd = new(start.X + maximum * deltaX, start.Y + maximum * deltaY);
        return true;
    }

    private static bool ClipTest(double denominator, double numerator, ref double minimum, ref double maximum)
    {
        if (Math.Abs(denominator) <= Epsilon)
        {
            return numerator >= 0;
        }

        var ratio = numerator / denominator;
        if (denominator < 0)
        {
            if (ratio > maximum) return false;
            if (ratio > minimum) minimum = ratio;
        }
        else
        {
            if (ratio < minimum) return false;
            if (ratio < maximum) maximum = ratio;
        }
        return true;
    }

    private static NormalizedPoint MapToCrop(NormalizedPoint point, NormalizedRect crop) => new(
        Math.Clamp((point.X - crop.Left) / crop.Width, 0, 1),
        Math.Clamp((point.Y - crop.Top) / crop.Height, 0, 1));

    private static double PolylineLength(IReadOnlyList<NormalizedPoint> points)
    {
        var length = 0d;
        for (var index = 1; index < points.Count; index++)
        {
            length += Distance(points[index - 1], points[index]);
        }
        return length;
    }

    private static double Distance(NormalizedPoint first, NormalizedPoint second)
    {
        var x = second.X - first.X;
        var y = second.Y - first.Y;
        return Math.Sqrt(x * x + y * y);
    }

    private static void ValidateCrop(NormalizedRect crop, string sourcePath, int pixelWidth, int pixelHeight)
    {
        if (!double.IsFinite(crop.X) || !double.IsFinite(crop.Y) ||
            !double.IsFinite(crop.Width) || !double.IsFinite(crop.Height) ||
            crop.X < 0 || crop.Y < 0 || crop.Width <= 0 || crop.Height <= 0 ||
            crop.Right > 1 || crop.Bottom > 1)
        {
            throw new ArgumentOutOfRangeException(nameof(crop), "Crop bounds must be a positive rectangle within normalized [0, 1] image space.");
        }

        ArgumentException.ThrowIfNullOrWhiteSpace(sourcePath);
        if (Path.IsPathRooted(sourcePath) || sourcePath.Split(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar).Contains(".."))
        {
            throw new ArgumentException("Cropped source image path must remain relative to the session directory.", nameof(sourcePath));
        }
        if (pixelWidth <= 0) throw new ArgumentOutOfRangeException(nameof(pixelWidth));
        if (pixelHeight <= 0) throw new ArgumentOutOfRangeException(nameof(pixelHeight));
    }
}
