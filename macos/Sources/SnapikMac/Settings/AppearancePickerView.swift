// Port of `src/Snapik.App/Controls/AppearancePicker.xaml(.cs)`, SPEC-DELTA-3 §1.5 G-4, G-5 and
// `tasks/tz-005-details/A-onboarding.md` §A4, §A5.
import AppKit
import SnapikCore

/// Paints what a palette or an accent is made of. A brush of the theme is either one colour or a run
/// of them along a line, and the points of the run are the WPF ones — the unit square of the element
/// with `0,0` at its top-left corner — so they are turned into the angle `NSGradient` draws along
/// here, once, rather than at every call site.
enum AppearanceBrush {
    static func fill(_ brush: ThemeBrush, in path: NSBezierPath, bounds: NSRect) {
        switch brush {
        case .solid(let colour):
            colour.setFill()
            path.fill()
        case .gradient(_, let start, let end):
            guard let gradient = brush.nsGradient() else {
                brush.flat.setFill()
                path.fill()
                return
            }
            gradient.draw(in: path, angle: angle(from: start, to: end, in: bounds))
        }
    }

    static func fill(_ brush: ThemeBrush, in rect: NSRect, radius: CGFloat = 0) {
        fill(brush, in: NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius), bounds: rect)
    }

    /// The WPF pair of points as the angle of a Cocoa gradient: y runs down in the unit square and up
    /// on screen, so the vertical part of the vector changes sign.
    private static func angle(from start: CGPoint, to end: CGPoint, in bounds: NSRect) -> CGFloat {
        let dx = (end.x - start.x) * max(bounds.width, 1)
        let dy = -(end.y - start.y) * max(bounds.height, 1)
        if dx == 0 && dy == 0 { return 0 }
        return atan2(dy, dx) * 180 / .pi
    }
}

/// The look of the application in one control: the gallery of themes, the row of accents and a line
/// showing what a mark will look like. It is shown twice — on step four of the wizard and in the
/// "Вид" tab of the settings — and both show the same thing because it is the same control.
///
/// The preview is live and free: choosing a card applies the theme to the whole application at once
/// and saves nothing. Whoever owns the control takes the values when it saves, and puts the previous
/// pair back if the user walks away.
final class AppearancePickerView: NSView {
    /// A card and the gap after it: what one press of a chevron moves the gallery by.
    static let cardStep: CGFloat = 142
    private static let cardWidth: CGFloat = 132
    private static let chevronSize: CGFloat = 26
    private static let galleryMargin: CGFloat = 8
    private static let cardHeight: CGFloat = 100

    /// [S5-3] The identifiers of the palette row, in the order the editor offers them
    /// (`EditorAppearance.palettes`). One list and not three: the row is written by hand here while
    /// the editor builds its own popover, and two lists of the same preference are how the fourth
    /// name went missing in the first place.
    private static let paletteIds = ["standard", "pastel", "neon", "custom"]

    /// The names of the themes, in the order the gallery shows them. [ТЗ№4 B1] The card that carried
    /// the light theme is the dawn one, and it says so.
    private static let themeNames: [String: String] = [
        "dark": "Тёмная", "glass": "Стекло", "night": "Ночь",
        "sunset": "Закат", "sea": "Море", "dawn": "Светлая · Рассвет",
    ]

    // The identifier of an accent and its name have drifted apart: "teal" is shown as green and
    // "coral" as orange, because the settings file carries the identifier and renaming it would cost
    // a migration for a word.
    private static let accentNames: [String: String] = [
        "blue": "синий", "teal": "зелёный", "violet": "фиолетовый", "coral": "оранжевый",
        "rose": "розовый", "cyan": "бирюзовый",
        "blue-violet": "сине-фиолетовый", "orange-rose": "оранжево-розовый",
        "green-cyan": "зелёно-бирюзовый", "amber-pink": "янтарно-розовый",
        "rose-violet": "розово-фиолетовый", "cyan-blue": "бирюзово-синий",
    ]

    private let themeCaption = NSTextField(labelWithString: "")
    private let accentCaption = NSTextField(labelWithString: "")
    private let paletteCaption = NSTextField(labelWithString: "")
    private let previousThemeButton = ChevronButton(pointsLeft: true)
    private let nextThemeButton = ChevronButton(pointsLeft: false)
    private let galleryClip = GalleryClipView()
    private let cardsContainer = NSView(frame: .zero)
    private let accentRow = NSView(frame: .zero)
    private let paletteRow = NSView(frame: .zero)
    private let paletteButtons: [NSButton]
    private let sample = SampleRowView()

    private var cards: [ThemeCardButton] = []
    private var dots: [AccentDotView] = []
    private var accentDivider: NSView?
    private var language = "ru"

    /// The card the gallery starts at, counted by the control itself.
    private(set) var firstCard = 0

    var onThemeChanged: (() -> Void)?
    var onAccentChanged: (() -> Void)?
    var onPaletteChanged: (() -> Void)?

    private var theme = ThemeService.defaultTheme
    private var accent = ThemeService.defaultAccent
    private var palette = "standard"

    var selectedTheme: String {
        get { theme }
        set {
            let normalized = ThemeService.normalizeTheme(newValue)
            guard normalized != theme else { return }
            theme = normalized
            // The gallery is left where it stands: choosing a theme must not pull it back from where
            // the chevrons have taken it (`A-onboarding.md` §A4 — this is the removed
            // `BringSelectedCardIntoView`, and the gallery always opens on the first card).
            markSelectedCard()
            onThemeChanged?()
        }
    }

    var selectedAccent: String {
        get { accent }
        set {
            let normalized = ThemeService.normalizeAccent(newValue)
            guard normalized != accent else { return }
            accent = normalized
            markSelectedDot()
            onAccentChanged?()
        }
    }

    /// Which twelve-colour set the editor offers: standard, pastel, neon or the user's own.
    ///
    /// [S5-3] The names this setter accepts are the four the editor knows. A name it refused was
    /// written back to the file as `"standard"` by the next save of the settings — any save, whether
    /// or not the "Вид" tab was ever opened — and the neon chosen in the editor was lost with it.
    var selectedPalette: String {
        get { palette }
        set {
            let value =
                (newValue == "pastel" || newValue == "neon" || newValue == "custom")
                ? newValue : "standard"
            guard value != palette else { return }
            palette = value
            refreshPaletteRow()
            onPaletteChanged?()
        }
    }

    /// Whether the row of annotation palettes is part of the control. It is not by default: the
    /// settings carry it, the wizard does not ask a first-time user to pick between colour sets.
    var showPaletteRow = false {
        didSet {
            paletteRow.isHidden = !showPaletteRow
            paletteCaption.isHidden = !showPaletteRow
            needsLayout = true
        }
    }

    override init(frame frameRect: NSRect) {
        let standard = NSButton(title: "", target: nil, action: nil)
        let pastel = NSButton(title: "", target: nil, action: nil)
        let neon = NSButton(title: "", target: nil, action: nil)
        let custom = NSButton(title: "", target: nil, action: nil)
        paletteButtons = [standard, pastel, neon, custom]
        super.init(frame: frameRect)

        for caption in [themeCaption, accentCaption, paletteCaption] {
            caption.font = NSFont.systemFont(ofSize: 12)
            addSubview(caption)
        }
        previousThemeButton.target = self
        previousThemeButton.action = #selector(previousThemeClicked)
        nextThemeButton.target = self
        nextThemeButton.action = #selector(nextThemeClicked)
        addSubview(previousThemeButton)
        addSubview(nextThemeButton)

        galleryClip.onScroll = { [weak self] cards in self?.pageBy(cards) }
        galleryClip.addSubview(cardsContainer)
        addSubview(galleryClip)
        addSubview(accentRow)

        for (index, button) in paletteButtons.enumerated() {
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.cornerRadius = 7
            button.font = NSFont.systemFont(ofSize: 12)
            button.tag = index
            button.target = self
            button.action = #selector(paletteClicked(_:))
            paletteRow.addSubview(button)
        }
        addSubview(paletteRow)
        addSubview(sample)

        buildThemeCards()
        buildAccentRow()
        paletteRow.isHidden = true
        paletteCaption.isHidden = true
        applyLanguage(language)
        refreshTheme()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The height the control needs; both owners lay it out themselves and both ask for this.
    var fittingHeight: CGFloat {
        let paletteHeight: CGFloat = showPaletteRow ? 20 + 8 + 28 + 18 : 0
        return 20 + 8 + Self.cardHeight + 22 + 20 + 8 + 28 + 18 + paletteHeight + 58
    }

    // MARK: - Localization

    /// The captions are built in code, so they are rebuilt whenever the language changes, the way the
    /// hotkey field rebuilds its own.
    func applyLanguage(_ language: String) {
        self.language = language
        themeCaption.stringValue = text("Тема · фон и панели")
        accentCaption.stringValue = text("Цвет · рамки, кнопки, номера отметок")
        paletteCaption.stringValue = text("Палитра отметок")
        paletteButtons[0].title = text("Стандартная")
        paletteButtons[1].title = text("Пастель")
        paletteButtons[2].title = text("Неон")
        paletteButtons[3].title = text("Своя")
        previousThemeButton.toolTip = text("Предыдущая тема")
        nextThemeButton.toolTip = text("Следующая тема")
        sample.applyLanguage(language)
        for card in cards {
            let name = text(Self.themeNames[card.themeId] ?? card.themeId)
            card.name = name
            card.setAccessibilityLabel(UiFormat.text(text("Тема: {0}"), name))
        }
        for dot in dots {
            let name = text(Self.accentNames[dot.accentId] ?? dot.accentId)
            dot.setAccessibilityLabel(UiFormat.text(text("Акцент: {0}"), name))
            dot.toolTip = name
        }
        refreshPaletteRow()
        needsLayout = true
    }

    private func text(_ russian: String) -> String { MacUiText.text(russian, language: language) }

    // MARK: - Building

    // Every card is drawn out of the palette it stands for, not out of the one in force: the sea card
    // has to show the sea while the application is still dark.
    private func buildThemeCards() {
        for themeId in ThemeService.themes {
            let card = ThemeCardButton(themeId: themeId)
            card.target = self
            card.action = #selector(themeCardClicked(_:))
            cardsContainer.addSubview(card)
            cards.append(card)
        }
        markSelectedCard()
    }

    private func buildAccentRow() {
        var dividerPlaced = false
        for accentId in ThemeService.accents {
            // The row is split in two by what an accent is and not by its name: the hairline goes in
            // front of the first accent that paints with more than one colour
            // (`B-themes-accents.md` §5.4).
            if !dividerPlaced && ThemeService.isGradientAccent(accentId) {
                let divider = NSView(frame: .zero)
                divider.wantsLayer = true
                accentRow.addSubview(divider)
                accentDivider = divider
                dividerPlaced = true
            }
            let dot = AccentDotView(accentId: accentId)
            dot.onPick = { [weak self] picked in self?.pickAccent(picked) }
            accentRow.addSubview(dot)
            dots.append(dot)
        }
        markSelectedDot()
    }

    // MARK: - Selection

    private func markSelectedCard() {
        for card in cards { card.isSelected = card.themeId == theme }
    }

    private func markSelectedDot() {
        for dot in dots { dot.isSelected = dot.accentId == accent }
    }

    private func refreshPaletteRow() {
        let ids = Self.paletteIds
        let tokens = ThemeService.accent(accent)
        let colours = ThemeService.palette(ThemeService.currentTheme)
        for (index, button) in paletteButtons.enumerated() {
            button.layer?.backgroundColor = (ids[index] == palette ? tokens.soft : colours.elevated).cgColor
            button.contentTintColor = colours.text
        }
    }

    /// Repaints everything the control draws out of the pair in force; the owner calls it after the
    /// pair changes under it, and the control calls it itself when a card or a dot is picked.
    func refreshTheme() {
        let colours = ThemeService.palette(ThemeService.currentTheme)
        themeCaption.textColor = colours.textMuted
        accentCaption.textColor = colours.textMuted
        paletteCaption.textColor = colours.textMuted
        accentDivider?.layer?.backgroundColor = colours.divider.cgColor
        previousThemeButton.palette = colours
        nextThemeButton.palette = colours
        sample.palette = colours
        for card in cards { card.needsDisplay = true }
        for dot in dots { dot.needsDisplay = true }
        refreshPaletteRow()
    }

    // MARK: - Gallery

    /// How many whole cards the gallery shows at its current width, never fewer than one.
    private var visibleCards: Int {
        max(1, Int(galleryClip.bounds.width / Self.cardStep))
    }

    /// The furthest card the gallery can start at: past it the strip would show empty space.
    var lastPage: Int { max(0, cards.count - visibleCards) }

    /// The gallery is moved by the card, and the card is counted here. The last step is short of a
    /// whole card on purpose: "every step is 142" and "the last card is whole" cannot both hold, and
    /// the second one wins (`A-onboarding.md` §A4).
    func pageBy(_ cards: Int) {
        firstCard = min(max(firstCard + cards, 0), lastPage)
        layoutGallery(animated: true)
        markChevrons()
    }

    /// The wheel and the horizontal gesture of a trackpad, for the probe: a real `NSEvent` needs a
    /// window behind it.
    func pageByWheel(_ notches: Int) { pageBy(notches) }

    // An end says so. A chevron with nothing left to show is switched off instead of answering a
    // click with nothing.
    private func markChevrons() {
        previousThemeButton.isEnabled = firstCard > 0
        nextThemeButton.isEnabled = firstCard < lastPage
    }

    private func layoutGallery(animated: Bool) {
        let extent = CGFloat(cards.count) * Self.cardStep
        let viewport = galleryClip.bounds.width
        let maximumOffset = max(0, extent - viewport)
        let offset = min(CGFloat(firstCard) * Self.cardStep, maximumOffset)
        let frame = NSRect(x: -offset, y: 0, width: extent, height: galleryClip.bounds.height)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                cardsContainer.animator().frame = frame
            }
        } else {
            cardsContainer.frame = frame
        }
    }

    @objc private func previousThemeClicked() { pageBy(-1) }

    @objc private func nextThemeClicked() { pageBy(1) }

    // The preview is the whole point of the control: the click paints the application, and nothing
    // here writes to the settings file.
    @objc private func themeCardClicked(_ sender: ThemeCardButton) {
        selectedTheme = sender.themeId
        ThemeService.apply(theme: selectedTheme, accent: selectedAccent)
        refreshTheme()
    }

    private func pickAccent(_ accentId: String) {
        selectedAccent = accentId
        ThemeService.apply(theme: selectedTheme, accent: selectedAccent)
        refreshTheme()
    }

    @objc private func paletteClicked(_ sender: NSButton) {
        selectedPalette = Self.paletteIds[sender.tag]
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        let width = bounds.width
        var y = bounds.height

        y -= 20
        themeCaption.frame = NSRect(x: 0, y: y, width: width, height: 16)
        y -= 8 + Self.cardHeight
        let galleryTop = y
        previousThemeButton.frame = NSRect(
            x: 0, y: galleryTop + (Self.cardHeight - Self.chevronSize) / 2,
            width: Self.chevronSize, height: Self.chevronSize)
        nextThemeButton.frame = NSRect(
            x: width - Self.chevronSize, y: galleryTop + (Self.cardHeight - Self.chevronSize) / 2,
            width: Self.chevronSize, height: Self.chevronSize)
        galleryClip.frame = NSRect(
            x: Self.chevronSize + Self.galleryMargin, y: galleryTop,
            width: max(0, width - 2 * (Self.chevronSize + Self.galleryMargin)), height: Self.cardHeight)
        for (index, card) in cards.enumerated() {
            card.frame = NSRect(
                x: CGFloat(index) * Self.cardStep, y: 0, width: Self.cardWidth, height: Self.cardHeight)
        }
        layoutGallery(animated: false)
        markChevrons()

        y -= 22 + 20
        accentCaption.frame = NSRect(x: 0, y: y, width: width, height: 16)
        y -= 8 + 28
        accentRow.frame = NSRect(x: 0, y: y, width: width, height: 28)
        layoutAccentRow()

        if showPaletteRow {
            y -= 18 + 20
            paletteCaption.frame = NSRect(x: 0, y: y, width: width, height: 16)
            y -= 8 + 28
            paletteRow.frame = NSRect(x: 0, y: y, width: width, height: 28)
            var x: CGFloat = 0
            for button in paletteButtons {
                let buttonWidth = max(90, button.attributedTitle.size().width + 28)
                button.frame = NSRect(x: x, y: 0, width: buttonWidth, height: 28)
                x += buttonWidth + 6
            }
        }

        y -= 18 + 58
        sample.frame = NSRect(x: 0, y: max(0, y), width: width, height: 58)
    }

    // Twelve dots of 28 with a gap of 10 and the hairline of the divider: 455 px in all
    // (`A-onboarding.md` §A5), which fits the 520 the wizard gives the control.
    private func layoutAccentRow() {
        let firstGradient = ThemeService.accents.first { ThemeService.isGradientAccent($0) }
        var x: CGFloat = 0
        for dot in dots {
            if let divider = accentDivider, dot.accentId == firstGradient {
                divider.frame = NSRect(x: x + 4, y: 3, width: 1, height: 22)
                x += 9
            }
            dot.frame = NSRect(x: x, y: 0, width: 28, height: 28)
            x += 38
        }
    }

    // MARK: - Smoke hooks

    /// The gallery shows a card per theme and the row a dot per accent; the counts are the data of
    /// `ThemeService`, and a set short of one is what the probe is looking for.
    var smokeCardCount: Int { cards.count }

    var smokeDotCount: Int { dots.count }

    /// The three captions of the palette row, in the language the control was last given. The wizard
    /// switches this row off (O-6), so the settings window is the one place it is on screen and the
    /// one place its translation is worth checking.
    var smokePaletteTitles: [String] { paletteButtons.map(\.title) }

    /// The hairline stands in front of the first accent that paints with more than one colour, and
    /// there is exactly one of it. Windows compared the identifier `"blue-violet"` instead, which
    /// would have broken silently the next time the row was reordered.
    var smokeDividerPrecedesFirstGradient: Bool {
        guard let divider = accentDivider,
            let index = dots.firstIndex(where: { ThemeService.isGradientAccent($0.accentId) }),
            index > 0
        else { return false }
        return divider.frame.minX >= dots[index - 1].frame.maxX
            && divider.frame.maxX <= dots[index].frame.minX
    }
}

// MARK: - Pieces

/// The clip the cards run under: the wheel and the horizontal gesture of a trackpad page the gallery
/// and stop there, so a wheel over the gallery never scrolls the window of the wizard behind it
/// ([ТЗ№4 A4]).
private final class GalleryClipView: NSView {
    var onScroll: ((Int) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func scrollWheel(with event: NSEvent) {
        // One event carries both axes on this platform; the horizontal one wins where there is one at
        // all, and a gesture to the right moves the gallery forward.
        let horizontal = event.scrollingDeltaX
        let vertical = event.scrollingDeltaY
        if abs(horizontal) > abs(vertical) {
            if horizontal == 0 { return }
            onScroll?(horizontal < 0 ? 1 : -1)
        } else {
            if vertical == 0 { return }
            onScroll?(vertical < 0 ? 1 : -1)
        }
        // Deliberately not passed on: without this the wheel reaches the scroll view of the wizard.
    }
}

/// One card of the gallery: the theme it stands for, drawn out of that theme's own palette.
private final class ThemeCardButton: NSControl {
    let themeId: String
    var isSelected = false { didSet { needsDisplay = true } }
    var name: String = "" { didSet { nameLabel.stringValue = name } }

    private let nameLabel = NSTextField(labelWithString: "")

    init(themeId: String) {
        self.themeId = themeId
        super.init(frame: .zero)
        wantsLayer = true
        nameLabel.font = NSFont.systemFont(ofSize: 12)
        nameLabel.alignment = .center
        addSubview(nameLabel)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        nameLabel.frame = NSRect(x: 0, y: 6, width: bounds.width, height: 16)
    }

    override func mouseDown(with event: NSEvent) {
        if let action, let target { NSApp.sendAction(action, to: target, from: self) }
    }

    override func draw(_ dirtyRect: NSRect) {
        let palette = ThemeService.palette(themeId)
        let accent = ThemeService.accent(ThemeService.currentAccent)
        let inForce = ThemeService.palette(ThemeService.currentTheme)
        nameLabel.textColor = inForce.text

        let card = bounds.insetBy(dx: 1, dy: 1)
        let cardPath = NSBezierPath(roundedRect: card, xRadius: 10, yRadius: 10)
        inForce.elevated.setFill()
        cardPath.fill()
        if isSelected {
            cardPath.lineWidth = 2
            accent.flat.setStroke()
            cardPath.stroke()
        }

        // The preview panel of the card: the desktop it sits on, and a strip of the theme it stands
        // for; both are clipped to the rounded rectangle they are drawn in.
        let preview = NSRect(x: card.minX + 6, y: card.maxY - 6 - 64, width: card.width - 12, height: 64)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: preview, xRadius: 7, yRadius: 7).addClip()
        AppearanceBrush.fill(backdrop(), in: preview, radius: 7)

        let strip = NSRect(x: preview.maxX - 6 - 40, y: preview.minY + 6, width: 40, height: preview.height - 12)
        let stripPath = NSBezierPath(roundedRect: strip, xRadius: 5, yRadius: 5)
        AppearanceBrush.fill(palette.surface, in: stripPath, bounds: strip)
        palette.surfaceLine.setStroke()
        stripPath.lineWidth = 1
        stripPath.stroke()

        var barTop = strip.maxY - 4
        for index in 0..<3 {
            let height: CGFloat = index == 2 ? 8 : 12
            let bar = NSRect(x: strip.minX + 4, y: barTop - height, width: strip.width - 8, height: height)
            if index == 2 {
                AppearanceBrush.fill(accent.brush, in: bar, radius: 3)
            } else {
                AppearanceBrush.fill(.solid(palette.divider), in: bar, radius: 3)
            }
            barTop -= height + 3
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    // The mock desktop a preview panel sits on: one neutral tone for the dark themes and one for the
    // light ones, and the glass card shows the colours glass is meant to be seen through.
    private func backdrop() -> ThemeBrush {
        switch themeId {
        case "dawn": return .solid(NSColor(hex: "#E8ECF2"))
        case "glass":
            return .gradient(
                [
                    ThemeGradientStop(0, NSColor(hex: "#5B6B8C")),
                    ThemeGradientStop(0.5, NSColor(hex: "#8C6B7A")),
                    ThemeGradientStop(1, NSColor(hex: "#4E7C8A")),
                ], start: CGPoint(x: 0, y: 0), end: CGPoint(x: 1, y: 1))
        case "dark": return .solid(NSColor(hex: "#2A3140"))
        default: return .solid(NSColor(hex: "#1E2430"))
        }
    }
}

/// One accent of the row: a circle of 28 painted by the accent itself, with a white ring while it is
/// the one in force.
private final class AccentDotView: NSView {
    let accentId: String
    var isSelected = false { didSet { needsDisplay = true } }
    var onPick: ((String) -> Void)?

    init(accentId: String) {
        self.accentId = accentId
        super.init(frame: .zero)
        setAccessibilityRole(.radioButton)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func mouseDown(with event: NSEvent) { onPick?(accentId) }

    override func draw(_ dirtyRect: NSRect) {
        AppearanceBrush.fill(ThemeService.accent(accentId).brush, in: NSBezierPath(ovalIn: bounds), bounds: bounds)
        guard isSelected else { return }
        let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 2, dy: 2))
        ring.lineWidth = 2
        NSColor.white.setStroke()
        ring.stroke()
    }
}

/// "так будут выглядеть отметки": a frame, a number and a button, all three in the accent in force.
private final class SampleRowView: NSView {
    var palette: ThemePalette = ThemeService.palette(nil) { didSet { needsDisplay = true } }
    private let doneLabel = NSTextField(labelWithString: "")
    private let caption = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        doneLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        doneLabel.textColor = .white
        caption.font = NSFont.systemFont(ofSize: 12)
        addSubview(doneLabel)
        addSubview(caption)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func applyLanguage(_ language: String) {
        doneLabel.stringValue = MacUiText.text("Готово", language: language)
        caption.stringValue = MacUiText.text("так будут выглядеть отметки", language: language)
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let centre = bounds.midY
        doneLabel.sizeToFit()
        let capsuleX = 14 + 70 + 14 + 22 + 14
        doneLabel.frame = NSRect(
            x: CGFloat(capsuleX) + 12, y: centre - doneLabel.frame.height / 2,
            width: doneLabel.frame.width, height: doneLabel.frame.height)
        caption.sizeToFit()
        let captionX = doneLabel.frame.maxX + 12 + 14
        caption.frame = NSRect(
            x: captionX, y: centre - caption.frame.height / 2,
            width: max(0, min(caption.frame.width, bounds.width - captionX - 12)),
            height: caption.frame.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        let accent = ThemeService.accent(ThemeService.currentAccent)
        let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        palette.elevated.setFill()
        box.fill()
        palette.elevatedLine.setStroke()
        box.lineWidth = 1
        box.stroke()
        caption.textColor = palette.textMuted

        let centre = bounds.midY
        let frame = NSRect(x: 14, y: centre - 17, width: 70, height: 34)
        let framePath = NSBezierPath(rect: frame.insetBy(dx: 1.5, dy: 1.5))
        framePath.lineWidth = 3
        accent.flat.setStroke()
        framePath.stroke()

        let badge = NSRect(x: frame.maxX + 14, y: centre - 11, width: 22, height: 22)
        AppearanceBrush.fill(accent.brush, in: NSBezierPath(ovalIn: badge), bounds: badge)
        draw("1", in: badge, size: 10, weight: .bold)

        let capsule = NSRect(
            x: badge.maxX + 14, y: centre - 15, width: doneLabel.frame.width + 24, height: 30)
        AppearanceBrush.fill(accent.brush, in: capsule, radius: 7)
    }

    private func draw(_ value: String, in rect: NSRect, size: CGFloat, weight: NSFont.Weight) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: NSColor.white,
        ]
        let text = NSAttributedString(string: value, attributes: attributes)
        let textSize = text.size()
        text.draw(at: NSPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2))
    }
}

/// The chevron of the gallery: one card back or on, dimmed where there is nothing left to show.
private final class ChevronButton: NSButton {
    private let pointsLeft: Bool
    var palette: ThemePalette = ThemeService.palette(nil) { didSet { needsDisplay = true } }

    init(pointsLeft: Bool) {
        self.pointsLeft = pointsLeft
        super.init(frame: .zero)
        isBordered = false
        title = ""
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
        let alpha: CGFloat = isEnabled ? 1 : 0.42
        palette.hover.withAlphaComponent(alpha).setFill()
        box.fill()
        palette.elevatedLine.withAlphaComponent(alpha).setStroke()
        box.lineWidth = 1
        box.stroke()

        let arrow = NSBezierPath()
        let centre = NSPoint(x: bounds.midX, y: bounds.midY)
        let dx: CGFloat = pointsLeft ? 3 : -3
        arrow.move(to: NSPoint(x: centre.x + dx, y: centre.y + 5.5))
        arrow.line(to: NSPoint(x: centre.x - dx, y: centre.y))
        arrow.line(to: NSPoint(x: centre.x + dx, y: centre.y - 5.5))
        arrow.lineWidth = 1.5
        arrow.lineCapStyle = .round
        arrow.lineJoinStyle = .round
        palette.text.withAlphaComponent(alpha).setStroke()
        arrow.stroke()
    }
}
