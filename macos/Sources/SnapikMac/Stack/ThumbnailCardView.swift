// Port of the capture card (`EdgeStackWindow.xaml:234-300`), SPEC-DELTA-3 §1.3 S-3, S-5 and
// `tasks/tz-005-details/C-strip.md` §C1, §C6.
import AppKit
import SnapikCore

protocol ThumbnailCardViewDelegate: AnyObject {
    func thumbnailCardDidOpen(_ card: ThumbnailCardView)
    func thumbnailCardDidRequestRemove(_ card: ThumbnailCardView)
    func thumbnailCard(_ card: ThumbnailCardView, didBeginDragWith event: NSEvent)
    /// Fired on `mouseEntered`/`mouseExited`, so the container can re-run its accordion layout
    /// (`EdgeStackContentView.layoutCards`) and play the hover tick sound.
    func thumbnailCard(_ card: ThumbnailCardView, hoverDidChange isHovered: Bool)
}

/// One capture of the strip: the thumbnail full bleed at 0.86, a **top** strip ([ТЗ№4 C1]) with the
/// letter of the capture and the number of its notes, and a delete button that appears under the
/// pointer. The card is the only thing in the strip besides the window itself that carries a shadow
/// ([ТЗ№4 C6]) and it throws it **upwards**: the card below is drawn over this one, so the seam that
/// is seen is the top edge of the lower card and the shadow falls into it.
///
/// The accordion open/close animation lives in the container (`EdgeStackContentView`); this view
/// only reports hover and paints its own border, dimming and delete button.
final class ThumbnailCardView: NSView {
    weak var delegate: ThumbnailCardViewDelegate?
    private(set) var captureId: SBGuid?

    /// The card clips its content; the card's own layer must not, or it would clip its shadow away.
    private let clipView = NSView()
    private let imageView = NSImageView()
    private let labelStrip = NSView()
    private let badgeView = NSView()
    private let badgeLabel = NSTextField(labelWithString: "")
    private let sentMark = NSImageView()
    private let noteIconView = NSImageView()
    private let noteCountLabel = NSTextField(labelWithString: "")
    private let deleteButton = NSButton()
    private var trackingArea: NSTrackingArea?

    private(set) var isHovered = false
    /// A capture that has already left in a package: it stays in the strip, dimmed, with a check
    /// instead of a letter (`SentCaptureRules`).
    private(set) var isSent = false
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
        layer?.cornerRadius = StackMetrics.cardCornerRadius
        layer?.borderWidth = 1
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowRadius = StackMetrics.cardShadowBlur / 2
        layer?.shadowOpacity = StackMetrics.cardShadowOpacity
        // Positive height is upwards: the cards are laid out in AppKit's own axis on purpose
        // (`StackListView` is not flipped), so the shadow needs no sign of its own.
        layer?.shadowOffset = CGSize(width: 0, height: StackMetrics.cardShadowOffset)

        clipView.wantsLayer = true
        clipView.layer?.cornerRadius = StackMetrics.cardCornerRadius
        clipView.layer?.masksToBounds = true
        addSubview(clipView)

        imageView.imageScaling = .scaleAxesIndependently
        imageView.alphaValue = 0.86
        clipView.addSubview(imageView)

        labelStrip.wantsLayer = true
        clipView.addSubview(labelStrip)

        badgeView.wantsLayer = true
        badgeView.layer?.cornerRadius = 10
        labelStrip.addSubview(badgeView)

        badgeLabel.alignment = .center
        badgeLabel.textColor = .white
        badgeLabel.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        badgeLabel.backgroundColor = .clear
        badgeLabel.isBezeled = false
        badgeLabel.isEditable = false
        badgeView.addSubview(badgeLabel)

        sentMark.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
        sentMark.contentTintColor = .white
        sentMark.isHidden = true
        badgeView.addSubview(sentMark)

        noteIconView.image = NSImage(systemSymbolName: "bubble.left", accessibilityDescription: nil)
        noteIconView.contentTintColor = NSColor(hex: "#AEB8C7")
        labelStrip.addSubview(noteIconView)

        noteCountLabel.textColor = NSColor(hex: "#DCE3ED")
        noteCountLabel.font = NSFont.systemFont(ofSize: 11)
        noteCountLabel.backgroundColor = .clear
        noteCountLabel.isBezeled = false
        noteCountLabel.isEditable = false
        labelStrip.addSubview(noteCountLabel)

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
        applyPalette()
    }

    func configure(id: SBGuid, label: String?, image: NSImage?, noteCount: Int, isSent: Bool) {
        captureId = id
        imageView.image = image
        badgeLabel.stringValue = label ?? ""
        badgeLabel.isHidden = isSent
        sentMark.isHidden = !isSent
        noteCountLabel.stringValue = "\(noteCount)"
        self.isSent = isSent
        applyPalette()
        layoutSubviews()
    }

    /// Re-reads the palette and the accent (`ThemeService`): the strip repaints itself every time it
    /// is shown, so a theme picked in the settings is on screen at the next capture.
    func applyPalette() {
        clipView.layer?.backgroundColor = StackTheme.cardBackground.cgColor
        labelStrip.layer?.backgroundColor = StackTheme.cardLabelStripBackground.cgColor
        badgeView.layer?.backgroundColor = (isSent ? StackTheme.sentBadgeBackground : StackTheme.accent.flat).cgColor
        updateAppearance()
    }

    /// Finding 23/24 (§1.20 dictionary): the card is one big "open capture" button with no name of
    /// its own, and the delete button needs the language of the moment.
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
        clipView.frame = bounds
        imageView.frame = clipView.bounds
        layer?.shadowPath = CGPath(
            roundedRect: bounds, cornerWidth: StackMetrics.cardCornerRadius,
            cornerHeight: StackMetrics.cardCornerRadius, transform: nil)

        // [ТЗ№4 C1] The strip is at the top of the card: that is the part of it the next card does
        // not cover.
        let stripHeight = StackMetrics.cardLabelStripHeight
        labelStrip.frame = NSRect(x: 0, y: bounds.height - stripHeight, width: bounds.width, height: stripHeight)
        badgeView.frame = NSRect(x: 7, y: (stripHeight - 20) / 2, width: 20, height: 20)
        badgeLabel.frame = badgeView.bounds
        sentMark.frame = NSRect(x: 4, y: 4, width: 12, height: 12)
        noteIconView.frame = NSRect(x: badgeView.frame.maxX + 7, y: (stripHeight - 11) / 2, width: 11, height: 11)
        let noteLabelX = noteIconView.frame.maxX + 4
        noteCountLabel.frame = NSRect(
            x: noteLabelX, y: (stripHeight - 14) / 2, width: max(0, bounds.width - noteLabelX - 36), height: 14)

        let deleteSize = StackMetrics.cardDeleteButtonSize
        deleteButton.frame = NSRect(
            x: bounds.width - deleteSize - 5, y: bounds.height - deleteSize - 2, width: deleteSize, height: deleteSize)
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
        let borderColour: NSColor
        if isSelected {
            borderColour = StackTheme.cardSelectedBorder
        } else if isHovered {
            borderColour = StackTheme.cardHoverBorder
        } else {
            borderColour = isSent ? StackTheme.sentCardBorder : StackTheme.cardBorder
        }
        layer?.borderColor = borderColour.cgColor
        // The dimming of a sent capture sits on the thumbnail and its strip, not on the card, so the
        // delete button that appears on hover stays as bright as on any other capture.
        clipView.alphaValue = isSent ? 0.45 : 1
        deleteButton.animator().alphaValue = (isHovered || isSelected) ? 1 : 0
    }

    /// Delegated to the container's drag/click tracking loop, which tells "open" (no threshold
    /// crossed) from "reorder drag" (SPEC §1.9).
    override func mouseDown(with event: NSEvent) {
        delegate?.thumbnailCard(self, didBeginDragWith: event)
    }

    @objc private func removeClicked() { delegate?.thumbnailCardDidRequestRemove(self) }
}
