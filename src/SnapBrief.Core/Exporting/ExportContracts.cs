using System.Collections.Immutable;
using SnapBrief.Core.Models;

namespace SnapBrief.Core.Exporting;

public sealed record ExportImageEntry(
    Guid CaptureId,
    string DisplayLabel,
    string FileName,
    string Sha256,
    long ByteLength);

public sealed record ExportManifest(
    Guid ExportId,
    Guid SessionId,
    int Revision,
    DateTimeOffset CreatedAtUtc,
    ImmutableArray<ExportImageEntry> Images,
    string PromptFileName,
    string PromptSha256,
    string PromptText,
    int CaptureCount,
    int NoteCount);

public sealed record PreparedExport(string RootDirectory, ExportManifest Manifest)
{
    public IReadOnlyList<string> GetImagePathsInOrder() => Manifest.Images
        .Select(image => Path.GetFullPath(Path.Combine(RootDirectory, image.FileName)))
        .ToArray();
}

public sealed record ExportImageContext(string DisplayLabel, int CaptureIndex, string SourceImagePath);

public interface IExportImageRenderer
{
    Task RenderAsync(
        CaptureItem capture,
        ExportImageContext context,
        Stream destination,
        CancellationToken cancellationToken);
}

public interface IExportService
{
    Task<PreparedExport> PrepareAsync(
        SnapBriefSession session,
        string sessionDirectory,
        CancellationToken cancellationToken = default);
}
