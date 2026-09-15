// Port of the undo/redo stacks in `OverlayEditorWindow.xaml.cs:38-39,621-666`, SPEC §1.5
import Foundation
import SnapikCore

/// Local overlay undo/redo history (SPEC §1.5: "Локальная история оверлея (не `SessionHistory`
/// из Core)"). Two LIFO stacks of `OverlaySnapshot`, exactly mirroring the Windows
/// `Stack<OverlaySnapshot>` pair — **not** a wrapper over Core's `SessionHistory` (that type
/// versions a whole `SnapikSession`, one revision per undo step; the overlay instead keeps its
/// own pre-commit snapshots of the single capture being edited, matching the Windows source of
/// truth in `OverlayEditorWindow.xaml.cs`). The class is still named `EditorHistory` per
/// CONTRACTS.md's naming, but its implementation follows SPEC.md, the higher-priority source of
/// behavior for this zone.
final class EditorHistory {
    private var undoStack: [OverlaySnapshot] = []
    private var redoStack: [OverlaySnapshot] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Port of `PushHistory()` (`:621-627`): pushes the given "before" snapshot and clears redo.
    func push(_ snapshot: OverlaySnapshot) {
        undoStack.append(snapshot)
        redoStack.removeAll()
    }

    /// Port of `OnUndoClick` (`:629-634`): pushes `current` onto redo, pops and returns the
    /// snapshot to restore.
    func undo(current: OverlaySnapshot) -> OverlaySnapshot? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return previous
    }

    /// Port of `OnRedoClick` (`:636-641`).
    func redo(current: OverlaySnapshot) -> OverlaySnapshot? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }

    /// Port of `_undo.Push(before)` call sites that push a snapshot but do not touch redo state
    /// implicitly cleared elsewhere (crop/resize commit paths push directly without going through
    /// `push(_:)`'s redo-clear, then clear redo themselves) — provided for parity with those call
    /// sites (`OnCropRequested:701-702`, `ApplyCaptureResizeAsync:177-178`).
    func pushWithoutClearingRedo(_ snapshot: OverlaySnapshot) {
        undoStack.append(snapshot)
    }

    func clearRedo() {
        redoStack.removeAll()
    }

    func reset() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}
