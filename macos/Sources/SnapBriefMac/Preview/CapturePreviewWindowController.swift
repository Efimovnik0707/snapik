// Port of `CapturePreviewWindow.xaml(.cs)` (window chrome, zoom, fullscreen, keyboard, debounced
// persist), SPEC-DELTA-2 §1.5, SPEC-DELTA-2B §D. Called from `AppCoordinator.openCapture`
// (core-shell's zone) per `CONTRACTS.md` "Дополнение sync 2".
import AppKit
import SnapBriefCore

/// `.titled + .fullSizeContentView + .resizable` per SPEC-DELTA-2 §1.5's accepted decision;
/// standard buttons are hidden rather than removed from the style mask (removing them would
/// disable resizing). `onKeyDown` intercepts Esc/F11/Cmd+Ctrl+F/Cmd+0/1/+/- before normal
/// `keyDown` delivery reaches the first responder (e.g. a comment's `NSTextView`), matching
/// `PreviewKeyDown` being a `Window`-level `PreviewKeyDown` handler on Windows.
final class CapturePreviewWindow: NSWindow {
    var onKeyDown: ((NSEvent) -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let onKeyDown, onKeyDown(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if let onKeyDown, onKeyDown(event) { return }
        super.keyDown(with: event)
    }
}

@MainActor
final class CapturePreviewWindowController: NSWindowController, NSWindowDelegate {
    private let model: PreviewCommentsModel
    private let sourceImage: CGImage
    private let language: String
    private let persist: (CaptureItem) async -> Void

    private let rootView = NSView()
    private let headerView = PreviewHeaderView(frame: .zero)
    private let imageContainer = NSView()
    private let imageScrollView = PreviewImageScrollView(frame: .zero)
    private let commentsPanel = PreviewCommentsPanelView(frame: .zero)

    private var completion: ((Bool) -> Void)?
    private var markupRequested = false
    private var fitToWindow = true
    private var zoom: CGFloat = 1
    private var canAutoClose = false
    private var closing = false
    private var isFullscreen = false
    private var savedFrameBeforeFullscreen: NSRect?
    private var previousFrontmostApplication: NSRunningApplication?
    private var saveTimer: Timer?
    private var persistTask: Task<Void, Never>?

    init(
        capture: CaptureItem,
        image: CGImage,
        displayLabel: String,
        language: String,
        playSounds: Bool,
        persist: @escaping (CaptureItem) async -> Void
    ) {
        self.sourceImage = image
        self.language = language
        self.persist = persist
        self.model = PreviewCommentsModel(capture: capture, displayLabel: displayLabel, language: language)
        _ = playSounds // Reserved: the preview window itself plays no capture/tick sounds (SPEC-DELTA-2 §1.6 only wires those into the stack and the capture commit path).

        let window = CapturePreviewWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
            styleMask: [.titled, .fullSizeContentView, .resizable, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = false
        window.backgroundColor = NSColor(hex: "#101318")
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 720, height: 500)
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        super.init(window: window)
        window.delegate = self

        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor(hex: "#101318").cgColor
        imageContainer.addSubview(imageScrollView)
        rootView.addSubview(imageContainer)
        rootView.addSubview(commentsPanel)
        rootView.addSubview(headerView)
        window.contentView = rootView

        headerView.onZoomOut = { [weak self] in guard let self else { return }; self.setZoom(self.zoom / 1.2) }
        headerView.onZoomIn = { [weak self] in guard let self else { return }; self.setZoom(self.zoom * 1.2) }
        headerView.onFit = { [weak self] in self?.enableFit() }
        headerView.onActualSize = { [weak self] in self?.setZoom(1) }
        headerView.onFullscreen = { [weak self] in self?.toggleFullscreen() }
        headerView.onMarkup = { [weak self] in self?.markupClicked() }
        headerView.onClose = { [weak self] in self?.closePreview() }
        headerView.onDrag = { [weak self] event in self?.window?.performDrag(with: event) }

        imageScrollView.onViewportResized = { [weak self] in self?.updateFitZoom() }

        commentsPanel.onAddComment = { [weak self] in self?.addComment() }
        commentsPanel.onTextChanged = { [weak self] id, text in self?.textChanged(id: id, text: text) }
        commentsPanel.onDelete = { [weak self] id in self?.deleteComment(id: id) }

        window.onKeyDown = { [weak self] event in self?.handleKeyDown(event) ?? false }

        applyLocalization()
        model.rebuild()
        commentsPanel.reload(entries: model.entries)
        headerView.configure(
            label: displayLabel, imageSize: CGSize(width: capture.pixelWidth, height: capture.pixelHeight))
        renderPreview()
        layoutContent()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Presentation

    /// Port of `ShowForAsync` + `OnSourceInitialized`: position within `screen`'s (or the primary
    /// screen's) work area, remember the previously-frontmost app so it can be restored on close,
    /// activate without stealing the caller's undo stack, and arm auto-close only after the
    /// window has settled (matches the `ApplicationIdle` dispatch on Windows).
    func present(on screen: NSScreen?, completion: @escaping (_ markupRequested: Bool) -> Void) {
        self.completion = completion
        guard let window else {
            completion(false)
            return
        }
        let targetScreen = screen ?? NSScreen.screens.first
        let workArea = targetScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let bounds = PreviewGeometry.previewBounds(workArea: workArea)
        window.minSize = bounds.minSize
        window.setFrame(bounds.frame, display: false)
        layoutContent()

        previousFrontmostApplication = NSWorkspace.shared.frontmostApplication
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.updateFitZoom()
            self?.canAutoClose = true
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        guard canAutoClose, !closing else { return }
        closePreview()
    }

    func windowDidResize(_ notification: Notification) {
        layoutContent()
        updateFitZoom()
    }

    // MARK: - Layout

    private func layoutContent() {
        guard let contentView = window?.contentView else { return }
        let bounds = contentView.bounds
        headerView.frame = CGRect(
            x: 0, y: bounds.height - PreviewHeaderView.height, width: bounds.width, height: PreviewHeaderView.height)

        let bodyHeight = max(0, bounds.height - PreviewHeaderView.height)
        let panelWidth = PreviewCommentsPanelView.width
        imageContainer.frame = CGRect(x: 12, y: 12, width: max(0, bounds.width - panelWidth - 18), height: max(0, bodyHeight - 24))
        imageScrollView.frame = imageContainer.bounds
        commentsPanel.frame = CGRect(x: imageContainer.frame.maxX + 6, y: 12, width: panelWidth, height: max(0, bodyHeight - 24))
    }

    // MARK: - Rendering

    private func renderPreview() {
        let rendered = PreviewRenderer.render(capture: model.capture, image: sourceImage, displayLabel: model.displayLabel) ?? sourceImage
        imageScrollView.setImage(rendered, size: CGSize(width: model.capture.pixelWidth, height: model.capture.pixelHeight))
    }

    // MARK: - Zoom

    private func setZoom(_ value: CGFloat) {
        fitToWindow = false
        zoom = min(max(value, 0.1), 4)
        applyZoom()
    }

    private func enableFit() {
        fitToWindow = true
        updateFitZoom()
    }

    private func updateFitZoom() {
        guard fitToWindow else { return }
        let viewport = imageScrollView.bounds.size
        let imageSize = CGSize(width: model.capture.pixelWidth, height: model.capture.pixelHeight)
        guard viewport.width > 8, viewport.height > 8 else { return }
        zoom = PreviewGeometry.fitZoom(viewport: viewport, image: imageSize)
        applyZoom()
    }

    private func applyZoom() {
        imageScrollView.setMagnification(zoom, centeredAt: .zero)
        headerView.setZoomText(Int((zoom * 100).rounded()))
        headerView.setFitActive(fitToWindow)
    }

    // MARK: - Fullscreen

    /// Port of `OnFullscreenClick`: toggling `WindowState.Maximized` — this is a plain
    /// frame-swap to `screen.visibleFrame`, per SPEC-DELTA-2's accepted decision, not
    /// `NSWindow.toggleFullScreen(_:)` (which would animate to a separate Space).
    private func toggleFullscreen() {
        guard let window else { return }
        isFullscreen.toggle()
        if isFullscreen {
            savedFrameBeforeFullscreen = window.frame
            if let screen = window.screen ?? NSScreen.screens.first {
                window.setFrame(screen.visibleFrame, display: true, animate: true)
            }
        } else if let saved = savedFrameBeforeFullscreen {
            window.setFrame(saved, display: true, animate: true)
        }
        headerView.updateFullscreenTooltip(isFullscreen: isFullscreen, language: language)
        DispatchQueue.main.async { [weak self] in self?.updateFitZoom() }
    }

    // MARK: - Comments

    private func addComment() {
        _ = model.addComment()
        commentsPanel.reload(entries: model.entries)
        renderPreview()
        queuePersist()
        DispatchQueue.main.async { [weak self] in self?.commentsPanel.scrollToLastAndFocus() }
    }

    private func textChanged(id: UUID, text: String) {
        guard let entry = model.entries.first(where: { $0.id == id }) else { return }
        model.setText(text, for: entry)
        queuePersist()
    }

    private func deleteComment(id: UUID) {
        guard let entry = model.entries.first(where: { $0.id == id }) else { return }
        model.delete(entry)
        commentsPanel.reload(entries: model.entries)
        renderPreview()
        queuePersist()
    }

    // MARK: - Persist

    /// Port of the `DispatcherTimer 360 мс` debounce + `_persistChain`: coalesce bursts of edits
    /// into one re-render + one `persist` call, chained (not concurrent) so writes stay ordered.
    private func queuePersist() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.36, repeats: false) { [weak self] _ in
            self?.saveTick()
        }
    }

    private func saveTick() {
        saveTimer = nil
        renderPreview()
        let capture = model.capture
        let previousTask = persistTask
        persistTask = Task { [persist] in
            await previousTask?.value
            await persist(capture)
        }
    }

    /// Port of `FlushEditsAsync`: called from `closePreview()` before firing `completion`.
    private func flushEdits() async {
        let pending = saveTimer != nil
        saveTimer?.invalidate()
        saveTimer = nil
        await persistTask?.value
        if pending { await persist(model.capture) }
    }

    // MARK: - Keyboard

    /// Port of `OnPreviewKeyDown`: Esc closes; F11 or Cmd+Ctrl+F toggles fullscreen; Cmd+0/1/+/-
    /// control zoom. Keycodes 53 (Esc) / 103 (F11) match `AnnotationCanvasView.Keycode` /
    /// `CapturePreviewWindow.xaml.cs:269-278`.
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 {
            closePreview()
            return true
        }
        if event.keyCode == 103 {
            toggleFullscreen()
            return true
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == [.command, .control], event.charactersIgnoringModifiers?.lowercased() == "f" {
            toggleFullscreen()
            return true
        }
        if flags == .command {
            switch event.charactersIgnoringModifiers {
            case "0": enableFit(); return true
            case "1": setZoom(1); return true
            case "=", "+": setZoom(zoom * 1.2); return true
            case "-": setZoom(zoom / 1.2); return true
            default: break
            }
        }
        return false
    }

    // MARK: - Close

    private func markupClicked() {
        markupRequested = true
        closePreview()
    }

    /// Port of `ClosePreview`/`OnClosed`: flush any pending debounced persist, close the window,
    /// then hand control back via `completion`, restoring the previously-frontmost app only when
    /// the user did not request markup (matching `if (!MarkupRequested) previous.Activate()`
    /// implied by `EdgeStackWindow.Preview.cs`'s subsequent `HideForCapture`/editor flow).
    private func closePreview() {
        guard !closing else { return }
        closing = true
        Task { [weak self] in
            guard let self else { return }
            await self.flushEdits()
            self.window?.close()
            let markup = self.markupRequested
            let previous = self.previousFrontmostApplication
            self.completion?(markup)
            if !markup {
                previous?.activate(options: [])
            }
        }
    }

    private func applyLocalization() {
        headerView.applyLocalization(language: language)
        commentsPanel.applyLocalization(language: language)
    }
}
