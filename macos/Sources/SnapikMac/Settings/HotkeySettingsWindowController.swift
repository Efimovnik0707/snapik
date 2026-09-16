// Port of `HotkeySettingsWindow.xaml(.cs)`, SPEC §1.17, §6.5, §7.3, §7.4,
// SPEC-DELTA-3 §1.5 G-3, G-6…G-10, G-13.
import AppKit
import SnapikCore

/// The background of a themed window: the surface of the palette, which is a run of colours in four
/// of the six themes, and the line around it.
final class ThemedSurfaceView: NSView {
    var palette: ThemePalette = ThemeService.palette(nil) { didSet { needsDisplay = true } }
    var cornerRadius: CGFloat = ThemeMetrics.outerCornerRadius

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: cornerRadius, yRadius: cornerRadius)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        AppearanceBrush.fill(palette.surface, in: bounds, radius: cornerRadius)
        NSGraphicsContext.restoreGraphicsState()
        palette.surfaceLine.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

@MainActor
final class HotkeySettingsWindowController: NSWindowController, NSWindowDelegate {
    private weak var coordinator: AppCoordinator?
    /// Called once the window has fully closed (Save, Cancel, or the red-close-button-equivalent
    /// path) — after hotkeys have been re-registered (SPEC §1.17 step 4, the C# `finally`).
    var onClosed: (() -> Void)?
    /// [ТЗ№4 A7] What the wizard opened by "Пройти знакомство заново" hands back: the strip is shown
    /// without being activated once the wizard is gone. Wave 2 wires it in `AppCoordinator`.
    var onOnboardingFinished: (() -> Void)?
    /// Whether the window was left through the "Пройти знакомство заново" link (G-13); the smoke run
    /// reads it, and so may the owner.
    private(set) var onboardingRequested = false

    private let surface = ThemedSurfaceView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let tabButtons: [NSButton]
    private let generalTab = GeneralTabView(frame: .zero)
    private let hotkeysTab = HotkeysTabView(frame: .zero)
    private let savingTab = SavingTabView(frame: .zero)
    private let appearanceTab = AppearanceTabView(frame: .zero)
    private let tabContainer = NSView()
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let cancelButton = NSButton(title: "", target: nil, action: nil)
    private let saveButton = NSButton(title: "", target: nil, action: nil)

    private var selectedTabIndex = 0
    private var language: String
    /// The look the window was opened with. The appearance tab repaints the application while it is
    /// being looked at and saves nothing; walking away has to put back the pair it was opened with.
    private let openedTheme: String
    private let openedAccent: String
    private var saved = false
    private var wizard: OnboardingWindowController?

    /// The combinations the chip has offered and the system refused to register. A shortcut another
    /// application holds fails at the registration and nowhere earlier, so the queue learns about it
    /// only after a save was attempted, and the chip moves on to the next candidate.
    private var refusedBySystem: [String] = []
    /// The combination the chip put into the field, if the user took one.
    private var suggested: String?

    private var tabs: [SettingsTabView] { [generalTab, hotkeysTab, savingTab, appearanceTab] }

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        self.language = coordinator.language
        self.openedTheme = ThemeService.normalizeTheme(coordinator.settings.theme)
        self.openedAccent = ThemeService.normalizeAccent(coordinator.settings.accentId)
        let general = NSButton(title: "", target: nil, action: nil)
        let hotkeys = NSButton(title: "", target: nil, action: nil)
        let saving = NSButton(title: "", target: nil, action: nil)
        let look = NSButton(title: "", target: nil, action: nil)
        self.tabButtons = [general, hotkeys, saving, look]

        let window = NSWindow(
            // SPEC-DELTA-2B.md §E4: height grows from 480 to 520 to fit the two new checkboxes.
            // The width is the one Windows gives the same dialog (`HotkeySettingsWindow.xaml:3`,
            // 620x520): the "Вид" tab of SPEC-DELTA-3 G-3 fits in it whole, and its gallery pages by
            // the chevrons on both builds alike, so nothing has to scroll here.
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.title = "Настройки Snapik"
        window.isMovableByWindowBackground = false

        super.init(window: window)
        window.delegate = self
        ThemeService.apply(theme: coordinator.settings.theme, accent: coordinator.settings.accentId)
        buildContent(in: window)
        populateFields(from: coordinator.settings)
        applyLocalization()
        applyTheme()
        window.center()

        coordinator.beginEditingSettings()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildContent(in window: NSWindow) {
        guard let contentView = window.contentView else { return }
        contentView.wantsLayer = true
        surface.frame = contentView.bounds
        surface.autoresizingMask = [.width, .height]
        contentView.addSubview(surface)

        titleLabel.font = NSFont.systemFont(ofSize: 21, weight: .semibold)
        surface.addSubview(titleLabel)

        for (index, button) in tabButtons.enumerated() {
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.cornerRadius = 8
            button.tag = index
            button.target = self
            button.action = #selector(tabClicked(_:))
            surface.addSubview(button)
        }

        for tab in tabs { tabContainer.addSubview(tab) }
        surface.addSubview(tabContainer)

        // The two fields of this window are each other's neighbours: a combination one of them holds
        // is refused in the other while it is being pressed (G-6).
        hotkeysTab.captureField.conflictsWith = [hotkeysTab.fullscreenField]
        hotkeysTab.fullscreenField.conflictsWith = [hotkeysTab.captureField]
        for field in [hotkeysTab.captureField, hotkeysTab.fullscreenField] {
            field.onHotkeyChanged = { [weak self] field in self?.hotkeyRecorded(in: field) }
            field.onBeginRecording = { [weak self] _ in self?.saveButton.keyEquivalent = "" }
            field.onFinishRecording = { [weak self] _ in
                self?.saveButton.keyEquivalent = "\r"
            }
        }
        hotkeysTab.captureEnabledBox.target = self
        hotkeysTab.captureEnabledBox.action = #selector(shortcutSwitchChanged)
        hotkeysTab.fullscreenEnabledBox.target = self
        hotkeysTab.fullscreenEnabledBox.action = #selector(shortcutSwitchChanged)
        hotkeysTab.suggestChip.onClick = { [weak self] in self?.takeSuggestion() }

        generalTab.soundsBox.target = self
        generalTab.soundsBox.action = #selector(soundsChanged)
        generalTab.languageSegment.target = self
        generalTab.languageSegment.action = #selector(languageChanged)
        generalTab.runOnboardingLink.onClick = { [weak self] in self?.runOnboardingClicked() }

        savingTab.browseButton.target = self
        savingTab.browseButton.action = #selector(browseDirectoryClicked)
        savingTab.qualitySlider.target = self
        savingTab.qualitySlider.action = #selector(qualityChanged)
        savingTab.formatPopup.target = self
        savingTab.formatPopup.action = #selector(qualityChanged)

        // The appearance tab repaints what is on screen as it is clicked and saves nothing; the
        // window follows it so that the pair being tried out is the pair being looked at.
        appearanceTab.picker.onThemeChanged = { [weak self] in self?.applyTheme() }
        appearanceTab.picker.onAccentChanged = { [weak self] in self?.applyTheme() }

        errorLabel.font = NSFont.systemFont(ofSize: 12)
        errorLabel.isHidden = true
        surface.addSubview(errorLabel)

        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked)
        surface.addSubview(cancelButton)

        saveButton.target = self
        saveButton.action = #selector(saveClicked)
        saveButton.keyEquivalent = "\r"
        surface.addSubview(saveButton)

        layoutContent(in: surface)
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
        tabContainer.frame = NSRect(
            x: padding, y: bottomAreaHeight, width: width, height: tabsAreaTop - bottomAreaHeight)
        for tab in tabs {
            tab.frame = tabContainer.bounds
            tab.needsLayout = true
        }

        errorLabel.frame = NSRect(x: padding, y: bottomAreaHeight - 32, width: width, height: 24)
        saveButton.frame = NSRect(x: contentView.bounds.width - padding - 100, y: padding, width: 100, height: 34)
        cancelButton.frame = NSRect(x: saveButton.frame.minX - 88, y: padding, width: 80, height: 34)
    }

    private func populateFields(from settings: HotkeySettings) {
        generalTab.startupSwitch.state = LaunchAtLoginService.isEnabled ? .on : .off
        generalTab.notificationsBox.state = settings.showNotifications ? .on : .off
        generalTab.clearStackBox.state = settings.clearStackAfterPaste ? .on : .off
        generalTab.soundsBox.state = settings.playSounds ? .on : .off
        generalTab.volumeSlider.integerValue = max(0, min(100, settings.soundVolume))
        generalTab.updateVolumeRow()
        generalTab.languageSegment.selectedSegment = settings.language == "en" ? 1 : 0

        hotkeysTab.captureEnabledBox.state = settings.captureEnabled ? .on : .off
        hotkeysTab.captureField.currentId = settings.captureId
        hotkeysTab.fullscreenEnabledBox.state = settings.fullscreenSaveEnabled ? .on : .off
        hotkeysTab.fullscreenField.currentId = settings.fullscreenSaveId
        updateShortcutState()

        savingTab.autoSaveBox.state = settings.autoSaveCaptures ? .on : .off
        savingTab.formatPopup.selectItem(at: settings.saveFormat == "jpeg" ? 1 : 0)
        savingTab.qualitySlider.integerValue = max(1, min(100, settings.jpegQuality))
        savingTab.directoryField.stringValue = settings.saveDirectory
        savingTab.updateQuality()

        appearanceTab.picker.selectedTheme = settings.theme
        appearanceTab.picker.selectedAccent = settings.accentId
        appearanceTab.picker.selectedPalette = settings.annotationPalette
    }

    private func applyLocalization() {
        titleLabel.stringValue = MacUiText.text("Настройки", language: language)
        let names = ["Общие", "Клавиши", "Сохранение", "Вид"]
        for (index, button) in tabButtons.enumerated() {
            button.title = MacUiText.text(names[index], language: language)
        }
        for tab in tabs { tab.applyLocalization(language) }
        cancelButton.title = MacUiText.text("Отмена", language: language)
        saveButton.title = MacUiText.text("Сохранить", language: language)
        // Finding 24: two §1.20 dictionary strings otherwise unused anywhere in the port —
        // supplementary accessibility names for the "Клавиши" tab button (a menu-item-like
        // control) and its content pane (the tab's header, for VoiceOver users tabbing in).
        tabButtons[1].setAccessibilityLabel(MacUiText.text("Горячие клавиши…", language: language))
        hotkeysTab.setAccessibilityTitle(MacUiText.text("Настройки клавиш", language: language))
        updateShortcutState()
        showTab(selectedTabIndex)
    }

    /// Repaints the window out of the pair in force: the appearance tab applies a theme as it is
    /// clicked, and this is what follows it.
    private func applyTheme() {
        let palette = ThemeService.palette(ThemeService.currentTheme)
        let accent = ThemeService.accent(ThemeService.currentAccent)
        surface.palette = palette
        titleLabel.textColor = palette.text
        errorLabel.textColor = palette.danger
        for tab in tabs { tab.applyTheme(palette) }
        for (index, button) in tabButtons.enumerated() {
            button.layer?.backgroundColor = (index == selectedTabIndex ? accent.soft : palette.elevated).cgColor
            button.contentTintColor = palette.text
        }
        hotkeysTab.suggestChip.palette = palette
    }

    private func showTab(_ index: Int) {
        selectedTabIndex = index
        for (tabIndex, tab) in tabs.enumerated() { tab.isHidden = tabIndex != index }
        let palette = ThemeService.palette(ThemeService.currentTheme)
        let accent = ThemeService.accent(ThemeService.currentAccent)
        for (buttonIndex, button) in tabButtons.enumerated() {
            button.layer?.backgroundColor = (buttonIndex == index ? accent.soft : palette.elevated).cgColor
        }
    }

    @objc private func tabClicked(_ sender: NSButton) {
        showTab(sender.tag)
    }

    @objc private func qualityChanged() {
        savingTab.updateQuality()
    }

    @objc private func soundsChanged() {
        generalTab.updateVolumeRow()
    }

    @objc private func languageChanged() {
        // The captions built in code follow the language picked in this window, not the one it opened
        // with.
        language = generalTab.languageSegment.selectedSegment == 1 ? "en" : "ru"
        applyLocalization()
        applyTheme()
    }

    @objc private func shortcutSwitchChanged() {
        updateShortcutState()
    }

    // MARK: - The shortcut that is off and the chip beside it (G-7)

    // What the chip offers: the first combination of the queue that neither field holds and nothing
    // has refused. `nil` means the queue is exhausted and the chip has nothing to say.
    private func suggestedShortcut() -> String? {
        HotkeyRules.suggestFree(taken: [hotkeysTab.captureField.currentId] + refusedBySystem)
    }

    // A shortcut that is switched off shows "Не назначено", and the one for the whole screen also
    // shows the chip that switches it on.
    private func updateShortcutState() {
        hotkeysTab.captureField.isAssigned = hotkeysTab.captureEnabledBox.state == .on
        hotkeysTab.fullscreenField.isAssigned = hotkeysTab.fullscreenEnabledBox.state == .on
        let suggestion = hotkeysTab.fullscreenField.isAssigned ? nil : suggestedShortcut()
        hotkeysTab.suggestChip.isHidden = suggestion == nil
        guard let suggestion else { return }
        let label = HotkeyRecorderField.labelParts(forId: suggestion).joined(separator: " ")
        hotkeysTab.suggestChip.title = UiFormat.text(
            MacUiText.text("Предложить: {0}", language: language), label)
        hotkeysTab.suggestChip.toolTip = suggestion
        hotkeysTab.needsLayout = true
    }

    private func takeSuggestion() {
        guard let suggestion = suggestedShortcut() else { return }
        suggested = suggestion
        hotkeysTab.fullscreenField.currentId = suggestion
        hotkeysTab.fullscreenEnabledBox.state = .on
        errorLabel.isHidden = true
        updateShortcutState()
    }

    // A combination the chip put there and the system would not take is dropped again: the shortcut
    // goes back to "Не назначено" and the chip offers the next candidate.
    private func refuseSuggestion() {
        guard hotkeysTab.fullscreenEnabledBox.state == .on, let suggestion = suggested,
            HotkeyRules.sameGesture(hotkeysTab.fullscreenField.currentId, suggestion)
        else { return }
        refusedBySystem.append(suggestion)
        hotkeysTab.fullscreenEnabledBox.state = .off
        updateShortcutState()
    }

    // The field records the key itself; the window only clears the error it may still show. A
    // combination pressed into a field that was switched off is a request for that shortcut.
    private func hotkeyRecorded(in field: HotkeyRecorderField) {
        errorLabel.isHidden = true
        if field === hotkeysTab.captureField { hotkeysTab.captureEnabledBox.state = .on }
        if field === hotkeysTab.fullscreenField { hotkeysTab.fullscreenEnabledBox.state = .on }
        updateShortcutState()
        window?.makeFirstResponder(saveButton)
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

    /// [ТЗ№4 E2] The link at the bottom of "Общие": the dialog is left without saving — so the theme
    /// it was playing with goes back — and the wizard opens on the file as it is on disk.
    private func runOnboardingClicked() {
        requestOnboarding()
        window?.close()
    }

    private func requestOnboarding() {
        onboardingRequested = true
    }

    private func openOnboarding() {
        guard let coordinator else { return }
        let controller = OnboardingWindowController(coordinator: coordinator)
        wizard = controller
        controller.onFinished = { [weak self] in
            self?.wizard = nil
            self?.onOnboardingFinished?()
        }
        controller.showWindow(self)
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

        // A shortcut recorded before the neighbouring field took it is caught here, by the gesture the
        // two ids parse to, and not by the registration: the system only refuses the second one while
        // both are switched on, and its message blames another application (G-6).
        if hotkeysTab.captureEnabledBox.state == .on, hotkeysTab.fullscreenEnabledBox.state == .on,
            HotkeyRules.sameGesture(hotkeysTab.captureField.currentId, hotkeysTab.fullscreenField.currentId)
        {
            hotkeysTab.captureField.showConflict()
            hotkeysTab.fullscreenField.showConflict()
            showError("Одно сочетание на два действия. Поменяй одно из них.")
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
            try applyStartup()
            try candidate.save(path: coordinator.workspace.settingsPath)
            coordinator.applySettings(candidate)
            saved = true
            window?.close()
        } catch let hotkeyError as GlobalHotkeyService.HotkeyError {
            coordinator.hotkeyService.unregisterAll()
            // A combination the chip offered and the system refused is withdrawn, and the queue moves
            // on to the next candidate.
            refuseSuggestion()
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
        } catch let startupError as StartupUnavailable {
            coordinator.hotkeyService.unregisterAll()
            generalTab.startupUnavailableLabel.isHidden = false
            generalTab.needsLayout = true
            showError(
                "\(MacUiText.text("Не удалось изменить автозапуск", language: language)): \(startupError.reason)")
        } catch {
            coordinator.hotkeyService.unregisterAll()
            StartupLog.write(
                coordinator.options,
                "Settings save failed for capture=\(candidate.captureId) fullscreenSave=\(candidate.fullscreenSaveId): \(error)")
            showError("Не удалось сохранить настройки: \(error)")
        }
    }

    /// The login item is a registration of the system and not a preference of the settings file: it
    /// is read when the window opens and written when it saves. A machine that will not take it
    /// leaves the line saying so, the way the wizard does.
    struct StartupUnavailable: Error { let reason: String }

    private func applyStartup() throws {
        let wanted = generalTab.startupSwitch.state == .on
        guard wanted != LaunchAtLoginService.isEnabled else { return }
        do {
            try LaunchAtLoginService.setEnabled(wanted)
        } catch {
            throw StartupUnavailable(reason: error.localizedDescription)
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
        // `rememberRegion` and `captureCursor` have no row of their own any more (G-8): the two
        // preferences travel from the file this window was opened with, untouched. So do
        // `confirmSessionDiscard`, `packageSaveDirectory` and `packageCreateSubfolder`, which the
        // dialogs that own them write.
        candidate.clearStackAfterPaste = generalTab.clearStackBox.state == .on
        candidate.playSounds = generalTab.soundsBox.state == .on
        candidate.soundVolume = generalTab.volumeSlider.integerValue
        candidate.autoSaveCaptures = savingTab.autoSaveBox.state == .on
        candidate.saveFormat = savingTab.formatPopup.indexOfSelectedItem == 1 ? "jpeg" : "png"
        candidate.jpegQuality = savingTab.qualitySlider.integerValue
        // Port of SPEC-DELTA-2B §E4: expand `~` and standardize before persisting, so a manually
        // typed `~/Pictures/Snapik` resolves the same as the folder picker's absolute path.
        candidate.saveDirectory =
            URL(fileURLWithPath: (savingTab.directoryField.stringValue as NSString).expandingTildeInPath).standardizedFileURL.path
        candidate.language = generalTab.languageSegment.selectedSegment == 1 ? "en" : "ru"
        candidate.theme = appearanceTab.picker.selectedTheme
        candidate.accentId = appearanceTab.picker.selectedAccent
        candidate.annotationPalette = appearanceTab.picker.selectedPalette
        return candidate
    }

    // MARK: - Smoke hooks

    var smokeTabCount: Int { tabButtons.count }

    var smokeAppearancePicker: AppearancePickerView { appearanceTab.picker }

    func smokeSelectTab(_ index: Int) { showTab(index) }

    /// One combination written into both fields is refused, both of them go red and nothing is saved.
    /// The keys are given as a preset and as a custom id of the same gesture, so the check also proves
    /// the comparison is by gesture and not by text.
    func smokeRunConflictProbe() -> Bool {
        hotkeysTab.captureField.currentId = "ctrl-alt-s"
        hotkeysTab.fullscreenField.currentId = "custom:3:83"
        hotkeysTab.captureEnabledBox.state = .on
        hotkeysTab.fullscreenEnabledBox.state = .on
        saveClicked()
        return !saved && hotkeysTab.captureField.showsConflict && hotkeysTab.fullscreenField.showsConflict
            && !errorLabel.isHidden
    }

    /// A clean installation: the shortcut of the whole screen is off, the field says so, and the chip
    /// offers the first combination of the queue; taking it switches the shortcut on.
    func smokeRunSuggestProbe() -> Bool {
        hotkeysTab.fullscreenEnabledBox.state = .off
        updateShortcutState()
        guard !hotkeysTab.fullscreenField.isAssigned, !hotkeysTab.suggestChip.isHidden,
            let offered = suggestedShortcut()
        else { return false }
        takeSuggestion()
        return hotkeysTab.fullscreenEnabledBox.state == .on
            && HotkeyRules.sameGesture(hotkeysTab.fullscreenField.currentId, offered)
            && hotkeysTab.suggestChip.isHidden
    }

    /// The link of [ТЗ№4 E2] asks for the wizard and saves nothing of its own.
    func smokeRequestOnboarding() -> Bool {
        requestOnboarding()
        let asked = onboardingRequested
        onboardingRequested = false
        return asked && !saved
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // The appearance tab repaints the application while it is being looked at and saves nothing;
        // walking away from the window has to put back the pair it was opened with (G-3).
        if !saved { ThemeService.apply(theme: openedTheme, accent: openedAccent) }
        coordinator?.endEditingSettings()
        onClosed?()
        // The wizard is opened after the dialog is gone: two windows of this size one over the other
        // are not worth the link at the bottom of a tab (`A-onboarding.md` §E2).
        if onboardingRequested {
            onboardingRequested = false
            openOnboarding()
        }
    }
}
