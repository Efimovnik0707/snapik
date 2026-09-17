// Port of the four `HotkeySettingsWindow` tabs ("Общие", "Клавиши", "Сохранение", "Вид"),
// SPEC §6.5, SPEC-DELTA-3 §1.5 G-3, G-7, G-8, G-9, G-10, G-13.
import AppKit
import SnapikCore

/// `{0}`/`{1}` are the Windows-style placeholders of the shared string table (`StatusStrings.swift`
/// fills the same ones by hand); `String(format:)` cannot read them, and a translated line carrying
/// a per-cent sign would break it anyway.
enum UiFormat {
    static func text(_ template: String, _ values: String...) -> String {
        var result = template
        for (index, value) in values.enumerated() {
            result = result.replacingOccurrences(of: "{\(index)}", with: value)
        }
        return result
    }
}

private func checkbox(_ title: String) -> NSButton {
    let button = NSButton(checkboxWithTitle: title, target: nil, action: nil)
    button.font = NSFont.systemFont(ofSize: 13)
    return button
}

private func sectionLabel(_ title: String) -> NSTextField {
    let field = NSTextField(labelWithString: title)
    field.font = NSFont.systemFont(ofSize: 13)
    return field
}

/// What every tab answers to: the pair in force repaints it, the language relabels it.
class SettingsTabView: NSView {
    func applyLocalization(_ language: String) {}
    func applyTheme(_ palette: ThemePalette) {}

    /// [A5-1] What the tab lays out, from its top down to the lowest thing it puts on screen. The
    /// window neither scrolls nor resizes, so a tab that asks for more than the area it is given
    /// loses its bottom without a word, and the probe measures all four instead of comparing one
    /// declared number with another. A row that is switched off is not part of the measurement, the
    /// way a collapsed row is not part of a WPF stack.
    var smokeContentHeight: CGFloat {
        guard let lowest = subviews.filter({ !$0.isHidden }).map({ $0.frame.minY }).min() else {
            return 0
        }
        return bounds.height - lowest
    }
}

/// "Общие": the startup switch, the notifications / clear-the-strip / sounds boxes with the volume
/// under them, the language segment and the link back into the wizard.
final class GeneralTabView: SettingsTabView {
    let startupSwitch = NSSwitch(frame: .zero)
    let startupLabel = sectionLabel("")
    let startupUnavailableLabel = NSTextField(labelWithString: "")
    let notificationsBox = checkbox("")
    /// SPEC-DELTA-3 §2.2 `ClearStackAfterPaste`.
    let clearStackBox = checkbox("")
    let soundsBox = checkbox("")
    /// The volume belongs to the sounds: with them off there is nothing to make quieter (G-10).
    let volumeLabel = sectionLabel("")
    let volumeSlider = NSSlider(value: 40, minValue: 0, maxValue: 100, target: nil, action: nil)
    /// [S5-2] The number the slider is worth, beside it. The slider carries no scale of its own, so
    /// without the number the only way to read the volume was to listen to it.
    let volumeValueLabel = sectionLabel("")
    let languageLabel = sectionLabel("")
    let languageSegment = NSSegmentedControl(labels: ["Русский", "English"], trackingMode: .selectOne, target: nil, action: nil)
    /// [ТЗ№4 E2] The link at the bottom of the tab; it opens the whole wizard with the values in
    /// force and throws away what the dialog was holding.
    let runOnboardingLink = LinkLabel()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        startupUnavailableLabel.font = NSFont.systemFont(ofSize: 12)
        startupUnavailableLabel.isHidden = true
        volumeSlider.numberOfTickMarks = 101
        volumeSlider.allowsTickMarkValuesOnly = true
        volumeValueLabel.font = NSFont.systemFont(ofSize: 12)
        for view in [
            startupSwitch, startupLabel, startupUnavailableLabel, notificationsBox, clearStackBox,
            soundsBox, volumeLabel, volumeSlider, volumeValueLabel, languageLabel, languageSegment,
            runOnboardingLink,
        ] as [NSView] {
            addSubview(view)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// With the sounds off there is nothing to make quieter, and the row goes with them.
    func updateVolumeRow() {
        let visible = soundsBox.state == .on
        volumeLabel.isHidden = !visible
        volumeSlider.isHidden = !visible
        volumeValueLabel.isHidden = !visible
    }

    /// [S5-2] The number the slider is worth, in the shape the quality caption already uses: a space
    /// before the sign, and the same text in both languages. Written by hand and not by a
    /// `NumberFormatter`: a formatter would put a locale's separators into a number that has none.
    func updateVolumeCaption() {
        volumeValueLabel.stringValue = "\(volumeSlider.integerValue) %"
    }

    override func applyLocalization(_ language: String) {
        startupLabel.stringValue = MacUiText.text("Открывать при включении компьютера", language: language)
        startupUnavailableLabel.stringValue = MacUiText.text("Автозапуск недоступен", language: language)
        notificationsBox.title = MacUiText.text("Показывать уведомления", language: language)
        notificationsBox.toolTip = MacUiText.text(
            "Всплывающее окно у часов: «Скопировано», «Сохранено»", language: language)
        clearStackBox.title = MacUiText.text("Очищать ленту после вставки", language: language)
        clearStackBox.toolTip = MacUiText.text(
            "После Ctrl+V лента очищается сама, снимки удаляются", language: language)
        soundsBox.title = MacUiText.text("Звуки", language: language)
        soundsBox.toolTip = MacUiText.text(
            "Щелчок затвора при снимке и тихие тики ленты", language: language)
        volumeLabel.stringValue = MacUiText.text("Громкость", language: language)
        volumeSlider.toolTip = MacUiText.text("Насколько громко звучит интерфейс", language: language)
        languageLabel.stringValue = MacUiText.text("Язык", language: language)
        // [ТЗ№4 E2] Localized here by hand while Windows had no pair for it; Windows wrote one
        // (`UiLanguage.cs:190`), so the link reads it from the shared table like every neighbour.
        runOnboardingLink.stringValue = MacUiText.text("Пройти знакомство заново", language: language)
        needsLayout = true
    }

    override func applyTheme(_ palette: ThemePalette) {
        for label in [startupLabel, volumeLabel, languageLabel] { label.textColor = palette.text }
        startupUnavailableLabel.textColor = palette.textMuted
        volumeValueLabel.textColor = palette.textMuted
        for box in [notificationsBox, clearStackBox, soundsBox] { box.contentTintColor = palette.text }
        runOnboardingLink.textColor = palette.textFaint
    }

    override func layout() {
        super.layout()
        var y = bounds.height - 24
        startupSwitch.frame = NSRect(x: 0, y: y - 2, width: 40, height: 22)
        startupLabel.frame = NSRect(x: 50, y: y, width: bounds.width - 50, height: 18)
        if !startupUnavailableLabel.isHidden {
            y -= 20
            startupUnavailableLabel.frame = NSRect(x: 50, y: y, width: bounds.width - 50, height: 16)
        }
        y -= 32
        notificationsBox.frame = NSRect(x: 0, y: y, width: bounds.width, height: 20)
        y -= 30
        clearStackBox.frame = NSRect(x: 0, y: y, width: bounds.width, height: 20)
        y -= 30
        soundsBox.frame = NSRect(x: 0, y: y, width: bounds.width, height: 20)
        y -= 24
        volumeLabel.frame = NSRect(x: 22, y: y, width: bounds.width - 22, height: 16)
        y -= 26
        volumeSlider.frame = NSRect(x: 22, y: y, width: 200, height: 20)
        // [S5-2] The number sits after the slider with the gap Windows gives it
        // (`HotkeySettingsWindow.xaml:32-40`, a margin of 10 inside a horizontal stack).
        volumeValueLabel.frame = NSRect(
            x: volumeSlider.frame.maxX + 10, y: y + 2, width: 60, height: 16)
        y -= 30
        languageLabel.frame = NSRect(x: 0, y: y, width: bounds.width, height: 16)
        y -= 32
        languageSegment.frame = NSRect(x: 0, y: y, width: 200, height: 26)
        y -= 34
        runOnboardingLink.frame = NSRect(x: 0, y: y, width: bounds.width, height: 18)
    }
}

/// "Клавиши": the two shortcuts with their switches, and the chip that offers a free combination for
/// the one that is off (G-7).
final class HotkeysTabView: SettingsTabView {
    let captureEnabledBox = checkbox("")
    let captureField = HotkeyRecorderField(frame: .zero)
    let fullscreenEnabledBox = checkbox("")
    let fullscreenField = HotkeyRecorderField(frame: .zero)
    let suggestChip = ChipButton(frame: .zero)
    let limitationCaption = NSTextField(wrappingLabelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        limitationCaption.font = NSFont.systemFont(ofSize: 11)
        suggestChip.isHidden = true
        for view in [
            captureEnabledBox, captureField, fullscreenEnabledBox, fullscreenField, suggestChip,
            limitationCaption,
        ] as [NSView] {
            addSubview(view)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func applyLocalization(_ language: String) {
        captureEnabledBox.title = MacUiText.text("Сделать скриншот", language: language)
        // [ТЗ№4 C8/E1] "Скриншот всего экрана в папку" of 1.4.0 is "Снимок всего экрана" here.
        fullscreenEnabledBox.title = MacUiText.text("Снимок всего экрана", language: language)
        captureField.language = language
        fullscreenField.language = language
        // Port of SPEC §7.6 Q7: not part of the Windows string table (macOS-only limitation notice),
        // so localized inline rather than through the shared dictionary.
        limitationCaption.stringValue =
            language == "en"
            ? "A single modifier key (e.g. just ⌘) cannot be used as a shortcut on macOS — press a full combination."
            : "Одиночный модификатор (например, только ⌘) нельзя назначить сочетанием на macOS — нажмите полную комбинацию."
        needsLayout = true
    }

    override func applyTheme(_ palette: ThemePalette) {
        for box in [captureEnabledBox, fullscreenEnabledBox] { box.contentTintColor = palette.text }
        captureField.palette = palette
        fullscreenField.palette = palette
        suggestChip.palette = palette
        limitationCaption.textColor = palette.textMuted
    }

    override func layout() {
        super.layout()
        var y = bounds.height - 20
        captureEnabledBox.frame = NSRect(x: 0, y: y, width: bounds.width, height: 20)
        y -= 7 + 48
        captureField.frame = NSRect(x: 0, y: y, width: bounds.width, height: 48)
        y -= 20 + 20
        fullscreenEnabledBox.frame = NSRect(x: 0, y: y, width: bounds.width, height: 20)
        y -= 7 + 48
        fullscreenField.frame = NSRect(x: 0, y: y, width: bounds.width, height: 48)
        y -= 10 + 28
        suggestChip.frame = NSRect(x: 0, y: y, width: suggestChip.fittingWidth, height: 28)
        y -= 16 + 32
        limitationCaption.frame = NSRect(x: 0, y: max(0, y), width: bounds.width, height: 32)
    }
}

/// "Сохранение": auto-save, format, the JPEG quality (shown for JPEG alone) and the save folder.
final class SavingTabView: SettingsTabView {
    let autoSaveBox = checkbox("")
    let formatLabel = sectionLabel("")
    let formatPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let qualityLabel = sectionLabel("")
    let qualitySlider = NSSlider(value: 92, minValue: 1, maxValue: 100, target: nil, action: nil)
    let directoryLabel = sectionLabel("")
    let directoryField = NSTextField(frame: .zero)
    let browseButton = NSButton(title: "…", target: nil, action: nil)
    private var language = "ru"

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        formatPopup.addItems(withTitles: ["PNG", "JPEG"])
        qualitySlider.numberOfTickMarks = 100
        qualitySlider.allowsTickMarkValuesOnly = true
        directoryField.font = NSFont.systemFont(ofSize: 13)
        for view in [
            autoSaveBox, formatLabel, formatPopup, qualityLabel, qualitySlider, directoryLabel,
            directoryField, browseButton,
        ] as [NSView] {
            addSubview(view)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The quality caption is built in code, so it is rebuilt every time the window is translated or
    /// the slider moves; PNG has no quality to set and the row goes away with it.
    func updateQuality() {
        let jpeg = formatPopup.indexOfSelectedItem == 1
        qualityLabel.isHidden = !jpeg
        qualitySlider.isHidden = !jpeg
        qualityLabel.stringValue = UiFormat.text(
            MacUiText.text("Качество JPEG: {0} % (меньше, легче файл)", language: language),
            "\(qualitySlider.integerValue)")
    }

    override func applyLocalization(_ language: String) {
        self.language = language
        autoSaveBox.title = MacUiText.text("Автоматически сохранять готовые снимки", language: language)
        autoSaveBox.toolTip = MacUiText.text(
            "Каждый готовый снимок сразу ложится в папку сохранения", language: language)
        formatLabel.stringValue = MacUiText.text("Формат", language: language)
        formatPopup.toolTip = MacUiText.text("JPEG легче, PNG точнее", language: language)
        directoryLabel.stringValue = MacUiText.text("Папка сохранения", language: language)
        directoryField.toolTip = MacUiText.text("Куда падают снимки и пакеты", language: language)
        browseButton.toolTip = MacUiText.text("Выбрать папку", language: language)
        updateQuality()
        needsLayout = true
    }

    override func applyTheme(_ palette: ThemePalette) {
        autoSaveBox.contentTintColor = palette.text
        for label in [formatLabel, qualityLabel, directoryLabel] { label.textColor = palette.text }
    }

    override func layout() {
        super.layout()
        var y = bounds.height - 20
        autoSaveBox.frame = NSRect(x: 0, y: y, width: bounds.width, height: 20)
        y -= 36
        formatLabel.frame = NSRect(x: 0, y: y, width: bounds.width, height: 16)
        y -= 27
        formatPopup.frame = NSRect(x: 0, y: y, width: 140, height: 26)
        y -= 40
        qualityLabel.frame = NSRect(x: 0, y: y, width: bounds.width, height: 16)
        y -= 30
        qualitySlider.frame = NSRect(x: 0, y: y, width: bounds.width, height: 20)
        y -= 32
        directoryLabel.frame = NSRect(x: 0, y: y, width: bounds.width, height: 16)
        y -= 27
        directoryField.frame = NSRect(x: 0, y: y, width: bounds.width - 48, height: 26)
        browseButton.frame = NSRect(x: bounds.width - 40, y: y, width: 40, height: 26)
    }
}

/// "Вид": the same control the wizard shows on its fourth step, with the row of annotation palettes
/// the wizard does not show (G-3, G-4). It scrolls, because the control with the palette row is
/// taller than the tab whenever the window has to open shorter than the height it declares
/// (SPEC-DELTA-5 §5.4 S5-1: 620 cures the cut content, not a monitor that cannot hold it).
final class AppearanceTabView: SettingsTabView {
    let picker = AppearancePickerView(frame: .zero)
    private let scrollView = NSScrollView(frame: .zero)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        picker.showPaletteRow = true
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = picker
        addSubview(scrollView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func applyLocalization(_ language: String) { picker.applyLanguage(language) }

    override func applyTheme(_ palette: ThemePalette) { picker.refreshTheme() }

    /// [A5-1] The only subview of this tab is the scroller, which always fills it: what the tab is
    /// really worth is what the control inside asks for.
    override var smokeContentHeight: CGFloat { picker.fittingHeight }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        let height = max(picker.fittingHeight, bounds.height)
        picker.frame = NSRect(x: 0, y: 0, width: bounds.width, height: height)
        picker.needsLayout = true
    }
}

// MARK: - Small controls

/// A line of text that reads as a way out rather than as a button: the "Пропустить настройку" of the
/// wizard and the "Пройти знакомство заново" of the settings are the same thing.
final class LinkLabel: NSTextField {
    var onClick: (() -> Void)?

    init() {
        super.init(frame: .zero)
        isEditable = false
        isSelectable = false
        isBordered = false
        drawsBackground = false
        font = NSFont.systemFont(ofSize: 12)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func mouseDown(with event: NSEvent) { onClick?() }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

/// The chip beside a shortcut that is switched off: it carries the first free combination and
/// switches the shortcut on with it (G-7, and the same chip on step 2 of the wizard).
final class ChipButton: NSView {
    var onClick: (() -> Void)?
    var palette: ThemePalette = ThemeService.palette(nil) { didSet { refresh() } }
    /// Whether the chip is drawn in the accent (the wizard) or in the elevated tone (the settings).
    var wearsAccent = false { didSet { refresh() } }

    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        label.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        addSubview(label)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var title: String {
        get { label.stringValue }
        set {
            label.stringValue = newValue
            label.sizeToFit()
            needsLayout = true
        }
    }

    var fittingWidth: CGFloat { label.frame.width + 24 }

    override func layout() {
        super.layout()
        label.frame = NSRect(
            x: 12, y: (bounds.height - label.frame.height) / 2, width: label.frame.width,
            height: label.frame.height)
    }

    override func mouseDown(with event: NSEvent) { onClick?() }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    private func refresh() {
        let accent = ThemeService.accent(ThemeService.currentAccent)
        layer?.backgroundColor = (wearsAccent ? accent.soft : palette.elevated).cgColor
        layer?.borderColor = (wearsAccent ? accent.flat : palette.elevatedLine).cgColor
        label.textColor = palette.text
    }
}
