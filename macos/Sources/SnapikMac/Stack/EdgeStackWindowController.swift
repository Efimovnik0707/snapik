// Port of `EdgeStackWindow.xaml(.cs)`: the window of the strip, its placement at the edge, the two
// grips that resize it, the capsule it collapses into and the "•••" menu.
// SPEC §1.9, §6.4, §9.8; SPEC-DELTA-3 §1.3 S-2, S-5, S-8…S-14.
import AppKit
import SnapikCore

/// Non-activating panel: `.borderless`, `.nonactivatingPanel`, transparent, with the shadow drawn by
/// the panel view inside it rather than by the system — the window is 20 points wider than what is
/// seen, and that field is what the shadow lives in ([ТЗ№4 C6]).
final class EdgeStackPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class EdgeStackWindowController: NSWindowController {
    weak var coordinator: AppCoordinator?

    /// `internal` (not `private`): the smoke probes of this zone drive it directly
    /// (`App/SmokeTestRunner+Stack.swift`).
    let contentContainer: EdgeStackContentView
    private var thumbnailCache: [SBGuid: NSImage] = [:]
    private var settingsWindowController: HotkeySettingsWindowController?

    /// Port of `_softLimitWarned`: the gentle warning past the twentieth capture is said once and
    /// stays quiet until the strip has come back down to it.
    private var softLimitWarned = false
    /// Port of `_capsuleMode`: a mode of this window, never written to the settings file — a strip
    /// that opened collapsed would look like a strip that failed to open.
    private var isCapsuleMode = false
    /// SPEC-DELTA-5 §1.1 L-7: whether the strip has been put at the edge of the working area yet.
    /// Windows places it from `OnLoaded` and never again; this port has no such moment — the window
    /// is built with the coordinator and shown much later — so the first `reveal()` is it.
    private var placedOnce = false
    private var expandedWidth: CGFloat = CGFloat(StripResizeGeometry.defaultWidth)
    private var expandedTop: CGFloat = 0
    /// Port of `_expandedLeft` (SPEC-DELTA-5 §1.1 L-6): without it the strip came back to the edge
    /// of the monitor whatever corner the user had dragged it to, and the capsule stood at that edge
    /// instead of over the strip it came from.
    private var expandedLeft: CGFloat = 0
    /// Port of `_topmostSuspensions`: a dialog owned by the strip would open behind a floating one.
    private var topmostSuspensions = 0
    /// Set when a card's delete button was pressed, so the undo toast belongs to that delete and not
    /// to any later call about the same restorable capture.
    private var awaitingDeleteToast = false

    var isVisible: Bool { window?.isVisible ?? false }

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        let width = CGFloat(StripResizeGeometry.clampWidth(coordinator.settings.stackWidth, workWidth: 0))
        let panel = EdgeStackPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: width),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The shadow is ours (`StackPanelView`), and it lives inside the window: a second, system
        // one would sit on the edge of the transparent field and be seen as a contour.
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isExcludedFromWindowsMenu = true
        // [ТЗ№4 C5] Any free place of the panel drags the window.
        panel.isMovableByWindowBackground = true
        panel.sharingType = WindowCaptureExclusion.sharingType
        panel.title = MacUiText.text("Snapik — Лента снимков", language: coordinator.language)

        contentContainer = EdgeStackContentView(frame: NSRect(x: 0, y: 0, width: width, height: width))
        panel.contentView = contentContainer

        super.init(window: panel)
        contentContainer.delegate = self
        contentContainer.applyLocalization(language: coordinator.language)
        applyTopmost()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Visibility (SPEC §1.9 "Появление стопки")

    /// Port of `ShowStackWithoutActivation`: reposition, order to the top without taking focus,
    /// re-read the palette, fade in over 180 ms. This is also the entry point the first-run wizard
    /// uses when it closes (S-15): it never activates the application.
    func reveal() {
        contentContainer.applyPalette()
        refresh()
        // SPEC-DELTA-5 §1.1 L-7, port of `if (!_capsuleMode) EnsureStripPlaced();` (`:730`): the
        // capsule is placed by `positionAtEdge()`, which is the only branch it has; the strip is
        // placed at the edge once and afterwards only brought back onto the screen if it has left
        // it. Windows does the first placement from `OnLoaded`; the flag here is the same moment —
        // the strip is built long before it is first shown.
        if isCapsuleMode {
            positionAtEdge()
        } else if placedOnce {
            ensureStripPlaced()
        } else {
            placedOnce = true
            placeStripInitially()
        }
        // Port of the last line of `ShowStackWithoutActivation` (`:738`), SPEC-DELTA-5 §1.2 L-8: a
        // showing ends at the capture that was added last.
        scrollStripToEnd()
        window?.alphaValue = 0
        // `orderFrontRegardless()` shows the window without activating the app (SPEC §9.8).
        window?.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { [weak self] context in
            context.duration = StackMetrics.appearSeconds
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self?.window?.animator().alphaValue = 1
        }
    }

    /// Port of `HideStack`: hides the window, the captures and the session are untouched. A toast
    /// that outlived the panel would greet the next showing with stale text.
    func hide() {
        contentContainer.hideToast()
        window?.orderOut(nil)
    }

    func setStatus(_ text: String, isError: Bool) {
        if isError {
            contentContainer.setStatus(text, isError: true)
        } else {
            contentContainer.setStatus("", isError: false)
            if !text.isEmpty { contentContainer.showToast(text) }
        }
    }

    /// Port of `ShowToast(UiLanguage.Text("Снимок удалён"), UiLanguage.Text("Отменить"), …)`, S-12:
    /// the strip no longer carries a permanent "Вернуть" link, the undo lives in the toast of the
    /// delete it belongs to. Called by `AppCoordinator.removeCapture`/`restoreRemoved` once the
    /// session knows whether there is anything to restore.
    func updateRestoreButtonVisibility(_ visible: Bool) {
        guard visible, awaitingDeleteToast else {
            awaitingDeleteToast = false
            return
        }
        awaitingDeleteToast = false
        let language = coordinator?.language ?? "ru"
        contentContainer.showToast(
            MacUiText.text("Снимок удалён", language: language),
            actionTitle: MacUiText.text("Отменить", language: language)
        ) { [weak self] in
            Task { @MainActor in await self?.coordinator?.restoreRemoved() }
        }
    }

    func updateLanguage(_ language: String) {
        window?.title = MacUiText.text("Snapik — Лента снимков", language: language)
        contentContainer.applyLocalization(language: language)
        contentContainer.setEmptyHintShortcut(captureShortcutLabel())
        applyTopmost()
        layoutWindow()
    }

    /// Reloads the captures from the current session and re-lays out the window.
    func refresh() {
        guard let coordinator else { return }
        let captures = coordinator.workspace.session.captures
        // R2 fix: drop the cached thumbnail of a capture the session no longer holds, so a stale
        // bitmap can never resurface for a capture that later reuses the same id.
        let liveIds = Set(captures.map(\.id))
        thumbnailCache = thumbnailCache.filter { liveIds.contains($0.key) }
        // A sent capture keeps its place in the strip and gives its letter to the ones still waiting
        // (`SentCaptureRules.stripLabels`).
        let labels =
            (try? SentCaptureRules.stripLabels(captures.map(\.sent)))
            ?? Array(repeating: nil, count: captures.count)
        let rows: [StackCaptureRow] = captures.enumerated().map { index, capture in
            // Port of the SPEC-DELTA-2B §E1 formula: annotations with a non-empty note plus, if it
            // has one, the note of the capture itself.
            let annotationNoteCount = capture.annotations.filter { ExportText.hasContent($0.note) }.count
            let noteCount = annotationNoteCount + (ExportText.hasContent(capture.note) ? 1 : 0)
            return StackCaptureRow(
                id: capture.id, label: index < labels.count ? labels[index] : nil,
                thumbnail: thumbnail(for: capture), noteCount: noteCount, isSent: capture.sent,
                kind: capture.kind)
        }
        contentContainer.reload(rows: rows)
        contentContainer.setEmptyHintShortcut(captureShortcutLabel())
        noteStripGrowth(count: captures.count)
        // Before `layoutWindow()` and not after it (SPEC-DELTA-5 §1.1 L-2): the window takes its own
        // height from the list and from the footer, and a list settled afterwards would leave the
        // window a frame behind.
        applyListHeight()
        layoutWindow()
    }

    /// Port of `ScrollStripToEnd` (`EdgeStackWindow.xaml.cs:358`), SPEC-DELTA-5 §1.2 L-8. Called
    /// from a showing of the strip and from the two imports, and deliberately **not** from deleting,
    /// reordering or marking captures as sent: the bottom of the list is the wrong place to be
    /// taken to when the change was somewhere else.
    func scrollStripToEnd() {
        contentContainer.scrollToNewest()
    }

    /// R2 fix: `refresh()` keys its cache on `capture.id`, which survives a crop/resize/re-edit —
    /// without this, reopening and committing a capture would keep showing the pre-edit bitmap.
    func invalidateThumbnail(for id: SBGuid) {
        thumbnailCache.removeValue(forKey: id)
    }

    // MARK: - The limit of the strip (S-2)

    /// Port of `StripIsFull`: the strip holds twenty-six captures, sent ones included, and the number
    /// of the toast comes from the constant, never from the sentence. Every way of adding a capture
    /// asks this first; the ones that live in the coordinator (import, clipboard, capture, restore)
    /// call it through this window.
    @discardableResult
    func stripIsFull(adding: Int = 1) -> Bool {
        let count = coordinator?.workspace.session.captures.count ?? 0
        guard count + adding > SentCaptureRules.maxStripCaptures else { return false }
        showToast(
            format("В ленте максимум {0} снимков. Отправьте или удалите лишние", SentCaptureRules.maxStripCaptures))
        return true
    }

    /// Port of `NoteStripGrowth`: the soft limit, said once. Twenty-six captures fit the strip, but a
    /// chat usually takes about twenty images in one paste. Every way of adding a capture ends in
    /// `refresh()`, which is where this is counted.
    private func noteStripGrowth(count: Int) {
        guard count > SentCaptureRules.softStripWarning else {
            softLimitWarned = false
            return
        }
        guard !softLimitWarned else { return }
        softLimitWarned = true
        showToast(format("Чаты обычно принимают до {0} картинок за раз", SentCaptureRules.softStripWarning))
    }

    private func format(_ key: String, _ value: Int) -> String {
        MacUiText.text(key, language: coordinator?.language ?? "ru")
            .replacingOccurrences(of: "{0}", with: "\(value)")
    }

    private func showToast(_ text: String) {
        contentContainer.showToast(text)
    }

    // MARK: - Geometry (S-9)

    /// The working area the strip lives on. Finding 14: `NSScreen.main` follows key-window focus and
    /// is `nil` when Snapik has no key window, which made the placement nondeterministic; the primary
    /// display is the deterministic equivalent of "the screen" here.
    /// `internal` (not `private`): the capsule probe of the smoke run measures against the same
    /// working area the window is placed in, and on a CI runner that is not the screen of a desk.
    func workArea() -> NSRect {
        (NSScreen.screens.first ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    /// The working area of the screen a window of ours actually stands on, for the two places that
    /// clamp a strip the user has already moved (SPEC-DELTA-5 §2.6): a strip dragged onto the second
    /// monitor must not be pulled back by the frame of the first. Everything else — the first
    /// placement, the clamp of the width, the probes — keeps asking `workArea()`, so a machine with
    /// one screen answers exactly as it did before.
    private func workArea(for window: NSWindow?) -> NSRect {
        window?.screen?.visibleFrame ?? workArea()
    }

    /// Port of `PositionAtEdge` as it is left after the split (SPEC-DELTA-5 §1.1 L-7): the capsule,
    /// which has no `EnsureStripPlaced` of its own, and the first placement of the strip.
    private func positionAtEdge() {
        guard let window else { return }
        if isCapsuleMode {
            let work = workArea(for: window)
            let size = contentContainer.capsuleSize()
            let top = expandedTop > 0 ? expandedTop : work.maxY - 24
            // Port of `PositionCapsuleAtStrip` (`:825-829`), SPEC-DELTA-5 §1.1 L-6: the right edge
            // of the strip the capsule came from, not the right edge of the monitor. Both windows
            // carry the same 20-point field under their shadow, so the sides that are seen line up.
            let left = CGFloat(
                StripResizeGeometry.capsuleLeft(
                    stripLeft: Double(expandedLeft), stripWidth: Double(expandedWidth),
                    capsuleWidth: Double(size.width)))
            window.setFrame(
                NSRect(x: left, y: top - size.height, width: size.width, height: size.height),
                display: true)
            contentContainer.frame = NSRect(origin: .zero, size: size)
            return
        }
        placeStripInitially()
    }

    /// Port of `PlaceStripInitially` (`EdgeStackWindow.xaml.cs:887-906`): the stored width clamped by
    /// the working area, the height of the list, then the right edge of that area and a vertical
    /// middle that never starts above 24 points from its top. It happens **once**; every showing
    /// after it is `ensureStripPlaced()`, which leaves the strip where the user dragged it. The
    /// window is flush with the working area — the 20 points that are seen between the panel and the
    /// edge of the screen are the field that carries the shadow ([ТЗ№4 C6]).
    private func placeStripInitially() {
        guard let window else { return }
        let work = workArea()
        let settings = coordinator?.settings ?? HotkeySettings.default
        let width = CGFloat(StripResizeGeometry.clampWidth(settings.stackWidth, workWidth: Double(work.width)))
        applyListHeight()
        contentContainer.frame = NSRect(x: 0, y: 0, width: width, height: contentContainer.windowHeight())
        contentContainer.layoutSubtreeIfNeeded()

        let height = contentContainer.windowHeight()
        let inset = max(24, (work.height - height) / 2)
        let originY = min(max(work.maxY - inset - height, work.minY), work.maxY - height)
        window.setFrame(NSRect(x: work.maxX - width, y: originY, width: width, height: height), display: true)
        contentContainer.frame = NSRect(x: 0, y: 0, width: width, height: height)
    }

    /// Port of `EnsureStripPlaced` (`EdgeStackWindow.xaml.cs:908-917`), SPEC-DELTA-5 §1.1 L-7: a
    /// showing of a strip that has already been placed settles the height of the list and brings the
    /// rectangle back onto the screen **only** if it has left it. The width, the left edge and the
    /// top edge are the user's from here on: a strip dragged away from the edge used to jump back to
    /// it after every capture.
    private func ensureStripPlaced() {
        guard let window else { return }
        applyListHeight()
        let width = window.frame.width
        contentContainer.frame = NSRect(x: 0, y: 0, width: width, height: contentContainer.windowHeight())
        contentContainer.layoutSubtreeIfNeeded()

        let height = contentContainer.windowHeight()
        let work = workArea(for: window)
        // The top edge is held and the window grows downwards, as `layoutWindow()` does it; the
        // rectangle handed to Core is therefore the one the window is about to have, not the one it
        // has now. `restoreRect` knows Foundation alone, so it is given eight numbers (§2.5).
        let placed = StripResizeGeometry.restoreRect(
            x: Double(window.frame.minX), y: Double(window.frame.maxY - height),
            width: Double(width), height: Double(height),
            workX: Double(work.minX), workY: Double(work.minY),
            workWidth: Double(work.width), workHeight: Double(work.height))
        window.setFrame(
            NSRect(x: CGFloat(placed.x), y: CGFloat(placed.y), width: width, height: height), display: true)
        contentContainer.frame = NSRect(x: 0, y: 0, width: width, height: height)
    }

    /// Port of `ApplyListHeight` (`EdgeStackWindow.xaml.cs:876-882`), SPEC-DELTA-5 §1.1 L-2: the
    /// height of the list is the height of what it holds until the corner grip is dragged, and the
    /// number from the settings after that — a ceiling in the first case, the height itself in the
    /// second (`StripResizeGeometry.listHeight`). Written here and nowhere else: every path that
    /// changes the strip ends in `refresh()`, which is where this is called.
    private func applyListHeight() {
        let settings = coordinator?.settings ?? HotkeySettings.default
        let stored = StripResizeGeometry.clampListHeight(
            settings.stackHeight, workHeight: Double(workArea().height),
            chromeHeight: Double(contentContainer.chromeHeight()))
        contentContainer.listHeight = CGFloat(
            StripResizeGeometry.listHeight(
                count: contentContainer.rowCount, stored: stored, manual: settings.stackHeightManual))
    }

    /// The window follows the height of its content without walking about: the top right corner is
    /// held where it is and only the bottom edge moves.
    private func layoutWindow() {
        guard let window, !isCapsuleMode else { return }
        let height = contentContainer.windowHeight()
        let frame = window.frame
        guard abs(frame.height - height) > 0.5 else {
            contentContainer.frame = NSRect(origin: .zero, size: frame.size)
            return
        }
        let top = frame.maxY
        window.setFrame(NSRect(x: frame.minX, y: top - height, width: frame.width, height: height), display: true)
        contentContainer.frame = NSRect(x: 0, y: 0, width: frame.width, height: height)
    }

    /// Port of `BeginResize`/`OnWidthDragDelta`/`OnCornerDragDelta`: the whole geometry is taken once,
    /// at the start of the drag, and every figure below is measured **from** it —
    /// `StripResizeGeometry` then answers on the first pixel of the way back from a clamp instead of
    /// owing the travel already spent past it.
    private func runResize(kind: StackResizeKind, startEvent: NSEvent) {
        guard let window else { return }
        let work = workArea()
        let startFrame = window.frame
        let rightEdge = startFrame.maxX
        let topEdge = startFrame.maxY
        let startWidth = startFrame.width
        let startListHeight = contentContainer.listHeight
        let chrome = max(1, startFrame.height - startListHeight)
        // The pointer of the press itself, in screen points: a position read at the top of the loop
        // instead has already travelled by however long the first frame took.
        let startPointer = window.convertPoint(toScreen: startEvent.locationInWindow)

        while true {
            guard
                let next = window.nextEvent(
                    matching: [.leftMouseDragged, .leftMouseUp], until: .distantFuture, inMode: .eventTracking,
                    dequeue: true)
            else { break }
            if next.type == .leftMouseUp { break }

            let pointer = NSEvent.mouseLocation
            let resized = StripResizeGeometry.widthFromStart(
                right: Double(rightEdge), startWidth: Double(startWidth),
                pointerDelta: Double(pointer.x - startPointer.x), leftLimit: Double(work.minX))
            var height = startFrame.height
            if kind == .corner {
                // The pointer travels downwards in the Windows units the geometry is written in, and
                // downwards is a *smaller* y here; the room below the top edge of the window is the
                // working area seen the same way round.
                let listHeight = CGFloat(
                    StripResizeGeometry.listHeightFromStart(
                        startListHeight: Double(startListHeight),
                        pointerDelta: Double(startPointer.y - pointer.y), chromeHeight: Double(chrome),
                        top: 0, workBottom: Double(topEdge - work.minY)))
                contentContainer.listHeight = listHeight
                height = chrome + listHeight
            }
            let width = CGFloat(resized.width)
            window.setFrame(
                NSRect(x: CGFloat(resized.left), y: topEdge - height, width: width, height: height), display: true)
            contentContainer.frame = NSRect(x: 0, y: 0, width: width, height: height)
        }

        persistStackGeometry(kind: kind, startFrame: startFrame, startListHeight: startListHeight)
    }

    /// Port of `OnWidthDragCompleted`/`OnCornerDragCompleted` (`:956-957`, `:1004-1013`),
    /// SPEC-DELTA-5 §1.2 L-12. Windows has a handler for each grip; the loop here is one, so the
    /// two are told apart by `kind`: the width alone never writes the height and never raises the
    /// flag, and only a finished drag of the **corner** makes the stored height a manual one.
    private func persistStackGeometry(kind: StackResizeKind, startFrame: NSRect, startListHeight: CGFloat) {
        guard let window else { return }
        let width = Double(window.frame.width)
        let listHeight = Double(contentContainer.listHeight)
        // A press that moved nothing writes nothing: the first click of a double click on the grip
        // goes through this same loop, and a `manual = true` written by it would be taken back by
        // the second click a moment later — the strip would settle on its content either way, but
        // the settings file would have been written twice for a gesture that changed no geometry.
        guard abs(width - Double(startFrame.width)) > 0.5 || abs(listHeight - Double(startListHeight)) > 0.5
        else { return }
        mutateSettings { settings in
            settings.stackWidth = width
            if kind == .corner {
                settings.stackHeight = listHeight
                settings.stackHeightManual = true
            }
        }
    }

    // MARK: - The capsule (S-10)

    /// Port of `CollapseToCapsule`: the same window in another mode. The counter of the capsule shows
    /// what the header shows, and a capture taken while the strip is collapsed does not open it.
    func collapseToCapsule() {
        guard !isCapsuleMode, let window else { return }
        isCapsuleMode = true
        expandedWidth = window.frame.width
        expandedTop = window.frame.maxY
        // The whole rectangle is remembered, the left edge included; the height of the list is not,
        // on purpose — it follows the content, and captures may arrive while the strip stands
        // collapsed (`_expandedListHeight` was taken off Windows for the same reason).
        expandedLeft = window.frame.minX
        contentContainer.hideToast()
        contentContainer.setCollapsed(true)
        positionAtEdge()
    }

    /// Port of `ExpandFromCapsule` (`:795-822`), SPEC-DELTA-5 §1.1 L-6: the rectangle the strip had
    /// when it was collapsed, with the height of the list settled again from what the strip holds
    /// now. The working area is a frame to clamp against and not a place to move to — a strip
    /// dragged away from the edge comes back where it was left.
    func expandFromCapsule() {
        guard isCapsuleMode, let window else { return }
        isCapsuleMode = false
        contentContainer.setCollapsed(false)
        let work = workArea(for: window)
        let width = CGFloat(StripResizeGeometry.clampWidth(Double(expandedWidth), workWidth: Double(work.width)))
        applyListHeight()
        contentContainer.frame = NSRect(x: 0, y: 0, width: width, height: contentContainer.windowHeight())
        contentContainer.layoutSubtreeIfNeeded()
        let height = contentContainer.windowHeight()
        let placed = StripResizeGeometry.restoreRect(
            x: Double(expandedLeft), y: Double(expandedTop - height),
            width: Double(width), height: Double(height),
            workX: Double(work.minX), workY: Double(work.minY),
            workWidth: Double(work.width), workHeight: Double(work.height))
        // One `setFrame`, as `PlaceWindow` is one `SetWindowPos`: the strip must not be seen
        // travelling through a placement of its own between two assignments.
        window.setFrame(
            NSRect(x: CGFloat(placed.x), y: CGFloat(placed.y), width: width, height: height), display: true)
        contentContainer.frame = NSRect(x: 0, y: 0, width: width, height: height)
    }

    // MARK: - Topmost (S-12)

    private func applyTopmost() {
        let wanted = coordinator?.settings.stackTopmost ?? true
        window?.level = topmostSuspensions == 0 && wanted ? .floating : .normal
    }

    /// A dialog owned by the strip would otherwise open behind a floating strip. Suspensions nest (a
    /// dialog opened over another one), so the strip comes back on top only when the last one ends.
    func beginTopmostSuspension() {
        topmostSuspensions += 1
        applyTopmost()
    }

    func endTopmostSuspension() {
        topmostSuspensions = max(0, topmostSuspensions - 1)
        applyTopmost()
    }

    /// The same for a window that is modal: the suspension lasts exactly as long as the call does.
    func withTopmostSuspended<T>(_ body: () -> T) -> T {
        beginTopmostSuspension()
        defer { endTopmostSuspension() }
        return body()
    }

    private func toggleTopmost() {
        let desired = !(coordinator?.settings.stackTopmost ?? true)
        mutateSettings { $0.stackTopmost = desired }
        applyTopmost()
    }

    // MARK: - Settings

    /// Port of `MutateSettings`: the editor writes its own defaults into the same file, so a change
    /// made from the strip is applied on top of what is on disk right now and not on top of the
    /// snapshot taken at startup. A file that cannot be written leaves its error on screen and still
    /// applies the change to this session — an unreadable settings file must not freeze the panel.
    @discardableResult
    private func mutateSettings(_ change: (inout HotkeySettings) -> Void) -> Bool {
        guard let coordinator else { return false }
        var stored = coordinator.workspace.preferences
        change(&stored)
        var saved = true
        do {
            try stored.save(path: coordinator.workspace.settingsPath)
        } catch {
            setStatus(StatusStrings.couldNotSave("\(error)"), isError: true)
            saved = false
        }
        coordinator.applySettings(stored)
        return saved
    }

    private func captureShortcutLabel() -> String? {
        guard let settings = coordinator?.settings, settings.captureEnabled else { return nil }
        return HotkeyIdentifier.parse(settings.captureId).label
    }

    // MARK: - Clearing and leaving (S-13)

    /// Port of `ConfirmSessionDiscard`: clearing the strip and leaving the application delete the
    /// captures of the session from the disk, so both ask first. An empty strip has nothing to lose
    /// and never asks, and the question carries the box that turns it off.
    func confirmSessionDiscard() -> Bool {
        guard let coordinator else { return true }
        guard !coordinator.workspace.session.captures.isEmpty, coordinator.settings.confirmSessionDiscard else {
            return true
        }
        let answer = withTopmostSuspended { DiscardSessionSheet.ask(language: coordinator.language) }
        guard answer.confirmed else { return false }
        // A settings file that cannot be written leaves its own error on screen and must not stop the
        // deletion the user has just confirmed.
        if answer.doNotAskAgain { mutateSettings { $0.confirmSessionDiscard = false } }
        return true
    }

    private func clearStackFromUser() {
        guard confirmSessionDiscard(), let coordinator else { return }
        Task { @MainActor [weak self] in
            // Clearing gives the clipboard back; a rotation does not (S-12, `ClearStackAsync`).
            guard await coordinator.clearStack() else { return }
            guard let self else { return }
            self.softLimitWarned = false
            self.reveal()
            self.contentContainer.showToast(MacUiText.text("Лента очищена", language: coordinator.language))
        }
    }

    private func quitFromUser() {
        guard confirmSessionDiscard() else { return }
        NSApp.terminate(nil)
    }

    // MARK: - Thumbnails

    private func thumbnail(for capture: CaptureItem) -> NSImage? {
        if let cached = thumbnailCache[capture.id] { return cached }
        guard let coordinator else { return nil }
        let url = coordinator.workspace.sessionDirectory.appendingPathComponent(capture.sourceImagePath)
        guard let cgImage = ImageCodec.loadImage(at: url) else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: capture.pixelWidth, height: capture.pixelHeight))
        thumbnailCache[capture.id] = image
        return image
    }
}

extension EdgeStackWindowController: EdgeStackContentViewDelegate {
    func edgeStackContentDidRequestNewCapture() {
        guard !stripIsFull() else { return }
        Task { @MainActor in await coordinator?.newCapture() }
    }

    func edgeStackContentDidRequestHide() {
        hide()
    }

    func edgeStackContentDidRequestCollapse() {
        collapseToCapsule()
    }

    func edgeStackContentDidRequestExpand() {
        expandFromCapsule()
    }

    func edgeStackContentDidRequestClear() {
        clearStackFromUser()
    }

    func edgeStackContent(_ view: EdgeStackContentView, didRequestMoreMenuAt anchor: NSView) {
        showMoreMenu(anchor: anchor)
    }

    func edgeStackContent(_ view: EdgeStackContentView, didOpenCaptureId id: SBGuid) {
        Task { @MainActor in await coordinator?.openCapture(id) }
    }

    func edgeStackContent(_ view: EdgeStackContentView, didRequestRemoveCaptureId id: SBGuid) {
        awaitingDeleteToast = true
        Task { @MainActor in await coordinator?.removeCapture(id) }
    }

    func edgeStackContent(_ view: EdgeStackContentView, didReorderCaptureId id: SBGuid, toIndex index: Int) {
        Task { @MainActor in await coordinator?.reorderCapture(captureId: id, toIndex: index) }
    }

    func edgeStackContent(_ view: EdgeStackContentView, didRequestDragWith event: NSEvent) {
        window?.performDrag(with: event)
    }

    /// Port of `OnCornerGripPress` (`:996-1002`), SPEC-DELTA-5 §1.2 L-12: a double click on the
    /// corner grip is the "size to content" gesture, and it gives the strip back to what it holds.
    /// `NSEvent.clickCount` is counted by the system on the press itself, so the `Preview` trick
    /// Windows needs against a `Thumb` that captures the mouse has no equivalent here.
    func edgeStackContent(_ view: EdgeStackContentView, didRequestResize kind: StackResizeKind, with event: NSEvent) {
        if kind == .corner, event.clickCount == 2 {
            mutateSettings { $0.stackHeightManual = false }
            applyListHeight()
            layoutWindow()
            return
        }
        runResize(kind: kind, startEvent: event)
    }

    /// Port of `OnCaptureThumbMouseEnter`/`OnCaptureListMouseWheel` (SPEC-DELTA-2 §1.6): the
    /// hover/scroll tick, throttled and suppressed after the shutter by `UiSoundService` itself.
    func edgeStackContentDidRequestTickSound(_ view: EdgeStackContentView) {
        UiSoundService.tick(coordinator?.settings ?? .default)
    }

    func edgeStackContentDidChangeContentHeight(_ view: EdgeStackContentView) {
        layoutWindow()
    }

    /// Port of `OnMoreClick` (`:918-937`), items in the order of the Windows menu. [ТЗ№4 S-11] the
    /// check mark of "Поверх других окон" is `NSMenuItem.state`: AppKit draws the column itself, and
    /// a glyph of our own would sit next to it.
    private func showMoreMenu(anchor: NSView) {
        guard let coordinator else { return }
        let language = coordinator.language
        let menu = NSMenu()

        let topmostItem = makeItem("Поверх других окон", language: language) { [weak self] in self?.toggleTopmost() }
        topmostItem.state = coordinator.settings.stackTopmost ? .on : .off
        menu.addItem(topmostItem)
        menu.addItem(.separator())

        menu.addItem(makeItem("Импортировать файл…", language: language) { Task { @MainActor in await coordinator.importFiles() } })
        menu.addItem(makeItem("Вставить изображение из буфера", language: language) { Task { @MainActor in await coordinator.importFromClipboard() } })
        if coordinator.hasRemovedCapture {
            menu.addItem(makeItem("Вернуть удалённый снимок", language: language) { Task { @MainActor in await coordinator.restoreRemoved() } })
        }
        menu.addItem(makeItem("Очистить ленту", language: language) { [weak self] in self?.clearStackFromUser() })
        menu.addItem(.separator())
        menu.addItem(makeItem("Копировать пакет", language: language) { Task { @MainActor in await coordinator.copyPackage() } })
        menu.addItem(makeItem("Сохранить пакет…", language: language) { Task { @MainActor in await coordinator.savePackageAs() } })
        menu.addItem(makeItem("Настройки", language: language) { [weak self] in self?.openSettings() })
        menu.addItem(.separator())
        menu.addItem(makeItem("Выйти", language: language) { [weak self] in self?.quitFromUser() })

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: anchor)
    }

    private func makeItem(_ title: String, language: String, action: @escaping () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: MacUiText.text(title, language: language), action: #selector(menuAction(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = action
        return item
    }

    @objc private func menuAction(_ sender: NSMenuItem) {
        (sender.representedObject as? () -> Void)?()
    }

    /// Shown from both the "•••" menu and the menu-bar "Настройки" item (which also reveals the strip
    /// first, SPEC §1.1 point 2). Reuses the window that is already open.
    func openSettings() {
        guard let coordinator else { return }
        if let existing = settingsWindowController {
            existing.showWindow(self)
            return
        }
        let settingsController = HotkeySettingsWindowController(coordinator: coordinator)
        settingsWindowController = settingsController
        // The settings window is not modal here, so the suspension lasts until it closes and not
        // until the call that opened it returns.
        beginTopmostSuspension()
        settingsController.onClosed = { [weak self] in
            self?.settingsWindowController = nil
            self?.endTopmostSuspension()
        }
        // [ТЗ№4 A7] "Пройти знакомство заново" ends the same way the first run does: the strip comes
        // back on the screen without being activated.
        settingsController.onOnboardingFinished = { [weak self] in self?.reveal() }
        settingsController.showWindow(self)
    }
}
