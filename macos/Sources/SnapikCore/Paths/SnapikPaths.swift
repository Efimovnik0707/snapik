import Foundation

/// Port of the data-directory logic in `src/Snapik.Infrastructure/Persistence/JsonSessionStore.cs`
/// (`JsonSessionStore.CreateDefault`, `%LOCALAPPDATA%\Snapik\sessions`) and
/// `src/Snapik.App/App.xaml.cs` (`StartupTrace.GetDataRoot`, `--data-dir` / `SNAPIK_DATA_DIR`).
public enum SnapikPaths {
    /// Default sessions directory for the current platform:
    /// - macOS: `~/Library/Application Support/Snapik/sessions`
    /// - Windows: `%LOCALAPPDATA%\Snapik\sessions`
    /// - other platforms: a reasonable fallback under the user's home directory, needed only so
    ///   this package keeps compiling; Snapik itself only ships for macOS and Windows.
    public static func defaultSessionsDirectory() -> URL {
        #if os(macOS)
        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
                "Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("Snapik/sessions", isDirectory: true)
        #elseif os(Windows)
        if let localAppData = ProcessInfo.processInfo.environment["LOCALAPPDATA"], !localAppData.isEmpty {
            return URL(fileURLWithPath: localAppData).appendingPathComponent(
                "Snapik/sessions", isDirectory: true)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent(
            "Snapik/sessions", isDirectory: true)
        #else
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            ".snapik/sessions", isDirectory: true)
        #endif
    }

    /// Port of `--data-dir` / `SNAPIK_DATA_DIR` override handling: an explicit directory wins,
    /// otherwise falls back to the platform default.
    public static func sessionsDirectory(dataDirectory: URL?) -> URL {
        dataDirectory ?? defaultSessionsDirectory()
    }
}
