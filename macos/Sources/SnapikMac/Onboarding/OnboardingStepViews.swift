// The four built steps of the wizard (the fifth one is `HowToSlidesView`), ported from
// `src/Snapik.App/OnboardingWindow.xaml`, SPEC-DELTA-3 §1.6 O-2…O-6.
import AppKit
import SnapikCore

/// One layout for every step: the same width, the same heading, the same buttons.
class OnboardingStepView: NSView {
    static let panelWidth: CGFloat = 440

    let titleLabel = NSTextField(wrappingLabelWithString: "")
    let subtitleLabel = NSTextField(wrappingLabelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        titleLabel.font = NSFont.systemFont(ofSize: 24, weight: .semibold)
        subtitleLabel.font = NSFont.systemFont(ofSize: 14)
        addSubview(titleLabel)
        addSubview(subtitleLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func applyLocalization(_ language: String) {}

    func applyTheme(_ palette: ThemePalette) {
        titleLabel.textColor = palette.text
        subtitleLabel.textColor = palette.textMuted
    }

    /// How tall the step is; the wizard scrolls what does not fit.
    var fittingHeight: CGFloat { 0 }

    func text(_ russian: String, _ language: String) -> String {
        MacUiText.text(russian, language: language)
    }

    /// Lays the heading out at the top of the step and answers with the line under it.
    func layoutHeading(width: CGFloat, centred: Bool) -> CGFloat {
        titleLabel.alignment = centred ? .center : .left
        subtitleLabel.alignment = centred ? .center : .left
        let titleHeight = ceil(
            titleLabel.attributedStringValue.boundingRect(
                with: NSSize(width: width, height: 1000), options: [.usesLineFragmentOrigin]
            ).height)
        let subtitleHeight = ceil(
            subtitleLabel.attributedStringValue.boundingRect(
                with: NSSize(width: width, height: 1000), options: [.usesLineFragmentOrigin]
            ).height)
        var y = bounds.height - 12 - titleHeight
        titleLabel.frame = NSRect(x: 0, y: y, width: width, height: titleHeight)
        y -= 10 + subtitleHeight
        subtitleLabel.frame = NSRect(x: 0, y: y, width: width, height: subtitleHeight)
        return y - 28
    }
}

/// Step 1, "Добро пожаловать": the language is asked once, here, and nowhere else, and the scene
/// under it is what the product does in one loop of nine seconds.
final class OnboardingWelcomeStepView: OnboardingStepView {
    let languageSegment = NSSegmentedControl(
        labels: ["Русский", "English"], trackingMode: .selectOne, target: nil, action: nil)
    let scene = CaptureSceneSmallView(frame: .zero)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(languageSegment)
        addSubview(scene)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func applyLocalization(_ language: String) {
        titleLabel.stringValue = text("Выдели. Прокомментируй. Отправь.", language)
        subtitleLabel.stringValue = text(
            "Скриншотер для одной задачи: несколько снимков с заметками — и сразу в дело. В чат с ИИ, в мессенджер, в письмо, в задачу.",
            language)
        languageSegment.toolTip = text("Язык интерфейса", language)
        languageSegment.setAccessibilityLabel(text("Язык интерфейса", language))
        scene.applyLanguage(language)
        needsLayout = true
    }

    override var fittingHeight: CGFloat { 12 + 26 + 22 + 40 + 10 + 60 + 28 + 180 }

    override func layout() {
        super.layout()
        languageSegment.frame = NSRect(x: (bounds.width - 200) / 2, y: bounds.height - 12 - 26, width: 200, height: 26)
        let width = bounds.width
        let titleHeight = ceil(
            titleLabel.attributedStringValue.boundingRect(
                with: NSSize(width: width, height: 1000), options: [.usesLineFragmentOrigin]
            ).height)
        let subtitleHeight = ceil(
            subtitleLabel.attributedStringValue.boundingRect(
                with: NSSize(width: 470, height: 1000), options: [.usesLineFragmentOrigin]
            ).height)
        titleLabel.alignment = .center
        subtitleLabel.alignment = .center
        var y = bounds.height - 12 - 26 - 22 - titleHeight
        titleLabel.frame = NSRect(x: 0, y: y, width: width, height: titleHeight)
        y -= 10 + subtitleHeight
        subtitleLabel.frame = NSRect(x: (width - 470) / 2, y: y, width: 470, height: subtitleHeight)
        y -= 26 + 180
        scene.frame = NSRect(x: 0, y: y, width: width, height: 180)
    }
}

/// Step 2, "Клавиша для снимка": the rules answer before the registration does, and a free
/// combination is offered beside the refusal so the user is never left to invent one.
final class OnboardingHotkeyStepView: OnboardingStepView {
    let field = HotkeyRecorderField(frame: .zero)
    let conflictLabel = NSTextField(wrappingLabelWithString: "")
    let suggestChip = ChipButton(frame: .zero)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        conflictLabel.font = NSFont.systemFont(ofSize: 12)
        conflictLabel.isHidden = true
        suggestChip.isHidden = true
        suggestChip.wearsAccent = true
        addSubview(field)
        addSubview(conflictLabel)
        addSubview(suggestChip)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func applyLocalization(_ language: String) {
        titleLabel.stringValue = text("Клавиша для снимка", language)
        subtitleLabel.stringValue = text("Нажми на поле и введи своё сочетание", language)
        field.language = language
        field.setAccessibilityLabel(text("Клавиша для снимка", language))
        needsLayout = true
    }

    override func applyTheme(_ palette: ThemePalette) {
        super.applyTheme(palette)
        field.palette = palette
        suggestChip.palette = palette
        conflictLabel.textColor = palette.danger
    }

    override var fittingHeight: CGFloat { 12 + 30 + 10 + 21 + 28 + 48 + 10 + 20 + 10 + 28 }

    override func layout() {
        super.layout()
        var y = layoutHeading(width: bounds.width, centred: false)
        y -= 48
        field.frame = NSRect(x: 0, y: y, width: bounds.width, height: 48)
        y -= 10 + 20
        conflictLabel.frame = NSRect(x: 0, y: y, width: bounds.width, height: 20)
        y -= 10 + 28
        suggestChip.frame = NSRect(x: 0, y: y, width: suggestChip.fittingWidth, height: 28)
    }
}

/// Step 3: one card, the login item. The card that pinned the application to the taskbar is not
/// ported — in the Dock the application is there while it runs, and "keep in Dock" is the user's own
/// menu (SPEC-DELTA-3 §4, O-5).
final class OnboardingStartupStepView: OnboardingStepView {
    let card = CardView(frame: .zero)
    let startupSwitch = NSSwitch(frame: .zero)
    let cardTitle = NSTextField(wrappingLabelWithString: "")
    let cardSubtitle = NSTextField(wrappingLabelWithString: "")
    let unavailableLabel = NSTextField(wrappingLabelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        cardTitle.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        cardSubtitle.font = NSFont.systemFont(ofSize: 12)
        unavailableLabel.font = NSFont.systemFont(ofSize: 12)
        unavailableLabel.isHidden = true
        card.addSubview(cardTitle)
        card.addSubview(cardSubtitle)
        card.addSubview(unavailableLabel)
        card.addSubview(startupSwitch)
        addSubview(card)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func applyLocalization(_ language: String) {
        titleLabel.stringValue = text("Чтобы всегда был под рукой", language)
        // Windows says "Два переключателя" because it has two cards; this step has one, and the line
        // is not in the shared table, so it is localized here — as the Q7 caption of the settings is.
        subtitleLabel.stringValue =
            language == "en"
            ? "One switch and Snapik never has to be looked for."
            : "Один переключатель — и Snapik не придётся искать."
        cardTitle.stringValue = text("Открывать при включении компьютера", language)
        cardSubtitle.stringValue = text("Ждёт в углу экрана, клавиша работает сразу", language)
        unavailableLabel.stringValue = text("Автозапуск недоступен", language)
        startupSwitch.setAccessibilityLabel(text("Открывать при включении компьютера", language))
        needsLayout = true
    }

    override func applyTheme(_ palette: ThemePalette) {
        super.applyTheme(palette)
        card.palette = palette
        cardTitle.textColor = palette.text
        cardSubtitle.textColor = palette.textMuted
        unavailableLabel.textColor = palette.danger
    }

    override var fittingHeight: CGFloat { 12 + 30 + 10 + 21 + 28 + 96 }

    override func layout() {
        super.layout()
        let y = layoutHeading(width: bounds.width, centred: false)
        let cardHeight: CGFloat = unavailableLabel.isHidden ? 84 : 104
        card.frame = NSRect(x: 0, y: y - cardHeight, width: bounds.width, height: cardHeight)
        let inner = card.bounds.insetBy(dx: 16, dy: 16)
        startupSwitch.frame = NSRect(
            x: inner.maxX - 40, y: inner.midY - 11, width: 40, height: 22)
        var textY = inner.maxY - 20
        cardTitle.frame = NSRect(x: inner.minX, y: textY, width: inner.width - 56, height: 20)
        textY -= 20
        cardSubtitle.frame = NSRect(x: inner.minX, y: textY, width: inner.width - 56, height: 18)
        if !unavailableLabel.isHidden {
            textY -= 20
            unavailableLabel.frame = NSRect(x: inner.minX, y: textY, width: inner.width - 56, height: 18)
        }
    }
}

/// Step 4, "Как будет выглядеть": the same control the settings show under "Вид", without the row of
/// annotation palettes (O-6).
final class OnboardingAppearanceStepView: OnboardingStepView {
    let picker = AppearancePickerView(frame: .zero)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        picker.showPaletteRow = false
        addSubview(picker)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func applyLocalization(_ language: String) {
        titleLabel.stringValue = text("Как будет выглядеть", language)
        subtitleLabel.stringValue = text(
            "Нажми — окно сразу перекрасится. Поменять можно в любой момент в настройках.", language)
        picker.applyLanguage(language)
        needsLayout = true
    }

    override func applyTheme(_ palette: ThemePalette) {
        super.applyTheme(palette)
        picker.refreshTheme()
    }

    override var fittingHeight: CGFloat { 12 + 30 + 10 + 21 + 28 + picker.fittingHeight }

    override func layout() {
        super.layout()
        let y = layoutHeading(width: bounds.width, centred: false)
        let height = picker.fittingHeight
        picker.frame = NSRect(x: 0, y: y - height, width: bounds.width, height: height)
        picker.needsLayout = true
    }
}

/// One card per promise of a step: the elevated tone of the palette with the line around it.
final class CardView: NSView {
    var palette: ThemePalette = ThemeService.palette(nil) { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
        palette.elevated.setFill()
        box.fill()
        palette.elevatedLine.setStroke()
        box.lineWidth = 1
        box.stroke()
    }
}
