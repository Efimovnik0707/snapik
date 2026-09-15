using Snapik.Core.Persistence;

namespace Snapik.Infrastructure.Persistence;

public sealed class SessionAssetStore(ISessionStore sessionStore) : ISessionAssetStore
{
    private static readonly byte[] PngSignature = [137, 80, 78, 71, 13, 10, 26, 10];

    public async Task<string> SaveOriginalPngAsync(
        Guid sessionId,
        Guid captureId,
        Stream pngContent,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(pngContent);
        if (!pngContent.CanRead)
        {
            throw new ArgumentException("PNG content stream must be readable.", nameof(pngContent));
        }

        var relativePath = Path.Combine("source", $"{captureId:N}.png");
        var sourceDirectory = Path.Combine(sessionStore.GetSessionDirectory(sessionId), "source");
        Directory.CreateDirectory(sourceDirectory);
        var destination = Path.Combine(sourceDirectory, $"{captureId:N}.png");
        var temporary = Path.Combine(sourceDirectory, $".{captureId:N}-{Guid.NewGuid():N}.tmp");

        try
        {
            await using (var output = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 65536, FileOptions.Asynchronous))
            {
                await pngContent.CopyToAsync(output, cancellationToken);
            }

            await ValidatePngAsync(temporary, cancellationToken);
            File.Move(temporary, destination, true);
            return relativePath;
        }
        finally
        {
            if (File.Exists(temporary))
            {
                File.Delete(temporary);
            }
        }
    }

    private static async Task ValidatePngAsync(string path, CancellationToken cancellationToken)
    {
        var signature = new byte[PngSignature.Length];
        await using var stream = File.OpenRead(path);
        var bytesRead = await stream.ReadAsync(signature, cancellationToken);
        if (bytesRead != signature.Length || !signature.SequenceEqual(PngSignature))
        {
            throw new InvalidDataException("Capture content is not a PNG image.");
        }
    }
}
