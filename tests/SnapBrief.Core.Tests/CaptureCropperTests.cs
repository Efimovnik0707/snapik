using SnapBrief.Core.Editing;
using SnapBrief.Core.Models;

namespace SnapBrief.Core.Tests;

public sealed class CaptureCropperTests
{
    [Fact]
    public void Crop_preserves_identity_and_notes_clips_geometry_and_reports_removed_annotations()
    {
        var arrow = AnnotationItem.Create(AnnotationKind.Arrow, [new(0.1, 0.5), new(0.9, 0.5)], note: "Arrow note");
        var box = AnnotationItem.Create(AnnotationKind.Blur, [new(0.1, 0.1), new(0.4, 0.4)], note: "Blur note");
        var outside = AnnotationItem.Create(AnnotationKind.Redaction, [new(0.8, 0.8), new(0.9, 0.9)], note: "Outside");
        var source = CaptureItem.Create("source/original.png", 1000, 800, 144, 144, "Title", "Capture note") with
        {
            Annotations = [arrow, box, outside]
        };

        var result = CaptureCropper.Crop(source, new(0.25, 0.25, 0.5, 0.5), "source/cropped.png", 500, 400);

        Assert.Same(source, result.PreviousCapture);
        Assert.Equal(source.Id, result.CroppedCapture.Id);
        Assert.Equal(source.Title, result.CroppedCapture.Title);
        Assert.Equal(source.Note, result.CroppedCapture.Note);
        Assert.Equal(source.DpiX, result.CroppedCapture.DpiX);
        Assert.Equal(source.DpiY, result.CroppedCapture.DpiY);
        Assert.Equal("source/cropped.png", result.CroppedCapture.SourceImagePath);
        Assert.Equal((500, 400), (result.CroppedCapture.PixelWidth, result.CroppedCapture.PixelHeight));
        Assert.Equal([arrow.Id, box.Id], result.CroppedCapture.Annotations.Select(item => item.Id));
        Assert.Equal([outside.Id], result.RemovedAnnotationIds.ToArray());

        AssertPoint(result.CroppedCapture.Annotations[0].Points[0], 0, 0.5);
        AssertPoint(result.CroppedCapture.Annotations[0].Points[1], 1, 0.5);
        AssertPoint(result.CroppedCapture.Annotations[1].Points[0], 0, 0);
        AssertPoint(result.CroppedCapture.Annotations[1].Points[1], 0.3, 0.3);
    }

    [Fact]
    public void Crop_preserves_all_visible_polyline_runs_without_joining_disconnected_segments()
    {
        var stroke = AnnotationItem.Create(AnnotationKind.Freehand,
        [
            new(0.3, 0.3), new(0.4, 0.4), new(0.8, 0.4),
            new(0.8, 0.6), new(0.4, 0.6), new(0.5, 0.5), new(0.6, 0.4)
        ]);
        var source = CaptureItem.Create("source/original.png", 100, 100) with { Annotations = [stroke] };

        var result = CaptureCropper.Crop(source, new(0.25, 0.25, 0.5, 0.5), "source/crop.png", 50, 50);

        var cropped = result.CroppedCapture.Annotations.Single();
        var segments = cropped.GetPathSegments();
        Assert.Equal(2, segments.Length);
        Assert.Equal(segments[0].ToArray(), cropped.Points.ToArray());
        Assert.NotEqual(segments[0][^1], segments[1][0]);
        Assert.All(segments.SelectMany(segment => segment), point =>
        {
            Assert.InRange(point.X, 0, 1);
            Assert.InRange(point.Y, 0, 1);
        });
        Assert.DoesNotContain(result.RemovedAnnotationIds, id => id == stroke.Id);
        Assert.Same(source, result.PreviousCapture);
        Assert.Empty(source.Annotations[0].PathSegments);
        Assert.Equal(stroke.Points.ToArray(), source.Annotations[0].Points.ToArray());
    }

    [Fact]
    public void Crop_rescales_the_note_offset_to_the_smaller_image()
    {
        var moved = AnnotationItem.Create(AnnotationKind.Comment, [new(0.4, 0.4), new(0.41, 0.41)], note: "Moved")
            with { NoteOffset = new NormalizedPoint(0.1, -0.05) };
        var source = CaptureItem.Create("source/original.png", 1000, 800) with { Annotations = [moved] };

        var cropped = CaptureCropper.Crop(source, new(0.25, 0.25, 0.5, 0.25), "source/crop.png", 500, 200).CroppedCapture;

        // The same shift in pixels is twice the fraction of a half-wide crop, four times that of a
        // quarter-high one; the badge must not walk away from the mark when the picture is cropped.
        AssertPoint(cropped.Annotations[0].NoteOffset!.Value, 0.2, -0.2);
        Assert.Equal(new NormalizedPoint(0.1, -0.05), source.Annotations[0].NoteOffset);
    }

    [Fact]
    public void Crop_keeps_the_fill_colour_and_the_outline_flag_of_a_region()
    {
        var concealed = AnnotationItem.Create(AnnotationKind.Rectangle, [new(0.3, 0.3), new(0.6, 0.6)]) with
        {
            Shape = AnnotationShape.Ellipse, Fill = AnnotationFill.Solid, FillColor = "#FF000000", HasOutline = false
        };
        var source = CaptureItem.Create("source/original.png", 1000, 800) with { Annotations = [concealed] };

        var cropped = CaptureCropper.Crop(source, new(0.25, 0.25, 0.5, 0.5), "source/crop.png", 500, 400).CroppedCapture;

        var annotation = Assert.Single(cropped.Annotations);
        Assert.Equal(AnnotationShape.Ellipse, annotation.Shape);
        Assert.Equal(AnnotationFill.Solid, annotation.Fill);
        Assert.Equal("#FF000000", annotation.FillColor);
        Assert.False(annotation.HasOutline);
    }

    [Fact]
    public void Crop_keeps_the_size_a_caption_was_typed_in()
    {
        var caption = AnnotationItem.Create(AnnotationKind.Text, [new(0.3, 0.3), new(0.6, 0.4)], text: "Привет") with
        {
            FontSize = 48
        };
        var source = CaptureItem.Create("source/original.png", 1000, 800) with { Annotations = [caption] };

        var cropped = CaptureCropper.Crop(source, new(0.25, 0.25, 0.5, 0.5), "source/crop.png", 500, 400).CroppedCapture;

        var annotation = Assert.Single(cropped.Annotations);
        Assert.Equal(48, annotation.FontSize);
        Assert.Equal("Привет", annotation.Text);
    }

    [Fact]
    public void Crop_rejects_invalid_bounds_without_mutating_the_source()
    {
        var source = CaptureItem.Create("source/original.png", 100, 100);

        Assert.Throws<ArgumentOutOfRangeException>(() =>
            CaptureCropper.Crop(source, new(0.75, 0.75, 0.5, 0.5), "source/crop.png", 50, 50));
        Assert.Equal("source/original.png", source.SourceImagePath);
        Assert.Equal((100, 100), (source.PixelWidth, source.PixelHeight));
    }

    private static void AssertPoint(NormalizedPoint actual, double expectedX, double expectedY)
    {
        Assert.Equal(expectedX, actual.X, 10);
        Assert.Equal(expectedY, actual.Y, 10);
    }
}
