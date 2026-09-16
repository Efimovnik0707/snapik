// The probes of the settings window and of the wizard, kept apart from `SmokeTestRunner.swift` while
// the three portions of wave 1 run side by side (SPEC-DELTA-3 §7); wave 2 folds them into the run.
import AppKit
import SnapikCore

extension SmokeTestRunner {
    /// Builds the settings window and the wizard over an isolated data directory, walks both of them
    /// and answers with one line per check, in the shape the main run reports.
    ///
    /// Nothing here touches the login item: registering one on the machine that is only probing the
    /// interface would be a side effect of a check.
    @MainActor
    static func runSettingsAndOnboardingProbes(dataDirectory: URL) -> [(name: String, ok: Bool)] {
        var results: [(name: String, ok: Bool)] = []
        func check(_ name: String, _ condition: Bool) { results.append((name, condition)) }

        let options = CommandLineOptions.parse(
            arguments: ["--data-dir", dataDirectory.path], environment: [:])
        let coordinator = AppCoordinator(options: options)

        // 1. The settings window: four tabs, the appearance control on the fourth, and the two rules
        // the save block holds (G-3, G-4, G-5, G-6, G-7, G-13).
        let settings = HotkeySettingsWindowController(coordinator: coordinator)
        settings.window?.contentView?.layoutSubtreeIfNeeded()
        check("settings tabs", settings.smokeTabCount == 4)
        // The frame Windows gives the same dialog (`HotkeySettingsWindow.xaml:3`).
        check("settings window 620x520", settings.window?.frame.size == NSSize(width: 620, height: 520))

        settings.smokeSelectTab(3)
        settings.window?.contentView?.layoutSubtreeIfNeeded()
        let picker = settings.smokeAppearancePicker
        picker.layoutSubtreeIfNeeded()
        check(
            "appearance picker shows every theme and every accent",
            picker.smokeCardCount == ThemeService.themes.count
                && picker.smokeDotCount == ThemeService.accents.count)
        check("accent divider stands before the first gradient", picker.smokeDividerPrecedesFirstGradient)

        // The gallery opens on the first card, pages by one, and stops where the last card is whole.
        var galleryOk = picker.firstCard == 0
        picker.pageBy(1)
        galleryOk = galleryOk && picker.firstCard == 1
        picker.pageByWheel(1)
        galleryOk = galleryOk && picker.firstCard == 2
        picker.pageBy(20)
        let lastPage = picker.firstCard
        galleryOk = galleryOk && lastPage == picker.lastPage && lastPage > 0
        // A card chosen where it stands leaves the gallery where the chevrons have taken it.
        picker.selectedTheme = ThemeService.themes[ThemeService.themes.count - 1]
        galleryOk = galleryOk && picker.firstCard == lastPage
        picker.pageBy(-20)
        galleryOk = galleryOk && picker.firstCard == 0
        check("theme gallery pages by one card and stays where it is put", galleryOk)

        check("one combination for two actions is refused", settings.smokeRunConflictProbe())
        check("the chip offers a free combination", settings.smokeRunSuggestProbe())
        check("the link asks for the wizard and saves nothing", settings.smokeRequestOnboarding())
        settings.window?.close()

        // 2. The key field: a key pressed alone is not a shortcut, the same key with a modifier is,
        // and a combination the system keeps is refused with the frame turning red (G-6).
        let field = HotkeyRecorderField(frame: NSRect(x: 0, y: 0, width: 360, height: 48))
        field.language = "ru"
        field.currentId = "ctrl-alt-s"
        field.beginRecording()
        let bareRefused = !field.recordKey(macKeyCode: 0x7B, modifiers: []) && field.currentId == "ctrl-alt-s"
        let askedForModifier = field.smokeCaption == MacUiText.text("Добавь Cmd, Option или Shift", language: "ru")
        let taken = field.recordKey(macKeyCode: 0x7B, modifiers: [.control])
        check(
            "a bare key is answered with a request for a modifier",
            bareRefused && askedForModifier && taken && field.currentId == "custom:2:37")

        field.beginRecording()
        let kept = field.currentId
        // Cmd + Space is the system's before it is anybody's.
        let reservedRefused = !field.recordKey(macKeyCode: 0x31, modifiers: [.control]) && field.currentId == kept
        let saidWhoKeepsIt =
            field.smokeCaption == MacUiText.text("Это сочетание занято системой", language: "ru")
            && field.showsConflict
        check("a combination the system keeps is refused", reservedRefused && saidWhoKeepsIt)

        let neighbour = HotkeyRecorderField(frame: .zero)
        neighbour.currentId = "custom:2:83"
        field.conflictsWith = [neighbour]
        field.beginRecording()
        check(
            "a shortcut the neighbouring field holds is refused",
            !field.recordKey(macKeyCode: 0x01, modifiers: [.control]) && field.currentId == kept)

        // 3. The wizard: five steps, the caption of the last one, the slides and their block of
        // captions, and the slides-only mode of the menu bar (O-2, O-7, O-8, [ТЗ№4 A6]).
        let wizard = OnboardingWindowController(coordinator: coordinator)
        wizard.window?.contentView?.layoutSubtreeIfNeeded()
        var stepsOk = true
        for step in 0..<OnboardingWindowController.stepCount {
            wizard.goToStep(step)
            wizard.window?.contentView?.layoutSubtreeIfNeeded()
            stepsOk = stepsOk && wizard.currentStep == step
        }
        wizard.applyLanguage("ru")
        check(
            "the wizard walks five steps and says so",
            stepsOk && wizard.smokeStepCaption == "Шаг 5 из 5" && wizard.smokeFinishTitle == "Начать")

        wizard.applyLanguage("en")
        let cyrillic = wizard.smokeVisibleStrings.filter {
            $0.range(of: "[А-Яа-яЁё]", options: .regularExpression) != nil
        }
        // A row that only says "no" would send the reader back to the window it cannot open; the
        // lines that stayed Russian are named in the report instead.
        check(
            "the English wizard shows no Russian"
                + (cyrillic.isEmpty ? "" : ": \(cyrillic.joined(separator: " · "))"),
            cyrillic.isEmpty)
        wizard.applyLanguage("ru")

        check(
            "the captions of every slide fit the block the dots stand under",
            wizard.smokeCaptionsFit(language: "ru") && wizard.smokeCaptionsFit(language: "en"))

        wizard.goToStep(OnboardingWindowController.stepCount - 1)
        wizard.smokeStartSlides()
        var slidesOk = wizard.smokeSlide == 0
        wizard.smokeStepSlides(-1)
        // An arrow on the first slide stays on it and stops the automatic run for good.
        slidesOk = slidesOk && wizard.smokeSlide == 0 && !wizard.smokeAutoAdvancing
        for _ in 0...HowToSlidesView.slideCount { wizard.smokeStepSlides(1) }
        slidesOk = slidesOk && wizard.smokeSlide == HowToSlidesView.slideCount - 1
        wizard.smokeGoToSlide(1)
        slidesOk = slidesOk && wizard.smokeSlide == 1
        wizard.smokeStopSlides()
        wizard.smokeStartSlides()
        // The step can be left and entered again; a carousel the user has stopped stays stopped.
        slidesOk = slidesOk && !wizard.smokeAutoAdvancing
        wizard.smokeStopSlides()
        check("the slides hold at their ends and stop when the user takes over", slidesOk)
        wizard.window?.close()

        let slidesOnly = OnboardingWindowController(coordinator: coordinator, howToOnly: true)
        slidesOnly.window?.contentView?.layoutSubtreeIfNeeded()
        check(
            "the menu bar opens the slides alone",
            slidesOnly.currentStep == OnboardingWindowController.stepCount - 1
                && slidesOnly.smokeFinishTitle == MacUiText.text("Готово", language: slidesOnly.selectedLanguage)
                && !slidesOnly.smokeShowsSteps)
        slidesOnly.window?.close()

        // 4. The rules the strip asks before it opens the wizard at all (O-2).
        var seen = HotkeySettings.default
        seen.onboardingVersion = OnboardingWindowController.currentVersion
        var older = HotkeySettings.default
        older.onboardingVersion = 1
        check(
            "the wizard opens once per version and never in a demo",
            OnboardingWindowController.shouldShowOnboarding(
                settingsFileExists: false, settings: HotkeySettings.default, demo: false)
                && !OnboardingWindowController.shouldShowOnboarding(
                    settingsFileExists: true, settings: seen, demo: false)
                && OnboardingWindowController.shouldShowOnboarding(
                    settingsFileExists: true, settings: older, demo: false)
                && !OnboardingWindowController.shouldShowOnboarding(
                    settingsFileExists: false, settings: HotkeySettings.default, demo: true))

        var chosenRussian = HotkeySettings.default
        chosenRussian.language = "ru"
        check(
            "the locale is guessed only where there is nothing to go on",
            OnboardingWindowController.suggestedLanguage(
                settingsFileExists: false, settings: HotkeySettings.default, cultureLanguage: "es") == "en"
                && OnboardingWindowController.suggestedLanguage(
                    settingsFileExists: true, settings: chosenRussian, cultureLanguage: "es") == "ru"
                && OnboardingWindowController.languageForCulture("ru") == "ru"
                && OnboardingWindowController.languageForCulture("uk") == "en")

        // 5. The save-package window: the name it offers and the two paths it refuses (G-12).
        let sheet = SavePackageSheetController(
            settings: coordinator.settings,
            now: Date(timeIntervalSince1970: 1_789_000_707))
        sheet.window?.contentView?.layoutSubtreeIfNeeded()
        check("the save-package window builds", sheet.validate() != nil)
        sheet.window?.close()

        return results
    }
}
