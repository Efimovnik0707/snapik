// Port of the clipboard-package, import, fast-save, paste-intent-rotation and settings/quit
// logic from `EdgeStackWindow.xaml.cs`/`EdgeStackWindow.Saving.cs`, SPEC §1.9-§1.12, §1.14,
// §1.17. Split out of `AppCoordinator.swift` to keep individual files within the ~200-400 line
// guideline; see that file's header for the deviations shared by both halves.
import AppKit
import SnapikCore

extension AppCoordinator {
    // MARK: - Clipboard package (SPEC §1.10, §1.12)

    /// Port of `SaveAndCopyCommittedPackageAsync` (`:386-404`). SPEC-DELTA-2A §4: runs under
    /// `clipboardPublicationGate` and cancels any in-flight receiver-echo watch first — this
    /// publishes a brand-new package, so any watch still chasing the *previous* one is obsolete.
    ///
    /// `includingSent` is the "Копировать пакет" command (`CopyPackageAsync`, `:1113-1135`): copying
    /// by hand is about the strip as a whole and takes the sent captures with it, and it becomes the
    /// current package because an intercepted Cmd+V pastes exactly that.
    @discardableResult
    func saveAndCopyCommittedPackage(includingSent: Bool = false) async -> Bool {
        await clipboardPublicationGate.wait()
        defer { clipboardPublicationGate.release() }
        cancelReceiverEchoWatch()

        do {
            // T-5, port of `SaveAndCopyCommittedPackageAsync`'s first branch (`:868-880`): everything
            // in the strip was already pasted, so the clipboard is left as the user has it instead of
            // publishing a package that repeats what the receiver already has.
            let packageCaptures = includingSent ? workspace.session.captures : workspace.pendingCaptures
            guard !packageCaptures.isEmpty else {
                _ = await save()
                prepared = nil
                ownedClipboardReceipt = nil
                ownedClipboardPromptText = nil
                publishedIsSingleCapture = false
                stackWindow?.setStatus("", isError: false)
                return true
            }

            let renderer = ExportImageRenderer()
            let export = try await workspace.prepareExport(renderer: renderer, includingSent: includingSent)
            prepared = export
            let current = await withCheckedContinuation { (continuation: CheckedContinuation<ClipboardSnapshot, Never>) in
                clipboard.capture { continuation.resume(returning: $0) }
            }
            let receipt = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ClipboardSnapshot, Error>) in
                clipboard.setPackageGuarded(
                    paths: export.imagePathsInOrder().map(\.path), text: export.manifest.promptText,
                    expectedSequence: current.sequence
                ) { result in continuation.resume(with: result) }
            }
            ownedClipboardReceipt = receipt
            ownedClipboardPromptText = export.manifest.promptText
            // Port of `CopyPackageAsync`'s `:1307`: a package published by hand or by a capture ends
            // the life of a single copy that was on the clipboard before it.
            publishedIsSingleCapture = false
            // Finding 4: gate on "Показывать уведомления".
            if settings.showNotifications { notificationService.notify("Снимки скопированы", language: language) }
            // Finding 24: two §1.20 dictionary strings otherwise unused anywhere in the port —
            // a VoiceOver announcement for the copy, independent of the notification toggle above
            // (a distinct accessibility channel, not the system notification).
            NSAccessibility.post(
                element: NSApp as Any, notification: .announcementRequested,
                userInfo: [
                    .announcement:
                        "\(MacUiText.text("Скопировано", language: language)). "
                        + MacUiText.text("Изображения и комментарии готовы к вставке", language: language),
                    .priority: NSAccessibilityPriorityLevel.medium.rawValue,
                ])
            stackWindow?.setStatus("", isError: false)
            return true
        } catch {
            _ = await save()
            stackWindow?.setStatus(StatusStrings.capturedButClipboardNotUpdated("\(error)"), isError: true)
            return false
        }
    }

    /// Port of `RefreshOwnedClipboardAsync` (`:656-688`). SPEC-DELTA-2A §4: runs under
    /// `clipboardPublicationGate`, same reasoning as `saveAndCopyCommittedPackage`.
    // `internal` (not `private`): called from stack actions in `AppCoordinator.swift`.
    func refreshOwnedClipboard() async {
        await clipboardPublicationGate.wait()
        defer { clipboardPublicationGate.release() }
        cancelReceiverEchoWatch()

        guard let receipt = ownedClipboardReceipt else { return }
        // SPEC-DELTA-5 §2.4 rule 1, port of `:1806`: what lies on the clipboard is one capture the
        // user copied on purpose. Rebuilding the package out of everything that waits would take it
        // away between the copy and the paste.
        guard !publishedIsSingleCapture else { return }
        let stillOurs = await withCheckedContinuation { continuation in
            clipboard.capture { continuation.resume(returning: $0.sequence == receipt.sequence) }
        }
        guard stillOurs else {
            ownedClipboardReceipt = nil
            ownedClipboardPromptText = nil
            publishedIsSingleCapture = false
            return
        }

        do {
            // T-5, port of `:1605-1618`: nothing is waiting. A strip that holds only sent captures
            // keeps the package that was pasted from it — the clipboard, the package and the receipt
            // all still describe it, so the same set can go somewhere else; only a strip that is
            // really empty gives the clipboard back.
            if workspace.pendingCaptures.isEmpty {
                guard workspace.session.captures.isEmpty else { return }
                let newReceipt = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ClipboardSnapshot, Error>) in
                    clipboard.setTextGuarded(text: "", expectedSequence: receipt.sequence) { result in continuation.resume(with: result) }
                }
                ownedClipboardReceipt = newReceipt
                ownedClipboardPromptText = nil
                prepared = nil
                return
            }

            let renderer = ExportImageRenderer()
            let export = try await workspace.prepareExport(renderer: renderer)
            prepared = export
            let newReceipt = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ClipboardSnapshot, Error>) in
                clipboard.setPackageGuarded(
                    paths: export.imagePathsInOrder().map(\.path), text: export.manifest.promptText,
                    expectedSequence: receipt.sequence
                ) { result in continuation.resume(with: result) }
            }
            ownedClipboardReceipt = newReceipt
            ownedClipboardPromptText = export.manifest.promptText
            // What is published now is a package again, whatever was published before it.
            publishedIsSingleCapture = false
            // Finding 4: gate on "Показывать уведомления".
            if settings.showNotifications { notificationService.notify("Снимки скопированы", language: language) }
        } catch {
            stackWindow?.setStatus(StatusStrings.sessionSavedButClipboardNotUpdated("\(error)"), isError: true)
        }
    }

    // MARK: - One capture on its own (SPEC-DELTA-5 §1.2 L-13)

    /// Port of `CopySingleCaptureAsync` (`EdgeStackWindow.Saving.cs:51-83`): one capture on the
    /// clipboard, through the same export and in the same formats a whole package is copied with, so
    /// a chat takes it the same way. It becomes the published package, so a paste that is noticed
    /// later marks that one capture as sent and nothing else; `prepared` is left alone, because the
    /// paste button still sends everything that waits.
    ///
    /// Returns whether the capture reached the clipboard: the strip is hidden while the editor is
    /// open, so its toast is seen by nobody there and the editor answers on its own plate
    /// (SPEC-DELTA-5 §2.4).
    @discardableResult
    func copySingleCapture(_ capture: CaptureItem, label: String) async -> Bool {
        await pasteIntentTransition?.value
        cancelReceiverEchoWatch()
        await clipboardPublicationGate.wait()
        defer { clipboardPublicationGate.release() }

        do {
            let export = try await workspace.exportSingle(
                capture, label: label, renderer: ExportImageRenderer())
            let current = await withCheckedContinuation { (continuation: CheckedContinuation<ClipboardSnapshot, Never>) in
                clipboard.capture { continuation.resume(returning: $0) }
            }
            let receipt = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ClipboardSnapshot, Error>) in
                clipboard.setPackageGuarded(
                    paths: export.imagePathsInOrder().map(\.path), text: export.manifest.promptText,
                    expectedSequence: current.sequence
                ) { result in continuation.resume(with: result) }
            }
            ownedClipboardReceipt = receipt
            ownedClipboardPromptText = export.manifest.promptText
            // What lies on the clipboard is the one card the user asked for: the strip must not
            // rebuild it out of the captures that are waiting, and a paste of it must not clear the
            // strip (SPEC-DELTA-5 §2.3, §2.4).
            publishedIsSingleCapture = true
            UiSoundService.copied(settings)
            stackWindow?.setStatus(
                MacUiText.text("Снимок {0} скопирован", language: language)
                    .replacingOccurrences(of: "{0}", with: label), isError: false)
            return true
        } catch {
            stackWindow?.setStatus(
                "\(MacUiText.text("Не удалось скопировать снимок", language: language)): \(error)", isError: true)
            return false
        }
    }

    /// Port of `SaveSingleCaptureAsAsync` (`EdgeStackWindow.Saving.cs:86-121`): one capture into a
    /// file the user picks. The picture is the one "Сохранить на компьютер" writes — the capture and
    /// its annotations, without the header and without the field the carried badges stand in — while
    /// "Копировать снимок" goes through the export and has both. The asymmetry is Windows's own.
    func saveSingleCaptureAs(_ capture: CaptureItem, label: String) async {
        let panel = NSSavePanel()
        panel.title = MacUiText.text("Сохранить снимок…", language: language)
        panel.allowedContentTypes = [.png, .jpeg]
        let suggested = FastSaveService.newPath(
            directory: URL(fileURLWithPath: settings.saveDirectory), format: settings.saveFormat)
        panel.nameFieldStringValue = suggested.lastPathComponent
        panel.directoryURL = suggested.deletingLastPathComponent()
        // The strip floats over everything, its own dialog included, until the suspension ends.
        let answer = stackWindow?.withTopmostSuspended { panel.runModal() } ?? panel.runModal()
        guard answer == .OK, let url = panel.url else { return }

        let suffix = url.pathExtension.lowercased()
        guard suffix == "png" || suffix == "jpg" || suffix == "jpeg" else {
            stackWindow?.setStatus(MacUiText.text("Выберите PNG или JPEG.", language: language), isError: true)
            return
        }
        do {
            let format: ImageCodec.Format =
                suffix == "png" ? .png : .jpeg(quality: max(1, min(100, settings.jpegQuality)))
            try writeAnnotated(capture, label: label, format: format, to: url)
            if settings.showNotifications { notificationService.notify("Снимок сохранён", language: language) }
        } catch {
            stackWindow?.setStatus(
                "\(MacUiText.text("Не удалось сохранить", language: language)): \(error)", isError: true)
        }
    }

    /// The letter of a capture as the strip shows it. Mac has no `CaptureItem.DisplayLabel` the way
    /// Windows does: a capture that is still waiting takes the letter the strip hands out
    /// (`SentCaptureRules.stripLabels`), and a sent one — whose badge is a tick and whose letter is
    /// `nil` — takes the letter of its place, the way the autosave names one (SPEC-DELTA-5 §1.2
    /// L-13, the trap of the strip letter).
    func singleCaptureLabel(for capture: CaptureItem) -> String {
        let captures = workspace.session.captures
        guard let index = captures.firstIndex(where: { $0.id == capture.id }) else { return "A" }
        if let labels = try? SentCaptureRules.stripLabels(captures.map(\.sent)), index < labels.count,
            let label = labels[index]
        {
            return label
        }
        return (try? CaptureLabels.forIndex(index)) ?? "A"
    }

    /// The capture and its annotations drawn into a file, by the recipe of `AutoSaveService` (the
    /// "save what you see" render, not the export PNG) but into the place the user picked.
    private func writeAnnotated(
        _ capture: CaptureItem, label: String, format: ImageCodec.Format, to url: URL
    ) throws {
        let sourceURL = workspace.sessionDirectory.appendingPathComponent(capture.sourceImagePath)
        guard let sourceImage = ImageCodec.loadImage(at: sourceURL) else {
            throw SnapikError.fileNotFound("The source image of the capture is missing at \(sourceURL.path).")
        }
        let width = sourceImage.width
        let height = sourceImage.height
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo)
        else {
            throw SnapikError.invalidOperation("The render context of the capture could not be created.")
        }
        // Top-left origin, Y downwards, which is `AnnotationPainter`'s contract.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        var labelsById: [SBGuid: String] = [:]
        for labeled in CaptureLabels.forNotedAnnotations(captureLabel: label, capture: capture) {
            labelsById[labeled.annotation.id] = labeled.displayLabel
        }
        AnnotationPainter.draw(
            capture.annotations, imageSize: CGSize(width: width, height: height), in: context,
            options: AnnotationPaintOptions(
                showLabels: true, labelFor: { labelsById[$0.id] }, sourceImage: sourceImage,
                labelStyle: .screen))

        guard let rendered = context.makeImage(), let data = ImageCodec.encode(rendered, format: format) else {
            throw SnapikError.invalidData("The annotated capture could not be encoded.")
        }
        try ImageCodec.writeAtomically(data, to: url)
    }

    func copyPackage() async {
        // T-5 (`:1110-1112`): copying by hand takes the strip as a whole, sent captures included.
        if await saveAndCopyCommittedPackage(includingSent: true) {
            // G-10: the third sound of the round. It belongs to "Копировать пакет" and not to a
            // capture — a capture already has the shutter, and Windows takes the note off that path
            // for the same reason (`EdgeStackWindow.xaml.cs:1127`).
            UiSoundService.copied(settings)
            stackWindow?.setStatus(StatusStrings.packageCopied, isError: false)
        }
    }

    func savePackageAs() async {
        let resolvedExport: PreparedExport?
        if let prepared {
            resolvedExport = prepared
        } else {
            resolvedExport = await prepareExportForMenu()
        }
        guard let export = resolvedExport else { return }

        // G-12: one window instead of the system folder picker — the folder, the name and the
        // subfolder switch are on screen at once, and the choice is remembered.
        let now = Date()
        guard let choice = await askWherePackageGoes(now: now) else { return }

        // Port of `SavePackageAsAsync`'s `MutateSettings` (`EdgeStackWindow.xaml.cs:1148`): saving
        // into the same place a second time is one click. A settings file that cannot be written
        // leaves its own error on screen and must not stop the package from being saved.
        var stored = workspace.preferences
        stored.packageSaveDirectory = choice.directory
        stored.packageCreateSubfolder = choice.createSubfolder
        do {
            try stored.save(path: workspace.settingsPath)
        } catch {
            stackWindow?.setStatus(StatusStrings.couldNotSave("\(error)"), isError: true)
        }
        applySettings(stored)

        // Only what the user opened the folder for: the images and the text. `manifest.json`
        // describes the package for the application itself and stays in the working directory.
        let promptFileName = export.manifest.promptFileName
        let sources =
            ((try? FileManager.default.contentsOfDirectory(
                at: export.rootDirectory, includingPropertiesForKeys: nil)) ?? [])
            .filter { url in
                url.pathExtension.lowercased() == "png"
                    || (!promptFileName.isEmpty && url.lastPathComponent == promptFileName)
            }
        let destinationRoot = URL(fileURLWithPath: choice.directory)

        // The whole set of destinations is checked before the first copy: a package saved twice into
        // the same place becomes "…-2" as a whole, never half of one and half of another.
        let destination: URL
        let prefix: String
        if choice.createSubfolder {
            let folder = SaveNaming.freeName(choice.folderName) { candidate in
                sources.contains { source in
                    FileManager.default.fileExists(
                        atPath: destinationRoot.appendingPathComponent(candidate)
                            .appendingPathComponent(source.lastPathComponent).path)
                }
            }
            guard let folder else {
                stackWindow?.setStatus(
                    MacUiText.text(
                        "В этой папке нет свободного имени для пакета. Выберите другую папку.",
                        language: language), isError: true)
                return
            }
            destination = destinationRoot.appendingPathComponent(folder)
            prefix = ""
        } else {
            // Without a subfolder the files share the folder with whatever is already there, so the
            // date of the package goes into every name; with one, the folder name already carries it.
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            let stamp = SaveNaming.freeName(formatter.string(from: now)) { candidate in
                sources.contains { source in
                    FileManager.default.fileExists(
                        atPath: destinationRoot.appendingPathComponent(
                            "\(candidate)-\(source.lastPathComponent)"
                        ).path)
                }
            }
            guard let stamp else {
                stackWindow?.setStatus(
                    MacUiText.text(
                        "В этой папке нет свободного имени для пакета. Выберите другую папку.",
                        language: language), isError: true)
                return
            }
            destination = destinationRoot
            prefix = "\(stamp)-"
        }

        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            for source in sources {
                try FileManager.default.copyItem(
                    at: source, to: destination.appendingPathComponent(prefix + source.lastPathComponent))
            }
            stackWindow?.setStatus(StatusStrings.packageSaved, isError: false)
        } catch {
            stackWindow?.setStatus(
                "\(MacUiText.text("Не удалось сохранить пакет", language: language)): \(error)", isError: true)
        }
    }

    /// The save-package window, awaited: the choice it was closed with, or nil on every other way
    /// out. Held in a property while it is up — a window controller nothing references goes away
    /// with the run-loop turn that opened it.
    private func askWherePackageGoes(now: Date) async -> SavePackageChoice? {
        let sheet = SavePackageSheetController(settings: settings, now: now)
        savePackageSheet = sheet
        stackWindow?.beginTopmostSuspension()
        let choice = await withCheckedContinuation { (continuation: CheckedContinuation<SavePackageChoice?, Never>) in
            sheet.onClosed = { choice in continuation.resume(returning: choice) }
            sheet.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        stackWindow?.endTopmostSuspension()
        savePackageSheet = nil
        return choice
    }

    private func prepareExportForMenu() async -> PreparedExport? {
        guard !workspace.session.captures.isEmpty else {
            stackWindow?.setStatus(StatusStrings.makeACaptureFirst, isError: true)
            return nil
        }
        // Finding 7: SPEC §1.9 "Сохранить пакет…" shows progress/result status text that was
        // never actually printed.
        stackWindow?.setStatus(StatusStrings.preparingPngAndText, isError: false)
        do {
            // T-5 (`:1151`): saving by hand takes every capture of the strip, sent ones included.
            let export = try await workspace.prepareExport(renderer: ExportImageRenderer(), includingSent: true)
            prepared = export
            stackWindow?.setStatus(
                StatusStrings.prepared(imageCount: export.imagePathsInOrder().count, noteCount: export.manifest.noteCount),
                isError: false)
            return export
        } catch {
            stackWindow?.setStatus(StatusStrings.couldNotPrepare("\(error)"), isError: true)
            return nil
        }
    }

    // MARK: - Import (SPEC §1.9 "•••" menu)

    func importFiles() async {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg]
        guard panel.runModal() == .OK else { return }
        // S-2, port of `ImportFileAsync` (`EdgeStackWindow.xaml.cs:1060-1063`): the strip is asked
        // after the dialog and before the first file, and a selection larger than the free places
        // takes the first of them — the toast about the limit replaces the one about what was added.
        guard stackWindow?.stripIsFull() != true else { return }
        let free = SentCaptureRules.maxStripCaptures - workspace.session.captures.count

        var imported = 0
        for url in panel.urls.prefix(free) {
            do {
                guard let image = ImageCodec.loadImage(at: url) else {
                    throw SnapikError.invalidData("Unsupported image file.")
                }
                guard let data = ImageCodec.encode(image, format: .png) else {
                    throw SnapikError.invalidData("Could not re-encode image as PNG.")
                }
                // S-3 (`EdgeStackWindow.xaml.cs:1071-1074`): the name of the file is what tells one
                // import from another, on the chip of the card and in `prompt.md`; a capture of a
                // region has nothing to put there and leaves it empty.
                _ = try await workspace.addCapture(
                    pngData: data, pixelWidth: image.width, pixelHeight: image.height,
                    title: url.lastPathComponent, kind: .import)
                imported += 1
            } catch {
                stackWindow?.setStatus(StatusStrings.importFailed(fileName: url.lastPathComponent, error: "\(error)"), isError: true)
            }
        }
        stackWindow?.refresh()
        // Port of `ImportFileAsync`'s `ScrollStripToEnd()` (`:1271`), SPEC-DELTA-5 §1.2 L-8: the
        // files that were just imported are the ones to look at.
        stackWindow?.scrollStripToEnd()
        invalidatePrepared()
        _ = await save()
        stackWindow?.setStatus(StatusStrings.imported(count: imported), isError: false)
    }

    func importFromClipboard() async {
        // S-2: the fourth way of adding a capture asks the strip like the other three.
        guard stackWindow?.stripIsFull() != true else { return }
        let pasteboard = NSPasteboard.general
        guard
            let objects = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
            let image = objects.first,
            let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            stackWindow?.setStatus(StatusStrings.clipboardHasNoImage, isError: true)
            return
        }

        do {
            guard let data = ImageCodec.encode(cgImage, format: .png) else {
                throw SnapikError.invalidData("Could not encode clipboard image as PNG.")
            }
            _ = try await workspace.addCapture(pngData: data, pixelWidth: cgImage.width, pixelHeight: cgImage.height)
            stackWindow?.refresh()
            // Port of `ImportClipboardAsync`'s `ScrollStripToEnd()` (`:1287`), SPEC-DELTA-5 §1.2 L-8.
            stackWindow?.scrollStripToEnd()
            invalidatePrepared()
            _ = await save()
            stackWindow?.setStatus(StatusStrings.imageAdded, isError: false)
        } catch {
            stackWindow?.setStatus(StatusStrings.couldNotOpenCapture("\(error)"), isError: true)
        }
    }

    // MARK: - The whole screen (SPEC-DELTA-4 §1.2 S-1, S-2, §2.7)

    /// Port of `CaptureFullscreenAsync` (`EdgeStackWindow.Saving.cs:45-73`). The shortcut no longer
    /// writes a PNG straight into the folder and shows nothing: the whole screen goes into the strip
    /// like any other capture, and the folder gets it from the autosave the rest of them go through
    /// — three files of five megabytes each used to land in Pictures while the strip stayed empty.
    /// The tail is the tail of an ordinary capture minus the editor: the shortcut means "take
    /// everything right now", and a full-screen editor over a picture 3840 px wide is not that.
    func saveFullscreen() async {
        // Finding 11 / SPEC-DELTA-2A §4: don't race a paste-intent-driven session rotation
        // that's still in flight.
        await pasteIntentTransition?.value
        guard !isBusy else { return }
        // Asked before anything is hidden, exactly as in the capture of a region (`:53, 57`): a press
        // on a full strip must not black the screen out for a capture that has nowhere to go. The
        // toast is the strip's, so the strip is left on the screen to carry it.
        guard stackWindow?.stripIsFull() != true else {
            stackWindow?.reveal()
            return
        }
        isBusy = true
        defer {
            isBusy = false
            // S-2 (`:72`): the strip comes back whether it was on the screen or not — the capture
            // that has just been taken is in it, and a hidden strip would say nothing of that.
            stackWindow?.reveal()
        }

        hideAllOwnWindows()
        try? await Task.sleep(nanoseconds: 120_000_000)

        do {
            guard let frame = await captureDesktopFrame() else {
                throw SnapikError.invalidData("no screen frame")
            }
            guard let data = ImageCodec.encode(frame.image, format: .png) else {
                throw SnapikError.invalidData("Could not encode the screen as PNG.")
            }
            let capture = try await workspace.addCapture(
                pngData: data, pixelWidth: frame.image.width, pixelHeight: frame.image.height,
                kind: .fullscreen, monitorCount: NSScreen.screens.count)
            stackWindow?.refresh()
            invalidatePrepared()
            UiSoundService.capture(settings)
            _ = await saveAndCopyCommittedPackage()
            await autoSave(capture)
        } catch {
            stackWindow?.setStatus(
                "\(MacUiText.text("Не удалось снять экран", language: language)): \(error)", isError: true)
        }
    }

    // MARK: - Settings (SPEC §1.17)
    //
    // `handlePasteIntent`/`completePasteIntent` (formerly here, SPEC §1.11/§5.4) moved to
    // `AppCoordinator+PasteIntent.swift` per SPEC-DELTA-2A §4: the rewrite adds the intercepted
    // per-image sequence, the reusable-package republish, and the receiver-echo watch.

    /// Port of `OpenSettings` step 1: unregister both hotkeys before showing the dialog, so a
    /// combination we already own doesn't look "taken" while it is being re-recorded.
    func beginEditingSettings() {
        hotkeyService.unregisterAll()
    }

    /// Port of `OpenSettings`'s `finally`: re-register from whatever settings are current
    /// (applied or not), surfacing any conflicts.
    func endEditingSettings() {
        registerHotkeys()
    }

    func applySettings(_ newSettings: HotkeySettings) {
        settings = newSettings
        language = newSettings.language
        UiLanguage.current = newSettings.language
        statusBar?.updateLanguage(newSettings.language)
        stackWindow?.updateLanguage(newSettings.language)
        registerHotkeys()
    }

    // MARK: - Quit (SPEC §9.7)

    /// Port of `DiscardSessionOnExitAsync` (`EdgeStackWindow.xaml.cs:1857-1889`), C-15: a session
    /// lives for one run, so the run that is ending takes its directory with it — under the same
    /// gate and in the same order as "Очистить ленту", the clipboard first (the package on it is a
    /// list of paths into the directory that goes), the files after.
    ///
    /// Returns `true` if it is safe to terminate. An operation still in flight is the one case that
    /// keeps the files: whatever it writes would land in a directory that was just deleted, and the
    /// purge of the next start takes the whole root anyway (`:1863-1867`). That branch keeps this
    /// port's forced save, which is what the quit reply has always been built on (SPEC §9.7).
    func prepareForQuit() async -> Bool {
        guard !isBusy else {
            StartupLog.write(options, "Exit: the session was left to the next start, an operation was still running.")
            let saved = await save()
            if !saved { stackWindow?.reveal() }
            return saved
        }

        await clipboardPublicationGate.wait()
        defer { clipboardPublicationGate.release() }
        // Nothing may publish or rebuild the clipboard from here on: the strip is going.
        isSessionResetting = true
        cancelReceiverEchoWatch()
        await releaseOwnedClipboard()
        workspace.discardCurrentSession { [weak self] message in
            guard let self else { return }
            StartupLog.write(self.options, message)
        }
        return true
    }

    func shutdown() {
        hotkeyService.unregisterAll()
        pasteIntentObserver.stop()
        cancelReceiverEchoWatch()
    }
}
