using System.Collections.Immutable;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Snapik.Core.Exporting;
using Snapik.Core.Models;
using Snapik.Infrastructure.Serialization;

namespace Snapik.Infrastructure.Exporting;

public sealed class FileExportService(IExportImageRenderer renderer, TimeProvider? timeProvider = null) : IExportService
{
    private static readonly byte[] PngSignature = [137, 80, 78, 71, 13, 10, 26, 10];
    private readonly TimeProvider _timeProvider = timeProvider ?? TimeProvider.System;

    public async Task<PreparedExport> PrepareAsync(
        SnapikSession session,
        string sessionDirectory,
        CancellationToken cancellationToken = default)
    {
        SessionValidation.Validate(session);
        if (session.Captures.IsEmpty)
        {
            throw new InvalidOperationException("Cannot export a session without captures.");
        }

        ArgumentException.ThrowIfNullOrWhiteSpace(sessionDirectory);
        var sessionRoot = Path.GetFullPath(sessionDirectory);
        var exportId = Guid.NewGuid();
        var exportsRoot = Path.Combine(sessionRoot, "exports");
        var staging = Path.Combine(exportsRoot, $".staging-{exportId:N}");
        var finalDirectory = Path.Combine(exportsRoot, $"revision-{session.Revision:D6}-{exportId:N}");
        Directory.CreateDirectory(staging);

        try
        {
            var images = ImmutableArray.CreateBuilder<ExportImageEntry>(session.Captures.Length);
            for (var index = 0; index < session.Captures.Length; index++)
            {
                cancellationToken.ThrowIfCancellationRequested();
                var capture = session.Captures[index];
                var label = CaptureLabels.ForIndex(index);
                // The user opens these files in a folder of their own: "01-A.png" sorts and reads
                // like a page number. The guid of the capture stays in manifest.images[].captureId.
                var fileName = $"{index + 1:D2}-{label}.png";
                var imagePath = Path.Combine(staging, fileName);
                var sourceImagePath = ResolveSessionPath(sessionRoot, capture.SourceImagePath);
                if (!File.Exists(sourceImagePath))
                {
                    throw new FileNotFoundException("Capture source image does not exist.", sourceImagePath);
                }

                await using (var output = new FileStream(imagePath, FileMode.CreateNew, FileAccess.Write, FileShare.None, 65536, FileOptions.Asynchronous))
                {
                    await renderer.RenderAsync(capture, new ExportImageContext(label, index, sourceImagePath), output, cancellationToken);
                }

                await ValidatePngAsync(imagePath, cancellationToken);
                var imageInfo = new FileInfo(imagePath);
                images.Add(new ExportImageEntry(capture.Id, label, fileName, await Sha256Async(imagePath, cancellationToken), imageInfo.Length));
            }

            // Captures without notes produce no text at all: the package is then images only, and
            // an empty prompt.md would just be an empty file for the user to open.
            var promptText = new PromptGenerator().Generate(session);
            var promptFileName = promptText.Length == 0 ? string.Empty : "prompt.md";
            var promptSha256 = string.Empty;
            if (promptText.Length > 0)
            {
                var promptPath = Path.Combine(staging, promptFileName);
                await File.WriteAllTextAsync(promptPath, promptText, new UTF8Encoding(false), cancellationToken);
                promptSha256 = await Sha256Async(promptPath, cancellationToken);
            }

            var manifest = new ExportManifest(
                exportId,
                session.Id,
                session.Revision,
                _timeProvider.GetUtcNow(),
                images.MoveToImmutable(),
                promptFileName,
                promptSha256,
                promptText,
                session.Captures.Length,
                CountNotes(session));

            var manifestPath = Path.Combine(staging, "manifest.json");
            await using (var manifestStream = new FileStream(manifestPath, FileMode.CreateNew, FileAccess.Write, FileShare.None, 65536, FileOptions.Asynchronous))
            {
                await JsonSerializer.SerializeAsync(manifestStream, manifest, SnapikJson.Options, cancellationToken);
            }

            Directory.Move(staging, finalDirectory);
            return new PreparedExport(finalDirectory, manifest);
        }
        catch
        {
            if (Directory.Exists(staging))
            {
                Directory.Delete(staging, true);
            }

            throw;
        }
    }

    private static int CountNotes(SnapikSession session) =>
        (ExportText.HasContent(session.GlobalNote) ? 1 : 0) +
        session.Captures.Sum(capture =>
            (ExportText.HasContent(capture.Note) ? 1 : 0) +
            capture.Annotations.Count(annotation => ExportText.HasContent(annotation.Note)));

    private static string ResolveSessionPath(string sessionRoot, string relativePath)
    {
        var resolved = Path.GetFullPath(Path.Combine(sessionRoot, relativePath));
        var rootPrefix = Path.TrimEndingDirectorySeparator(sessionRoot) + Path.DirectorySeparatorChar;
        if (!resolved.StartsWith(rootPrefix, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidDataException("Capture image path escapes the session directory.");
        }

        return resolved;
    }

    private static async Task ValidatePngAsync(string path, CancellationToken cancellationToken)
    {
        var signature = new byte[PngSignature.Length];
        await using var stream = File.OpenRead(path);
        var bytesRead = await stream.ReadAsync(signature, cancellationToken);
        if (bytesRead != signature.Length || !signature.SequenceEqual(PngSignature))
        {
            throw new InvalidDataException("The export renderer did not produce a PNG image.");
        }
    }

    private static async Task<string> Sha256Async(string path, CancellationToken cancellationToken)
    {
        await using var stream = File.OpenRead(path);
        var hash = await SHA256.HashDataAsync(stream, cancellationToken);
        return Convert.ToHexStringLower(hash);
    }
}
