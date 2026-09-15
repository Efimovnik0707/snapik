// Port of `CapturePreviewWindow.xaml:80-107` (title bar), SPEC-DELTA-2 §1.5, SPEC-DELTA-2B §D.
import AppKit

/// The custom 46pt title bar: capture-label badge, "Просмотр снимка" title, "W × H" size text,
/// and the zoom/fit/fullscreen/markup/close button cluster.
final class PreviewHeaderView: NSView {
    static let height: CGFloat = 46

    private let badgeView = NSView()
    private let badgeLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let sizeLabel = NSTextField(labelWithString: "")

    private let zoomOutButton = NSButton()
    private let zoomLabel = NSTextField(labelWithString: "")
    private let zoomInButton = NSButton()
    private let fitButton = NSButton()
    private let actualSizeButton = NSButton()
    private let fullscreenButton = NSButton()
    private let markupButton = NSButton()
    private let closeButton = NSButton()

    var onZoomOut: (() -> Void)?
    var onZoomIn: (() -> Void)?
    var onFit: (() -> Void)?
    var onActualSize: (() -> Void)?
    var onFullscreen: (() -> Void)?
    var onMarkup: (() -> Void)?
    var onClose: (() -> Void)?
    /// Port of the caption-area drag (`WindowChrome CaptionHeight="46"`): fired for any
    /// `mouseDown` that did not land on one of the buttons above.
    var onDrag: ((NSEvent) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(hex: "#171B22").cgColor

        badgeView.wantsLayer = true
        badgeView.layer?.backgroundColor = NSColor(hex: "#2F8CFF").cgColor
        badgeView.layer?.cornerRadius = 12
        addSubview(badgeView)

        badgeLabel.alignment = .center
        badgeLabel.textColor = .white
        badgeLabel.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        badgeLabel.backgroundColor = .clear
        badgeLabel.isBezeled = false
        badgeLabel.isEditable = false
        badgeView.addSubview(badgeLabel)

        titleLabel.textColor = NSColor(hex: "#EEF2F8")
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.backgroundColor = .clear
        titleLabel.isBezeled = false
        titleLabel.isEditable = false
        addSubview(titleLabel)

        sizeLabel.textColor = NSColor(hex: "#8F9AAA")
        sizeLabel.font = NSFont.systemFont(ofSize: 11)
        sizeLabel.backgroundColor = .clear
        sizeLabel.isBezeled = false
        sizeLabel.isEditable = false
        addSubview(sizeLabel)

        configureIconButton(zoomOutButton, symbol: "minus", action: #selector(zoomOutClicked))
        configureIconButton(zoomInButton, symbol: "plus", action: #selector(zoomInClicked))
        configureIconButton(fullscreenButton, symbol: "arrow.up.left.and.arrow.down.right", action: #selector(fullscreenClicked))
        configureIconButton(closeButton, symbol: "xmark", action: #selector(closeClicked))

        zoomLabel.alignment = .center
        zoomLabel.textColor = NSColor(hex: "#B9C3D1")
        zoomLabel.font = NSFont.systemFont(ofSize: 11)
        zoomLabel.backgroundColor = .clear
        zoomLabel.isBezeled = false
        zoomLabel.isEditable = false
        addSubview(zoomLabel)

        configureTextButton(fitButton, action: #selector(fitClicked))
        configureTextButton(actualSizeButton, action: #selector(actualSizeClicked))
        actualSizeButton.title = "100%"

        configureTextButton(markupButton, action: #selector(markupClicked))
        markupButton.layer?.backgroundColor = NSColor(hex: "#2F8CFF").cgColor
        markupButton.layer?.borderColor = NSColor(hex: "#2F8CFF").cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func configureIconButton(_ button: NSButton, symbol: String, action: Selector) {
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor(hex: "#242A33").cgColor
        button.layer?.borderColor = NSColor(hex: "#3A4451").cgColor
        button.layer?.borderWidth = 1
        button.layer?.cornerRadius = 8
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.contentTintColor = NSColor(hex: "#E9EDF4")
        button.target = self
        button.action = action
        addSubview(button)
    }

    private func configureTextButton(_ button: NSButton, action: Selector) {
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor(hex: "#242A33").cgColor
        button.layer?.borderColor = NSColor(hex: "#3A4451").cgColor
        button.layer?.borderWidth = 1
        button.layer?.cornerRadius = 8
        button.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        button.contentTintColor = NSColor(hex: "#E9EDF4")
        button.target = self
        button.action = action
        addSubview(button)
    }

    func configure(label: String, imageSize: CGSize) {
        badgeLabel.stringValue = label
        sizeLabel.stringValue = "\(Int(imageSize.width)) × \(Int(imageSize.height))"
    }

    func applyLocalization(language: String) {
        titleLabel.stringValue = MacUiText.text("Просмотр снимка", language: language)
        zoomOutButton.toolTip = MacUiText.text("Уменьшить", language: language)
        zoomOutButton.setAccessibilityLabel(zoomOutButton.toolTip)
        zoomInButton.toolTip = MacUiText.text("Увеличить", language: language)
        zoomInButton.setAccessibilityLabel(zoomInButton.toolTip)
        let fitTitle = MacUiText.text("По размеру окна", language: language)
        fitButton.title = fitTitle
        fitButton.toolTip = fitTitle
        markupButton.title = MacUiText.text("Разметка", language: language)
        let closeTitle = MacUiText.text("Закрыть просмотр", language: language)
        closeButton.toolTip = closeTitle
        closeButton.setAccessibilityLabel(closeTitle)
        updateFullscreenTooltip(isFullscreen: false, language: language)
    }

    func updateFullscreenTooltip(isFullscreen: Bool, language: String) {
        let tooltip = MacUiText.text(isFullscreen ? "Вернуть размер" : "На весь экран", language: language)
        fullscreenButton.toolTip = tooltip
        fullscreenButton.setAccessibilityLabel(tooltip)
    }

    func setZoomText(_ percent: Int) {
        zoomLabel.stringValue = "\(percent)%"
    }

    func setFitActive(_ active: Bool) {
        fitButton.layer?.borderColor = (active ? NSColor(hex: "#7AB8FF") : NSColor(hex: "#3A4451")).cgColor
    }

    override func layout() {
        super.layout()
        let leftX: CGFloat = 15
        badgeView.frame = CGRect(x: leftX, y: (bounds.height - 24) / 2, width: 24, height: 24)
        badgeLabel.frame = badgeView.bounds
        titleLabel.frame = CGRect(x: badgeView.frame.maxX + 9, y: (bounds.height - 16) / 2, width: 130, height: 16)
        sizeLabel.frame = CGRect(x: titleLabel.frame.maxX + 9, y: (bounds.height - 14) / 2, width: 100, height: 14)

        var x = bounds.width - 7
        let buttonHeight: CGFloat = 32
        let y = (bounds.height - buttonHeight) / 2
        func place(_ view: NSView, width: CGFloat) {
            x -= width
            view.frame = CGRect(x: x, y: y, width: width, height: buttonHeight)
            x -= 4
        }
        place(closeButton, width: 32)
        place(markupButton, width: 80)
        place(fullscreenButton, width: 32)
        place(actualSizeButton, width: 52)
        place(fitButton, width: 112)
        place(zoomInButton, width: 32)
        place(zoomLabel, width: 43)
        place(zoomOutButton, width: 32)
    }

    /// AppKit only routes `mouseDown` here for points that miss every button subview (the
    /// buttons handle their own clicks first), so this is effectively "clicked empty caption
    /// area" already — matches `WindowChrome.IsHitTestVisibleInChrome` being `False` outside the
    /// buttons.
    override func mouseDown(with event: NSEvent) {
        onDrag?(event)
    }

    @objc private func zoomOutClicked() { onZoomOut?() }
    @objc private func zoomInClicked() { onZoomIn?() }
    @objc private func fitClicked() { onFit?() }
    @objc private func actualSizeClicked() { onActualSize?() }
    @objc private func fullscreenClicked() { onFullscreen?() }
    @objc private func markupClicked() { onMarkup?() }
    @objc private func closeClicked() { onClose?() }
}
