using System.Collections.Immutable;

namespace Snapik.Core.Models;

public sealed record CaptureItem(
    Guid Id,
    string SourceImagePath,
    int PixelWidth,
    int PixelHeight,
    double DpiX,
    double DpiY,
    string Title,
    string Note,
    ImmutableArray<AnnotationItem> Annotations)
{
    /// <summary>The capture was already pasted as part of a package; it stays in the strip, but out of the next one.</summary>
    public bool Sent { get; init; }

    public static CaptureItem Create(
        string sourceImagePath,
        int pixelWidth,
        int pixelHeight,
        double dpiX = 96,
        double dpiY = 96,
        string? title = null,
        string? note = null) =>
        new(
            Guid.NewGuid(),
            sourceImagePath,
            pixelWidth,
            pixelHeight,
            dpiX,
            dpiY,
            title ?? string.Empty,
            note ?? string.Empty,
            ImmutableArray<AnnotationItem>.Empty);
}

