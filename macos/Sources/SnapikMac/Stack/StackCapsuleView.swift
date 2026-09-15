// Port of the collapsed strip (`EdgeStackWindow.xaml:334-352`, `CollapseToCapsule`/
// `ExpandFromCapsule`, `EdgeStackWindow.xaml.cs:649-700`), SPEC-DELTA-3 §1.3 S-10.
import AppKit
import SnapikCore

/// The strip collapsed: the same window, not a second one. The window carries the hotkeys, the
/// sharing type, the level and the drag of the panel, and a capsule of its own would have to repeat
/// all of it. The counter shows what the header shows — the captures still waiting.
final class StackCapsuleView: NSView {
    var onClick: (() -> Void)?

    private let badgeView = NSView()
    private let badgeIcon = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let countPill = NSView()
    private let countLabel = NSTextField(labelWithString: "0")
    private let chevron = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = StackMetrics.capsuleCornerRadius
        layer?.borderWidth = 1
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowRadius = 9
        layer?.shadowOffset = CGSize(width: 0, height: -4)

        badgeView.wantsLayer = true
        badgeView.layer?.cornerRadius = 14
        addSubview(badgeView)

        badgeIcon.image = NSImage(systemSymbolName: "camera", accessibilityDescription: nil)
        badgeIcon.contentTintColor = .white
        badgeView.addSubview(badgeIcon)

        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        addSubview(titleLabel)

        countPill.wantsLayer = true
        countPill.layer?.cornerRadius = 8
        addSubview(countPill)

        countLabel.font = NSFont.systemFont(ofSize: 11)
        countLabel.alignment = .center
        countPill.addSubview(countLabel)

        chevron.image = NSImage(systemSymbolName: "chevron.up", accessibilityDescription: nil)
        addSubview(chevron)

        setAccessibilityRole(.button)
        applyPalette()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func applyPalette() {
        let palette = StackTheme.palette
        layer?.borderColor = palette.surfaceLine.cgColor
        layer?.shadowOpacity = Float(palette.shadowOpacity)
        badgeView.layer?.backgroundColor = StackTheme.accent.flat.cgColor
        titleLabel.textColor = palette.text
        countPill.layer?.backgroundColor = palette.elevated.cgColor
        countLabel.textColor = palette.textMuted
        chevron.contentTintColor = palette.textMuted
        needsDisplay = true
    }

    func applyLocalization(language: String) {
        titleLabel.stringValue = MacUiText.text("Новый снимок", language: language)
        let expand = MacUiText.text("Развернуть ленту", language: language)
        toolTip = expand
        setAccessibilityLabel(expand)
        needsLayout = true
    }

    func setCount(_ count: Int) {
        countLabel.stringValue = "\(count)"
        needsLayout = true
    }

    /// The width the capsule asks for: the window is sized to it, both sides by the content.
    func preferredWidth() -> CGFloat {
        let title = max(titleLabel.intrinsicContentSize.width, 84)
        let count = max(countLabel.intrinsicContentSize.width + 12, 24)
        return 6 + 28 + 7 + title + 7 + count + 7 + 12 + 12
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(
            roundedRect: bounds, xRadius: StackMetrics.capsuleCornerRadius,
            yRadius: StackMetrics.capsuleCornerRadius)
        StackBrush.fill(StackTheme.palette.surface, in: path, bounds: bounds)
    }

    override func layout() {
        super.layout()
        badgeView.frame = NSRect(x: 6, y: (bounds.height - 28) / 2, width: 28, height: 28)
        badgeIcon.frame = NSRect(x: 6, y: 6, width: 16, height: 16)

        let titleWidth = max(titleLabel.intrinsicContentSize.width, 84)
        titleLabel.frame = NSRect(x: badgeView.frame.maxX + 7, y: (bounds.height - 16) / 2, width: titleWidth, height: 16)

        let countWidth = max(countLabel.intrinsicContentSize.width + 12, 24)
        countPill.frame = NSRect(x: titleLabel.frame.maxX + 7, y: (bounds.height - 16) / 2, width: countWidth, height: 16)
        countLabel.frame = countPill.bounds

        chevron.frame = NSRect(x: countPill.frame.maxX + 7, y: (bounds.height - 12) / 2, width: 12, height: 12)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
