// Port of `AddChip` and the pill's expand/collapse behaviour (`OverlayEditorWindow.xaml.cs:
// 1330-1468`), SPEC-DELTA-2.md §1.3, SPEC-DELTA-3 §1.4 E-7.
import AppKit
import SnapikCore

/// The pill of a note: the text and the cross, and **no number** — the number of a comment is the
/// badge on the capture, and a second one inside the pill was the duplicate that was seen
/// (SPEC-DELTA-3 §1.4 E-7). The pill itself is the handle the note is dragged by; the text field and
/// the cross keep their own presses.
///
/// A collapsed pill is hidden outright: with the badge gone there is nothing left in it to show, and
/// the number on the capture stands for the note until the pill is opened again — by a double click
/// on the mark, by the row of the comments panel, or by hovering it.
final class CommentChipView: NSView {
    /// The pill lost the 26 pt its own badge took (`xaml.cs:1386`: `Width = 244`).
    static let expandedWidth: CGFloat = 244
    /// The width of the note field inside it (`Width = 200` on the grid).
    static let noteWidth: CGFloat = 200
    static let minHeight: CGFloat = 40
    private static let padding: CGFloat = 6
    private static let noteMinHeight: CGFloat = 32
    private static let noteMaxHeight: CGFloat = 78
    private static let closeSize: CGFloat = 27
    /// A press that travelled less than this is a click that opens the note, not a drag
    /// (`DragNoteTo`, `xaml.cs:1257`).
    private static let dragThreshold: CGFloat = 4

    let annotationId: SBGuid
    private let scrollView = NSScrollView()
    let textView = EditorTextView(frame: .zero)
    private let closeButton: ChipCloseButtonView
    private var trackingArea: NSTrackingArea?

    private(set) var isExpanded = false
    private(set) var isHovered = false
    /// The pill's own text field is the window's first responder right now.
    var isEditing: Bool { window?.firstResponder === textView }

    // Drag state (`BeginNoteDrag`/`DragNoteTo`/`EndNoteDrag`, `xaml.cs:1245-1277`).
    private var dragStartInWindow: CGPoint?
    private var dragMoved = false

    var onNoteChanged: ((String) -> Void)?
    var onCloseClicked: (() -> Void)?
    var onFocusGained: (() -> Void)?
    var onFocusLost: (() -> Void)?
    var onHoverEntered: (() -> Void)?
    var onHoverExited: (() -> Void)?
    /// A press that did not travel: it opens the note.
    var onClicked: (() -> Void)?
    /// Enter without modifiers inside the text field; Shift+Enter is a plain newline.
    var onCommit: (() -> Void)?
    /// Plain Escape while this pill's field has focus moves focus back to the canvas.
    var onEscape: (() -> Void)?
    /// The drag of the pill, in the coordinate space of the layer it lives in.
    var onDragBegan: (() -> Void)?
    var onDragged: ((CGPoint) -> Void)?
    /// `true` from the handler when the press really was a drag, so the click is not also delivered.
    var onDragEnded: (() -> Bool)?

    var width: CGFloat { Self.expandedWidth }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(annotationId: SBGuid, note: String, language: String) {
        self.annotationId = annotationId
        closeButton = ChipCloseButtonView(size: Self.closeSize, tooltip: EditorStrings.removeComment(language))
        super.init(frame: CGRect(x: 0, y: 0, width: Self.expandedWidth, height: Self.minHeight))
        // The pill is the handle now, and its tooltip is kept off the text field, or it would stand
        // over the words while they are being typed.
        toolTip = EditorStrings.addComment(language)

        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = EditorTheme.systemFont(13)
        textView.textColor = EditorTheme.textPrimary
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.string = note
        textView.insertionPointColor = EditorTheme.textPrimary
        textView.selectedTextAttributes = [.backgroundColor: AccentPalette.wash(alpha: 0.35)]
        textView.textContainerInset = NSSize(width: 7, height: 5)
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.delegate = self
        textView.onEscape = { [weak self] in self?.onEscape?() }
        textView.onCommit = { [weak self] in self?.onCommit?() }
        textView.onFocusGained = { [weak self] in self?.onFocusGained?() }
        textView.onFocusLost = { [weak self] in self?.onFocusLost?() }

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        addSubview(scrollView)

        closeButton.onClick = { [weak self] in self?.onCloseClicked?() }
        addSubview(closeButton)

        setExpanded(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var note: String {
        get { textView.string }
        set { textView.string = newValue }
    }

    /// Content-driven height, matching the WPF `TextBox`'s `MinHeight="32" MaxHeight="78"` auto-grow,
    /// clamped and padded to the pill's own `MinHeight="40"`.
    func preferredHeight() -> CGFloat {
        guard let container = textView.textContainer else { return Self.minHeight }
        textView.layoutManager?.ensureLayout(for: container)
        let used = textView.layoutManager?.usedRect(for: container).height ?? Self.noteMinHeight
        let noteHeight = min(max(used, Self.noteMinHeight), Self.noteMaxHeight)
        return max(Self.minHeight, noteHeight + Self.padding * 2)
    }

    func setExpanded(_ expanded: Bool) {
        isExpanded = expanded
        isHidden = !expanded
        needsLayout = true
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        onHoverEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        onHoverExited?()
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

    override func mouseDown(with event: NSEvent) {
        dragStartInWindow = event.locationInWindow
        dragMoved = false
        onDragBegan?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStartInWindow else { return }
        let delta = CGPoint(x: event.locationInWindow.x - start.x, y: event.locationInWindow.y - start.y)
        if !dragMoved, hypot(delta.x, delta.y) < Self.dragThreshold { return }
        dragMoved = true
        // The window's Y grows upward and the chip layer's grows downward, so the vertical part of
        // the travel is inverted once, here.
        onDragged?(CGPoint(x: delta.x, y: -delta.y))
    }

    override func mouseUp(with event: NSEvent) {
        dragStartInWindow = nil
        let dragged = onDragEnded?() ?? false
        dragMoved = false
        // A press that did not travel is still a click: it opens the note.
        if !dragged { onClicked?() }
    }

    override func layout() {
        super.layout()
        let padding = Self.padding
        let contentHeight = bounds.height - padding * 2
        closeButton.frame = CGRect(
            x: bounds.width - padding - Self.closeSize, y: padding + (contentHeight - Self.closeSize) / 2,
            width: Self.closeSize, height: Self.closeSize)
        let noteWidth = max(0, bounds.width - padding * 2 - Self.closeSize - 2)
        scrollView.frame = CGRect(x: padding, y: padding, width: noteWidth, height: contentHeight)
        textView.frame = CGRect(x: 0, y: 0, width: noteWidth, height: contentHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: EditorTheme.annotationChipCornerRadius, yRadius: EditorTheme.annotationChipCornerRadius)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.42)
        shadow.shadowBlurRadius = 14
        shadow.shadowOffset = NSSize(width: 0, height: -4)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        EditorTheme.annotationChipBackground.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    func focusAndSelectAll() {
        window?.makeFirstResponder(textView)
        textView.selectAll(nil)
    }
}

extension CommentChipView: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        onNoteChanged?(textView.string)
    }
}
