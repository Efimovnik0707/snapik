import Foundation

/// Port of `src/Snapik.Core/Exporting/ExportContracts.cs`.
/// JSON fields: `captureId`, `displayLabel`, `fileName`, `sha256`, `byteLength`.
public struct ExportImageEntry: Codable, Equatable, Sendable {
    public var captureId: SBGuid
    public var displayLabel: String
    public var fileName: String
    public var sha256: String
    public var byteLength: Int64

    public init(captureId: SBGuid, displayLabel: String, fileName: String, sha256: String, byteLength: Int64) {
        self.captureId = captureId
        self.displayLabel = displayLabel
        self.fileName = fileName
        self.sha256 = sha256
        self.byteLength = byteLength
    }

    enum CodingKeys: String, CodingKey {
        case captureId
        case displayLabel
        case fileName
        case sha256
        case byteLength
    }
}

/// JSON fields: `exportId`, `sessionId`, `revision`, `createdAtUtc`, `images`, `promptFileName`,
/// `promptSha256`, `promptText`, `captureCount`, `noteCount`.
public struct ExportManifest: Codable, Equatable, Sendable {
    public var exportId: SBGuid
    public var sessionId: SBGuid
    public var revision: Int
    public var createdAtUtc: Date
    public var images: [ExportImageEntry]
    public var promptFileName: String
    public var promptSha256: String
    public var promptText: String
    public var captureCount: Int
    public var noteCount: Int

    public init(
        exportId: SBGuid,
        sessionId: SBGuid,
        revision: Int,
        createdAtUtc: Date,
        images: [ExportImageEntry],
        promptFileName: String,
        promptSha256: String,
        promptText: String,
        captureCount: Int,
        noteCount: Int
    ) {
        self.exportId = exportId
        self.sessionId = sessionId
        self.revision = revision
        self.createdAtUtc = createdAtUtc
        self.images = images
        self.promptFileName = promptFileName
        self.promptSha256 = promptSha256
        self.promptText = promptText
        self.captureCount = captureCount
        self.noteCount = noteCount
    }

    enum CodingKeys: String, CodingKey {
        case exportId
        case sessionId
        case revision
        case createdAtUtc
        case images
        case promptFileName
        case promptSha256
        case promptText
        case captureCount
        case noteCount
    }
}

/// Port of `PreparedExport` (`GetImagePathsInOrder`).
public struct PreparedExport: Sendable {
    public let rootDirectory: URL
    public let manifest: ExportManifest

    public init(rootDirectory: URL, manifest: ExportManifest) {
        self.rootDirectory = rootDirectory
        self.manifest = manifest
    }

    public func imagePathsInOrder() -> [URL] {
        manifest.images.map { rootDirectory.appendingPathComponent($0.fileName).standardizedFileURL }
    }
}

/// Port of `ExportImageContext`.
public struct ExportImageContext: Sendable {
    public let displayLabel: String
    public let captureIndex: Int
    public let sourceImagePath: URL

    public init(displayLabel: String, captureIndex: Int, sourceImagePath: URL) {
        self.displayLabel = displayLabel
        self.captureIndex = captureIndex
        self.sourceImagePath = sourceImagePath
    }
}

/// Port of `IExportImageRenderer`. Rendering annotated pixels onto the source image is out of
/// Core's scope (no CoreImage/AppKit here): the Mac app target implements this protocol and
/// draws `capture`'s annotations (passed again explicitly as `annotations` per spec, though they
/// are also reachable via `capture.annotations`) into a PNG.
public protocol ExportImageRendering {
    func renderPNG(
        capture: CaptureItem,
        annotations: [AnnotationItem],
        context: ExportImageContext
    ) async throws -> Data
}

/// Port of `IExportService`.
public protocol ExportService {
    func prepare(session: SnapikSession, sessionDirectory: URL) async throws -> PreparedExport
}
