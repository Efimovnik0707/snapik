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

// The outline a boxed mark is drawn with, and what stands inside it. Two properties instead of new
// kinds: the crop, the validation and the hit test keep working on the same box, and a build that
// does not know them draws the plain rectangle it always drew.
public enum AnnotationShape
{
    Rectangle,
    Rounded,
    Ellipse
}

public enum AnnotationFill
{
    None,
    Solid,
    Translucent
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

    public AnnotationShape Shape { get; init; } = AnnotationShape.Rectangle;
    public AnnotationFill Fill { get; init; } = AnnotationFill.None;
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
