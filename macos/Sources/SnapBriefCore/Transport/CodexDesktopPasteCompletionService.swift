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

    private let clipboard: ClipboardServicing
    private let foreground: ForegroundTargetServicing
    private let input: GuardedInputInjecting
    private let codexProfile: TargetProfile
    private let settlementDelay: TimeInterval
    private let scheduler: TransportScheduler

    public init(
        clipboard: ClipboardServicing,
        foreground: ForegroundTargetServicing,
        input: GuardedInputInjecting,
        codexProfile: TargetProfile = BuiltInTargetProfiles.codexDesktop,
        settlementDelay: TimeInterval = CodexDesktopPasteCompletionService.defaultSettlementDelay,
        scheduler: TransportScheduler = DispatchQueueScheduler()
    ) {
        precondition(settlementDelay >= 0)
        self.clipboard = clipboard
        self.foreground = foreground
        self.input = input
        self.codexProfile = codexProfile
        self.settlementDelay = settlementDelay
        self.scheduler = scheduler
    }

    /// Port of `CompleteAsync` (`:25-108`).
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
}
