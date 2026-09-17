// Port of `SyncShotKind`/`PositionShotKind`/`OnSurfaceViewChanged`
// (`OverlayEditorWindow.xaml.cs:1641-1723`), SPEC-DELTA-4 §1.3 E-7, E-8, §3.5, §4,
// SPEC-DELTA-5-editor.md §1.2 E-1.
//
// The switch of the scale is gone with the round of 1.6.0, and the file is named after what is
// left: the caption of the capture and the views that follow the scale the wheel gives it.
import AppKit
import SnapikCore

@MainActor
extension OverlayEditorController {
    /// Builds the caption once, the way `setupEditor` builds the panel, and puts it over the capture
    /// of the active screen.
    func setupScaleViews(on slot: OverlayScreenSlot) {
        if shotKindView == nil {
            let caption = EditorShotKindView(frame: .zero)
            slot.contentView.addSubview(caption)
            shotKindView = caption
        }
        syncShotKind()
        positionShotKind()
    }

    // MARK: - The caption of the capture (E-7)

    /// Port of `SyncShotKind` (`:1644-1666`): what the capture is, in words — the whole screen with
    /// the number of monitors behind it, or the name of the file that was imported, and the size in
    /// pixels either way. A capture of a region is what the editor has always shown, and it says
    /// nothing.
    func syncShotKind() {
        guard let capture, let shotKindView else { return }
        let size = "\(capture.image.width)×\(capture.image.height)"
        var parts: [String] = []
        switch capture.kind {
        case .fullscreen:
            parts = capture.monitorCount > 1
                ? [EditorStrings.wholeScreen(language), EditorStrings.monitorCount(language, capture.monitorCount), size]
                : [EditorStrings.wholeScreen(language), size]
        case .import:
            parts = capture.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? [EditorStrings.importedFile(language), size]
                : [EditorStrings.importedFile(language), capture.title, size]
        case .region:
            parts = []
        }
        shotKindView.isHidden = parts.isEmpty
        guard !parts.isEmpty else { return }
        shotKindView.update(
            symbolName: capture.kind == .fullscreen ? EditorIcon.display : EditorIcon.importedFile,
            caption: parts.joined(separator: " · "))
    }

    /// Port of `PositionShotKind` (`:1670-1678`): the caption stands inside the top right corner of
    /// the capture, eight points in from both edges.
    func positionShotKind() {
        guard let shotKindView, !shotKindView.isHidden, let screenIndex = activeScreenIndex else { return }
        let work = layoutWorkArea(screenIndex: screenIndex)
        let size = shotKindView.sizeToFitContent()
        let left = EditorGeometry.clamp(
            cropRectLocal.maxX - size.width - 8, work.minX + 8, max(work.minX + 8, work.maxX - size.width - 8))
        let top = EditorGeometry.clamp(cropRectLocal.minY + 8, work.minY + 8, max(work.minY + 8, work.maxY - size.height - 8))
        shotKindView.frame = CGRect(origin: CGPoint(x: left, y: top), size: size)
    }

    /// Port of `OnSurfaceViewChanged` (`:1718-1723`): the scale changed under the wheel — the pills
    /// that left the capture are hidden, and the handles of the capture borders come back only while
    /// it is fitted. It asks the switch beside the panel for nothing any more: there is none.
    func surfaceViewChanged() {
        // The pills and the handles are placed from `imageRect`, and the scale has just moved it:
        // asking the canvas to redraw would answer too late, after they were placed from the old one.
        canvasView?.recomputeImageRect()
        updateCaptureHandles()
        repositionChips()
    }
}
