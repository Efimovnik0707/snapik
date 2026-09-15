import Foundation

/// Port of `src/Snapik.Core/Persistence/ISessionStore.cs` (`ISessionStore` -> `SessionStore`,
/// dropping the "I" prefix per Swift convention).
public protocol SessionStore {
    func getSessionDirectory(sessionId: SBGuid) -> URL
    func save(_ session: SnapikSession) async throws
    func load(sessionId: SBGuid) async throws -> SnapikSession?
}

/// Port of `ISessionAssetStore`.
public protocol SessionAssetStore {
    func saveOriginalPNG(sessionId: SBGuid, captureId: SBGuid, pngContent: Data) async throws -> String
}
