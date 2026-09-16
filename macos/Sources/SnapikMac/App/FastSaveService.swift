// Port of `LocalImageSave.NewPath` as used by `EdgeStackWindow.Saving.cs:16-32`, SPEC §1.14.
import Foundation

/// The name a capture is written under when it goes straight to the user's folder. [ТЗ№4 §2.7] The
/// whole-screen shortcut no longer writes a PNG past the strip — it adds the capture to the strip
/// like any other, and the only writer left is `AutoSaveService`, which asks for the path here.
enum FastSaveService {
    /// Port of `LocalImageSave.NewPath`: a timestamped filename that never overwrites an existing
    /// file.
    static func newPath(directory: URL, format: String) -> URL {
        let ext = format == "jpeg" ? "jpg" : "png"
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let timestamp = fileTimestamp()
        var candidate = directory.appendingPathComponent("Snapik-\(timestamp).\(ext)")
        var suffix = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("Snapik-\(timestamp)-\(suffix).\(ext)")
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
}
