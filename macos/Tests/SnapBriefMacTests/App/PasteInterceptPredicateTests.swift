// XCTest for `PasteInterceptPredicate` (SPEC-DELTA-2A §4, §7): a pure function, so these are
// direct unit tests with no `AppCoordinator` involved.

import XCTest
@testable import SnapBriefCore
@testable import SnapBriefMac

final class PasteInterceptPredicateTests: XCTestCase {
    private static let codexProfile = BuiltInTargetProfiles.codexDesktop
    private static let arbitraryApp = ForegroundTarget(
        processName: "GrokBot", bundleIdentifier: "com.example.grokbot", windowTitle: "GrokBot", windowId: 1,
        focusedElementId: "2")
    private static let codexApp = ForegroundTarget(
        processName: "Codex", bundleIdentifier: MacTargetBundleIdentifiers.codexDesktop, windowTitle: "Codex",
        windowId: 3, focusedElementId: "4")

    private static let readyState = PasteInterceptState(
        resetting: false, transitionInFlight: false, gateBusy: false, ownedSequence: 10, promptPresent: true,
        preparedPresent: true)

    // Guard A: any "not ready" condition declines interception and logs "state not ready".
    func testGuardADeclinesWhenStateIsNotReady() {
        let notReadyCases: [PasteInterceptState] = [
            {
                var state = Self.readyState
                state.resetting = true
                return state
            }(),
            {
                var state = Self.readyState
                state.transitionInFlight = true
                return state
            }(),
            {
                var state = Self.readyState
                state.gateBusy = true
                return state
            }(),
            {
                var state = Self.readyState
                state.ownedSequence = nil
                return state
            }(),
            {
                var state = Self.readyState
                state.ownedSequence = 999
                return state
            }(),
            {
                var state = Self.readyState
                state.promptPresent = false
                return state
            }(),
            {
                var state = Self.readyState
                state.preparedPresent = false
                return state
            }(),
        ]

        for state in notReadyCases {
            let (intercept, log) = PasteInterceptPredicate.evaluate(
                intent: Self.intent(gesture: .commandV, sequence: 10, target: Self.arbitraryApp),
                state: state, codexProfile: Self.codexProfile)
            XCTAssertFalse(intercept)
            XCTAssertTrue(log.hasPrefix("PasteIntent predicate: state not ready"))
        }
    }

    // Guard B: every macOS gesture (Cmd+V, Ctrl+V, Option+V) is interceptable; none is declined
    // by Guard B alone (only Guard A/C or the profile match can decline).
    func testGuardBAcceptsEveryMacGesture() {
        for gesture: PasteIntentGesture in [.commandV, .controlV, .optionV] {
            let (intercept, log) = PasteInterceptPredicate.evaluate(
                intent: Self.intent(gesture: gesture, sequence: 10, target: Self.arbitraryApp),
                state: Self.readyState, codexProfile: Self.codexProfile)
            XCTAssertTrue(intercept)
            XCTAssertTrue(log.hasPrefix("PasteIntent predicate: intercept=true"))
        }
    }

    // Guard C: no foreground target -> declined with the "target mismatch" log.
    func testGuardCDeclinesWithoutATarget() {
        let (intercept, log) = PasteInterceptPredicate.evaluate(
            intent: Self.intent(gesture: .commandV, sequence: 10, target: nil), state: Self.readyState,
            codexProfile: Self.codexProfile)
        XCTAssertFalse(intercept)
        XCTAssertTrue(log.hasPrefix("PasteIntent predicate: target mismatch"))
    }

    // Decision: Codex Desktop is excluded from interception (SPEC-DELTA-2A §1.2 "Исключение Codex
    // Desktop — в предикате координатора"); every other app is intercepted.
    func testDecisionExcludesCodexDesktopButInterceptsOtherApps() {
        let codexResult = PasteInterceptPredicate.evaluate(
            intent: Self.intent(gesture: .commandV, sequence: 10, target: Self.codexApp), state: Self.readyState,
            codexProfile: Self.codexProfile)
        XCTAssertFalse(codexResult.intercept)
        XCTAssertTrue(codexResult.log.contains("intercept=false"))

        let arbitraryResult = PasteInterceptPredicate.evaluate(
            intent: Self.intent(gesture: .commandV, sequence: 10, target: Self.arbitraryApp), state: Self.readyState,
            codexProfile: Self.codexProfile)
        XCTAssertTrue(arbitraryResult.intercept)
        XCTAssertTrue(arbitraryResult.log.contains("intercept=true"))
    }

    private static func intent(gesture: PasteIntentGesture, sequence: Int, target: ForegroundTarget?) -> PasteIntent {
        PasteIntent(gesture: gesture, timestamp: Date(), synthetic: false, target: target, clipboardSequence: sequence)
    }
}
