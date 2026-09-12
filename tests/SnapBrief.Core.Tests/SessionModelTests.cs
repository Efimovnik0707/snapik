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

    [Fact]
    public void Captures_without_notes_get_no_section_and_a_silent_session_gets_no_text()
    {
        var silent = CaptureItem.Create("source/a.png", 100, 100) with
        {
            Annotations = [AnnotationItem.Create(AnnotationKind.Rectangle, [new(0.2, 0.2), new(0.4, 0.4)])]
        };
        var noted = CaptureItem.Create("source/b.png", 100, 100) with
        {
            Annotations = [AnnotationItem.Create(AnnotationKind.Arrow, [new(0.1, 0.2), new(0.8, 0.9)], note: "Сделать шире")]
        };
        var silentSession = SessionOperations.AddCapture(SnapBriefSession.Create(Start), silent, Start);
        var mixedSession = SessionOperations.AddCapture(silentSession, noted, Start.AddSeconds(1));

        Assert.Equal(string.Empty, new PromptGenerator().Generate(silentSession));

        var prompt = new PromptGenerator().Generate(mixedSession);

        Assert.DoesNotContain("Снимок A", prompt, StringComparison.Ordinal);
        Assert.Contains("Снимок B.", prompt, StringComparison.Ordinal);
        Assert.Contains("B1: Сделать шире", prompt, StringComparison.Ordinal);
        Assert.Equal(
            "Общее пожелание:\nСохранить цвета",
            new PromptGenerator().Generate(silentSession with { GlobalNote = "Сохранить цвета" }));
    }

    [Fact]
    public void Sent_captures_leave_the_package_and_give_their_letters_to_the_waiting_ones()
    {
        var first = CaptureItem.Create("source/first.png", 100, 100) with { Sent = true };
        var second = CaptureItem.Create("source/second.png", 100, 100);
        var third = CaptureItem.Create("source/third.png", 100, 100) with { Sent = true };
        var fourth = CaptureItem.Create("source/fourth.png", 100, 100);
        CaptureItem[] captures = [first, second, third, fourth];

        var package = SentCaptureRules.ForPackage(captures, capture => capture.Sent);
        var labels = SentCaptureRules.StripLabels([.. captures.Select(capture => capture.Sent)]);

        Assert.Equal([second.Id, fourth.Id], package.Select(capture => capture.Id));
        Assert.Equal([null, "A", null, "B"], labels);
        Assert.Equal(["A", "B"], SentCaptureRules.StripLabels([false, false]));
        Assert.Empty(SentCaptureRules.ForPackage(captures, _ => true));
    }

    private sealed class FrozenTimeProvider(DateTimeOffset value) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => value;
    }
}
