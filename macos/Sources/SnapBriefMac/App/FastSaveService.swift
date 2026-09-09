// Port of `LocalImageSave` as used by `EdgeStackWindow.Saving.cs:16-32` (fullscreen quick save),
// SPEC §1.14.
import CoreGraphics
import Foundation
import SnapBriefCore

/// Writes a whole-desktop capture straight to disk, in the user's chosen folder/format, without
/// touching the current package or clipboard (SPEC §1.14: "не добавляет... и не заменяет буфер").
enum FastSaveService {
    /// Port of `LocalImageSave.NewPath`: a timestamped filename that never overwrites an existing
    /// file.
    static func newPath(directory: URL, format: String) -> URL {
        let ext = format == "jpeg" ? "jpg" : "png"
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let timestamp = fileTimestamp()
        var candidate = directory.appendingPathComponent("SnapBrief-\(timestamp).\(ext)")
        var suffix = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("SnapBrief-\(timestamp)-\(suffix).\(ext)")
            suffix += 1
        }
        return candidate
    }

    private static func fileTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }

    static func save(_ image: CGImage, settings: HotkeySettings) throws {
        let format: ImageCodec.Format =
            settings.saveFormat == "jpeg"
            ? .jpeg(quality: max(1, min(100, settings.jpegQuality)))
            : .png
        guard let data = ImageCodec.encode(image, format: format) else {
            throw SnapBriefError.invalidData("Could not encode the captured screen.")
        }
        let destination = newPath(directory: URL(fileURLWithPath: settings.saveDirectory), format: settings.saveFormat)
        try ImageCodec.writeAtomically(data, to: destination)
    }
}
