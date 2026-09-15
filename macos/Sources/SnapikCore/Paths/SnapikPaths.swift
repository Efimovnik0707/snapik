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

    /// The data root itself: `sessions`, `settings.json` and `startup.log` live side by side
    /// under it.
    public static func defaultDataRoot() -> URL {
        defaultSessionsDirectory().deletingLastPathComponent()
    }

    // legacy: up to version 1.4.0 the application was named SnapBrief and kept exactly the same
    // folder under that name. An update has to carry it over, or the user starts with empty
    // settings and no sessions. Port of `AppDataPaths` (`src/Snapik.App/AppDataPaths.cs`).
    public static func legacyDataRoot() -> URL {
        defaultDataRoot().deletingLastPathComponent().appendingPathComponent(
            "SnapBrief", isDirectory: true)
    }

    /// Called once at startup, before anything reads or creates the folder, and only for the
    /// default location: a run with `--data-dir` owns its own directory and is left alone.
    public static func carryOverLegacyData(fileManager: FileManager = .default) {
        carryOverLegacyData(from: legacyDataRoot(), to: defaultDataRoot(), fileManager: fileManager)
    }

    public static func carryOverLegacyData(
        from legacyRoot: URL, to root: URL, fileManager: FileManager = .default
    ) {
        guard fileManager.fileExists(atPath: legacyRoot.path),
            !fileManager.fileExists(atPath: root.path)
        else { return }
        do {
            // Same volume: a rename, and the old folder is gone afterwards.
            try fileManager.createDirectory(
                at: root.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.moveItem(at: legacyRoot, to: root)
        } catch {
            // Could not be moved: copy instead and leave the old folder where it is. Data of the
            // older name is a convenience, never a reason not to start.
            try? fileManager.copyItem(at: legacyRoot, to: root)
        }
    }

    /// Port of `--data-dir` / `SNAPIK_DATA_DIR` override handling: an explicit directory wins,
    /// otherwise falls back to the platform default.
    public static func sessionsDirectory(dataDirectory: URL?) -> URL {
        dataDirectory ?? defaultSessionsDirectory()
    }
}
