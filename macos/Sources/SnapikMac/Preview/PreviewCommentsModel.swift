// Port of `CapturePreviewWindow.xaml.cs:114-186` (`RebuildComments`, `RefreshCommentLabels`,
// `AnnotationName`, `OnAddCommentClick`, `DeleteComment`), SPEC-DELTA-2 §1.5, SPEC-DELTA-2B §D.
import Foundation
import SnapikCore

/// One row of the comments panel. `annotationId == nil` means "the whole-capture comment"
/// (`_capture.Note`); otherwise it points at an `AnnotationItem` (either `.comment` or any other
/// kind that carries a non-empty `note`).
struct PreviewCommentEntry: Equatable {
    let id: UUID
    var annotationId: SBGuid?
    var label: String
    var relation: String
    var text: String
}

/// Pure(ish) model behind the preview window's comments panel — no AppKit dependency, so it can
/// be driven directly from tests (`PreviewModelTests.swift`, `CapturePreviewProbe`) without a
/// window. Mutates `capture` in place; the window controller is responsible for re-rendering the
/// image and persisting after any mutating call.
@MainActor
final class PreviewCommentsModel {
    var capture: CaptureItem
    let displayLabel: String
    var language: String
    private(set) var entries: [PreviewCommentEntry] = []

    /// Stable per-annotation identity for `PreviewCommentEntry.id`, so a view layer diffing by
    /// `id` does not treat "same annotation, refreshed label" as a brand-new row.
    private var idsByAnnotation: [SBGuid: UUID] = [:]
    private var captureNoteEntryId: UUID?

    init(capture: CaptureItem, displayLabel: String, language: String) {
        self.capture = capture
        self.displayLabel = displayLabel
        self.language = language
    }

    /// Port of `RebuildComments`: capture-level comment first (if any), then every annotation
    /// that is a pin (`.comment`) or carries free text, in original annotation order.
    @discardableResult
    func rebuild() -> [PreviewCommentEntry] {
        var result: [PreviewCommentEntry] = []

        if ExportText.hasContent(capture.note) {
            let entryId = captureNoteEntryId ?? UUID()
            captureNoteEntryId = entryId
            result.append(
                PreviewCommentEntry(
                    id: entryId,
                    annotationId: nil,
                    label: displayLabel,
                    relation: MacUiText.text("Комментарий к снимку", language: language),
                    text: capture.note))
        } else {
            captureNoteEntryId = nil
        }

        for annotation in capture.annotations where annotation.kind == .comment || ExportText.hasContent(annotation.note) {
            let entryId = idsByAnnotation[annotation.id] ?? UUID()
            idsByAnnotation[annotation.id] = entryId
            let relation: String
            if let parentId = annotation.parentAnnotationId {
                relation = MacUiText.text("К отметке", language: language) + " " + annotationName(parentId)
            } else {
                relation = MacUiText.text("К снимку", language: language) + " " + displayLabel
            }
            result.append(
                PreviewCommentEntry(id: entryId, annotationId: annotation.id, label: "+", relation: relation, text: annotation.note))
        }

        let liveIds = Set(capture.annotations.map(\.id))
        idsByAnnotation = idsByAnnotation.filter { liveIds.contains($0.key) }
        entries = result
        refreshLabels()
        return entries
    }

    /// Port of `RefreshCommentLabels`: reassigns every entry's display label from
    /// `CaptureLabels.forNotedAnnotations` (source of truth for export numbering); an
    /// annotation-backed entry whose annotation currently has no text (so it did not claim a
    /// number) falls back to `"+"`.
    func refreshLabels() {
        let labeled = CaptureLabels.forNotedAnnotations(captureLabel: displayLabel, capture: capture)
        var labelsById: [SBGuid: String] = [:]
        for item in labeled { labelsById[item.annotation.id] = item.displayLabel }
        for index in entries.indices {
            if let annotationId = entries[index].annotationId {
                entries[index].label = labelsById[annotationId] ?? "+"
            } else {
                entries[index].label = displayLabel
            }
        }
    }

    /// Port of `AnnotationName`: the parent's export label if it currently has one, else
    /// `"{displayLabel}·{1-based index among non-comment annotations}"`.
    private func annotationName(_ id: SBGuid) -> String {
        guard capture.annotations.contains(where: { $0.id == id }) else { return "" }
        let labeled = CaptureLabels.forNotedAnnotations(captureLabel: displayLabel, capture: capture)
        if let match = labeled.first(where: { $0.annotation.id == id }) {
            return match.displayLabel
        }
        var index = 0
        for candidate in capture.annotations {
            if candidate.id == id { break }
            if candidate.kind != .comment { index += 1 }
        }
        return "\(displayLabel)·\(index + 1)"
    }

    /// Port of `OnAddCommentClick`: a fresh `.comment` pin anchored at the image center, second
    /// point offset by 8px (clamped into the image), empty note.
    @discardableResult
    func addComment() -> PreviewCommentEntry {
        let width = Double(capture.pixelWidth)
        let height = Double(capture.pixelHeight)
        let dx = width > 0 ? 8 / width : 0
        let dy = height > 0 ? 8 / height : 0
        let annotation = AnnotationItem(
            id: SBGuid(),
            kind: .comment,
            points: [NormalizedPoint(0.5, 0.5), NormalizedPoint(min(1, 0.5 + dx), min(1, 0.5 + dy))],
            strokeColor: "#FF2F8CFF",
            thickness: 3,
            text: "",
            note: "",
            parentAnnotationId: nil,
            arrowStyle: "straight")
        capture.annotations.append(annotation)
        rebuild()
        // `rebuild()` always appends the new pin last (annotation order), so `entries.last!` is
        // safe here — a `.comment` annotation is unconditionally included regardless of its
        // (empty) note.
        return entries.last!
    }

    /// Port of `DeleteComment`: a `.comment` pin is removed outright; any other annotation, or
    /// the whole-capture slot, just has its note cleared (the shape itself survives).
    func delete(_ entry: PreviewCommentEntry) {
        if let annotationId = entry.annotationId {
            if let index = capture.annotations.firstIndex(where: { $0.id == annotationId }) {
                if capture.annotations[index].kind == .comment {
                    capture.annotations.remove(at: index)
                } else {
                    capture.annotations[index].note = ""
                }
            }
        } else {
            capture.note = ""
        }
        rebuild()
    }

    /// Port of the `CommentEntry.Text` setter: writes through to the annotation note / capture
    /// note, then refreshes labels (numbering may change as text goes from empty to non-empty or
    /// back) without discarding row identity the way a full `rebuild()` would if called eagerly
    /// on every keystroke.
    func setText(_ text: String, for entry: PreviewCommentEntry) {
        if let annotationId = entry.annotationId {
            guard let index = capture.annotations.firstIndex(where: { $0.id == annotationId }) else { return }
            capture.annotations[index].note = text
        } else {
            capture.note = text
        }
        refreshLabels()
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index].text = text
        }
    }
}
