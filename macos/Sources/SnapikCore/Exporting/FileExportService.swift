import Foundation

/// Port of `src/Snapik.Infrastructure/Exporting/FileExportService.cs`.
///
/// The C# renderer writes PNG bytes into a caller-provided `Stream`; the Swift
/// `ExportImageRendering` protocol instead returns `Data` for the rendered PNG (simpler surface
/// for a Foundation-only, no-CoreImage Core target — the Mac app target owns the actual pixel
/// rendering). This service still validates the PNG signature, hashes it, and writes it to disk
/// itself, preserving the "no partial revision on invalid renderer output" guarantee.
public final class FileExportService: ExportService {
    private static let pngSignature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]

    private let renderer: ExportImageRendering
    private let timeProvider: TimeProvider

    public init(renderer: ExportImageRendering, timeProvider: TimeProvider = SystemTimeProvider()) {
        self.renderer = renderer
        self.timeProvider = timeProvider
    }

    public func prepare(session: SnapikSession, sessionDirectory: URL) async throws -> PreparedExport {
        try SessionValidation.validate(session)
        guard !session.captures.isEmpty else {
            throw SnapikError.invalidOperation("Cannot export a session without captures.")
        }

        let sessionRoot = sessionDirectory.standardizedFileURL
        let exportId = SBGuid()
        let exportsRoot = sessionRoot.appendingPathComponent("exports", isDirectory: true)
        let staging = exportsRoot.appendingPathComponent(".staging-\(exportId.digitsLowercase)", isDirectory: true)
        let revisionSuffix = String(format: "%06d", session.revision)
        let finalDirectory = exportsRoot.appendingPathComponent(
            "revision-\(revisionSuffix)-\(exportId.digitsLowercase)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        do {
            var images: [ExportImageEntry] = []
            for (index, capture) in session.captures.enumerated() {
                let label = try CaptureLabels.forIndex(index)
                let fileName = "\(label)_\(capture.id.digitsLowercase).png"
                let imagePath = staging.appendingPathComponent(fileName)
                let sourceImagePath = try Self.resolveSessionPath(
                    sessionRoot: sessionRoot, relativePath: capture.sourceImagePath)

                guard FileManager.default.fileExists(atPath: sourceImagePath.path) else {
                    throw SnapikError.fileNotFound(
                        "Capture source image does not exist: \(sourceImagePath.path)")
                }

                let context = ExportImageContext(displayLabel: label, captureIndex: index, sourceImagePath: sourceImagePath)
                let rendered = try await renderer.renderPNG(
                    capture: capture, annotations: capture.annotations, context: context)

                try Self.validatePNG(rendered)
                try Self.writeNew(rendered, to: imagePath)

                images.append(
                    ExportImageEntry(
                        captureId: capture.id,
                        displayLabel: label,
                        fileName: fileName,
                        sha256: SHA256.hexString(rendered),
                        byteLength: Int64(rendered.count)))
            }

            let promptText = try PromptGenerator().generate(session)
            let promptFileName = "prompt.md"
            let promptPath = staging.appendingPathComponent(promptFileName)
            let promptData = Data(promptText.utf8)
            try Self.writeNew(promptData, to: promptPath)

            let manifest = ExportManifest(
                exportId: exportId,
                sessionId: session.id,
                revision: session.revision,
                createdAtUtc: timeProvider.utcNow(),
                images: images,
                promptFileName: promptFileName,
                promptSha256: SHA256.hexString(promptData),
                promptText: promptText,
                captureCount: session.captures.count,
                noteCount: Self.countNotes(session))

            let manifestPath = staging.appendingPathComponent("manifest.json")
            let manifestData = try SnapikJson.encoder.encode(manifest)
            try Self.writeNew(manifestData, to: manifestPath)

            try FileManager.default.moveItem(at: staging, to: finalDirectory)
            return PreparedExport(rootDirectory: finalDirectory, manifest: manifest)
        } catch {
            if FileManager.default.fileExists(atPath: staging.path) {
                try? FileManager.default.removeItem(at: staging)
            }
            throw error
        }
    }

    private static func writeNew(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    private static func countNotes(_ session: SnapikSession) -> Int {
        var count = ExportText.hasContent(session.globalNote) ? 1 : 0
        for capture in session.captures {
            count += ExportText.hasContent(capture.note) ? 1 : 0
            count += capture.annotations.filter { ExportText.hasContent($0.note) }.count
        }
        return count
    }

    private static func resolveSessionPath(sessionRoot: URL, relativePath: String) throws -> URL {
        let resolved = sessionRoot.appendingPathComponent(relativePath).standardizedFileURL
        var rootPrefix = sessionRoot.standardizedFileURL.path
        if !rootPrefix.hasSuffix("/") {
            rootPrefix += "/"
        }
        guard resolved.path.lowercased().hasPrefix(rootPrefix.lowercased()) else {
            throw SnapikError.invalidData("Capture image path escapes the session directory.")
        }
        return resolved
    }

    private static func validatePNG(_ data: Data) throws {
        guard data.count >= pngSignature.count, Array(data.prefix(pngSignature.count)) == pngSignature else {
            throw SnapikError.invalidData("The export renderer did not produce a PNG image.")
        }
    }
}
