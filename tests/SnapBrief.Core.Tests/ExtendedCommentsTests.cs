using System.Collections.Immutable;
using SnapBrief.Core.Exporting;
using SnapBrief.Core.Models;
using SnapBrief.Infrastructure.Serialization;

namespace SnapBrief.Core.Tests;

public sealed class ExtendedCommentsTests
{
    [Theory]
    [InlineData(0, "A")]
    [InlineData(25, "Z")]
    [InlineData(26, "AA")]
    [InlineData(299, "KN")]
    public void Labels_extend_beyond_one_alphabet(int index, string expected) => Assert.Equal(expected, CaptureLabels.ForIndex(index));

    [Fact]
    public void Hundreds_of_comments_preserve_identity_links_and_arrow_style_in_json()
    {
        var parent = AnnotationItem.Create(AnnotationKind.Arrow, [new(.1, .1), new(.5, .5)], note: "Область") with { ArrowStyle = "curved" };
        var notes = Enumerable.Range(0, 300).Select(i => AnnotationItem.Create(AnnotationKind.Comment,
            [new(.2, .2), new(.21, .21)], note: $"Комментарий {i}") with { ParentAnnotationId = parent.Id }).ToImmutableArray();
        var capture = CaptureItem.Create("source/a.png", 1000, 1000) with { Annotations = notes.Insert(0, parent) };
        var session = SnapBriefSession.Create(DateTimeOffset.UtcNow) with { Captures = [capture] };
        var json = System.Text.Json.JsonSerializer.Serialize(session, SnapBriefJson.Options);
        var restored = System.Text.Json.JsonSerializer.Deserialize<SnapBriefSession>(json, SnapBriefJson.Options)!;
        Assert.Equal("curved", restored.Captures[0].Annotations[0].ArrowStyle);
        Assert.All(restored.Captures[0].Annotations.Skip(1), a => Assert.Equal(parent.Id, a.ParentAnnotationId));
        var prompt = new PromptGenerator().Generate(restored);
        Assert.Contains("A301: Комментарий 299 (к области A1)", prompt);
    }

    [Fact]
    public void Note_offset_survives_json_and_stays_null_in_a_session_written_without_it()
    {
        var moved = AnnotationItem.Create(AnnotationKind.Comment, [new(.2, .2), new(.21, .21)], note: "Сдвинутая")
            with { NoteOffset = new NormalizedPoint(-.08, .15) };
        var capture = CaptureItem.Create("source/a.png", 1000, 1000) with { Annotations = [moved] };
        var session = SnapBriefSession.Create(DateTimeOffset.UtcNow) with { Captures = [capture] };
        var json = System.Text.Json.JsonSerializer.Serialize(session, SnapBriefJson.Options);
        var restored = System.Text.Json.JsonSerializer.Deserialize<SnapBriefSession>(json, SnapBriefJson.Options)!;
        Assert.Equal(new NormalizedPoint(-.08, .15), restored.Captures[0].Annotations[0].NoteOffset);

        var legacy = System.Text.Json.Nodes.JsonNode.Parse(json)!;
        legacy["captures"]![0]!["annotations"]![0]!.AsObject().Remove("noteOffset");
        var beforeTheField = System.Text.Json.JsonSerializer.Deserialize<SnapBriefSession>(legacy.ToJsonString(), SnapBriefJson.Options)!;
        Assert.Null(beforeTheField.Captures[0].Annotations[0].NoteOffset);
        SessionValidation.Validate(beforeTheField);
        SessionValidation.Validate(restored);
    }

    [Fact]
    public void Shape_and_fill_survive_json_and_default_for_a_session_written_without_them()
    {
        var oval = AnnotationItem.Create(AnnotationKind.Rectangle, [new(.1, .1), new(.6, .4)])
            with { Shape = AnnotationShape.Ellipse, Fill = AnnotationFill.Translucent };
        var capture = CaptureItem.Create("source/a.png", 1000, 1000) with { Annotations = [oval] };
        var session = SnapBriefSession.Create(DateTimeOffset.UtcNow) with { Captures = [capture] };
        var json = System.Text.Json.JsonSerializer.Serialize(session, SnapBriefJson.Options);
        Assert.Contains("\"shape\": \"ellipse\"", json);
        Assert.Contains("\"fill\": \"translucent\"", json);
        var restored = System.Text.Json.JsonSerializer.Deserialize<SnapBriefSession>(json, SnapBriefJson.Options)!;
        Assert.Equal(AnnotationShape.Ellipse, restored.Captures[0].Annotations[0].Shape);
        Assert.Equal(AnnotationFill.Translucent, restored.Captures[0].Annotations[0].Fill);

        var legacy = System.Text.Json.Nodes.JsonNode.Parse(json)!;
        var written = legacy["captures"]![0]!["annotations"]![0]!.AsObject();
        written.Remove("shape");
        written.Remove("fill");
        var beforeTheFields = System.Text.Json.JsonSerializer.Deserialize<SnapBriefSession>(legacy.ToJsonString(), SnapBriefJson.Options)!;
        Assert.Equal(AnnotationShape.Rectangle, beforeTheFields.Captures[0].Annotations[0].Shape);
        Assert.Equal(AnnotationFill.None, beforeTheFields.Captures[0].Annotations[0].Fill);
        SessionValidation.Validate(beforeTheFields);
    }

    // The preview window checked these two rules on its own list of comments. The window is gone,
    // so the rules are checked here, on the labels the export itself hands out.
    [Fact]
    public void An_empty_note_claims_no_label_and_numbering_closes_the_gap_after_a_deletion()
    {
        var first = AnnotationItem.Create(AnnotationKind.Rectangle, [new(.1, .1), new(.2, .2)], note: "Первый");
        var blank = AnnotationItem.Create(AnnotationKind.Comment, [new(.3, .3), new(.31, .31)]);
        var second = AnnotationItem.Create(AnnotationKind.Comment, [new(.4, .4), new(.41, .41)], note: "Второй");
        var capture = CaptureItem.Create("source/a.png", 1000, 1000) with { Annotations = [first, blank, second] };

        var labels = CaptureLabels.ForNotedAnnotations("A", capture).ToArray();
        Assert.Equal(["A1", "A2"], labels.Select(item => item.DisplayLabel));
        Assert.DoesNotContain(blank.Id, labels.Select(item => item.Annotation.Id));

        var afterDeletion = capture with { Annotations = capture.Annotations.Remove(first) };
        var remaining = CaptureLabels.ForNotedAnnotations("A", afterDeletion).ToArray();
        Assert.Equal(["A1"], remaining.Select(item => item.DisplayLabel));
        Assert.Equal(second.Id, remaining.Single().Annotation.Id);
    }

    [Fact]
    public void Cropping_keeps_comment_but_clears_a_removed_parent_link()
    {
        var parent = AnnotationItem.Create(AnnotationKind.Rectangle, [new(.8, .8), new(.9, .9)]);
        var comment = AnnotationItem.Create(AnnotationKind.Comment, [new(.1, .1), new(.11, .11)], note: "Keep") with { ParentAnnotationId = parent.Id };
        var capture = CaptureItem.Create("source/a.png", 1000, 1000) with { Annotations = [parent, comment] };
        var cropped = SnapBrief.Core.Editing.CaptureCropper.Crop(capture, new(0, 0, .5, .5), "source/crop.png", 500, 500).CroppedCapture;
        Assert.Equal(comment.Id, Assert.Single(cropped.Annotations).Id);
        Assert.Null(cropped.Annotations[0].ParentAnnotationId);
        Assert.Equal("Keep", cropped.Annotations[0].Note);
    }
}

