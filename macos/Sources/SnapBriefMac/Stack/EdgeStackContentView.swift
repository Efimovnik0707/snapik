// Port of `EdgeStackWindow.xaml` content (header, accordion thumbnail list, "+ Снимок" button,
// status row), SPEC-DELTA-2 §1.7, SPEC-DELTA-2B §E1.
import AppKit
import SnapBriefCore

protocol EdgeStackContentViewDelegate: AnyObject {
    func edgeStackContentDidRequestNewCapture()
    func edgeStackContentDidRequestHide()
    func edgeStackContent(_ view: EdgeStackContentView, didRequestMoreMenuAt anchor: NSView)
    func edgeStackContent(_ view: EdgeStackContentView, didOpenCaptureId id: SBGuid)
    func edgeStackContent(_ view: EdgeStackContentView, didRequestRemoveCaptureId id: SBGuid)
    func edgeStackContent(_ view: EdgeStackContentView, didReorderCaptureId id: SBGuid, toIndex index: Int)
    func edgeStackContentDidRequestRestore()
    func edgeStackContentHeaderMouseDown(with event: NSEvent)
    /// Port of `OnCaptureThumbMouseEnter`/`OnCaptureListMouseWheel`: both play the capture-list
    /// hover/scroll tick (SPEC-DELTA-2 §1.6), which needs `AppSettings.playSounds` — something
    /// only the coordinator (via `EdgeStackWindowController`) knows about.
    func edgeStackContentDidRequestTickSound(_ view: EdgeStackContentView)
}

/// Row model handed to the content view on every `reload(...)` — a thin projection of
/// `CaptureItem` plus the pre-rendered thumbnail and note count (loading `CGImage`s from disk and
/// counting non-empty notes is the caller's job, not this view's).
struct StackCaptureRow {
    let id: SBGuid
    let label: String
    let thumbnail: NSImage?
    let noteCount: Int
}

/// Port of `EdgeStackWindow.xaml:100-105`'s `ListBox` + `PreviewMouseWheel="OnCaptureListMouseWheel"`:
/// forwards every wheel event to `onScroll` (for the hover/scroll tick sound) before scrolling
/// normally.
final class TickingScrollView: NSScrollView {
    var onScroll: (() -> Void)?

    override func scrollWheel(with event: NSEvent) {
        onScroll?()
        super.scrollWheel(with: event)
    }
}

/// The floating panel's content: outer rounded shell (`#F2171A20`, corner radius 16), header,
/// scrollable accordion card list (visible height capped at `StackMetrics.listMaxHeight`,
/// document bottom-padded by `StackMetrics.listBottomPadding`), primary "+ Снимок" button, and a
/// status row with an optional "Вернуть" link.
final class EdgeStackContentView: NSView {
    weak var delegate: EdgeStackContentViewDelegate?

    private let titleDot = NSView()
    private let titleLabel = NSTextField(labelWithString: "SnapBrief")
    private let countPill = NSView()
    private let countLabel = NSTextField(labelWithString: "0")
    private let moreButton = NSButton()
    private let closeButton = NSButton()
    private let headerView = NSView()

    private let scrollView = TickingScrollView()
    private let listContainer = FlippedView()
    private var cardViews: [ThumbnailCardView] = []
    private var rows: [StackCaptureRow] = []
    private var selectedCaptureId: SBGuid?

    private let newCaptureButton = NSButton()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let restoreButton = NSButton()

    private var draggingCardIndex: Int?
    /// Finding 23/24: cards need the current language to localize their "Открыть снимок"/
    /// "Удалить" accessibility labels (§1.20 dictionary), even though their visible content has
    /// no text of its own.
    private var currentLanguage = "ru"

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = DarkPalette.floatingPanelBackground.cgColor
        layer?.cornerRadius = ThemeMetrics.outerCornerRadius
        configure()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func configure() {
        configureHeader()

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        // Legacy (always-visible) scrollers paint a light track next to the dark cards; use the
        // overlay style so the list stays dark edge to edge.
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.verticalScroller?.knobStyle = .light
        scrollView.documentView = listContainer
        scrollView.onScroll = { [weak self] in
            guard let self else { return }
            self.delegate?.edgeStackContentDidRequestTickSound(self)
        }
        addSubview(scrollView)

        newCaptureButton.title = ""
        newCaptureButton.bezelStyle = .rounded
        newCaptureButton.isBordered = false
        newCaptureButton.wantsLayer = true
        newCaptureButton.layer?.backgroundColor = DarkPalette.accent.cgColor
        newCaptureButton.layer?.cornerRadius = ThemeMetrics.buttonCornerRadius
        newCaptureButton.contentTintColor = .white
        newCaptureButton.target = self
        newCaptureButton.action = #selector(newCaptureClicked)
        addSubview(newCaptureButton)

        statusLabel.textColor = DarkPalette.errorText
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.isHidden = true
        addSubview(statusLabel)

        restoreButton.title = ""
        restoreButton.isBordered = false
        restoreButton.contentTintColor = DarkPalette.restoreLinkText
        restoreButton.font = NSFont.systemFont(ofSize: 11)
        restoreButton.target = self
        restoreButton.action = #selector(restoreClicked)
        restoreButton.isHidden = true
        addSubview(restoreButton)
    }

    private func configureHeader() {
        titleDot.wantsLayer = true
        titleDot.layer?.backgroundColor = DarkPalette.accent.cgColor
        titleDot.layer?.cornerRadius = 3.5
        headerView.addSubview(titleDot)

        titleLabel.textColor = DarkPalette.primaryText
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        headerView.addSubview(titleLabel)

        countPill.wantsLayer = true
        countPill.layer?.backgroundColor = NSColor(hex: "#2B3440").cgColor
        countPill.layer?.cornerRadius = 8
        headerView.addSubview(countPill)

        countLabel.textColor = DarkPalette.secondaryTextBF
        countLabel.font = NSFont.systemFont(ofSize: 11)
        countLabel.alignment = .center
        countPill.addSubview(countLabel)

        moreButton.title = "\u{2022}\u{2022}\u{2022}"
        moreButton.isBordered = false
        moreButton.contentTintColor = DarkPalette.secondaryTextBF
        moreButton.target = self
        moreButton.action = #selector(moreClicked)
        headerView.addSubview(moreButton)

        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Свернуть в трей")
        closeButton.isBordered = false
        closeButton.contentTintColor = DarkPalette.secondaryTextBF
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        headerView.addSubview(closeButton)

        addSubview(headerView)
    }

    // MARK: - Data

    func reload(rows: [StackCaptureRow]) {
        self.rows = rows
        countLabel.stringValue = "\(rows.count)"

        for card in cardViews { card.removeFromSuperview() }
        cardViews = rows.map { row in
            let card = ThumbnailCardView(frame: .zero)
            card.delegate = self
            card.configure(id: row.id, label: row.label, image: row.thumbnail, noteCount: row.noteCount)
            card.isSelected = row.id == selectedCaptureId
            card.applyLocalization(language: currentLanguage)
            listContainer.addSubview(card)
            return card
        }

        needsLayout = true
    }

    /// Port of `EdgeStackWindow.Preview.cs:17,43` (`capture.IsSelected = true`/`false` while the
    /// preview window is open): highlights the open capture's card with the accent border and
    /// keeps it in its expanded accordion state.
    func setSelectedCapture(_ id: SBGuid?) {
        selectedCaptureId = id
        for (index, card) in cardViews.enumerated() {
            card.isSelected = index < rows.count && rows[index].id == id
        }
        layoutCards(width: bounds.width - ThemeMetrics.outerPadding * 2, animated: false)
    }

    func setStatus(_ text: String, isError: Bool) {
        statusLabel.stringValue = text
        statusLabel.isHidden = !isError || text.isEmpty
    }

    func setRestoreVisible(_ visible: Bool) {
        restoreButton.isHidden = !visible
        needsLayout = true
    }

    func applyLocalization(language: String) {
        moreButton.toolTip = MacUiText.text("Ещё", language: language)
        let hideLabel = MacUiText.text("Свернуть в трей", language: language)
        closeButton.toolTip = hideLabel
        closeButton.setAccessibilityLabel(hideLabel)
        restoreButton.title = MacUiText.text("Вернуть", language: language)
        currentLanguage = language
        for card in cardViews { card.applyLocalization(language: language) }
    }

    // MARK: - Layout

    /// Fixed width `StackMetrics.width` (208); height driven by content, clamped to
    /// `[ThemeMetrics.stackMinHeight, ThemeMetrics.stackMaxHeight]` with the (collapsed) card
    /// list capped at `StackMetrics.listMaxHeight` (SPEC-DELTA-2 §1.7).
    func preferredHeight() -> CGFloat {
        let headerHeight: CGFloat = 28
        let listHeight = min(StackMetrics.listMaxHeight, collapsedListHeight())
        let buttonHeight = ThemeMetrics.buttonHeight
        let statusHeight: CGFloat = (statusLabel.isHidden && restoreButton.isHidden) ? 0 : 24
        let total = ThemeMetrics.outerPadding * 2 + headerHeight + 7 + listHeight + 8 + buttonHeight + statusHeight
        return max(ThemeMetrics.stackMinHeight, min(ThemeMetrics.stackMaxHeight, total))
    }

    private func collapsedListHeight() -> CGFloat {
        guard !cardViews.isEmpty else { return 0 }
        return CGFloat(cardViews.count - 1) * StackMetrics.cardStep + StackMetrics.cardHeight
    }

    override func layout() {
        super.layout()
        let padding = ThemeMetrics.outerPadding
        let contentWidth = bounds.width - padding * 2

        headerView.frame = NSRect(x: padding, y: bounds.height - padding - 28, width: contentWidth, height: 28)
        titleDot.frame = NSRect(x: 0, y: 10, width: 7, height: 7)
        titleLabel.frame = NSRect(x: 14, y: 6, width: 90, height: 16)
        countPill.frame = NSRect(x: contentWidth - 62, y: 4, width: 26, height: 16)
        countLabel.frame = countPill.bounds
        moreButton.frame = NSRect(x: contentWidth - 32, y: 2, width: 20, height: 20)
        closeButton.frame = NSRect(x: contentWidth - 12, y: 4, width: 10, height: 10)

        let listTop = headerView.frame.minY - 7
        let listHeight = min(StackMetrics.listMaxHeight, collapsedListHeight())
        let buttonHeight = ThemeMetrics.buttonHeight
        let statusHeight: CGFloat = (statusLabel.isHidden && restoreButton.isHidden) ? 0 : 24

        scrollView.frame = NSRect(x: padding, y: listTop - listHeight, width: contentWidth, height: listHeight)
        layoutCards(width: contentWidth, animated: false)

        let buttonTop = scrollView.frame.minY - 8
        newCaptureButton.frame = NSRect(x: padding, y: buttonTop - buttonHeight, width: contentWidth, height: buttonHeight)

        if statusHeight > 0 {
            let statusTop = newCaptureButton.frame.minY - statusHeight
            statusLabel.frame = NSRect(x: padding, y: statusTop, width: contentWidth - 60, height: statusHeight)
            restoreButton.frame = NSRect(x: bounds.width - padding - 55, y: statusTop, width: 55, height: statusHeight)
        }
    }

    /// Port of `EdgeStackWindow.xaml:144-158`'s accordion `DataTrigger`s: a hovered or selected
    /// card opens to its full height with `StackMetrics.expandedMargin` breathing room above and
    /// below; every other card stays collapsed, overlapping the next by `StackMetrics.cardOverlap`.
    /// `animated` wraps the frame changes in `NSAnimationContext` (open **0.18s**, close **0.16s**,
    /// ease-out — SPEC-DELTA-2B §E1); resorts z-order afterwards (hover 20, selected 30).
    private func layoutCards(width: CGFloat, animated: Bool, duration: TimeInterval = StackMetrics.expandInSeconds) {
        var y: CGFloat = 0
        var frames: [NSRect] = []
        for card in cardViews {
            let expanded = card.isHovered || card.isSelected
            let top = expanded ? y + StackMetrics.expandedMargin : y
            frames.append(NSRect(x: 0, y: top, width: width, height: StackMetrics.cardHeight))
            y = expanded ? top + StackMetrics.cardHeight + StackMetrics.expandedMargin : top + StackMetrics.cardStep
        }
        let documentHeight = max(y + StackMetrics.listBottomPadding, scrollView.bounds.height)

        let applyFrames = { [weak self] in
            guard let self else { return }
            for (card, frame) in zip(self.cardViews, frames) { card.frame = frame }
            self.listContainer.frame = NSRect(x: 0, y: 0, width: width, height: documentHeight)
        }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                for (card, frame) in zip(cardViews, frames) {
                    card.animator().frame = frame
                }
                listContainer.animator().frame = NSRect(x: 0, y: 0, width: width, height: documentHeight)
            }
        } else {
            applyFrames()
        }

        listContainer.sortSubviews(
            { a, b, _ in
                guard let cardA = a as? ThumbnailCardView, let cardB = b as? ThumbnailCardView else { return .orderedSame }
                let zA = cardA.isSelected ? 30 : (cardA.isHovered ? 20 : 0)
                let zB = cardB.isSelected ? 30 : (cardB.isHovered ? 20 : 0)
                if zA == zB { return .orderedSame }
                return zA < zB ? .orderedAscending : .orderedDescending
            }, context: nil)
    }

    // MARK: - Actions

    @objc private func newCaptureClicked() { delegate?.edgeStackContentDidRequestNewCapture() }
    @objc private func closeClicked() { delegate?.edgeStackContentDidRequestHide() }
    @objc private func moreClicked() { delegate?.edgeStackContent(self, didRequestMoreMenuAt: moreButton) }
    @objc private func restoreClicked() { delegate?.edgeStackContentDidRequestRestore() }

    override func mouseDown(with event: NSEvent) {
        // Only the header area drags the window; clicks on cards/buttons are handled by them.
        let point = convert(event.locationInWindow, from: nil)
        if headerView.frame.contains(point) {
            delegate?.edgeStackContentHeaderMouseDown(with: event)
        }
    }
}

extension EdgeStackContentView: ThumbnailCardViewDelegate {
    func thumbnailCardDidOpen(_ card: ThumbnailCardView) {
        guard let index = cardViews.firstIndex(where: { $0 === card }) else { return }
        delegate?.edgeStackContent(self, didOpenCaptureId: rows[index].id)
    }

    func thumbnailCardDidRequestRemove(_ card: ThumbnailCardView) {
        guard let index = cardViews.firstIndex(where: { $0 === card }) else { return }
        delegate?.edgeStackContent(self, didRequestRemoveCaptureId: rows[index].id)
    }

    func thumbnailCard(_ card: ThumbnailCardView, hoverDidChange isHovered: Bool) {
        delegate?.edgeStackContentDidRequestTickSound(self)
        layoutCards(
            width: bounds.width - ThemeMetrics.outerPadding * 2,
            animated: true,
            duration: isHovered ? StackMetrics.expandInSeconds : StackMetrics.expandOutSeconds)
    }

    /// Manual drag-reorder loop (SPEC §1.9: "порог начала — системная минимальная вертикальная
    /// дистанция драга"). Runs a local event-tracking loop for the duration of the drag instead
    /// of a full `NSDraggingSession`, which is unnecessary for same-view vertical reordering.
    // CHECK-API: `NSEvent.nextEvent(matching:until:inMode:dequeue:)` tracking-loop pattern; not
    // verified against a compiler.
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
            let targetIndex = min(max(Int(localPoint.y / StackMetrics.cardStep), 0), max(cardViews.count - 1, 0))
            draggingCardIndex = targetIndex
        }

        if didPassThreshold, let targetIndex = draggingCardIndex, targetIndex != startIndex {
            delegate?.edgeStackContent(self, didReorderCaptureId: rows[startIndex].id, toIndex: targetIndex)
        } else if !didPassThreshold {
            // Port of "Клик по миниатюре" (SPEC §1.9): released without crossing the drag
            // threshold — treat it as opening the capture instead of reordering.
            thumbnailCardDidOpen(card)
        }
        draggingCardIndex = nil
    }
}

/// A flipped (top-left origin) container so card ordering top-to-bottom matches array order
/// without extra Y-axis math.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
