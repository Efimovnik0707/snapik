// Port of `AddChip`/the comment chip's expand-collapse behavior (`OverlayEditorWindow.xaml.cs:
// 449-621`, `OverlayEditorWindow.Comments.cs`), SPEC-DELTA-2.md §1.3, SPEC-DELTA-2B.md §C7.
import AppKit
import SnapikCore

/// Small round badge (`A1`, `B2`, "+"/"T", ...) drawn directly rather than composited from an
/// `NSTextField` over a circular background view.
final class AnnotationBadgeView: NSView {
    var label: String = "" { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        EditorTheme.accent.setFill()
        NSBezierPath(ovalIn: bounds).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: EditorTheme.systemFont(11, weight: .bold), .foregroundColor: NSColor.white,
        ]
        let text = NSAttributedString(string: label, attributes: attributes)
        let size = text.size()
        text.draw(at: CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }
}

/// Port of the per-annotation comment chip (SPEC-DELTA-2.md §1.3 "Чипы"). A 25x25 number badge, a
/// growing multi-line note field (32...78pt) and a close button when **expanded** (270pt wide);
/// only the badge when **collapsed** (43pt wide). Created once per visible chip and never rebuilt
/// while typing (finding preserved from the pre-sync chip: keep focus/caret/IME state).
final class CommentChipView: NSView {
    static let expandedWidth: CGFloat = 270
    static let collapsedWidth: CGFloat = 43
    static let minHeight: CGFloat = 40
    private static let padding: CGFloat = 6
    private static let noteMinHeight: CGFloat = 32
    private static let noteMaxHeight: CGFloat = 78
    private static let badgeSize: CGFloat = 25
    private static let closeSize: CGFloat = 27

    let annotationId: SBGuid
    let isTextInput: Bool
    private let badge = AnnotationBadgeView(frame: .zero)
    private let scrollView = NSScrollView()
    let textView = EditorTextView(frame: .zero)
    private let closeButton: ChipCloseButtonView
    private var trackingArea: NSTrackingArea?

    private(set) var isExpanded = false
    private(set) var isHovered = false
    /// Port of `chip.isEditing` (SPEC-DELTA-2B.md §C7): the chip's own text field is the window's
    /// first responder right now.
    var isEditing: Bool { window?.firstResponder === textView }

    var onNoteChanged: ((String) -> Void)?
    var onCloseClicked: (() -> Void)?
    var onFocusGained: (() -> Void)?
    var onFocusLost: (() -> Void)?
    var onHoverEntered: (() -> Void)?
    var onHoverExited: (() -> Void)?
    var onBadgeClicked: (() -> Void)?
    /// Enter without modifiers inside the text field (SPEC-DELTA-2.md §1.3 "`PreviewKeyDown`
    /// Enter без модификаторов = `Finish()`"); Shift+Enter is a plain newline, handled by the
    /// text view itself and never reaches this closure.
    var onCommit: (() -> Void)?
    /// SPEC §7.5 point 2: plain Escape while this chip's field has focus moves focus back to the
    /// canvas (does not close the chip).
    var onEscape: (() -> Void)?

    var badgeLabel: String {
        get { badge.label }
        set { badge.label = newValue }
    }

    /// The chip's current target width (SPEC-DELTA-2.md §1.3: "ширина 270 раскрыт / 43 свёрнут").
    var width: CGFloat { isExpanded ? Self.expandedWidth : Self.collapsedWidth }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(annotationId: SBGuid, badgeLabel: String, note: String, isTextInput: Bool = false) {
        self.annotationId = annotationId
        self.isTextInput = isTextInput
        closeButton = ChipCloseButtonView(
            size: Self.closeSize,
            tooltip: isTextInput ? EditorStrings.closeTextInput("ru") : EditorStrings.removeComment("ru"))
        super.init(frame: CGRect(x: 0, y: 0, width: Self.collapsedWidth, height: Self.minHeight))

        badge.label = badgeLabel
        addSubview(badge)

        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = EditorTheme.systemFont(13)
        textView.textColor = .white
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.string = note
        textView.insertionPointColor = .white
        textView.selectedTextAttributes = [.backgroundColor: EditorTheme.accent]
        textView.textContainerInset = NSSize(width: 7, height: 5)
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.delegate = self
        textView.onEscape = { [weak self] in self?.onEscape?() }
        textView.onCommit = { [weak self] in self?.onCommit?() }
        // Fix MEDIUM-5: forward real first-responder transitions instead of relying on
        // `NSTextViewDelegate.textDidBeginEditing`/`textDidEndEditing` (see `EditorTextView`).
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

        updateSubviewVisibility()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Content-driven height, matching the WPF `TextBox`'s `MinHeight="32" MaxHeight="78"`
    /// auto-grow behavior, clamped and padded to the chip's own `MinHeight="40"`. Meaningless
    /// while collapsed (the caller uses a fixed 40pt collapsed height, SPEC-DELTA-2.md §1.3
    /// "RepositionChips": "размер (chip.width, expanded ? max(90, preferredHeight) : 40)").
    func preferredHeight() -> CGFloat {
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        let used = textView.layoutManager?.usedRect(for: textView.textContainer!).height ?? Self.noteMinHeight
        let noteHeight = min(max(used, Self.noteMinHeight), Self.noteMaxHeight)
        return max(Self.minHeight, noteHeight + Self.padding * 2)
    }

    /// Port of `chip.setExpanded` (SPEC-DELTA-2B.md §C7): only toggles this chip's own state and
    /// visibility; sizing/positioning is the controller's job (`repositionChips()`). A Text-chip
    /// hides entirely while collapsed (its content already renders directly on the canvas).
    func setExpanded(_ expanded: Bool) {
        isExpanded = expanded
        if isTextInput {
            isHidden = !expanded
        }
        updateSubviewVisibility()
        needsLayout = true
        needsDisplay = true
    }

    private func updateSubviewVisibility() {
        scrollView.isHidden = !isExpanded
        closeButton.isHidden = !isExpanded
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

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if badge.frame.contains(point) || !isExpanded {
            onBadgeClicked?()
        }
    }

    override func layout() {
        super.layout()
        let padding = Self.padding
        let contentHeight = bounds.height - padding * 2

        badge.frame = CGRect(x: padding, y: padding + (contentHeight - Self.badgeSize) / 2, width: Self.badgeSize, height: Self.badgeSize)
        guard isExpanded else { return }

        closeButton.frame = CGRect(
            x: bounds.width - padding - Self.closeSize, y: padding + (contentHeight - Self.closeSize) / 2,
            width: Self.closeSize, height: Self.closeSize)

        let noteX = padding + Self.badgeSize + 5
        let noteWidth = max(0, bounds.width - noteX - padding - Self.closeSize - 5)
        scrollView.frame = CGRect(x: noteX, y: padding, width: noteWidth, height: contentHeight)
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

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        false
    }
}
