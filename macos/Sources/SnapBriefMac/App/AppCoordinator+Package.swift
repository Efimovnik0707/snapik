// Port of the clipboard-package, import, fast-save, paste-intent-rotation and settings/quit
// logic from `EdgeStackWindow.xaml.cs`/`EdgeStackWindow.Saving.cs`, SPEC §1.9-§1.12, §1.14,
// §1.17. Split out of `AppCoordinator.swift` to keep individual files within the ~200-400 line
// guideline; see that file's header for the deviations shared by both halves.
import AppKit
import SnapBriefCore

extension AppCoordinator {
    // MARK: - Clipboard package (SPEC §1.10, §1.12)

    /// Port of `SaveAndCopyCommittedPackageAsync` (`:386-404`).
    @discardableResult
    func saveAndCopyCommittedPackage() async -> Bool {
        do {
            let renderer = ExportImageRenderer()
            let export = try await workspace.prepareExport(renderer: renderer)
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
            notificationService.notify("Снимки скопированы", language: language)
            stackWindow?.setStatus("", isError: false)
            return true
        } catch {
            _ = await save()
            stackWindow?.setStatus(StatusStrings.capturedButClipboardNotUpdated("\(error)"), isError: true)
            return false
        }
    }

    /// Port of `RefreshOwnedClipboardAsync` (`:656-688`).
    // `internal` (not `private`): called from stack actions in `AppCoordinator.swift`.
    func refreshOwnedClipboard() async {
        guard let receipt = ownedClipboardReceipt else { return }
        let stillOurs = await withCheckedContinuation { continuation in
            clipboard.capture { continuation.resume(returning: $0.sequence == receipt.sequence) }
        }
        guard stillOurs else {
            ownedClipboardReceipt = nil
            ownedClipboardPromptText = nil
            return
        }

        do {
            if workspace.session.captures.isEmpty {
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
            notificationService.notify("Снимки скопированы", language: language)
        } catch {
            stackWindow?.setStatus(StatusStrings.sessionSavedButClipboardNotUpdated("\(error)"), isError: true)
        }
    }

    func copyPackage() async {
        if await saveAndCopyCommittedPackage() {
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

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = MacUiText.text("Выбрать папку", language: language)
        guard panel.runModal() == .OK, let destinationRoot = panel.url else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let destination = destinationRoot.appendingPathComponent("SnapBrief-\(formatter.string(from: Date()))")

        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let files = try FileManager.default.contentsOfDirectory(at: export.rootDirectory, includingPropertiesForKeys: nil)
            for file in files {
                try FileManager.default.copyItem(at: file, to: destination.appendingPathComponent(file.lastPathComponent))
            }
            stackWindow?.setStatus(StatusStrings.packageSaved, isError: false)
        } catch {
            stackWindow?.setStatus(StatusStrings.couldNotSave("\(error)"), isError: true)
        }
    }

    private func prepareExportForMenu() async -> PreparedExport? {
        guard !workspace.session.captures.isEmpty else {
            stackWindow?.setStatus(StatusStrings.makeACaptureFirst, isError: true)
            return nil
        }
        do {
            let export = try await workspace.prepareExport(renderer: ExportImageRenderer())
            prepared = export
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

        var imported = 0
        for url in panel.urls {
            do {
                guard let image = ImageCodec.loadImage(at: url) else {
                    throw SnapBriefError.invalidData("Unsupported image file.")
                }
                guard let data = ImageCodec.encode(image, format: .png) else {
                    throw SnapBriefError.invalidData("Could not re-encode image as PNG.")
                }
                _ = try await workspace.addCapture(pngData: data, pixelWidth: image.width, pixelHeight: image.height)
                imported += 1
            } catch {
                stackWindow?.setStatus(StatusStrings.importFailed(fileName: url.lastPathComponent, error: "\(error)"), isError: true)
            }
        }
        stackWindow?.refresh()
        invalidatePrepared()
        _ = await save()
        stackWindow?.setStatus(StatusStrings.imported(count: imported), isError: false)
    }

    func importFromClipboard() async {
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
                throw SnapBriefError.invalidData("Could not encode clipboard image as PNG.")
            }
            _ = try await workspace.addCapture(pngData: data, pixelWidth: cgImage.width, pixelHeight: cgImage.height)
            stackWindow?.refresh()
            invalidatePrepared()
            _ = await save()
            stackWindow?.setStatus(StatusStrings.imageAdded, isError: false)
        } catch {
            stackWindow?.setStatus(StatusStrings.couldNotOpenCapture("\(error)"), isError: true)
        }
    }

    // MARK: - Fast save (SPEC §1.14)

    func saveFullscreen() async {
        guard !isBusy else { return }
        isBusy = true
        let wasVisible = stackWindow?.isVisible ?? false
        defer { isBusy = false }

        hideAllOwnWindows()
        try? await Task.sleep(nanoseconds: 120_000_000)

        do {
            guard let frame = await captureDesktopFrame() else {
                throw SnapBriefError.invalidData("no screen frame")
            }
            try FastSaveService.save(frame.image, settings: settings)
            notificationService.notify("Снимок сохранён", language: language)
        } catch {
            stackWindow?.setStatus(StatusStrings.couldNotSaveScreen("\(error)"), isError: true)
            stackWindow?.reveal()
            return
        }

        if wasVisible { stackWindow?.reveal() }
    }

    // MARK: - Paste-intent-driven rotation (SPEC §1.11, §5.4)

    /// Port of `OnPasteIntentObserved` (`:179-192`).
    func handlePasteIntent(_ intent: PasteIntent) {
        guard let receiptAtIntent = ownedClipboardReceipt, intent.clipboardSequence == receiptAtIntent.sequence else {
            return  // Pasted something that wasn't our current package.
        }
        guard let promptAtIntent = ownedClipboardPromptText else {
            stackWindow?.setStatus(StatusStrings.couldNotConfirmPackageContents, isError: true)
            return
        }
        guard !isSessionResetting, !isCompletingPasteIntent else { return }

        Task { await completePasteIntent(intent, receiptAtIntent: receiptAtIntent, promptAtIntent: promptAtIntent) }
    }

    /// Port of `CompletePasteIntentAsync` (`:194-230`): runs the Codex Desktop text catch-up
    /// (SPEC §5.4), then rotates the session if the package really was consumed.
    private func completePasteIntent(_ intent: PasteIntent, receiptAtIntent: ClipboardSnapshot, promptAtIntent: String) async {
        isCompletingPasteIntent = true
        defer { isCompletingPasteIntent = false }

        let result = await withCheckedContinuation { (continuation: CheckedContinuation<CodexPasteCompletionResult, Never>) in
            codexPasteCompletion.complete(
                intent: intent, ownedPackageReceipt: receiptAtIntent, immutablePromptText: promptAtIntent
            ) { completion in continuation.resume(returning: completion) }
        }

        // A newer capture may have replaced the package while completion was waiting: never
        // rotate that newer session in response to this older paste intent (`:204-205`).
        guard ownedClipboardReceipt?.sequence == receiptAtIntent.sequence else { return }

        if let textReceipt = result.textClipboardReceipt {
            ownedClipboardReceipt = textReceipt
        }

        switch result.status {
        case .completedUnverified:
            await startNewSession()
        case .notApplicable:
            // Pasted our package somewhere other than Codex Desktop — still rotate, as long as
            // our package is (still) what's actually on the clipboard.
            let sequence = ownedClipboardReceipt?.sequence
            let stillOurs = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                clipboard.capture { continuation.resume(returning: sequence != nil && $0.sequence == sequence) }
            }
            if stillOurs { await startNewSession() }
        case .failed:
            let message = result.error.map { "\($0)" } ?? result.message
            stackWindow?.setStatus(StatusStrings.pasteObservedButSessionNotStarted(message), isError: true)
        default:
            stackWindow?.setStatus(StatusStrings.capturesSavedButPasteIncomplete(result.message), isError: true)
        }
    }

    // MARK: - Settings (SPEC §1.17)

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

    /// Returns `true` if it is safe to terminate (forced save succeeded).
    func prepareForQuit() async -> Bool {
        let saved = await save()
        if !saved { stackWindow?.reveal() }
        return saved
    }

    func shutdown() {
        hotkeyService.unregisterAll()
        pasteIntentObserver.stop()
    }
}
