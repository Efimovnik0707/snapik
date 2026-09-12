using System.Collections.Immutable;

namespace SnapBrief.Core.Models;

public enum AnnotationKind
{
    Arrow,
    Rectangle,
    Highlight,
    Freehand,
    Text,
    Redaction,
    Blur,
    Comment
}

public readonly record struct NormalizedPoint(double X, double Y);

public sealed record AnnotationItem(
    Guid Id,
    AnnotationKind Kind,
    ImmutableArray<NormalizedPoint> Points,
    string StrokeColor,
    double Thickness,
    string Text,
    string Note)
{
    public Guid? ParentAnnotationId { get; init; }
    public string ArrowStyle { get; init; } = "straight";

    // Where the user dragged the numbered badge of this mark, as a shift from the place the
    // renderer picks by itself, in fractions of the image size. Null means automatic placement,
    // so a session written before the field reads back exactly as it did.
    public NormalizedPoint? NoteOffset { get; init; }
    public ImmutableArray<ImmutableArray<NormalizedPoint>> PathSegments { get; init; } = [];

    public ImmutableArray<ImmutableArray<NormalizedPoint>> GetPathSegments() =>
        !PathSegments.IsDefaultOrEmpty
            ? PathSegments
            : Points.IsDefaultOrEmpty
                ? []
                : [Points];

    public static AnnotationItem Create(
        AnnotationKind kind,
        IEnumerable<NormalizedPoint> points,
        string strokeColor = "#FF3B30",
        double thickness = 3,
        string? text = null,
        string? note = null) =>
        new(Guid.NewGuid(), kind, points.ToImmutableArray(), strokeColor, thickness, text ?? string.Empty, note ?? string.Empty);
}
