// Port of `SyncShotKind`/`PositionShotKind`/`SyncScaleSwitch`/`OnFitScaleClick`/
// `OnOneToOneScaleClick`/`OnSurfaceViewChanged` (`OverlayEditorWindow.xaml.cs:1641-1723`),
// SPEC-DELTA-4 §1.3 E-5, E-7, E-8, §3.5, §4, §5 point 3.
import AppKit
import SnapikCore

@MainActor
extension OverlayEditorController {
    /// Builds the switch and the caption once, the way `setupEditor` builds the panel, and puts both
    /// over the capture of the active screen.
    func setupScaleViews(on slot: OverlayScreenSlot) {
        if scaleSwitchView == nil {
            let scaleSwitch = EditorScaleSwitchView(language: language)
            scaleSwitch.onFitClicked = { [weak self] in self?.fitScaleClicked() }
            scaleSwitch.onOneToOneClicked = { [weak self] in self?.oneToOneScaleClicked() }
            slot.contentView.addSubview(scaleSwitch)
            scaleSwitchView = scaleSwitch
        }
        if shotKindView == nil {
            let caption = EditorShotKindView(frame: .zero)
            slot.contentView.addSubview(caption)
            shotKindView = caption
        }
        // A window that was never laid out on a monitor still has to answer what the capture is
        // fitted into: the working area it is standing on is that answer (`:1105-1109`).
        if fitBox.width <= 0 || fitBox.height <= 0, let screenIndex = activeScreenIndex {
            fitBox = EditorGeometry.reopenFitBox(windowSize: layoutWorkArea(screenIndex: screenIndex).size)
        }
        syncShotKind()
        syncScaleSwitch()
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

    // MARK: - The switch of the scale (E-5)

    /// Port of `SyncScaleSwitch` (`:1682-1693`): a capture that fits the screen at its own size has
    /// nothing to switch between, and one that does not says how far it was scaled down and which
    /// side did it.
    func syncScaleSwitch() {
        guard let capture, let scaleSwitchView else { return }
        let fit = EditorGeometry.fit(
            imageWidth: Double(capture.image.width), imageHeight: Double(capture.image.height),
            boxWidth: Double(fitBox.width), boxHeight: Double(fitBox.height))
        scaleSwitchView.isHidden = fit.boundBy == .none
        guard fit.boundBy != .none else { return }
        scaleSwitchView.update(
            fitCaption: EditorStrings.fitPercent(language, boundBy: fit.boundBy, percent: Int((fit.scale * 100).rounded())),
            fitted: canvasView?.viewScale == nil)
    }

    /// Port of `OnFitScaleClick` (`:1697-1702`). Both handlers end with the switch: a press on the
    /// segment that is already in force changes no scale, the canvas raises nothing, and the segments
    /// would be left showing neither of the two (SPEC-DELTA-4 §5 point 3).
    func fitScaleClicked() {
        canvasView?.viewOffset = .zero
        canvasView?.viewScale = nil
        syncScaleSwitch()
    }

    /// Port of `OnOneToOneScaleClick` (`:1704-1714`): the middle of the capture stays the middle, so
    /// at its own size the picture opens where the fitted one was looked at, and the clamp of the
    /// canvas takes it from there.
    func oneToOneScaleClicked() {
        guard let capture else { return }
        canvasView?.viewOffset = CGPoint(
            x: (CGFloat(capture.image.width) - cropRectLocal.width) / 2,
            y: (CGFloat(capture.image.height) - cropRectLocal.height) / 2)
        canvasView?.viewScale = 1
        syncScaleSwitch()
    }

    /// Port of `OnSurfaceViewChanged` (`:1718-1723`): the scale changed, by the switch or by the
    /// wheel — the segments follow it, the pills that left the capture are hidden, and the handles of
    /// the capture borders come back only while it is fitted.
    func surfaceViewChanged() {
        syncScaleSwitch()
        updateCaptureHandles()
        repositionChips()
    }
}
