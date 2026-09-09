import Foundation

/// Port of `src/SnapBrief.Core/Persistence/ISessionStore.cs` (`ISessionStore` -> `SessionStore`,
/// dropping the "I" prefix per Swift convention).
public protocol SessionStore {
    func getSessionDirectory(sessionId: SBGuid) -> URL
    func save(_ session: SnapBriefSession) async throws
    func load(sessionId: SBGuid) async throws -> SnapBriefSession?
}

/// Port of `ISessionAssetStore`.
public protocol SessionAssetStore {
    func saveOriginalPNG(sessionId: SBGuid, captureId: SBGuid, pngContent: Data) async throws -> String
}
