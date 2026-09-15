// Port of `RefreshLabels`, `AddChip`/`RebuildChips`/`RepositionChips`, `FindChipPlacement`,
// `MoveLinkedComments`, the chip expand/collapse machinery, and the one-shot Comment tool
// (`OverlayEditorWindow.xaml.cs:339-621`, `OverlayEditorWindow.Comments.cs`), SPEC-DELTA-2.md
// §1.3, SPEC-DELTA-2B.md §C7. Replaces the pre-sync "shot note chip" / "context note button"
// affordances entirely: a whole-capture comment is now just a pin with `parentAnnotationId == nil`.
import AppKit
import SnapikCore

@MainActor
extension OverlayEditorController {
    // MARK: - Canvas event handlers (SPEC-DELTA-2.md §1.3)

    /// Port of `OnAnnotationCreated` (`:339-352`, updated for Comment).
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
            selectTool(.select)
        }

        pushHistory()
        refreshLabels()

        if annotation.kind == .rectangle || annotation.kind == .text || annotation.kind == .comment {
            visibleChipIds.insert(annotation.id)
            addChip(for: annotation, focus: true)
        }
    }

    /// Port of `OnSelectionChanged` (`:354-359`); the C# guard on a pressed mouse button doesn't
    /// apply here (selection changes on mouse-down happen synchronously before any drag begins).
    func selectionChanged(_ annotation: EditorAnnotation?) {
        syncAppearance()
        repositionChips()
    }

    /// Port of `OnAnnotationChanged` (`:361-368`), now moving linked comments first (SPEC-DELTA-2.md
    /// §1.3 "`MoveLinkedComments`, из `OnAnnotationChanged`").
    func annotationChanged() {
        moveLinkedComments()
        pushHistory()
        refreshLabels()
        guard let screenIndex = activeScreenIndex else { return }
        // Detects the "annotation deleted via the Delete key" case (`AnnotationCanvasView
        // .keyDown` mutates `capture.annotations` directly and only calls `onAnnotationChanged`)
        // by looking for a chip whose annotation no longer exists, and purges it via a full
        // rebuild; otherwise a plain reposition is enough.
        let liveIds = Set(capture?.annotations.map(\.id) ?? [])
        if chipViews.keys.contains(where: { !liveIds.contains($0) }) {
            rebuildChips(on: slots[screenIndex])
        } else {
            repositionChips()
        }
        syncAppearance()
    }

    /// Port of `RefreshLabels` (`:436-450`, SPEC-DELTA-2.md §1.3): every annotation's badge shows
    /// its real note-derived label if it has one, else a placeholder — `"T"` for Text, `"+"` for
    /// everything else (including a Comment pin, whose badge is its only on-canvas marker).
    func refreshLabels() {
        guard let capture else { return }
        let labeled = CaptureLabels.forNotedAnnotations(captureLabel: capture.displayLabel, capture: capture.toCore())
        let labelById = Dictionary(uniqueKeysWithValues: labeled.map { ($0.annotation.id, $0.displayLabel) })
        for annotation in capture.annotations {
            let real = labelById[annotation.id]
            annotation.label = real ?? (annotation.kind == .text ? EditorStrings.textPlaceholderBadge : EditorStrings.commentPlaceholderBadge)
            if let chip = chipViews[annotation.id] {
                chip.badgeLabel = annotation.label
            }
        }
        canvasView?.needsDisplay = true
    }

    // MARK: - One-shot Comment tool (SPEC-DELTA-2.md §1.3 "One-shot")

    /// Port of `OnCommentClick` (`:513-531`): captures which annotation (if any) the new comment
    /// should link to, then arms the Comment tool. A single subsequent click anywhere places the
    /// pin (`AnnotationCanvasView.mouseDown`'s `.comment` branch) and returns to Select.
    func commentButtonClicked() {
        guard capture != nil else { return }
        let selected = canvasView?.selectedAnnotation
        commentParentId = selected?.kind == .comment ? selected?.parentAnnotationId : selected?.id
        selectTool(.comment)
    }

    // MARK: - Comment chips (SPEC-DELTA-2.md §1.3, SPEC-DELTA-2B.md §C7)

    /// Port of `RebuildChips` (`:382-389`).
    func rebuildChips(on slot: OverlayScreenSlot) {
        for chip in chipViews.values { chip.removeFromSuperview() }
        chipViews.removeAll()
        expandedChipId = nil
        guard let capture else { return }
        let liveIds = Set(capture.annotations.map(\.id))
        visibleChipIds.formIntersection(liveIds)
        for annotation in capture.annotations where visibleChipIds.contains(annotation.id) {
            addChip(for: annotation, focus: false)
        }
    }

    /// Port of `AddChip` (`:391-434`), now hosted in `chipLayerView` and wired for expand/collapse
    /// (SPEC-DELTA-2B.md §C7).
    func addChip(for annotation: EditorAnnotation, focus: Bool) {
        guard let screenIndex = activeScreenIndex, let chipLayerView else { return }
        let isTextTool = annotation.kind == .text
        let chip = CommentChipView(
            annotationId: annotation.id, badgeLabel: annotation.label,
            note: isTextTool ? annotation.text : annotation.note, isTextInput: isTextTool)

        chip.onNoteChanged = { [weak self, weak annotation] text in
            guard let self, let annotation, !self.settingUp else { return }
            if annotation.kind == .text { annotation.text = text } else { annotation.note = text }
            self.refreshLabels()
            // Typing a note does not push an undo step (SPEC §1.5: "Изменение текста заметки
            // историю не пушит"), but it must still clear redo and refresh the undo/redo baseline
            // so a later undo doesn't resurrect a stale redo entry.
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
            if !self.hasFocusedChip(otherThan: chip.annotationId) {
                self.expandChip(chip.annotationId, expanded: true)
            }
        }
        chip.onHoverExited = { [weak self, weak chip] in
            guard let self, let chip else { return }
            if !chip.isEditing { self.finishChip(chip.annotationId) }
        }
        chip.onBadgeClicked = { [weak self, weak annotation, weak chip] in
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

        chipLayerView.addSubview(chip)
        chipViews[annotation.id] = chip
        repositionChips()
        positionToolbar()
        if focus {
            expandChip(annotation.id, expanded: true)
            DispatchQueue.main.async { chip.focusAndSelectAll() }
        }
    }

    /// Port of `Expand`/`CollapseOtherChips` (SPEC-DELTA-2.md §1.3): collapses every other chip
    /// (skipping ones with keyboard focus), sets `expandedChipId`, re-lays every chip out, and
    /// resyncs the toolbar's obstacle list.
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

    /// Fix MEDIUM-1: z-order of chips isn't implied by document order alone — an expanded chip
    /// (and, failing that, a focused one) must draw and hit-test above its collapsed siblings, or
    /// an overlapping neighbor swallows its clicks. `ChipLayerView.hitTest` already walks
    /// `subviews.reversed()`, so the highest-priority chip must be the *last* subview.
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

    /// Port of `HasFocusedChipOtherThan` (`Comments.cs:13-14`).
    private func hasFocusedChip(otherThan id: SBGuid) -> Bool {
        chipViews.contains(where: { $0.key != id && $0.value.isEditing })
    }

    /// Port of `Finish()` (`:523-546`): an empty, non-Text chip is discarded; for a Comment that
    /// also deletes the pin annotation itself (and deselects it). Otherwise the chip just collapses.
    func finishChip(_ id: SBGuid) {
        guard let chip = chipViews[id] else { return }
        // Fix LOW-4: the annotation may already be gone (e.g. deleted via the Delete key while
        // this chip still had focus) — discard the now-orphaned chip instead of silently no-op'ing.
        guard let capture, let annotation = capture.annotations.first(where: { $0.id == id }) else {
            chip.removeFromSuperview()
            chipViews[id] = nil
            if expandedChipId == id { expandedChipId = nil }
            repositionChips()
            positionToolbar()
            return
        }
        let noteEmpty = (annotation.kind == .text ? annotation.text : annotation.note).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if !chip.isTextInput, noteEmpty {
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

    /// Port of `OnDeleteAnnotationNoteClick` (`:565-579`, updated for Comment): a Comment pin's
    /// close button removes the whole annotation; every other kind just clears its note text. Not
    /// `private`: also called directly by `+SmokeTest.swift`'s `smokeRunNoteAffordanceProbe`.
    func deleteAnnotationNote(_ annotation: EditorAnnotation) {
        guard capture != nil else { return }
        let hadContent = !(annotation.kind == .text ? annotation.text : annotation.note).isEmpty
        if hadContent, let before = lastSnapshot { history.pushWithoutClearingRedo(before) }
        history.clearRedo()

        if annotation.kind == .comment {
            capture?.annotations.removeAll(where: { $0.id == annotation.id })
            if canvasView?.selectedAnnotation?.id == annotation.id {
                canvasView?.selectAnnotation(id: nil)
            }
        } else if annotation.kind != .text {
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

    /// Port of `RepositionChips` (`:452-457`, rewritten for SPEC-DELTA-2.md §1.3's expand/collapse
    /// layout): the expanded chip (if any) is placed first, the rest in annotation order; each
    /// chip's own preferred anchor is just below its annotation's display bounds
    /// (`crop.minX + bounds.minX`, `crop.minY + bounds.maxY + 8`), and `EditorGeometry
    /// .findChipPlacement` spirals it away from every chip already placed this pass.
    func repositionChips() {
        guard let capture, let screenIndex = activeScreenIndex, let canvasView else { return }
        let work = cropMonitorWorkAreaLocal(screenIndex: screenIndex)
        var occupied: [CGRect] = []

        let orderedIds = capture.annotations.map(\.id).filter { chipViews[$0] != nil }
        let ordered = orderedIds.sorted { lhs, rhs in
            (lhs == expandedChipId ? 0 : 1) < (rhs == expandedChipId ? 0 : 1)
        }

        for id in ordered {
            guard let chip = chipViews[id], let annotation = capture.annotations.first(where: { $0.id == id }) else { continue }
            let height: CGFloat = chip.isExpanded ? max(90, chip.preferredHeight()) : 40
            let size = CGSize(width: chip.width, height: height)
            let bounds = canvasView.displayBounds(of: annotation)
            let preferred = CGPoint(x: cropRectLocal.minX + bounds.minX, y: cropRectLocal.minY + bounds.maxY + 8)

            let rect: CGRect
            if chip.isExpanded, chip.frame.width == size.width, chip.frame.height == size.height, occupied.allSatisfy({ !$0.insetBy(dx: -6, dy: -6).intersects(chip.frame) }) {
                // An already-expanded chip keeps its current position (SPEC-DELTA-2.md §1.3
                // "раскрытый сохраняет текущую позицию") instead of jumping back to `preferred`.
                rect = chip.frame
            } else {
                rect = EditorGeometry.findChipPlacement(preferred: preferred, size: size, work: work, occupied: occupied)
            }
            chip.frame = rect
            occupied.append(rect)
        }
    }

    // MARK: - Linked comment movement (SPEC-DELTA-2.md §1.3 `MoveLinkedComments`)

    /// Port of `MoveLinkedComments` (`Comments.cs:77-95`): for every comment linked to an
    /// annotation, if the parent disappeared the link is cleared; otherwise, if the parent's
    /// bounds actually changed since `lastSnapshot`, the comment's own points are carried along via
    /// `EditorGeometry.linkedCommentPoints`.
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

    // MARK: - Click-outside dismissal (SPEC-DELTA-2B.md §C7)

    /// Wires one window's global `leftMouseDown` observation so a click outside the currently
    /// expanded chip collapses it (SPEC-DELTA-2.md §1.3 "Клик вне слоя чипов").
    func wireChipDismissal(_ window: OverlayWindow) {
        window.onLeftMouseDown = { [weak self, weak window] event in
            guard let self, let window, let expandedChipId, let chip = self.chipViews[expandedChipId] else { return }
            guard let contentView = window.contentView else { return }
            let point = contentView.convert(event.locationInWindow, from: nil)
            let hit = contentView.hitTest(point)
            if hit == nil || (hit !== chip && !(hit?.isDescendant(of: chip) ?? false)) {
                self.finishChip(expandedChipId)
            }
        }
    }

    // MARK: - Toolbar positioning (SPEC-DELTA-2B.md §C7)

    /// Port of `PositionToolbar` (`:481-511`), now driven by chip *frames* (270/43 wide) instead
    /// of the old fixed comment-chip width.
    func positionToolbar() {
        guard let toolbarView, let screenIndex = activeScreenIndex else { return }
        let size = toolbarView.sizeToFitContent()
        let work = cropMonitorWorkAreaLocal(screenIndex: screenIndex)
        let obstacles = chipViews.values.map { $0.frame }
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
