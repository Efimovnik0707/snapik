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
    /// The letter a package of one capture keeps instead of the "A" its position would give it: the
    /// card it was copied from shows that letter, and the picture, the file name and the text have
    /// to agree with it. `nil`, and a package numbers itself by position, byte for byte as before.
    private let singleCaptureLabel: String?

    public init(
        renderer: ExportImageRendering,
        timeProvider: TimeProvider = SystemTimeProvider(),
        singleCaptureLabel: String? = nil
    ) {
        self.renderer = renderer
        self.timeProvider = timeProvider
        self.singleCaptureLabel = singleCaptureLabel
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
                let label: String
                if let only = singleCaptureLabel, session.captures.count == 1 {
                    label = only
                } else {
                    label = try CaptureLabels.forIndex(index)
                }
                // Port of `FileExportService.cs:43-45`: the user opens these files in a folder
                // of their own, and "01-A.png" sorts and reads like a page number. The guid of the
                // capture stays in `manifest.images[].captureId`, and nothing takes the name apart
                // again.
                let fileName = String(format: "%02d", index + 1) + "-\(label).png"
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

            // Port of `FileExportService.cs:63-73`: captures without notes produce no text at
            // all. The package is then images only, and an empty prompt.md would just be an empty
            // file for the user to open; the manifest carries empty strings, and a reader of it has
            // to allow for them.
            let promptText = try PromptGenerator(singleCaptureLabel: singleCaptureLabel).generate(session)
            let promptFileName = promptText.isEmpty ? "" : "prompt.md"
            var promptSha256 = ""
            if !promptText.isEmpty {
                let promptData = Data(promptText.utf8)
                try Self.writeNew(promptData, to: staging.appendingPathComponent(promptFileName))
                promptSha256 = SHA256.hexString(promptData)
            }

            let manifest = ExportManifest(
                exportId: exportId,
                sessionId: session.id,
                revision: session.revision,
                createdAtUtc: timeProvider.utcNow(),
                images: images,
                promptFileName: promptFileName,
                promptSha256: promptSha256,
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
