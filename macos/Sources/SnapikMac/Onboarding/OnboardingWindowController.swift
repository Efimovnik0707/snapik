// Port of `src/Snapik.App/OnboardingWindow.xaml(.cs)`, SPEC-DELTA-3 §1.6 O-1, O-2, O-5, O-6, O-8
// and `tasks/tz-005-details/A-onboarding.md` §A1, §A2, §A3, §A7, §E2.
import AppKit
import SnapikCore

/// The wizard of the first run: the language, the capture shortcut, the login item, the look and an
/// animated hint about the whole scenario. Five steps live in one container and are shown by index.
///
/// It is a window of its own rather than a page of the settings: the strip hides itself before this
/// runs, and a window owned by a hidden window would end up behind everything. The rounding and the
/// shadow are the system's — nothing draws a second contour, and the whole titlebar drags the window
/// (SPEC-DELTA-3 §4, the Windows `WindowChrome` block is not ported).
@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    /// Bumping this shows the wizard again to everyone who has already seen the older one.
    static let currentVersion = 3
    static let stepCount = 5
    /// Below this the wizard would be a strip of chrome; the content scrolls instead.
    private static let minimumUsefulHeight: CGFloat = 360

    private weak var coordinator: AppCoordinator?
    // The menu bar opens the slides alone: no language, no shortcut, no steps, one "Готово" button.
    private let howToOnly: Bool
    private var appliedCaptureId: String
    // The free combination the chip of step 2 offers, or nil while nothing refuses the current one.
    private var suggestedCaptureId: String?
    // The theme, the accent and the language the wizard opened with, to go back to if the user skips
    // the setup ([ТЗ№4 E2]: "Пропустить" must not write the language either).
    private let openedTheme: String
    private let openedAccent: String
    private let openedLanguage: String
    private var settings: HotkeySettings
    private var language: String
    private var step = 0
    // Whether "Начать" or "Пропустить настройку" is closing the window, so that every other way of
    // closing it can be answered as a skip.
    private var closedByButton = false

    /// Applies what the wizard has collected (the shortcut is registered here, so a conflict is
    /// reported before the user leaves the step) and answers with the error to show, or nil. Wave 2
    /// may hand its own in; without one the wizard registers and writes the file itself.
    var onApply: ((HotkeySettings) -> String?)?
    /// [ТЗ№4 A7] The wizard is gone: "Начать", "Пропустить", the cross and Cmd+W all end here, and the
    /// strip is shown without being activated. Wave 2 binds it to
    /// `EdgeStackWindowController.showStackWithoutActivation()`.
    var onFinished: (() -> Void)?

    private let surface = ThemedSurfaceView()
    private let scrollView = NSScrollView(frame: .zero)
    private let stepsContainer = OnboardingKeyView(frame: .zero)
    private let welcomeStep = OnboardingWelcomeStepView(frame: .zero)
    private let hotkeyStep = OnboardingHotkeyStepView(frame: .zero)
    private let startupStep = OnboardingStartupStepView(frame: .zero)
    private let appearanceStep = OnboardingAppearanceStepView(frame: .zero)
    private let slides = HowToSlidesView(frame: .zero)
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let stepLabel = NSTextField(labelWithString: "")
    private let skipLink = LinkLabel()
    private let backButton = NSButton(title: "", target: nil, action: nil)
    private let nextButton = NSButton(title: "", target: nil, action: nil)
    private let startButton = NSButton(title: "", target: nil, action: nil)

    private var steps: [NSView] { [welcomeStep, hotkeyStep, startupStep, appearanceStep, slides] }

    init(coordinator: AppCoordinator, howToOnly: Bool = false, settingsFileExists: Bool = true) {
        self.coordinator = coordinator
        self.howToOnly = howToOnly
        self.settings = coordinator.settings
        self.appliedCaptureId = coordinator.settings.captureId
        self.openedTheme = ThemeService.normalizeTheme(coordinator.settings.theme)
        self.openedAccent = ThemeService.normalizeAccent(coordinator.settings.accentId)
        let language = Self.suggestedLanguage(
            settingsFileExists: settingsFileExists, settings: coordinator.settings,
            cultureLanguage: Locale.current.language.languageCode?.identifier ?? "en")
        self.language = language
        self.openedLanguage = language

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 600),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Snapik"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.level = .normal
        super.init(window: window)
        window.delegate = self
        ThemeService.apply(theme: coordinator.settings.theme, accent: coordinator.settings.accentId)
        buildContent(in: window)
        showStep(howToOnly ? Self.stepCount - 1 : 0)
        applyLanguage(language)
        applyTheme()
        place(window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Rules shared with the strip

    /// The wizard opens once per version: a machine without a settings file has never seen it, and a
    /// newer version shows it again. A demo or a smoke run never shows it.
    static func shouldShowOnboarding(settingsFileExists: Bool, settings: HotkeySettings, demo: Bool) -> Bool {
        !demo && (!settingsFileExists || settings.onboardingVersion < currentVersion)
    }

    /// A Russian system gives Russian, every other locale gives English: the interface has two
    /// languages, and a Ukrainian or Spanish user is not served by guessing Russian for them.
    static func languageForCulture(_ twoLetterIsoLanguageName: String) -> String {
        twoLetterIsoLanguageName == "ru" ? "ru" : "en"
    }

    /// The language the wizard opens in. The locale is a guess, and it is only made where there is
    /// nothing to go on: no settings file, nothing chosen in it.
    static func suggestedLanguage(
        settingsFileExists: Bool, settings: HotkeySettings, cultureLanguage: String
    ) -> String {
        let chosen = (settings.language == "ru" || settings.language == "en") ? settings.language : nil
        let seen = settingsFileExists || settings.onboardingVersion > 0
        if seen, let chosen { return chosen }
        return languageForCulture(cultureLanguage)
    }

    // MARK: - Building

    private func buildContent(in window: NSWindow) {
        guard let contentView = window.contentView else { return }
        contentView.wantsLayer = true
        surface.cornerRadius = 0
        surface.frame = contentView.bounds
        surface.autoresizingMask = [.width, .height]
        contentView.addSubview(surface)

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = stepsContainer
        stepsContainer.onArrowKey = { [weak self] delta in self?.handleNavigationKey(delta) ?? false }
        for view in steps { stepsContainer.addSubview(view) }
        surface.addSubview(scrollView)

        welcomeStep.languageSegment.target = self
        welcomeStep.languageSegment.action = #selector(languageSegmentChanged)

        hotkeyStep.field.onHotkeyChanged = { [weak self] _ in
            self?.errorLabel.isHidden = true
            self?.refreshCaptureConflict()
        }
        hotkeyStep.suggestChip.onClick = { [weak self] in self?.takeSuggestion() }

        errorLabel.font = NSFont.systemFont(ofSize: 12)
        errorLabel.isHidden = true
        surface.addSubview(errorLabel)

        stepLabel.font = NSFont.systemFont(ofSize: 13)
        surface.addSubview(stepLabel)
        skipLink.onClick = { [weak self] in self?.skipClicked() }
        surface.addSubview(skipLink)

        for button in [backButton, nextButton, startButton] {
            button.bezelStyle = .rounded
            button.font = NSFont.systemFont(ofSize: 13)
            surface.addSubview(button)
        }
        backButton.target = self
        backButton.action = #selector(backClicked)
        nextButton.target = self
        nextButton.action = #selector(nextClicked)
        startButton.target = self
        startButton.action = #selector(startClicked)

        // The login item is read once, when the step that owns it is built; the slides from the menu
        // bar never show that step and never ask.
        if !howToOnly {
            startupStep.startupSwitch.state = LaunchAtLoginService.isEnabled ? .on : .off
        }
        hotkeyStep.field.currentId = settings.captureId
        appearanceStep.picker.selectedTheme = settings.theme
        appearanceStep.picker.selectedAccent = settings.accentId
        appearanceStep.picker.onThemeChanged = { [weak self] in self?.applyTheme() }
        appearanceStep.picker.onAccentChanged = { [weak self] in self?.applyTheme() }

        layoutContent()
    }

    /// The wizard opens on the screen the pointer is on, not on the primary one, and never taller
    /// than the working area of that screen (`A-onboarding.md` §A3 — on macOS the scale is the
    /// system's business, only the rule about the working area is ported).
    private func place(_ window: NSWindow) {
        let pointer = NSEvent.mouseLocation
        let screen =
            NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
        guard let area = screen?.visibleFrame else {
            window.center()
            return
        }
        let height = max(Self.minimumUsefulHeight, min(600, area.height - 40))
        let frame = NSRect(
            x: area.midX - 310, y: area.midY - height / 2, width: 620, height: height)
        window.setFrame(window.frameRect(forContentRect: frame), display: false)
        layoutContent()
    }

    private func layoutContent() {
        guard surface.bounds.width > 0 else { return }
        let left: CGFloat = 24
        let width = surface.bounds.width - left * 2
        let footerHeight: CGFloat = 34
        let bottom: CGFloat = 24

        let buttonWidth: CGFloat = 96
        startButton.frame = NSRect(
            x: surface.bounds.width - left - buttonWidth, y: bottom, width: buttonWidth, height: footerHeight)
        nextButton.frame = startButton.frame
        backButton.frame = NSRect(
            x: startButton.frame.minX - 8 - buttonWidth, y: bottom, width: buttonWidth, height: footerHeight)
        stepLabel.frame = NSRect(x: left, y: bottom + 8, width: 120, height: 18)
        skipLink.frame = NSRect(x: left + 136, y: bottom + 8, width: 200, height: 18)

        errorLabel.frame = NSRect(x: left, y: bottom + footerHeight + 8, width: width, height: 20)
        let top = surface.bounds.height - 20 - titlebarInset
        let scrollBottom = bottom + footerHeight + 14 + (errorLabel.isHidden ? 0 : 28)
        scrollView.frame = NSRect(x: left, y: scrollBottom, width: width, height: max(0, top - scrollBottom))
        layoutSteps()
    }

    /// The titlebar is transparent but it is still there, and the content must not start under it.
    private var titlebarInset: CGFloat {
        guard let window, let contentView = window.contentView else { return 28 }
        return max(0, window.frame.height - contentView.frame.height)
    }

    private func layoutSteps() {
        let viewport = scrollView.contentSize
        let current = steps[step]
        let width = stepWidth(step)
        let height = stepHeight(step)
        let documentHeight = max(height, viewport.height)
        stepsContainer.frame = NSRect(x: 0, y: 0, width: viewport.width, height: documentHeight)
        current.frame = NSRect(
            x: (viewport.width - width) / 2, y: documentHeight - height, width: width, height: height)
        current.needsLayout = true
    }

    private func stepWidth(_ index: Int) -> CGFloat {
        switch index {
        case 0, 3: return 520
        case 4: return HowToSlidesView.contentWidth
        default: return OnboardingStepView.panelWidth
        }
    }

    private func stepHeight(_ index: Int) -> CGFloat {
        switch index {
        case 0: return welcomeStep.fittingHeight
        case 1: return hotkeyStep.fittingHeight
        case 2: return startupStep.fittingHeight
        case 3: return appearanceStep.fittingHeight
        default: return HowToSlidesView.fittingHeight
        }
    }

    // MARK: - Language and theme

    var selectedLanguage: String { language }
    var currentStep: Int { step }

    /// The step caption is built in code, so it is rebuilt every time the window is translated. The
    /// segment of the first step follows the language whoever calls this has chosen, including the
    /// guess made for the first run.
    func applyLanguage(_ language: String) {
        self.language = language
        welcomeStep.languageSegment.selectedSegment = language == "en" ? 1 : 0
        welcomeStep.applyLocalization(language)
        hotkeyStep.applyLocalization(language)
        startupStep.applyLocalization(language)
        appearanceStep.applyLocalization(language)
        slides.applyLanguage(language)
        skipLink.stringValue = MacUiText.text("Пропустить настройку", language: language)
        backButton.title = MacUiText.text("Назад", language: language)
        nextButton.title = MacUiText.text("Далее", language: language)
        startButton.title = MacUiText.text(howToOnly ? "Готово" : "Начать", language: language)
        refreshStepCaption()
        refreshCaptureConflict()
        layoutSteps()
    }

    private func applyTheme() {
        let palette = ThemeService.palette(ThemeService.currentTheme)
        surface.palette = palette
        window?.backgroundColor = palette.surface.flat
        errorLabel.textColor = palette.danger
        stepLabel.textColor = palette.textMuted
        skipLink.textColor = palette.textFaint
        welcomeStep.applyTheme(palette)
        hotkeyStep.applyTheme(palette)
        startupStep.applyTheme(palette)
        appearanceStep.applyTheme(palette)
        slides.applyTheme(palette)
    }

    @objc private func languageSegmentChanged() {
        let picked = welcomeStep.languageSegment.selectedSegment == 1 ? "en" : "ru"
        guard picked != language else { return }
        applyLanguage(picked)
    }

    // MARK: - Steps

    func goToStep(_ index: Int) { showStep(index) }

    private func showStep(_ index: Int) {
        step = min(max(index, 0), Self.stepCount - 1)
        errorLabel.isHidden = true
        for (stepIndex, view) in steps.enumerated() { view.isHidden = stepIndex != step }
        let last = step == Self.stepCount - 1
        // The switch is asked for once and belongs to the first step alone.
        welcomeStep.languageSegment.isHidden = step != 0
        backButton.isHidden = step == 0
        nextButton.isHidden = last
        startButton.isHidden = !last
        nextButton.keyEquivalent = last ? "" : "\r"
        startButton.keyEquivalent = last ? "\r" : ""
        refreshStepCaption()
        nextButton.isEnabled = true
        refreshCaptureConflict()

        // The scenes only run while their step is on screen: a loop nobody is looking at keeps
        // repainting a hidden panel.
        if step == 0 { welcomeStep.scene.play() } else { welcomeStep.scene.halt() }
        if last {
            slides.start()
            window?.makeFirstResponder(stepsContainer)
        } else {
            slides.stop()
        }

        if howToOnly {
            // Everything the menu bar does not need: the wizard is only the slides here, and its one
            // button says "Готово" instead of "Начать".
            backButton.isHidden = true
            nextButton.isHidden = true
            stepLabel.isHidden = true
            skipLink.isHidden = true
        }
        layoutSteps()
    }

    private func refreshStepCaption() {
        stepLabel.stringValue = UiFormat.text(
            MacUiText.text("Шаг {0} из {1}", language: language), "\(step + 1)", "\(Self.stepCount)")
    }

    /// Left and Right step through the slides while the last step is on screen, and say so by
    /// answering `true`; on the other steps they belong to whatever has the focus. The keys never
    /// move the wizard between its steps, and an arrow at the end of the slides does nothing at all.
    @discardableResult
    func handleNavigationKey(_ delta: Int) -> Bool {
        guard step == Self.stepCount - 1, delta != 0 else { return false }
        slides.step(delta)
        return true
    }

    // MARK: - The shortcut of step 2

    /// What the shortcut of the step is refused for, as the Russian key of the message, or nil when
    /// nothing refuses it. The rules are the shared ones; the wizard only asks them.
    private func captureRefusal() -> String? {
        let id = hotkeyStep.field.currentId
        if let parsed = HotkeyRules.parseCustom(id),
            HotkeyRules.isSystemReserved(
                modifiers: HotkeyModifiers(rawValue: parsed.modifiers), virtualKey: parsed.virtualKey)
        {
            return "Это сочетание занято системой"
        }
        // The fullscreen shortcut only holds its combination while its own switch is on: off, it keeps
        // the default id in the file and would otherwise refuse the same combination on a clean
        // installation.
        return settings.fullscreenSaveEnabled && HotkeyRules.sameGesture(id, settings.fullscreenSaveId)
            ? "Уже занято" : nil
    }

    // The refusal is shown under the field, "Далее" stops until it is gone, and a free combination is
    // offered beside it, so that the user is never left to invent one.
    private func refreshCaptureConflict() {
        let refusal = captureRefusal()
        hotkeyStep.conflictLabel.stringValue =
            refusal.map { MacUiText.text($0, language: language) } ?? ""
        hotkeyStep.conflictLabel.isHidden = refusal == nil
        suggestedCaptureId =
            refusal == nil
            ? nil : HotkeyRules.suggestFree(taken: [settings.fullscreenSaveId, settings.pasteId])
        if let suggestion = suggestedCaptureId {
            let label = HotkeyRecorderField.labelParts(forId: suggestion).joined(separator: " ")
            hotkeyStep.suggestChip.title = UiFormat.text(
                MacUiText.text("Предложить: {0}", language: language), label)
        }
        hotkeyStep.suggestChip.isHidden = suggestedCaptureId == nil
        if step == 1 { nextButton.isEnabled = refusal == nil }
        hotkeyStep.needsLayout = true
    }

    private func takeSuggestion() {
        guard let suggestion = suggestedCaptureId else { return }
        // The field reports what the user records, never what is written into it, so the refusal is
        // asked about again here.
        hotkeyStep.field.currentId = suggestion
        refreshCaptureConflict()
    }

    // MARK: - Applying

    // Only the fields the wizard owns are new; everything else travels from the file it was opened
    // with, and the candidate carries the language of the wizard.
    private func candidate(captureId: String) -> HotkeySettings {
        var candidate = settings
        candidate.captureId = captureId
        candidate.language = language
        candidate.onboardingVersion = Self.currentVersion
        candidate.theme = appearanceStep.picker.selectedTheme
        candidate.accentId = appearanceStep.picker.selectedAccent
        return candidate
    }

    // The shortcut is applied when the user leaves its step and again at the finish: the wizard has
    // no "cancel", so what is on screen is what the settings file gets.
    @discardableResult
    private func apply(captureId: String) -> Bool {
        let built = candidate(captureId: captureId)
        let error = (onApply ?? defaultApply)(built)
        if let error {
            errorLabel.stringValue = error
            errorLabel.isHidden = false
            layoutContent()
            return false
        }
        settings = built
        appliedCaptureId = captureId
        errorLabel.isHidden = true
        return true
    }

    private func defaultApply(_ candidate: HotkeySettings) -> String? {
        guard let coordinator else { return nil }
        coordinator.hotkeyService.unregisterAll()
        do {
            if candidate.captureEnabled {
                try coordinator.hotkeyService.register(
                    name: "capture", identifier: HotkeyIdentifier.parse(candidate.captureId))
            }
            if candidate.fullscreenSaveEnabled {
                try coordinator.hotkeyService.register(
                    name: "fullscreen-save", identifier: HotkeyIdentifier.parse(candidate.fullscreenSaveId))
            }
            try candidate.save(path: coordinator.workspace.settingsPath)
            coordinator.applySettings(candidate)
            return nil
        } catch {
            StartupLog.write(coordinator.options, "Onboarding apply failed for \(candidate.captureId): \(error)")
            return "Не удалось назначить сочетание. Возможно, оно уже занято — нажмите другое."
        }
    }

    private func applyStartup() -> Bool {
        let wanted = startupStep.startupSwitch.state == .on
        guard wanted != LaunchAtLoginService.isEnabled else { return true }
        do {
            try LaunchAtLoginService.setEnabled(wanted)
            return true
        } catch {
            startupStep.unavailableLabel.isHidden = false
            startupStep.needsLayout = true
            errorLabel.stringValue =
                "\(MacUiText.text("Не удалось изменить автозапуск", language: language)): \(error.localizedDescription)"
            errorLabel.isHidden = false
            layoutContent()
            return false
        }
    }

    // MARK: - Buttons

    @objc private func backClicked() { showStep(step - 1) }

    @objc private func nextClicked() {
        if step == 1 && (captureRefusal() != nil || !apply(captureId: hotkeyStep.field.currentId)) { return }
        showStep(step + 1)
    }

    @objc private func startClicked() {
        // Nothing was collected in the slides-only mode, so nothing is written back from it.
        if !howToOnly && (!apply(captureId: hotkeyStep.field.currentId) || !applyStartup()) { return }
        closedByButton = true
        window?.close()
    }

    // "Пропустить настройку" and the cross mean the same thing and do the same thing; the text says
    // it in words, and says it on every step.
    private func skipClicked() {
        closedByButton = true
        skipSetup()
        window?.close()
    }

    /// [ТЗ№4 E2] "Пропустить" leaves the file as it was: the theme and the accent go back, and so does
    /// the language, which the candidate would otherwise carry out of the wizard.
    private func skipSetup() {
        guard !howToOnly else { return }
        if appearanceStep.picker.selectedTheme != openedTheme
            || appearanceStep.picker.selectedAccent != openedAccent
        {
            appearanceStep.picker.selectedTheme = openedTheme
            appearanceStep.picker.selectedAccent = openedAccent
            ThemeService.apply(theme: openedTheme, accent: openedAccent)
            applyTheme()
        }
        if language != openedLanguage { applyLanguage(openedLanguage) }
        apply(captureId: appliedCaptureId)
    }

    /// Marks the wizard as passed. It runs when the window is gone, whatever closed it, and it is
    /// deliberately separate from the applying: a shortcut that could not be registered keeps the
    /// user on its step, but must not bring the whole wizard back on every start.
    private func markPassed() {
        guard let coordinator, coordinator.settings.onboardingVersion < Self.currentVersion else { return }
        var passed = coordinator.settings
        passed.onboardingVersion = Self.currentVersion
        try? passed.save(path: coordinator.workspace.settingsPath)
        coordinator.applySettings(passed)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // The window can go away without any button: the cross, Cmd+W, "Начать". Every one of them
        // counts as "seen", and every one of them has to release the loops the steps left running.
        if !closedByButton { skipSetup() }
        welcomeStep.scene.halt()
        slides.stop()
        markPassed()
        onFinished?()
    }

    func windowDidResize(_ notification: Notification) {
        layoutContent()
    }
}

/// The view the arrows reach while the slides are on screen: Left and Right belong to them there, and
/// to whatever has the focus everywhere else.
final class OnboardingKeyView: NSView {
    var onArrowKey: ((Int) -> Bool)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let delta = event.keyCode == 123 ? -1 : event.keyCode == 124 ? 1 : 0
        if delta != 0, onArrowKey?(delta) == true { return }
        super.keyDown(with: event)
    }
}
