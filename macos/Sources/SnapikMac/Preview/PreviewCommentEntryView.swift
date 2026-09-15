// Port of `CapturePreviewWindow.xaml:145-165` (comment card `DataTemplate`), SPEC-DELTA-2 §1.5,
// SPEC-DELTA-2B §D.
import AppKit

/// One comment card: label + relation row, delete button, multi-line note field. Height is
/// content-driven (`preferredHeight`), matching the note `TextBox`'s `MinHeight=54 MaxHeight=150`.
final class PreviewCommentEntryView: NSView {
    private let labelField = NSTextField(labelWithString: "")
    private let relationField = NSTextField(labelWithString: "")
    private let deleteButton = NSButton()
    private let scrollView = NSScrollView()
    let textView = EditorTextView(frame: .zero)

    private(set) var entryId: UUID?

    var onTextChanged: ((String) -> Void)?
    var onDelete: (() -> Void)?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(hex: "#202630").cgColor
        layer?.cornerRadius = 10

        labelField.textColor = NSColor(hex: "#7AB8FF")
        labelField.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        labelField.backgroundColor = .clear
        labelField.isBezeled = false
        labelField.isEditable = false
        labelField.lineBreakMode = .byClipping
        addSubview(labelField)

        relationField.textColor = NSColor(hex: "#8F9AAA")
        relationField.font = NSFont.systemFont(ofSize: 11)
        relationField.backgroundColor = .clear
        relationField.isBezeled = false
        relationField.isEditable = false
        relationField.lineBreakMode = .byTruncatingTail
        addSubview(relationField)

        deleteButton.isBordered = false
        deleteButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
        deleteButton.contentTintColor = NSColor(hex: "#BFC8D6")
        deleteButton.target = self
        deleteButton.action = #selector(deleteClicked)
        addSubview(deleteButton)

        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.textColor = NSColor(hex: "#EEF2F8")
        textView.backgroundColor = NSColor(hex: "#1C222B")
        textView.drawsBackground = true
        textView.insertionPointColor = NSColor(hex: "#7AB8FF")
        textView.selectedTextAttributes = [.backgroundColor: NSColor(hex: "#315CF5")]
        textView.textContainerInset = NSSize(width: 9, height: 7)
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.delegate = self
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(hex: "#1C222B")
        scrollView.wantsLayer = true
        scrollView.layer?.cornerRadius = 8
        scrollView.layer?.borderWidth = 1
        scrollView.layer?.borderColor = NSColor(hex: "#3A4451").cgColor
        addSubview(scrollView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func applyLocalization(language: String) {
        let tooltip = MacUiText.text("Удалить комментарий", language: language)
        deleteButton.toolTip = tooltip
        deleteButton.setAccessibilityLabel(tooltip)
    }

    /// Assigns row content. Only touches `textView.string` when it actually differs, so an
    /// in-progress edit (caret position, selection) is never clobbered by a `reload` triggered by
    /// this same keystroke.
    func configure(entryId: UUID, label: String, relation: String, text: String) {
        self.entryId = entryId
        labelField.stringValue = label
        relationField.stringValue = relation
        if textView.string != text { textView.string = text }
        needsLayout = true
    }

    /// Port of the `TextBox`'s `MinHeight=54 MaxHeight=150`, driven by the text view's used rect
    /// instead of a WPF auto-size pass.
    func preferredHeight() -> CGFloat {
        guard let container = textView.textContainer, let layoutManager = textView.layoutManager else { return 9 + 16 + 7 + 54 + 9 }
        layoutManager.ensureLayout(for: container)
        let used = layoutManager.usedRect(for: container).height + textView.textContainerInset.height * 2
        let noteHeight = min(max(used, 54), 150)
        return 9 + 16 + 7 + noteHeight + 9
    }

    override func layout() {
        super.layout()
        let padding: CGFloat = 9
        let deleteSize: CGFloat = 28
        labelField.sizeToFit()
        labelField.frame = CGRect(x: padding, y: padding, width: labelField.frame.width, height: 15)
        let relationX = labelField.frame.maxX + 6
        relationField.frame = CGRect(
            x: relationX, y: padding, width: max(0, bounds.width - padding - deleteSize - relationX), height: 15)
        deleteButton.frame = CGRect(x: bounds.width - deleteSize - 5, y: -5, width: deleteSize, height: deleteSize)

        let noteY = padding + 16 + 7
        let noteHeight = max(0, bounds.height - noteY - padding)
        scrollView.frame = CGRect(x: 0, y: noteY, width: bounds.width, height: noteHeight)
        textView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: noteHeight)
    }

    func focusTextEnd() {
        window?.makeFirstResponder(textView)
        let length = (textView.string as NSString).length
        textView.setSelectedRange(NSRange(location: length, length: 0))
    }

    @objc private func deleteClicked() { onDelete?() }
}

extension PreviewCommentEntryView: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        onTextChanged?(textView.string)
    }
}
