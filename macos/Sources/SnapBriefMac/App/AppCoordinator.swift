// Port of the non-UI logic in `EdgeStackWindow.xaml.cs`/`EdgeStackWindow.Saving.cs`, SPEC §1.2,
// §1.9-§1.12, §1.14, §5.4.
//
// Deviation from the Windows source: the recipient-selection row and its paste button are
// intentionally not ported as visible UI (SPEC §1.9 point 4). `PasteCoordinator` is still
// constructed (satisfies "владеет ... PasteCoordinator", CONTRACTS.md), but is never driven from
// the UI, matching "в основном сценарии он не используется" (SPEC §5.2). Everything else —
// paste-intent detection, the Codex Desktop text catch-up, session rotation — is wired up per
// spec using Core Transport's actual published API (`Sources/SnapBriefCore/Transport/`).
import AppKit
import SnapBriefCore

@MainActor
final class AppCoordinator {
    let options: CommandLineOptions
    let workspace: SessionWorkspace
    private let captureService: ScreenCaptureServicing
    // `internal` (not `private`): used extensively from `AppCoordinator+Package.swift`.
    let clipboard: ClipboardServicing
    // `internal` (not `private`): `pasteIntentObserver.stop()` is called from
    // `AppCoordinator+Package.swift`'s `shutdown()`.
    let pasteIntentObserver: PasteIntentObserving
    private let foregroundTargetService: ForegroundTargetServicing
    private let inputInjector: GuardedInputInjecting
    // Owned per CONTRACTS.md ("владеет ... PasteCoordinator"); not actively driven (see header).
    private let pasteCoordinator: PasteCoordinator
    // `internal` (not `private`): driven from `AppCoordinator+Package.swift`'s
    // `completePasteIntent` (SPEC §5.4).
    let codexPasteCompletion: CodexDesktopPasteCompletionService
    let hotkeyService = GlobalHotkeyService()
    let notificationService = NotificationService()

    // `internal` (not `private(set)`): written from `AppCoordinator+Package.swift`'s
    // `applySettings`.
    var settings: HotkeySettings
    var language: String

    // `internal` (not `private`): mutated from `AppCoordinator+OverlayEditorDelegate.swift`.
    var overlay: OverlayEditorController?
    /// The in-flight commit started by `overlayEditor(_:didCommit:annotations:)`, `Bool` = whether
    /// `saveAndCopyCommittedPackage()` actually succeeded. Finding 5: `overlayEditorRequestsNextCapture`
    /// awaits this before starting the next capture, instead of racing ahead of the append.
    /// `internal` (not `private`): set/read from `AppCoordinator+OverlayEditorDelegate.swift`.
    var pendingCommitTask: Task<Bool, Never>?
    private var removedStack: [(capture: CaptureItem, index: Int)] = []
    // `internal` (not `private`): used from `AppCoordinator+Package.swift`.
    var prepared: PreparedExport?
    /// Our last known-good clipboard write, if the package on the clipboard is still ours (SPEC
    /// §1.10 point 4: "receipt — доказательство владения буфером"). `internal` (not `private`):
    /// used from `AppCoordinator+Package.swift`.
    var ownedClipboardReceipt: ClipboardSnapshot?
    var ownedClipboardPromptText: String?
    /// Port of `_pasteIntentTransition`: `true` while `completePasteIntent` is running, so a
    /// second paste intent observed mid-flight is ignored (SPEC §1.11 point 3).
    var isCompletingPasteIntent = false

    // `internal` (not `private`): used from `AppCoordinator+Package.swift`.
    var isBusy = false
    var isSessionResetting = false

    weak var stackWindow: EdgeStackWindowController?
    weak var statusBar: StatusBarController?

    init(options: CommandLineOptions) {
        self.options = options
        self.workspace = SessionWorkspace(dataDirectory: options.dataDirectory)
        self.settings = workspace.preferences
        self.language = settings.language
        UiLanguage.current = settings.language

        self.captureService = ScreenCaptureService()
        let clipboard = MacClipboardService()
        self.clipboard = clipboard
        let foregroundTargetService = MacForegroundTargetService()
        self.foregroundTargetService = foregroundTargetService
        let inputInjector = MacInputInjector()
        self.inputInjector = inputInjector
        self.pasteIntentObserver = MacPasteIntentObserver(
            foreground: foregroundTargetService, clipboardSequence: { NSPasteboard.general.changeCount })
        self.codexPasteCompletion = CodexDesktopPasteCompletionService(
            clipboard: clipboard, foreground: foregroundTargetService, input: inputInjector)
        self.pasteCoordinator = PasteCoordinator(
            clipboard: clipboard, foreground: foregroundTargetService, input: inputInjector,
            observer: UnobservableAcceptanceObserver(foreground: foregroundTargetService))

        hotkeyService.onHotkeyPressed = { [weak self] name in self?.handleHotkey(name) }
        pasteIntentObserver.onPasteIntent = { [weak self] intent in self?.handlePasteIntent(intent) }
        // Finding 16/7: surface the Mac-only "event tap could not be reactivated" failure as the
        // Windows-parity "Вставка остановлена: {e}" status. `PasteIntentObserving` itself has no
        // such hook (Core protocol, CONTRACTS.md), so this only wires up when the concrete Mac
        // type is in play — true for every real run; only test doubles fall through silently.
        if let macObserver = self.pasteIntentObserver as? MacPasteIntentObserver {
            macObserver.onStopped = { [weak self] error in
                self?.stackWindow?.setStatus(StatusStrings.pasteStopped("\(error)"), isError: true)
            }
        }
    }

    // MARK: - Startup

    func start() {
        StartupLog.write(options, "AppCoordinator start entered")

        // Screen Recording is checked/requested lazily, at the first *real* capture
        // (`captureDesktopFrame()`) instead of here — SPEC §9.1 as scoped by CONTRACTS.md
        // "Shell": startup (including `--demo`) must never trigger the TCC prompt.
        do {
            try pasteIntentObserver.start()
        } catch {
            stackWindow?.setStatus(StatusStrings.pasteIntentUnavailable("\(error)"), isError: true)
        }

        registerHotkeys()

        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.options.demo {
                do {
                    try await DemoSessionFactory.seedDemoSession(in: self.workspace)
                } catch {
                    self.stackWindow?.setStatus(StatusStrings.failedToRestoreSession("\(error)"), isError: true)
                }
            } else {
                _ = await self.workspace.loadCurrent()
            }
            self.stackWindow?.refresh()
            self.stackWindow?.reveal()
        }
    }

    // MARK: - Hotkeys

    // `internal` (not `private`): called from `AppCoordinator+Package.swift`.
    func registerHotkeys() {
        hotkeyService.unregisterAll()
        var conflicts: [String] = []

        if settings.captureEnabled {
            do { try hotkeyService.register(name: "capture", identifier: HotkeyIdentifier.parse(settings.captureId)) }
            catch { conflicts.append("захват") }
        }
        if settings.fullscreenSaveEnabled {
            do { try hotkeyService.register(name: "fullscreen-save", identifier: HotkeyIdentifier.parse(settings.fullscreenSaveId)) }
            catch { conflicts.append("сохранение экрана") }
        }

        if !conflicts.isEmpty {
            stackWindow?.setStatus(StatusStrings.hotkeyConflict(conflicts), isError: true)
        }
    }

    private func handleHotkey(_ name: String) {
        switch name {
        case "capture":
            if let overlay, overlay.isPresented {
                overlay.handleGlobalHotkey()
            } else {
                Task { @MainActor in await self.newCapture() }
            }
        case "fullscreen-save":
            Task { @MainActor in await self.saveFullscreen() }
        default:
            break
        }
    }

    // MARK: - Capture loop (SPEC §1.2 point 3, §1.9)

    func newCapture() async {
        // Finding 11: don't race a paste-intent-driven session rotation that's still in flight.
        guard !isCompletingPasteIntent else { return }
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        guard await ensureCurrentCaptureSession() else {
            // Finding 21: only reveal here on a failure path — a successful path leaves the
            // overlay in charge of the screen until it commits or cancels.
            stackWindow?.reveal()
            return
        }
        await beginOverlayCapture()
    }

    /// Port of `EnsureCurrentCaptureSessionAsync` (§1.12).
    ///
    /// Deviation: the Windows source also has an explicit "could not verify the clipboard" error
    /// branch here (`StatusStrings.couldNotVerifyClipboardBeforeCapture`, SPEC §1.12), but
    /// `ClipboardServicing.capture(_:)` (CONTRACTS.md, `Sources/SnapBriefCore/Transport`, outside
    /// this zone) has no failure case to report — `MacClipboardService.capture` always succeeds
    /// synchronously reading `NSPasteboard`. That branch is therefore unreachable on macOS as the
    /// protocol is currently shaped; wiring it for real needs a `Result`-returning `capture(_:)`
    /// in Core, which is a plan deviation flagged here rather than silently worked around.
    private func ensureCurrentCaptureSession() async -> Bool {
        guard !workspace.session.captures.isEmpty else { return true }

        if let receipt = ownedClipboardReceipt {
            let stillOurs = await withCheckedContinuation { continuation in
                clipboard.capture { snapshot in continuation.resume(returning: snapshot.sequence == receipt.sequence) }
            }
            if stillOurs { return true }
        }

        ownedClipboardReceipt = nil
        ownedClipboardPromptText = nil
        return await startNewSession()
    }

    // `internal` (not `private`): called from `AppCoordinator+OverlayEditorDelegate.swift`.
    func beginOverlayCapture() async {
        hideAllOwnWindows()
        try? await Task.sleep(nanoseconds: 120_000_000)

        guard let frame = await captureDesktopFrame() else {
            stackWindow?.setStatus(StatusStrings.captureNotCompleted("no screen frame"), isError: true)
            stackWindow?.reveal()
            return
        }

        let context = EditorWorkspaceContext(
            session: workspace.session, sessionDirectory: workspace.sessionDirectory,
            assetStore: workspace.assetStore, nextCaptureIndex: workspace.session.captures.count,
            regionPath: workspace.regionPath)

        let controller = OverlayEditorController(
            frame: frame, workspace: context, settings: settings, language: language)
        controller.delegate = self
        overlay = controller
        controller.present()
    }

    // `internal` (not `private`): called from `AppCoordinator+Package.swift`'s `saveFullscreen`.
    func captureDesktopFrame() async -> DesktopFrame? {
        // Port of SPEC §9.1's permission check, moved here (the single gate every real capture
        // path — hotkey capture, thumbnail re-open, fullscreen save — goes through) so it never
        // fires at app startup or during `--demo` (CONTRACTS.md "Shell").
        guard captureService.hasScreenRecordingPermission else {
            captureService.requestScreenRecordingPermission()
            stackWindow?.setStatus(StatusStrings.screenRecordingPermissionMissing, isError: true)
            return nil
        }

        return await withCheckedContinuation { continuation in
            captureService.captureDesktop(includeCursor: settings.captureCursor) { [weak self] result in
                // Finding 2: `ScreenCaptureService` now already redispatches to main, but this
                // stays wrapped defensively per the review's explicit instruction.
                switch result {
                case .success(let frame):
                    continuation.resume(returning: frame)
                case .failure(let error):
                    Task { @MainActor in self?.stackWindow?.setStatus(StatusStrings.captureSetupFailed("\(error)"), isError: true) }
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Port of `HideForCapture` (`:326-332`): fallback strategy (SPEC §9.8) — order every own
    /// visible window out and let the run loop flush before the delayed capture.
    // `internal` (not `private`): called from `AppCoordinator+Package.swift`'s `saveFullscreen`.
    func hideAllOwnWindows() {
        for window in NSApplication.shared.windows where window.isVisible {
            window.orderOut(nil)
        }
        CATransaction.flush()
    }

    // MARK: - Stack actions (SPEC §1.9)

    /// Port of `OnOpenCaptureClick` (SPEC §1.9 "Клик по миниатюре"). Finding 1: the previous
    /// implementation always opened a *fresh* selection over the new frame, discarding the saved
    /// capture entirely; this now loads the capture's own saved pixels and reopens it in place via
    /// `OverlayEditorController.presentExisting` (a fresh frame is still snapped first — the
    /// background shade behind the reopened capture must match the current desktop, SPEC §1.9).
    func openCapture(_ captureId: SBGuid) async {
        guard !isBusy, let capture = workspace.session.captures.first(where: { $0.id == captureId }) else { return }
        isBusy = true
        defer { isBusy = false }

        let sourceURL = workspace.sessionDirectory.appendingPathComponent(capture.sourceImagePath)
        guard let sourceImage = ImageCodec.loadImage(at: sourceURL) else {
            stackWindow?.setStatus(StatusStrings.couldNotOpenCapture("missing source image"), isError: true)
            stackWindow?.reveal()
            return
        }

        hideAllOwnWindows()
        try? await Task.sleep(nanoseconds: 120_000_000)
        guard let frame = await captureDesktopFrame() else {
            stackWindow?.setStatus(StatusStrings.couldNotOpenCapture("no screen frame"), isError: true)
            stackWindow?.reveal()
            return
        }

        let index = workspace.session.captures.firstIndex(where: { $0.id == capture.id }) ?? 0
        let context = EditorWorkspaceContext(
            session: workspace.session, sessionDirectory: workspace.sessionDirectory,
            assetStore: workspace.assetStore, nextCaptureIndex: index, regionPath: workspace.regionPath)
        let controller = OverlayEditorController(frame: frame, workspace: context, settings: settings, language: language)
        controller.delegate = self
        overlay = controller
        controller.presentExisting(capture: capture, image: sourceImage)
    }

    func removeCapture(_ captureId: SBGuid) async {
        guard let index = workspace.session.captures.firstIndex(where: { $0.id == captureId }) else { return }
        let capture = workspace.session.captures[index]
        do {
            try workspace.removeCapture(captureId)
            removedStack.append((capture, index))
            invalidatePrepared()
            stackWindow?.refresh()
            if await save() { stackWindow?.setStatus(StatusStrings.captureDeleted, isError: false) }
            await refreshOwnedClipboard()
            stackWindow?.updateRestoreButtonVisibility(removedStack.isEmpty == false)
        } catch {
            stackWindow?.setStatus(StatusStrings.couldNotOpenCapture("\(error)"), isError: true)
        }
    }

    func restoreRemoved() async {
        guard let removed = removedStack.popLast() else { return }
        do {
            try workspace.insertCapture(removed.capture, at: removed.index)
            invalidatePrepared()
            stackWindow?.refresh()
            if await save() { stackWindow?.setStatus(StatusStrings.captureRestored, isError: false) }
            await refreshOwnedClipboard()
        } catch {
            stackWindow?.setStatus(StatusStrings.couldNotOpenCapture("\(error)"), isError: true)
        }
        stackWindow?.updateRestoreButtonVisibility(removedStack.isEmpty == false)
    }

    var hasRemovedCapture: Bool { !removedStack.isEmpty }

    func reorderCapture(captureId: SBGuid, toIndex: Int) async {
        do {
            try workspace.moveCapture(captureId, to: toIndex)
            invalidatePrepared()
            stackWindow?.refresh()
            if await save() { stackWindow?.setStatus(StatusStrings.orderChanged, isError: false) }
            await refreshOwnedClipboard()
        } catch {
            stackWindow?.setStatus(StatusStrings.couldNotOpenCapture("\(error)"), isError: true)
        }
    }

    // MARK: - Session lifecycle (SPEC §1.11)

    @discardableResult
    func startNewSession() async -> Bool {
        guard !isSessionResetting else { return false }
        isSessionResetting = true
        defer { isSessionResetting = false }

        do {
            try await workspace.startNewSession()
            removedStack.removeAll()
            prepared = nil
            ownedClipboardReceipt = nil
            ownedClipboardPromptText = nil
            stackWindow?.refresh()
            stackWindow?.hide()
            stackWindow?.setStatus("", isError: false)
            return true
        } catch {
            stackWindow?.setStatus(StatusStrings.couldNotStartNewSession("\(error)"), isError: true)
            return false
        }
    }

    // `internal` (not `private`): called from `AppCoordinator+Package.swift`.
    func invalidatePrepared() { prepared = nil }

    // `internal` (not `private`): called from `AppCoordinator+Package.swift`.
    @discardableResult
    func save() async -> Bool {
        do {
            try await workspace.save()
            return true
        } catch {
            stackWindow?.setStatus(StatusStrings.couldNotSave("\(error)"), isError: true)
            return false
        }
    }
}
