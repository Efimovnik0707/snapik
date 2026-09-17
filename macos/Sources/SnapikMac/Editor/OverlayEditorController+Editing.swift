// Port of `SetupEditor`, `OnToolClick`/`SelectToolMode`, the split-capsule menus
// (`OverlayEditorWindow.Shapes.cs`, `.Arrows.cs`) and `OnCropRequested`
// (`OverlayEditorWindow.xaml.cs:228-337,668-714`), SPEC §1.3, §6.2, §6.3,
// SPEC-DELTA-3 §1.4 E-1, E-3, E-4, E-5, E-11, E-12, E-19.
import AppKit
import SnapikCore

/// Port of `CropBorder` (`OverlayEditorWindow.xaml:45`): a 2pt accent border with a transparent
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
    /// Port of `SetupEditor` (`:228-257`). Re-run after every crop/resize/undo-redo restore, not just
    /// the initial capture — only the very first call defaults the tool.
    func setupEditor() {
        guard let capture, let screenIndex = activeScreenIndex else { return }
        settingUp = true
        let slot = slots[screenIndex]
        slot.contentView.hintView.isHidden = true
        slot.contentView.holeRectLocal = cropRectLocal

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
            // The half of the pencil capsule the settings file carries is armed only as the pencil's
            // own mode; the tool the editor opens with is the region, as it always was.
            canvasView?.tool = .rectangle
        }
        canvasView?.language = language
        canvasView?.capture = capture

        if chipLayerView == nil {
            let layer = ChipLayerView(frame: NSRect(origin: .zero, size: slot.contentView.bounds.size))
            layer.autoresizingMask = [.width, .height]
            slot.contentView.addSubview(layer)
            chipLayerView = layer
        }

        ensureToolbarView(on: slot)
        // The panel is built before the capture is placed, so it went into the content view before
        // the canvas did; the order of the subviews is the order they are drawn in, and the panel
        // belongs over the picture. Asked for again here it lands where it always stood: over the
        // canvas and the pills, under the views built after it.
        if let toolbarView {
            slot.contentView.addSubview(toolbarView, positioned: .above, relativeTo: nil)
        }

        setupCommentsPanelIfNeeded(on: slot)
        setupScaleViews(on: slot)
        toolbarView?.setActiveTool(canvasView?.tool ?? .rectangle)
        syncAppearance()

        setupCaptureHandles(on: slot)

        lastSnapshot = snapshotState()
        refreshLabels()
        rebuildChips(on: slot)
        positionCommentsPanel()
        positionToolbar()
        window(for: screenIndex)?.makeFirstResponder(canvasView)
        settingUp = false
    }

    /// The panel is built before the capture is placed and not with the rest of the editing views:
    /// the room the capture is given is the working area less the height of the panel, and that
    /// height cannot be asked of a panel that does not exist yet (SPEC-DELTA-5-editor.md §1.2 E-1).
    func ensureToolbarView(on slot: OverlayScreenSlot) {
        guard toolbarView == nil else { return }
        let toolbar = EditorToolbarView(language: language)
        // The pencil capsule's own button arms whichever half was last chosen, not always the
        // pen (SPEC-DELTA-3 §1.4 E-4).
        toolbar.onToolSelected = { [weak self] tool in
            if tool == .pen { self?.selectPencilTool() } else { self?.selectTool(tool) }
        }
        toolbar.onDragBegan = { [weak self] point in self?.beginToolbarDrag(at: point) }
        toolbar.onDragMoved = { [weak self] point in self?.dragToolbarTo(point) }
        toolbar.onDragEnded = { [weak self] in self?.endToolbarDrag() }
        wireToolbarActions(toolbar)
        slot.contentView.addSubview(toolbar)
        toolbarView = toolbar
    }

    /// Port of `_commentsPanelVisible` (`OverlayEditorWindow.xaml.cs:1020`, SPEC-DELTA-3 §1.4 E-12):
    /// the panel belongs to a capture opened again from the strip that already carries at least one
    /// note. A brand-new capture has nothing to list.
    private func setupCommentsPanelIfNeeded(on slot: OverlayScreenSlot) {
        guard commentsPanelView == nil, !isNewCapture, let capture else { return }
        let hasNotes = capture.annotations.contains { !$0.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard hasNotes else { return }
        let panel = CommentsPanelView(language: language)
        slot.contentView.addSubview(panel)
        commentsPanelView = panel
        syncCommentsPanel()
    }

    func window(for screenIndex: Int) -> AppKit.NSWindow? {
        slots[screenIndex].window
    }

    /// Removes every editing-mode subview (used by `commit`/`cancelEditing` before `close()` tears
    /// down the windows themselves).
    func teardownEditingViews() {
        canvasContainerView?.removeFromSuperview()
        toolbarView?.removeFromSuperview()
        shotKindView?.removeFromSuperview()
        chipLayerView?.removeFromSuperview()
        commentsPanelView?.removeFromSuperview()
        textEditorView?.removeFromSuperview()
        for handle in captureHandleViews { handle.removeFromSuperview() }
        resizeOutlineView?.removeFromSuperview()
        chipViews.removeAll()
        canvasContainerView = nil
        canvasView = nil
        toolbarView = nil
        shotKindView = nil
        chipLayerView = nil
        commentsPanelView = nil
        textEditorView = nil
        captureHandleViews = []
        resizeOutlineView = nil
    }

    private func wireCanvasCallbacks(_ canvas: AnnotationCanvasView) {
        canvas.onAnnotationCreated = { [weak self] annotation in self?.annotationCreated(annotation) }
        canvas.onSelectionChanged = { [weak self] annotation in self?.selectionChanged(annotation) }
        canvas.onAnnotationChanged = { [weak self] in self?.annotationChanged() }
        canvas.onCropRequested = { [weak self] bounds in self?.cropRequested(bounds) }
        canvas.onAnnotationActivated = { [weak self] annotation in self?.annotationActivated(annotation) }
        canvas.onViewChanged = { [weak self] in self?.surfaceViewChanged() }
        canvas.onNoteHovered = { [weak self] annotation in self?.noteHovered(annotation) }
    }

    private func wireToolbarActions(_ toolbar: EditorToolbarView) {
        // The capsule of the colour opens the outline; the square inside it opens the fill, and it
        // is a view of its own so that the two presses are told apart (H-1).
        toolbar.colorCapsule.onClick = { [weak self, weak toolbar] in
            guard let toolbar else { return }
            self?.togglePopover(.color, relativeTo: toolbar.colorCapsule)
        }
        toolbar.colorCapsule.fillSquare.onClick = { [weak self, weak toolbar] in
            guard let self, let toolbar else { return }
            // The fill belongs to a region: with another tool in the hand and nothing selected the
            // square arms the region first, the way a pick in the shape menu does.
            if self.canvasView?.selectedAnnotation == nil, !EditorAppearance.hasFill(self.canvasView?.tool ?? .select) {
                self.selectTool(.rectangle)
            }
            self.togglePopover(.fill, relativeTo: toolbar.colorCapsule.fillSquare)
        }
        // The second capsule opens whichever sheet it is showing: the width with the pattern under
        // it, or the size of a caption. A capsule that shows nothing opens nothing.
        toolbar.lineCapsule.onClick = { [weak self, weak toolbar] in
            guard let self, let toolbar else { return }
            let second = EditorInspector.inspectorViewOf(EditorInspector.inspectedTool(
                selected: self.canvasView?.selectedAnnotation, armed: self.canvasView?.tool ?? .rectangle)).second
            switch second {
            case .none: return
            case .fontSize: self.togglePopover(.fontSize, relativeTo: toolbar.lineCapsule)
            case .line, .shape: self.togglePopover(.thickness, relativeTo: toolbar.lineCapsule)
            }
        }
        toolbar.shortcutSheetButton.onClick = { [weak self, weak toolbar] in
            guard let toolbar else { return }
            self?.togglePopover(.shortcutSheet, relativeTo: toolbar.shortcutSheetButton)
        }
        toolbar.shapeMenuButton.onClick = { [weak self, weak toolbar] in
            guard let toolbar else { return }
            self?.showShapeMenu(from: toolbar.shapeMenuButton)
        }
        toolbar.arrowOptionsButton.onClick = { [weak self, weak toolbar] in
            guard let toolbar else { return }
            self?.showArrowStyleMenu(from: toolbar.arrowOptionsButton)
        }
        toolbar.pencilMenuButton.onClick = { [weak self, weak toolbar] in
            guard let toolbar else { return }
            self?.showPencilMenu(from: toolbar.pencilMenuButton)
        }
        toolbar.commentButton.onClick = { [weak self] in self?.commentButtonClicked() }
        toolbar.undoButton.onClick = { [weak self] in self?.performUndo() }
        toolbar.redoButton.onClick = { [weak self] in self?.performRedo() }
        toolbar.saveButton.onClick = { [weak self] in self?.saveToFile() }
        toolbar.doneButton.onClick = { [weak self] in self?.commit(addNext: false) }
    }

    // MARK: - Tool selection (SPEC §1.3)

    /// Port of `OnToolClick`/`SelectToolMode` (`:293-301,1120-1129`). A caption being typed is
    /// finished first: the letters belong to the mark, not to the tool that is being put down.
    func selectTool(_ tool: EditorTool) {
        if isEditingText { commitTextEdit() }
        // The pencil capsule carries whichever half is armed, and that half travels between captures
        // (SPEC-DELTA-3 §1.4 E-4, §2.2 `AnnotationPencil`).
        if tool == .pen || tool == .highlight {
            appearanceDefaultsChanged = appearanceDefaultsChanged || activePencil != tool
            activePencil = tool
        }
        canvasView?.selectAnnotation(id: nil)
        canvasView?.tool = tool
        toolbarView?.setActiveTool(tool)
        syncAppearance()
        window(for: activeScreenIndex ?? 0)?.makeFirstResponder(canvasView)
    }

    /// The pencil capsule's own button: it arms whichever half was last chosen, without opening the
    /// menu beside it (`PenTool`, `xaml:213`).
    func selectPencilTool() {
        selectTool(activePencil)
    }

    // MARK: - The split-capsule menus (`OverlayEditorWindow.Shapes.cs`)

    /// The whole menu is one edit: it takes the state before opening and pushes at most one history
    /// entry when it closes, exactly like a popover (`OpenToolMenu`, `Shapes.cs:37-42`).
    private func beginMenuEdit() {
        guard capture != nil else { return }
        appearanceBefore = snapshotState()
        appearanceChanged = false
    }

    private func endMenuEdit() {
        commitAppearanceSession()
        syncAppearance()
        window(for: activeScreenIndex ?? 0)?.makeFirstResponder(canvasView)
    }

    /// Port of `BuildShapeMenu` (`Shapes.cs:44-67`): the three frames a region and a blur share.
    func showShapeMenu(from anchor: NSView) {
        guard let canvasView else { return }
        beginMenuEdit()
        let target = EditorMenuTarget(controller: self)
        let menu = NSMenu()
        let selected = canvasView.selectedAnnotation
        // The shape belongs to the frame alone since 1.7.0 (`.Shapes.cs:50`): a blur is drawn with
        // the shape the frame carries, and a selected blur has no say of its own in it
        // (SPEC-DELTA-5-editor.md §1.3 E-11).
        let current = selected?.kind == .rectangle ? (selected?.shape ?? activeShape) : activeShape

        func add(_ shape: AnnotationShape, _ title: String) {
            let item = NSMenuItem(title: title, action: #selector(EditorMenuTarget.selectShape(_:)), keyEquivalent: "")
            item.target = target
            item.representedObject = shape.rawValue
            item.state = current == shape ? .on : .off
            item.image = EditorIcon.image(symbol: shapeSymbol(shape), color: .white, pointSize: 13)
            item.attributedTitle = NSAttributedString(string: title, attributes: [.foregroundColor: NSColor.white])
            menu.addItem(item)
        }

        add(.rectangle, EditorStrings.shapeRectangle(language))
        add(.rounded, EditorStrings.shapeRounded(language))
        add(.ellipse, EditorStrings.shapeEllipse(language))
        popUp(menu, from: anchor)
        endMenuEdit()
    }

    private func shapeSymbol(_ shape: AnnotationShape) -> String {
        switch shape {
        case .rectangle: return "rectangle"
        case .rounded: return "rectangle.roundedtop"
        case .ellipse: return "oval"
        }
    }

    func applyShape(_ shape: AnnotationShape) {
        // The shape belongs to the frame and to nothing else (`.Shapes.cs:59-64`): picking one with
        // a blur selected, or with a blur in the hand, switches to the frame the way any other
        // foreign selection does, and the blur goes on being drawn with what the frame carries.
        let selected = canvasView?.selectedAnnotation
        if selected?.kind != .rectangle { selectTool(.rectangle) }
        applyAppearance(shape: shape)
    }

    /// Port of `BuildPencilMenu` (`Shapes.cs:71-86`): the other half of the pencil capsule.
    func showPencilMenu(from anchor: NSView) {
        let target = EditorMenuTarget(controller: self)
        let menu = NSMenu()
        for tool in [EditorTool.pen, EditorTool.highlight] {
            let title = EditorShortcuts.caption(tool, language: language)
            let item = NSMenuItem(title: title, action: #selector(EditorMenuTarget.selectTool(_:)), keyEquivalent: "")
            item.target = target
            item.representedObject = tool.rawValue
            item.state = activePencil == tool ? .on : .off
            item.image = EditorIcon.image(symbol: tool == .pen ? EditorIcon.pencil : EditorIcon.highlighter, color: .white, pointSize: 13)
            item.attributedTitle = NSAttributedString(string: title, attributes: [.foregroundColor: NSColor.white])
            menu.addItem(item)
        }
        popUp(menu, from: anchor)
    }

    /// Port of the `ArrowOptionsButton` menu (`OverlayEditorWindow.Arrows.cs`): four styles, each
    /// with a rendered sample and a checkmark on the one in force.
    func showArrowStyleMenu(from anchor: NSView) {
        guard let canvasView else { return }
        beginMenuEdit()
        let target = EditorMenuTarget(controller: self)
        let menu = NSMenu()
        let selectedArrow = canvasView.selectedAnnotation?.kind == .arrow ? canvasView.selectedAnnotation : nil
        let currentStyle = selectedArrow?.arrowStyle ?? canvasView.activeArrowStyle

        func add(_ title: String, _ style: String) {
            let item = NSMenuItem(title: title, action: #selector(EditorMenuTarget.selectArrowStyle(_:)), keyEquivalent: "")
            item.target = target
            item.representedObject = style
            item.image = ArrowDrawing.sampleImage(style: style)
            item.state = currentStyle == style ? .on : .off
            item.attributedTitle = NSAttributedString(string: title, attributes: [.foregroundColor: NSColor.white])
            menu.addItem(item)
        }

        // Three styles and not four: the thick arrow is not offered any more (`Arrows.cs:15-17`).
        // The value goes on being read out of a session written before this round (§3.1).
        add(EditorStrings.arrowStraight(language), "straight")
        add(EditorStrings.arrowCurved(language), "curved")
        add(EditorStrings.arrowWide(language), "wide")
        popUp(menu, from: anchor)
        endMenuEdit()
    }

    /// Port of the arrow-style click (`Arrows.cs:25-31`): a selected arrow takes the style, otherwise
    /// the tool is armed with it; the next new arrow picks it up either way.
    func applyArrowStyle(_ style: String) {
        guard let canvasView else { return }
        if canvasView.selectedAnnotation?.kind == .arrow {
            applyAppearance(arrowStyle: style)
        } else {
            selectTool(.arrow)
            canvasView.activeArrowStyle = style
            syncAppearance()
        }
    }

    /// `NSMenu.popUp(positioning:at:in:)` runs its own modal event-tracking loop and does not return
    /// until the menu closes, so the target only has to outlive this call.
    private func popUp(_ menu: NSMenu, from anchor: NSView) {
        menu.popUp(positioning: nil, at: CGPoint(x: 0, y: anchor.bounds.maxY), in: anchor)
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

/// `NSMenu` requires an `@objc` target/selector pair; this small `NSObject` forwards each item to the
/// controller via a weak reference (the controller itself is a plain Swift class, not `NSObject`, so
/// it cannot be a menu target directly).
@MainActor
final class EditorMenuTarget: NSObject {
    weak var controller: OverlayEditorController?

    init(controller: OverlayEditorController) {
        self.controller = controller
    }

    @objc func selectShape(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let shape = AnnotationShape(rawValue: raw) else { return }
        controller?.applyShape(shape)
    }

    @objc func selectTool(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let tool = EditorTool(rawValue: raw) else { return }
        controller?.selectTool(tool)
    }

    @objc func selectArrowStyle(_ sender: NSMenuItem) {
        guard let style = sender.representedObject as? String else { return }
        controller?.applyArrowStyle(style)
    }
}
