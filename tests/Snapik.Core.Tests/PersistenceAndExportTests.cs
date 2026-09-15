using System.Collections.Concurrent;
using System.Collections.Immutable;
using System.Text.Json;
using System.Text.Json.Nodes;
using Snapik.Core.Editing;
using Snapik.Core.Exporting;
using Snapik.Core.Models;
using Snapik.Infrastructure.Exporting;
using Snapik.Infrastructure.Persistence;
using Snapik.Infrastructure.Serialization;

namespace Snapik.Core.Tests;

public sealed class PersistenceAndExportTests : IDisposable
{
    private static readonly DateTimeOffset Start = new(2026, 9, 8, 20, 0, 0, TimeSpan.Zero);
    private readonly string _root = Path.Combine(Path.GetTempPath(), $"snapik-tests-{Guid.NewGuid():N}");

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
        var session = SessionOperations.AddCapture(SnapikSession.Create(Start), capture, Start.AddSeconds(1));

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
        var session = SessionOperations.AddCapture(SnapikSession.Create(Start), capture, Start);
        var json = JsonNode.Parse(JsonSerializer.Serialize(session, SnapikJson.Options))!.AsObject();
        var annotationJson = json["captures"]!.AsArray()[0]!["annotations"]!.AsArray()[0]!.AsObject();
        Assert.True(annotationJson.Remove("pathSegments"));

        var directory = store.GetSessionDirectory(session.Id);
        Directory.CreateDirectory(directory);
        await File.WriteAllTextAsync(Path.Combine(directory, "session.json"), json.ToJsonString(SnapikJson.Options));

        var restored = await store.LoadAsync(session.Id);

        var restoredAnnotation = Assert.Single(Assert.Single(restored!.Captures).Annotations);
        Assert.Empty(restoredAnnotation.PathSegments);
        var fallback = Assert.Single(restoredAnnotation.GetPathSegments());
        Assert.Equal(annotation.Points.ToArray(), fallback.ToArray());
        Assert.Equal(annotation.Id, restoredAnnotation.Id);
        Assert.Equal(annotation.Note, restoredAnnotation.Note);
    }

    [Fact]
    public async Task Json_store_round_trips_the_size_a_caption_was_typed_in()
    {
        var store = new JsonSessionStore(Path.Combine(_root, "sessions"));
        var caption = AnnotationItem.Create(AnnotationKind.Text, [new(0.1, 0.1), new(0.4, 0.2)], text: "Привет") with
        {
            FontSize = 32
        };
        var capture = CaptureItem.Create("source/capture.png", 800, 600) with { Annotations = [caption] };
        var session = SessionOperations.AddCapture(SnapikSession.Create(Start), capture, Start);

        await store.SaveAsync(session);
        var restored = await store.LoadAsync(session.Id);

        // The name in the file matters as much as the value: the Mac port reads the same key.
        Assert.Contains("\"fontSize\": 32", JsonSerializer.Serialize(session, SnapikJson.Options), StringComparison.Ordinal);
        var restoredCaption = restored!.Captures[0].Annotations[0];
        Assert.Equal(32, restoredCaption.FontSize);
        Assert.Equal("Привет", restoredCaption.Text);
        SessionValidation.Validate(restored);
    }

    [Fact]
    public async Task Json_store_reads_a_caption_written_before_the_size_existed()
    {
        var sessionsRoot = Path.Combine(_root, "sessions");
        var store = new JsonSessionStore(sessionsRoot);
        var caption = AnnotationItem.Create(AnnotationKind.Text, [new(0.1, 0.1), new(0.4, 0.2)], text: "Старая надпись");
        var capture = CaptureItem.Create("source/capture.png", 800, 600) with { Annotations = [caption] };
        var session = SessionOperations.AddCapture(SnapikSession.Create(Start), capture, Start);
        var json = JsonNode.Parse(JsonSerializer.Serialize(session, SnapikJson.Options))!.AsObject();
        Assert.True(json["captures"]!.AsArray()[0]!["annotations"]!.AsArray()[0]!.AsObject().Remove("fontSize"));
        var directory = store.GetSessionDirectory(session.Id);
        Directory.CreateDirectory(directory);
        await File.WriteAllTextAsync(Path.Combine(directory, "session.json"), json.ToJsonString(SnapikJson.Options));

        var restored = await store.LoadAsync(session.Id);

        var restoredCaption = Assert.Single(Assert.Single(restored!.Captures).Annotations);
        Assert.Equal(20, restoredCaption.FontSize);
        SessionValidation.Validate(restored);
    }

    [Fact]
    public async Task Json_store_round_trips_the_pattern_of_a_stroke_and_defaults_it_to_solid()
    {
        var store = new JsonSessionStore(Path.Combine(_root, "sessions"));
        var dotted = AnnotationItem.Create(AnnotationKind.Rectangle, [new(0.1, 0.1), new(0.4, 0.4)]) with
        {
            LineStyle = AnnotationLineStyle.Dotted
        };
        var plain = AnnotationItem.Create(AnnotationKind.Arrow, [new(0.5, 0.5), new(0.9, 0.9)]);
        var capture = CaptureItem.Create("source/capture.png", 800, 600) with { Annotations = [dotted, plain] };
        var session = SessionOperations.AddCapture(SnapikSession.Create(Start), capture, Start);

        await store.SaveAsync(session);
        var restored = await store.LoadAsync(session.Id);

        // The name in the file matters as much as the value: the Mac port reads the same key.
        Assert.Contains("\"lineStyle\": \"dotted\"", JsonSerializer.Serialize(session, SnapikJson.Options), StringComparison.Ordinal);
        Assert.Equal(AnnotationLineStyle.Dotted, restored!.Captures[0].Annotations[0].LineStyle);
        Assert.Equal(AnnotationLineStyle.Solid, restored.Captures[0].Annotations[1].LineStyle);
        SessionValidation.Validate(restored);

        // A session written before the field existed reads as solid, which is what it was drawn as.
        var json = JsonNode.Parse(JsonSerializer.Serialize(session, SnapikJson.Options))!.AsObject();
        Assert.True(json["captures"]!.AsArray()[0]!["annotations"]!.AsArray()[0]!.AsObject().Remove("lineStyle"));
        var directory = store.GetSessionDirectory(session.Id);
        Directory.CreateDirectory(directory);
        await File.WriteAllTextAsync(Path.Combine(directory, "session.json"), json.ToJsonString(SnapikJson.Options));
        var reread = await store.LoadAsync(session.Id);
        Assert.Equal(AnnotationLineStyle.Solid, reread!.Captures[0].Annotations[0].LineStyle);
    }

    // An enum read from a file can only be one of its own names; one built in code can be anything,
    // and a pattern nobody knows would be drawn as nothing at all.
    [Fact]
    public void A_line_style_outside_the_enumeration_is_refused()
    {
        var broken = AnnotationItem.Create(AnnotationKind.Rectangle, [new(0.1, 0.1), new(0.4, 0.4)]) with
        {
            LineStyle = (AnnotationLineStyle)77
        };
        var capture = CaptureItem.Create("source/capture.png", 800, 600) with { Annotations = [broken] };

        // Every change of a session is validated on the way in, so the capture never reaches one.
        Assert.Throws<InvalidDataException>(() => SessionOperations.AddCapture(SnapikSession.Create(Start), capture, Start));
    }

    [Fact]
    public async Task Json_store_round_trips_the_fill_colour_the_outline_flag_and_the_blur_fill()
    {
        var store = new JsonSessionStore(Path.Combine(_root, "sessions"));
        var concealed = AnnotationItem.Create(AnnotationKind.Rectangle, [new(0.1, 0.1), new(0.4, 0.4)]) with
        {
            Fill = AnnotationFill.Solid, FillColor = "#FF000000", HasOutline = false
        };
        var blurred = AnnotationItem.Create(AnnotationKind.Rectangle, [new(0.5, 0.5), new(0.9, 0.9)]) with
        {
            Shape = AnnotationShape.Ellipse, Fill = AnnotationFill.Blur
        };
        var capture = CaptureItem.Create("source/capture.png", 800, 600) with { Annotations = [concealed, blurred] };
        var session = SessionOperations.AddCapture(SnapikSession.Create(Start), capture, Start);

        await store.SaveAsync(session);
        var restored = await store.LoadAsync(session.Id);

        // The names in the file matter as much as the values: the Mac port reads the same three keys.
        var json = JsonSerializer.Serialize(session, SnapikJson.Options);
        Assert.Contains("\"fill\": \"blur\"", json, StringComparison.Ordinal);
        Assert.Contains("\"fillColor\": \"#FF000000\"", json, StringComparison.Ordinal);
        Assert.Contains("\"hasOutline\": false", json, StringComparison.Ordinal);
        var restoredConcealed = restored!.Captures[0].Annotations[0];
        Assert.Equal(AnnotationFill.Solid, restoredConcealed.Fill);
        Assert.Equal("#FF000000", restoredConcealed.FillColor);
        Assert.False(restoredConcealed.HasOutline);
        var restoredBlurred = restored.Captures[0].Annotations[1];
        Assert.Equal(AnnotationFill.Blur, restoredBlurred.Fill);
        Assert.Null(restoredBlurred.FillColor);
        Assert.True(restoredBlurred.HasOutline);
        SessionValidation.Validate(restored);
    }

    [Fact]
    public async Task Json_store_reads_a_session_without_the_fill_fields_and_one_that_still_holds_a_redaction()
    {
        var store = new JsonSessionStore(Path.Combine(_root, "sessions"));
        var box = AnnotationItem.Create(AnnotationKind.Rectangle, [new(0.1, 0.1), new(0.4, 0.4)]);
        var redaction = AnnotationItem.Create(AnnotationKind.Redaction, [new(0.5, 0.5), new(0.8, 0.8)]);
        var capture = CaptureItem.Create("source/capture.png", 800, 600) with { Annotations = [box, redaction] };
        var session = SessionOperations.AddCapture(SnapikSession.Create(Start), capture, Start);
        var json = JsonNode.Parse(JsonSerializer.Serialize(session, SnapikJson.Options))!.AsObject();
        foreach (var annotation in json["captures"]!.AsArray()[0]!["annotations"]!.AsArray())
        {
            var item = annotation!.AsObject();
            item.Remove("fill");
            item.Remove("fillColor");
            Assert.True(item.Remove("hasOutline"));
        }
        var directory = store.GetSessionDirectory(session.Id);
        Directory.CreateDirectory(directory);
        await File.WriteAllTextAsync(Path.Combine(directory, "session.json"), json.ToJsonString(SnapikJson.Options));

        var restored = await store.LoadAsync(session.Id);

        // A file written before the fill carried a colour reads exactly as it did: no fill, no colour
        // of its own, and an outline. The redaction kind stays readable for the editor to migrate.
        var restoredBox = restored!.Captures[0].Annotations[0];
        Assert.Equal(AnnotationFill.None, restoredBox.Fill);
        Assert.Null(restoredBox.FillColor);
        Assert.True(restoredBox.HasOutline);
        Assert.Equal(AnnotationKind.Redaction, restored.Captures[0].Annotations[1].Kind);
        SessionValidation.Validate(restored);
    }

    [Fact]
    public async Task Json_store_round_trips_the_sent_flag_and_reads_a_file_written_without_it()
    {
        var sessionsRoot = Path.Combine(_root, "sessions");
        var store = new JsonSessionStore(sessionsRoot);
        var sent = CaptureItem.Create("source/sent.png", 100, 100) with { Sent = true };
        var waiting = CaptureItem.Create("source/waiting.png", 100, 100);
        var session = SessionOperations.AddCapture(SnapikSession.Create(Start), sent, Start);
        session = SessionOperations.AddCapture(session, waiting, Start.AddSeconds(1));

        await store.SaveAsync(session);
        var restored = await store.LoadAsync(session.Id);

        Assert.True(restored!.Captures[0].Sent);
        Assert.False(restored.Captures[1].Sent);

        var json = JsonNode.Parse(JsonSerializer.Serialize(session, SnapikJson.Options))!.AsObject();
        foreach (var capture in json["captures"]!.AsArray()) Assert.True(capture!.AsObject().Remove("sent"));
        var legacy = session with { Id = Guid.NewGuid() };
        json["id"] = legacy.Id.ToString("D");
        var directory = store.GetSessionDirectory(legacy.Id);
        Directory.CreateDirectory(directory);
        await File.WriteAllTextAsync(Path.Combine(directory, "session.json"), json.ToJsonString(SnapikJson.Options));

        var restoredLegacy = await store.LoadAsync(legacy.Id);

        Assert.All(restoredLegacy!.Captures, capture => Assert.False(capture.Sent));
    }

    [Fact]
    public async Task Overlapping_saves_commit_the_latest_invocation_even_when_revisions_repeat()
    {
        var store = new JsonSessionStore(Path.Combine(_root, "sessions"));
        var capture = CaptureItem.Create("source/capture.png", 100, 100);
        var baseline = SessionOperations.AddCapture(SnapikSession.Create(Start), capture, Start);
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
        var session = SessionOperations.AddCapture(SnapikSession.Create(Start), first, Start);
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
        // The user opens these files by name: a two-digit index and the letter of the capture.
        Assert.Equal(["01-A.png", "02-B.png"], prepared.Manifest.Images.Select(image => image.FileName));
        Assert.All(prepared.GetImagePathsInOrder(), path => Assert.True(File.Exists(path)));
        Assert.Equal(2, prepared.Manifest.CaptureCount);
        Assert.Equal(2, prepared.Manifest.NoteCount);
        Assert.All(prepared.Manifest.Images, image => Assert.Equal(64, image.Sha256.Length));
        Assert.Equal(originalPrompt, await File.ReadAllTextAsync(Path.Combine(prepared.RootDirectory, "prompt.md")));
        Assert.DoesNotContain("Новое пожелание", prepared.Manifest.PromptText, StringComparison.Ordinal);
        Assert.NotEqual(session.Revision, changed.Revision);
        Assert.DoesNotContain(Directory.EnumerateFiles(prepared.RootDirectory), path => Path.GetFileName(path).Contains("source", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public async Task A_package_without_notes_carries_images_only_and_writes_no_prompt_file()
    {
        var service = new FileExportService(new RecordingPngRenderer(new ConcurrentQueue<string>()), new FrozenTimeProvider(Start));
        var capture = CaptureItem.Create("source/a.png", 800, 600);
        var session = SessionOperations.AddCapture(SnapikSession.Create(Start), capture, Start);
        var sessionDirectory = Path.Combine(_root, "session");
        Directory.CreateDirectory(Path.Combine(sessionDirectory, "source"));
        await File.WriteAllBytesAsync(Path.Combine(sessionDirectory, capture.SourceImagePath), RecordingPngRenderer.OnePixelPng);

        var prepared = await service.PrepareAsync(session, sessionDirectory);

        Assert.Equal(string.Empty, prepared.Manifest.PromptText);
        Assert.Equal(string.Empty, prepared.Manifest.PromptFileName);
        Assert.Equal(string.Empty, prepared.Manifest.PromptSha256);
        Assert.False(File.Exists(Path.Combine(prepared.RootDirectory, "prompt.md")));
        Assert.Single(prepared.Manifest.Images);
    }

    [Fact]
    public async Task Invalid_renderer_output_does_not_publish_a_partial_revision()
    {
        var service = new FileExportService(new InvalidRenderer());
        var capture = CaptureItem.Create("source/a.png", 10, 10);
        var session = SessionOperations.AddCapture(SnapikSession.Create(Start), capture, Start);
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
        var session = SessionOperations.AddCapture(SnapikSession.Create(Start), capture, Start) with
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
