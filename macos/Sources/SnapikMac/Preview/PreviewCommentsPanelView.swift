// Port of `CapturePreviewWindow.xaml:121-170` (comments column) and `.xaml.cs:149-169`
// (scroll-to-new-row focus), SPEC-DELTA-2 §1.5, SPEC-DELTA-2B §D.
import AppKit

/// Flipped host so rows stack top-to-bottom in array order without extra Y-axis math (matches
/// `FlippedView` in `Stack/EdgeStackContentView.swift`).
final class PreviewCommentsFlippedContainer: NSView {
    override var isFlipped: Bool { true }
}

/// Fixed-width (292) column: header ("Комментарии" + add button), scrollable card list, empty
/// state.
final class PreviewCommentsPanelView: NSView {
    static let width: CGFloat = 292

    private let titleLabel = NSTextField(labelWithString: "")
    private let addButton = NSButton()
    private let scrollView = NSScrollView()
    private let listContainer = PreviewCommentsFlippedContainer()
    private let emptyLabel = NSTextField(wrappingLabelWithString: "")

    private var rowViews: [UUID: PreviewCommentEntryView] = [:]
    private var order: [UUID] = []
    private var currentLanguage = "ru"

    var onAddComment: (() -> Void)?
    var onTextChanged: ((UUID, String) -> Void)?
    var onDelete: ((UUID) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(hex: "#171B22").cgColor
        layer?.cornerRadius = 10

        titleLabel.textColor = NSColor(hex: "#EEF2F8")
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.backgroundColor = .clear
        titleLabel.isBezeled = false
        titleLabel.isEditable = false
        addSubview(titleLabel)

        addButton.isBordered = false
        addButton.wantsLayer = true
        addButton.layer?.backgroundColor = NSColor(hex: "#242A33").cgColor
        addButton.layer?.borderColor = NSColor(hex: "#3A4451").cgColor
        addButton.layer?.borderWidth = 1
        addButton.layer?.cornerRadius = 8
        addButton.image = NSImage(systemSymbolName: "plus.bubble", accessibilityDescription: nil)
        addButton.contentTintColor = NSColor(hex: "#DCE3ED")
        addButton.target = self
        addButton.action = #selector(addClicked)
        addSubview(addButton)

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.documentView = listContainer
        addSubview(scrollView)

        emptyLabel.textColor = NSColor(hex: "#8F9AAA")
        emptyLabel.backgroundColor = .clear
        emptyLabel.isBezeled = false
        emptyLabel.isEditable = false
        emptyLabel.isSelectable = false
        addSubview(emptyLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func applyLocalization(language: String) {
        currentLanguage = language
        titleLabel.stringValue = MacUiText.text("Комментарии", language: language)
        let tooltip = MacUiText.text("Добавить комментарий", language: language)
        addButton.toolTip = tooltip
        addButton.setAccessibilityLabel(tooltip)
        emptyLabel.stringValue = MacUiText.text("Нет комментариев", language: language)
        for view in rowViews.values { view.applyLocalization(language: language) }
    }

    /// Port of `RebuildComments` feeding the `ListBox`: pools row views by `PreviewCommentEntry.id`
    /// so an in-progress text edit in an untouched row survives a reload triggered by editing a
    /// different row.
    func reload(entries: [PreviewCommentEntry]) {
        let newIds = Set(entries.map(\.id))
        for (id, view) in rowViews where !newIds.contains(id) {
            view.removeFromSuperview()
            rowViews.removeValue(forKey: id)
        }
        order = entries.map(\.id)
        for entry in entries {
            let view: PreviewCommentEntryView
            if let existing = rowViews[entry.id] {
                view = existing
            } else {
                let created = PreviewCommentEntryView(frame: .zero)
                created.applyLocalization(language: currentLanguage)
                created.onTextChanged = { [weak self] text in self?.onTextChanged?(entry.id, text) }
                created.onDelete = { [weak self] in self?.onDelete?(entry.id) }
                listContainer.addSubview(created)
                rowViews[entry.id] = created
                view = created
            }
            view.configure(entryId: entry.id, label: entry.label, relation: entry.relation, text: entry.text)
        }
        emptyLabel.isHidden = !entries.isEmpty
        needsLayout = true
    }

    /// Port of the post-`OnAddCommentClick` `Dispatcher.BeginInvoke` block: scroll the newest row
    /// into view and put the caret at the end of its (empty) note field.
    func scrollToLastAndFocus() {
        guard let lastId = order.last, let view = rowViews[lastId] else { return }
        layoutRows()
        scrollView.contentView.scrollToVisible(view.frame)
        view.focusTextEnd()
    }

    override func layout() {
        super.layout()
        let padding: CGFloat = 12
        titleLabel.frame = CGRect(x: padding, y: padding, width: bounds.width - padding * 2 - 40, height: 18)
        addButton.frame = CGRect(x: bounds.width - padding - 32, y: padding - 4, width: 32, height: 32)
        let listTop = padding + 22
        scrollView.frame = CGRect(x: 0, y: listTop, width: bounds.width, height: max(0, bounds.height - listTop - padding))
        emptyLabel.frame = CGRect(x: padding, y: listTop + 4, width: bounds.width - padding * 2, height: 40)
        layoutRows()
    }

    private func layoutRows() {
        var y: CGFloat = 0
        let width = scrollView.bounds.width
        for id in order {
            guard let view = rowViews[id] else { continue }
            let height = view.preferredHeight()
            view.frame = CGRect(x: 0, y: y, width: width, height: height)
            y += height + 9
        }
        listContainer.frame = CGRect(x: 0, y: 0, width: width, height: max(y, scrollView.bounds.height))
    }

    @objc private func addClicked() { onAddComment?() }
}
