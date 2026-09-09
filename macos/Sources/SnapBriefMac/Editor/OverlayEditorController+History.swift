// Port of `SnapshotState`/`RestoreState`/`PushHistory`/`OnUndoClick`/`OnRedoClick`
// (`OverlayEditorWindow.xaml.cs:621-666`), SPEC §1.5.
import AppKit
import SnapBriefCore

@MainActor
extension OverlayEditorController {
    /// Port of `SnapshotState()` (`:643`).
    func snapshotState() -> OverlaySnapshot? {
        guard let capture else { return nil }
        return OverlaySnapshot(capture: capture.snapshot(), cropRect: cropRectLocal, visibleChipIds: visibleChipIds, shotNoteVisible: shotNoteChipView?.superview != nil)
    }

    /// Port of `PushHistory()` (`:621-627`): pushes the snapshot taken **before** the mutation
    /// that just happened, and refreshes `lastSnapshot` to the new "before" baseline.
    func pushHistory() {
        guard let before = lastSnapshot else { return }
        history.push(before)
        lastSnapshot = snapshotState()
        refreshUndoRedoButtons()
    }

    /// Port of `OnUndoClick` (`:629-634`).
    func performUndo() {
        guard !busyCrop, !isModalOpen, captureResizeCorner < 0, let current = snapshotState() else { return }
        guard let previous = history.undo(current: current) else { return }
        restoreState(previous)
    }

    /// Port of `OnRedoClick` (`:636-641`).
    func performRedo() {
        guard !busyCrop, !isModalOpen, captureResizeCorner < 0, let current = snapshotState() else { return }
        guard let next = history.redo(current: current) else { return }
        restoreState(next)
    }

    /// Port of `RestoreState(OverlaySnapshot)` (`:645-666`).
    func restoreState(_ state: OverlaySnapshot) {
        guard let capture, let screenIndex = activeScreenIndex else { return }
        capture.restore(state.capture)
        cropRectLocal = state.cropRect
        visibleChipIds = state.visibleChipIds

        canvasView?.capture = capture
        settingUp = true
        if let shotNoteChipView { shotNoteChipView.note = capture.note }
        settingUp = false

        let slot = slots[screenIndex]
        canvasContainerView?.frame = cropRectLocal
        canvasView?.frame = CGRect(origin: .zero, size: cropRectLocal.size)
        slot.contentView.holeRectLocal = cropRectLocal
        updateCaptureHandles()

        if state.shotNoteVisible {
            showShotNoteChip(focus: false)
        } else {
            hideShotNoteChip()
        }

        lastSnapshot = snapshotState()
        rebuildChips(on: slot)
        updateContextNoteAffordance(annotation: canvasView?.selectedAnnotation)
        positionToolbar()
        canvasView?.needsDisplay = true
        refreshUndoRedoButtons()
    }

    func refreshUndoRedoButtons() {
        toolbarView?.setUndoRedoEnabled(canUndo: history.canUndo, canRedo: history.canRedo)
    }
}
