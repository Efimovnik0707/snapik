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
        // [A5-1] The window neither scrolls nor resizes, so the height it declares has to hold the
        // tallest of its four tabs. A measurement that comes back as nothing would let any height
        // through, which is how a cut tab lived through every run of the old check: it compared the
        // declared 620x520 with the literal 620x520 and could not fail.
        let tallestTab = settings.smokeTallestTabHeight()
        let tabArea = settings.smokeTabAreaHeight
        let tabsFit = tallestTab >= 200 && tallestTab <= tabArea
        check(
            "the settings window is as tall as its tallest tab"
                + (tabsFit ? "" : ": \(Int(tallestTab)) px against \(Int(tabArea)) px"),
            tabsFit)
        // [A5-1, S5-2] The number beside the volume, in both languages, and the row that goes with
        // the sounds.
        check(
            "the volume says its number and goes away with the sounds",
            settings.smokeRunVolumeCaptionProbe())

        settings.smokeSelectTab(3)
        settings.window?.contentView?.layoutSubtreeIfNeeded()
        let picker = settings.smokeAppearancePicker
        picker.layoutSubtreeIfNeeded()
        check(
            "appearance picker shows every theme and every accent",
            picker.smokeCardCount == ThemeService.themes.count
                && picker.smokeDotCount == ThemeService.accents.count)
        check("accent divider stands before the first gradient", picker.smokeDividerPrecedesFirstGradient)

        // The palette row is the one part of the control the wizard hides (O-6), so its translation
        // is checked here, where it is on screen.
        picker.applyLanguage("en")
        let paletteTitles = picker.smokePaletteTitles
        let paletteTranslated = paletteTitles == ["Standard", "Pastel", "Neon", "Custom"]
        check(
            "the palette row translates"
                + (paletteTranslated ? "" : ": \(paletteTitles.joined(separator: " · "))"),
            paletteTranslated)
        picker.applyLanguage(coordinator.language)

        // [A5-1] The row of the settings is written by hand and the popover of the editor builds
        // itself out of `EditorAppearance.palettes`: two lists of one preference, compared as
        // sequences, because a row offering the same names in another order already disagrees.
        let offeredPalettes = picker.smokePaletteIds
        let editorPalettes = EditorAppearance.palettes.map { $0.id }
        let paletteOrderOk = offeredPalettes == editorPalettes
        check(
            "the settings offer the palettes of the editor in its order"
                + (paletteOrderOk ? "" : ": \(offeredPalettes.joined(separator: ", "))"),
            paletteOrderOk)

        // [A5-3] A file that carries the neon palette is shown as neon and saved back as neon, and a
        // name nobody knows still falls back to the standard set.
        check(
            "a settings file carrying the neon palette keeps it",
            settings.smokeRunPaletteProbe("neon") == "neon"
                && settings.smokeRunPaletteProbe("telepathy") == "standard")
        _ = settings.smokeRunPaletteProbe(coordinator.settings.annotationPalette)

        // The gallery opens on the first card, pages by one, and stops where the last card is whole.
        var galleryOk = picker.firstCard == 0
        // [S5-4] At the start of the row "back" is marked as the end and "forward" is not, and both
        // stay pressable: the end is a mark the drawing dims by, never a disabled button.
        let atStart = picker.smokeChevronsAtEnd
        galleryOk = galleryOk && atStart.back && !atStart.forward && picker.smokeChevronsArePressable
        picker.pageBy(1)
        galleryOk = galleryOk && picker.firstCard == 1
        picker.pageByWheel(1)
        galleryOk = galleryOk && picker.firstCard == 2
        picker.pageBy(20)
        let lastPage = picker.firstCard
        galleryOk = galleryOk && lastPage == picker.lastPage && lastPage > 0
        let atFinish = picker.smokeChevronsAtEnd
        galleryOk = galleryOk && !atFinish.back && atFinish.forward
        // A press at the end of the row moves nothing, and the button it was pressed on is a button
        // still.
        picker.pageBy(1)
        galleryOk = galleryOk && picker.firstCard == lastPage && picker.smokeChevronsArePressable
        // A card chosen where it stands leaves the gallery where the chevrons have taken it.
        picker.selectedTheme = ThemeService.themes[ThemeService.themes.count - 1]
        galleryOk = galleryOk && picker.firstCard == lastPage
        picker.pageBy(-20)
        galleryOk = galleryOk && picker.firstCard == 0 && picker.smokeChevronsArePressable
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
                + (cyrillic.isEmpty
                    ? ""
                    : ": "
                        + cyrillic.map { "\($0) → \(MacUiText.text($0, language: "en"))" }
                        .joined(separator: " · ")),
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

        // [SPEC-DELTA-4 A-4] The appearance the wizard collects is written to settings.json along with
        // everything else it owns: the theme picked on the fourth step used to be applied at once
        // and forgotten by the next start, because the write carried three fields and neither of
        // these two. The rule the wizard writes with is the one run here, not a copy of it.
        let appearancePath = dataDirectory.appendingPathComponent("onboarding-appearance.json")
        var storedLook = HotkeySettings.default
        storedLook.theme = "dark"
        storedLook.accentId = "blue"
        storedLook.language = "ru"
        storedLook.soundVolume = 55
        try? storedLook.save(path: appearancePath)
        var collected = storedLook
        collected.theme = "sea"
        collected.accentId = "rose-violet"
        collected.language = "en"
        collected.onboardingVersion = OnboardingWindowController.currentVersion
        try? OnboardingWindowController.mergeOnboarding(
            stored: HotkeySettings.loadAndMigrate(path: appearancePath), candidate: collected
        ).save(path: appearancePath)
        let writtenLook = HotkeySettings.loadAndMigrate(path: appearancePath)
        check(
            "the wizard keeps the look it collected and leaves the rest alone",
            writtenLook.theme == "sea" && writtenLook.accentId == "rose-violet"
                && writtenLook.language == "en"
                && writtenLook.onboardingVersion == OnboardingWindowController.currentVersion
                && writtenLook.soundVolume == 55)

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

    /// [A5-2] The letter of a copied card travels the whole way: card, workspace, export service,
    /// prompt generator. Port of `VerifyTz007SingleExport` (`SmokeTestRunner.cs:1372-1381`). The unit
    /// tests of the export call the service straight away, so a wire cut anywhere above it would
    /// leave them green and the user with a picture that says "A" while the toast says "B".
    ///
    /// Apart from `runSettingsAndOnboardingProbes` because the export is `async` and that one is
    /// called inside a `MainActor.run` block, which takes no `await` (SPEC-DELTA-5 §6 point 4: the
    /// registry of `App/SmokeTestRunner.swift` calls this one beside it).
    static func runSingleExportProbe(dataDirectory: URL) async -> (name: String, ok: Bool) {
        let name = "a capture copied from card B is exported and written as B"
        do {
            let workspace = SessionWorkspace(dataDirectory: dataDirectory)
            let image = try await DemoSessionFactory.renderDemoImage(index: 0, width: 400, height: 300)
            guard let png = ImageCodec.encode(image, format: .png) else { return (name, false) }
            let capture = try await workspace.addCapture(
                pngData: png, pixelWidth: image.width, pixelHeight: image.height,
                note: "Комментарий к одиночному снимку")
            let prepared = try await workspace.exportSingle(
                capture, label: "B", renderer: ExportImageRenderer())
            let images = prepared.manifest.images
            let fileOk = images.count == 1 && images[0].fileName == "01-B.png"
                && images[0].displayLabel == "B"
            return (name, fileOk && prepared.manifest.promptText.hasPrefix("Снимок B"))
        } catch {
            return (name, false)
        }
    }
}
