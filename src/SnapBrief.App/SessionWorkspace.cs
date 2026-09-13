using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using SnapBrief.Core.Exporting;
using SnapBrief.Core.Models;
using SnapBrief.Core.Persistence;
using SnapBrief.Infrastructure.Exporting;
using SnapBrief.Infrastructure.Persistence;
using CoreCapture = SnapBrief.Core.Models.CaptureItem;

namespace SnapBrief.App;

public sealed class SessionWorkspace
{
    private readonly ISessionStore _store;
    private readonly ISessionAssetStore _assets;
    private readonly string _root;
    private readonly string _currentPointer;
    private const int KeptExportRevisions = 3;
    private static readonly DateTime ProcessStartUtc = System.Diagnostics.Process.GetCurrentProcess().StartTime.ToUniversalTime();
    private int _revision;
    private DateTimeOffset _createdAtUtc;

    public SessionWorkspace(string? explicitRoot = null)
    {
        _root = Path.GetFullPath(explicitRoot ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SnapBrief", "sessions"));
        _store = new JsonSessionStore(_root);
        _assets = new SessionAssetStore(_store);
        _currentPointer = Path.Combine(_root, "current-session.txt");
        SettingsPath = Path.Combine(explicitRoot ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SnapBrief"), "settings.json");
        SessionId = Guid.NewGuid();
        _createdAtUtc = DateTimeOffset.UtcNow;
    }

    public string SettingsPath { get; }
    public HotkeySettings Preferences => HotkeySettings.Load(SettingsPath);
    public string RegionPath => Path.Combine(Path.GetDirectoryName(SettingsPath)!, "last-region.json");
    public Guid SessionId { get; private set; }
    public string SessionDirectory => _store.GetSessionDirectory(SessionId);
    public string RestoredGlobalNote { get; private set; } = string.Empty;
    public string? RestoredProfileId { get; private set; }

    /// <summary>
    /// The export directories that must outlive the trim: the one whose PNGs are on the clipboard
    /// and the one the prepared package points at. They diverge, and a manual "Copy package" or
    /// "Save package…" writes revisions of its own that could otherwise push either of them out.
    /// </summary>
    public IReadOnlyCollection<string> PinnedExportDirectories { get; set; } = [];

    public async Task<IReadOnlyList<CaptureItem>> LoadCurrentAsync(CancellationToken cancellationToken = default)
    {
        if (!File.Exists(_currentPointer)) return [];
        var text = await File.ReadAllTextAsync(_currentPointer, cancellationToken);
        if (!Guid.TryParse(text.Trim(), out var id)) return [];
        var session = await _store.LoadAsync(id, cancellationToken);
        if (session is null) return [];
        SessionId = session.Id;
        _revision = session.Revision;
        _createdAtUtc = session.CreatedAtUtc;
        RestoredGlobalNote = session.GlobalNote;
        RestoredProfileId = session.SelectedTargetProfileId;
        var result = new List<CaptureItem>();
        foreach (var capture in session.Captures)
        {
            var path = Path.GetFullPath(Path.Combine(SessionDirectory, capture.SourceImagePath));
            if (!File.Exists(path)) continue;
            result.Add(CaptureItem.FromCore(capture, LoadBitmap(path)));
        }
        return result;
    }

    /// <summary>
    /// A session lives for one run, so whatever the previous run left in the sessions root goes
    /// before this one starts: every subdirectory named as a GUID and the pointer at the last
    /// session. Anything else in that root (settings.json, last-region.json, the startup log of a
    /// run with --data-dir) belongs to the application, not to a session, and stays. A directory
    /// another process still holds is skipped and traced; the next start tries again. This also
    /// covers a run that was killed: nothing else has to clean up after it.
    /// </summary>
    public Task PurgePreviousSessionsAsync(Action<string>? trace = null, CancellationToken cancellationToken = default) => Task.Run(() =>
    {
        if (!Directory.Exists(_root)) return;
        // The listing is taken whole before the first deletion: enumerating a directory while its
        // contents are being removed may walk past entries, and a session skipped that way is never
        // reported anywhere.
        foreach (var directory in Directory.GetDirectories(_root))
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (!Guid.TryParseExact(Path.GetFileName(directory), "N", out _)) continue;
            TryDeleteDirectory(directory, trace);
        }
        TryDeletePointer(trace);
    }, cancellationToken);

    /// <summary>
    /// Removes the directory of the current session with everything in it (session.json, the
    /// originals and every exports/revision-*) and starts a session of its own instead. Separate
    /// from <see cref="StartNewSessionAsync"/> on purpose: rotating a session keeps the previous one
    /// on disk, and only this call is meant to delete. The caller gives the clipboard back first:
    /// the published package is a list of paths into the directory that goes here.
    /// </summary>
    public Task DiscardCurrentSessionAsync(Action<string>? trace = null, CancellationToken cancellationToken = default) => Task.Run(() =>
    {
        TryDeleteDirectory(SessionDirectory, trace);
        TryDeletePointer(trace);
        SessionId = Guid.NewGuid();
        _revision = 0;
        _createdAtUtc = DateTimeOffset.UtcNow;
        RestoredGlobalNote = string.Empty;
        RestoredProfileId = null;
        PinnedExportDirectories = [];
    }, cancellationToken);

    private static void TryDeleteDirectory(string directory, Action<string>? trace)
    {
        if (!Directory.Exists(directory)) return;
        try { Directory.Delete(directory, true); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            trace?.Invoke($"Session cleanup: {Path.GetFileName(directory)} stayed on disk: {ex.Message}");
        }
    }

    private void TryDeletePointer(Action<string>? trace)
    {
        try { File.Delete(_currentPointer); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            trace?.Invoke($"Session cleanup: the current-session pointer stayed on disk: {ex.Message}");
        }
    }

    public async Task<CaptureItem> AddImageAsync(BitmapSource source, CancellationToken cancellationToken = default)
    {
        source.Freeze();
        var id = Guid.NewGuid();
        var sessionId = SessionId;
        await using var output = await EncodePngAsync(source, cancellationToken);
        var relative = await _assets.SaveOriginalPngAsync(sessionId, id, output, cancellationToken);
        return new CaptureItem { Id = id, Image = source, SourcePath = relative };
    }

    public async Task<string> SaveDerivedImageAsync(BitmapSource source, CancellationToken cancellationToken = default)
    {
        source.Freeze();
        var sessionId = SessionId;
        await using var output = await EncodePngAsync(source, cancellationToken);
        return await _assets.SaveOriginalPngAsync(sessionId, Guid.NewGuid(), output, cancellationToken);
    }

    private static Task<MemoryStream> EncodePngAsync(BitmapSource frozenSource, CancellationToken cancellationToken) => Task.Run(() =>
    {
        cancellationToken.ThrowIfCancellationRequested();
        var output = new MemoryStream();
        try
        {
            var encoder = new PngBitmapEncoder();
            encoder.Frames.Add(BitmapFrame.Create(frozenSource));
            encoder.Save(output);
            cancellationToken.ThrowIfCancellationRequested();
            output.Position = 0;
            return output;
        }
        catch { output.Dispose(); throw; }
    }, cancellationToken);
    public async Task SaveAsync(IEnumerable<CaptureItem> captures, string globalNote, string? profileId, CancellationToken cancellationToken = default)
    {
        var session = CreateSnapshot(captures, globalNote, profileId);
        await SaveSnapshotAsync(session, cancellationToken);
    }

    public async Task StartNewSessionAsync(
        IEnumerable<CaptureItem> currentCaptures,
        string globalNote,
        string? profileId,
        CancellationToken cancellationToken = default)
    {
        await SaveAsync(currentCaptures, globalNote, profileId, cancellationToken);

        var nextSession = SnapBriefSession.Create(DateTimeOffset.UtcNow);
        await SaveSnapshotAsync(nextSession, cancellationToken);

        SessionId = nextSession.Id;
        _revision = nextSession.Revision;
        _createdAtUtc = nextSession.CreatedAtUtc;
        RestoredGlobalNote = string.Empty;
        RestoredProfileId = null;
    }

    public Task<PreparedExport> PrepareAsync(IEnumerable<CaptureItem> captures, string globalNote, string? profileId, CancellationToken cancellationToken = default) =>
        PrepareAsync(captures, null, globalNote, profileId, cancellationToken);

    /// <summary>
    /// The whole strip is what gets persisted; <paramref name="packageCaptures"/> (null means all of
    /// them) is the part that goes into the exported package, so sent captures stay in session.json.
    /// </summary>
    public async Task<PreparedExport> PrepareAsync(
        IEnumerable<CaptureItem> captures,
        IEnumerable<CaptureItem>? packageCaptures,
        string globalNote,
        string? profileId,
        CancellationToken cancellationToken = default)
    {
        var session = CreateSnapshot(captures, globalNote, profileId);
        await SaveSnapshotAsync(session, cancellationToken);
        var exported = packageCaptures is null
            ? session
            : session with { Captures = packageCaptures.Select(capture => capture.ToCore()).ToImmutableArray() };
        var prepared = await new FileExportService(new WpfExportImageRenderer()).PrepareAsync(exported, SessionDirectory, cancellationToken);
        TrimExports(prepared.RootDirectory);
        return prepared;
    }

    // Every prepared package writes another exports/revision-* directory with a full copy of the
    // strip, and captures now live on across pastes, so only the newest few are kept. The directory
    // the current package points at and the pinned ones (the package on the clipboard and the
    // prepared one) are never removed, and a directory that refuses to go (a reader still holding a
    // file) is left for the next run.
    private void TrimExports(string currentPackageDirectory)
    {
        var exportsRoot = Path.Combine(SessionDirectory, "exports");
        if (!Directory.Exists(exportsRoot)) return;
        var keep = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { Path.GetFullPath(currentPackageDirectory) };
        foreach (var pinned in PinnedExportDirectories) keep.Add(Path.GetFullPath(pinned));
        var stale = Directory.EnumerateDirectories(exportsRoot, "revision-*")
            .Select(Path.GetFullPath)
            .OrderByDescending(ExportRevisionNumber)
            .Skip(KeptExportRevisions)
            .Where(path => !keep.Contains(path))
            // A .staging-* directory is removed by the export itself unless the process died in the
            // middle of writing it, so only the ones older than this process are safe to drop.
            .Concat(Directory.EnumerateDirectories(exportsRoot, ".staging-*")
                .Select(Path.GetFullPath)
                .Where(path => Directory.GetLastWriteTimeUtc(path) < ProcessStartUtc));
        foreach (var directory in stale)
        {
            try { Directory.Delete(directory, true); }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }
    }

    // revision-000123-{export id}: the revision number is what orders the directories. Sorting the
    // names as text keeps that order only while the number fits the padding it was written with.
    private static int ExportRevisionNumber(string directory)
    {
        var digits = Path.GetFileName(directory).AsSpan("revision-".Length);
        var end = 0;
        while (end < digits.Length && char.IsAsciiDigit(digits[end])) end++;
        return int.TryParse(digits[..end], out var revision) ? revision : 0;
    }

    private SnapBriefSession CreateSnapshot(IEnumerable<CaptureItem> captures, string globalNote, string? profileId)
    {
        var now = DateTimeOffset.UtcNow;
        var frozenCaptures = captures.Select(c => c.ToCore()).ToImmutableArray();
        return new SnapBriefSession(SessionId, SnapBriefSession.CurrentSchemaVersion, _createdAtUtc, now, ++_revision,
            globalNote, profileId, frozenCaptures);
    }

    private async Task SaveSnapshotAsync(SnapBriefSession session, CancellationToken cancellationToken)
    {
        await _store.SaveAsync(session, cancellationToken);
        Directory.CreateDirectory(_root);
        await File.WriteAllTextAsync(_currentPointer, session.Id.ToString("D"), cancellationToken);
    }

    public static BitmapSource LoadBitmap(string path)
    {
        using var stream = File.OpenRead(path);
        // WebP and other exotic formats decode only when the system ships a WIC codec for them, and
        // such a codec can also fail while producing the frame, not only while creating the decoder.
        try
        {
            var decoder = BitmapDecoder.Create(stream, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad);
            // Reported without wrapping the path in a Uri: a path the Uri parser rejects would replace
            // the real reason with a parsing error of its own.
            if (decoder.Frames.Count == 0) throw new NotSupportedException(UiLanguage.Text("Формат не поддерживается системой"));
            var frame = decoder.Frames[0];
            frame.Freeze();
            return frame;
        }
        catch (Exception ex) when (ex is NotSupportedException or FileFormatException)
        {
            throw new InvalidOperationException(UiLanguage.Text("Формат не поддерживается системой"), ex);
        }
    }

    public static BitmapSource CreateDemoBitmap(int index, int width = 1280, int height = 720, double dpi = 96)
    {
        var visual = new DrawingVisual();
        using (var dc = visual.RenderOpen())
        {
            dc.DrawRectangle(new SolidColorBrush(Color.FromRgb(245, 247, 250)), null, new System.Windows.Rect(0, 0, width, height));
            dc.DrawRectangle(new SolidColorBrush(Color.FromRgb(255, 255, 255)), null, new System.Windows.Rect(52, 48, width - 104, height - 96));
            dc.DrawRectangle(new SolidColorBrush(Color.FromRgb(232, 237, 246)), null, new System.Windows.Rect(52, 48, width - 104, 56));
            dc.DrawRectangle(new SolidColorBrush(Color.FromRgb(49, 92, 245)), null, new System.Windows.Rect(860 - index * 35, 540 - index * 28, 230, 62));
            var title = new FormattedText($"Тестовый экран {(char)('A' + index)}", System.Globalization.CultureInfo.CurrentUICulture,
                System.Windows.FlowDirection.LeftToRight, new Typeface("Segoe UI"), 31, new SolidColorBrush(Color.FromRgb(23, 32, 51)), 1);
            dc.DrawText(title, new System.Windows.Point(100, 150));
            var body = new FormattedText("Проверка SnapBrief: отдельный снимок и связанная заметка.", System.Globalization.CultureInfo.CurrentUICulture,
                System.Windows.FlowDirection.LeftToRight, new Typeface("Segoe UI"), 20, new SolidColorBrush(Color.FromRgb(94, 104, 122)), 1);
            dc.DrawText(body, new System.Windows.Point(100, 215));
        }
        var bitmap = new RenderTargetBitmap(width, height, dpi, dpi, PixelFormats.Pbgra32);
        bitmap.Render(visual);
        bitmap.Freeze();
        return bitmap;
    }
}
