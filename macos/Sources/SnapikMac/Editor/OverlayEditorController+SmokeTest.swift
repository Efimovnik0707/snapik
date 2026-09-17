// Test-only hooks for `--smoke-test` (SPEC §8.4 points 6, 9, 10; CONTRACTS.md "Editor",
// SPEC-DELTA-3 §1.7 K-2). These exist because the extended smoke test has no real mouse/keyboard
// input to synthesize gestures with — each hook drives the same model/view state a real gesture
// would, synchronously, on the main thread, so `App/SmokeTestRunner+Editor.swift` can call them
// without `async`/completion handlers. None of them go through `persistCurrentSource`'s disk round
// trip: they are about verifying in-memory editor behaviour.
import AppKit
import SnapikCore

@MainActor
extension OverlayEditorController {
    /// Simulates drawing a selection rectangle (in frame pixels) and transitions straight into
    /// markup mode, mirroring `finishSelection` without requiring real mouse events.
    @discardableResult
    func smokeSelectRegion(_ rectInFramePixels: CGRect) -> Bool {
        guard isPresented, capture == nil, !busyCrop else { return false }
        let frameBounds = CGRect(x: 0, y: 0, width: desktopFrame.pixelWidth, height: desktopFrame.pixelHeight)
        let clamped = rectInFramePixels.intersection(frameBounds)
        guard clamped.width >= 1, clamped.height >= 1, let cropped = desktopFrame.image.cropping(to: clamped) else { return false }

        let centerScreenPoint = ScreenGeometry.screenPoint(fromFramePixels: CGPoint(x: clamped.midX, y: clamped.midY), frame: desktopFrame)
        guard let screenIndex = slots.firstIndex(where: { $0.screen.frame.contains(centerScreenPoint) }) ?? slots.indices.first else { return false }

        activeScreenIndex = screenIndex
        slots[screenIndex].window.makeKeyAndOrderFront(nil)

        let newCapture = EditorCapture(image: cropped, sourceImagePath: "")
        newCapture.displayLabel = (try? CaptureLabels.forIndex(captureIndex)) ?? "A"
        capture = newCapture
        cropRectLocal = localRect(fromFramePixelRect: clamped, screenIndex: screenIndex)
        isNewCapture = true
        currentSourcePath = nil

        setupEditor()
        return capture != nil
    }

    /// Creates a Rectangle annotation at the given capture-pixel geometry (mirrors the canvas's own
    /// rectangle-creation branch: append, select, notify `annotationCreated`). If `note` is supplied,
    /// types it into the pill that opens, the same way a real edit would.
    @discardableResult
    func smokeCreateRectangle(_ rectInCapturePixels: CGRect, note: String?) -> String? {
        guard let capture, activeScreenIndex != nil, !busyCrop, captureResizeCorner < 0 else { return nil }
        let imageBounds = CGRect(x: 0, y: 0, width: capture.image.width, height: capture.image.height)
        let clamped = rectInCapturePixels.intersection(imageBounds)
        guard clamped.width > 0, clamped.height > 0 else { return nil }

        let annotation = EditorAnnotation(
            kind: .rectangle,
            points: [CGPoint(x: clamped.minX, y: clamped.minY), CGPoint(x: clamped.maxX, y: clamped.maxY)],
            color: armedAppearance.color,
            thickness: armedAppearance.thickness,
            shape: activeShape,
            fill: armedAppearance.fill,
            fillColor: armedAppearance.fillColor,
            lineStyle: armedAppearance.lineStyle)
        capture.annotations.append(annotation)
        canvasView?.selectAnnotation(id: annotation.id)
        annotationCreated(annotation)
        canvasView?.needsDisplay = true

        if let note {
            visibleChipIds.insert(annotation.id)
            if chipViews[annotation.id] == nil { addChip(for: annotation, focus: false) }
            if let chip = chipViews[annotation.id] {
                chip.note = note
                chip.onNoteChanged?(note)
            }
        }

        return annotation.id.description
    }

    /// SPEC §8.4 point 6: starts an unfinished blur gesture (a live `draft` on the canvas), renders
    /// the canvas before and during, and cancels the gesture without committing a blur annotation.
    @discardableResult
    func smokeVerifyBlurPreview() -> Bool {
        guard let canvasView, let capture, capture.image.width > 0, capture.image.height > 0 else { return false }
        guard let before = renderCanvasSnapshotForSmokeTest(canvasView) else { return false }

        let w = CGFloat(capture.image.width)
        let h = CGFloat(capture.image.height)
        let rect = CGRect(x: w * 0.25, y: h * 0.25, width: max(w * 0.2, 4), height: max(h * 0.2, 4))
        canvasView.draft = EditorAnnotation(
            kind: .blur,
            points: [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY)],
            color: armedAppearance.color,
            thickness: armedAppearance.thickness)

        let during = renderCanvasSnapshotForSmokeTest(canvasView)

        canvasView.draft = nil
        canvasView.needsDisplay = true

        guard let during else { return false }
        return before != during
    }

    /// SPEC §8.4 point 9: the four capture-corner handles exist with a 22x22 hit target, one handle's
    /// own drag callbacks actually move `cropRectLocal`, and the drag is cancelled without committing.
    @discardableResult
    func smokeRunCaptureResizeProbe() -> Bool {
        guard capture != nil, activeScreenIndex != nil, captureHandleViews.count == 4 else { return false }
        for handle in captureHandleViews where handle.frame.width != 22 || handle.frame.height != 22 { return false }

        let before = cropRectLocal
        let corner = 2 // bottom-right (SPEC §1.6 clockwise numbering)
        captureHandleViews[corner].onDragStarted?()
        guard captureResizeCorner == corner else { return false }

        let target = CGPoint(x: max(before.minX + 20, before.maxX - 40), y: max(before.minY + 20, before.maxY - 40))
        captureHandleViews[corner].onDragChanged?(target)
        let changed = cropRectLocal != before

        captureResizeCorner = -1
        resizeOutlineView?.isHidden = true
        cropRectLocal = before
        updateCropVisual()

        return changed
    }

    /// Creates a Comment pin at `at` (capture pixel space), mirroring the real flow: its second point
    /// is offset `(8,8)` and clamped, and its pill opens focused. [ТЗ№4 D3] the Comment tool stays in
    /// the hand afterwards, and since 1.6.0 the pin is linked to no mark at all.
    @discardableResult
    func smokeCreateComment(at point: CGPoint, note: String?) -> SBGuid? {
        guard let capture, activeScreenIndex != nil, !busyCrop, captureResizeCorner < 0 else { return nil }
        let imageBounds = CGRect(x: 0, y: 0, width: capture.image.width, height: capture.image.height)
        guard imageBounds.contains(point) else { return nil }

        let annotation = EditorAnnotation(kind: .comment, points: [point, point], color: armedAppearance.color, thickness: armedAppearance.thickness)
        capture.annotations.append(annotation)
        annotationCreated(annotation)

        if let note, let chip = chipViews[annotation.id] {
            chip.note = note
            chip.onNoteChanged?(note)
        }
        return annotation.id
    }

    /// Port of `RunNoteAffordanceProbe` (`OverlayEditorWindow.xaml.cs:107-202`), updated for
    /// SPEC-DELTA-3 §1.4 E-6, E-7, [ТЗ№4 D3] and SPEC-DELTA-5-editor.md §1.2 E-6: a pin is linked to
    /// no mark, whatever was selected when the tool was armed; the tool **stays** Comment afterwards;
    /// a second, unrelated comment collapses the first and neither pill overlaps the other; the pill
    /// carries no number of its own; a badge dragged off the capture keeps its point where it was and
    /// Escape folds the pill the pin unfolded before it puts the tool down; deleting a comment's note
    /// removes the pin entirely; finishing an empty rectangle's pill removes only the pill; a caption
    /// is typed on the capture and not in a pill.
    @discardableResult
    func smokeRunNoteAffordanceProbe() -> Bool {
        guard let capture, activeScreenIndex != nil else { return false }
        let w = CGFloat(capture.image.width)
        let h = CGFloat(capture.image.height)
        guard w >= 60, h >= 60 else { return false }

        let arrow = EditorAnnotation(kind: .arrow, points: [CGPoint(x: 10, y: 10), CGPoint(x: 60, y: 40)], color: armedAppearance.color, thickness: armedAppearance.thickness)
        capture.annotations.append(arrow)
        canvasView?.selectAnnotation(id: arrow.id)
        commentButtonClicked()
        guard canvasView?.tool == .comment else { return false }

        guard let firstId = smokeCreateComment(at: CGPoint(x: w * 0.5, y: h * 0.5), note: nil) else { return false }
        // [ТЗ№4 D3] the tool is not put down by the pin it just placed.
        guard canvasView?.tool == .comment else { return false }
        guard visibleChipIds.contains(firstId), let firstAnnotation = capture.annotations.first(where: { $0.id == firstId }) else { return false }
        // A pin is its own object: the arrow that was selected when the tool was armed is not its
        // parent, and moving that arrow leaves the pin where it stands.
        guard firstAnnotation.parentAnnotationId == nil else { return false }

        // The pill the pin unfolded is the first thing Escape folds, above putting the tool down.
        guard expandedChipId == firstId, nextEscapeStep() == .expandedNote else { return false }
        expandChip(firstId, expanded: false)
        guard nextEscapeStep() == .comment else { return false }

        // The badge travels alone and off the capture if the hand takes it there: the point it is
        // pinned to stays, and the offset is not clamped into the picture.
        if let canvasView {
            canvasView.recomputeImageRect()
            let pinnedTo = firstAnnotation.points.first ?? .zero
            canvasView.beginGesture(canvasView.badgeCenter(of: firstAnnotation))
            canvasView.updateGesture(canvasView.toDisplay(CGPoint(x: -w * 0.4, y: h * 0.1)), pressed: true)
            canvasView.endGesture()
            guard let carried = firstAnnotation.noteOffset, carried.x < 0 else { return false }
            guard firstAnnotation.points.first == pinnedTo else { return false }
            firstAnnotation.noteOffset = nil
        }
        expandChip(firstId, expanded: true)

        let commentProbeText = "smoke-comment-probe"
        guard let firstChip = chipViews[firstId] else { return false }
        firstChip.note = commentProbeText
        firstChip.onNoteChanged?(commentProbeText)
        guard firstAnnotation.note == commentProbeText else { return false }

        guard let secondId = smokeCreateComment(at: CGPoint(x: w * 0.2, y: h * 0.8), note: "second") else { return false }
        guard let firstChipAfter = chipViews[firstId], let secondChip = chipViews[secondId] else { return false }
        // The pill of the first collapsed, which with the number gone means it left the screen.
        guard firstChipAfter.isHidden, !secondChip.isHidden else { return false }
        guard abs(secondChip.frame.width - CommentChipView.expandedWidth) < 0.5 else { return false }

        deleteAnnotationNote(firstAnnotation)
        guard !capture.annotations.contains(where: { $0.id == firstId }), chipViews[firstId] == nil else { return false }

        let rectRect = CGRect(x: w * 0.05, y: h * 0.05, width: max(w * 0.1, 10), height: max(h * 0.1, 10))
        guard let rectIdString = smokeCreateRectangle(rectRect, note: nil), let rectId = SBGuid(uuidString: rectIdString) else { return false }
        visibleChipIds.insert(rectId)
        if let rectAnnotation = capture.annotations.first(where: { $0.id == rectId }), chipViews[rectId] == nil {
            addChip(for: rectAnnotation, focus: false)
        }
        finishChip(rectId)
        guard capture.annotations.contains(where: { $0.id == rectId }), chipViews[rectId] == nil else { return false }

        // A caption is typed on the capture itself: the field stands over it and no pill is made.
        let textAnnotation = EditorAnnotation(
            kind: .text, points: [CGPoint(x: w * 0.3, y: h * 0.3), CGPoint(x: w * 0.3 + 80, y: h * 0.3 + 40)],
            color: armedAppearance.color, thickness: armedAppearance.thickness, text: "")
        capture.annotations.append(textAnnotation)
        annotationCreated(textAnnotation)
        guard chipViews[textAnnotation.id] == nil, isEditingText, let field = textEditorView else { return false }
        let textProbeText = "smoke-text-probe"
        field.string = textProbeText
        captionTextDidChange()
        commitTextEdit()

        return textAnnotation.text == textProbeText && textAnnotation.note.isEmpty && !isEditingText
    }

    /// The state that would be delivered to the delegate if committed right now, without closing.
    func smokeCurrentState() -> (capture: CaptureItem, annotations: [AnnotationItem])? {
        guard let capture else { return nil }
        let coreCapture = capture.toCore()
        return (coreCapture, coreCapture.annotations)
    }

    /// Commits the current capture programmatically, exactly as a click outside it would.
    func smokeCommit() {
        commit(addNext: false)
    }

    // MARK: - Appearance probes

    /// Drives the same immediate-apply path a real swatch click / hex commit / slider drag would,
    /// without needing a popover on screen. The first call in an uncommitted session captures the
    /// pre-edit baseline exactly as opening the real popover does.
    func smokeSetAppearance(color: NSColor?, thickness: Double?) {
        if appearanceBefore == nil { appearanceBefore = snapshotState() }
        applyAppearance(color: color, thickness: thickness)
    }

    /// The selected annotation's current colour (`#AARRGGBB`) and thickness, or `nil`.
    func smokeSelectedAnnotationAppearance() -> (color: String, thickness: Double)? {
        guard let selected = canvasView?.selectedAnnotation else { return nil }
        return (selected.color.hexARGB, selected.thickness)
    }

    /// Port of `OnUndoClick` for probes with no toolbar button to click. If an appearance session is
    /// still open, first commits it exactly as closing the real popover would, so the resulting
    /// single undo restores the pre-edit state in one step.
    func smokeUndo() {
        commitAppearanceSession()
        performUndo()
    }

    /// Forces `AnnotationCanvasView.draw(_:)` to run against an off-screen bitmap and returns its raw
    /// pixel bytes, so callers can byte-compare "before" against "during a gesture".
    private func renderCanvasSnapshotForSmokeTest(_ canvasView: AnnotationCanvasView) -> Data? {
        guard canvasView.bounds.width > 0, canvasView.bounds.height > 0,
            let rep = canvasView.bitmapImageRepForCachingDisplay(in: canvasView.bounds)
        else { return nil }
        canvasView.cacheDisplay(in: canvasView.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - Probes of sync 3 (SPEC-DELTA-3 §1.7 K-2)

    /// The colour goes to the tool in the hand and to nothing else (rule 2 of the round of 1.6.0):
    /// it reaches the canvas, the capsule of the panel shows it, and the next frame is drawn with it.
    /// A tool with no settings of its own — the Comment here — takes nothing at all, and the frame
    /// keeps what it was set to.
    @discardableResult
    func smokeVerifyOneActiveColor() -> Bool {
        guard let canvasView, let capture else { return false }
        selectTool(.rectangle)
        let picked = NSColor(srgbRed: 0x34 / 255, green: 0xC7 / 255, blue: 0x59 / 255, alpha: 1)
        applyAppearance(color: picked)
        guard EditorAppearance.sameColor(canvasView.activeColor, picked) else { return false }
        guard EditorAppearance.sameColor(toolbarView?.colorCapsule.strokeColor ?? .black, picked) else { return false }

        // With the Comment in hand the block is there but dead, and a colour pressed on it changes
        // nothing: the frame still carries the one it was given.
        selectTool(.comment)
        applyAppearance(color: NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        guard EditorAppearance.sameColor(appearance(of: .rectangle).color, picked) else { return false }

        selectTool(.rectangle)
        let w = CGFloat(capture.image.width)
        let h = CGFloat(capture.image.height)
        canvasView.recomputeImageRect()
        canvasView.beginGesture(canvasView.toDisplay(CGPoint(x: w * 0.1, y: h * 0.1)))
        canvasView.updateGesture(canvasView.toDisplay(CGPoint(x: w * 0.4, y: h * 0.4)), pressed: true)
        canvasView.endGesture()
        guard let drawn = capture.annotations.last, drawn.kind == .rectangle else { return false }
        let ok = EditorAppearance.sameColor(drawn.color, picked)
        capture.annotations.removeAll(where: { $0 === drawn })
        canvasView.selectAnnotation(id: nil)
        return ok
    }

    /// Rule 6 of the round (SPEC-DELTA-5-editor.md §1.2 E-4, §4.2): every tool keeps its own set, a
    /// mark drawn by hand is born with the set of the tool that drew it, and what the editor writes
    /// when it closes is what the next window reads back. The second window is not built here — what
    /// it would read is the settings file, and the file is what this probe reads back, together with
    /// the three common keys this same writer must not lose.
    @discardableResult
    func smokeVerifyToolMemory() -> Bool {
        guard let canvasView, let capture else { return false }
        let green = NSColor(srgbRed: 0x34 / 255, green: 0xC7 / 255, blue: 0x59 / 255, alpha: 1)
        let red = NSColor(srgbRed: 1, green: 0x3B / 255, blue: 0x30 / 255, alpha: 1)
        let blue = NSColor(srgbRed: 0, green: 0x7A / 255, blue: 1, alpha: 1)
        let yellow = NSColor(srgbRed: 1, green: 0xCC / 255, blue: 0, alpha: 1)

        canvasView.selectAnnotation(id: nil)
        selectTool(.rectangle)
        applyAppearance(color: green, thickness: 4, fill: .translucent, fillColor: red)
        selectTool(.arrow)
        applyAppearance(color: blue, lineStyle: .dashed)
        selectTool(.text)
        applyAppearance(color: .white, fontSize: 20)
        selectTool(.highlight)
        applyAppearance(color: yellow)

        // Back on the frame: it gives its own set, and the capsules of the panel show it.
        selectTool(.rectangle)
        var ok = EditorAppearance.sameColor(appearance(of: .rectangle).color, green)
        ok = ok && appearance(of: .rectangle).fill == .translucent
        ok = ok && EditorAppearance.sameColor(appearance(of: .arrow).color, blue)
        ok = ok && appearance(of: .arrow).lineStyle == .dashed
        ok = ok && appearance(of: .text).fontSize == 20
        ok = ok && EditorAppearance.sameColor(appearance(of: .highlight).color, yellow)
        ok = ok && EditorAppearance.sameColor(toolbarView?.colorCapsule.strokeColor ?? .black, green)
        ok = ok && toolbarView?.lineCapsule.value == EditorStrings.pixelLabel(4)

        // A frame drawn by hand is born with it.
        let w = CGFloat(capture.image.width)
        let h = CGFloat(capture.image.height)
        canvasView.recomputeImageRect()
        canvasView.beginGesture(canvasView.toDisplay(CGPoint(x: w * 0.1, y: h * 0.1)))
        canvasView.updateGesture(canvasView.toDisplay(CGPoint(x: w * 0.4, y: h * 0.4)), pressed: true)
        canvasView.endGesture()
        if let drawn = capture.annotations.last, drawn.kind == .rectangle {
            ok = ok && EditorAppearance.sameColor(drawn.color, green) && drawn.fill == .translucent
            capture.annotations.removeAll(where: { $0 === drawn })
            canvasView.selectAnnotation(id: nil)
        } else {
            ok = false
        }

        // And the file the editor leaves behind: the six sets come back, and the palette, the own
        // row of colours and the half of the pencil capsule are still in it.
        appearanceDefaultsChanged = true
        flushAppearanceDefaults()
        let stored = HotkeySettings.load(path: workspaceContext.settingsPath)
        let readBack = ToolAppearanceStore.read(stored)
        ok = ok && readBack[.rectangle]?.color.hexRGB == green.hexRGB
        ok = ok && readBack[.rectangle]?.fill == .translucent
        ok = ok && readBack[.rectangle]?.fillColor?.hexRGB == red.hexRGB
        ok = ok && readBack[.arrow]?.lineStyle == .dashed
        ok = ok && readBack[.text]?.fontSize == 20
        ok = ok && readBack[.highlight]?.color.hexRGB == yellow.hexRGB
        ok = ok && stored.annotationPalette == activePalette.id
        ok = ok && stored.customPaletteColors == customColors
        ok = ok && stored.annotationPencil == (activePencil == .highlight ? "highlight" : "pen")
        return ok
    }

    /// The rules of the interpolation (SPEC-DELTA-5-editor.md §1.2 H-2, §4.2, the analogue of
    /// `VerifyScalingRules`): the mode is not kept on the view, so the pure function that decides it
    /// is what the probe asks, at the four ratios the editor really draws at.
    @discardableResult
    func smokeVerifyScalingRules() -> Bool {
        // Fitted below its own size: averaged, or a dark photograph comes out as grit.
        var ok = AnnotationCanvasView.interpolation(ratio: 0.312) == .high
        ok = ok && AnnotationCanvasView.interpolation(ratio: 0.5) == .high
        // At its own size and above: pixel for pixel, or the seam of two monitors is smeared.
        ok = ok && AnnotationCanvasView.interpolation(ratio: 1) == .none
        ok = ok && AnnotationCanvasView.interpolation(ratio: 2) == .none
        // And the picture the editor has on screen right now obeys the same rule.
        if let canvasView, let capture, capture.image.width > 0 {
            canvasView.recomputeImageRect()
            let ratio = canvasView.imageRect.width / CGFloat(capture.image.width)
            let expected: NSImageInterpolation = ratio >= 0.999 ? .none : .high
            ok = ok && AnnotationCanvasView.interpolation(ratio: ratio) == expected
        }
        return ok
    }

    /// [ТЗ№4 D1] The spectrum, the eyedropper and the "+" belong to every palette, and "+" puts the
    /// colour in force into the own one without moving the row out from under the hand.
    @discardableResult
    func smokeVerifyPalettes() -> Bool {
        guard let toolbarView else { return false }
        for id in ["standard", "pastel", "neon", "custom"] {
            selectPalette(id)
            togglePopover(.color, relativeTo: toolbarView.colorCapsule)
            guard let popover = colorPopoverController else { return false }
            guard popover.isSpectrumVisible, popover.isEyedropperVisible else { return false }
            if id == "custom", popover.swatchCount != HotkeySettings.maxCustomPaletteColors { return false }
            closePopovers()
        }

        customColors.removeAll()
        selectPalette("standard")
        selectTool(.rectangle)
        let colour = NSColor(srgbRed: 0x2F / 255, green: 0x8C / 255, blue: 0xFF / 255, alpha: 1)
        applyAppearance(color: colour)
        rememberCustomColor(inspectedAppearance.color)
        // The row of the panel did not move: the standard palette is still the one showing.
        guard activePalette.id == "standard" else { return false }
        guard customColors.first == colour.hexRGB else { return false }
        // A colour picked twice rises instead of standing in the row twice, and the row never grows
        // past the twelve cells the file allows.
        rememberCustomColor(colour)
        guard customColors.count == 1 else { return false }
        for step in 0..<(HotkeySettings.maxCustomPaletteColors + 2) {
            rememberCustomColor(NSColor(srgbRed: CGFloat(10 + step) / 255, green: 0x20 / 255, blue: 0x30 / 255, alpha: 1))
        }
        guard customColors.count == HotkeySettings.maxCustomPaletteColors else { return false }
        customColors.removeAll()
        selectPalette("standard")
        return true
    }

    /// [ТЗ№4 D3] With the Comment tool in the hand a press on the badge of an existing comment grabs
    /// it instead of dropping a second pin, and the tool is still Comment afterwards.
    @discardableResult
    func smokeVerifyCommentGrab() -> Bool {
        guard let canvasView, let capture else { return false }
        let w = CGFloat(capture.image.width)
        let h = CGFloat(capture.image.height)
        guard w >= 120, h >= 120 else { return false }
        let before = capture.annotations.count

        selectTool(.comment)
        canvasView.recomputeImageRect()
        let anchor = CGPoint(x: w * 0.5, y: h * 0.5)
        let pin = EditorAnnotation(kind: .comment, points: [anchor, CGPoint(x: anchor.x + 8, y: anchor.y + 8)], color: armedAppearance.color, thickness: armedAppearance.thickness)
        pin.label = "A1"
        capture.annotations.append(pin)
        canvasView.needsDisplay = true

        canvasView.beginGesture(canvasView.badgeCenter(of: pin))
        canvasView.endGesture()
        var ok = capture.annotations.count == before + 1 && canvasView.selectedAnnotation === pin && canvasView.tool == .comment

        // One order of the press for every tool (SPEC-DELTA-5-editor.md §1.2 E-5): with the frame in
        // the hand a press on a frame that is already there selects it and draws no second one, a
        // drag of its outline writes one entry of the history, and a press without a drag writes
        // none at all.
        let frame = EditorAnnotation(
            kind: .rectangle,
            points: [CGPoint(x: w * 0.1, y: h * 0.1), CGPoint(x: w * 0.4, y: h * 0.4)],
            color: armedAppearance.color, thickness: 4)
        capture.annotations.append(frame)
        canvasView.selectAnnotation(id: nil)
        selectTool(.rectangle)
        canvasView.recomputeImageRect()
        let outline = canvasView.toDisplay(CGPoint(x: w * 0.25, y: h * 0.1))
        let counted = capture.annotations.count

        canvasView.beginGesture(outline)
        canvasView.endGesture()
        ok = ok && capture.annotations.count == counted && canvasView.selectedAnnotation === frame

        let entriesBeforeClick = history.undoDepth
        canvasView.beginGesture(outline)
        canvasView.updateGesture(outline, pressed: true)
        canvasView.endGesture()
        ok = ok && history.undoDepth == entriesBeforeClick

        canvasView.beginGesture(outline)
        canvasView.updateGesture(CGPoint(x: outline.x + 40, y: outline.y + 30), pressed: true)
        canvasView.endGesture()
        ok = ok && history.undoDepth == entriesBeforeClick + 1

        // A drag of the pointer over an empty place leaves no mark behind: a draft of kind `select`
        // used to reach the session, and the export drew a rectangle where it stood.
        canvasView.selectAnnotation(id: nil)
        selectTool(.select)
        let emptied = capture.annotations.count
        let empty = canvasView.toDisplay(CGPoint(x: w * 0.8, y: h * 0.8))
        canvasView.beginGesture(empty)
        canvasView.updateGesture(CGPoint(x: empty.x + 30, y: empty.y + 20), pressed: true)
        canvasView.endGesture()
        ok = ok && capture.annotations.count == emptied

        capture.annotations.removeAll(where: { $0 === pin || $0 === frame })
        canvasView.selectAnnotation(id: nil)
        selectTool(.select)
        return ok
    }

    /// SPEC-DELTA-3 §1.4 E-2: the pattern of a stroke reaches the exported PNG and survives a copy of
    /// the mark.
    @discardableResult
    func smokeVerifyLineStyleRoundTrip() -> Bool {
        guard let capture else { return false }
        let annotation = EditorAnnotation(
            kind: .rectangle, points: [CGPoint(x: 10, y: 10), CGPoint(x: 90, y: 60)],
            color: armedAppearance.color, thickness: 4, lineStyle: .dashed)
        capture.annotations.append(annotation)
        let core = annotation.toCore(imageWidth: capture.image.width, imageHeight: capture.image.height)
        let copied = annotation.clone()
        capture.annotations.removeAll(where: { $0 === annotation })
        return core.lineStyle == .dashed && copied.lineStyle == .dashed
    }

    /// SPEC-DELTA-3 §1.4 E-14: a frame filled with blur is baked into the preview, and dragging it
    /// reuses the cached raster instead of rebuilding the whole frame.
    @discardableResult
    func smokeVerifyBlurCache() -> Bool {
        guard let canvasView, let capture else { return false }
        let w = CGFloat(capture.image.width)
        let h = CGFloat(capture.image.height)
        let filled = EditorAnnotation(
            kind: .rectangle, points: [CGPoint(x: w * 0.2, y: h * 0.2), CGPoint(x: w * 0.6, y: h * 0.6)],
            color: armedAppearance.color, thickness: 4, fill: .blur)
        capture.annotations.append(filled)
        let baked = canvasView.applyBlurAnnotations(capture.image)
        guard baked !== capture.image else {
            capture.annotations.removeAll(where: { $0 === filled })
            return false
        }
        canvasView.selectAnnotation(id: filled.id)
        canvasView.manipulating = true
        filled.points[1] = CGPoint(x: w * 0.7, y: h * 0.7)
        let reused = canvasView.applyBlurAnnotations(capture.image) === baked
        canvasView.manipulating = false
        canvasView.selectAnnotation(id: nil)
        capture.annotations.removeAll(where: { $0 === filled })
        canvasView.blurCache = nil
        canvasView.blurCacheKey = nil
        return reused
    }

    /// SPEC-DELTA-3 §1.4 E-6: the size a caption is typed in is the size it is drawn in, on screen and
    /// in the export — the box of the mark is the letters and nothing else.
    @discardableResult
    func smokeVerifyCaptionSize() -> Bool {
        guard let canvasView, let capture else { return false }
        let annotation = EditorAnnotation(
            kind: .text, points: [CGPoint(x: 20, y: 20)], color: armedAppearance.color, thickness: 4,
            text: "Ag Привет", fontSize: 32)
        capture.annotations.append(annotation)
        canvasView.fitTextMark(annotation)
        let measured = TextMarkMetrics.measure(annotation.text, fontSize: annotation.fontSize)
        let box = EditorGeometry.boundsOf(points: annotation.points)
        let core = annotation.toCore(imageWidth: capture.image.width, imageHeight: capture.image.height)
        capture.annotations.removeAll(where: { $0 === annotation })
        return abs(Double(box.width) - measured.width) < 2 && abs(Double(box.height) - measured.height) < 2 && core.fontSize == 32
    }

    /// Port of `RunEditorScaleProbe` (`SmokeTestRunner.cs:460`), rewritten for the round of 1.6.0
    /// (SPEC-DELTA-5-editor.md §4.2): the switch beside the panel is gone, a capture opens at its own
    /// size whenever there is room for it, and the wheel with Cmd is the one way into a scale of its
    /// own. What is left of the old probe stands: the capture names itself in its corner, the picture
    /// scrolls, and the pill of a mark that went out of sight goes with it. What the probe borrows it
    /// puts back: the controller has more probes to run after this one.
    @discardableResult
    func smokeRunEditorViewProbe() -> Bool {
        guard let canvasView, let capture, let shotKindView, activeScreenIndex != nil else { return false }
        guard let wide = Self.smokeSolidImage(width: 3840, height: 1125) else { return false }

        let previousImage = capture.image
        let previousKind = capture.kind
        let previousMonitors = capture.monitorCount
        let previousCrop = cropRectLocal

        let scale = EditorGeometry.fit(imageWidth: 3840, imageHeight: 1125, boxWidth: 1198, boxHeight: 593)
        capture.image = wide
        capture.kind = .fullscreen
        capture.monitorCount = 2
        cropRectLocal = CGRect(
            x: 100, y: 100, width: 3840 * CGFloat(scale), height: 1125 * CGFloat(scale))
        let mark = EditorAnnotation(
            kind: .rectangle, points: [CGPoint(x: 3600, y: 500), CGPoint(x: 3800, y: 700)],
            color: armedAppearance.color, thickness: armedAppearance.thickness, note: "У правого края")
        capture.annotations.append(mark)
        visibleChipIds.insert(mark.id)
        setupEditor()
        // The pill is opened by hand: a collapsed one is already hidden, and the fact under test is
        // that the scale is what puts it away.
        expandChip(mark.id, expanded: true)

        // A capture the working area holds together with the panel below it opens at its own size:
        // 1420 fits 1536 - 16 and 700 fits 824 - 16 - 50 - 10.
        var ok = EditorGeometry.placeCapture(
            image: CGSize(width: 1420, height: 700),
            work: CGRect(x: 0, y: 0, width: 1536, height: 824),
            panel: CGSize(width: 460, height: 50)).size == CGSize(width: 1420, height: 700)
        // The caption of the capture says what it is, in the same words the strip card carries.
        ok = ok && !shotKindView.isHidden
            && shotKindView.caption.contains("3840×1125")
            && shotKindView.caption.contains(EditorStrings.wholeScreen(language))
            && shotKindView.caption.contains(EditorStrings.monitorCount(language, 2))
        // A capture smaller than the box is not scaled at all.
        ok = ok && EditorGeometry.fit(imageWidth: 400, imageHeight: 300, boxWidth: 1198, boxHeight: 593) == 1

        // The wheel with Cmd answers from the fitted state, which is the regression this round
        // carries: until it did, the right segment of the switch was the only way into a scale of
        // one's own, and there is no switch any more. Thirteen notches of a tenth each run into the
        // ceiling of one, where the mark by the right edge is out of sight and its pill goes with it
        // instead of hanging over the desktop.
        canvasView.zoomByNotches(13, cursor: CGPoint(x: cropRectLocal.width / 2, y: cropRectLocal.height / 2))
        ok = ok && canvasView.viewScale == 1
        ok = ok && chipViews[mark.id]?.isHidden == true

        // And the picture scrolls: an offset past the end of it stops where the picture ends, and the
        // rectangle it is drawn in starts at minus that.
        canvasView.viewOffset = CGPoint(x: 9000, y: 9000)
        canvasView.recomputeImageRect()
        ok = ok && abs(canvasView.viewOffset.x - (3840 - cropRectLocal.width)) < 0.5
        ok = ok && abs(canvasView.imageRect.minX + canvasView.viewOffset.x) < 0.5

        canvasView.viewOffset = .zero
        canvasView.viewScale = nil
        capture.annotations.removeAll(where: { $0 === mark })
        visibleChipIds.remove(mark.id)
        capture.image = previousImage
        capture.kind = previousKind
        capture.monitorCount = previousMonitors
        cropRectLocal = previousCrop
        setupEditor()
        return ok
    }

    /// One flat grey picture of the size asked for: the probe above needs a capture of two monitors
    /// and cares about nothing but its size.
    private static func smokeSolidImage(width: Int, height: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
        else { return nil }
        context.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// SPEC-DELTA-5-editor.md §4.2: the panel stands in three blocks, goes to two rows only when one
    /// does not fit, keeps the buttons on the right of the first row either way, and stays where the
    /// hand dragged it. Measured against synthetic widths, not against a live monitor.
    @discardableResult
    func smokeVerifyToolbarLayout() -> Bool {
        guard let toolbarView, activeScreenIndex != nil else { return false }
        let padding: CGFloat = 7

        // One width for every tool in the hand: the properties block is 176 whatever stands in it,
        // and that is the contract the count of rows leans on.
        toolbarView.maximumWidth = 4000
        var widths: [CGFloat] = []
        for tool in [EditorTool.rectangle, .text, .blur, .select, .arrow] {
            selectTool(tool)
            widths.append(toolbarView.sizeToFitContent().size.width)
        }
        guard let firstWidth = widths.first, widths.allSatisfy({ abs($0 - firstWidth) < 0.5 }) else { return false }
        guard EditorToolbarView.propertiesWidth == 176 else { return false }
        selectTool(.rectangle)

        // The free width of the reference shot without the comments panel: everything in one row.
        toolbarView.maximumWidth = 1077
        var ok = toolbarView.sizeToFitContent().rows == .one
        ok = ok && toolbarView.lineCapsule.frame.minY == toolbarView.doneButton.frame.minY

        // And with the comments panel: the properties go to the second row, the buttons stay on the
        // right of the first, and the chevrons of the split capsules stay with the tools.
        toolbarView.maximumWidth = 781
        let wrapped = toolbarView.sizeToFitContent()
        ok = ok && wrapped.rows == .two
        ok = ok && wrapped.size.width <= 781
        ok = ok && toolbarView.lineCapsule.frame.minY > toolbarView.doneButton.frame.minY
        ok = ok && toolbarView.doneButton.frame.minY == padding
        ok = ok && toolbarView.doneButton.frame.maxX <= wrapped.size.width - padding + 0.5
        for chevron in [toolbarView.shapeMenuButton, toolbarView.arrowOptionsButton, toolbarView.pencilMenuButton] {
            ok = ok && chevron.frame.minY == toolbarView.selectButton.frame.minY
        }

        // A panel that has room outside the capture never lies on it, whatever the working area.
        let areas: [(crop: CGRect, work: CGRect)] = [
            (CGRect(x: 500, y: 400, width: 540, height: 120), CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            (CGRect(x: 100, y: 100, width: 800, height: 400), CGRect(x: 0, y: 0, width: 1536, height: 824)),
            (CGRect(x: 0, y: 0, width: 600, height: 700), CGRect(x: 0, y: 0, width: 1200, height: 800)),
        ]
        for area in areas {
            let placed = EditorGeometry.placeToolbar(
                crop: area.crop, work: area.work, size: CGSize(width: 460, height: 50), notes: [],
                mayOverlap: false)
            ok = ok && !placed.intersects(area.crop) && area.work.contains(placed)
        }

        // Dragged by its free place the panel moves, and the next placement leaves it where it was
        // put instead of taking it back beside the capture.
        toolbarView.maximumWidth = 4000
        positionToolbar()
        let placedByItself = toolbarView.frame.origin
        beginToolbarDrag(at: CGPoint(x: placedByItself.x + 20, y: placedByItself.y + 20))
        dragToolbarTo(CGPoint(x: placedByItself.x + 140, y: placedByItself.y + 90))
        endToolbarDrag()
        let dragged = toolbarView.frame.origin
        ok = ok && hypot(dragged.x - placedByItself.x, dragged.y - placedByItself.y) > 1
        positionToolbar()
        ok = ok && hypot(toolbarView.frame.minX - dragged.x, toolbarView.frame.minY - dragged.y) < 0.5

        toolbarUserOrigin = nil
        toolbarDragGrab = nil
        selectTool(.select)
        positionToolbar()
        return ok
    }
}
