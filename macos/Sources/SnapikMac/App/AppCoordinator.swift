// Port of the non-UI logic in `EdgeStackWindow.xaml.cs`/`EdgeStackWindow.Saving.cs`, SPEC §1.2,
// §1.9-§1.12, §1.14, §5.4.
//
// Deviation from the Windows source: the recipient-selection row and its paste button are
// intentionally not ported as visible UI (SPEC §1.9 point 4). `PasteCoordinator` is still
// constructed (satisfies "владеет ... PasteCoordinator", CONTRACTS.md), but is never driven from
// the UI, matching "в основном сценарии он не используется" (SPEC §5.2). Everything else —
// paste-intent detection, the Codex Desktop text catch-up, session rotation — is wired up per
// spec using Core Transport's actual published API (`Sources/SnapikCore/Transport/`).
import AppKit
import SnapikCore

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
    /// SPEC-DELTA-2A §4 (CONTRACTS.md sync 2): `true` once the package on the clipboard has been
    /// pasted and republished for reuse (`republishPackageForReuse`) — the *next* capture session
    /// must start fresh instead of appending to the pasted stack (`ensureCurrentCaptureSession`).
    var pasteObservedForCurrentPackage = false
    /// Port of `_pasteIntentTransition`: non-`nil` while `completePasteIntent` is running, so a
    /// second paste intent observed mid-flight is ignored (SPEC §1.11 point 3), and every other
    /// mutating operation (`newCapture`, `saveFullscreen`, `openCapture`) awaits it first.
    var pasteIntentTransition: Task<Void, Never>?
    /// Port of `_clipboardPublicationGate` (`SemaphoreSlim(1, 1)`, SPEC-DELTA-2A §4): serializes
    /// every clipboard-publishing operation (`saveAndCopyCommittedPackage`, `refreshOwnedClipboard`,
    /// `completePasteIntent`, the receiver-echo re-arm) against each other.
    let clipboardPublicationGate = AsyncGate()
    /// Port of the receiver-echo watch task (`AppCoordinator+PasteIntent.swift`), SPEC-DELTA-2A §5.
    var receiverEchoWatchTask: Task<Void, Never>?
    /// Identity token for `receiverEchoWatchTask`, so its own completion only clears the property
    /// if a newer watch hasn't already replaced it (`AppCoordinator+PasteIntent.swift`).
    var receiverEchoWatchToken: UUID?

    /// R8 fix: the app that was frontmost before the *first* capture of a "+ Снимок" chain
    /// activated this app, remembered for every controller in that chain instead of each one
    /// re-reading `NSWorkspace.shared.frontmostApplication` (which can race with the previous
    /// controller's own `close()`-time reactivation and report Snapik itself). Set in
    /// `beginOverlayCapture()`; cleared in `AppCoordinator+OverlayEditorDelegate.swift` once a
    /// chain ends (commit without a next capture, or cancel).
    var captureSeriesPreviousApp: NSRunningApplication?
    /// R8 fix: set synchronously by `overlayEditorRequestsNextCapture` so the deferred check in
    /// `overlayEditor(_:didCommit:)` can tell "+ Снимок" (chain continues) apart from "Готово"
    /// (chain ends) — both delegate calls for one commit happen synchronously, back to back, in
    /// `OverlayEditorController.commit(addNext:)`.
    var nextCaptureRequested = false

    // `internal` (not `private`): used from `AppCoordinator+Package.swift`.
    var isBusy = false
    var isSessionResetting = false

    weak var stackWindow: EdgeStackWindowController?
    weak var statusBar: StatusBarController?

    /// Whether `settings.json` was already on disk when this run started, read before anything of
    /// ours could write it. The wizard asks it twice: a machine without a file has never seen the
    /// wizard, and it is also the only machine whose language may be guessed from the locale
    /// (SPEC-DELTA-3 §1.6 O-2).
    let settingsFileExisted: Bool
    /// The wizard while it is on screen: an `NSWindowController` nothing holds goes away with the
    /// run-loop turn that opened it.
    private var onboarding: OnboardingWindowController?

    init(options: CommandLineOptions) {
        self.options = options
        self.workspace = SessionWorkspace(dataDirectory: options.dataDirectory)
        // Read before the migration below, which writes the file it has just healed.
        self.settingsFileExisted = FileManager.default.fileExists(atPath: workspace.settingsPath.path)
        // SPEC-DELTA-3 §2.2 (C-9): the start of the run is where a file written by an older build
        // is brought up to the current version and a broken shortcut id is healed **in the file**,
        // not only in the copy this object holds. Every later read (`workspace.preferences`) is the
        // plain one it has always been.
        self.settings = HotkeySettings.loadAndMigrate(path: workspace.settingsPath)
        self.language = settings.language
        UiLanguage.current = settings.language

        self.captureService = ScreenCaptureService()
        let clipboard = MacClipboardService()
        self.clipboard = clipboard
        let foregroundTargetService = MacForegroundTargetService()
        self.foregroundTargetService = foregroundTargetService
        let inputInjector = MacInputInjector()
        self.inputInjector = inputInjector
        self.codexPasteCompletion = CodexDesktopPasteCompletionService(
            clipboard: clipboard, foreground: foregroundTargetService, input: inputInjector)
        self.pasteCoordinator = PasteCoordinator(
            clipboard: clipboard, foreground: foregroundTargetService, input: inputInjector,
            observer: UnobservableAcceptanceObserver(foreground: foregroundTargetService))

        // Constructed last among the stored properties (SPEC-DELTA-2A §4, CONTRACTS.md sync 2):
        // `shouldIntercept` captures `[weak self]`, so every other non-optional stored property
        // must already be assigned by the time this runs.
        let macPasteObserver = MacPasteIntentObserver(
            foreground: foregroundTargetService, clipboardSequence: { NSPasteboard.general.changeCount })
        self.pasteIntentObserver = macPasteObserver
        // The predicate captures `self`, so it is attached only after every stored property is
        // initialized (Swift forbids capturing `self` in an initializer before that point).
        // The tap callback runs on the main run loop but is not `@MainActor`-isolated to the
        // compiler; this class is `@MainActor` and the tap is attached to `CFRunLoopGetMain()`,
        // so `assumeIsolated` is safe (SPEC-DELTA-2A §1.2, risk 6).
        macPasteObserver.shouldIntercept = { [weak self] intent in
            MainActor.assumeIsolated { self?.shouldInterceptPasteIntent(intent) ?? false }
        }

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
            // SPEC-DELTA-2A §6: forward tap-mode/re-enable diagnostics to `startup.log`.
            macObserver.onDiagnostic = { [weak self] message in self?.logPasteIntent(message) }
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

        // SPEC-DELTA-2A §1.1: request Accessibility once so interception (`.defaultTap`) can be
        // used instead of the `.listenOnly` degradation, but never during `--demo`/`--smoke-test`
        // (CONTRACTS.md "Shell": those must never trigger a TCC prompt).
        if !options.demo && !options.smokeTest {
            TransportPermissions.requestAccessibilityAccess()
        }

        registerHotkeys()

        // Port of the wizard branch of `EdgeStackWindow.OnLoaded` (`:209-214`), SPEC-DELTA-3 §1.6
        // O-2: before the session is restored, because on the very first run there is nothing to
        // restore and the wizard writes the language and the shortcut the rest of the startup reads.
        let wizardShown = OnboardingWindowController.shouldShowOnboarding(
            settingsFileExists: settingsFileExisted, settings: settings,
            demo: options.demo || options.smokeTest)
        if wizardShown { showOnboarding() }

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
            // [ТЗ№4 A7] A run that began with the wizard ends with the strip shown by the wizard's
            // own `onFinished`, and not a moment earlier: the strip would flash empty behind it.
            if !wizardShown { self.stackWindow?.reveal() }
        }
    }

    /// Port of `ShowOnboarding` (`EdgeStackWindow.xaml.cs:1194`), SPEC-DELTA-3 §1.6 O-2, S-15.
    /// `howToOnly` is the "Как пользоваться" item of the menu bar: the slides alone, nothing
    /// collected, nothing written, and the strip left exactly as they found it.
    func showOnboarding(howToOnly: Bool = false) {
        StartupLog.write(options, "Onboarding opens: howToOnly=\(howToOnly)")
        let controller = OnboardingWindowController(
            coordinator: self, howToOnly: howToOnly, settingsFileExists: settingsFileExisted)
        onboarding = controller
        controller.onFinished = { [weak self] in
            self?.onboarding = nil
            // [ТЗ№4 A7] "Начать" and "Пропустить" alike end with the strip on the screen, shown
            // without activating the application.
            if !howToOnly { self?.stackWindow?.reveal() }
        }
        controller.showWindow(nil)
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
            } else if pendingCommitTask != nil {
                // R3 fix: a previous commit is still being folded into the session
                // (`overlayEditor(_:didCommit:)`'s `pendingCommitTask`, cleared once that finishes)
                // — `overlay` is already `nil` at this point, so without this check a hotkey here
                // would race a brand-new capture against that in-flight append/save.
                return
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
        // Finding 11 / SPEC-DELTA-2A §4: don't race a paste-intent-driven session rotation
        // that's still in flight — wait for it (not guard-return: the rotation itself may be
        // exactly what makes this capture valid to start).
        await pasteIntentTransition?.value
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
    /// `ClipboardServicing.capture(_:)` (CONTRACTS.md, `Sources/SnapikCore/Transport`, outside
    /// this zone) has no failure case to report — `MacClipboardService.capture` always succeeds
    /// synchronously reading `NSPasteboard`. That branch is therefore unreachable on macOS as the
    /// protocol is currently shaped; wiring it for real needs a `Result`-returning `capture(_:)`
    /// in Core, which is a plan deviation flagged here rather than silently worked around.
    private func ensureCurrentCaptureSession() async -> Bool {
        // Port of `EnsureCurrentCaptureSessionAsync`'s first block (SPEC-DELTA-2A §4, Part 1
        // §4.6): a package that was already pasted-and-republished always starts a fresh session
        // — the clipboard is not even re-read (a re-armed package after this point belongs to the
        // *next* session, not this stale one).
        if pasteObservedForCurrentPackage {
            pasteObservedForCurrentPackage = false
            cancelReceiverEchoWatch()
            ownedClipboardReceipt = nil
            ownedClipboardPromptText = nil
            return await startNewSession()
        }

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
        // R3 fix: the single funnel point for both entry paths — `newCapture()` (fresh hotkey/
        // stack button) and `overlayEditorRequestsNextCapture` ("+ Снимок") — so a second call
        // can never stand up a second overlay while one is already up.
        guard overlay == nil else { return }

        // R8 fix: remember the pre-chain frontmost app once, at the very start of a "+ Снимок"
        // series; every controller in the chain gets the same value (see
        // `previousFrontmostApplicationOverride`'s doc comment).
        if captureSeriesPreviousApp == nil {
            captureSeriesPreviousApp = NSWorkspace.shared.frontmostApplication
        }

        hideAllOwnWindows()
        try? await Task.sleep(nanoseconds: 120_000_000)

        guard let frame = await captureDesktopFrame() else {
            stackWindow?.setStatus(StatusStrings.captureNotCompleted("no screen frame"), isError: true)
            stackWindow?.reveal()
            captureSeriesPreviousApp = nil
            return
        }

        let context = EditorWorkspaceContext(
            session: workspace.session, sessionDirectory: workspace.sessionDirectory,
            assetStore: workspace.assetStore, nextCaptureIndex: workspace.session.captures.count,
            regionPath: workspace.regionPath)

        let controller = OverlayEditorController(
            frame: frame, workspace: context, settings: settings, language: language)
        controller.previousFrontmostApplicationOverride = captureSeriesPreviousApp
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

    /// Port of `OnOpenCaptureClick` (SPEC §1.9 "Клик по миниатюре"). SPEC-DELTA-3 §7 W0-6 (S-1):
    /// the read-only preview window is gone from both builds, so a click on a card goes straight
    /// back into markup, the way it did before SPEC-DELTA-2B §D.
    func openCapture(_ captureId: SBGuid) async {
        // R5 fix: don't reopen a capture into a session that a paste-intent rotation
        // (`completePasteIntent`/`startNewSession`) is in the middle of retiring — that race is
        // exactly what left `overlayEditor(_:didCommit:)`'s session-id check needs to guard
        // against. `pasteIntentTransition` replaces the old `isCompletingPasteIntent` flag
        // (SPEC-DELTA-2A §4): awaited, not guard-returned, same as `newCapture`/`openCapture`.
        await pasteIntentTransition?.value
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
            // R2 fix: a restored capture (`restoreRemoved`) reuses this same id; without dropping
            // the cached bitmap here, `stackWindow?.refresh()` right below would still find a hit
            // for a capture that briefly wasn't in the session.
            stackWindow?.invalidateThumbnail(for: captureId)
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

        // SPEC-DELTA-2A §4: every session rotation, however triggered, ends any in-flight
        // receiver-echo watch and forgets that the outgoing package was ever pasted.
        cancelReceiverEchoWatch()
        pasteObservedForCurrentPackage = false

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
