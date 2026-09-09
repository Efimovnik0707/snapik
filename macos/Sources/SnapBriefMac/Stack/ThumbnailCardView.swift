// Port of the capture-card template (`EdgeStackWindow.xaml:120-161`, accordion hover/selected
// triggers `:144-159`), SPEC-DELTA-2 §1.7, SPEC-DELTA-2B §E1.
import AppKit
import SnapBriefCore

protocol ThumbnailCardViewDelegate: AnyObject {
    func thumbnailCardDidOpen(_ card: ThumbnailCardView)
    func thumbnailCardDidRequestRemove(_ card: ThumbnailCardView)
    func thumbnailCard(_ card: ThumbnailCardView, didBeginDragWith event: NSEvent)
    /// Fired on `mouseEntered`/`mouseExited`, so the container can re-run its accordion layout
    /// (`EdgeStackContentView.layoutCards`) and play the hover tick sound.
    func thumbnailCard(_ card: ThumbnailCardView, hoverDidChange isHovered: Bool)
}

/// Tiny stroke-only glyph, reusing `IconPath` (Editor's icon mini-language parser, same target).
private final class MiniIconView: NSView {
    var pathData = ""
    var nativeSize: CGFloat = 10
    var strokeColor: NSColor = .white
    var lineWidth: CGFloat = 1.2

    override func draw(_ dirtyRect: NSRect) {
        IconPath.draw(pathData, in: bounds, nativeSize: nativeSize, stroke: strokeColor, lineWidth: lineWidth)
    }
}

/// Height **78**, corner radius **11**, background `#242A33`, border `#46505E` (hover
/// `#718096`, selected `#7AB8FF`). A full-bleed "open capture" button showing the thumbnail at
/// 0.86 opacity, a bottom label strip (`#E6171A20`, height 26) with the capture's letter badge,
/// a note-count icon+number, and a delete button (27x27) visible on hover/selection. The
/// accordion open/close animation itself lives in the container (`EdgeStackContentView`) — this
/// view only reports hover state and renders the border/delete-button feedback for its own
/// current `isHovered`/`isSelected`.
final class ThumbnailCardView: NSView {
    weak var delegate: ThumbnailCardViewDelegate?
    private(set) var captureId: SBGuid?

    private let imageView = NSImageView()
    private let stripView = NSView()
    private let badgeView = NSView()
    private let badgeLabel = NSTextField(labelWithString: "")
    private let noteIconView = MiniIconView()
    private let noteCountLabel = NSTextField(labelWithString: "")
    private let deleteButton = NSButton()
    private var trackingArea: NSTrackingArea?

    private(set) var isHovered = false
    var isSelected = false {
        didSet { updateAppearance() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        configure()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func configure() {
        layer?.backgroundColor = DarkPalette.cardBackground.cgColor
        layer?.borderColor = StackMetrics.cardBorder.cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = StackMetrics.cornerRadius
        layer?.masksToBounds = true

        imageView.imageScaling = .scaleAxesIndependently
        imageView.alphaValue = 0.86
        addSubview(imageView)

        stripView.wantsLayer = true
        stripView.layer?.backgroundColor = NSColor(hex: "#E6171A20").cgColor
        addSubview(stripView)

        badgeView.wantsLayer = true
        badgeView.layer?.backgroundColor = DarkPalette.accent.cgColor
        badgeView.layer?.cornerRadius = 10
        stripView.addSubview(badgeView)

        badgeLabel.alignment = .center
        badgeLabel.textColor = .white
        badgeLabel.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        badgeLabel.backgroundColor = .clear
        badgeLabel.isBezeled = false
        badgeLabel.isEditable = false
        badgeView.addSubview(badgeLabel)

        noteIconView.pathData = "M1,1 L9,1 L9,7 L5,7 L2,9 L2,7 L1,7 Z"
        noteIconView.nativeSize = 10
        noteIconView.strokeColor = NSColor(hex: "#AEB8C7")
        noteIconView.lineWidth = 1.2
        stripView.addSubview(noteIconView)

        noteCountLabel.textColor = NSColor(hex: "#DCE3ED")
        noteCountLabel.font = NSFont.systemFont(ofSize: 11)
        noteCountLabel.backgroundColor = .clear
        noteCountLabel.isBezeled = false
        noteCountLabel.isEditable = false
        stripView.addSubview(noteCountLabel)

        deleteButton.isBordered = false
        deleteButton.wantsLayer = true
        deleteButton.layer?.backgroundColor = NSColor(hex: "#E6171A20").cgColor
        deleteButton.layer?.cornerRadius = 4
        deleteButton.alphaValue = 0
        deleteButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
        deleteButton.contentTintColor = .white
        deleteButton.target = self
        deleteButton.action = #selector(removeClicked)
        addSubview(deleteButton)

        setAccessibilityRole(.button)
    }

    func configure(id: SBGuid, label: String, image: NSImage?, noteCount: Int) {
        captureId = id
        imageView.image = image
        badgeLabel.stringValue = label
        noteCountLabel.stringValue = "\(noteCount)"
        layoutSubviews()
    }

    /// Finding 23/24 (§1.20 dictionary): the full-bleed "open capture" button has no name of its
    /// own, and the delete button's accessibility description was a hardcoded Russian string
    /// regardless of `language`.
    func applyLocalization(language: String) {
        setAccessibilityLabel(MacUiText.text("Открыть снимок", language: language))
        let removeLabel = MacUiText.text("Удалить", language: language)
        deleteButton.setAccessibilityLabel(removeLabel)
        deleteButton.toolTip = removeLabel
    }

    override func layout() {
        super.layout()
        layoutSubviews()
    }

    private func layoutSubviews() {
        imageView.frame = bounds
        let stripHeight: CGFloat = 26
        stripView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: stripHeight)
        badgeView.frame = NSRect(x: 7, y: (stripHeight - 20) / 2, width: 20, height: 20)
        badgeLabel.frame = badgeView.bounds
        noteIconView.frame = NSRect(x: badgeView.frame.maxX + 7, y: (stripHeight - 10) / 2, width: 10, height: 10)
        let noteLabelX = noteIconView.frame.maxX + 4
        noteCountLabel.frame = NSRect(x: noteLabelX, y: (stripHeight - 14) / 2, width: max(0, bounds.width - noteLabelX - 8), height: 14)
        deleteButton.frame = NSRect(x: bounds.width - 27 - 5, y: bounds.height - 27 - 5, width: 27, height: 27)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
        delegate?.thumbnailCard(self, hoverDidChange: true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
        delegate?.thumbnailCard(self, hoverDidChange: false)
    }

    private func updateAppearance() {
        let borderColor = isSelected ? StackMetrics.selectedBorder : (isHovered ? StackMetrics.hoverBorder : StackMetrics.cardBorder)
        layer?.borderColor = borderColor.cgColor
        deleteButton.animator().alphaValue = (isHovered || isSelected) ? 1 : 0
    }

    /// Delegated to the container's drag/click tracking loop, which distinguishes "open" (no
    /// threshold crossed) from "reorder drag" (SPEC §1.9: "Клик по миниатюре" vs. "Drag and drop
    /// миниатюр").
    override func mouseDown(with event: NSEvent) {
        delegate?.thumbnailCard(self, didBeginDragWith: event)
    }

    @objc private func removeClicked() { delegate?.thumbnailCardDidRequestRemove(self) }
}
