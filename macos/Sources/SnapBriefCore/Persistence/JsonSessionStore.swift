import Foundation

/// Port of `src/SnapBrief.Infrastructure/Persistence/JsonSessionStore.cs`.
///
/// The C# implementation uses `SemaphoreSlim(1, 1)` plus an `Interlocked.Increment`-assigned save
/// sequence so that, under overlapping `SaveAsync` calls for the same session, the file always
/// ends up reflecting the call with the highest sequence number regardless of completion order
/// (`Overlapping_saves_commit_the_latest_invocation_even_when_revisions_repeat`). No actors are
/// used here (per project constraints); `NSLock` provides the equivalent mutual exclusion, held
/// for the full duration of the write (matching the semaphore fully serializing saves).
public final class JsonSessionStore: SessionStore {
    private let sessionsRoot: URL
    private let lock = NSLock()
    private var committedSaveSequences: [SBGuid: Int64] = [:]
    private var nextSaveSequence: Int64 = 0

    public init(sessionsRoot: URL) {
        self.sessionsRoot = sessionsRoot.standardizedFileURL
    }

    /// Port of `JsonSessionStore.CreateDefault`.
    public static func createDefault() -> JsonSessionStore {
        JsonSessionStore(sessionsRoot: SnapBriefPaths.defaultSessionsDirectory())
    }

    /// Port of `GetSessionDirectory`: `{sessionsRoot}/{sessionId:N}`.
    public func getSessionDirectory(sessionId: SBGuid) -> URL {
        sessionsRoot.appendingPathComponent(sessionId.digitsLowercase, isDirectory: true)
    }

    public func save(_ session: SnapBriefSession) async throws {
        try SessionValidation.validate(session)

        lock.lock()
        nextSaveSequence += 1
        let saveSequence = nextSaveSequence
        lock.unlock()

        lock.lock()
        defer { lock.unlock() }

        if let committed = committedSaveSequences[session.id], committed >= saveSequence {
            return
        }

        let directory = getSessionDirectory(sessionId: session.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("session.json")
        let temporary = directory.appendingPathComponent(".session-\(SBGuid().digitsLowercase).tmp")

        defer {
            if FileManager.default.fileExists(atPath: temporary.path) {
                try? FileManager.default.removeItem(at: temporary)
            }
        }

        let data = try SnapBriefJson.encoder.encode(session)
        try data.write(to: temporary, options: .atomic)

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporary, to: destination)

        committedSaveSequences[session.id] = saveSequence
    }

    public func load(sessionId: SBGuid) async throws -> SnapBriefSession? {
        let path = getSessionDirectory(sessionId: sessionId).appendingPathComponent("session.json")
        guard FileManager.default.fileExists(atPath: path.path) else {
            return nil
        }

        let data = try Data(contentsOf: path)
        let session = try SnapBriefJson.decoder.decode(SnapBriefSession.self, from: data)
        try SessionValidation.validate(session)
        return session
    }
}
