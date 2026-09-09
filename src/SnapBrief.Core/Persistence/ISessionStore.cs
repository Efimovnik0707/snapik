using SnapBrief.Core.Models;

namespace SnapBrief.Core.Persistence;

public interface ISessionStore
{
    string GetSessionDirectory(Guid sessionId);
    Task SaveAsync(SnapBriefSession session, CancellationToken cancellationToken = default);
    Task<SnapBriefSession?> LoadAsync(Guid sessionId, CancellationToken cancellationToken = default);
}

public interface ISessionAssetStore
{
    Task<string> SaveOriginalPngAsync(
        Guid sessionId,
        Guid captureId,
        Stream pngContent,
        CancellationToken cancellationToken = default);
}
