using System.Collections.Immutable;

namespace Snapik.Core.Models;

// Title is the name of the file an imported capture came from; a region and a whole-screen shot
// leave it empty, and the words under a whole-screen shot are built from Kind instead.
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

    /// <summary>Where the capture came from. An init property and not a positional one: a session
    /// written before 1.5.0 has no "kind" at all and reads back as a region, without a migration.</summary>
    public CaptureKind Kind { get; init; } = CaptureKind.Region;

    /// <summary>How many monitors the whole-screen shot covered; 0 means "not known" and is what
    /// every other kind carries. A negative number from a foreign file dies here, which is why
    /// SessionValidation knows nothing about this field.</summary>
    public int MonitorCount { get => field; init => field = Math.Max(0, value); }

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

