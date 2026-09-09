// Port of Windows/CodexDesktopPasteCompletionService.cs, SPEC §5.4.
//
// Practical verification showed Codex Desktop accepts the PNG from the clipboard but ignores the
// text in the same clipboard write. After the user's physical Cmd+V, this service performs a
// guarded second step: wait, re-verify everything, put only the prompt text on the clipboard, and
// repeat Cmd+V. Enter is never sent (structurally impossible: `InputInjecting.injectPaste` only
// knows Cmd+V/Option+V). Messages are the literal Windows English strings (SPEC §5.4 quotes them
// verbatim; internal diagnostics, not translated per Q6 — this service's text was already English
// on Windows).

import Foundation

public final class CodexDesktopPasteCompletionService {
    public static let defaultSettlementDelay: TimeInterval = 0.5
    /// Port of `DefaultImageSettlementDelay` (SPEC-DELTA-2A §2): per-image delay after a Cmd+V
    /// image paste in `completeSequential`.
    public static let defaultImageSettlementDelay: TimeInterval = 0.7
    /// Port of `DefaultAltVImageSettlementDelay` (SPEC-DELTA-2A §2, поправка): per-image delay
    /// after a Ctrl+V/Option+V image paste — both non-`.commandV` gestures use this longer delay.
    public static let defaultAltVImageSettlementDelay: TimeInterval = 1.2

    private let clipboard: ClipboardServicing
    private let foreground: ForegroundTargetServicing
    private let input: GuardedInputInjecting
    private let codexProfile: TargetProfile
    private let settlementDelay: TimeInterval
    private let imageSettlementDelay: TimeInterval
    private let altVImageSettlementDelay: TimeInterval
    private let scheduler: TransportScheduler

    public init(
        clipboard: ClipboardServicing,
        foreground: ForegroundTargetServicing,
        input: GuardedInputInjecting,
        codexProfile: TargetProfile = BuiltInTargetProfiles.codexDesktop,
        settlementDelay: TimeInterval = CodexDesktopPasteCompletionService.defaultSettlementDelay,
        imageSettlementDelay: TimeInterval = CodexDesktopPasteCompletionService.defaultImageSettlementDelay,
        altVImageSettlementDelay: TimeInterval = CodexDesktopPasteCompletionService.defaultAltVImageSettlementDelay,
        scheduler: TransportScheduler = DispatchQueueScheduler()
    ) {
        precondition(settlementDelay >= 0)
        precondition(imageSettlementDelay >= 0)
        precondition(altVImageSettlementDelay >= 0)
        self.clipboard = clipboard
        self.foreground = foreground
        self.input = input
        self.codexProfile = codexProfile
        self.settlementDelay = settlementDelay
        self.imageSettlementDelay = imageSettlementDelay
        self.altVImageSettlementDelay = altVImageSettlementDelay
        self.scheduler = scheduler
    }

    /// Port of `CompleteAsync` (`:25-108`). SPEC-DELTA-2A §2: intercepted intents (SPEC-DELTA-2A
    /// §1) are handled by `completeSequential` instead — `!intent.intercepted` is guarded first.
    public func complete(
        intent: PasteIntent,
        ownedPackageReceipt: ClipboardSnapshot,
        immutablePromptText: String,
        cancellationToken: PasteCancellationToken = PasteCancellationToken(),
        completion: @escaping (CodexPasteCompletionResult) -> Void
    ) {
        // Captured synchronously, before any delay, so the focused element reflects the moment
        // this method was invoked rather than after the settlement wait (`:34-35`).
        let target = foreground.currentTarget()
        guard
            !intent.intercepted,
            !intent.alternate,
            let target,
            let intentTarget = intent.target,
            target == intentTarget,
            codexProfile.matches(target)
        else {
            completion(Self.result(
                .notApplicable, "Paste completion applies only to a physical Ctrl+V in Codex Desktop."))
            return
        }

        if intent.clipboardSequence != ownedPackageReceipt.sequence {
            completion(Self.result(.staleIntent, "The paste intent does not refer to SnapBrief's current package."))
            return
        }
        if immutablePromptText.isEmpty {
            completion(Self.result(.nothingToDispatch, "The package has no prompt text to paste."))
            return
        }

        scheduler.schedule(after: settlementDelay) { [weak self] in
            guard let self else { return }
            if cancellationToken.isCancelled {
                completion(Self.result(.cancelled, "The guarded text paste was cancelled."))
                return
            }
            self.clipboard.capture { snapshot in
                guard snapshot.sequence == ownedPackageReceipt.sequence else {
                    completion(Self.result(.clipboardChanged, "The clipboard changed before the text paste."))
                    return
                }
                guard let recheckedTarget = self.foreground.currentTarget(), recheckedTarget == target else {
                    completion(Self.result(.targetLost, "Codex focus changed before the text paste."))
                    return
                }

                self.clipboard.setTextGuarded(
                    text: immutablePromptText, expectedSequence: ownedPackageReceipt.sequence
                ) { writeResult in
                    switch writeResult {
                    case .failure(let error):
                        completion(Self.result(.clipboardChanged, Self.clipboardChangedMessage(for: error), error: error))
                    case .success(let textReceipt):
                        self.dispatch(
                            target: target, textReceipt: textReceipt, cancellationToken: cancellationToken,
                            completion: completion)
                    }
                }
            }
        }
    }

    /// Port of step 9 (`:91-98`): guarded Ctrl+V, with the final re-check immediately before
    /// injection (after waiting for physical key release, per SPEC §5.6).
    private func dispatch(
        target: ForegroundTarget, textReceipt: ClipboardSnapshot, cancellationToken: PasteCancellationToken,
        completion: @escaping (CodexPasteCompletionResult) -> Void
    ) {
        var rejectedStatus = CodexPasteCompletionStatus.clipboardChanged
        input.injectPasteGuarded(
            alternate: false,
            finalGuard: { guardCompletion in
                self.clipboard.capture { latest in
                    if latest.sequence != textReceipt.sequence {
                        rejectedStatus = .clipboardChanged
                        guardCompletion(false)
                        return
                    }
                    guard let latestTarget = self.foreground.currentTarget(), latestTarget == target else {
                        rejectedStatus = .targetLost
                        guardCompletion(false)
                        return
                    }
                    guardCompletion(true)
                }
            },
            completion: { dispatched in
                if !dispatched {
                    let message = rejectedStatus == .targetLost
                        ? "Codex focus changed while the paste keys were being released."
                        : "The clipboard changed while the paste keys were being released."
                    completion(Self.result(rejectedStatus, message, receipt: textReceipt))
                    return
                }
                completion(Self.result(
                    .completedUnverified,
                    "Prompt text paste was dispatched to Codex; receiver acceptance was not observable.",
                    receipt: textReceipt))
            })
    }

    // MARK: - completeSequential (SPEC-DELTA-2A §2, port of `CompleteSequentialAsync`,
    // `CodexDesktopPasteCompletionService.cs:121-205`)

    /// Universal per-image paste sequence for any foreground app whose physical Ctrl+V/Option+V
    /// SnapBrief intercepted (SPEC-DELTA-2A §1): publish image 1 alone, guarded-send the intent's
    /// own gesture, wait `perImageDelay`, repeat for every remaining image, then publish the
    /// prompt text alone and guarded-send Cmd+V (text is always Cmd+V, поправка).
    public func completeSequential(
        intent: PasteIntent,
        ownedPackageReceipt: ClipboardSnapshot,
        immutableImagePaths: [String],
        immutablePromptText: String,
        cancellationToken: PasteCancellationToken = PasteCancellationToken(),
        completion: @escaping (CodexPasteCompletionResult) -> Void
    ) {
        // Captured synchronously, before any I/O, mirroring `complete`'s `:34-35` guard timing.
        let target = foreground.currentTarget()
        guard
            intent.intercepted,
            let target,
            let intentTarget = intent.target,
            target == intentTarget,
            !codexProfile.matches(target)
        else {
            completion(Self.result(
                .notApplicable,
                "Intercepted paste completion applies only to a physical Ctrl+V or Alt+V outside Codex Desktop."))
            return
        }

        guard intent.clipboardSequence == ownedPackageReceipt.sequence else {
            completion(Self.result(.staleIntent, "The paste intent does not refer to SnapBrief's current package."))
            return
        }

        guard !immutableImagePaths.isEmpty, !immutablePromptText.isEmpty else {
            completion(Self.result(.nothingToDispatch, "The package needs at least one image and prompt text."))
            return
        }

        let perImageDelay = intent.gesture == .commandV ? imageSettlementDelay : altVImageSettlementDelay
        stageImage(
            index: 0, expectedSequence: ownedPackageReceipt.sequence, target: target,
            imagePaths: immutableImagePaths, promptText: immutablePromptText, gesture: intent.gesture,
            perImageDelay: perImageDelay, cancellationToken: cancellationToken, completion: completion)
    }

    /// Port of the per-image loop body (`:158-186`): publish image `index` alone, guarded-send
    /// `gesture`, wait, re-verify, then either stage the next image or move on to the text step.
    private func stageImage(
        index: Int, expectedSequence: Int, target: ForegroundTarget, imagePaths: [String], promptText: String,
        gesture: PasteIntentGesture, perImageDelay: TimeInterval, cancellationToken: PasteCancellationToken,
        completion: @escaping (CodexPasteCompletionResult) -> Void
    ) {
        if cancellationToken.isCancelled {
            completion(Self.result(.cancelled, "The guarded sequential paste was cancelled."))
            return
        }

        clipboard.setPNGGuarded(path: imagePaths[index], expectedSequence: expectedSequence) { [weak self] writeResult in
            guard let self else { return }
            switch writeResult {
            case .failure(let error):
                completion(Self.result(
                    .clipboardChanged,
                    Self.clipboardChangedMessage(
                        for: error, fallback: "The clipboard changed before image \(index + 1) could be published.")))
            case .success(let receipt):
                self.sendImageGuarded(
                    index: index, receipt: receipt, target: target, imagePaths: imagePaths, promptText: promptText,
                    gesture: gesture, perImageDelay: perImageDelay, cancellationToken: cancellationToken,
                    completion: completion)
            }
        }
    }

    /// Port of the guarded Ctrl+V/Alt+V dispatch for one staged image plus its post-dispatch
    /// re-verification (`:170-186`): the final re-check happens immediately before injection
    /// (after waiting for physical key release, SPEC §5.6); a second re-check happens after
    /// `perImageDelay` elapses, before moving on.
    private func sendImageGuarded(
        index: Int, receipt: ClipboardSnapshot, target: ForegroundTarget, imagePaths: [String], promptText: String,
        gesture: PasteIntentGesture, perImageDelay: TimeInterval, cancellationToken: PasteCancellationToken,
        completion: @escaping (CodexPasteCompletionResult) -> Void
    ) {
        var rejectedStatus = CodexPasteCompletionStatus.clipboardChanged
        input.injectPasteGuarded(
            gesture: gesture,
            finalGuard: { [weak self] guardCompletion in
                guard let self else { guardCompletion(false); return }
                self.clipboard.capture { latest in
                    if latest.sequence != receipt.sequence {
                        rejectedStatus = .clipboardChanged
                        guardCompletion(false)
                        return
                    }
                    guard let latestTarget = self.foreground.currentTarget(), latestTarget == target else {
                        rejectedStatus = .targetLost
                        guardCompletion(false)
                        return
                    }
                    guardCompletion(true)
                }
            },
            completion: { [weak self] dispatched in
                guard let self else { return }
                if !dispatched {
                    let message =
                        (rejectedStatus == .targetLost ? "Claude focus changed" : "The clipboard changed")
                        + " while the image \(index + 1) paste keys were being released."
                    completion(Self.result(rejectedStatus, message, receipt: receipt))
                    return
                }

                self.scheduler.schedule(after: perImageDelay) { [weak self] in
                    guard let self else { return }
                    if cancellationToken.isCancelled {
                        completion(Self.result(.cancelled, "The guarded sequential paste was cancelled."))
                        return
                    }
                    self.clipboard.capture { latest in
                        guard latest.sequence == receipt.sequence else {
                            completion(Self.result(
                                .clipboardChanged, "The clipboard changed after image \(index + 1) paste.",
                                receipt: receipt))
                            return
                        }
                        guard let latestTarget = self.foreground.currentTarget(), latestTarget == target else {
                            completion(Self.result(
                                .targetLost, "Focus changed after image \(index + 1) paste.", receipt: receipt))
                            return
                        }

                        if index + 1 < imagePaths.count {
                            self.stageImage(
                                index: index + 1, expectedSequence: receipt.sequence, target: target,
                                imagePaths: imagePaths, promptText: promptText, gesture: gesture,
                                perImageDelay: perImageDelay, cancellationToken: cancellationToken,
                                completion: completion)
                        } else {
                            self.stageText(
                                expectedSequence: receipt.sequence, target: target, promptText: promptText,
                                cancellationToken: cancellationToken, completion: completion)
                        }
                    }
                }
            })
    }

    /// Port of the trailing text step (`:187-198`): publish the prompt text alone, then guarded-
    /// send Cmd+V (text is always Cmd+V, поправка) — never the intent's own gesture.
    private func stageText(
        expectedSequence: Int, target: ForegroundTarget, promptText: String,
        cancellationToken: PasteCancellationToken, completion: @escaping (CodexPasteCompletionResult) -> Void
    ) {
        if cancellationToken.isCancelled {
            completion(Self.result(.cancelled, "The guarded sequential paste was cancelled."))
            return
        }

        clipboard.setTextGuarded(text: promptText, expectedSequence: expectedSequence) { [weak self] writeResult in
            guard let self else { return }
            switch writeResult {
            case .failure(let error):
                completion(Self.result(
                    .clipboardChanged,
                    Self.clipboardChangedMessage(for: error, fallback: "The clipboard changed before the text could be published.")))
            case .success(let textReceipt):
                var rejectedStatus = CodexPasteCompletionStatus.clipboardChanged
                self.input.injectPasteGuarded(
                    gesture: .commandV,
                    finalGuard: { [weak self] guardCompletion in
                        guard let self else { guardCompletion(false); return }
                        self.clipboard.capture { latest in
                            if latest.sequence != textReceipt.sequence {
                                rejectedStatus = .clipboardChanged
                                guardCompletion(false)
                                return
                            }
                            guard let latestTarget = self.foreground.currentTarget(), latestTarget == target else {
                                rejectedStatus = .targetLost
                                guardCompletion(false)
                                return
                            }
                            guardCompletion(true)
                        }
                    },
                    completion: { dispatched in
                        if !dispatched {
                            let message =
                                (rejectedStatus == .targetLost ? "Claude focus changed" : "The clipboard changed")
                                + " while the text paste keys were being released."
                            completion(Self.result(rejectedStatus, message, receipt: textReceipt))
                            return
                        }
                        completion(Self.result(
                            .completedUnverified,
                            "Image and prompt paste shortcuts were dispatched in order; receiver acceptance was not observable.",
                            receipt: textReceipt))
                    })
            }
        }
    }

    private static func result(
        _ status: CodexPasteCompletionStatus, _ message: String, receipt: ClipboardSnapshot? = nil,
        error: Error? = nil
    ) -> CodexPasteCompletionResult {
        CodexPasteCompletionResult(status: status, message: message, textClipboardReceipt: receipt, error: error)
    }

    /// Port of the `catch (ClipboardChangedException ex)` branch (`:96-98`), which surfaces the
    /// exception's own message.
    private static func clipboardChangedMessage(for error: Error) -> String {
        if case TransportError.clipboardChanged(let message) = error { return message }
        return "The clipboard changed before the text paste."
    }

    /// Overload used by `completeSequential`/`stageImage`/`stageText`, whose fallback message
    /// varies by step (image index vs. text).
    private static func clipboardChangedMessage(for error: Error, fallback: String) -> String {
        if case TransportError.clipboardChanged(let message) = error { return message }
        return fallback
    }
}
