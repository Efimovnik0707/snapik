// Port of `HotkeySettingsWindow.xaml(.cs)`, SPEC §1.17, §6.5, §7.3, §7.4.
import AppKit
import SnapBriefCore

@MainActor
final class HotkeySettingsWindowController: NSWindowController, NSWindowDelegate {
    private weak var coordinator: AppCoordinator?
    /// Called once the window has fully closed (Save, Cancel, or the red-close-button-equivalent
    /// path) — after hotkeys have been re-registered (SPEC §1.17 step 4, the C# `finally`).
    var onClosed: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let tabButtons: [NSButton]
    private let generalTab = GeneralTabView(frame: .zero)
    private let hotkeysTab = HotkeysTabView(frame: .zero)
    private let savingTab = SavingTabView(frame: .zero)
    private let tabContainer = NSView()
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let cancelButton = NSButton(title: "", target: nil, action: nil)
    private let saveButton = NSButton(title: "", target: nil, action: nil)

    private var selectedTabIndex = 0
    private let language: String

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        self.language = coordinator.language
        let general = NSButton(title: "", target: nil, action: nil)
        let hotkeys = NSButton(title: "", target: nil, action: nil)
        let saving = NSButton(title: "", target: nil, action: nil)
        self.tabButtons = [general, hotkeys, saving]

        let window = NSWindow(
            // SPEC-DELTA-2B.md §E4: height grows from 480 to 520 to fit the two new checkboxes
            // ("Звуки захвата и стопки" on "Общие", "Автоматически сохранять готовые снимки" on
            // "Сохранение") without cramping either tab.
            contentRect: NSRect(x: 0, y: 0, width: 530, height: 520),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.title = "Настройки SnapBrief"
        window.isMovableByWindowBackground = false

        super.init(window: window)
        window.delegate = self
        buildContent(in: window)
        populateFields(from: coordinator.settings)
        applyLocalization()
        window.center()

        coordinator.beginEditingSettings()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildContent(in window: NSWindow) {
        guard let contentView = window.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = DarkPalette.settingsWindowBackground.cgColor
        contentView.layer?.borderColor = DarkPalette.settingsWindowBorder.cgColor
        contentView.layer?.borderWidth = 1
        contentView.layer?.cornerRadius = ThemeMetrics.outerCornerRadius

        titleLabel.font = NSFont.systemFont(ofSize: 21, weight: .semibold)
        titleLabel.textColor = DarkPalette.primaryText
        contentView.addSubview(titleLabel)

        for (index, button) in tabButtons.enumerated() {
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.cornerRadius = 8
            button.contentTintColor = DarkPalette.primaryText
            button.tag = index
            button.target = self
            button.action = #selector(tabClicked(_:))
            contentView.addSubview(button)
        }

        tabContainer.addSubview(generalTab)
        tabContainer.addSubview(hotkeysTab)
        tabContainer.addSubview(savingTab)
        contentView.addSubview(tabContainer)

        hotkeysTab.captureField.delegate = self
        hotkeysTab.fullscreenField.delegate = self
        savingTab.browseButton.target = self
        savingTab.browseButton.action = #selector(browseDirectoryClicked)
        savingTab.qualitySlider.target = self
        savingTab.qualitySlider.action = #selector(qualityChanged)

        errorLabel.textColor = DarkPalette.errorText
        errorLabel.font = NSFont.systemFont(ofSize: 12)
        errorLabel.isHidden = true
        contentView.addSubview(errorLabel)

        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked)
        contentView.addSubview(cancelButton)

        saveButton.target = self
        saveButton.action = #selector(saveClicked)
        saveButton.keyEquivalent = "\r"
        contentView.addSubview(saveButton)

        layoutContent(in: contentView)
    }

    private func layoutContent(in contentView: NSView) {
        let padding: CGFloat = 24
        let width = contentView.bounds.width - padding * 2
        titleLabel.frame = NSRect(x: padding, y: contentView.bounds.height - padding - 30, width: width, height: 30)

        let tabsTop = titleLabel.frame.minY - 10
        var x = padding
        for button in tabButtons {
            let buttonWidth: CGFloat = 100
            button.frame = NSRect(x: x, y: tabsTop - 34, width: buttonWidth, height: 34)
            x += buttonWidth + 6
        }

        let tabsAreaTop = tabsTop - 34 - 10
        let bottomAreaHeight: CGFloat = 34 + 40
        tabContainer.frame = NSRect(x: padding, y: bottomAreaHeight, width: width, height: tabsAreaTop - bottomAreaHeight)
        for tab in [generalTab, hotkeysTab, savingTab] as [NSView] {
            tab.frame = tabContainer.bounds
        }

        errorLabel.frame = NSRect(x: padding, y: bottomAreaHeight - 32, width: width, height: 24)
        saveButton.frame = NSRect(x: contentView.bounds.width - padding - 100, y: padding, width: 100, height: 34)
        cancelButton.frame = NSRect(x: saveButton.frame.minX - 88, y: padding, width: 80, height: 34)
    }

    private func populateFields(from settings: HotkeySettings) {
        generalTab.notificationsBox.state = settings.showNotifications ? .on : .off
        generalTab.rememberRegionBox.state = settings.rememberRegion ? .on : .off
        generalTab.captureCursorBox.state = settings.captureCursor ? .on : .off
        generalTab.soundsBox.state = settings.playSounds ? .on : .off
        generalTab.languagePopup.selectItem(at: settings.language == "en" ? 1 : 0)

        hotkeysTab.captureEnabledBox.state = settings.captureEnabled ? .on : .off
        hotkeysTab.captureField.currentId = settings.captureId
        hotkeysTab.fullscreenEnabledBox.state = settings.fullscreenSaveEnabled ? .on : .off
        hotkeysTab.fullscreenField.currentId = settings.fullscreenSaveId

        savingTab.autoSaveBox.state = settings.autoSaveCaptures ? .on : .off
        savingTab.formatPopup.selectItem(at: settings.saveFormat == "jpeg" ? 1 : 0)
        let quality = max(1, min(100, settings.jpegQuality))
        savingTab.qualitySlider.integerValue = quality
        savingTab.qualityValueLabel.stringValue = "\(quality)"
        savingTab.directoryField.stringValue = settings.saveDirectory
    }

    private func applyLocalization() {
        titleLabel.stringValue = MacUiText.text("Настройки", language: language)
        let names = ["Общие", "Клавиши", "Сохранение"]
        for (index, button) in tabButtons.enumerated() {
            button.title = MacUiText.text(names[index], language: language)
            button.layer?.backgroundColor = (index == selectedTabIndex ? NSColor(hex: "#284B78") : NSColor(hex: "#252B35")).cgColor
        }
        generalTab.applyLocalization(language)
        hotkeysTab.applyLocalization(language)
        savingTab.applyLocalization(language)
        generalTab.languagePopup.selectItem(at: language == "en" ? 1 : 0)
        cancelButton.title = MacUiText.text("Отмена", language: language)
        saveButton.title = MacUiText.text("Сохранить", language: language)
        // Finding 24: two §1.20 dictionary strings otherwise unused anywhere in the port —
        // supplementary accessibility names for the "Клавиши" tab button (a menu-item-like
        // control) and its content pane (the tab's header, for VoiceOver users tabbing in).
        tabButtons[1].setAccessibilityLabel(MacUiText.text("Горячие клавиши…", language: language))
        hotkeysTab.setAccessibilityTitle(MacUiText.text("Настройки клавиш", language: language))
        showTab(selectedTabIndex)
    }

    private func showTab(_ index: Int) {
        selectedTabIndex = index
        generalTab.isHidden = index != 0
        hotkeysTab.isHidden = index != 1
        savingTab.isHidden = index != 2
        for (buttonIndex, button) in tabButtons.enumerated() {
            button.layer?.backgroundColor = (buttonIndex == index ? NSColor(hex: "#284B78") : NSColor(hex: "#252B35")).cgColor
        }
    }

    @objc private func tabClicked(_ sender: NSButton) {
        showTab(sender.tag)
    }

    @objc private func qualityChanged() {
        savingTab.qualityValueLabel.stringValue = "\(savingTab.qualitySlider.integerValue)"
    }

    @objc private func browseDirectoryClicked() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = URL(fileURLWithPath: savingTab.directoryField.stringValue)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        savingTab.directoryField.stringValue = url.path
    }

    @objc private func cancelClicked() {
        window?.close()
    }

    /// Port of `OnSave` (`:152-173`): build the candidate, try registering both hotkeys, save the
    /// file; on any failure show the matching error text and keep the dialog open (SPEC §1.17).
    @objc private func saveClicked() {
        guard let coordinator else { return }

        // Port of `:160-161` (SPEC-DELTA-2.md §1.8, SPEC-DELTA-2B.md §E4): an empty save folder is
        // rejected before anything else — hotkeys are never touched and the dialog stays open.
        guard !savingTab.directoryField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showError(MacUiText.text("Укажите папку сохранения.", language: language))
            return
        }

        let candidate = buildCandidateSettings()

        coordinator.hotkeyService.unregisterAll()
        do {
            if candidate.captureEnabled {
                try coordinator.hotkeyService.register(name: "capture", identifier: HotkeyIdentifier.parse(candidate.captureId))
            }
            if candidate.fullscreenSaveEnabled {
                try coordinator.hotkeyService.register(
                    name: "fullscreen-save", identifier: HotkeyIdentifier.parse(candidate.fullscreenSaveId))
            }
            try candidate.save(path: coordinator.workspace.settingsPath)
            coordinator.applySettings(candidate)
            window?.close()
        } catch let hotkeyError as GlobalHotkeyService.HotkeyError {
            coordinator.hotkeyService.unregisterAll()
            let text =
                hotkeyError.isConflict
                ? "Эта клавиша уже занята. Освободите её в другом приложении или выберите другую."
                : "Не удалось назначить сочетание. Возможно, оно уже занято — нажмите другое."
            // Finding 17 (SPEC §1.17 step 3): every registration error is also written to
            // startup.log, tagged with the hotkey combination that was being assigned.
            StartupLog.write(
                coordinator.options,
                "Hotkey registration failed for capture=\(candidate.captureId) fullscreenSave=\(candidate.fullscreenSaveId): \(hotkeyError)")
            showError(text)
        } catch {
            coordinator.hotkeyService.unregisterAll()
            StartupLog.write(
                coordinator.options,
                "Settings save failed for capture=\(candidate.captureId) fullscreenSave=\(candidate.fullscreenSaveId): \(error)")
            showError("Не удалось сохранить настройки: \(error)")
        }
    }

    /// These conflict/save-error strings are not part of the §1.20 dictionary (like the other
    /// status strings, they stay Russian regardless of interface language — see
    /// `StatusStrings.swift`).
    private func showError(_ text: String) {
        errorLabel.stringValue = text
        errorLabel.isHidden = false
    }

    private func buildCandidateSettings() -> HotkeySettings {
        var candidate = coordinator?.settings ?? HotkeySettings.default
        candidate.captureId = hotkeysTab.captureField.currentId
        candidate.fullscreenSaveId = hotkeysTab.fullscreenField.currentId
        candidate.captureEnabled = hotkeysTab.captureEnabledBox.state == .on
        candidate.fullscreenSaveEnabled = hotkeysTab.fullscreenEnabledBox.state == .on
        candidate.showNotifications = generalTab.notificationsBox.state == .on
        candidate.rememberRegion = generalTab.rememberRegionBox.state == .on
        candidate.captureCursor = generalTab.captureCursorBox.state == .on
        candidate.playSounds = generalTab.soundsBox.state == .on
        candidate.autoSaveCaptures = savingTab.autoSaveBox.state == .on
        candidate.saveFormat = savingTab.formatPopup.indexOfSelectedItem == 1 ? "jpeg" : "png"
        candidate.jpegQuality = savingTab.qualitySlider.integerValue
        // Port of SPEC-DELTA-2B §E4: expand `~` and standardize before persisting, so a manually
        // typed `~/Pictures/SnapBrief` resolves the same as the folder picker's absolute path.
        candidate.saveDirectory =
            URL(fileURLWithPath: (savingTab.directoryField.stringValue as NSString).expandingTildeInPath).standardizedFileURL.path
        candidate.language = generalTab.languagePopup.indexOfSelectedItem == 1 ? "en" : "ru"
        return candidate
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        coordinator?.endEditingSettings()
        onClosed?()
    }
}

extension HotkeySettingsWindowController: HotkeyRecorderFieldDelegate {
    func hotkeyRecorderField(_ field: HotkeyRecorderField, didRecord id: String) {
        // Value already stored on the field itself; nothing else to update here.
    }

    /// Finding 8: while a field is recording, every keystroke — including Enter — belongs to the
    /// recording (SPEC §7.3), so the window's default button must stop reacting to Enter until
    /// recording ends.
    func hotkeyRecorderFieldDidBeginRecording(_ field: HotkeyRecorderField) {
        saveButton.keyEquivalent = ""
    }

    func hotkeyRecorderFieldDidFinishRecording(_ field: HotkeyRecorderField) {
        saveButton.keyEquivalent = "\r"
        window?.makeFirstResponder(saveButton)
    }
}
