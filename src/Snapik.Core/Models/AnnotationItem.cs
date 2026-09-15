using System.Collections.Immutable;
using System.Text.Json.Serialization;

namespace Snapik.Core.Models;

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

// The pattern a stroke is drawn with: a frame, an oval, an arrow and a pencil have one, and a
// highlighter, a caption, a blur and a comment have no stroke to pattern. Absent means "solid",
// which is what every mark written before the field was drawn with.
public enum AnnotationLineStyle
{
    Solid,
    Dashed,
    Dotted
}

public enum AnnotationFill
{
    None,
    Solid,
    Translucent,
    Blur
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
    public AnnotationLineStyle LineStyle { get; init; } = AnnotationLineStyle.Solid;

    // What stands inside the box, as "#AARRGGBB". Absent means the colour of the outline, which is
    // what every mark written before the field carried.
    public string? FillColor { get; init; }

    // Read but never written any more: a build before 1.5.0 put "do not draw the frame" here. The
    // only value that still means anything is false on a rectangle, and it means "a solid fill of
    // one colour". The name of the key is spelled out because the camelCase policy would otherwise
    // write "legacyHasOutline" and the old files would stop being read.
    [JsonPropertyName("hasOutline")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public bool? LegacyHasOutline { get; init; }

    // The size a text mark is typed in, in the pixels of the capture, so the screen and the export
    // show the same letters. Absent means 20, which is what a mark written before the field gets;
    // the thickness of a text mark does not stand for its size any more.
    public double FontSize { get; init; } = 20;
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
