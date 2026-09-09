// Port of `OnWindowMouseDown/Move/Up`, `RestoreLastRegion` (`OverlayEditorWindow.xaml.cs:166-226`,
// `OverlayEditorWindow.Save.cs:61-83`), SPEC §1.2 steps 6-9, §1.13 point 9.
import AppKit
import SnapBriefCore

extension OverlayEditorController {
    /// Wires one screen's selection-mode mouse callbacks. Selection is scoped to whichever screen
    /// receives the initiating `mouseDown` (AppKit keeps delivering `mouseDragged`/`mouseUp` to
    /// that same view even if the cursor leaves its window); other screens simply keep showing a
    /// full, holeless shade for the duration — SPEC's own multi-monitor note (§9.5) leaves the
    /// exact cross-screen selection UX as a "fix on real hardware" item, so this is a deliberate,
    /// documented simplification rather than a silent gap.
    func wireSelectionCallbacks(_ contentView: OverlayContentView, screenIndex: Int) {
        contentView.onMouseDown = { [weak self] index, point in self?.selectionMouseDown(screenIndex: index, point: point) }
        contentView.onMouseDragged = { [weak self] index, point in self?.selectionMouseDragged(screenIndex: index, point: point) }
        contentView.onMouseUp = { [weak self] index, point in self?.selectionMouseUp(screenIndex: index, point: point) }
        contentView.onBackgroundClick = { [weak self] index, point in self?.backgroundClicked(screenIndex: index, point: point) }
        contentView.onKeyDown = { [weak self] event in self?.handleKeyDown(event) }
    }

    /// Port of `OnWindowMouseDown` (`:166-174`).
    private func selectionMouseDown(screenIndex: Int, point: CGPoint) {
        guard !busyCrop, capture == nil, isNewCapture else { return }
        selectionScreenIndex = screenIndex
        selectionStartLocal = point
        selectionRectLocal = CGRect(origin: point, size: .zero)
        updateSelectionVisual()
    }

    /// Port of `OnWindowMouseMove` (`:176-182`).
    private func selectionMouseDragged(screenIndex: Int, point: CGPoint) {
        guard let start = selectionStartLocal, selectionScreenIndex == screenIndex else { return }
        selectionRectLocal = EditorGeometry.normalize(start, point)
        updateSelectionVisual()
    }

    /// Port of `OnWindowMouseUp` selection-completion half (`:184-226`).
    private func selectionMouseUp(screenIndex: Int, point: CGPoint) {
        guard let start = selectionStartLocal, selectionScreenIndex == screenIndex else { return }
        selectionRectLocal = EditorGeometry.normalize(start, point)
        updateSelectionVisual()
        selectionStartLocal = nil

        guard selectionRectLocal.width >= 12, selectionRectLocal.height >= 12 else {
            selectionRectLocal = .zero
            updateSelectionVisual()
            return
        }

        finishSelection(screenIndex: screenIndex, localRect: selectionRectLocal)
    }

    /// Port of `OnWindowMouseUp`'s background-click completion branch (`:186-193`, SPEC §1.8
    /// "Клик вне снимка по затемнённому фону").
    private func backgroundClicked(screenIndex: Int, point: CGPoint) {
        guard capture != nil, !busyCrop, screenIndex == activeScreenIndex else { return }
        guard !cropRectLocal.contains(point) else { return }
        commit(addNext: false)
    }

    private func updateSelectionVisual() {
        guard let screenIndex = selectionScreenIndex else { return }
        slots[screenIndex].contentView.holeRectLocal = selectionRectLocal
        slots[screenIndex].contentView.hintView.isHidden = selectionRectLocal.width > 0
    }

    /// Port of the pixel crop + `AddImageAsync` half of `OnWindowMouseUp` (`:200-225`).
    private func finishSelection(screenIndex: Int, localRect: CGRect) {
        busyCrop = true

        guard let pixelRect = framePixelRect(fromLocalRect: localRect, screenIndex: screenIndex), let cropped = desktopFrame.image.cropping(to: pixelRect) else {
            busyCrop = false
            selectionRectLocal = .zero
            updateSelectionVisual()
            return
        }

        activeScreenIndex = screenIndex
        let newCapture = EditorCapture(image: cropped, sourceImagePath: "")
        newCapture.displayLabel = (try? CaptureLabels.forIndex(captureIndex)) ?? "A"
        capture = newCapture
        cropRectLocal = localRect
        isNewCapture = true

        persistCurrentSource(cropped) { [weak self] result in
            guard let self else { return }
            self.busyCrop = false
            switch result {
            case .success:
                self.setupEditor()
            case .failure(let error):
                self.showHintError(EditorStrings.couldNotSaveCapture(self.language, "\(error)"))
                self.capture = nil
                self.selectionRectLocal = .zero
                self.updateSelectionVisual()
            }
        }
    }

    // MARK: - Coordinate conversions (SPEC §9.5)

    /// `local` (in `slots[screenIndex]`'s point space) -> the frame-pixel rect it covers,
    /// clamped to the frame's bounds.
    func framePixelRect(fromLocalRect local: CGRect, screenIndex: Int) -> CGRect? {
        let globalTopLeft = globalPoint(fromLocal: CGPoint(x: local.minX, y: local.minY), screenIndex: screenIndex)
        let globalBottomRight = globalPoint(fromLocal: CGPoint(x: local.maxX, y: local.maxY), screenIndex: screenIndex)
        let pixelTopLeft = ScreenGeometry.framePixels(fromScreenPoint: unflip(globalTopLeft), frame: desktopFrame)
        let pixelBottomRight = ScreenGeometry.framePixels(fromScreenPoint: unflip(globalBottomRight), frame: desktopFrame)
        let rect = CGRect(
            x: min(pixelTopLeft.x, pixelBottomRight.x), y: min(pixelTopLeft.y, pixelBottomRight.y),
            width: abs(pixelBottomRight.x - pixelTopLeft.x), height: abs(pixelBottomRight.y - pixelTopLeft.y))
            .intersection(CGRect(x: 0, y: 0, width: desktopFrame.pixelWidth, height: desktopFrame.pixelHeight))
        return rect.width >= 1 && rect.height >= 1 ? rect : nil
    }

    /// The inverse: a frame-pixel rect -> the local rect it covers on `screenIndex`.
    func localRect(fromFramePixelRect pixelRect: CGRect, screenIndex: Int) -> CGRect {
        let topLeftScreen = ScreenGeometry.screenPoint(fromFramePixels: CGPoint(x: pixelRect.minX, y: pixelRect.minY), frame: desktopFrame)
        let bottomRightScreen = ScreenGeometry.screenPoint(fromFramePixels: CGPoint(x: pixelRect.maxX, y: pixelRect.maxY), frame: desktopFrame)
        let localTopLeft = localPoint(fromGlobal: ScreenGeometry.flipToTopLeft(topLeftScreen), screenIndex: screenIndex)
        let localBottomRight = localPoint(fromGlobal: ScreenGeometry.flipToTopLeft(bottomRightScreen), screenIndex: screenIndex)
        return CGRect(
            x: min(localTopLeft.x, localBottomRight.x), y: min(localTopLeft.y, localBottomRight.y),
            width: abs(localBottomRight.x - localTopLeft.x), height: abs(localBottomRight.y - localTopLeft.y))
    }

    /// Inverts `ScreenGeometry.flipToTopLeft` (`flip(p) = (p.x - global.minX, global.maxY - p.y)`,
    /// CONTRACTS.md §"Координаты"), since only the forward direction is declared there.
    private func unflip(_ flipped: CGPoint) -> CGPoint {
        let global = ScreenGeometry.globalPointsRect
        return CGPoint(x: flipped.x + global.minX, y: global.maxY - flipped.y)
    }

    // MARK: - Remember last region (SPEC §1.13 point 9, simplified)

    /// Port of `RestoreLastRegion`/`RememberCurrentRegion` (`OverlayEditorWindow.Save.cs:47-83`).
    /// Persisted next to the session directory: `EditorWorkspaceContext` has no dedicated
    /// settings/state path for this (see the final report's deviation notes), so this uses a
    /// hidden file beside the sessions root rather than under the shell's own app-support layout.
    private var lastRegionURL: URL {
        workspaceContext.sessionDirectory.deletingLastPathComponent().appendingPathComponent(".snapbrief-last-region.json")
    }

    private struct SavedRegion: Codable {
        let left: Int
        let top: Int
        let width: Int
        let height: Int
        let x: Double
        let y: Double
        let w: Double
        let h: Double
    }

    func restoreLastRegionIfNeeded() {
        guard settings.rememberRegion, isNewCapture, capture == nil else { return }
        guard let data = try? Data(contentsOf: lastRegionURL), let region = try? JSONDecoder().decode(SavedRegion.self, from: data) else { return }
        guard region.left == desktopFrame.left, region.top == desktopFrame.top,
            region.width == desktopFrame.pixelWidth, region.height == desktopFrame.pixelHeight
        else { return }
        guard region.x.isFinite, region.y.isFinite, region.w.isFinite, region.h.isFinite,
            region.x >= 0, region.y >= 0, region.w > 0, region.h > 0, region.x + region.w <= 1.00001, region.y + region.h <= 1.00001
        else { return }

        let pixelRect = CGRect(
            x: region.x * Double(desktopFrame.pixelWidth), y: region.y * Double(desktopFrame.pixelHeight),
            width: region.w * Double(desktopFrame.pixelWidth), height: region.h * Double(desktopFrame.pixelHeight))
        guard let cropped = desktopFrame.image.cropping(to: pixelRect) else { return }

        let centerScreen = ScreenGeometry.screenPoint(fromFramePixels: CGPoint(x: pixelRect.midX, y: pixelRect.midY), frame: desktopFrame)
        guard let screenIndex = slots.firstIndex(where: { $0.screen.frame.contains(centerScreen) }) else { return }

        activeScreenIndex = screenIndex
        let newCapture = EditorCapture(image: cropped, sourceImagePath: "")
        newCapture.displayLabel = (try? CaptureLabels.forIndex(captureIndex)) ?? "A"
        capture = newCapture
        cropRectLocal = localRect(fromFramePixelRect: pixelRect, screenIndex: screenIndex)

        busyCrop = true
        persistCurrentSource(cropped) { [weak self] result in
            guard let self else { return }
            self.busyCrop = false
            if case .success = result {
                self.setupEditor()
            } else {
                self.capture = nil
                self.selectionRectLocal = .zero
            }
        }
    }

    /// Port of `RememberCurrentRegion` (`Save.cs:47-59`). Called from the commit/save paths.
    func rememberCurrentRegionIfNeeded() {
        guard isNewCapture, settings.rememberRegion, cropRectLocal.width > 0, let screenIndex = activeScreenIndex else { return }
        guard let pixelRect = framePixelRect(fromLocalRect: cropRectLocal, screenIndex: screenIndex) else { return }

        let region = SavedRegion(
            left: desktopFrame.left, top: desktopFrame.top, width: desktopFrame.pixelWidth, height: desktopFrame.pixelHeight,
            x: Double(pixelRect.minX) / Double(desktopFrame.pixelWidth), y: Double(pixelRect.minY) / Double(desktopFrame.pixelHeight),
            w: Double(pixelRect.width) / Double(desktopFrame.pixelWidth), h: Double(pixelRect.height) / Double(desktopFrame.pixelHeight))

        try? JSONEncoder().encode(region).write(to: lastRegionURL, options: [.atomic])
    }
}
