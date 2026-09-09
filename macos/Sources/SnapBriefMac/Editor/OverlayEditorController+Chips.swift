// Port of `RefreshLabels`, `AddChip`/`RebuildChips`/`RepositionChips`, `PositionChip`,
// `UpdateContextNoteAffordance`, `ShotNoteChip` handling, `PositionToolbar`, `GetCropMonitorWorkArea`
// (`OverlayEditorWindow.xaml.cs:339-611`), SPEC §1.4, §6.2.
import AppKit
import SnapBriefCore

@MainActor
extension OverlayEditorController {
    // MARK: - Canvas event handlers (SPEC §1.3/§1.4)

    /// Port of `OnAnnotationCreated` (`:339-352`).
    func annotationCreated(_ annotation: EditorAnnotation) {
        guard capture != nil else { return }
        pushHistory()
        refreshLabels()
        if annotation.kind == .rectangle {
            visibleChipIds.insert(annotation.id)
            addChip(for: annotation, focus: true)
            contextNoteButtonView?.isHidden = true
        } else {
            updateContextNoteAffordance(annotation: annotation)
        }
    }

    /// Port of `OnSelectionChanged` (`:354-359`); the C# guard on a pressed mouse button doesn't
    /// apply here (selection changes on mouse-down happen synchronously before any drag begins).
    func selectionChanged(_ annotation: EditorAnnotation?) {
        syncAppearance()
        repositionChips()
        updateContextNoteAffordance(annotation: annotation)
    }

    /// Port of `OnAnnotationChanged` (`:361-368`).
    func annotationChanged() {
        pushHistory()
        refreshLabels()
        guard let screenIndex = activeScreenIndex else { return }
        if chipViews.count != (capture?.annotations.count ?? 0) {
            rebuildChips(on: slots[screenIndex])
        } else {
            repositionChips()
        }
        updateContextNoteAffordance(annotation: canvasView?.selectedAnnotation)
        syncAppearance()
    }

    /// Port of `RefreshLabels` (`:436-450`).
    func refreshLabels() {
        guard let capture else { return }
        let labeled = CaptureLabels.forNotedAnnotations(captureLabel: capture.displayLabel, capture: capture.toCore())
        let labelById = Dictionary(uniqueKeysWithValues: labeled.map { ($0.annotation.id, $0.displayLabel) })
        for annotation in capture.annotations {
            annotation.label = labelById[annotation.id] ?? ""
            if let chip = chipViews[annotation.id] {
                chip.badgeLabel = provisionalBadgeText(for: annotation)
            }
        }
        canvasView?.needsDisplay = true
    }

    private func provisionalBadgeText(for annotation: EditorAnnotation) -> String {
        guard let capture else { return "" }
        guard !annotation.label.isEmpty else {
            let noteIndex = capture.annotations.prefix(while: { $0.id != annotation.id })
                .filter { !$0.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count + 1
            return "\(capture.displayLabel)\(noteIndex)"
        }
        return annotation.label
    }

    // MARK: - Annotation comment chips (SPEC §1.4)

    /// Port of `RebuildChips` (`:382-389`).
    func rebuildChips(on slot: OverlayScreenSlot) {
        for chip in chipViews.values { chip.removeFromSuperview() }
        chipViews.removeAll()
        guard let capture else { return }
        let liveIds = Set(capture.annotations.map(\.id))
        visibleChipIds.formIntersection(liveIds)
        for annotation in capture.annotations where visibleChipIds.contains(annotation.id) {
            addChip(for: annotation, focus: false)
        }
    }

    /// Port of `AddChip` (`:391-434`).
    func addChip(for annotation: EditorAnnotation, focus: Bool) {
        guard let screenIndex = activeScreenIndex else { return }
        let chip = CommentChipView(annotationId: annotation.id, badgeLabel: provisionalBadgeText(for: annotation), note: annotation.note)
        chip.onNoteChanged = { [weak self, weak annotation] text in
            guard let self, let annotation, !self.settingUp else { return }
            annotation.note = text
            self.refreshLabels()
            // Finding 12: matches the shot-note chip's own `onNoteChanged` below — typing a note
            // does not push an undo step (SPEC §1.5: "Изменение текста заметки историю не
            // пушит"), but it must still clear redo and refresh the undo/redo-button baseline so a
            // later undo doesn't resurrect a stale redo entry.
            self.history.clearRedo()
            self.lastSnapshot = self.snapshotState()
            self.refreshUndoRedoButtons()
        }
        chip.onCloseClicked = { [weak self, weak annotation] in
            guard let self, let annotation else { return }
            self.deleteAnnotationNote(annotation)
        }
        chip.onFocusGained = { [weak self, weak annotation] in
            guard let annotation else { return }
            self?.canvasView?.selectAnnotation(id: annotation.id)
        }
        chip.onEscape = { [weak self] in
            guard let self else { return }
            self.window(for: screenIndex)?.makeFirstResponder(self.canvasView)
        }
        slots[screenIndex].contentView.addSubview(chip)
        chipViews[annotation.id] = chip
        positionChip(chip, for: annotation)
        refreshLabels()
        positionToolbar()
        if focus {
            DispatchQueue.main.async { chip.focusAndSelectAll() }
        }
    }

    /// Port of `RepositionChips` (`:452-457`).
    func repositionChips() {
        guard let capture else { return }
        for (id, chip) in chipViews {
            guard let annotation = capture.annotations.first(where: { $0.id == id }) else { continue }
            positionChip(chip, for: annotation)
        }
    }

    /// Port of `PositionChip` (`:459-470`).
    private func positionChip(_ chip: CommentChipView, for annotation: EditorAnnotation) {
        guard let canvasView, let screenIndex = activeScreenIndex else { return }
        let height = chip.preferredHeight()
        let bounds = canvasView.displayBounds(of: annotation)
        let work = cropMonitorWorkAreaLocal(screenIndex: screenIndex)
        let origin = EditorGeometry.positionChip(displayBounds: bounds, cropRect: cropRectLocal, work: work)
        chip.frame = CGRect(x: origin.x, y: origin.y, width: CommentChipView.width, height: height)
    }

    /// Port of `OnDeleteAnnotationNoteClick` (`:565-579`).
    private func deleteAnnotationNote(_ annotation: EditorAnnotation) {
        guard capture != nil else { return }
        if !annotation.note.isEmpty, let before = lastSnapshot { history.pushWithoutClearingRedo(before) }
        history.clearRedo()
        annotation.note = ""
        lastSnapshot = snapshotState()
        visibleChipIds.remove(annotation.id)
        chipViews[annotation.id]?.removeFromSuperview()
        chipViews[annotation.id] = nil
        refreshLabels()
        positionToolbar()
        updateContextNoteAffordance(annotation: annotation)
        refreshUndoRedoButtons()
    }

    // MARK: - Context "add comment" button (SPEC §1.4)

    /// Port of `UpdateContextNoteAffordance` (`:533-563`).
    func updateContextNoteAffordance(annotation: EditorAnnotation?) {
        guard let screenIndex = activeScreenIndex, capture != nil else {
            contextNoteButtonView?.isHidden = true
            return
        }
        let target = annotation ?? canvasView?.selectedAnnotation
        if let target, visibleChipIds.contains(target.id) {
            contextNoteButtonView?.isHidden = true
            return
        }

        ensureContextNoteButton(on: slots[screenIndex])
        guard let button = contextNoteButtonView else { return }
        let work = cropMonitorWorkAreaLocal(screenIndex: screenIndex)
        let bounds: CGRect? = target.flatMap { canvasView?.displayBounds(of: $0) }
        let origin = EditorGeometry.positionContextNoteButton(annotationBounds: bounds, cropRect: cropRectLocal, work: work)
        button.frame = CGRect(origin: origin, size: CGSize(width: 32, height: 32))
        button.isHidden = false
    }

    private func ensureContextNoteButton(on slot: OverlayScreenSlot) {
        guard contextNoteButtonView == nil else { return }
        let button = ContextNoteButtonView(frame: .zero)
        button.onClick = { [weak self] in self?.commentButtonClicked() }
        slot.contentView.addSubview(button)
        contextNoteButtonView = button
    }

    /// Port of `OnCommentClick` (`:513-531`).
    func commentButtonClicked() {
        guard capture != nil else { return }
        if let selected = canvasView?.selectedAnnotation {
            visibleChipIds.insert(selected.id)
            if let chip = chipViews[selected.id] {
                chip.focusAndSelectAll()
            } else {
                addChip(for: selected, focus: true)
            }
            contextNoteButtonView?.isHidden = true
            return
        }
        showShotNoteChip(focus: true)
        contextNoteButtonView?.isHidden = true
    }

    // MARK: - Whole-capture comment (SPEC §1.4 "Комментарий ко всему снимку")

    /// Port of `ShotNoteChip` becoming visible (`OnCommentClick`/`SetupEditor:244-246`).
    func showShotNoteChip(focus: Bool) {
        guard let capture, let screenIndex = activeScreenIndex else { return }
        if shotNoteChipView == nil {
            let chip = ShotNoteChipView(title: EditorStrings.captureLabelTitle(language, capture.displayLabel), note: capture.note)
            chip.onNoteChanged = { [weak self] text in
                guard let self, !self.settingUp else { return }
                self.capture?.note = text
                self.history.clearRedo()
                self.lastSnapshot = self.snapshotState()
                self.syncAppearance()
            }
            chip.onCloseClicked = { [weak self] in self?.closeShotNoteChip() }
            chip.onEscape = { [weak self] in
                guard let self else { return }
                self.window(for: screenIndex)?.makeFirstResponder(self.canvasView)
            }
            slots[screenIndex].contentView.addSubview(chip)
            shotNoteChipView = chip
        } else {
            settingUp = true
            shotNoteChipView?.title = EditorStrings.captureLabelTitle(language, capture.displayLabel)
            shotNoteChipView?.note = capture.note
            settingUp = false
        }
        positionShotNote()
        positionToolbar()
        if focus { shotNoteChipView?.focus() }
    }

    func hideShotNoteChip() {
        shotNoteChipView?.removeFromSuperview()
        shotNoteChipView = nil
    }

    /// Port of `OnCloseShotNoteClick` (`:581-596`).
    private func closeShotNoteChip() {
        guard let capture else { return }
        if !capture.note.isEmpty, let before = lastSnapshot { history.pushWithoutClearingRedo(before) }
        history.clearRedo()
        settingUp = true
        capture.note = ""
        settingUp = false
        lastSnapshot = snapshotState()
        hideShotNoteChip()
        positionToolbar()
        updateContextNoteAffordance(annotation: canvasView?.selectedAnnotation)
        window(for: activeScreenIndex ?? 0)?.makeFirstResponder(canvasView)
        refreshUndoRedoButtons()
    }

    /// Port of `PositionShotNote` (`:472-479`).
    private func positionShotNote() {
        guard let shotNoteChipView, let screenIndex = activeScreenIndex else { return }
        let work = cropMonitorWorkAreaLocal(screenIndex: screenIndex)
        let origin = EditorGeometry.positionShotNote(cropRect: cropRectLocal, work: work)
        let height = shotNoteChipView.preferredHeight()
        shotNoteChipView.frame = CGRect(x: origin.x, y: origin.y, width: ShotNoteChipView.width, height: height)
    }

    // MARK: - Toolbar positioning (SPEC §6.2 `PositionToolbar`)

    /// Port of `PositionToolbar` (`:481-511`).
    func positionToolbar() {
        guard let toolbarView, let screenIndex = activeScreenIndex else { return }
        let size = toolbarView.sizeToFitContent()
        let work = cropMonitorWorkAreaLocal(screenIndex: screenIndex)
        var obstacles: [CGRect] = chipViews.values.map { CGRect(x: $0.frame.minX, y: $0.frame.minY, width: max($0.frame.width, CommentChipView.width), height: max($0.frame.height, 40)) }
        if let shotNoteChipView {
            obstacles.append(CGRect(x: shotNoteChipView.frame.minX, y: shotNoteChipView.frame.minY, width: ShotNoteChipView.width, height: max(shotNoteChipView.frame.height, 60)))
        }
        let origin = EditorGeometry.positionToolbar(cropRect: cropRectLocal, work: work, toolbarSize: size, obstacles: obstacles)
        toolbarView.frame = CGRect(origin: origin, size: size)
    }

    // MARK: - Monitor work area (SPEC §1.4 `GetCropMonitorWorkArea`)

    /// Port of `GetCropMonitorWorkArea` (`:598-611`). AppKit's `NSScreen.visibleFrame` is
    /// directly the work-area equivalent of Windows' `Screen.WorkingArea` (menu bar/Dock
    /// excluded), so no pixel-scale reconstruction is needed here.
    func cropMonitorWorkAreaLocal(screenIndex: Int) -> CGRect {
        let visible = slots[screenIndex].screen.visibleFrame
        let topLeft = CGPoint(x: visible.minX, y: visible.maxY)
        let bottomRight = CGPoint(x: visible.maxX, y: visible.minY)
        let localTopLeft = localPoint(fromGlobal: ScreenGeometry.flipToTopLeft(topLeft), screenIndex: screenIndex)
        let localBottomRight = localPoint(fromGlobal: ScreenGeometry.flipToTopLeft(bottomRight), screenIndex: screenIndex)
        return CGRect(
            x: min(localTopLeft.x, localBottomRight.x), y: min(localTopLeft.y, localBottomRight.y),
            width: abs(localBottomRight.x - localTopLeft.x), height: abs(localBottomRight.y - localTopLeft.y))
    }
}
