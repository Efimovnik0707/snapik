using System.Text;
using System.Text.Json;
using SnapBrief.Core.Models;
using SnapBrief.Core.Persistence;
using SnapBrief.Infrastructure.Serialization;

namespace SnapBrief.Infrastructure.Persistence;

public sealed class JsonSessionStore : ISessionStore
{
    private readonly string _sessionsRoot;
    private readonly SemaphoreSlim _saveGate = new(1, 1);
    private readonly Dictionary<Guid, long> _committedSaveSequences = [];
    private long _nextSaveSequence;

    public JsonSessionStore(string sessionsRoot)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(sessionsRoot);
        _sessionsRoot = Path.GetFullPath(sessionsRoot);
    }

    public static JsonSessionStore CreateDefault()
    {
        var localData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        return new JsonSessionStore(Path.Combine(localData, "SnapBrief", "sessions"));
    }

    public string GetSessionDirectory(Guid sessionId) => Path.Combine(_sessionsRoot, sessionId.ToString("N"));

    public async Task SaveAsync(SnapBriefSession session, CancellationToken cancellationToken = default)
    {
        SessionValidation.Validate(session);
        var saveSequence = Interlocked.Increment(ref _nextSaveSequence);
        await _saveGate.WaitAsync(cancellationToken);

        try
        {
            if (_committedSaveSequences.TryGetValue(session.Id, out var committedSequence) && committedSequence >= saveSequence)
            {
                return;
            }

            var directory = GetSessionDirectory(session.Id);
            Directory.CreateDirectory(directory);
            var destination = Path.Combine(directory, "session.json");
            var temporary = Path.Combine(directory, $".session-{Guid.NewGuid():N}.tmp");

            try
            {
            await using (var stream = new FileStream(
                temporary,
                FileMode.CreateNew,
                FileAccess.Write,
                FileShare.None,
                65536,
                FileOptions.Asynchronous | FileOptions.WriteThrough))
            {
                await JsonSerializer.SerializeAsync(stream, session, SnapBriefJson.Options, cancellationToken);
                await stream.FlushAsync(cancellationToken);
            }

            File.Move(temporary, destination, true);
                _committedSaveSequences[session.Id] = saveSequence;
            }
            finally
            {
                if (File.Exists(temporary))
                {
                    File.Delete(temporary);
                }
            }
        }
        finally
        {
            _saveGate.Release();
        }
    }

    public async Task<SnapBriefSession?> LoadAsync(Guid sessionId, CancellationToken cancellationToken = default)
    {
        var path = Path.Combine(GetSessionDirectory(sessionId), "session.json");
        if (!File.Exists(path))
        {
            return null;
        }

        await using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 65536, FileOptions.Asynchronous);
        var session = await JsonSerializer.DeserializeAsync<SnapBriefSession>(stream, SnapBriefJson.Options, cancellationToken)
            ?? throw new InvalidDataException("Session JSON did not contain a session.");
        SessionValidation.Validate(session);
        return session;
    }
}
