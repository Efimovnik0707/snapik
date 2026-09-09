using System.Collections.Concurrent;
using System.Collections.Immutable;
using System.Text.Json;
using System.Text.Json.Nodes;
using SnapBrief.Core.Editing;
using SnapBrief.Core.Exporting;
using SnapBrief.Core.Models;
using SnapBrief.Infrastructure.Exporting;
using SnapBrief.Infrastructure.Persistence;
using SnapBrief.Infrastructure.Serialization;

namespace SnapBrief.Core.Tests;

public sealed class PersistenceAndExportTests : IDisposable
{
    private static readonly DateTimeOffset Start = new(2026, 9, 8, 20, 0, 0, TimeSpan.Zero);
    private readonly string _root = Path.Combine(Path.GetTempPath(), $"snapbrief-tests-{Guid.NewGuid():N}");

    [Fact]
    public async Task Json_store_round_trips_the_validated_session()
    {
        var store = new JsonSessionStore(Path.Combine(_root, "sessions"));
        var annotation = AnnotationItem.Create(
            AnnotationKind.Blur,
            [new(0.1, 0.2), new(0.8, 0.9)],
            note: "Увеличить кнопку");
        var firstRun = new[] { new NormalizedPoint(0.1, 0.1), new NormalizedPoint(0.4, 0.4) }.ToImmutableArray();
        var secondRun = new[] { new NormalizedPoint(0.6, 0.6), new NormalizedPoint(0.9, 0.9) }.ToImmutableArray();
        var segmented = AnnotationItem.Create(AnnotationKind.Freehand, firstRun, note: "Два штриха") with
        {
            PathSegments = [firstRun, secondRun]
        };
        var capture = CaptureItem.Create("source/capture.png", 1920, 1080) with { Annotations = [annotation, segmented] };
        var session = SessionOperations.AddCapture(SnapBriefSession.Create(Start), capture, Start.AddSeconds(1));

        await store.SaveAsync(session);
        var restored = await store.LoadAsync(session.Id);

        Assert.NotNull(restored);
        Assert.Equal(session.Id, restored.Id);
        Assert.Equal(session.Revision, restored.Revision);
        Assert.Equal(session.CreatedAtUtc, restored.CreatedAtUtc);
        Assert.Equal(session.ModifiedAtUtc, restored.ModifiedAtUtc);
        Assert.Equal(session.Captures.Select(item => item.Id), restored.Captures.Select(item => item.Id));
        Assert.Equal(annotation.Id, restored!.Captures[0].Annotations[0].Id);
        Assert.Equal(annotation.Note, restored.Captures[0].Annotations[0].Note);
        Assert.Equal(AnnotationKind.Blur, restored.Captures[0].Annotations[0].Kind);
        Assert.Equal(annotation.Points.ToArray(), restored.Captures[0].Annotations[0].Points.ToArray());
        var restoredSegmented = restored.Captures[0].Annotations[1];
        Assert.Equal(segmented.Id, restoredSegmented.Id);
        Assert.Equal(segmented.Note, restoredSegmented.Note);
        Assert.Equal(2, restoredSegmented.PathSegments.Length);
        Assert.Equal(firstRun.ToArray(), restoredSegmented.PathSegments[0].ToArray());
        Assert.Equal(secondRun.ToArray(), restoredSegmented.PathSegments[1].ToArray());
    }

    [Fact]
    public async Task Json_store_loads_schema_one_annotations_without_path_segments()
    {
        var sessionsRoot = Path.Combine(_root, "sessions");
        var store = new JsonSessionStore(sessionsRoot);
        var annotation = AnnotationItem.Create(
            AnnotationKind.Freehand,
            [new(0.1, 0.2), new(0.8, 0.9)],
            note: "Legacy stroke");
        var capture = CaptureItem.Create("source/capture.png", 100, 100) with { Annotations = [annotation] };
        var session = SessionOperations.AddCapture(SnapBriefSession.Create(Start), capture, Start);
        var json = JsonNode.Parse(JsonSerializer.Serialize(session, SnapBriefJson.Options))!.AsObject();
        var annotationJson = json["captures"]!.AsArray()[0]!["annotations"]!.AsArray()[0]!.AsObject();
        Assert.True(annotationJson.Remove("pathSegments"));

        var directory = store.GetSessionDirectory(session.Id);
        Directory.CreateDirectory(directory);
        await File.WriteAllTextAsync(Path.Combine(directory, "session.json"), json.ToJsonString(SnapBriefJson.Options));

        var restored = await store.LoadAsync(session.Id);

        var restoredAnnotation = Assert.Single(Assert.Single(restored!.Captures).Annotations);
        Assert.Empty(restoredAnnotation.PathSegments);
        var fallback = Assert.Single(restoredAnnotation.GetPathSegments());
        Assert.Equal(annotation.Points.ToArray(), fallback.ToArray());
        Assert.Equal(annotation.Id, restoredAnnotation.Id);
        Assert.Equal(annotation.Note, restoredAnnotation.Note);
    }

    [Fact]
    public async Task Overlapping_saves_commit_the_latest_invocation_even_when_revisions_repeat()
    {
        var store = new JsonSessionStore(Path.Combine(_root, "sessions"));
        var capture = CaptureItem.Create("source/capture.png", 100, 100);
        var baseline = SessionOperations.AddCapture(SnapBriefSession.Create(Start), capture, Start);
        var saves = Enumerable.Range(0, 40)
            .Select(index => store.SaveAsync(baseline with { GlobalNote = $"note-{index}" }))
            .ToArray();

        await Task.WhenAll(saves);
        var restored = await store.LoadAsync(baseline.Id);

        Assert.NotNull(restored);
        Assert.Equal("note-39", restored.GlobalNote);
        Assert.Equal(baseline.Revision, restored.Revision);
    }

    [Fact]
    public async Task Asset_store_publishes_a_valid_png_under_a_stable_relative_capture_path()
    {
        var sessionStore = new JsonSessionStore(Path.Combine(_root, "sessions"));
        var assetStore = new SessionAssetStore(sessionStore);
        var sessionId = Guid.NewGuid();
        var captureId = Guid.NewGuid();
        await using var content = new MemoryStream(RecordingPngRenderer.OnePixelPng);

        var relativePath = await assetStore.SaveOriginalPngAsync(sessionId, captureId, content);

        Assert.Equal(Path.Combine("source", $"{captureId:N}.png"), relativePath);
        Assert.True(File.Exists(Path.Combine(sessionStore.GetSessionDirectory(sessionId), relativePath)));
    }

    [Fact]
    public async Task Export_is_an_immutable_ordered_revision_with_hashes_and_no_sources()
    {
        var labelsSeen = new ConcurrentQueue<string>();
        var renderer = new RecordingPngRenderer(labelsSeen);
        var service = new FileExportService(renderer, new FrozenTimeProvider(Start));
        var first = CaptureItem.Create("source/one.png", 800, 600, note: "Первый комментарий");
        var second = CaptureItem.Create("source/two.png", 800, 600) with
        {
            Annotations = [AnnotationItem.Create(AnnotationKind.Rectangle, [new(0.1, 0.1), new(0.5, 0.5)], note: "Второй комментарий")]
        };
        var session = SessionOperations.AddCapture(SnapBriefSession.Create(Start), first, Start);
        session = SessionOperations.AddCapture(session, second, Start);
        var sessionDirectory = Path.Combine(_root, "session");
        Directory.CreateDirectory(Path.Combine(sessionDirectory, "source"));
        await File.WriteAllBytesAsync(Path.Combine(sessionDirectory, first.SourceImagePath), RecordingPngRenderer.OnePixelPng);
        await File.WriteAllBytesAsync(Path.Combine(sessionDirectory, second.SourceImagePath), RecordingPngRenderer.OnePixelPng);

        var prepared = await service.PrepareAsync(session, sessionDirectory);
        var originalPrompt = prepared.Manifest.PromptText;
        var changed = SessionOperations.UpdateGlobalNote(session, "Новое пожелание", Start.AddMinutes(1));

        Assert.Equal(["A", "B"], labelsSeen);
        Assert.Equal([first.Id, second.Id], prepared.Manifest.Images.Select(image => image.CaptureId));
        Assert.Equal(2, prepared.Manifest.CaptureCount);
        Assert.Equal(2, prepared.Manifest.NoteCount);
        Assert.All(prepared.Manifest.Images, image => Assert.Equal(64, image.Sha256.Length));
        Assert.Equal(originalPrompt, await File.ReadAllTextAsync(Path.Combine(prepared.RootDirectory, "prompt.md")));
        Assert.DoesNotContain("Новое пожелание", prepared.Manifest.PromptText, StringComparison.Ordinal);
        Assert.NotEqual(session.Revision, changed.Revision);
        Assert.DoesNotContain(Directory.EnumerateFiles(prepared.RootDirectory), path => Path.GetFileName(path).Contains("source", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public async Task Invalid_renderer_output_does_not_publish_a_partial_revision()
    {
        var service = new FileExportService(new InvalidRenderer());
        var capture = CaptureItem.Create("source/a.png", 10, 10);
        var session = SessionOperations.AddCapture(SnapBriefSession.Create(Start), capture, Start);
        var sessionDirectory = Path.Combine(_root, "session");
        Directory.CreateDirectory(Path.Combine(sessionDirectory, "source"));
        await File.WriteAllBytesAsync(Path.Combine(sessionDirectory, capture.SourceImagePath), RecordingPngRenderer.OnePixelPng);

        await Assert.ThrowsAsync<InvalidDataException>(() => service.PrepareAsync(session, sessionDirectory));

        var exports = Path.Combine(sessionDirectory, "exports");
        Assert.Empty(Directory.Exists(exports) ? Directory.EnumerateDirectories(exports) : []);
    }

    [Fact]
    public async Task Whitespace_only_notes_are_not_labeled_exported_or_counted_but_real_text_is_preserved()
    {
        var capture = CaptureItem.Create("source/a.png", 10, 10, note: " \t\r\n") with
        {
            Annotations =
            [
                AnnotationItem.Create(AnnotationKind.Arrow, [new(0.1, 0.1), new(0.2, 0.2)], note: "   "),
                AnnotationItem.Create(AnnotationKind.Rectangle, [new(0.2, 0.2), new(0.6, 0.6)], note: "  Реальная заметка  \n")
            ]
        };
        var session = SessionOperations.AddCapture(SnapBriefSession.Create(Start), capture, Start) with
        {
            GlobalNote = "\r\n\t"
        };
        var sessionDirectory = Path.Combine(_root, "whitespace-session");
        Directory.CreateDirectory(Path.Combine(sessionDirectory, "source"));
        await File.WriteAllBytesAsync(Path.Combine(sessionDirectory, capture.SourceImagePath), RecordingPngRenderer.OnePixelPng);

        var prepared = await new FileExportService(new RecordingPngRenderer(new ConcurrentQueue<string>()))
            .PrepareAsync(session, sessionDirectory);

        Assert.Equal(1, prepared.Manifest.NoteCount);
        Assert.DoesNotContain("Общее пожелание", prepared.Manifest.PromptText, StringComparison.Ordinal);
        Assert.DoesNotContain("Комментарий к снимку", prepared.Manifest.PromptText, StringComparison.Ordinal);
        Assert.Contains("A1:   Реальная заметка  \n", prepared.Manifest.PromptText, StringComparison.Ordinal);
        Assert.DoesNotContain("A2:", prepared.Manifest.PromptText, StringComparison.Ordinal);
    }

    public void Dispose()
    {
        if (Directory.Exists(_root))
        {
            Directory.Delete(_root, true);
        }
    }

    private sealed class RecordingPngRenderer(ConcurrentQueue<string> labelsSeen) : IExportImageRenderer
    {
        internal static readonly byte[] OnePixelPng = Convert.FromBase64String(
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=");

        public async Task RenderAsync(CaptureItem capture, ExportImageContext context, Stream destination, CancellationToken cancellationToken)
        {
            labelsSeen.Enqueue(context.DisplayLabel);
            await destination.WriteAsync(OnePixelPng, cancellationToken);
        }
    }

    private sealed class InvalidRenderer : IExportImageRenderer
    {
        public Task RenderAsync(CaptureItem capture, ExportImageContext context, Stream destination, CancellationToken cancellationToken) =>
            destination.WriteAsync("not-png"u8.ToArray(), cancellationToken).AsTask();
    }

    private sealed class FrozenTimeProvider(DateTimeOffset value) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => value;
    }
}
