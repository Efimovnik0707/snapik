// Port of the three `HotkeySettingsWindow` tabs ("Общие", "Клавиши", "Сохранение"), SPEC §6.5.
import AppKit
import SnapikCore

private func checkbox(_ title: String) -> NSButton {
    let button = NSButton(checkboxWithTitle: title, target: nil, action: nil)
    button.font = NSFont.systemFont(ofSize: 13)
    button.contentTintColor = DarkPalette.primaryText
    return button
}

private func sectionLabel(_ title: String) -> NSTextField {
    let field = NSTextField(labelWithString: title)
    field.textColor = DarkPalette.secondaryTextBF
    field.font = NSFont.systemFont(ofSize: 13)
    return field
}

/// "Общие": notifications / remember-region / capture-cursor checkboxes + language popup.
final class GeneralTabView: NSView {
    let notificationsBox = checkbox("")
    let rememberRegionBox = checkbox("")
    let captureCursorBox = checkbox("")
    /// SPEC-DELTA-2.md §1.8, SPEC-DELTA-2B.md §E4: "Звуки захвата и стопки", placed after
    /// `captureCursorBox` (matches `HotkeySettingsWindow.xaml:19`'s "Общие" tab order).
    let soundsBox = checkbox("")
    let languageLabel = sectionLabel("")
    let languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for view in [notificationsBox, rememberRegionBox, captureCursorBox, soundsBox, languageLabel, languagePopup] {
            addSubview(view)
        }
        languagePopup.addItems(withTitles: ["Русский", "English"])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func applyLocalization(_ language: String) {
        notificationsBox.title = MacUiText.text("Уведомления о копировании и сохранении", language: language)
        rememberRegionBox.title = MacUiText.text("Запоминать последнюю область", language: language)
        captureCursorBox.title = MacUiText.text("Захватывать курсор", language: language)
        soundsBox.title = MacUiText.text("Звуки захвата и стопки", language: language)
        languageLabel.stringValue = MacUiText.text("Язык", language: language)
    }

    override func layout() {
        super.layout()
        var y = bounds.height - 10 - 20
        notificationsBox.frame = NSRect(x: 0, y: y, width: bounds.width, height: 20)
        y -= 36
        rememberRegionBox.frame = NSRect(x: 0, y: y, width: bounds.width, height: 20)
        y -= 36
        captureCursorBox.frame = NSRect(x: 0, y: y, width: bounds.width, height: 20)
        y -= 36
        soundsBox.frame = NSRect(x: 0, y: y, width: bounds.width, height: 20)
        y -= 32
        languageLabel.frame = NSRect(x: 0, y: y, width: bounds.width, height: 16)
        y -= 27
        languagePopup.frame = NSRect(x: 0, y: y, width: 180, height: 26)
    }
}

/// "Клавиши": capture/fullscreen-save toggles + recorder fields, plus the Q7 limitation caption.
final class HotkeysTabView: NSView {
    let captureEnabledBox = checkbox("")
    let captureField = HotkeyRecorderField(frame: .zero)
    let fullscreenEnabledBox = checkbox("")
    let fullscreenField = HotkeyRecorderField(frame: .zero)
    let limitationCaption = NSTextField(wrappingLabelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for view in [captureEnabledBox, captureField, fullscreenEnabledBox, fullscreenField, limitationCaption] {
            addSubview(view)
        }
        limitationCaption.textColor = DarkPalette.secondaryText9A
        limitationCaption.font = NSFont.systemFont(ofSize: 11)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func applyLocalization(_ language: String) {
        captureEnabledBox.title = MacUiText.text("Захват области", language: language)
        fullscreenEnabledBox.title = MacUiText.text("Быстро сохранить весь экран", language: language)
        captureField.language = language
        fullscreenField.language = language
        // Port of SPEC §7.6 Q7: not part of the Windows string table (macOS-only limitation
        // notice), so localized inline rather than through `MacUiText`.
        limitationCaption.stringValue =
            language == "en"
            ? "A single modifier key (e.g. just ⌘) cannot be used as a shortcut on macOS — press a full combination."
            : "Одиночный модификатор (например, только ⌘) нельзя назначить сочетанием на macOS — нажмите полную комбинацию."
    }

    override func layout() {
        super.layout()
        var y = bounds.height - 10 - 20
        captureEnabledBox.frame = NSRect(x: 0, y: y, width: bounds.width, height: 20)
        y -= 27
        captureField.frame = NSRect(x: 0, y: y - 34, width: bounds.width, height: 34)
        y -= 34 + 20
        fullscreenEnabledBox.frame = NSRect(x: 0, y: y, width: bounds.width, height: 20)
        y -= 27
        fullscreenField.frame = NSRect(x: 0, y: y - 34, width: bounds.width, height: 34)
        y -= 34 + 16
        limitationCaption.frame = NSRect(x: 0, y: max(0, y - 30), width: bounds.width, height: 30)
    }
}

/// "Сохранение": format popup, JPEG-quality slider, save-directory field + browse button.
final class SavingTabView: NSView {
    /// SPEC-DELTA-2.md §1.8, SPEC-DELTA-2B.md §E4: "Автоматически сохранять готовые снимки", first
    /// control on "Сохранение" (matches `HotkeySettingsWindow.xaml:30`'s tab order).
    let autoSaveBox = checkbox("")
    let formatLabel = sectionLabel("")
    let formatPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let qualityLabel = sectionLabel("")
    let qualityValueLabel = NSTextField(labelWithString: "90")
    let qualitySlider = NSSlider(value: 90, minValue: 1, maxValue: 100, target: nil, action: nil)
    let directoryLabel = sectionLabel("")
    let directoryField = NSTextField()
    let browseButton = NSButton(title: "…", target: nil, action: nil)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        formatPopup.addItems(withTitles: ["PNG", "JPEG"])
        qualitySlider.numberOfTickMarks = 100
        qualitySlider.allowsTickMarkValuesOnly = true
        qualityValueLabel.alignment = .right
        directoryField.font = NSFont.systemFont(ofSize: 13)
        browseButton.toolTip = "Выбрать папку"

        for view in [
            autoSaveBox, formatLabel, formatPopup, qualityLabel, qualityValueLabel, qualitySlider,
            directoryLabel, directoryField, browseButton,
        ] {
            addSubview(view)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func applyLocalization(_ language: String) {
        autoSaveBox.title = MacUiText.text("Автоматически сохранять готовые снимки", language: language)
        formatLabel.stringValue = MacUiText.text("Формат", language: language)
        qualityLabel.stringValue = MacUiText.text("Качество JPEG", language: language)
        directoryLabel.stringValue = MacUiText.text("Папка сохранения", language: language)
        browseButton.toolTip = MacUiText.text("Выбрать папку", language: language)
    }

    override func layout() {
        super.layout()
        var y = bounds.height - 10 - 20
        autoSaveBox.frame = NSRect(x: 0, y: y, width: bounds.width, height: 20)
        y -= 36
        formatLabel.frame = NSRect(x: 0, y: y, width: bounds.width, height: 16)
        y -= 27
        formatPopup.frame = NSRect(x: 0, y: y, width: 140, height: 26)
        y -= 40
        qualityLabel.frame = NSRect(x: 0, y: y, width: bounds.width - 40, height: 16)
        qualityValueLabel.frame = NSRect(x: bounds.width - 40, y: y, width: 40, height: 16)
        y -= 30
        qualitySlider.frame = NSRect(x: 0, y: y, width: bounds.width, height: 20)
        y -= 32
        directoryLabel.frame = NSRect(x: 0, y: y, width: bounds.width, height: 16)
        y -= 27
        directoryField.frame = NSRect(x: 0, y: y, width: bounds.width - 48, height: 26)
        browseButton.frame = NSRect(x: bounds.width - 40, y: y, width: 40, height: 26)
    }
}
