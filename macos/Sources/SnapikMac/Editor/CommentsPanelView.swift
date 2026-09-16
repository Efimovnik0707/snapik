// Port of `Controls/CommentListEntry.cs` and the `CommentsPanel` block of `OverlayEditorWindow.xaml`
// (`:179-189`), SPEC-DELTA-3 §1.4 E-12.
import AppKit
import SnapikCore

/// One row of the comments panel: the number of the note, its text and what it is attached to. Not a
/// button on purpose — a click here selects the mark on the capture without taking the focus away
/// from it.
final class CommentListEntryView: NSView {
    let annotationId: SBGuid
    private let badgeLabel = NSTextField(labelWithString: "")
    private let textLabel = NSTextField(labelWithString: "")
    private let relationLabel = NSTextField(labelWithString: "")
    private var isHovering = false { didSet { needsDisplay = true } }
    private var trackingArea: NSTrackingArea?

    /// The row of the note the hand is on takes the accent thinned down.
    var isCurrent = false { didSet { needsDisplay = true } }
    var onActivated: (() -> Void)?

    static let badgeSize: CGFloat = 25
    private static let padding = NSEdgeInsets(top: 6, left: 7, bottom: 6, right: 7)

    override var isFlipped: Bool { true }

    init(annotationId: SBGuid) {
        self.annotationId = annotationId
        super.init(frame: .zero)
        badgeLabel.font = EditorTheme.systemFont(11, weight: .bold)
        badgeLabel.textColor = .white
        badgeLabel.alignment = .center
        badgeLabel.backgroundColor = .clear
        badgeLabel.isBezeled = false
        badgeLabel.isEditable = false
        badgeLabel.isSelectable = false
        addSubview(badgeLabel)

        textLabel.font = EditorTheme.systemFont(12)
        textLabel.textColor = EditorTheme.textPrimary
        textLabel.backgroundColor = .clear
        textLabel.isBezeled = false
        textLabel.isEditable = false
        textLabel.isSelectable = false
        textLabel.lineBreakMode = .byWordWrapping
        textLabel.maximumNumberOfLines = 0
        addSubview(textLabel)

        relationLabel.font = EditorTheme.systemFont(11)
        relationLabel.textColor = EditorTheme.textSecondary9A
        relationLabel.backgroundColor = .clear
        relationLabel.isBezeled = false
        relationLabel.isEditable = false
        relationLabel.isSelectable = false
        addSubview(relationLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The number of the note, or "+" while it has no text and claims no number yet.
    var label: String {
        get { badgeLabel.stringValue }
        set { badgeLabel.stringValue = newValue }
    }

    var text: String {
        get { textLabel.stringValue }
        set {
            textLabel.stringValue = newValue
            needsLayout = true
        }
    }

    var relation: String {
        get { relationLabel.stringValue }
        set {
            relationLabel.stringValue = newValue
            relationLabel.isHidden = newValue.isEmpty
            needsLayout = true
        }
    }

    func height(forWidth width: CGFloat) -> CGFloat {
        let textWidth = max(40, width - Self.padding.left - Self.padding.right - Self.badgeSize - 8)
        let textHeight = textLabel.stringValue.isEmpty ? 0 : textLabel.sizeThatFits(NSSize(width: textWidth, height: .greatestFiniteMagnitude)).height
        let relationHeight: CGFloat = relationLabel.isHidden ? 0 : 19
        return max(Self.badgeSize, textHeight + relationHeight) + Self.padding.top + Self.padding.bottom
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }
    override func mouseExited(with event: NSEvent) { isHovering = false }
    override func mouseUp(with event: NSEvent) { onActivated?() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func layout() {
        super.layout()
        let textX = Self.padding.left + Self.badgeSize + 8
        let textWidth = max(40, bounds.width - textX - Self.padding.right)
        let textHeight = textLabel.stringValue.isEmpty ? 0 : textLabel.sizeThatFits(NSSize(width: textWidth, height: .greatestFiniteMagnitude)).height
        textLabel.frame = CGRect(x: textX, y: Self.padding.top, width: textWidth, height: textHeight)
        relationLabel.frame = CGRect(x: textX, y: Self.padding.top + textHeight + 3, width: textWidth, height: relationLabel.isHidden ? 0 : 16)
        badgeLabel.frame = CGRect(x: Self.padding.left, y: Self.padding.top + (Self.badgeSize - 14) / 2, width: Self.badgeSize, height: 14)
    }

    override func draw(_ dirtyRect: NSRect) {
        if isCurrent {
            AccentPalette.wash(alpha: 0.28).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 9, yRadius: 9).fill()
        } else if isHovering {
            EditorTheme.toolHoverBackground.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 9, yRadius: 9).fill()
        }
        let badge = CGRect(x: Self.padding.left, y: Self.padding.top, width: Self.badgeSize, height: Self.badgeSize)
        EditorTheme.accent.setFill()
        NSBezierPath(ovalIn: badge).fill()
    }
}

/// The panel on the right of a reopened capture that already carries at least one note
/// (SPEC-DELTA-3 §1.4 E-12): a title, the rows, and the line that stands in for an empty list.
final class CommentsPanelView: NSView {
    static let width: CGFloat = 280
    /// The gap between the panel and the work area the markup is laid out in.
    static let gap: CGFloat = 16
    private static let padding: CGFloat = 14

    private let titleLabel: NSTextField
    private let emptyLabel: NSTextField
    private let scrollView = NSScrollView()
    private let listView = NSView(frame: .zero)
    private(set) var entries: [CommentListEntryView] = []

    override var isFlipped: Bool { true }

    init(language: String) {
        titleLabel = EditorPopoverChrome.label(EditorStrings.comments(language), bold: true)
        emptyLabel = EditorPopoverChrome.label(EditorStrings.noComments(language), color: EditorTheme.textSecondary9A)
        emptyLabel.font = EditorTheme.systemFont(12)
        super.init(frame: .zero)
        addSubview(titleLabel)
        addSubview(emptyLabel)
        listView.autoresizingMask = [.width]
        scrollView.documentView = listView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.automaticallyAdjustsContentInsets = false
        addSubview(scrollView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Rebuilds the rows only when the set of them changed; otherwise the numbers and the text are
    /// refreshed in place (`SyncCommentsPanel`, `Comments.cs:45-70`).
    func setRows(_ rows: [(id: SBGuid, label: String, text: String, relation: String)], activate: @escaping (SBGuid) -> Void) {
        if entries.map(\.annotationId) != rows.map(\.id) {
            for entry in entries { entry.removeFromSuperview() }
            entries = rows.map { row in
                let entry = CommentListEntryView(annotationId: row.id)
                entry.onActivated = { activate(row.id) }
                listView.addSubview(entry)
                return entry
            }
        }
        for (entry, row) in zip(entries, rows) {
            entry.label = row.label
            entry.text = row.text
            entry.relation = row.relation
        }
        emptyLabel.isHidden = !rows.isEmpty
        needsLayout = true
        layoutRows()
    }

    func highlight(_ annotationId: SBGuid?) {
        for entry in entries { entry.isCurrent = annotationId != nil && entry.annotationId == annotationId }
        // Scrolled to by the heights of the rows above it.
        guard let current = entries.first(where: { $0.isCurrent }) else { return }
        listView.scrollToVisible(current.frame)
    }

    private func layoutRows() {
        let rowWidth = max(40, scrollView.contentSize.width)
        var y: CGFloat = 0
        for entry in entries {
            let height = entry.height(forWidth: rowWidth)
            entry.frame = CGRect(x: 0, y: y, width: rowWidth, height: height)
            y += height + 4
        }
        listView.frame = CGRect(x: 0, y: 0, width: rowWidth, height: max(y, scrollView.contentSize.height))
    }

    override func layout() {
        super.layout()
        let contentWidth = bounds.width - Self.padding * 2
        titleLabel.frame = CGRect(x: Self.padding, y: Self.padding, width: contentWidth, height: 20)
        emptyLabel.frame = CGRect(x: Self.padding, y: Self.padding + 30, width: contentWidth, height: 18)
        let top = Self.padding + 30
        scrollView.frame = CGRect(x: Self.padding, y: top, width: contentWidth, height: max(0, bounds.height - top - Self.padding))
        layoutRows()
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: EditorTheme.toolbarCornerRadius, yRadius: EditorTheme.toolbarCornerRadius)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
        shadow.shadowBlurRadius = 22
        shadow.shadowOffset = NSSize(width: 0, height: -5)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        EditorTheme.toolbarBackground.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}
