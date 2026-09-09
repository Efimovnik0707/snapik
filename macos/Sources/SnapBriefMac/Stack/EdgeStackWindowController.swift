// Port of `EdgeStackWindow.xaml(.cs)` window chrome, positioning and the "•••" menu, SPEC §1.9,
// §6.4, §9.8.
import AppKit
import SnapBriefCore

/// Non-activating panel: `.borderless`, `.nonactivatingPanel`, normal level (SPEC says explicitly
/// *not* topmost), excluded from other apps' screen captures.
final class EdgeStackPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class EdgeStackWindowController: NSWindowController {
    weak var coordinator: AppCoordinator?

    private let contentContainer: EdgeStackContentView
    private var thumbnailCache: [SBGuid: NSImage] = [:]
    private var settingsWindowController: HotkeySettingsWindowController?

    var isVisible: Bool { window?.isVisible ?? false }

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        let panel = EdgeStackPanel(
            contentRect: NSRect(x: 0, y: 0, width: StackMetrics.width, height: ThemeMetrics.stackMinHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .normal
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.isExcludedFromWindowsMenu = true
        // Port of `SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE)` (SPEC §9.8).
        panel.sharingType = WindowCaptureExclusion.sharingType
        panel.title = "SnapBrief — Стопка снимков"

        contentContainer = EdgeStackContentView(
            frame: NSRect(x: 0, y: 0, width: StackMetrics.width, height: ThemeMetrics.stackMinHeight))
        panel.contentView = contentContainer

        super.init(window: panel)
        contentContainer.delegate = self
        contentContainer.applyLocalization(language: coordinator.language)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Visibility (SPEC §1.9 "Появление стопки")

    /// Port of `ShowStackWithoutActivation`: reposition, order to top without stealing focus,
    /// re-apply language, animate the fade-in over **180 ms**.
    func reveal() {
        refresh()
        positionAtEdge()
        window?.alphaValue = 0
        // `orderFrontRegardless()` shows the window without activating the app (SPEC §9.8).
        window?.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { [weak self] context in
            context.duration = TimeInterval(ThemeMetrics.stackAppearAnimationSeconds)
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self?.window?.animator().alphaValue = 1
        }
    }

    /// Port of the crestik/`HideStack` behavior: just hides the window, captures/session are
    /// untouched.
    func hide() {
        window?.orderOut(nil)
    }

    func setStatus(_ text: String, isError: Bool) {
        contentContainer.setStatus(text, isError: isError)
        resizeToFitContent()
    }

    func updateRestoreButtonVisibility(_ visible: Bool) {
        contentContainer.setRestoreVisible(visible)
        resizeToFitContent()
    }

    func updateLanguage(_ language: String) {
        contentContainer.applyLocalization(language: language)
    }

    /// Reloads capture thumbnails/labels from the current session and re-lays-out the window.
    func refresh() {
        guard let coordinator else { return }
        let captures = coordinator.workspace.session.captures
        // R2 fix: drop any cached thumbnail for a capture no longer in the session (deleted, or
        // left behind by a session rotation), so a stale bitmap can never resurface for a
        // different capture that later reuses the same id.
        let liveIds = Set(captures.map(\.id))
        thumbnailCache = thumbnailCache.filter { liveIds.contains($0.key) }
        let rows: [StackCaptureRow] = captures.enumerated().map { index, capture in
            let label = (try? CaptureLabels.forIndex(index)) ?? "?"
            // Port of the SPEC-DELTA-2B §E1 `refresh()` formula: annotations with a non-empty
            // note plus (if present) the whole-capture note itself. A `.comment` pin with no text
            // does not count (matches `CaptureLabels.forNotedAnnotations` not numbering it).
            let annotationNoteCount = capture.annotations.filter { ExportText.hasContent($0.note) }.count
            let noteCount = annotationNoteCount + (ExportText.hasContent(capture.note) ? 1 : 0)
            return StackCaptureRow(id: capture.id, label: label, thumbnail: thumbnail(for: capture), noteCount: noteCount)
        }
        contentContainer.reload(rows: rows)
        resizeToFitContent()
    }

    /// Port of `EdgeStackWindow.Preview.cs:17,43` (`capture.IsSelected`), called by
    /// `AppCoordinator.openCapture`/its `present(on:completion:)` closure while the preview
    /// window is open (SPEC-DELTA-2B §D "Интеграция в shell").
    func setSelectedCapture(_ id: SBGuid?) {
        contentContainer.setSelectedCapture(id)
    }

    /// R2 fix: `refresh()`'s cache lookup keys only on `capture.id`, which never changes across a
    /// crop/resize/re-edit — without this, reopening and committing a capture (`replaceCapture`)
    /// would keep showing the pre-edit thumbnail bitmap forever. Called by
    /// `AppCoordinator.overlayEditor(_:didCommit:)` for its `replaceCapture` branch.
    func invalidateThumbnail(for id: SBGuid) {
        thumbnailCache.removeValue(forKey: id)
    }

    private func thumbnail(for capture: CaptureItem) -> NSImage? {
        if let cached = thumbnailCache[capture.id] { return cached }
        guard let coordinator else { return nil }
        let url = coordinator.workspace.sessionDirectory.appendingPathComponent(capture.sourceImagePath)
        guard let cgImage = ImageCodec.loadImage(at: url) else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: capture.pixelWidth, height: capture.pixelHeight))
        thumbnailCache[capture.id] = image
        return image
    }

    private func resizeToFitContent() {
        guard let window else { return }
        let height = contentContainer.preferredHeight()
        var frame = window.frame
        let deltaHeight = height - frame.height
        frame.origin.y -= deltaHeight
        frame.size.height = height
        frame.size.width = StackMetrics.width
        window.setFrame(frame, display: true)
        contentContainer.frame = NSRect(x: 0, y: 0, width: StackMetrics.width, height: height)
    }

    /// Port of `PositionAtEdge` (`EdgeStackWindow.xaml.cs:364-369`): right edge, vertically
    /// centered, never above 24pt from the top of the work area.
    private func positionAtEdge() {
        // Finding 14: `NSScreen.main` follows key-window focus (nil when SnapBrief itself has no
        // key window), which made positioning nondeterministic; the primary display
        // (`NSScreen.screens.first`) is the deterministic Windows-equivalent of "the screen".
        guard let window, let screen = NSScreen.screens.first else { return }
        let workArea = screen.visibleFrame
        let height = max(window.frame.height, ThemeMetrics.stackMinHeight)
        let x = workArea.maxX - StackMetrics.width - ThemeMetrics.stackEdgeInset
        let y = max(
            workArea.minY + (workArea.height - height) / 2,
            workArea.maxY - 24 - height)
        window.setFrame(NSRect(x: x, y: y, width: StackMetrics.width, height: height), display: false)
    }
}

extension EdgeStackWindowController: EdgeStackContentViewDelegate {
    func edgeStackContentDidRequestNewCapture() {
        Task { @MainActor in await coordinator?.newCapture() }
    }

    func edgeStackContentDidRequestHide() {
        hide()
    }

    func edgeStackContent(_ view: EdgeStackContentView, didRequestMoreMenuAt anchor: NSView) {
        showMoreMenu(anchor: anchor)
    }

    func edgeStackContent(_ view: EdgeStackContentView, didOpenCaptureId id: SBGuid) {
        Task { @MainActor in await coordinator?.openCapture(id) }
    }

    func edgeStackContent(_ view: EdgeStackContentView, didRequestRemoveCaptureId id: SBGuid) {
        Task { @MainActor in await coordinator?.removeCapture(id) }
    }

    func edgeStackContent(_ view: EdgeStackContentView, didReorderCaptureId id: SBGuid, toIndex index: Int) {
        Task { @MainActor in await coordinator?.reorderCapture(captureId: id, toIndex: index) }
    }

    func edgeStackContentDidRequestRestore() {
        Task { @MainActor in await coordinator?.restoreRemoved() }
    }

    func edgeStackContentHeaderMouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    /// Port of `OnCaptureThumbMouseEnter`/`OnCaptureListMouseWheel` (SPEC-DELTA-2 §1.6): the
    /// hover/scroll tick, throttled and suppressed after the capture shutter by
    /// `CaptureFeedbackSound.tick` itself.
    func edgeStackContentDidRequestTickSound(_ view: EdgeStackContentView) {
        CaptureFeedbackSound.tick(enabled: coordinator?.settings.playSounds ?? true)
    }

    /// Port of `OnMoreClick` (`:437-453`), items in order (SPEC §1.9).
    private func showMoreMenu(anchor: NSView) {
        guard let coordinator else { return }
        let language = coordinator.language
        let menu = NSMenu()

        menu.addItem(makeItem("Импортировать файл…", language: language) { Task { @MainActor in await coordinator.importFiles() } })
        menu.addItem(makeItem("Вставить изображение из буфера", language: language) { Task { @MainActor in await coordinator.importFromClipboard() } })
        if coordinator.hasRemovedCapture {
            menu.addItem(makeItem("Вернуть удалённый снимок", language: language) { Task { @MainActor in await coordinator.restoreRemoved() } })
        }
        menu.addItem(makeItem("Новая сессия", language: language) { Task { @MainActor in await coordinator.startNewSession() } })
        menu.addItem(.separator())
        menu.addItem(makeItem("Копировать пакет", language: language) { Task { @MainActor in await coordinator.copyPackage() } })
        menu.addItem(makeItem("Сохранить пакет…", language: language) { Task { @MainActor in await coordinator.savePackageAs() } })
        menu.addItem(makeItem("Настройки", language: language) { [weak self] in self?.openSettings() })
        menu.addItem(.separator())
        menu.addItem(makeItem("Выйти", language: language) { NSApp.terminate(nil) })

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.height), in: anchor)
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

    /// Shown from both the "•••" menu and the status-bar "Настройки" item (which also reveals
    /// the stack first, SPEC §1.1 point 2). Reuses the existing window if one is already open.
    func openSettings() {
        guard let coordinator else { return }
        if let existing = settingsWindowController {
            existing.showWindow(self)
            return
        }
        let settingsController = HotkeySettingsWindowController(coordinator: coordinator)
        settingsWindowController = settingsController
        settingsController.onClosed = { [weak self] in self?.settingsWindowController = nil }
        settingsController.showWindow(self)
    }
}
