// Port of the interception predicate in `EdgeStackWindow.xaml.cs:77-105`, SPEC-DELTA-2 Part 1
// §4.1; SPEC-DELTA-2A §4. Pulled out as a pure function (no `AppCoordinator` access) so it can be
// unit-tested without standing up the whole coordinator (`PasteInterceptPredicateTests.swift`).
import Foundation
import SnapBriefCore

/// Snapshot of the `AppCoordinator` state the predicate needs, gathered by
/// `AppCoordinator+PasteIntent.shouldInterceptPasteIntent(_:)`.
struct PasteInterceptState {
    var resetting: Bool
    var transitionInFlight: Bool
    var gateBusy: Bool
    var ownedSequence: Int?
    var promptPresent: Bool
    var preparedPresent: Bool
}

enum PasteInterceptPredicate {
    /// Port of Guard A/B/C plus the final decision (`EdgeStackWindow.xaml.cs:77-105`). Called
    /// synchronously from inside `MacPasteIntentObserver`'s tap callback (SPEC-DELTA-2A §1.2), so
    /// this never performs I/O — only pure comparisons against already-captured state.
    static func evaluate(
        intent: PasteIntent, state: PasteInterceptState, codexProfile: TargetProfile
    ) -> (intercept: Bool, log: String) {
        // Guard A: SnapBrief itself is not in a state where an intercepted paste could be
        // completed (a session reset or a previous completion/republish is still in flight, the
        // clipboard hasn't settled since the last write, or the intent doesn't refer to the
        // package we currently own).
        guard
            !state.resetting, !state.transitionInFlight, !state.gateBusy,
            let ownedSequence = state.ownedSequence, ownedSequence == intent.clipboardSequence,
            state.promptPresent, state.preparedPresent
        else {
            let log =
                "PasteIntent predicate: state not ready (resetting=\(state.resetting), "
                + "transitionDone=\(!state.transitionInFlight), gate=\(state.gateBusy ? 1 : 0), "
                + "ownedSeq=\(state.ownedSequence.map(String.init) ?? "nil"), intentSeq=\(intent.clipboardSequence), "
                + "prompt=\(state.promptPresent), prepared=\(state.preparedPresent), "
                + "gesture=\(gestureLabel(intent.gesture)))"
            return (false, log)
        }

        // Guard B: on macOS every `PasteIntentGesture` case (Cmd+V, Ctrl+V, Option+V) is an
        // interceptable gesture (SPEC-DELTA-2A поправка) — there is no "other" gesture that could
        // reach this predicate — kept for structural parity with Windows' Ctrl+V/Alt+V check and
        // as a guard against a future gesture case being added without updating this predicate.
        guard intent.gesture == .commandV || intent.gesture == .controlV || intent.gesture == .optionV else {
            return (false, "PasteIntent predicate: gesture \(gestureLabel(intent.gesture)) not intercepted")
        }

        // Guard C: no usable foreground target. (Windows also re-fetches and compares HWND/PID
        // here to catch a race between the key event and predicate evaluation; macOS has no such
        // race — `intent.target` was captured synchronously, in the same tap callback invocation
        // that calls this predicate, SPEC-DELTA-2A §1.2: "intent.target берётся один раз в
        // callback и передаётся в предикат".)
        guard let target = intent.target else {
            return (false, "PasteIntent predicate: target mismatch (usable=false, process=n/a, hwnd=0 vs 0, pid=0 vs 0)")
        }

        let intercept = !codexProfile.matches(target)
        let log =
            "PasteIntent predicate: intercept=\(intercept), gesture=\(gestureLabel(intent.gesture)), "
            + "process=\(target.processName), title=\(target.windowTitle ?? ""), seq=\(intent.clipboardSequence)"
        return (intercept, log)
    }

    /// SPEC-DELTA-2A §6: "жест печатать `CmdV`/`CtrlV`/`OptionV`".
    static func gestureLabel(_ gesture: PasteIntentGesture) -> String {
        switch gesture {
        case .commandV: return "CmdV"
        case .controlV: return "CtrlV"
        case .optionV: return "OptionV"
        }
    }
}
