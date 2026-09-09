// Port of the capture-card template (`EdgeStackWindow.xaml:94-97` and surrounding markup),
// SPEC §1.9 point 2.
import AppKit
import SnapBriefCore

protocol ThumbnailCardViewDelegate: AnyObject {
    func thumbnailCardDidOpen(_ card: ThumbnailCardView)
    func thumbnailCardDidRequestRemove(_ card: ThumbnailCardView)
    func thumbnailCard(_ card: ThumbnailCardView, didBeginDragWith event: NSEvent)
}

/// Height **82**, corner radius **10**, background `#242A33`, border `#39424E`; a full-bleed
/// "open capture" button showing the thumbnail at 0.82 opacity, a bottom label strip
/// (`#D9171A20`, height 25) with a round `#2F8CFF` badge holding the capture's letter label, and a
/// delete button (27x27) that is only visible on hover / keyboard focus within the card.
final class ThumbnailCardView: NSView {
    weak var delegate: ThumbnailCardViewDelegate?
    private(set) var captureId: SBGuid?

    private let imageView = NSImageView()
    private let stripView = NSView()
    private let badgeView = NSView()
    private let badgeLabel = NSTextField(labelWithString: "")
    private let deleteButton = NSButton()
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        configure()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func configure() {
        layer?.backgroundColor = DarkPalette.cardBackground.cgColor
        layer?.borderColor = DarkPalette.cardBorder.cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = ThemeMetrics.cardCornerRadius
        layer?.masksToBounds = true

        imageView.imageScaling = .scaleAxesIndependently
        imageView.alphaValue = 0.82
        addSubview(imageView)

        stripView.wantsLayer = true
        stripView.layer?.backgroundColor = DarkPalette.thumbnailStripBackground.cgColor
        addSubview(stripView)

        badgeView.wantsLayer = true
        badgeView.layer?.backgroundColor = DarkPalette.accent.cgColor
        badgeView.layer?.cornerRadius = 10
        stripView.addSubview(badgeView)

        badgeLabel.alignment = .center
        badgeLabel.textColor = .white
        badgeLabel.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        badgeView.addSubview(badgeLabel)

        deleteButton.isBordered = false
        deleteButton.wantsLayer = true
        deleteButton.layer?.backgroundColor = DarkPalette.hintBackground.cgColor
        deleteButton.layer?.cornerRadius = 4
        deleteButton.alphaValue = 0
        // CHECK-API: NSButton with an SF Symbol image as its sole content, no border.
        deleteButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Удалить")
        deleteButton.contentTintColor = DarkPalette.secondaryTextBF
        deleteButton.target = self
        deleteButton.action = #selector(removeClicked)
        addSubview(deleteButton)
    }

    func configure(id: SBGuid, label: String, image: NSImage?) {
        captureId = id
        imageView.image = image
        badgeLabel.stringValue = label
        layoutSubviews()
    }

    override func layout() {
        super.layout()
        layoutSubviews()
    }

    private func layoutSubviews() {
        imageView.frame = bounds
        let stripHeight: CGFloat = 25
        stripView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: stripHeight)
        badgeView.frame = NSRect(x: 6, y: 2.5, width: 20, height: 20)
        badgeLabel.frame = badgeView.bounds
        deleteButton.frame = NSRect(x: bounds.width - 27 - 7, y: bounds.height - 27 - 7, width: 27, height: 27)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { deleteButton.animator().alphaValue = 1 }
    override func mouseExited(with event: NSEvent) { deleteButton.animator().alphaValue = 0 }

    /// Delegated to the container's drag/click tracking loop, which distinguishes "open" (no
    /// threshold crossed) from "reorder drag" (SPEC §1.9: "Клик по миниатюре" vs. "Drag and drop
    /// миниатюр").
    override func mouseDown(with event: NSEvent) {
        delegate?.thumbnailCard(self, didBeginDragWith: event)
    }

    @objc private func removeClicked() { delegate?.thumbnailCardDidRequestRemove(self) }
}
