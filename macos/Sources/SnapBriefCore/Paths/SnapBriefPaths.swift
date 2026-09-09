import Foundation

/// Port of the data-directory logic in `src/SnapBrief.Infrastructure/Persistence/JsonSessionStore.cs`
/// (`JsonSessionStore.CreateDefault`, `%LOCALAPPDATA%\SnapBrief\sessions`) and
/// `src/SnapBrief.App/App.xaml.cs` (`StartupTrace.GetDataRoot`, `--data-dir` / `SNAPBRIEF_DATA_DIR`).
public enum SnapBriefPaths {
    /// Default sessions directory for the current platform:
    /// - macOS: `~/Library/Application Support/SnapBrief/sessions`
    /// - Windows: `%LOCALAPPDATA%\SnapBrief\sessions`
    /// - other platforms: a reasonable fallback under the user's home directory, needed only so
    ///   this package keeps compiling; SnapBrief itself only ships for macOS and Windows.
    public static func defaultSessionsDirectory() -> URL {
        #if os(macOS)
        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
                "Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("SnapBrief/sessions", isDirectory: true)
        #elseif os(Windows)
        if let localAppData = ProcessInfo.processInfo.environment["LOCALAPPDATA"], !localAppData.isEmpty {
            return URL(fileURLWithPath: localAppData).appendingPathComponent(
                "SnapBrief/sessions", isDirectory: true)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent(
            "SnapBrief/sessions", isDirectory: true)
        #else
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            ".snapbrief/sessions", isDirectory: true)
        #endif
    }

    /// Port of `--data-dir` / `SNAPBRIEF_DATA_DIR` override handling: an explicit directory wins,
    /// otherwise falls back to the platform default.
    public static func sessionsDirectory(dataDirectory: URL?) -> URL {
        dataDirectory ?? defaultSessionsDirectory()
    }
}
