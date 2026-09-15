using Snapik.Core.Models;

namespace Snapik.Core.Persistence;

public interface ISessionStore
{
    string GetSessionDirectory(Guid sessionId);
    Task SaveAsync(SnapikSession session, CancellationToken cancellationToken = default);
    Task<SnapikSession?> LoadAsync(Guid sessionId, CancellationToken cancellationToken = default);
}

public interface ISessionAssetStore
{
    Task<string> SaveOriginalPngAsync(
        Guid sessionId,
        Guid captureId,
        Stream pngContent,
        CancellationToken cancellationToken = default);
}
