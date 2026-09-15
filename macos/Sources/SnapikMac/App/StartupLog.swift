// Port of `StartupTrace` (`src/Snapik.App/App.xaml.cs:88-103`), SPEC §1.19.
import Foundation
import SnapikCore

/// Appends timestamped lines to `startup.log` in the resolved data root. All write failures are
/// swallowed, matching the C# `catch { }`.
enum StartupLog {
    /// `ISO8601Precise` (Core) is `internal` to `SnapikCore`, so the log line timestamp here
    /// uses a plain `DateFormatter` instead; only the file/session JSON dates need bit-identical
    /// .NET `"O"`-format round-tripping.
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// Port of `StartupTrace.GetDataRoot`.
    static func dataRoot(for options: CommandLineOptions) -> URL {
        if let dataDirectory = options.dataDirectory {
            return dataDirectory
        }
        return SnapikPaths.defaultSessionsDirectory()
    }

    static func write(_ options: CommandLineOptions, _ message: String) {
        let root = dataRoot(for: options)
        guard (try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)) != nil else {
            return
        }

        let line = "\(formatter.string(from: Date())) \(message)\n"
        let logPath = root.appendingPathComponent("startup.log")
        guard let data = line.data(using: .utf8) else { return }

        if let handle = try? FileHandle(forWritingTo: logPath) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: logPath)
        }
    }
}
