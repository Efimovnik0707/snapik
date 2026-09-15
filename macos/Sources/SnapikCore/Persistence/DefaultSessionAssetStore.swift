import Foundation

/// Port of `src/Snapik.Infrastructure/Persistence/SessionAssetStore.cs`
/// (`SessionAssetStore` -> `DefaultSessionAssetStore`, avoiding a name clash with the
/// `SessionAssetStore` protocol it conforms to).
public final class DefaultSessionAssetStore: SessionAssetStore {
    private static let pngSignature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]

    private let sessionStore: SessionStore

    public init(sessionStore: SessionStore) {
        self.sessionStore = sessionStore
    }

    /// Port of `SaveOriginalPngAsync`: writes to a temp file, validates the PNG signature, then
    /// atomically replaces the destination. Relative path uses `/` (not the C# `Path.Combine`
    /// OS-specific separator); this is a deliberate, self-consistent adaptation for a
    /// Foundation-only cross-platform target and matches the test's own `Path.Combine("source", ...)`
    /// expectation in spirit (a stable, forward-slash relative capture path).
    public func saveOriginalPNG(sessionId: SBGuid, captureId: SBGuid, pngContent: Data) async throws -> String {
        let relativePath = "source/\(captureId.digitsLowercase).png"
        let sourceDirectory = sessionStore.getSessionDirectory(sessionId: sessionId)
            .appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)

        let destination = sourceDirectory.appendingPathComponent("\(captureId.digitsLowercase).png")
        let temporary = sourceDirectory.appendingPathComponent(
            ".\(captureId.digitsLowercase)-\(SBGuid().digitsLowercase).tmp")

        defer {
            if FileManager.default.fileExists(atPath: temporary.path) {
                try? FileManager.default.removeItem(at: temporary)
            }
        }

        try pngContent.write(to: temporary, options: .atomic)
        try Self.validatePNG(at: temporary)

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporary, to: destination)

        return relativePath
    }

    private static func validatePNG(at url: URL) throws {
        let data = try Data(contentsOf: url)
        guard data.count >= pngSignature.count, Array(data.prefix(pngSignature.count)) == pngSignature else {
            throw SnapikError.invalidData("Capture content is not a PNG image.")
        }
    }
}
