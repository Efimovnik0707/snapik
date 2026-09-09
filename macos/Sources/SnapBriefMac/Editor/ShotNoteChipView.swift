// Port of `ShotNoteChip` (`OverlayEditorWindow.xaml:70-83`, `.xaml.cs:246,472-479,581-596,613-619`),
// SPEC §1.4 "Комментарий ко всему снимку".
import AppKit

/// The whole-capture comment chip. Fixed width 250, a title (`СНИМОК {label}` while editing,
/// SPEC §1.3 "Активный инструмент по умолчанию" setup step), a close button, and a note field
/// (34...92pt).
final class ShotNoteChipView: NSView {
    static let width: CGFloat = 250
    private static let padding: CGFloat = 8
    private static let noteMinHeight: CGFloat = 34
    private static let noteMaxHeight: CGFloat = 92
    private static let titleHeight: CGFloat = 16
    private static let closeSize: CGFloat = 25

    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = ChipCloseButtonView(size: ShotNoteChipView.closeSize, tooltip: EditorStrings.removeComment("ru"))
    private let scrollView = NSScrollView()
    let textView = EditorTextView(frame: .zero)

    var onNoteChanged: ((String) -> Void)?
    var onCloseClicked: (() -> Void)?
    /// SPEC §7.5 point 2, same as `CommentChipView.onEscape`.
    var onEscape: (() -> Void)?

    override var isFlipped: Bool { true }

    var title: String {
        get { titleLabel.stringValue }
        set { titleLabel.stringValue = newValue }
    }

    /// Setting this does not trigger `onNoteChanged` (mirrors `_settingUp` guarding
    /// `OnShotNoteChanged`, `OverlayEditorWindow.xaml.cs:615`).
    var note: String {
        get { textView.string }
        set { textView.string = newValue }
    }

    init(title: String, note: String) {
        super.init(frame: CGRect(x: 0, y: 0, width: Self.width, height: 100))

        titleLabel.stringValue = title
        titleLabel.font = EditorTheme.systemFont(11, weight: .semibold)
        titleLabel.textColor = EditorTheme.textSecondary9A
        titleLabel.backgroundColor = .clear
        titleLabel.isBezeled = false
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        addSubview(titleLabel)

        addSubview(closeButton)
        closeButton.onClick = { [weak self] in self?.onCloseClicked?() }

        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = EditorTheme.systemFont(13)
        textView.textColor = .white
        textView.backgroundColor = EditorTheme.shotNoteFieldBackground
        textView.drawsBackground = true
        textView.string = note
        textView.insertionPointColor = .white
        textView.selectedTextAttributes = [.backgroundColor: EditorTheme.accent]
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.delegate = self
        textView.onEscape = { [weak self] in self?.onEscape?() }

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .lineBorder
        scrollView.wantsLayer = false
        addSubview(scrollView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func preferredHeight() -> CGFloat {
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        let used = textView.layoutManager?.usedRect(for: textView.textContainer!).height ?? Self.noteMinHeight
        let noteHeight = min(max(used, Self.noteMinHeight), Self.noteMaxHeight)
        return Self.padding + Self.titleHeight + 5 + noteHeight + Self.padding
    }

    override func layout() {
        super.layout()
        let padding = Self.padding
        titleLabel.frame = CGRect(x: padding, y: padding, width: bounds.width - padding * 2 - Self.closeSize - 4, height: Self.titleHeight)
        closeButton.frame = CGRect(x: bounds.width - padding - Self.closeSize, y: padding - 4, width: Self.closeSize, height: Self.closeSize)

        let noteY = padding + Self.titleHeight + 5
        let noteHeight = max(0, bounds.height - noteY - padding)
        scrollView.frame = CGRect(x: padding, y: noteY, width: bounds.width - padding * 2, height: noteHeight)
        textView.frame = CGRect(x: 0, y: 0, width: bounds.width - padding * 2, height: noteHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: EditorTheme.shotNoteChipCornerRadius, yRadius: EditorTheme.shotNoteChipCornerRadius)
        EditorTheme.shotNoteChipBackground.setFill()
        path.fill()
    }

    func focus() {
        window?.makeFirstResponder(textView)
    }
}

extension ShotNoteChipView: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        onNoteChanged?(textView.string)
    }
}
