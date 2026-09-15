// Port of `src/Snapik.App/OverlayEditorWindow.Text.cs`, SPEC-DELTA-3 §1.4 E-6.
import AppKit
import SnapikCore

/// The field a caption is typed in, standing exactly where the letters will be drawn and in the size
/// they will be drawn in. Enter finishes it, Shift+Enter breaks the line inside it, Escape gives it
/// up — the three keys `NSTextView` does not hand over by itself.
final class EditorCaptionTextView: NSTextView {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?
    var onFocusLost: (() -> Void)?

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { onFocusLost?() }
        return result
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == Keycode.escape, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
            onCancel?()
            return
        }
        if event.keyCode == Keycode.enter || event.keyCode == Keycode.enterAlternate {
            if event.modifierFlags.contains(.shift) {
                insertNewline(nil)
            } else {
                onCommit?()
            }
            return
        }
        super.keyDown(with: event)
    }
}

@MainActor
extension OverlayEditorController {
    var isEditingText: Bool { editingTextAnnotation != nil }

    /// Port of `BeginTextEdit` (`Text.cs:47-73`). The word a caption starts with is selected whole:
    /// typing replaces it, a click inside it does not.
    func beginTextEdit(_ annotation: EditorAnnotation, selectAll: Bool, isNew: Bool) {
        guard capture != nil, annotation.kind == .text, let canvasView, let screenIndex = activeScreenIndex else { return }
        if let current = editingTextAnnotation, current !== annotation { commitTextEdit() }

        editingTextAnnotation = annotation
        editingTextIsNew = isNew
        editingTextBefore = annotation.text
        editingTextUndoDepth = history.undoDepth
        // A caption just placed already has an entry of its own, pushed where it was created.
        textEditBefore = isNew ? nil : snapshotState()

        canvasView.editingTextId = annotation.id
        canvasView.selectAnnotation(id: annotation.id)

        let field = textEditorView ?? makeTextEditor(on: slots[screenIndex])
        settingUp = true
        field.string = annotation.text
        settingUp = false
        field.isHidden = false
        resizeTextEditor()
        if selectAll {
            field.selectAll(nil)
        } else {
            field.setSelectedRange(NSRange(location: field.string.count, length: 0))
        }
        canvasView.needsDisplay = true
        window(for: screenIndex)?.makeFirstResponder(field)
    }

    private func makeTextEditor(on slot: OverlayScreenSlot) -> EditorCaptionTextView {
        let field = EditorCaptionTextView(frame: NSRect(x: 0, y: 0, width: 120, height: 30))
        field.isEditable = true
        field.isSelectable = true
        field.isRichText = false
        field.drawsBackground = false
        field.backgroundColor = .clear
        field.insertionPointColor = .white
        field.selectedTextAttributes = [.backgroundColor: AccentPalette.wash(alpha: 0.35)]
        field.textContainerInset = .zero
        field.textContainer?.lineFragmentPadding = 0
        field.textContainer?.widthTracksTextView = false
        field.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        field.isHorizontallyResizable = true
        field.isVerticallyResizable = true
        let proxy = CaptionTextDelegateProxy(controller: self)
        captionTextDelegate = proxy
        field.delegate = proxy
        field.onCommit = { [weak self] in self?.commitTextEdit() }
        field.onCancel = { [weak self] in self?.cancelTextEdit() }
        field.onFocusLost = { [weak self] in
            // A press somewhere else finishes the caption, the way clicking away from it does
            // everywhere. Deferred by one turn so a click that lands on another editor control does
            // not race the commit.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.editingTextAnnotation != nil else { return }
                if self.textEditorView?.window?.firstResponder !== self.textEditorView { self.commitTextEdit() }
            }
        }
        slot.contentView.addSubview(field)
        textEditorView = field
        return field
    }

    /// Port of `ResizeTextEditor` (`Text.cs:77-86`): the capture is shown scaled, so both the place
    /// and the size of the letters follow the crop rectangle.
    func resizeTextEditor() {
        guard let annotation = editingTextAnnotation, let capture, let field = textEditorView,
            cropRectLocal.width > 0, let anchor = annotation.points.first
        else { return }
        let scale = cropRectLocal.width / CGFloat(max(1, capture.image.width))
        let size = max(1, CGFloat(TextMarkMetrics.clamp(annotation.fontSize)) * scale)
        field.font = EditorTheme.systemFont(size)
        field.textColor = annotation.color
        let measured = TextMarkMetrics.measure(annotation.text, fontSize: annotation.fontSize)
        field.frame = CGRect(
            x: cropRectLocal.minX + anchor.x * scale, y: cropRectLocal.minY + anchor.y * scale,
            width: max(24, CGFloat(measured.width) * scale + size), height: max(size, CGFloat(measured.height) * scale))
    }

    /// Port of `CommitTextEdit` (`Text.cs:97-121`).
    func commitTextEdit() {
        guard let annotation = editingTextAnnotation, !closingTextEdit else { return }
        closingTextEdit = true
        defer { closingTextEdit = false }

        let before = textEditBefore
        let rewritten = annotation.text != editingTextBefore
        closeTextEditor()
        // A caption with nothing in it is not a caption: leaving it would drop an invisible mark on
        // the capture, and there would be no way to find it again.
        if annotation.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            dropTextMark(annotation)
        } else if capture != nil {
            // Retyping a caption is one entry of the history, made here and not per keystroke.
            if let before, rewritten {
                history.pushWithoutClearingRedo(before)
                history.clearRedo()
            }
            lastSnapshot = snapshotState()
            refreshLabels()
        }
        window(for: activeScreenIndex ?? 0)?.makeFirstResponder(canvasView)
        refreshUndoRedoButtons()
    }

    /// Port of `CancelTextEdit` (`Text.cs:123-141`).
    func cancelTextEdit() {
        guard let annotation = editingTextAnnotation, !closingTextEdit else { return }
        closingTextEdit = true
        defer { closingTextEdit = false }

        closeTextEditor()
        if editingTextIsNew || editingTextBefore.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            dropTextMark(annotation)
        } else {
            annotation.text = editingTextBefore
            canvasView?.fitTextMark(annotation)
            if capture != nil { lastSnapshot = snapshotState() }
            refreshLabels()
        }
        window(for: activeScreenIndex ?? 0)?.makeFirstResponder(canvasView)
        refreshUndoRedoButtons()
    }

    private func closeTextEditor() {
        editingTextAnnotation = nil
        textEditBefore = nil
        canvasView?.editingTextId = nil
        textEditorView?.isHidden = true
        canvasView?.needsDisplay = true
    }

    /// Port of `DropTextMark` (`Text.cs:153-163`): a caption that was given up leaves the capture,
    /// and one that was only just placed takes the history entry of its own placement with it, so one
    /// Escape leaves nothing behind.
    private func dropTextMark(_ annotation: EditorAnnotation) {
        guard let capture else { return }
        if canvasView?.selectedAnnotation === annotation { canvasView?.selectAnnotation(id: nil) }
        capture.annotations.removeAll(where: { $0 === annotation })
        if editingTextIsNew, history.undoDepth > 0, history.undoDepth == editingTextUndoDepth {
            history.popUndo()
        }
        visibleChipIds.remove(annotation.id)
        lastSnapshot = snapshotState()
        refreshLabels()
        syncAppearance()
    }
}

/// `NSTextViewDelegate` descends from `NSObjectProtocol`, and the controller is a plain Swift
/// class, so the delegate is a small forwarder — the same reasoning as
/// `AppearancePopoverDelegateProxy`.
@MainActor
final class CaptionTextDelegateProxy: NSObject, NSTextViewDelegate {
    weak var controller: OverlayEditorController?

    init(controller: OverlayEditorController) {
        self.controller = controller
    }

    /// Port of `OnTextEditorChanged` (`Text.cs:88-95`): the letters travel into the mark on every
    /// keystroke, and the box of the mark is refitted to them.
    func textDidChange(_ notification: Notification) {
        controller?.captionTextDidChange()
    }
}

@MainActor
extension OverlayEditorController {
    func captionTextDidChange() {
        guard !settingUp, let annotation = editingTextAnnotation, let field = textEditorView else { return }
        annotation.text = field.string
        canvasView?.fitTextMark(annotation)
        resizeTextEditor()
        canvasView?.needsDisplay = true
    }
}
