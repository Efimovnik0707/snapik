// Port of `RefreshLabels`, `AddChip`/`RebuildChips`/`RepositionChips`, the pill drag, the comments
// panel and the Comment tool (`OverlayEditorWindow.xaml.cs:1245-1560`,
// `OverlayEditorWindow.Comments.cs`), SPEC-DELTA-2.md §1.3, SPEC-DELTA-3 §1.4 E-7, E-9, E-12.
import AppKit
import SnapikCore

@MainActor
extension OverlayEditorController {
    // MARK: - Canvas event handlers

    /// Port of `OnAnnotationCreated` (`:339-352`, updated for the Comment tool and for a caption
    /// typed on the capture).
    func annotationCreated(_ annotation: EditorAnnotation) {
        guard capture != nil else { return }

        if annotation.kind == .comment {
            annotation.parentAnnotationId = commentParentId
            commentParentId = nil
            if let capture, let first = annotation.points.first {
                let width = CGFloat(capture.image.width)
                let height = CGFloat(capture.image.height)
                annotation.points = [first, CGPoint(x: min(width, first.x + 8), y: min(height, first.y + 8))]
            }
            // [ТЗ№4 D3] The Comment tool stays in the hand after the pin: it is put down by Escape,
            // by the Select button or by choosing another tool (`D-editor.md` §4.1).
        }

        pushHistory()
        refreshLabels()

        // A caption is typed on the capture itself now, not in a pill (SPEC-DELTA-3 §1.4 E-6).
        if annotation.kind == .text {
            beginTextEdit(annotation, selectAll: true, isNew: true)
            return
        }
        if annotation.kind == .comment {
            visibleChipIds.insert(annotation.id)
            addChip(for: annotation, focus: true)
        }
    }

    /// Port of `OnSelectionChanged` (`:354-359`).
    func selectionChanged(_ annotation: EditorAnnotation?) {
        syncAppearance()
        repositionChips()
        commentsPanelView?.highlight(annotation?.id)
    }

    /// Port of `OnAnnotationChanged` (`:1287-1296`).
    func annotationChanged() {
        moveLinkedComments()
        pushHistory()
        refreshLabels()
        guard let screenIndex = activeScreenIndex else { return }
        // Detects the "annotation deleted via the Delete key or the eraser" case by looking for a
        // chip whose annotation no longer exists, and purges it via a full rebuild.
        let liveIds = Set(capture?.annotations.map(\.id) ?? [])
        if chipViews.keys.contains(where: { !liveIds.contains($0) }) {
            rebuildChips(on: slots[screenIndex])
        } else {
            repositionChips()
        }
        syncAppearance()
    }

    /// Port of `AnnotationActivated` (`:203-208`): a double click opens the note of whatever it lands
    /// on — the editor of the letters for a caption, the pill for everything else.
    func annotationActivated(_ annotation: EditorAnnotation) {
        if annotation.kind == .text {
            beginTextEdit(annotation, selectAll: true, isNew: false)
            return
        }
        visibleChipIds.insert(annotation.id)
        if let chip = chipViews[annotation.id] {
            expandChip(annotation.id, expanded: true)
            chip.focusAndSelectAll()
        } else {
            addChip(for: annotation, focus: true)
        }
    }

    /// Port of `RefreshLabels` (`:1469-1480`): every annotation's badge shows its real note-derived
    /// label if it has one, else a placeholder — `"T"` for a caption, `"+"` for everything else.
    func refreshLabels() {
        guard let capture else { return }
        let labeled = CaptureLabels.forNotedAnnotations(captureLabel: capture.displayLabel, capture: capture.toCore())
        let labelById = Dictionary(uniqueKeysWithValues: labeled.map { ($0.annotation.id, $0.displayLabel) })
        for annotation in capture.annotations {
            let real = labelById[annotation.id]
            annotation.label = real ?? (annotation.kind == .text ? EditorStrings.textPlaceholderBadge : EditorStrings.commentPlaceholderBadge)
        }
        syncCommentsPanel()
        canvasView?.needsDisplay = true
    }

    // MARK: - The Comment tool (SPEC-DELTA-3 §1.4 E-9)

    /// Port of `OnCommentClick` (`:513-531`): captures which annotation (if any) the new comment
    /// should link to, then arms the Comment tool. [ТЗ№4 D3] the tool stays armed after the pin.
    func commentButtonClicked() {
        guard capture != nil else { return }
        let selected = canvasView?.selectedAnnotation
        commentParentId = selected?.kind == .comment ? selected?.parentAnnotationId : selected?.id
        selectTool(.comment)
    }

    // MARK: - Comment pills (E-7)

    /// Port of `RebuildChips` (`:1315-1327`).
    func rebuildChips(on slot: OverlayScreenSlot) {
        for chip in chipViews.values { chip.removeFromSuperview() }
        chipViews.removeAll()
        expandedChipId = nil
        guard let capture else { return }
        let liveIds = Set(capture.annotations.map(\.id))
        visibleChipIds.formIntersection(liveIds)
        // Every mark that already carries a note gets its pill back, so a reopened capture shows the
        // notes it was saved with.
        for annotation in capture.annotations where !annotation.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            visibleChipIds.insert(annotation.id)
        }
        for annotation in capture.annotations where visibleChipIds.contains(annotation.id) {
            addChip(for: annotation, focus: false)
        }
    }

    /// Port of `AddChip` (`:1331-1468`), now with the pill as its own drag handle and no number
    /// inside it (SPEC-DELTA-3 §1.4 E-7).
    func addChip(for annotation: EditorAnnotation, focus: Bool) {
        guard let screenIndex = activeScreenIndex, let chipLayerView else { return }
        let chip = CommentChipView(annotationId: annotation.id, note: annotation.note, language: language)

        chip.onNoteChanged = { [weak self, weak annotation] text in
            guard let self, let annotation, !self.settingUp else { return }
            annotation.note = text
            self.refreshLabels()
            // Typing a note does not push an undo step (SPEC §1.5), but it must still clear redo and
            // refresh the baseline so a later undo does not resurrect a stale redo entry.
            self.history.clearRedo()
            self.lastSnapshot = self.snapshotState()
            self.refreshUndoRedoButtons()
        }
        chip.onCloseClicked = { [weak self, weak annotation] in
            guard let self, let annotation else { return }
            self.deleteAnnotationNote(annotation)
        }
        chip.onFocusGained = { [weak self, weak annotation] in
            guard let self, let annotation else { return }
            self.canvasView?.selectAnnotation(id: annotation.id)
            self.expandChip(annotation.id, expanded: true)
        }
        chip.onFocusLost = { [weak self, weak chip] in
            guard let self, let chip else { return }
            DispatchQueue.main.async { [weak self, weak chip] in
                guard let self, let chip else { return }
                if !chip.isEditing, !chip.isHovered { self.finishChip(chip.annotationId) }
            }
        }
        chip.onHoverEntered = { [weak self, weak chip] in
            guard let self, let chip else { return }
            if self.chipDragAnnotation == nil, !self.hasFocusedChip(otherThan: chip.annotationId) {
                self.expandChip(chip.annotationId, expanded: true)
            }
        }
        chip.onHoverExited = { [weak self, weak chip] in
            guard let self, let chip else { return }
            if self.chipDragAnnotation == nil, !chip.isEditing { self.finishChip(chip.annotationId) }
        }
        chip.onClicked = { [weak self, weak annotation, weak chip] in
            guard let self, let annotation, let chip else { return }
            self.canvasView?.selectAnnotation(id: annotation.id)
            self.expandChip(annotation.id, expanded: true)
            chip.focusAndSelectAll()
        }
        chip.onCommit = { [weak self, weak chip] in
            guard let self, let chip else { return }
            self.finishChip(chip.annotationId)
            self.window(for: screenIndex)?.makeFirstResponder(self.canvasView)
        }
        chip.onEscape = { [weak self] in
            guard let self else { return }
            self.window(for: screenIndex)?.makeFirstResponder(self.canvasView)
        }
        chip.onDragBegan = { [weak self, weak annotation] in
            guard let self, let annotation else { return }
            self.beginNoteDrag(annotation)
        }
        chip.onDragged = { [weak self] delta in self?.dragNote(by: delta) }
        chip.onDragEnded = { [weak self] in self?.endNoteDrag() ?? false }

        chipLayerView.addSubview(chip)
        chipViews[annotation.id] = chip
        expandChip(annotation.id, expanded: focus)
        refreshLabels()
        if focus {
            DispatchQueue.main.async { chip.focusAndSelectAll() }
        }
    }

    /// Port of `Expand`/`CollapseOtherChips` (`:1387-1404`).
    func expandChip(_ id: SBGuid, expanded: Bool) {
        guard let chip = chipViews[id] else { return }
        if expanded {
            for (otherId, other) in chipViews where otherId != id && other.isExpanded {
                guard !other.isEditing else { continue }
                other.setExpanded(false)
            }
            expandedChipId = id
        } else if expandedChipId == id {
            expandedChipId = nil
        }
        chip.setExpanded(expanded)
        sortChipZOrder()
        repositionChips()
        positionToolbar()
    }

    /// An expanded pill (and, failing that, a focused one) must draw and hit-test above its siblings.
    /// `ChipLayerView.hitTest` walks `subviews.reversed()`, so the highest priority is last.
    private func sortChipZOrder() {
        guard let chipLayerView else { return }
        chipLayerView.sortSubviews(
            { a, b, _ in
                func key(_ view: NSView) -> Int {
                    guard let chip = view as? CommentChipView else { return 0 }
                    if chip.isExpanded { return 2 }
                    if chip.isEditing { return 1 }
                    return 0
                }
                let ka = key(a)
                let kb = key(b)
                if ka == kb { return .orderedSame }
                return ka < kb ? .orderedAscending : .orderedDescending
            }, context: nil)
    }

    /// Port of `HasFocusedChipOtherThan` (`Comments.cs:109-110`).
    private func hasFocusedChip(otherThan id: SBGuid) -> Bool {
        chipViews.contains(where: { $0.key != id && $0.value.isEditing })
    }

    /// Port of `Finish()` (`:1405-1428`): a pill with nothing in it is discarded, and for a Comment
    /// that also removes the pin itself. Otherwise the pill just collapses.
    func finishChip(_ id: SBGuid) {
        guard let chip = chipViews[id] else { return }
        // The annotation may already be gone (deleted with the Delete key or the eraser while this
        // pill still had focus): discard the now-orphaned pill instead of silently doing nothing.
        guard let capture, let annotation = capture.annotations.first(where: { $0.id == id }) else {
            chip.removeFromSuperview()
            chipViews[id] = nil
            if expandedChipId == id { expandedChipId = nil }
            repositionChips()
            positionToolbar()
            return
        }

        if annotation.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            visibleChipIds.remove(id)
            chip.removeFromSuperview()
            chipViews[id] = nil
            if expandedChipId == id { expandedChipId = nil }
            if annotation.kind == .comment {
                capture.annotations.removeAll(where: { $0.id == id })
                if canvasView?.selectedAnnotation?.id == id {
                    canvasView?.selectAnnotation(id: nil)
                }
                lastSnapshot = snapshotState()
            }
            refreshLabels()
            repositionChips()
            positionToolbar()
            refreshUndoRedoButtons()
        } else {
            expandChip(id, expanded: false)
        }
    }

    /// Port of `OnDeleteAnnotationNoteClick` (`:1565-1579`): a Comment pin's cross removes the whole
    /// annotation; every other kind just loses its note.
    func deleteAnnotationNote(_ annotation: EditorAnnotation) {
        guard capture != nil else { return }
        let hadContent = !annotation.note.isEmpty
        if hadContent, let before = lastSnapshot { history.pushWithoutClearingRedo(before) }
        history.clearRedo()

        if annotation.kind == .comment {
            capture?.annotations.removeAll(where: { $0.id == annotation.id })
            if canvasView?.selectedAnnotation?.id == annotation.id {
                canvasView?.selectAnnotation(id: nil)
            }
        } else {
            annotation.note = ""
        }

        lastSnapshot = snapshotState()
        visibleChipIds.remove(annotation.id)
        if expandedChipId == annotation.id { expandedChipId = nil }
        chipViews[annotation.id]?.removeFromSuperview()
        chipViews[annotation.id] = nil
        refreshLabels()
        positionToolbar()
        canvasView?.needsDisplay = true
        refreshUndoRedoButtons()
    }

    // MARK: - Dragging a pill (`BeginNoteDrag`/`DragNoteTo`/`EndNoteDrag`, `:1245-1277`)

    /// Dragging the pill of a note moves the badge of its mark with it, on screen and in the export.
    /// The offset is written straight to the model, so the whole drag becomes one history entry when
    /// the pill is let go.
    func beginNoteDrag(_ annotation: EditorAnnotation) {
        chipDragAnnotation = annotation
        chipDragOrigin = annotation.noteOffset
        chipDragMoved = false
    }

    func dragNote(by delta: CGPoint) {
        guard let annotation = chipDragAnnotation, let capture, cropRectLocal.width > 0, cropRectLocal.height > 0 else { return }
        chipDragMoved = true
        let origin = chipDragOrigin ?? .zero
        annotation.noteOffset = CGPoint(
            x: origin.x + delta.x * CGFloat(capture.image.width) / cropRectLocal.width,
            y: origin.y + delta.y * CGFloat(capture.image.height) / cropRectLocal.height)
        canvasView?.needsDisplay = true
        repositionChips()
    }

    @discardableResult
    func endNoteDrag() -> Bool {
        let moved = chipDragMoved
        chipDragAnnotation = nil
        chipDragMoved = false
        guard moved else { return false }
        pushHistory()
        repositionChips()
        positionToolbar()
        return true
    }

    /// Port of `RepositionChips` (`:1482-1560`): the expanded pill first, then the ones the user
    /// placed by hand, then the rest in annotation order.
    func repositionChips() {
        guard let capture, let screenIndex = activeScreenIndex, let canvasView else { return }
        let work = layoutWorkArea(screenIndex: screenIndex)
        var occupied: [CGRect] = []

        // Read out here and not inside the comparator: `sorted(by:)` takes a plain closure, and the
        // state of the controller cannot be reached from one.
        let expanded = expandedChipId
        let visible = capture.annotations.filter { chipViews[$0.id]?.isExpanded == true }
        let ranked: [(rank: Int, order: Int, annotation: EditorAnnotation)] = visible.enumerated().map { index, annotation in
            let rank = annotation.id == expanded ? 0 : (annotation.noteOffset != nil ? 1 : 2)
            return (rank, index, annotation)
        }
        let ordered = ranked
            .sorted { lhs, rhs in lhs.rank == rhs.rank ? lhs.order < rhs.order : lhs.rank < rhs.rank }
            .map(\.annotation)

        for annotation in ordered {
            guard let chip = chipViews[annotation.id] else { continue }
            let height = max(90, chip.preferredHeight())
            let size = CGSize(width: chip.width, height: height)

            let rect: CGRect
            if annotation.noteOffset != nil {
                // The pill used to be laid over the badge, its own badge exactly covering it. With
                // that badge gone it would cover the number of the mark instead, so it stands beside
                // the badge, and mirrors to the left of it when the right has no room left.
                let gap: CGFloat = 8
                let badge = canvasView.badgeCenter(of: annotation)
                let radius = canvasView.badgeRadius(of: annotation)
                var left = cropRectLocal.minX + badge.x + radius + gap
                if left + size.width > work.maxX { left = cropRectLocal.minX + badge.x - radius - gap - size.width }
                rect = clampChip(CGPoint(x: left, y: cropRectLocal.minY + badge.y - height / 2), size: size, work: work)
            } else {
                let bounds = canvasView.displayBounds(of: annotation)
                let preferred = CGPoint(x: cropRectLocal.minX + bounds.minX, y: cropRectLocal.minY + bounds.maxY + 8)
                rect = EditorGeometry.findChipPlacement(preferred: preferred, size: size, work: work, occupied: occupied)
            }
            chip.frame = rect
            occupied.append(rect)
        }
    }

    private func clampChip(_ point: CGPoint, size: CGSize, work: CGRect) -> CGRect {
        CGRect(
            x: EditorGeometry.clamp(point.x, work.minX + 8, max(work.minX + 8, work.maxX - size.width - 8)),
            y: EditorGeometry.clamp(point.y, work.minY + 8, max(work.minY + 8, work.maxY - size.height - 8)),
            width: size.width, height: size.height)
    }

    // MARK: - Linked comment movement (SPEC-DELTA-2.md §1.3 `MoveLinkedComments`)

    func moveLinkedComments() {
        guard let capture else { return }
        let before = lastSnapshot?.capture.annotations ?? []
        let beforeById = Dictionary(uniqueKeysWithValues: before.map { ($0.id, $0) })

        for annotation in capture.annotations {
            guard let parentId = annotation.parentAnnotationId else { continue }
            guard let parent = capture.annotations.first(where: { $0.id == parentId }) else {
                annotation.parentAnnotationId = nil
                continue
            }
            guard let beforeParent = beforeById[parentId] else { continue }
            let oldBounds = EditorGeometry.boundsOf(points: beforeParent.points, additionalSegments: beforeParent.additionalPathSegments)
            let newBounds = EditorGeometry.boundsOf(points: parent.points, additionalSegments: parent.additionalPathSegments)
            guard oldBounds != newBounds else { continue }

            let oldAnchor = beforeParent.points.first ?? .zero
            let newAnchor = parent.points.first ?? .zero
            let delta = CGPoint(x: newAnchor.x - oldAnchor.x, y: newAnchor.y - oldAnchor.y)
            let imageSize = CGSize(width: capture.image.width, height: capture.image.height)
            annotation.points = EditorGeometry.linkedCommentPoints(
                annotation.points, oldParent: oldBounds, newParent: newBounds, parentDelta: delta, imageSize: imageSize)
        }
    }

    // MARK: - Click-outside dismissal

    /// Wires one window's global `leftMouseDown` observation so a click outside the expanded pill
    /// collapses it, and a click outside a caption being typed finishes it.
    func wireChipDismissal(_ window: OverlayWindow) {
        window.onLeftMouseDown = { [weak self, weak window] event in
            guard let self, let window, let contentView = window.contentView else { return }
            let point = contentView.convert(event.locationInWindow, from: nil)
            let hit = contentView.hitTest(point)
            if let field = self.textEditorView, self.editingTextAnnotation != nil, hit !== field, !(hit?.isDescendant(of: field) ?? false) {
                self.commitTextEdit()
            }
            guard let expandedChipId, let chip = self.chipViews[expandedChipId] else { return }
            if hit == nil || (hit !== chip && !(hit?.isDescendant(of: chip) ?? false)) {
                self.finishChip(expandedChipId)
            }
        }
    }

    // MARK: - Comments panel (SPEC-DELTA-3 §1.4 E-12)

    /// Port of `CommentRows` (`Comments.cs:36-42`): every comment pin, even one still without text,
    /// and every mark that carries a note.
    func commentRows() -> [(id: SBGuid, label: String, text: String, relation: String)] {
        guard let capture else { return [] }
        return capture.annotations
            .filter { $0.kind == .comment || !$0.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { annotation in
                (annotation.id, annotation.label.isEmpty ? "+" : annotation.label, annotation.note, relation(of: annotation))
            }
    }

    private func relation(of annotation: EditorAnnotation) -> String {
        guard annotation.kind == .comment, let capture else { return "" }
        let parent = annotation.parentAnnotationId.flatMap { parentId in capture.annotations.first(where: { $0.id == parentId }) }
        if let parent, !parent.label.isEmpty {
            return "\(EditorStrings.text("К отметке", language: language)) \(parent.label)"
        }
        return "\(EditorStrings.text("К снимку", language: language)) \(capture.displayLabel)"
    }

    /// Port of `SyncCommentsPanel` (`Comments.cs:45-70`).
    func syncCommentsPanel() {
        guard let panel = commentsPanelView else { return }
        panel.setRows(commentRows()) { [weak self] id in self?.activateCommentRow(id) }
        panel.highlight(canvasView?.selectedAnnotation?.id)
    }

    /// Port of `ActivateCommentRow` (`Comments.cs:85-90`): a click on a row selects the mark on the
    /// capture and opens its pill, without taking the focus off the capture.
    private func activateCommentRow(_ annotationId: SBGuid) {
        canvasView?.selectAnnotation(id: annotationId)
        if chipViews[annotationId] != nil {
            expandChip(annotationId, expanded: true)
        } else if let annotation = capture?.annotations.first(where: { $0.id == annotationId }) {
            visibleChipIds.insert(annotationId)
            addChip(for: annotation, focus: false)
        }
        commentsPanelView?.highlight(annotationId)
    }

    /// Port of `PositionCommentsPanel` (`Comments.cs:25-32`): the panel stands at the right edge of
    /// the work area of the monitor the capture is on.
    func positionCommentsPanel() {
        guard let panel = commentsPanelView, let screenIndex = activeScreenIndex else { return }
        let work = cropMonitorWorkAreaLocal(screenIndex: screenIndex)
        panel.frame = CGRect(
            x: max(work.minX, work.maxX - CommentsPanelView.width - 8), y: work.minY + 8,
            width: CommentsPanelView.width, height: max(160, work.height - 16))
    }

    /// Port of `LayoutWorkArea`/`WithoutCommentsStrip` (`Comments.cs:17-23`): with the comments panel
    /// on screen, the markup is laid out in the monitor minus the strip that panel takes, so the
    /// capture never hides under it.
    func layoutWorkArea(screenIndex: Int) -> CGRect {
        let work = cropMonitorWorkAreaLocal(screenIndex: screenIndex)
        guard commentsPanelView != nil else { return work }
        return CGRect(
            x: work.minX, y: work.minY,
            width: max(240, work.width - CommentsPanelView.width - CommentsPanelView.gap), height: work.height)
    }

    // MARK: - Toolbar positioning

    /// Port of `PositionToolbar` (`:481-511`), driven by the pill frames as obstacles. The row is
    /// allowed the width of the work area, so a panel too wide for it wraps instead of running off
    /// the screen (SPEC-DELTA-3 §1.4 E-11).
    func positionToolbar() {
        guard let toolbarView, let screenIndex = activeScreenIndex else { return }
        let work = layoutWorkArea(screenIndex: screenIndex)
        toolbarView.maximumWidth = max(240, work.width - 16)
        let size = toolbarView.sizeToFitContent()
        let obstacles = chipViews.values.filter { !$0.isHidden }.map { $0.frame }
        let origin = EditorGeometry.positionToolbar(cropRect: cropRectLocal, work: work, toolbarSize: size, obstacles: obstacles)
        toolbarView.frame = CGRect(origin: origin, size: size)
    }

    // MARK: - Monitor work area (SPEC §1.4 `GetCropMonitorWorkArea`)

    /// Port of `GetCropMonitorWorkArea` (`:598-611`). AppKit's `NSScreen.visibleFrame` is directly
    /// the work-area equivalent of Windows' `Screen.WorkingArea` (menu bar/Dock excluded), so no
    /// pixel-scale reconstruction is needed here.
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
