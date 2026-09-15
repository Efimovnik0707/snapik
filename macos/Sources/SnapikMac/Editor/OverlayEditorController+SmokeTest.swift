// Test-only hooks for `--smoke-test` (SPEC §8.4 points 6, 9, 10; CONTRACTS.md "Editor"). These
// exist because the extended smoke test has no real mouse/keyboard input to synthesize gestures
// with (unlike `MacInputInjector`, which only targets *other* apps' paste shortcuts) — each hook
// drives the same model/view state a real gesture would, synchronously, on the main thread, so
// `App/SmokeTestRunner.swift` (out of this zone) can call them without `async`/completion
// handlers. None of these hooks go through `persistCurrentSource`'s disk round trip: they are
// about verifying in-memory editor behavior (preview pixels, handle geometry, chip wiring), not
// re-exercising the asset-store write path already covered by `+Selection.swift`/`+Resize.swift`
// in normal use and by the Imaging zone's own `ImageCodec` tests.
import AppKit
import SnapikCore

@MainActor
extension OverlayEditorController {
    /// Simulates drawing a selection rectangle (in frame pixels) and transitions straight into
    /// markup mode, mirroring `finishSelection` without requiring real mouse events. Returns
    /// `false` if there is already a capture in progress, the overlay is not presented, or the
    /// rect does not land on any screen/inside the frame.
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

    /// Creates a Rectangle annotation at the given capture-pixel geometry (mirrors
    /// `AnnotationCanvasView.mouseUp`'s rectangle-creation branch: append, select, notify
    /// `annotationCreated`, which auto-opens its comment chip per SPEC §1.4). If `note` is
    /// supplied, types it into that auto-opened chip the same way a real edit would (sets the text
    /// view's string and fires the chip's own `onNoteChanged`, so history/label bookkeeping runs
    /// identically to user input). Returns the new annotation's id, or `nil` on failure.
    @discardableResult
    func smokeCreateRectangle(_ rectInCapturePixels: CGRect, note: String?) -> String? {
        guard let capture, activeScreenIndex != nil, !busyCrop, captureResizeCorner < 0 else { return nil }
        let imageBounds = CGRect(x: 0, y: 0, width: capture.image.width, height: capture.image.height)
        let clamped = rectInCapturePixels.intersection(imageBounds)
        guard clamped.width > 0, clamped.height > 0 else { return nil }

        let annotation = EditorAnnotation(
            kind: .rectangle,
            points: [CGPoint(x: clamped.minX, y: clamped.minY), CGPoint(x: clamped.maxX, y: clamped.maxY)],
            color: activeColor,
            thickness: activeThickness)
        capture.annotations.append(annotation)
        canvasView?.selectAnnotation(id: annotation.id)
        annotationCreated(annotation)
        canvasView?.needsDisplay = true

        if let note, let chip = chipViews[annotation.id] {
            chip.textView.string = note
            chip.onNoteChanged?(note)
        }

        return annotation.id.description
    }

    /// SPEC §8.4 point 6: starts an unfinished blur gesture (a live `draft` on the canvas, exactly
    /// what `AnnotationCanvasView.draw(_:)` renders as the translucent preview fill — SPEC §1.7),
    /// renders the canvas before and during, and cancels the gesture without committing a blur
    /// annotation. Returns `true` only if the rendered pixels actually differ.
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
            color: activeColor,
            thickness: activeThickness)

        let during = renderCanvasSnapshotForSmokeTest(canvasView)

        // Cancel the gesture (mirrors the Escape branch of `AnnotationCanvasView.keyDown` while a
        // draft is live) — no blur annotation is ever committed by this probe.
        canvasView.draft = nil
        canvasView.needsDisplay = true

        guard let during else { return false }
        return before != during
    }

    /// SPEC §8.4 point 9 (scoped down for a synchronous, no-mouse-input hook — see this file's
    /// header comment): confirms the four capture-corner handles exist with a 22x22 hit target,
    /// then drives one handle's own drag callbacks (exactly the ones `CaptureHandleView.mouseDown`/
    /// `mouseDragged` invoke) partway through a resize and checks that `cropRectLocal` actually
    /// changed, before cancelling the drag without committing (never touches disk).
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

    /// Creates a Comment pin at `at` (capture pixel space), mirroring the real one-shot flow
    /// (`AnnotationCanvasView.mouseDown`'s `.comment` branch + `annotationCreated`): the pin picks
    /// up whatever `commentParentId` is currently armed (set by `commentButtonClicked()` or the
    /// `N` hotkey beforehand), its second point is offset `(8,8)` and clamped, the tool returns to
    /// `.select`, and its chip auto-opens focused. If `note` is supplied, types it in exactly like
    /// a real edit. Returns the new pin's id, or `nil` on failure. Port of the placement half of
    /// `RunNoteAffordanceProbe` (`OverlayEditorWindow.xaml.cs:107-202`, SPEC-DELTA-2B.md §C8).
    @discardableResult
    func smokeCreateComment(at point: CGPoint, note: String?) -> SBGuid? {
        guard let capture, activeScreenIndex != nil, !busyCrop, captureResizeCorner < 0 else { return nil }
        let imageBounds = CGRect(x: 0, y: 0, width: capture.image.width, height: capture.image.height)
        guard imageBounds.contains(point) else { return nil }

        let annotation = EditorAnnotation(kind: .comment, points: [point, point], color: activeColor, thickness: activeThickness)
        capture.annotations.append(annotation)
        annotationCreated(annotation)

        if let note, let chip = chipViews[annotation.id] {
            chip.textView.string = note
            chip.onNoteChanged?(note)
        }
        return annotation.id
    }

    /// Port of `RunNoteAffordanceProbe` (`OverlayEditorWindow.xaml.cs:107-202`), updated for the
    /// one-shot Comment tool (SPEC-DELTA-2B.md §C8): arming Comment on a selected arrow links the
    /// pin to it; the tool returns to Select after one click; a second, unrelated comment collapses
    /// the first to 43pt while it opens at 270pt and neither chip's frame overlaps the other's;
    /// deleting a comment's note removes the pin entirely; finishing an empty Rectangle's chip
    /// removes only the chip, not the shape; a Text annotation's chip writes into `.text`.
    @discardableResult
    func smokeRunNoteAffordanceProbe() -> Bool {
        guard let capture, activeScreenIndex != nil else { return false }
        let w = CGFloat(capture.image.width)
        let h = CGFloat(capture.image.height)
        guard w >= 60, h >= 60 else { return false }

        let arrow = EditorAnnotation(kind: .arrow, points: [CGPoint(x: 10, y: 10), CGPoint(x: 60, y: 40)], color: activeColor, thickness: activeThickness)
        capture.annotations.append(arrow)
        canvasView?.selectAnnotation(id: arrow.id)
        commentButtonClicked()
        guard canvasView?.tool == .comment, commentParentId == arrow.id else { return false }

        guard let firstId = smokeCreateComment(at: CGPoint(x: w * 0.5, y: h * 0.5), note: nil) else { return false }
        guard canvasView?.tool == .select else { return false }
        guard visibleChipIds.contains(firstId), let firstAnnotation = capture.annotations.first(where: { $0.id == firstId }) else { return false }
        guard firstAnnotation.parentAnnotationId == arrow.id else { return false }

        let commentProbeText = "smoke-comment-probe"
        guard let firstChip = chipViews[firstId] else { return false }
        firstChip.textView.string = commentProbeText
        firstChip.onNoteChanged?(commentProbeText)
        guard firstAnnotation.note == commentProbeText else { return false }

        guard let secondId = smokeCreateComment(at: CGPoint(x: w * 0.2, y: h * 0.8), note: "second") else { return false }
        guard let firstChipAfter = chipViews[firstId], let secondChip = chipViews[secondId] else { return false }
        guard abs(firstChipAfter.frame.width - CommentChipView.collapsedWidth) < 0.5 else { return false }
        guard abs(secondChip.frame.width - CommentChipView.expandedWidth) < 0.5 else { return false }
        guard !firstChipAfter.frame.intersects(secondChip.frame) else { return false }

        deleteAnnotationNote(firstAnnotation)
        guard !capture.annotations.contains(where: { $0.id == firstId }), chipViews[firstId] == nil else { return false }

        let rectRect = CGRect(x: w * 0.05, y: h * 0.05, width: max(w * 0.1, 10), height: max(h * 0.1, 10))
        guard let rectIdString = smokeCreateRectangle(rectRect, note: nil), let rectId = SBGuid(uuidString: rectIdString) else { return false }
        finishChip(rectId)
        guard capture.annotations.contains(where: { $0.id == rectId }), chipViews[rectId] == nil else { return false }

        let textAnnotation = EditorAnnotation(
            kind: .text, points: [CGPoint(x: w * 0.3, y: h * 0.3), CGPoint(x: w * 0.3 + 80, y: h * 0.3 + 40)],
            color: activeColor, thickness: activeThickness)
        capture.annotations.append(textAnnotation)
        annotationCreated(textAnnotation)
        guard let textChip = chipViews[textAnnotation.id] else { return false }
        let textProbeText = "smoke-text-probe"
        textChip.textView.string = textProbeText
        textChip.onNoteChanged?(textProbeText)

        return textAnnotation.text == textProbeText && textAnnotation.note.isEmpty
    }

    /// The state that would be delivered to `OverlayEditorDelegate.overlayEditor(_:didCommit:annotations:)`
    /// if committed right now, without actually closing the overlay.
    func smokeCurrentState() -> (capture: CaptureItem, annotations: [AnnotationItem])? {
        guard let capture else { return nil }
        let coreCapture = capture.toCore()
        return (coreCapture, coreCapture.annotations)
    }

    /// Commits the current capture programmatically, exactly as if the user had clicked outside it
    /// (SPEC §1.8's background-click completion path).
    func smokeCommit() {
        commit(addNext: false)
    }

    // MARK: - Appearance popover probes (SPEC §1.3, §6.2 "Дополнение 2026-09-09")

    /// Drives the same immediate-apply path a real color swatch click / hex commit / slider drag
    /// would (`applyAppearance`), without needing the popover UI on screen. The first call in an
    /// uncommitted session captures the pre-edit baseline exactly as `toggleAppearancePopover()`
    /// does when it opens the real popover; call `smokeUndo()` to commit that session and undo it
    /// in one step (mirrors `RunNoteAffordanceProbe`'s direct `ApplyAppearance` calls,
    /// `OverlayEditorWindow.xaml.cs:134-138`).
    func smokeSetAppearance(color: NSColor?, thickness: Double?) {
        if appearanceBefore == nil { appearanceBefore = snapshotState() }
        applyAppearance(color: color, thickness: thickness)
    }

    /// The selected annotation's current color (`#AARRGGBB`) and thickness, or `nil` if nothing is
    /// selected.
    func smokeSelectedAnnotationAppearance() -> (color: String, thickness: Double)? {
        guard let selected = canvasView?.selectedAnnotation else { return nil }
        return (selected.color.hexARGB, selected.thickness)
    }

    /// Port of `OnUndoClick` for probes with no toolbar button to click. If a `smokeSetAppearance`
    /// session is still open, first commits it exactly as closing the real popover would (SPEC
    /// §1.3 point 3's "одна запись истории"), so the resulting single undo restores the pre-edit
    /// state in one step (mirrors `RunNoteAffordanceProbe`'s `OnAppearanceClosed` + `OnUndoClick`
    /// pair, `OverlayEditorWindow.xaml.cs:139-140`).
    func smokeUndo() {
        commitAppearanceSession()
        performUndo()
    }

    /// Forces `AnnotationCanvasView.draw(_:)` to run against an off-screen bitmap and returns its
    /// raw pixel bytes, so callers can byte-compare "before" vs. "during a gesture" renders.
    private func renderCanvasSnapshotForSmokeTest(_ canvasView: AnnotationCanvasView) -> Data? {
        guard canvasView.bounds.width > 0, canvasView.bounds.height > 0,
            let rep = canvasView.bitmapImageRepForCachingDisplay(in: canvasView.bounds)
        else { return nil }
        canvasView.cacheDisplay(in: canvasView.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }
}
