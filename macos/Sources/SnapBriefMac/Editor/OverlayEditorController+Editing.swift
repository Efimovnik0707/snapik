// Port of `SetupEditor`, `OnToolClick`, `OnColorClick`, `OnThicknessClick`, `OnMoreToolsClick`,
// `OnCropRequested` (`OverlayEditorWindow.xaml.cs:228-337,668-714`), SPEC §1.3, §6.2, §6.3.
import AppKit
import SnapBriefCore

/// Port of `CropBorder` (`OverlayEditorWindow.xaml:45`): a 2pt `#2F8CFF` border with a transparent
/// interior, hosting the `AnnotationCanvasView`.
@MainActor
final class CropBorderContainerView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
        path.lineWidth = 2
        EditorTheme.cropBorder.setStroke()
        path.stroke()
    }
}

@MainActor
extension OverlayEditorController {
    /// Port of `SetupEditor` (`:228-257`). `setupEditor()` is re-run after every crop/resize/
    /// undo-redo restore, not just the initial capture — finding 20: only the very first call
    /// (fresh selection or `presentExisting`) should default the tool to Rectangle; every later
    /// call preserves whatever tool was active, matching the Windows source (`SetupEditor` there
    /// does not touch the active tool at all; only initial construction does).
    func setupEditor() {
        guard let capture, let screenIndex = activeScreenIndex else { return }
        settingUp = true
        let slot = slots[screenIndex]
        slot.contentView.hintView.isHidden = true
        slot.contentView.holeRectLocal = cropRectLocal

        // `canvasContainerView` is created only on the very first `setupEditor()` call for this
        // controller and never torn down mid-session (`teardownEditingViews()` is reserved for a
        // future "edit again" flow — see its doc comment below), so `== nil` doubles as "is this
        // the first call" for the tool-reset decision above.
        let isInitialSetup = canvasContainerView == nil
        if canvasContainerView == nil {
            let container = CropBorderContainerView(frame: cropRectLocal)
            let canvas = AnnotationCanvasView(frame: NSRect(origin: .zero, size: cropRectLocal.size))
            canvas.autoresizingMask = [.width, .height]
            canvas.imagePadding = 0
            wireCanvasCallbacks(canvas)
            container.addSubview(canvas)
            slot.contentView.addSubview(container)
            canvasContainerView = container
            canvasView = canvas
        } else {
            canvasContainerView?.frame = cropRectLocal
            canvasView?.frame = NSRect(origin: .zero, size: cropRectLocal.size)
        }

        if isInitialSetup {
            canvasView?.tool = .rectangle
        }
        canvasView?.language = language
        canvasView?.activeColor = EditorTheme.annotationPalette[colorIndex]
        canvasView?.activeThickness = thicknesses[thicknessIndex]
        canvasView?.capture = capture

        if toolbarView == nil {
            let toolbar = EditorToolbarView(language: language)
            toolbar.onToolSelected = { [weak self] tool in self?.selectTool(tool) }
            wireToolbarActions(toolbar)
            slot.contentView.addSubview(toolbar)
            toolbarView = toolbar
        }
        toolbarView?.setActiveTool(canvasView?.tool ?? .rectangle)

        setupCaptureHandles(on: slot)

        // ShotNoteChip text/title is applied lazily when it is (re)opened (SPEC §1.4).
        lastSnapshot = snapshotState()
        refreshLabels()
        rebuildChips(on: slot)
        updateContextNoteAffordance(annotation: nil)
        positionToolbar()
        window(for: screenIndex)?.makeFirstResponder(canvasView)
        settingUp = false
    }

    func window(for screenIndex: Int) -> AppKit.NSWindow? {
        slots[screenIndex].window
    }

    /// Removes every editing-mode subview (used by `commit`/`cancelEditing` before `close()`
    /// tears down the windows themselves, and available for a future "edit again" flow).
    func teardownEditingViews() {
        canvasContainerView?.removeFromSuperview()
        toolbarView?.removeFromSuperview()
        shotNoteChipView?.removeFromSuperview()
        contextNoteButtonView?.removeFromSuperview()
        for handle in captureHandleViews { handle.removeFromSuperview() }
        resizeOutlineView?.removeFromSuperview()
        for chip in chipViews.values { chip.removeFromSuperview() }
        canvasContainerView = nil
        canvasView = nil
        toolbarView = nil
        shotNoteChipView = nil
        contextNoteButtonView = nil
        captureHandleViews = []
        resizeOutlineView = nil
        chipViews.removeAll()
    }

    private func wireCanvasCallbacks(_ canvas: AnnotationCanvasView) {
        canvas.onAnnotationCreated = { [weak self] annotation in self?.annotationCreated(annotation) }
        canvas.onSelectionChanged = { [weak self] annotation in self?.selectionChanged(annotation) }
        canvas.onAnnotationChanged = { [weak self] in self?.annotationChanged() }
        canvas.onCropRequested = { [weak self] bounds in self?.cropRequested(bounds) }
    }

    private func wireToolbarActions(_ toolbar: EditorToolbarView) {
        toolbar.moreToolsButton.onClick = { [weak self] in self?.showMoreToolsMenu() }
        toolbar.commentButton.onClick = { [weak self] in self?.commentButtonClicked() }
        toolbar.undoButton.onClick = { [weak self] in self?.performUndo() }
        toolbar.redoButton.onClick = { [weak self] in self?.performRedo() }
        toolbar.saveButton.onClick = { [weak self] in self?.saveToFile() }
        toolbar.addCaptureButton.onClick = { [weak self] in self?.commit(addNext: true) }
        toolbar.doneButton.onClick = { [weak self] in self?.commit(addNext: false) }
    }

    // MARK: - Tool / color / thickness (SPEC §1.3)

    func selectTool(_ tool: EditorTool) {
        canvasView?.tool = tool
        toolbarView?.setActiveTool(tool)
        window(for: activeScreenIndex ?? 0)?.makeFirstResponder(canvasView)
    }

    /// Port of `OnColorClick` (`:288-293`).
    func cycleColor() {
        colorIndex = (colorIndex + 1) % EditorTheme.annotationPalette.count
        canvasView?.activeColor = EditorTheme.annotationPalette[colorIndex]
    }

    /// Port of `OnThicknessClick` (`:295-300`).
    func cycleThickness() {
        thicknessIndex = (thicknessIndex + 1) % thicknesses.count
        canvasView?.activeThickness = thicknesses[thicknessIndex]
    }

    /// Port of `OnMoreToolsClick` (`:302-329`). `target` only needs to outlive this call:
    /// `NSMenu.popUp(positioning:at:in:)` runs its own modal event-tracking loop and does not
    /// return until the menu closes, so a local `let` is enough to keep it alive for every click.
    func showMoreToolsMenu() {
        guard let toolbar = toolbarView else { return }
        let target = MoreToolsMenuTarget(controller: self)
        let menu = NSMenu()
        menu.addItem(withTitle: "\(EditorStrings.toolPen(language))    P", action: #selector(MoreToolsMenuTarget.selectPen), keyEquivalent: "")
        menu.addItem(withTitle: "\(EditorStrings.toolHighlight(language))    H", action: #selector(MoreToolsMenuTarget.selectHighlight), keyEquivalent: "")
        menu.addItem(withTitle: "\(EditorStrings.toolText(language))    T", action: #selector(MoreToolsMenuTarget.selectText), keyEquivalent: "")
        menu.addItem(withTitle: "\(EditorStrings.toolConcealSolid(language))    X", action: #selector(MoreToolsMenuTarget.selectConceal), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: EditorStrings.annotationColor(language), action: #selector(MoreToolsMenuTarget.cycleColor), keyEquivalent: "")
        menu.addItem(withTitle: "\(EditorStrings.thickness(language)) \u{00B7} \(EditorStrings.thicknessLabel(thicknesses[thicknessIndex]))", action: #selector(MoreToolsMenuTarget.cycleThickness), keyEquivalent: "")
        for item in menu.items {
            item.target = target
            item.attributedTitle = NSAttributedString(string: item.title, attributes: [.foregroundColor: NSColor.white])
        }
        let anchor = CGPoint(x: 0, y: toolbar.moreToolsButton.frame.maxY)
        menu.popUp(positioning: nil, at: toolbar.convert(anchor, from: toolbar.moreToolsButton), in: toolbar)
    }

    // MARK: - In-canvas crop (SPEC §1.3 "Crop как отдельный случай")

    /// Port of `OnCropRequested` (`:668-714`).
    private func cropRequested(_ bounds: CGRect) {
        guard let capture, !busyCrop, !isModalOpen, captureResizeCorner < 0, canvasView?.manipulating != true else { return }
        guard let pixelRect = EditorGeometry.cropRequestPixelRect(bounds: bounds, imageWidth: capture.image.width, imageHeight: capture.image.height) else { return }
        guard let cropped = capture.image.cropping(to: pixelRect) else { return }

        busyCrop = true
        let before = snapshotState()
        let normalized = EditorGeometry.normalizedRect(pixelRect: pixelRect, imageWidth: capture.image.width, imageHeight: capture.image.height)

        persistCurrentSource(cropped) { [weak self] result in
            guard let self else { return }
            self.busyCrop = false
            switch result {
            case .success(let relativePath):
                do {
                    let coreResult = try CaptureCropper.crop(
                        source: capture.toCore(), cropBounds: normalized, croppedSourceImagePath: relativePath,
                        croppedPixelWidth: Int(pixelRect.width), croppedPixelHeight: Int(pixelRect.height))
                    let updated = EditorCapture.fromCore(coreResult.croppedCapture, image: cropped)
                    updated.displayLabel = capture.displayLabel
                    self.capture = updated
                    self.cropRectLocal = EditorGeometry.rescaledCropRect(
                        oldCropRectLocal: self.cropRectLocal, pixelRect: pixelRect,
                        imageWidth: capture.image.width, imageHeight: capture.image.height)
                    if let before { self.history.pushWithoutClearingRedo(before) }
                    self.history.clearRedo()
                    self.setupEditor()
                    self.selectTool(.select)
                } catch {
                    self.showHintError(EditorStrings.couldNotCropCapture(self.language, "\(error)"))
                }
            case .failure(let error):
                self.showHintError(EditorStrings.couldNotCropCapture(self.language, "\(error)"))
            }
        }
    }
}

/// `NSMenu` requires an `@objc` target/selector pair; this small `NSObject` forwards each item to
/// the controller via a weak reference (the controller itself is a plain Swift class, not
/// `NSObject`, so it cannot be a menu target directly). `NSObject` itself isn't main-actor by
/// default, and every forwarding method below calls into the now-`@MainActor` controller, so this
/// needs its own explicit annotation (finding 2) — `NSMenu.popUp` only ever invokes these targets
/// synchronously from the main thread's event-tracking loop, so this is not a change in behavior.
@MainActor
final class MoreToolsMenuTarget: NSObject {
    weak var controller: OverlayEditorController?

    init(controller: OverlayEditorController) {
        self.controller = controller
    }

    @objc func selectPen() { controller?.selectTool(.pen) }
    @objc func selectHighlight() { controller?.selectTool(.highlight) }
    @objc func selectText() { controller?.selectTool(.text) }
    @objc func selectConceal() { controller?.selectTool(.conceal) }
    @objc func cycleColor() { controller?.cycleColor() }
    @objc func cycleThickness() { controller?.cycleThickness() }
}
