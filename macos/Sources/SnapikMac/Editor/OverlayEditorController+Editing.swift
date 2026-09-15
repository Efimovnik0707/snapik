// Port of `SetupEditor`, `OnToolClick`, `OnMoreToolsClick`, `OnCropRequested`
// (`OverlayEditorWindow.xaml.cs:228-337,668-714`), SPEC §1.3, §6.2, §6.3. Color/thickness
// (`OnColorClick`/`OnThicknessClick`) moved to `OverlayEditorController+Appearance.swift` (SPEC
// §1.3, §6.2 "Дополнение 2026-09-09").
import AppKit
import SnapikCore

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
        canvasView?.activeColor = activeColor
        canvasView?.activeThickness = activeThickness
        canvasView?.capture = capture

        if chipLayerView == nil {
            let layer = ChipLayerView(frame: NSRect(origin: .zero, size: slot.contentView.bounds.size))
            layer.autoresizingMask = [.width, .height]
            slot.contentView.addSubview(layer)
            chipLayerView = layer
        }

        if toolbarView == nil {
            let toolbar = EditorToolbarView(language: language)
            toolbar.onToolSelected = { [weak self] tool in self?.selectTool(tool) }
            wireToolbarActions(toolbar)
            slot.contentView.addSubview(toolbar)
            toolbarView = toolbar
        }
        toolbarView?.setActiveTool(canvasView?.tool ?? .rectangle)
        // Port of `SyncAppearance()` at the end of `SetupEditor` (`OverlayEditorWindow.xaml.cs:252`).
        syncAppearance()

        setupCaptureHandles(on: slot)

        lastSnapshot = snapshotState()
        refreshLabels()
        rebuildChips(on: slot)
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
        chipLayerView?.removeFromSuperview()
        for handle in captureHandleViews { handle.removeFromSuperview() }
        resizeOutlineView?.removeFromSuperview()
        chipViews.removeAll()
        canvasContainerView = nil
        canvasView = nil
        toolbarView = nil
        chipLayerView = nil
        captureHandleViews = []
        resizeOutlineView = nil
    }

    private func wireCanvasCallbacks(_ canvas: AnnotationCanvasView) {
        canvas.onAnnotationCreated = { [weak self] annotation in self?.annotationCreated(annotation) }
        canvas.onSelectionChanged = { [weak self] annotation in self?.selectionChanged(annotation) }
        canvas.onAnnotationChanged = { [weak self] in self?.annotationChanged() }
        canvas.onCropRequested = { [weak self] bounds in self?.cropRequested(bounds) }
        // SPEC-DELTA-2.md §1.3 "Text двойным кликом": show/focus that Text annotation's chip.
        canvas.onTextDoubleClicked = { [weak self] annotation in
            guard let self else { return }
            self.visibleChipIds.insert(annotation.id)
            if let chip = self.chipViews[annotation.id] {
                self.expandChip(annotation.id, expanded: true)
                chip.focusAndSelectAll()
            } else {
                self.addChip(for: annotation, focus: true)
            }
        }
    }

    private func wireToolbarActions(_ toolbar: EditorToolbarView) {
        toolbar.appearanceButton.onClick = { [weak self] in self?.toggleAppearancePopover() }
        toolbar.moreToolsButton.onClick = { [weak self] in self?.showMoreToolsMenu() }
        toolbar.commentButton.onClick = { [weak self] in self?.commentButtonClicked() }
        toolbar.arrowOptionsButton.onClick = { [weak self] in self?.showArrowStyleMenu() }
        toolbar.undoButton.onClick = { [weak self] in self?.performUndo() }
        toolbar.redoButton.onClick = { [weak self] in self?.performRedo() }
        toolbar.saveButton.onClick = { [weak self] in self?.saveToFile() }
        toolbar.doneButton.onClick = { [weak self] in self?.commit(addNext: false) }
    }

    // MARK: - Tool selection (SPEC §1.3)

    /// Port of `OnToolClick`/`SelectToolMode` (`OverlayEditorWindow.xaml.cs:293-301,332-340`),
    /// unified into one function on macOS. Both now deselect first (SPEC §1.3, §6.2 "Дополнение
    /// 2026-09-09": switching tools no longer leaves a stale selection driving the appearance
    /// popover) and resync the toolbar's appearance button / "•••" highlight afterward.
    func selectTool(_ tool: EditorTool) {
        canvasView?.selectAnnotation(id: nil)
        canvasView?.tool = tool
        toolbarView?.setActiveTool(tool)
        syncAppearance()
        window(for: activeScreenIndex ?? 0)?.makeFirstResponder(canvasView)
    }

    /// Port of `OnMoreToolsClick` (`:302-329`, updated in the 2026-09-09 sync to drop the
    /// separator and the "Цвет отметки"/"Толщина" cycling items — those moved to the appearance
    /// popover — and to mark the active extra tool with a checkmark). `target` only needs to
    /// outlive this call: `NSMenu.popUp(positioning:at:in:)` runs its own modal event-tracking
    /// loop and does not return until the menu closes, so a local `let` is enough to keep it alive
    /// for every click.
    /// SPEC-DELTA-2B.md §C6: "только Pen/Highlight/Conceal" — Text moved onto the main toolbar as
    /// a regular toggle button, so it no longer appears here.
    func showMoreToolsMenu() {
        guard let toolbar = toolbarView else { return }
        let target = MoreToolsMenuTarget(controller: self)
        let menu = NSMenu()
        let currentTool = canvasView?.tool

        func addTool(_ title: String, _ tool: EditorTool, _ action: Selector) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = target
            item.state = currentTool == tool ? .on : .off
            item.attributedTitle = NSAttributedString(string: title, attributes: [.foregroundColor: NSColor.white])
            menu.addItem(item)
        }

        addTool("\(EditorStrings.toolPen(language))    P", .pen, #selector(MoreToolsMenuTarget.selectPen))
        addTool("\(EditorStrings.toolHighlight(language))    H", .highlight, #selector(MoreToolsMenuTarget.selectHighlight))
        addTool("\(EditorStrings.toolConcealSolid(language))    X", .conceal, #selector(MoreToolsMenuTarget.selectConceal))

        let anchor = CGPoint(x: 0, y: toolbar.moreToolsButton.frame.maxY)
        menu.popUp(positioning: nil, at: toolbar.convert(anchor, from: toolbar.moreToolsButton), in: toolbar)
    }

    // MARK: - Arrow style menu (SPEC-DELTA-2.md §1.2, SPEC-DELTA-2B.md §C6)

    /// Port of the `ArrowOptionsButton` menu (`OverlayEditorWindow.Arrows.cs`): 4 items, each with
    /// a rendered sample image and a checkmark on the currently-active style (the selected arrow's
    /// own style if one is selected, else the tool-level default). Clicking an item either mutates
    /// the selected arrow's style (pushing one undo step) or just arms the Arrow tool with that
    /// style, and always updates `canvasView.activeArrowStyle` for the *next* new arrow.
    func showArrowStyleMenu() {
        guard let toolbar = toolbarView, let canvasView else { return }
        let target = ArrowStyleMenuTarget(controller: self)
        let menu = NSMenu()
        let selectedArrow = canvasView.selectedAnnotation?.kind == .arrow ? canvasView.selectedAnnotation : nil
        let currentStyle = selectedArrow?.arrowStyle ?? canvasView.activeArrowStyle

        func addStyle(_ title: String, _ style: String) {
            let item = NSMenuItem(title: title, action: #selector(ArrowStyleMenuTarget.selectStyle(_:)), keyEquivalent: "")
            item.target = target
            item.representedObject = style
            item.image = ArrowDrawing.sampleImage(style: style)
            item.state = currentStyle == style ? .on : .off
            item.attributedTitle = NSAttributedString(string: title, attributes: [.foregroundColor: NSColor.white])
            menu.addItem(item)
        }

        addStyle(EditorStrings.arrowStraight(language), "straight")
        addStyle(EditorStrings.arrowCurved(language), "curved")
        addStyle(EditorStrings.arrowBold(language), "bold")
        addStyle(EditorStrings.arrowWide(language), "wide")

        let anchor = CGPoint(x: 0, y: toolbar.arrowOptionsButton.frame.maxY)
        menu.popUp(positioning: nil, at: toolbar.convert(anchor, from: toolbar.arrowOptionsButton), in: toolbar)
    }

    /// Port of the arrow-style menu item click (`Arrows.cs:25-31`): mutating an already-selected
    /// arrow pushes one undo step; otherwise this just arms the Arrow tool. `canvasView
    /// .activeArrowStyle` (and `syncAppearance()`) is always refreshed either way, so the *next*
    /// new arrow picks up the chosen style.
    func applyArrowStyle(_ style: String) {
        guard let canvasView else { return }
        if let selected = canvasView.selectedAnnotation, selected.kind == .arrow {
            if let before = lastSnapshot { history.pushWithoutClearingRedo(before) }
            history.clearRedo()
            selected.arrowStyle = style
            lastSnapshot = snapshotState()
            canvasView.needsDisplay = true
        } else {
            selectTool(.arrow)
        }
        canvasView.activeArrowStyle = style
        syncAppearance()
        refreshUndoRedoButtons()
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
    @objc func selectConceal() { controller?.selectTool(.conceal) }
}

/// `NSMenu` target for the arrow-style menu (`showArrowStyleMenu()`), same reasoning as
/// `MoreToolsMenuTarget` above.
@MainActor
final class ArrowStyleMenuTarget: NSObject {
    weak var controller: OverlayEditorController?

    init(controller: OverlayEditorController) {
        self.controller = controller
    }

    @objc func selectStyle(_ sender: NSMenuItem) {
        guard let style = sender.representedObject as? String else { return }
        controller?.applyArrowStyle(style)
    }
}
