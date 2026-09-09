using SnapBrief.Core.Editing;
using SnapBrief.Core.Exporting;
using SnapBrief.Core.Models;

namespace SnapBrief.Core.Tests;

public sealed class SessionModelTests
{
    private static readonly DateTimeOffset Start = new(2026, 9, 8, 20, 0, 0, TimeSpan.Zero);

    [Fact]
    public void Reorder_remove_and_undo_preserve_capture_identity_and_labels_follow_order()
    {
        var first = CaptureItem.Create("source/first.png", 100, 100, title: "Первый");
        var second = CaptureItem.Create("source/second.png", 100, 100, title: "Второй");
        var session = SessionOperations.AddCapture(SnapBriefSession.Create(Start), first, Start.AddMinutes(1));
        session = SessionOperations.AddCapture(session, second, Start.AddMinutes(2));
        var history = new SessionHistory(session, new FrozenTimeProvider(Start.AddMinutes(10)));

        history.Apply(value => SessionOperations.MoveCapture(value, second.Id, 0, Start.AddMinutes(3)));
        history.Apply(value => SessionOperations.RemoveCapture(value, first.Id, Start.AddMinutes(4)));

        Assert.Single(history.Current.Captures);
        Assert.Equal(second.Id, history.Current.Captures[0].Id);
        Assert.True(history.Undo());
        Assert.Equal([second.Id, first.Id], history.Current.Captures.Select(capture => capture.Id));
        Assert.Equal(5, history.Current.Revision);

        var prompt = new PromptGenerator().Generate(history.Current);
        Assert.Contains("Снимок A — Второй.", prompt, StringComparison.Ordinal);
        Assert.Contains("Снимок B — Первый.", prompt, StringComparison.Ordinal);
    }

    [Fact]
    public void Prompt_preserves_unicode_line_breaks_and_skips_empty_annotation_notes()
    {
        var capture = CaptureItem.Create("source/a.png", 100, 100, note: "Строка 1\nСтрока 2 🙂") with
        {
            Annotations =
            [
                AnnotationItem.Create(AnnotationKind.Arrow, [new(0.1, 0.2), new(0.8, 0.9)], note: "Сделать шире"),
                AnnotationItem.Create(AnnotationKind.Rectangle, [new(0.2, 0.2), new(0.4, 0.4)])
            ]
        };
        var session = SessionOperations.AddCapture(SnapBriefSession.Create(Start), capture, Start) with
        {
            GlobalNote = "Сохранить цвета"
        };

        var prompt = new PromptGenerator().Generate(session);

        Assert.Contains("Сохранить цвета", prompt, StringComparison.Ordinal);
        Assert.Contains("Строка 1\nСтрока 2 🙂", prompt, StringComparison.Ordinal);
        Assert.Contains("A1: Сделать шире", prompt, StringComparison.Ordinal);
        Assert.DoesNotContain("A2:", prompt, StringComparison.Ordinal);
        Assert.Equal(
            ["A1"],
            CaptureLabels.ForNotedAnnotations("A", capture).Select(item => item.DisplayLabel));
    }

    private sealed class FrozenTimeProvider(DateTimeOffset value) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => value;
    }
}
