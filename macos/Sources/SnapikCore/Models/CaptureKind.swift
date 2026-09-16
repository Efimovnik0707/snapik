import Foundation

/// Port of `src/Snapik.Core/Models/CaptureKind.cs` (SPEC-DELTA-4 §1.1 K-1).
/// Where a capture came from. The value is written into `session.json` in English
/// ("region", "fullscreen", "import"), so the file never carries an interface word.
public enum CaptureKind: String, Codable, Equatable, CaseIterable, Sendable {
    case region
    case fullscreen
    case `import`
}
