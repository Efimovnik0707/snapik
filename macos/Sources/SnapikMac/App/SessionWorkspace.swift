// Port of `src/Snapik.App/SessionWorkspace.cs`, SPEC §3.6.
//
// Deviation from the C# structure: on Windows the capture list lives in a separate WPF
// `ObservableCollection` and gets folded into a fresh `SnapikSession` snapshot (with a
// pre-incremented revision) on every save. On macOS, captures live directly in `session.captures`
// and are mutated through Core's `SessionOperations`, which already bumps `revision`/
// `modifiedAtUtc` and re-validates per call. `save()` therefore just persists the current
// in-memory session as-is. The one place SPEC §3.6 calls out explicitly ("каждая подготовка
// пакета увеличивает ревизию") is preserved verbatim in `prepareExport`.
import Foundation
import SnapikCore

final class SessionWorkspace {
    let store: SessionStore
    let assetStore: SessionAssetStore
    let sessionsRoot: URL
    let settingsPath: URL
    let regionPath: URL
    private let currentPointer: URL
    private let timeProvider: TimeProvider

    private(set) var session: SnapikSession

    init(dataDirectory: URL?, timeProvider: TimeProvider = SystemTimeProvider()) {
        self.timeProvider = timeProvider

        if let dataDirectory {
            // Port of `--data-dir`: sessions and settings share one flat directory (no nested
            // "sessions" subfolder), matching `SessionWorkspace(explicitRoot)` on Windows.
            self.sessionsRoot = dataDirectory.standardizedFileURL
            self.settingsPath = dataDirectory.appendingPathComponent("settings.json")
        } else {
            self.sessionsRoot = SnapikPaths.defaultSessionsDirectory()
            self.settingsPath = sessionsRoot.deletingLastPathComponent()
                .appendingPathComponent("settings.json")
        }

        self.regionPath = settingsPath.deletingLastPathComponent()
            .appendingPathComponent("last-region.json")
        self.currentPointer = sessionsRoot.appendingPathComponent("current-session.txt")

        let store = JsonSessionStore(sessionsRoot: sessionsRoot)
        self.store = store
        self.assetStore = DefaultSessionAssetStore(sessionStore: store)
        self.session = SnapikSession.create(nowUtc: timeProvider.utcNow())
    }

    var sessionDirectory: URL { store.getSessionDirectory(sessionId: session.id) }

    /// Settings are reread from disk on every access (SPEC §1.17: "Настройки перечитываются с
    /// диска при каждом обращении").
    var preferences: HotkeySettings { HotkeySettings.load(path: settingsPath) }

    /// Port of `LoadCurrentAsync` (`:47-67`). Returns `true` if a session pointer was found and
    /// loaded (even with zero captures); `false` means "start fresh", matching the Windows
    /// fallback to an empty list.
    @discardableResult
    func loadCurrent() async -> Bool {
        guard let text = try? String(contentsOf: currentPointer, encoding: .utf8) else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = SBGuid(uuidString: trimmed) else { return false }
        guard let loadedSession = try? await store.load(sessionId: id) else { return false }

        // Port of ":63" — a capture whose source file is missing is silently dropped, protecting
        // the rest of the session from one bad file.
        var restored = loadedSession
        let directory = store.getSessionDirectory(sessionId: loadedSession.id)
        restored.captures = loadedSession.captures.filter { capture in
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent(capture.sourceImagePath).path)
        }

        session = restored
        return true
    }

    /// Port of `SaveSnapshotAsync` (`:141-146`): persist the session, repoint
    /// `current-session.txt`.
    func save() async throws {
        try await store.save(session)
        try FileManager.default.createDirectory(at: sessionsRoot, withIntermediateDirectories: true)
        try session.id.description.write(to: currentPointer, atomically: true, encoding: .utf8)
    }

    /// Port of `StartNewSessionAsync` (§1.11): persist the current session, then create, persist
    /// and switch to a brand-new empty one. The previous session and its files remain on disk.
    func startNewSession() async throws {
        try await save()
        session = SnapikSession.create(nowUtc: timeProvider.utcNow())
        try await save()
    }

    /// Port of `PrepareAsync` (`:126-131`): bump revision unconditionally, save, then export
    /// (SPEC §3.6: "каждая подготовка пакета увеличивает ревизию и пишет session.json").
    func prepareExport(renderer: ExportImageRendering) async throws -> PreparedExport {
        session.revision += 1
        session.modifiedAtUtc = timeProvider.utcNow()
        try await save()

        let service = FileExportService(renderer: renderer, timeProvider: timeProvider)
        return try await service.prepare(session: session, sessionDirectory: sessionDirectory)
    }

    /// Port of `AddImageAsync`/`SaveDerivedImageAsync`: persists `pngData` as a new capture's
    /// source image and appends it to the session.
    ///
    /// `kind`/`monitorCount` are set here and not by the caller after the fact (`EdgeStackWindow`
    /// assigns them on the returned object, which it can because its `CaptureItem` is a class):
    /// a Swift capture is a value, and the copy in the session would keep the defaults
    /// (SPEC-DELTA-4 §2.1).
    @discardableResult
    func addCapture(
        pngData: Data, pixelWidth: Int, pixelHeight: Int,
        dpiX: Double = 96, dpiY: Double = 96, title: String? = nil, note: String? = nil,
        kind: CaptureKind = .region, monitorCount: Int = 0
    ) async throws -> CaptureItem {
        let captureId = SBGuid()
        let relativePath = try await assetStore.saveOriginalPNG(
            sessionId: session.id, captureId: captureId, pngContent: pngData)
        let capture = CaptureItem(
            id: captureId,
            sourceImagePath: relativePath,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            dpiX: dpiX,
            dpiY: dpiY,
            title: title ?? "",
            note: note ?? "",
            annotations: [],
            kind: kind,
            monitorCount: monitorCount)
        session = try SessionOperations.addCapture(session, capture: capture, nowUtc: timeProvider.utcNow())
        return capture
    }

    func removeCapture(_ captureId: SBGuid) throws {
        session = try SessionOperations.removeCapture(session, captureId: captureId, nowUtc: timeProvider.utcNow())
    }

    func moveCapture(_ captureId: SBGuid, to destinationIndex: Int) throws {
        session = try SessionOperations.moveCapture(
            session, captureId: captureId, destinationIndex: destinationIndex, nowUtc: timeProvider.utcNow())
    }

    /// Port of `RestoreRemoved` (`:746-754`): reinsert a deep-cloned removed capture at its
    /// former index, clamped to the current length.
    func insertCapture(_ capture: CaptureItem, at index: Int) throws {
        var updated = session
        let clampedIndex = min(max(index, 0), updated.captures.count)
        updated.captures.insert(capture, at: clampedIndex)
        updated.revision += 1
        updated.modifiedAtUtc = timeProvider.utcNow()
        try SessionValidation.validate(updated)
        session = updated
    }

    func replaceCapture(_ capture: CaptureItem) throws {
        session = try SessionOperations.updateCapture(session, capture: capture, nowUtc: timeProvider.utcNow())
    }

    /// Appends a `CaptureItem` whose source PNG the caller (the editor) has already written to
    /// disk via `assetStore` — used for `OverlayEditorDelegate.didCommit`, where the file is
    /// saved before the delegate callback fires (CONTRACTS.md "Editor").
    func appendCapture(_ capture: CaptureItem) throws {
        session = try SessionOperations.addCapture(session, capture: capture, nowUtc: timeProvider.utcNow())
    }

    /// Only used by `DemoSessionFactory` — the legacy global-note UI is intentionally not ported
    /// (SPEC §1.9 point 4: hidden recipient row, not part of the main scenario), but demo seeding
    /// still persists the same note the Windows build seeds.
    func updateGlobalNote(_ note: String) throws {
        session = try SessionOperations.updateGlobalNote(session, note: note, nowUtc: timeProvider.utcNow())
    }
}
