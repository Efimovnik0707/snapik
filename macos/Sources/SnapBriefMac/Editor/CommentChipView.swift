// Port of `AddChip` (`OverlayEditorWindow.xaml.cs:391-434`), SPEC §1.4 "Чип комментария к отметке".
import AppKit
import SnapBriefCore

/// Small round badge (`A1`, `B2`, ...) drawn directly rather than composited from an `NSTextField`
/// over a circular background view.
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

/// Port of the per-annotation comment chip (SPEC §1.4). Fixed width 226, min height 40, a 25x25
/// number badge, a growing multi-line note field (32...78pt), and a close button that clears the
/// note without deleting the annotation. Created once per visible chip and never rebuilt while
/// typing (SPEC §1.4's `.impeccable` requirement to preserve focus/caret/IME state).
final class CommentChipView: NSView {
    static let width: CGFloat = 226
    static let minHeight: CGFloat = 40
    private static let padding: CGFloat = 6
    private static let noteMinHeight: CGFloat = 32
    private static let noteMaxHeight: CGFloat = 78
    private static let badgeSize: CGFloat = 25
    private static let closeSize: CGFloat = 27

    let annotationId: SBGuid
    private let badge = AnnotationBadgeView(frame: .zero)
    private let scrollView = NSScrollView()
    let textView = EditorTextView(frame: .zero)
    private let closeButton: ChipCloseButtonView

    var onNoteChanged: ((String) -> Void)?
    var onCloseClicked: (() -> Void)?
    var onFocusGained: (() -> Void)?
    /// SPEC §7.5 point 2: plain Escape while this chip's field has focus moves focus back to the
    /// canvas (does not close the chip).
    var onEscape: (() -> Void)?

    var badgeLabel: String {
        get { badge.label }
        set { badge.label = newValue }
    }

    override var isFlipped: Bool { true }

    init(annotationId: SBGuid, badgeLabel: String, note: String) {
        self.annotationId = annotationId
        closeButton = ChipCloseButtonView(size: Self.closeSize, tooltip: EditorStrings.removeComment("ru"))
        super.init(frame: CGRect(x: 0, y: 0, width: Self.width, height: Self.minHeight))

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

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        addSubview(scrollView)

        closeButton.onClick = { [weak self] in self?.onCloseClicked?() }
        addSubview(closeButton)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Content-driven height, matching the WPF `TextBox`'s `MinHeight="32" MaxHeight="78"`
    /// auto-grow behavior, clamped and padded to the chip's own `MinHeight="40"`.
    func preferredHeight() -> CGFloat {
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        let used = textView.layoutManager?.usedRect(for: textView.textContainer!).height ?? Self.noteMinHeight
        let noteHeight = min(max(used, Self.noteMinHeight), Self.noteMaxHeight)
        return max(Self.minHeight, noteHeight + Self.padding * 2)
    }

    override func layout() {
        super.layout()
        let padding = Self.padding
        let contentHeight = bounds.height - padding * 2

        badge.frame = CGRect(x: padding, y: padding + (contentHeight - Self.badgeSize) / 2, width: Self.badgeSize, height: Self.badgeSize)
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

    func textDidBeginEditing(_ notification: Notification) {
        onFocusGained?()
    }
}
