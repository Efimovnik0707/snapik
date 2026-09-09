// Port of `InitializeCaptureHandles`/`UpdateCaptureHandles`/`OnCaptureResizeCompleted`/
// `ApplyCaptureResizeAsync` (`OverlayEditorWindow.Resize.cs`), SPEC §1.6.
import AppKit
import SnapBriefCore

extension OverlayEditorController {
    /// Port of `InitializeCaptureHandles` (`Resize.cs:58-101`).
    func setupCaptureHandles(on slot: OverlayScreenSlot) {
        guard captureHandleViews.isEmpty else {
            updateCaptureHandles()
            return
        }
        let outline = ResizeOutlineView(frame: cropRectLocal)
        outline.isHidden = true
        slot.contentView.addSubview(outline)
        resizeOutlineView = outline

        for corner in 0..<4 {
            let handle = CaptureHandleView(corner: corner)
            handle.onDragStarted = { [weak self] in self?.captureResizeDragStarted(corner: corner) }
            handle.onDragChanged = { [weak self] point in self?.captureResizeDragChanged(corner: corner, pointInContentView: point) }
            handle.onDragEnded = { [weak self] _ in self?.captureResizeDragEnded() }
            slot.contentView.addSubview(handle)
            captureHandleViews.append(handle)
        }
        updateCaptureHandles()
    }

    /// Port of `UpdateCaptureHandles` (`Resize.cs:103-124`).
    func updateCaptureHandles() {
        guard let capture, let screenIndex = activeScreenIndex else { return }
        if resizeSourceImage == nil {
            // "Expansion can reveal only pixels already captured, never a newer desktop."
            if isNewCapture {
                resizeSourceImage = desktopFrame.image
                resizeSourceRectLocal = fullFrameLocalRect(screenIndex: screenIndex)
            } else {
                resizeSourceImage = capture.image
                resizeSourceRectLocal = cropRectLocal
            }
        }

        let origins = EditorGeometry.captureHandleOrigins(cropRect: cropRectLocal, windowSize: slots[screenIndex].contentView.bounds.size)
        for (index, handle) in captureHandleViews.enumerated() where index < origins.count {
            handle.frame = CGRect(origin: origins[index], size: CGSize(width: 22, height: 22))
        }
        resizeOutlineView?.frame = cropRectLocal
    }

    /// This screen's own local rect, expressed the same way `cropRectLocal` is (top-left origin,
    /// full window bounds) — the "resize source" while the capture is still brand-new is the
    /// frozen desktop image occupying the whole window, not just the current crop.
    private func fullFrameLocalRect(screenIndex: Int) -> CGRect {
        CGRect(origin: .zero, size: slots[screenIndex].contentView.bounds.size)
    }

    // MARK: - Drag lifecycle (SPEC §1.6)

    private func captureResizeDragStarted(corner: Int) {
        guard capture != nil, !busyCrop else { return }
        captureResizeCorner = corner
        resizeOriginalCropRectLocal = cropRectLocal
        resizeOutlineView?.isHidden = false
        updateCaptureHandles()
    }

    private func captureResizeDragChanged(corner: Int, pointInContentView: CGPoint) {
        guard captureResizeCorner == corner, let screenIndex = activeScreenIndex else { return }
        let limit = resizeSourceRectLocal
        cropRectLocal = ResizeGeometry.resize(
            original: resizeOriginalCropRectLocal, corner: corner, point: pointInContentView, limit: limit, minimum: 12)
        slots[screenIndex].contentView.holeRectLocal = cropRectLocal
        updateCaptureHandles()
    }

    private func captureResizeDragEnded() {
        guard captureResizeCorner >= 0 else { return }
        captureResizeCorner = -1
        resizeOutlineView?.isHidden = true
        let requestedRect = cropRectLocal
        cropRectLocal = resizeOriginalCropRectLocal
        guard requestedRect != resizeOriginalCropRectLocal else {
            updateCropVisual()
            return
        }
        applyCaptureResize(requestedRectLocal: requestedRect)
    }

    private func updateCropVisual() {
        guard let screenIndex = activeScreenIndex else { return }
        slots[screenIndex].contentView.holeRectLocal = cropRectLocal
        updateCaptureHandles()
        canvasContainerView?.frame = cropRectLocal
        canvasView?.frame = CGRect(origin: .zero, size: cropRectLocal.size)
    }

    /// Port of `ApplyCaptureResizeAsync` (`Resize.cs:140-190`).
    private func applyCaptureResize(requestedRectLocal: CGRect) {
        guard let capture, let resizeSourceImage, activeScreenIndex != nil else { return }
        busyCrop = true
        let before = snapshotState()

        let plan = EditorGeometry.captureResizePlan(
            requestedRectLocal: requestedRectLocal, resizeSourceRectLocal: resizeSourceRectLocal,
            resizeSourcePixelSize: CGSize(width: resizeSourceImage.width, height: resizeSourceImage.height),
            currentCropRectLocal: cropRectLocal, currentCapturePixelSize: CGSize(width: capture.image.width, height: capture.image.height))

        guard let croppedSourceImage = resizeSourceImage.cropping(to: plan.sourcePixelRect) else {
            busyCrop = false
            return
        }

        let remapped = capture.snapshot()
        for annotation in remapped.annotations {
            annotation.points = annotation.points.map { EditorGeometry.remapAnnotationPoint($0, scale: plan.annotationScale, offset: plan.annotationOffset) }
            annotation.additionalPathSegments = annotation.additionalPathSegments.map { segment in
                segment.map { EditorGeometry.remapAnnotationPoint($0, scale: plan.annotationScale, offset: plan.annotationOffset) }
            }
        }
        let sourceCapture = EditorCapture(id: capture.id, image: resizeSourceImage, sourceImagePath: capture.sourceImagePath, dpiX: capture.dpiX, dpiY: capture.dpiY)
        sourceCapture.note = capture.note
        sourceCapture.annotations = remapped.annotations

        let normalized = EditorGeometry.normalizedRect(
            pixelRect: plan.sourcePixelRect, imageWidth: resizeSourceImage.width, imageHeight: resizeSourceImage.height)

        persistCurrentSource(croppedSourceImage) { [weak self] result in
            guard let self else { return }
            self.busyCrop = false
            switch result {
            case .success(let relativePath):
                do {
                    // `sourceCapture.image` is already `resizeSourceImage`, so `toCore()` (which
                    // always normalizes against `self.image`'s own pixel size) uses the correct,
                    // possibly-larger-than-`capture`, dimensions here.
                    let coreResult = try CaptureCropper.crop(
                        source: sourceCapture.toCore(), cropBounds: normalized, croppedSourceImagePath: relativePath,
                        croppedPixelWidth: Int(plan.sourcePixelRect.width), croppedPixelHeight: Int(plan.sourcePixelRect.height))
                    let updated = EditorCapture.fromCore(coreResult.croppedCapture, image: croppedSourceImage)
                    updated.displayLabel = capture.displayLabel
                    self.capture = updated
                    self.cropRectLocal = plan.newCropRectLocal
                    self.resizeSourceImage = nil
                    if let before { self.history.pushWithoutClearingRedo(before) }
                    self.history.clearRedo()
                    self.setupEditor()
                    self.refreshUndoRedoButtons()
                } catch {
                    if let before { self.restoreState(before) }
                    self.showHintError(EditorStrings.couldNotResizeCapture(self.language, "\(error)"))
                }
            case .failure(let error):
                if let before { self.restoreState(before) }
                self.showHintError(EditorStrings.couldNotResizeCapture(self.language, "\(error)"))
            }
        }
    }
}
