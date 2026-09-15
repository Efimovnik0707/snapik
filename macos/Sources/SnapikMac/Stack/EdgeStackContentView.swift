// Port of `EdgeStackWindow.xaml`'s content: the panel that carries the shadow field, the header,
// the card list, the empty hint, the capture button, the toast and the status line.
// SPEC-DELTA-3 §1.3 S-3, S-5, S-6, S-7, S-8, S-9, S-12; `tasks/tz-005-details/C-strip.md` §C1-C6.
import AppKit
import SnapikCore

/// Which grip a drag started on (S-9): the left edge takes the width, the bottom left corner takes
/// both the width and the height of the list.
enum StackResizeKind {
    case width
    case corner
}

protocol EdgeStackContentViewDelegate: AnyObject {
    func edgeStackContentDidRequestNewCapture()
    func edgeStackContentDidRequestHide()
    func edgeStackContentDidRequestCollapse()
    func edgeStackContentDidRequestExpand()
    func edgeStackContentDidRequestClear()
    func edgeStackContent(_ view: EdgeStackContentView, didRequestMoreMenuAt anchor: NSView)
    func edgeStackContent(_ view: EdgeStackContentView, didOpenCaptureId id: SBGuid)
    func edgeStackContent(_ view: EdgeStackContentView, didRequestRemoveCaptureId id: SBGuid)
    func edgeStackContent(_ view: EdgeStackContentView, didReorderCaptureId id: SBGuid, toIndex index: Int)
    /// [ТЗ№4 C5] Any free place of the panel drags the window; the buttons, the cards, the scroll
    /// bar and the grips take the press for themselves before it gets here.
    func edgeStackContent(_ view: EdgeStackContentView, didRequestDragWith event: NSEvent)
    func edgeStackContent(_ view: EdgeStackContentView, didRequestResize kind: StackResizeKind, with event: NSEvent)
    /// Port of `OnCaptureThumbMouseEnter`/`OnCaptureListMouseWheel` (SPEC-DELTA-2 §1.6): the
    /// hover/scroll tick, which needs `AppSettings.playSounds` — something only the coordinator
    /// (through `EdgeStackWindowController`) knows about.
    func edgeStackContentDidRequestTickSound(_ view: EdgeStackContentView)
    /// The toast, the status line and the empty state change how tall the panel has to be; the
    /// window is the controller's to resize.
    func edgeStackContentDidChangeContentHeight(_ view: EdgeStackContentView)
}

/// A row handed to the content view on every `reload(...)`: a thin projection of `CaptureItem` plus
/// the thumbnail and the note count. A sent capture carries no letter (`SentCaptureRules`).
struct StackCaptureRow {
    let id: SBGuid
    let label: String?
    let thumbnail: NSImage?
    let noteCount: Int
    let isSent: Bool
}

/// Forwards every wheel event to `onScroll` (the hover/scroll tick) before scrolling normally.
final class TickingScrollView: NSScrollView {
    var onScroll: (() -> Void)?

    override func scrollWheel(with event: NSEvent) {
        onScroll?()
        super.scrollWheel(with: event)
    }
}

/// [ТЗ№4 C2] The bar of the list: four points wide at rest and under the pointer alike, the grip
/// filling it, the slot never painted. It lives in the right padding lane of the list, so the width
/// of a card does not change when the strip starts to overflow.
final class StackScroller: NSScroller {
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat {
        StackMetrics.scrollBarWidth
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}

    override func drawKnob() {
        let knob = rect(for: .knob)
        let width = StackMetrics.scrollBarWidth
        let lane = NSRect(x: knob.midX - width / 2, y: knob.minY, width: width, height: knob.height)
        (isHovered ? StackTheme.scrollThumbHover : StackTheme.scrollThumb).setFill()
        NSBezierPath(roundedRect: lane, xRadius: 2, yRadius: 2).fill()
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
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }
}

/// The list of cards. Not flipped on purpose: the cards throw their shadow upwards ([ТЗ№4 C6]), and
/// a flipped container would flip the shadow with the geometry of its layers.
final class StackListView: NSView {}

/// Six invisible points over the left border of the panel, and sixteen on its bottom left corner.
final class StackGripView: NSView {
    var onMouseDown: ((NSEvent) -> Void)?

    override func mouseDown(with event: NSEvent) { onMouseDown?(event) }

    override func resetCursorRects() {
        // AppKit has no public diagonal resize cursor before macOS 15, so the corner shows the same
        // horizontal one as the edge rather than a private glyph.
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }
}

/// The visible panel of the strip: the rounded plate that carries the surface brush of the palette
/// and the one shadow of the window ([ТЗ№4 C6], SPEC-DELTA-3 §4 — no second contour of its own).
final class StackPanelView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowRadius = StackMetrics.panelShadowBlur / 2
        layer?.shadowOffset = CGSize(width: 0, height: -StackMetrics.panelShadowOffset)
        applyPalette()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func applyPalette() {
        let palette = StackTheme.palette
        layer?.shadowColor = palette.shadowColour.cgColor
        layer?.shadowOpacity = Float(palette.shadowOpacity)
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        layer?.shadowPath = CGPath(
            roundedRect: bounds, cornerWidth: StackMetrics.panelCornerRadius,
            cornerHeight: StackMetrics.panelCornerRadius, transform: nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(
            roundedRect: bounds, xRadius: StackMetrics.panelCornerRadius, yRadius: StackMetrics.panelCornerRadius)
        StackBrush.fill(StackTheme.palette.surface, in: path, bounds: bounds)
    }
}

/// The content of the window: the panel inside the field that carries the shadow, the two grips over
/// its edges, and the capsule the strip collapses into.
final class EdgeStackContentView: NSView {
    weak var delegate: EdgeStackContentViewDelegate?

    private let panelView = StackPanelView(frame: .zero)
    private let capsuleView = StackCapsuleView(frame: .zero)

    private let titleDot = NSView()
    private let titleLabel = NSTextField(labelWithString: "Snapik")
    private let countPill = NSView()
    private let countLabel = NSTextField(labelWithString: "0")
    private let clearButton = NSButton()
    private let moreButton = NSButton()
    private let collapseButton = NSButton()
    private let hideButton = NSButton()
    private let headerView = NSView()

    private let scrollView = TickingScrollView()
    private let listContainer = StackListView()
    private let emptyHintLabel = NSTextField(wrappingLabelWithString: "")
    /// `private(set)` (not `private`): the smoke probes of this zone read the frames and the layers
    /// of the cards (`App/SmokeTestRunner+Stack.swift`).
    private(set) var cardViews: [ThumbnailCardView] = []
    private var rows: [StackCaptureRow] = []
    private var selectedCaptureId: SBGuid?

    private let newCaptureButton = NSButton()
    private let toastView = StackToastView(frame: .zero)
    private let statusLabel = NSTextField(wrappingLabelWithString: "")

    private let widthGrip = StackGripView()
    private let cornerGrip = StackGripView()

    private var draggingCardIndex: Int?
    private var currentLanguage = "ru"
    private var emptyHintShortcut: String?

    /// The height of the *list*, not of the window: the window derives its own from this one
    /// (`StripResizeGeometry`). Ignored while the strip is empty, where the hint takes its place.
    var listHeight: CGFloat = CGFloat(StripResizeGeometry.defaultListHeight) {
        didSet { needsLayout = true }
    }
    private(set) var isCollapsed = false
    var isEmpty: Bool { rows.isEmpty }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        configure()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func configure() {
        addSubview(panelView)
        configureHeader()

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.verticalScroller = StackScroller()
        // `Margin="0,2,1,2"` of the bar: it sits in the right padding lane of the list.
        scrollView.scrollerInsets = NSEdgeInsets(top: 2, left: 0, bottom: 2, right: 1)
        scrollView.documentView = listContainer
        scrollView.onScroll = { [weak self] in
            guard let self else { return }
            self.delegate?.edgeStackContentDidRequestTickSound(self)
        }
        panelView.addSubview(scrollView)

        // [ТЗ№4 C3] The empty strip: the header, this hint and the capture button.
        emptyHintLabel.alignment = .center
        emptyHintLabel.font = NSFont.systemFont(ofSize: 12)
        emptyHintLabel.maximumNumberOfLines = 4
        emptyHintLabel.isHidden = true
        panelView.addSubview(emptyHintLabel)

        newCaptureButton.title = ""
        newCaptureButton.bezelStyle = .rounded
        newCaptureButton.isBordered = false
        newCaptureButton.wantsLayer = true
        newCaptureButton.layer?.cornerRadius = StackMetrics.buttonCornerRadius
        newCaptureButton.contentTintColor = .white
        newCaptureButton.imagePosition = .imageLeading
        newCaptureButton.image = NSImage(systemSymbolName: "camera", accessibilityDescription: nil)
        newCaptureButton.target = self
        newCaptureButton.action = #selector(newCaptureClicked)
        panelView.addSubview(newCaptureButton)

        panelView.addSubview(toastView)

        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.isHidden = true
        panelView.addSubview(statusLabel)

        widthGrip.onMouseDown = { [weak self] event in
            guard let self else { return }
            self.delegate?.edgeStackContent(self, didRequestResize: .width, with: event)
        }
        cornerGrip.onMouseDown = { [weak self] event in
            guard let self else { return }
            self.delegate?.edgeStackContent(self, didRequestResize: .corner, with: event)
        }
        // Declared after the panel so they win the hit test on the edge they sit on.
        addSubview(widthGrip)
        addSubview(cornerGrip)

        capsuleView.isHidden = true
        capsuleView.onClick = { [weak self] in self?.delegate?.edgeStackContentDidRequestExpand() }
        addSubview(capsuleView)

        applyPalette()
    }

    private func configureHeader() {
        titleDot.wantsLayer = true
        titleDot.layer?.cornerRadius = 3.5
        headerView.addSubview(titleDot)

        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        // [ТЗ№4 C4] "Snapik 26" is on the limit of the narrower header: the name gives way first.
        titleLabel.cell?.lineBreakMode = .byTruncatingTail
        titleLabel.cell?.truncatesLastVisibleLine = true
        headerView.addSubview(titleLabel)

        countPill.wantsLayer = true
        countPill.layer?.cornerRadius = 8
        headerView.addSubview(countPill)

        countLabel.font = NSFont.systemFont(ofSize: 11)
        countLabel.alignment = .center
        countPill.addSubview(countLabel)

        configureHeaderButton(clearButton, symbol: "trash", action: #selector(clearClicked))
        configureHeaderButton(moreButton, symbol: "ellipsis", action: #selector(moreClicked))
        configureHeaderButton(collapseButton, symbol: "minus", action: #selector(collapseClicked))
        configureHeaderButton(hideButton, symbol: "xmark", action: #selector(hideClicked))

        panelView.addSubview(headerView)
    }

    private func configureHeaderButton(_ button: NSButton, symbol: String, action: Selector) {
        button.isBordered = false
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.target = self
        button.action = action
        headerView.addSubview(button)
    }

    // MARK: - Data

    func reload(rows: [StackCaptureRow]) {
        self.rows = rows
        // The header counts what is still waiting, as the capsule does.
        let waiting = rows.filter { !$0.isSent }.count
        countLabel.stringValue = "\(waiting)"
        capsuleView.setCount(waiting)

        if let selectedCaptureId, !rows.contains(where: { $0.id == selectedCaptureId }) {
            self.selectedCaptureId = nil
        }

        for card in cardViews { card.removeFromSuperview() }
        // The order of the subviews is the order of the data, and the last subview is drawn over the
        // ones before it: the new capture lands over the old ones ([ТЗ№4 C1]). No depth converter,
        // no alternation index, no virtualization — the list is short by the rule of the strip.
        cardViews = rows.map { row in
            let card = ThumbnailCardView(frame: .zero)
            card.delegate = self
            card.configure(
                id: row.id, label: row.label, image: row.thumbnail, noteCount: row.noteCount, isSent: row.isSent)
            card.isSelected = row.id == selectedCaptureId
            card.applyLocalization(language: currentLanguage)
            listContainer.addSubview(card)
            return card
        }

        emptyHintLabel.isHidden = !rows.isEmpty
        scrollView.isHidden = rows.isEmpty
        // [ТЗ№4 C3] An empty strip is not resized by its corner: there is no list to resize.
        cornerGrip.isHidden = rows.isEmpty
        needsLayout = true
    }

    /// The label of the capture shortcut, or `nil` when that shortcut is switched off: the hint of
    /// the empty strip says what to press only when there is something to press.
    func setEmptyHintShortcut(_ shortcut: String?) {
        emptyHintShortcut = shortcut
        applyEmptyHintText()
    }

    func setSelectedCapture(_ id: SBGuid?) {
        selectedCaptureId = id
        for (index, card) in cardViews.enumerated() {
            card.isSelected = index < rows.count && rows[index].id == id
        }
        layoutCards(animated: false)
    }

    func setStatus(_ text: String, isError: Bool) {
        statusLabel.stringValue = text
        statusLabel.isHidden = !isError || text.isEmpty
        delegate?.edgeStackContentDidChangeContentHeight(self)
    }

    func showToast(_ text: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        toastView.show(text, actionTitle: actionTitle, action: action) { [weak self] in
            guard let self else { return }
            self.delegate?.edgeStackContentDidChangeContentHeight(self)
        }
    }

    func hideToast() {
        toastView.hideNow { [weak self] in
            guard let self else { return }
            self.delegate?.edgeStackContentDidChangeContentHeight(self)
        }
    }

    func setCollapsed(_ collapsed: Bool) {
        isCollapsed = collapsed
        panelView.isHidden = collapsed
        widthGrip.isHidden = collapsed
        cornerGrip.isHidden = collapsed || rows.isEmpty
        capsuleView.isHidden = !collapsed
        needsLayout = true
    }

    func applyLocalization(language: String) {
        currentLanguage = language
        clearButton.toolTip = MacUiText.text("Очистить ленту", language: language)
        clearButton.setAccessibilityLabel(clearButton.toolTip)
        moreButton.toolTip = MacUiText.text("Ещё", language: language)
        collapseButton.toolTip = MacUiText.text("Свернуть в капсулу", language: language)
        collapseButton.setAccessibilityLabel(collapseButton.toolTip)
        let hideLabel = MacUiText.text("Свернуть в трей", language: language)
        hideButton.toolTip = hideLabel
        hideButton.setAccessibilityLabel(hideLabel)
        newCaptureButton.title = MacUiText.text("Новый снимок", language: language)
        newCaptureButton.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        capsuleView.applyLocalization(language: language)
        applyEmptyHintText()
        for card in cardViews { card.applyLocalization(language: language) }
        needsLayout = true
    }

    /// Re-reads `ThemeService`: called whenever the strip is shown, so a theme picked in the
    /// settings is on screen without a restart.
    func applyPalette() {
        let palette = StackTheme.palette
        let accent = StackTheme.accent
        panelView.applyPalette()
        capsuleView.applyPalette()
        toastView.applyPalette()
        titleDot.layer?.backgroundColor = accent.flat.cgColor
        titleLabel.textColor = palette.text
        countPill.layer?.backgroundColor = palette.elevated.cgColor
        countLabel.textColor = palette.textMuted
        for button in [clearButton, moreButton, collapseButton, hideButton] {
            button.contentTintColor = palette.textMuted
        }
        newCaptureButton.layer?.backgroundColor = accent.flat.cgColor
        emptyHintLabel.textColor = palette.textMuted
        statusLabel.textColor = palette.danger
        for card in cardViews { card.applyPalette() }
        needsDisplay = true
    }

    private func applyEmptyHintText() {
        let first = MacUiText.text("Сначала сделайте снимок.", language: currentLanguage)
        // The shortcut is data, not a string of the dictionary: it is shown as it is written in the
        // settings, and it is left out when the capture shortcut is switched off.
        emptyHintLabel.stringValue = emptyHintShortcut.map { "\(first)\n\($0)" } ?? first
    }

    // MARK: - Heights

    /// Everything of the window that is not the list: the two shadow fields, the two paddings of the
    /// panel, the header, the gaps around the list, the capture button and whatever of the toast and
    /// the status line is on screen. This is the figure `StripResizeGeometry` is given.
    func chromeHeight() -> CGFloat {
        StackMetrics.shadowMargin * 2 + StackMetrics.panelPadding * 2 + StackMetrics.headerHeight
            + StackMetrics.listTopGap + StackMetrics.listBottomGap + StackMetrics.buttonHeight
            + footerHeight()
    }

    /// The height of the window as it is now: the chrome plus the list, or the chrome plus the hint
    /// of the empty strip ([ТЗ№4 C3] — the empty strip is as tall as its content).
    func windowHeight() -> CGFloat {
        chromeHeight() + (rows.isEmpty ? StackMetrics.emptyHintHeight : max(0, listHeight))
    }

    func capsuleSize() -> NSSize {
        NSSize(
            width: capsuleView.preferredWidth() + StackMetrics.shadowMargin * 2,
            height: StackMetrics.capsuleHeight + StackMetrics.shadowMargin * 2)
    }

    private func footerHeight() -> CGFloat {
        var height: CGFloat = 0
        let contentWidth = max(40, bounds.width - (StackMetrics.shadowMargin + StackMetrics.panelPadding) * 2)
        if !toastView.isHidden { height += 8 + toastView.preferredHeight(width: contentWidth) }
        if !statusLabel.isHidden { height += 8 + statusHeight(width: contentWidth) }
        return height
    }

    private func statusHeight(width: CGFloat) -> CGFloat {
        max(16, StackTextMeasure.height(of: statusLabel, width: width))
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        let margin = StackMetrics.shadowMargin

        if isCollapsed {
            capsuleView.frame = NSRect(
                x: margin, y: margin, width: max(0, bounds.width - margin * 2),
                height: max(0, bounds.height - margin * 2))
            return
        }

        panelView.frame = NSRect(
            x: margin, y: margin, width: max(0, bounds.width - margin * 2),
            height: max(0, bounds.height - margin * 2))

        let padding = StackMetrics.panelPadding
        let contentWidth = max(0, panelView.bounds.width - padding * 2)
        var top = panelView.bounds.height - padding

        headerView.frame = NSRect(x: padding, y: top - StackMetrics.headerHeight, width: contentWidth, height: StackMetrics.headerHeight)
        layoutHeader(width: contentWidth)
        top = headerView.frame.minY - StackMetrics.listTopGap

        let listBoxHeight = rows.isEmpty ? StackMetrics.emptyHintHeight : max(0, listHeight)
        let listFrame = NSRect(x: padding, y: top - listBoxHeight, width: contentWidth, height: listBoxHeight)
        if rows.isEmpty {
            // The hint stands in the middle of the 92-point block, the way the reference draws it.
            let hintWidth = max(0, contentWidth - 20)
            let hintHeight = StackTextMeasure.height(of: emptyHintLabel, width: hintWidth)
            emptyHintLabel.frame = NSRect(
                x: padding + 10, y: listFrame.midY - hintHeight / 2, width: hintWidth, height: hintHeight)
        } else {
            scrollView.frame = listFrame
            layoutCards(animated: false)
        }
        top = listFrame.minY - StackMetrics.listBottomGap

        newCaptureButton.frame = NSRect(x: padding, y: top - StackMetrics.buttonHeight, width: contentWidth, height: StackMetrics.buttonHeight)
        top = newCaptureButton.frame.minY

        if !toastView.isHidden {
            let height = toastView.preferredHeight(width: contentWidth)
            toastView.frame = NSRect(x: padding, y: top - 8 - height, width: contentWidth, height: height)
            top = toastView.frame.minY
        }
        if !statusLabel.isHidden {
            let height = statusHeight(width: contentWidth)
            statusLabel.frame = NSRect(x: padding, y: top - 8 - height, width: contentWidth, height: height)
        }

        // The grips sit on the visible edge of the panel, which is `shadowMargin` inside the window.
        widthGrip.frame = NSRect(x: margin - 3, y: margin + 22, width: 6, height: max(0, bounds.height - margin * 2 - 44))
        cornerGrip.frame = NSRect(x: margin, y: margin, width: 16, height: 16)
        window?.invalidateCursorRects(for: widthGrip)
        window?.invalidateCursorRects(for: cornerGrip)
    }

    private func layoutHeader(width: CGFloat) {
        let size = StackMetrics.headerButtonSize
        let gap: CGFloat = 2
        let centreY = (StackMetrics.headerHeight - size) / 2

        var x = width - size
        for button in [hideButton, collapseButton, moreButton, clearButton] {
            button.frame = NSRect(x: x, y: centreY, width: size, height: size)
            x -= size + gap
        }

        titleDot.frame = NSRect(x: 0, y: (StackMetrics.headerHeight - 7) / 2, width: 7, height: 7)
        let countWidth = max(countLabel.intrinsicContentSize.width + 10, 22)
        let buttonsLeft = x + size + gap
        let titleWidth = max(0, buttonsLeft - 14 - countWidth - 7 - 4)
        titleLabel.frame = NSRect(x: 14, y: (StackMetrics.headerHeight - 16) / 2, width: titleWidth, height: 16)
        countPill.frame = NSRect(
            x: titleLabel.frame.maxX + 7, y: (StackMetrics.headerHeight - 16) / 2, width: countWidth, height: 16)
        countLabel.frame = countPill.bounds
    }

    /// The cards, in the order of the data, each overlapping the one above it by
    /// `StackMetrics.cardOverlap`; a hovered or selected card opens to its full height with
    /// `StackMetrics.expandedMargin` of room above and below.
    ///
    /// The container is not flipped, so the geometry is worked out as a distance from the top of the
    /// document and turned into AppKit's axis at the end. The scroll position is kept across a
    /// reload: measured from the top, the way the user reads the list ([ТЗ№4 C1]).
    private func layoutCards(animated: Bool, duration: TimeInterval = StackMetrics.expandInSeconds) {
        guard !cardViews.isEmpty else {
            listContainer.frame = NSRect(x: 0, y: 0, width: scrollView.bounds.width, height: scrollView.bounds.height)
            return
        }
        let width = scrollView.bounds.width
        let cardWidth = max(0, width - StackMetrics.listPaddingLeft - StackMetrics.listPaddingRight)

        var tops: [CGFloat] = []
        var cursor = StackMetrics.listPaddingTop
        for card in cardViews {
            let expanded = card.isHovered || card.isSelected
            let cardTop = expanded ? cursor + StackMetrics.expandedMargin : cursor
            tops.append(cardTop)
            cursor = expanded
                ? cardTop + StackMetrics.cardHeight + StackMetrics.expandedMargin
                : cardTop + StackMetrics.cardStep
        }
        let contentBottom = (tops.last ?? 0) + StackMetrics.cardHeight
        let documentHeight = max(contentBottom + StackMetrics.listPaddingBottom, scrollView.bounds.height)

        let previousHeight = listContainer.frame.height
        let visible = scrollView.contentView.bounds
        let distanceFromTop = previousHeight > 0 ? previousHeight - visible.maxY : 0

        let frames = tops.map { top in
            NSRect(
                x: StackMetrics.listPaddingLeft, y: documentHeight - top - StackMetrics.cardHeight,
                width: cardWidth, height: StackMetrics.cardHeight)
        }

        listContainer.frame = NSRect(x: 0, y: 0, width: width, height: documentHeight)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                for (card, frame) in zip(cardViews, frames) { card.animator().frame = frame }
            }
        } else {
            for (card, frame) in zip(cardViews, frames) { card.frame = frame }
        }

        let maxOrigin = max(0, documentHeight - visible.height)
        let origin = min(max(0, documentHeight - distanceFromTop - visible.height), maxOrigin)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: origin))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    // MARK: - Actions

    @objc private func newCaptureClicked() { delegate?.edgeStackContentDidRequestNewCapture() }
    @objc private func hideClicked() { delegate?.edgeStackContentDidRequestHide() }
    @objc private func collapseClicked() { delegate?.edgeStackContentDidRequestCollapse() }
    @objc private func clearClicked() { delegate?.edgeStackContentDidRequestClear() }
    @objc private func moreClicked() { delegate?.edgeStackContent(self, didRequestMoreMenuAt: moreButton) }

    /// [ТЗ№4 C5] Whatever of the panel nothing else took: the header, the gaps between the cards,
    /// the plate around the button. The press arrives here through the responder chain, so the
    /// buttons, the cards, the scroll bar and the grips have already had their chance at it.
    override func mouseDown(with event: NSEvent) {
        delegate?.edgeStackContent(self, didRequestDragWith: event)
    }

    // MARK: - Smoke hooks (`App/SmokeTestRunner+Stack.swift`)

    /// Every string the strip shows by itself: the smoke run reads them back in English and fails on
    /// a Cyrillic one, which is how a string without a pair in the dictionary is caught.
    func smokeVisibleStrings() -> [String] {
        var strings = [titleLabel.stringValue, countLabel.stringValue, newCaptureButton.title, emptyHintLabel.stringValue]
        strings += [clearButton, moreButton, collapseButton, hideButton].compactMap(\.toolTip)
        if !statusLabel.isHidden { strings.append(statusLabel.stringValue) }
        return strings.filter { !$0.isEmpty }
    }
}

extension EdgeStackContentView: ThumbnailCardViewDelegate {
    func thumbnailCardDidOpen(_ card: ThumbnailCardView) {
        guard let index = cardViews.firstIndex(where: { $0 === card }) else { return }
        setSelectedCapture(rows[index].id)
        delegate?.edgeStackContent(self, didOpenCaptureId: rows[index].id)
    }

    func thumbnailCardDidRequestRemove(_ card: ThumbnailCardView) {
        guard let index = cardViews.firstIndex(where: { $0 === card }) else { return }
        delegate?.edgeStackContent(self, didRequestRemoveCaptureId: rows[index].id)
    }

    func thumbnailCard(_ card: ThumbnailCardView, hoverDidChange isHovered: Bool) {
        // Fix MEDIUM-7: only the entering edge plays the hover tick; `mouseExited` firing it too
        // doubled the sound on every card the pointer passed over.
        if isHovered {
            delegate?.edgeStackContentDidRequestTickSound(self)
        }
        layoutCards(animated: true, duration: isHovered ? StackMetrics.expandInSeconds : StackMetrics.expandOutSeconds)
    }

    /// Manual drag-reorder loop (SPEC §1.9): a local event-tracking loop for the length of the drag
    /// instead of a full `NSDraggingSession`, which a vertical reorder inside one view does not need.
    func thumbnailCard(_ card: ThumbnailCardView, didBeginDragWith event: NSEvent) {
        guard let window, let startIndex = cardViews.firstIndex(where: { $0 === card }) else { return }
        let startLocation = event.locationInWindow
        var didPassThreshold = false
        let threshold: CGFloat = 4

        while true {
            guard
                let next = window.nextEvent(
                    matching: [.leftMouseDragged, .leftMouseUp], until: .distantFuture, inMode: .eventTracking, dequeue: true)
            else { break }

            if next.type == .leftMouseUp { break }

            if !didPassThreshold {
                if abs(next.locationInWindow.y - startLocation.y) < threshold { continue }
                didPassThreshold = true
            }

            let localPoint = listContainer.convert(next.locationInWindow, from: nil)
            let fromTop = listContainer.bounds.height - localPoint.y - StackMetrics.listPaddingTop
            let targetIndex = min(max(Int(fromTop / StackMetrics.cardStep), 0), max(cardViews.count - 1, 0))
            draggingCardIndex = targetIndex
        }

        if didPassThreshold, let targetIndex = draggingCardIndex, targetIndex != startIndex {
            delegate?.edgeStackContent(self, didReorderCaptureId: rows[startIndex].id, toIndex: targetIndex)
        } else if !didPassThreshold {
            // Released without crossing the threshold: that is a click, and a click opens the
            // capture (SPEC §1.9 "Клик по миниатюре").
            thumbnailCardDidOpen(card)
        }
        draggingCardIndex = nil
    }
}
