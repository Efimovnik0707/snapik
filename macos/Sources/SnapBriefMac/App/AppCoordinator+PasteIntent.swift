// Port of the intercepted-paste-intent handling and reusable-package rotation in
// `EdgeStackWindow.xaml.cs`, SPEC-DELTA-2 Part 1 §4.3-§4.8; SPEC-DELTA-2A §4-§6.
//
// Split out of `AppCoordinator+Package.swift` per SPEC-DELTA-2A §4 ("Новый файл
// AppCoordinator+PasteIntent.swift ... из +Package.swift уходят handlePasteIntent/
// completePasteIntent"): this is the multi-image, reusable-package rewrite of what used to be a
// single Codex-only text catch-up.
import Foundation
import SnapBriefCore

extension AppCoordinator {
    private static let receiverEchoWatchWindow: TimeInterval = 6
    private static let receiverEchoPollInterval: TimeInterval = 0.2

    // MARK: - Predicate wiring (SPEC-DELTA-2A §4)

    /// The `shouldIntercept` closure passed to `MacPasteIntentObserver.init` (`AppCoordinator.init`,
    /// invoked synchronously from inside the tap callback via `MainActor.assumeIsolated`).
    func shouldInterceptPasteIntent(_ intent: PasteIntent) -> Bool {
        let state = PasteInterceptState(
            resetting: isSessionResetting,
            transitionInFlight: pasteIntentTransition != nil,
            gateBusy: clipboardPublicationGate.isBusy,
            ownedSequence: ownedClipboardReceipt?.sequence,
            promptPresent: !(ownedClipboardPromptText ?? "").isEmpty,
            preparedPresent: prepared != nil)
        let (intercept, log) = PasteInterceptPredicate.evaluate(
            intent: intent, state: state, codexProfile: BuiltInTargetProfiles.codexDesktop)
        logPasteIntent(log)
        return intercept
    }

    // MARK: - Observed intent (Part 1 §4.3, `OnPasteIntentObserved`)

    /// Port of `OnPasteIntentObserved` (`:179-192`).
    func handlePasteIntent(_ intent: PasteIntent) {
        logPasteIntent(
            "PasteIntent observed: gesture=\(PasteInterceptPredicate.gestureLabel(intent.gesture)), "
            + "intercepted=\(intent.intercepted), seq=\(intent.clipboardSequence), "
            + "ownedSeq=\(ownedClipboardReceipt.map { String($0.sequence) } ?? "nil"), "
            + "pid=\(ProcessInfo.processInfo.processIdentifier)")

        guard let receiptAtIntent = ownedClipboardReceipt, intent.clipboardSequence == receiptAtIntent.sequence else {
            // Pasted something that wasn't our current package.
            logClipboardDiagnostics()
            return
        }
        guard let promptAtIntent = ownedClipboardPromptText else {
            stackWindow?.setStatus(StatusStrings.couldNotConfirmPackageContents, isError: true)
            return
        }
        guard
            !isSessionResetting, pasteIntentTransition == nil, !clipboardPublicationGate.isBusy,
            ownedClipboardReceipt == receiptAtIntent
        else { return }

        let pathsAtIntent = prepared?.imagePathsInOrder().map(\.path) ?? []
        pasteIntentTransition = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.completePasteIntent(
                intent, receiptAtIntent: receiptAtIntent, promptAtIntent: promptAtIntent, pathsAtIntent: pathsAtIntent)
            self.pasteIntentTransition = nil
        }
    }

    // MARK: - Completion (Part 1 §4.4/§4.5, `CompletePasteIntentAsync`/`CompleteSequentialAsync`)

    /// Port of `CompletePasteIntentAsync` (`:194-230`): runs the intercepted per-image sequence
    /// (`completeSequential`) or the Codex Desktop text catch-up (`complete`), then either
    /// republishes the reusable package or rotates the session, depending on what happened.
    private func completePasteIntent(
        _ intent: PasteIntent, receiptAtIntent: ClipboardSnapshot, promptAtIntent: String, pathsAtIntent: [String]
    ) async {
        await clipboardPublicationGate.wait()
        defer { clipboardPublicationGate.release() }

        let result: CodexPasteCompletionResult
        if intent.intercepted {
            result = await withCheckedContinuation { (continuation: CheckedContinuation<CodexPasteCompletionResult, Never>) in
                codexPasteCompletion.completeSequential(
                    intent: intent, ownedPackageReceipt: receiptAtIntent, immutableImagePaths: pathsAtIntent,
                    immutablePromptText: promptAtIntent
                ) { continuation.resume(returning: $0) }
            }
        } else {
            result = await withCheckedContinuation { (continuation: CheckedContinuation<CodexPasteCompletionResult, Never>) in
                codexPasteCompletion.complete(
                    intent: intent, ownedPackageReceipt: receiptAtIntent, immutablePromptText: promptAtIntent
                ) { continuation.resume(returning: $0) }
            }
        }

        logPasteIntent(
            "PasteIntent completion: intercepted=\(intent.intercepted), images=\(pathsAtIntent.count), "
            + "status=\(result.status), message=\(result.message)")

        // A newer capture may have replaced the package while completion was waiting: never act
        // on that newer session in response to this older paste intent (`:204-205`).
        guard ownedClipboardReceipt?.sequence == receiptAtIntent.sequence else { return }

        if let receipt = result.currentClipboardReceipt {
            ownedClipboardReceipt = receipt
        }

        switch result.status {
        case .completedUnverified:
            await republishPackageForReuse(paths: pathsAtIntent, prompt: promptAtIntent)
        case .notApplicable where !intent.intercepted:
            // Pasted our package somewhere other than Codex Desktop, and Codex's own text
            // catch-up declined (wrong app/gesture) — still rotate, as long as our package is
            // (still) what's actually on the clipboard.
            let sequence = ownedClipboardReceipt?.sequence
            let snapshot = await captureClipboardSnapshot()
            if let sequence, snapshot.sequence == sequence { await startNewSession() }
        default:
            stackWindow?.setStatus(
                StatusStrings.capturesSavedButPasteIncomplete(result.message, language: language), isError: true)
        }
    }

    // MARK: - Reusable package (Part 1 §4.6, `RepublishPackageForReuseAsync`)

    /// Port of `RepublishPackageForReuseAsync` (`:317-344`), called from inside
    /// `completePasteIntent`'s `clipboardPublicationGate` critical section.
    func republishPackageForReuse(paths: [String], prompt: String) async {
        guard let current = ownedClipboardReceipt, let preparedExport = prepared else {
            stackWindow?.setStatus(StatusStrings.packageDisplaced(language: language), isError: true)
            return
        }
        let noteCount = preparedExport.manifest.noteCount

        let result = await setPackageGuardedAsync(paths: paths, text: prompt, expectedSequence: current.sequence)
        switch result {
        case .success(let receipt):
            ownedClipboardReceipt = receipt
            ownedClipboardPromptText = prompt
            pasteObservedForCurrentPackage = true
            logPasteIntent("PasteIntent republished package: seq=\(receipt.sequence), images=\(paths.count)")
            stackWindow?.setStatus(
                StatusStrings.pastedAndRepublished(imageCount: paths.count, noteCount: noteCount, language: language),
                isError: false)
            startReceiverEchoWatch(paths: paths, prompt: prompt)
        case .failure:
            cancelReceiverEchoWatch()
            ownedClipboardReceipt = nil
            ownedClipboardPromptText = nil
            stackWindow?.setStatus(StatusStrings.packageDisplaced(language: language), isError: true)
        }
    }

    // MARK: - Receiver echo watch (Part 1 §4.7)

    /// Port of `WatchForReceiverEchoAsync` (`:346-417`). One active watch per package: a fresh
    /// call always cancels whatever watch is already running first.
    func startReceiverEchoWatch(paths: [String], prompt: String) {
        cancelReceiverEchoWatch()
        let token = UUID()
        receiverEchoWatchToken = token
        receiverEchoWatchTask = Task { @MainActor [weak self] in
            await self?.watchForReceiverEcho(paths: paths, prompt: prompt, token: token)
            if self?.receiverEchoWatchToken == token {
                self?.receiverEchoWatchTask = nil
                self?.receiverEchoWatchToken = nil
            }
        }
    }

    func cancelReceiverEchoWatch() {
        receiverEchoWatchTask?.cancel()
        receiverEchoWatchTask = nil
        receiverEchoWatchToken = nil
    }

    private func watchForReceiverEcho(paths: [String], prompt: String, token: UUID) async {
        var deadline = Date().addingTimeInterval(Self.receiverEchoWatchWindow)

        while !Task.isCancelled, receiverEchoWatchToken == token, Date() < deadline {
            try? await Task.sleep(nanoseconds: UInt64(Self.receiverEchoPollInterval * 1_000_000_000))
            guard !Task.isCancelled, receiverEchoWatchToken == token else { return }
            guard let receipt = ownedClipboardReceipt else { return }

            let snapshot = await captureClipboardSnapshot()
            guard receiverEchoWatchToken == token else { return }
            if snapshot.sequence == receipt.sequence { continue }

            guard ClipboardEchoDetector.isReceiverEcho(snapshot, promptText: prompt) else {
                logPasteIntent("PasteIntent package displaced by foreign clipboard write")
                return
            }

            await clipboardPublicationGate.wait()
            guard receiverEchoWatchToken == token else {
                clipboardPublicationGate.release()
                return
            }
            let rearmResult = await setPackageGuardedAsync(paths: paths, text: prompt, expectedSequence: snapshot.sequence)
            clipboardPublicationGate.release()

            switch rearmResult {
            case .success(let newReceipt):
                logPasteIntent("PasteIntent re-armed after receiver echo: from seq \(receipt.sequence) to \(newReceipt.sequence)")
                ownedClipboardReceipt = newReceipt
                ownedClipboardPromptText = prompt
                deadline = Date().addingTimeInterval(Self.receiverEchoWatchWindow)
            case .failure:
                logPasteIntent("PasteIntent package displaced by foreign clipboard write")
                return
            }
        }
    }

    // MARK: - Diagnostics (SPEC-DELTA-2A §6)

    func logPasteIntent(_ message: String) {
        StartupLog.write(options, message)
    }

    /// Port of `LogClipboardDiagnosticsAsync`. `capture(_:)` never fails on macOS (see
    /// `ensureCurrentCaptureSession`'s doc comment in `AppCoordinator.swift`), so the "Clipboard
    /// diagnostics failed: {message}" line has no reachable Mac call site.
    private func logClipboardDiagnostics() {
        clipboard.capture { [weak self] snapshot in
            guard let self else { return }
            let formats = (self.clipboard as? MacClipboardService)?.diagnosticTypes() ?? []
            let preview = (snapshot.text ?? "<no text>")
                .replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "\n", with: "|")
            let truncated = preview.count > 120 ? String(preview.prefix(120)) : preview
            self.logPasteIntent(
                "Clipboard diagnostics: seq=\(snapshot.sequence), owner=n/a, "
                + "formats=[\(formats.joined(separator: ","))], text=\(truncated)")
        }
    }

    // MARK: - Small async wrappers shared by this file

    private func captureClipboardSnapshot() async -> ClipboardSnapshot {
        await withCheckedContinuation { continuation in clipboard.capture { continuation.resume(returning: $0) } }
    }

    private func setPackageGuardedAsync(
        paths: [String], text: String, expectedSequence: Int?
    ) async -> Result<ClipboardSnapshot, Error> {
        await withCheckedContinuation { continuation in
            clipboard.setPackageGuarded(paths: paths, text: text, expectedSequence: expectedSequence) {
                continuation.resume(returning: $0)
            }
        }
    }
}
