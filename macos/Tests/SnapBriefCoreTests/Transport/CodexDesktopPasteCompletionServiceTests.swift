// XCTest port of tests/SnapBrief.Windows.Tests/CodexDesktopPasteCompletionServiceTests.cs,
// SPEC §8.3 items 44-56 (13 tests).
//
// `CodexDesktopPasteCompletionService.complete` always goes through `TransportScheduler.schedule`
// for the settlement delay (even with `settlementDelay: 0`, `DispatchQueue.asyncAfter` never
// fires synchronously), so every test here awaits an `XCTestExpectation` instead of reading the
// completion's captured result immediately.

import XCTest
@testable import SnapBriefCore

final class CodexDesktopPasteCompletionServiceTests: XCTestCase {
    private static let codex = ForegroundTarget(
        processName: "ChatGPT", bundleIdentifier: MacTargetBundleIdentifiers.chatGPT, windowTitle: "ChatGPT",
        windowId: 101, focusedElementId: "202")

    // 44. PhysicalCodexCtrlV_StagesAndDispatchesImmutableText_Unverified
    func testPhysicalCodexCtrlVStagesAndDispatchesImmutableTextUnverified() throws {
        let clipboard = FakeClipboard(sequence: 41)
        let target = FakeTarget(Self.codex)
        let input = FakeGuardedInput()
        let service = Self.makeService(clipboard: clipboard, target: target, input: input)

        let final = complete(service, intent: Self.intent(sequence: 41), receipt: Self.receipt(41), text: "Снимок A.")

        XCTAssertEqual(final.status, .completedUnverified)
        XCTAssertEqual(clipboard.writtenText, "Снимок A.")
        XCTAssertEqual(final.textClipboardReceipt, Self.textReceipt(42, text: "Снимок A."))
        XCTAssertEqual(input.gestures, [.commandV])
        XCTAssertFalse(final.message.lowercased().contains("accepted"))
    }

    // 45-47. UnknownOrMismatchedTarget_IsNotApplicableAndDoesNotInject
    func testUnknownOrMismatchedTargetIsNotApplicableAndDoesNotInject() throws {
        let cases: [(process: String, windowId: Int, focusedElementId: String)] = [
            ("Code", 101, "202"),
            ("ChatGPT", 999, "202"),
            ("ChatGPT", 101, "999"),
        ]
        for testCase in cases {
            let clipboard = FakeClipboard(sequence: 41)
            let input = FakeGuardedInput()
            let target = FakeTarget(ForegroundTarget(
                processName: testCase.process, bundleIdentifier: nil, windowTitle: testCase.process,
                windowId: testCase.windowId, focusedElementId: testCase.focusedElementId))
            let service = Self.makeService(clipboard: clipboard, target: target, input: input)

            let final = complete(service, intent: Self.intent(sequence: 41), receipt: Self.receipt(41), text: "text")

            XCTAssertEqual(final.status, .notApplicable)
            XCTAssertNil(clipboard.writtenText)
            XCTAssertTrue(input.gestures.isEmpty)
        }
    }

    // 48. StaleIntentSequence_DoesNotWriteOrInject
    func testStaleIntentSequenceDoesNotWriteOrInject() throws {
        let clipboard = FakeClipboard(sequence: 42)
        let input = FakeGuardedInput()
        let service = Self.makeService(clipboard: clipboard, target: FakeTarget(Self.codex), input: input)

        let final = complete(service, intent: Self.intent(sequence: 41), receipt: Self.receipt(42), text: "text")

        XCTAssertEqual(final.status, .staleIntent)
        XCTAssertNil(clipboard.writtenText)
        XCTAssertTrue(input.gestures.isEmpty)
    }

    // 49. FocusChangeDuringSettlement_DoesNotWriteOrInject
    func testFocusChangeDuringSettlementDoesNotWriteOrInject() throws {
        let clipboard = FakeClipboard(sequence: 41)
        let target = FakeTarget(Self.codex)
        // Call 1 is the synchronous initial capture (must succeed); call 2 is the settlement
        // re-check before the text write (must observe the target as lost).
        var checks = 0
        target.beforeCurrentTarget = {
            checks += 1
            if checks >= 2 { target.current = nil }
        }
        let input = FakeGuardedInput()
        let service = Self.makeService(clipboard: clipboard, target: target, input: input)

        let final = complete(service, intent: Self.intent(sequence: 41), receipt: Self.receipt(41), text: "text")

        XCTAssertEqual(final.status, .targetLost)
        XCTAssertNil(clipboard.writtenText)
        XCTAssertTrue(input.gestures.isEmpty)
    }

    // 50. ClipboardChangeDuringSettlement_DoesNotWriteOrInject
    func testClipboardChangeDuringSettlementDoesNotWriteOrInject() throws {
        let clipboard = FakeClipboard(sequence: 42)
        let input = FakeGuardedInput()
        let service = Self.makeService(clipboard: clipboard, target: FakeTarget(Self.codex), input: input)

        let final = complete(service, intent: Self.intent(sequence: 41), receipt: Self.receipt(41), text: "text")

        XCTAssertEqual(final.status, .clipboardChanged)
        XCTAssertNil(clipboard.writtenText)
        XCTAssertTrue(input.gestures.isEmpty)
    }

    // 51. FocusLossAfterTextWrite_ReturnsReceiptButDoesNotInject
    func testFocusLossAfterTextWriteReturnsReceiptButDoesNotInject() throws {
        let clipboard = FakeClipboard(sequence: 41)
        let target = FakeTarget(Self.codex)
        // Call 1 = initial capture, call 2 = settlement re-check (both must still see the target),
        // call 3 = the finalGuard re-check right before injection (must observe it lost).
        var checks = 0
        target.beforeCurrentTarget = {
            checks += 1
            if checks >= 3 { target.current = nil }
        }
        let input = FakeGuardedInput()
        let service = Self.makeService(clipboard: clipboard, target: target, input: input)

        let final = complete(service, intent: Self.intent(sequence: 41), receipt: Self.receipt(41), text: "text")

        XCTAssertEqual(final.status, .targetLost)
        XCTAssertEqual(final.textClipboardReceipt, Self.textReceipt(42, text: "text"))
        XCTAssertTrue(input.gestures.isEmpty)
    }

    // 52. GuardedClipboardWriteFailure_IsReportedAndDoesNotInject
    func testGuardedClipboardWriteFailureIsReportedAndDoesNotInject() throws {
        let clipboard = FakeClipboard(sequence: 41)
        clipboard.failNextWrite = true
        let input = FakeGuardedInput()
        let service = Self.makeService(clipboard: clipboard, target: FakeTarget(Self.codex), input: input)

        let final = complete(service, intent: Self.intent(sequence: 41), receipt: Self.receipt(41), text: "text")

        XCTAssertEqual(final.status, .clipboardChanged)
        XCTAssertTrue(input.gestures.isEmpty)
    }

    // 53. ClipboardChangeAfterTextWrite_ReturnsReceiptButDoesNotInject
    func testClipboardChangeAfterTextWriteReturnsReceiptButDoesNotInject() throws {
        let clipboard = FakeClipboard(sequence: 41)
        clipboard.changeAfterWrite = true
        let input = FakeGuardedInput()
        let service = Self.makeService(clipboard: clipboard, target: FakeTarget(Self.codex), input: input)

        let final = complete(service, intent: Self.intent(sequence: 41), receipt: Self.receipt(41), text: "text")

        XCTAssertEqual(final.status, .clipboardChanged)
        XCTAssertEqual(final.textClipboardReceipt, Self.textReceipt(42, text: "text"))
        XCTAssertTrue(input.gestures.isEmpty)
    }

    // 54. FocusChangeDuringPhysicalReleaseWait_PreventsDispatch
    func testFocusChangeDuringPhysicalReleaseWaitPreventsDispatch() throws {
        let clipboard = FakeClipboard(sequence: 41)
        let target = FakeTarget(Self.codex)
        let input = FakeGuardedInput()
        input.beforeFinalGuard = {
            target.current = ForegroundTarget(
                processName: "Other", bundleIdentifier: nil, windowTitle: "Other", windowId: 900, focusedElementId: "901")
        }
        let service = Self.makeService(clipboard: clipboard, target: target, input: input)

        let final = complete(service, intent: Self.intent(sequence: 41), receipt: Self.receipt(41), text: "text")

        XCTAssertEqual(final.status, .targetLost)
        XCTAssertEqual(final.textClipboardReceipt, Self.textReceipt(42, text: "text"))
        XCTAssertTrue(input.gestures.isEmpty)
    }

    // 55. ClipboardChangeDuringPhysicalReleaseWait_PreventsDispatch
    func testClipboardChangeDuringPhysicalReleaseWaitPreventsDispatch() throws {
        let clipboard = FakeClipboard(sequence: 41)
        let input = FakeGuardedInput()
        input.beforeFinalGuard = { clipboard.externalWrite() }
        let service = Self.makeService(clipboard: clipboard, target: FakeTarget(Self.codex), input: input)

        let final = complete(service, intent: Self.intent(sequence: 41), receipt: Self.receipt(41), text: "text")

        XCTAssertEqual(final.status, .clipboardChanged)
        XCTAssertEqual(final.textClipboardReceipt, Self.textReceipt(42, text: "text"))
        XCTAssertTrue(input.gestures.isEmpty)
    }

    // 56. AltVAndEmptyPrompt_DoNotInject
    func testAltVAndEmptyPromptDoNotInject() throws {
        let clipboard = FakeClipboard(sequence: 41)
        let input = FakeGuardedInput()
        let service = Self.makeService(clipboard: clipboard, target: FakeTarget(Self.codex), input: input)

        let altResult = complete(service, intent: Self.intent(sequence: 41, alternate: true), receipt: Self.receipt(41), text: "text")
        let emptyResult = complete(service, intent: Self.intent(sequence: 41), receipt: Self.receipt(41), text: "")

        XCTAssertEqual(altResult.status, .notApplicable)
        XCTAssertEqual(emptyResult.status, .nothingToDispatch)
        XCTAssertTrue(input.gestures.isEmpty)
    }

    // MARK: - Helpers

    private func complete(
        _ service: CodexDesktopPasteCompletionService, intent: PasteIntent, receipt: ClipboardSnapshot, text: String
    ) -> CodexPasteCompletionResult {
        let expectation = expectation(description: "codex paste completion")
        var result: CodexPasteCompletionResult?
        service.complete(intent: intent, ownedPackageReceipt: receipt, immutablePromptText: text) {
            result = $0
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
        return result ?? CodexPasteCompletionResult(status: .failed, message: "no result")
    }

    private static func makeService(
        clipboard: FakeClipboard, target: FakeTarget, input: FakeGuardedInput
    ) -> CodexDesktopPasteCompletionService {
        CodexDesktopPasteCompletionService(clipboard: clipboard, foreground: target, input: input, settlementDelay: 0)
    }

    private static func intent(sequence: Int, alternate: Bool = false) -> PasteIntent {
        PasteIntent(
            gesture: alternate ? .optionV : .commandV, timestamp: Date(), synthetic: false, target: codex,
            clipboardSequence: sequence)
    }

    private static func receipt(_ sequence: Int) -> ClipboardSnapshot {
        ClipboardSnapshot(sequence: sequence, hasText: false, text: nil, filePaths: [], hasImage: false)
    }

    /// Expected shape of the receipt returned by `setTextGuarded` (step 8, SPEC §5.4 `:2091`):
    /// the clipboard now holds only the written text.
    private static func textReceipt(_ sequence: Int, text: String) -> ClipboardSnapshot {
        ClipboardSnapshot(sequence: sequence, hasText: true, text: text, filePaths: [], hasImage: false)
    }
}
