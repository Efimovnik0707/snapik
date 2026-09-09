// XCTest port of the Windows `CodexDesktopPasteCompletionServiceTests` additions for
// `CompleteSequentialAsync` ("universal per-image paste sequence for any foreground app",
// SPEC-DELTA-2 Part 1 commit `110839c`), plus the reusable-package tests (commits `a93ed58`,
// `e588ad0`). SPEC-DELTA-2A §2, §7.
//
// `completeSequential` always goes through `TransportScheduler.schedule` for its per-image/text
// delays (even with delay `0`, `DispatchQueue.asyncAfter` never fires synchronously), so every
// test here awaits an `XCTestExpectation`.

import XCTest
@testable import SnapBriefCore

final class SequentialPasteCompletionServiceTests: XCTestCase {
    private static let grokBot = ForegroundTarget(
        processName: "GrokBot", bundleIdentifier: "com.example.grokbot", windowTitle: "GrokBot",
        windowId: 301, focusedElementId: "401")
    private static let terminal = ForegroundTarget(
        processName: "Terminal", bundleIdentifier: MacTargetBundleIdentifiers.terminal, windowTitle: "zsh",
        windowId: 302, focusedElementId: "402")
    private static let codex = ForegroundTarget(
        processName: "Codex", bundleIdentifier: MacTargetBundleIdentifiers.codexDesktop, windowTitle: "Codex",
        windowId: 303, focusedElementId: "403")

    // testInterceptedCommandVInArbitraryAppDispatchesOrderedPngImagesThenTextViaCommandV (1 and 3)
    func testInterceptedCommandVInArbitraryAppDispatchesOrderedPngImagesThenTextViaCommandV() throws {
        for imagePaths in [["a.png"], ["a.png", "b.png", "c.png"]] {
            let clipboard = FakeClipboard(sequence: 10)
            let input = FakeGuardedInput()
            let service = Self.makeService(clipboard: clipboard, target: FakeTarget(Self.grokBot), input: input)

            let final = completeSequential(
                service, intent: Self.intent(gesture: .commandV, sequence: 10, target: Self.grokBot),
                receipt: Self.receipt(10), paths: imagePaths, prompt: "Снимок A.")

            XCTAssertEqual(final.status, .completedUnverified)
            XCTAssertEqual(clipboard.writes, imagePaths + ["TEXT"])
            XCTAssertEqual(clipboard.writtenText, "Снимок A.")
            XCTAssertEqual(input.gestures, Array(repeating: PasteIntentGesture.commandV, count: imagePaths.count) + [.commandV])
        }
    }

    // testInterceptedControlVInTerminalDispatchesImagesViaControlVThenTextViaCommandV (1 and 3)
    func testInterceptedControlVInTerminalDispatchesImagesViaControlVThenTextViaCommandV() throws {
        for imagePaths in [["a.png"], ["a.png", "b.png", "c.png"]] {
            let clipboard = FakeClipboard(sequence: 20)
            let input = FakeGuardedInput()
            let service = Self.makeService(clipboard: clipboard, target: FakeTarget(Self.terminal), input: input)

            let final = completeSequential(
                service, intent: Self.intent(gesture: .controlV, sequence: 20, target: Self.terminal),
                receipt: Self.receipt(20), paths: imagePaths, prompt: "Снимок B.")

            XCTAssertEqual(final.status, .completedUnverified)
            XCTAssertEqual(clipboard.writes, imagePaths + ["TEXT"])
            XCTAssertEqual(
                input.gestures, Array(repeating: PasteIntentGesture.controlV, count: imagePaths.count) + [.commandV])
        }
    }

    // testInterceptedOptionVDispatchesImagesViaOptionV
    func testInterceptedOptionVDispatchesImagesViaOptionV() throws {
        let clipboard = FakeClipboard(sequence: 30)
        let input = FakeGuardedInput()
        let service = Self.makeService(clipboard: clipboard, target: FakeTarget(Self.grokBot), input: input)

        let final = completeSequential(
            service, intent: Self.intent(gesture: .optionV, sequence: 30, target: Self.grokBot),
            receipt: Self.receipt(30), paths: ["a.png"], prompt: "text")

        XCTAssertEqual(final.status, .completedUnverified)
        XCTAssertEqual(input.gestures, [.optionV, .commandV])
    }

    // testUninterceptedIntentDoesNotWriteOrInject
    func testUninterceptedIntentDoesNotWriteOrInject() throws {
        let clipboard = FakeClipboard(sequence: 40)
        let input = FakeGuardedInput()
        let service = Self.makeService(clipboard: clipboard, target: FakeTarget(Self.grokBot), input: input)

        let final = completeSequential(
            service, intent: Self.intent(gesture: .commandV, sequence: 40, target: Self.grokBot, intercepted: false),
            receipt: Self.receipt(40), paths: ["a.png"], prompt: "text")

        XCTAssertEqual(final.status, .notApplicable)
        XCTAssertTrue(clipboard.writes.isEmpty)
        XCTAssertTrue(input.gestures.isEmpty)
    }

    // testInterceptedCodexDesktopIntentStaysOnCompletePathDoesNotWriteOrInject
    func testInterceptedCodexDesktopIntentStaysOnCompletePathDoesNotWriteOrInject() throws {
        let clipboard = FakeClipboard(sequence: 50)
        let input = FakeGuardedInput()
        let service = Self.makeService(clipboard: clipboard, target: FakeTarget(Self.codex), input: input)

        let final = completeSequential(
            service, intent: Self.intent(gesture: .commandV, sequence: 50, target: Self.codex),
            receipt: Self.receipt(50), paths: ["a.png"], prompt: "text")

        XCTAssertEqual(final.status, .notApplicable)
        XCTAssertTrue(clipboard.writes.isEmpty)
        XCTAssertTrue(input.gestures.isEmpty)
    }

    // testInterceptedIntentIsNotAlsoHandledByCodexCompletion
    func testInterceptedIntentIsNotAlsoHandledByCodexCompletion() throws {
        let clipboard = FakeClipboard(sequence: 60)
        let input = FakeGuardedInput()
        let service = Self.makeService(clipboard: clipboard, target: FakeTarget(Self.codex), input: input)

        let expectation = expectation(description: "codex complete")
        var result: CodexPasteCompletionResult?
        service.complete(
            intent: Self.intent(gesture: .commandV, sequence: 60, target: Self.codex),
            ownedPackageReceipt: Self.receipt(60), immutablePromptText: "text"
        ) { result = $0; expectation.fulfill() }
        wait(for: [expectation], timeout: 5)

        XCTAssertEqual(result?.status, .notApplicable)
        XCTAssertTrue(clipboard.writes.isEmpty)
    }

    // testStaleIntentAndEmptyPackageDoNotWriteOrInject
    func testStaleIntentAndEmptyPackageDoNotWriteOrInject() throws {
        let clipboard = FakeClipboard(sequence: 71)
        let input = FakeGuardedInput()
        let service = Self.makeService(clipboard: clipboard, target: FakeTarget(Self.grokBot), input: input)

        let stale = completeSequential(
            service, intent: Self.intent(gesture: .commandV, sequence: 70, target: Self.grokBot),
            receipt: Self.receipt(71), paths: ["a.png"], prompt: "text")
        XCTAssertEqual(stale.status, .staleIntent)

        let emptyImages = completeSequential(
            service, intent: Self.intent(gesture: .commandV, sequence: 71, target: Self.grokBot),
            receipt: Self.receipt(71), paths: [], prompt: "text")
        XCTAssertEqual(emptyImages.status, .nothingToDispatch)

        let emptyPrompt = completeSequential(
            service, intent: Self.intent(gesture: .commandV, sequence: 71, target: Self.grokBot),
            receipt: Self.receipt(71), paths: ["a.png"], prompt: "")
        XCTAssertEqual(emptyPrompt.status, .nothingToDispatch)

        XCTAssertTrue(clipboard.writes.isEmpty)
        XCTAssertTrue(input.gestures.isEmpty)
    }

    // testFocusChangeDuringPhysicalReleaseStopsBeforeAnyPasteShortcut
    func testFocusChangeDuringPhysicalReleaseStopsBeforeAnyPasteShortcut() throws {
        let clipboard = FakeClipboard(sequence: 80)
        let target = FakeTarget(Self.grokBot)
        let input = FakeGuardedInput()
        input.beforeFinalGuard = {
            target.current = ForegroundTarget(
                processName: "Other", bundleIdentifier: nil, windowTitle: "Other", windowId: 900, focusedElementId: "901")
        }
        let service = Self.makeService(clipboard: clipboard, target: target, input: input)

        let final = completeSequential(
            service, intent: Self.intent(gesture: .commandV, sequence: 80, target: Self.grokBot),
            receipt: Self.receipt(80), paths: ["a.png"], prompt: "text")

        XCTAssertEqual(final.status, .targetLost)
        XCTAssertEqual(clipboard.writes, ["a.png"])
        XCTAssertTrue(input.gestures.isEmpty)
    }

    // testFocusLossAfterFirstImagePasteReturnsCurrentReceiptAndStopsSequence
    func testFocusLossAfterFirstImagePasteReturnsCurrentReceiptAndStopsSequence() throws {
        let clipboard = FakeClipboard(sequence: 90)
        let target = FakeTarget(Self.grokBot)
        let input = FakeGuardedInput()
        input.afterDispatch = {
            target.current = ForegroundTarget(
                processName: "Other", bundleIdentifier: nil, windowTitle: "Other", windowId: 900, focusedElementId: "901")
        }
        let service = Self.makeService(clipboard: clipboard, target: target, input: input)

        let final = completeSequential(
            service, intent: Self.intent(gesture: .commandV, sequence: 90, target: Self.grokBot),
            receipt: Self.receipt(90), paths: ["a.png", "b.png"], prompt: "text")

        XCTAssertEqual(final.status, .targetLost)
        XCTAssertEqual(clipboard.writes, ["a.png"])
        XCTAssertEqual(input.gestures, [.commandV])
        XCTAssertEqual(final.textClipboardReceipt?.sequence, 91)
    }

    // testClipboardChangeAfterFirstImagePasteStopsBeforeSecondImageAndText
    func testClipboardChangeAfterFirstImagePasteStopsBeforeSecondImageAndText() throws {
        let clipboard = FakeClipboard(sequence: 100)
        let input = FakeGuardedInput()
        input.afterDispatch = { clipboard.externalWrite() }
        let service = Self.makeService(clipboard: clipboard, target: FakeTarget(Self.grokBot), input: input)

        let final = completeSequential(
            service, intent: Self.intent(gesture: .commandV, sequence: 100, target: Self.grokBot),
            receipt: Self.receipt(100), paths: ["a.png", "b.png"], prompt: "text")

        XCTAssertEqual(final.status, .clipboardChanged)
        XCTAssertEqual(clipboard.writes, ["a.png"])
        XCTAssertEqual(input.gestures, [.commandV])
    }

    // testCancellationAfterFirstImagePasteReturnsCurrentReceiptWithoutContinuing
    func testCancellationAfterFirstImagePasteReturnsCurrentReceiptWithoutContinuing() throws {
        let clipboard = FakeClipboard(sequence: 110)
        let input = FakeGuardedInput()
        let token = PasteCancellationToken()
        input.afterDispatch = { token.cancel() }
        let service = Self.makeService(clipboard: clipboard, target: FakeTarget(Self.grokBot), input: input)

        let final = completeSequential(
            service, intent: Self.intent(gesture: .commandV, sequence: 110, target: Self.grokBot),
            receipt: Self.receipt(110), paths: ["a.png", "b.png"], prompt: "text", cancellationToken: token)

        XCTAssertEqual(final.status, .cancelled)
        XCTAssertEqual(clipboard.writes, ["a.png"])
        XCTAssertEqual(input.gestures, [.commandV])
    }

    // testReusablePackageRepublishesFullPackageAfterCompletedPasteAndAcceptsNextIntent
    func testReusablePackageRepublishesFullPackageAfterCompletedPasteAndAcceptsNextIntent() throws {
        let clipboard = FakeClipboard(sequence: 120)
        let input = FakeGuardedInput()
        let service = Self.makeService(clipboard: clipboard, target: FakeTarget(Self.grokBot), input: input)

        let first = completeSequential(
            service, intent: Self.intent(gesture: .commandV, sequence: 120, target: Self.grokBot),
            receipt: Self.receipt(120), paths: ["a.png"], prompt: "Снимок A.")
        XCTAssertEqual(first.status, .completedUnverified)
        let afterFirst = try XCTUnwrap(first.currentClipboardReceipt)

        // The Core service itself only dispatches; republishing the reusable package for reuse is
        // an App-layer responsibility (`AppCoordinator+PasteIntent.republishPackageForReuse`,
        // SPEC-DELTA-2A §4). This exercises the primitive it relies on: a fresh
        // `setPackageGuarded` against the just-completed receipt succeeds and its resulting
        // sequence is what the *next* physical paste intent must carry to be accepted.
        let republishExpectation = expectation(description: "republish")
        var republished: ClipboardSnapshot?
        clipboard.setPackageGuarded(
            paths: ["a.png"], text: "Снимок A.", expectedSequence: afterFirst.sequence
        ) { result in
            if case .success(let receipt) = result { republished = receipt }
            republishExpectation.fulfill()
        }
        wait(for: [republishExpectation], timeout: 5)
        let republishedReceipt = try XCTUnwrap(republished)

        let second = completeSequential(
            service, intent: Self.intent(gesture: .commandV, sequence: republishedReceipt.sequence, target: Self.grokBot),
            receipt: republishedReceipt, paths: ["a.png"], prompt: "Снимок A.")
        XCTAssertEqual(second.status, .completedUnverified)
    }

    // testReusablePackageDisplacedByAnotherAppLeavesClipboardUntouched
    func testReusablePackageDisplacedByAnotherAppLeavesClipboardUntouched() throws {
        let clipboard = FakeClipboard(sequence: 130)
        let input = FakeGuardedInput()
        let service = Self.makeService(clipboard: clipboard, target: FakeTarget(Self.grokBot), input: input)

        let first = completeSequential(
            service, intent: Self.intent(gesture: .commandV, sequence: 130, target: Self.grokBot),
            receipt: Self.receipt(130), paths: ["a.png"], prompt: "Снимок A.")
        XCTAssertEqual(first.status, .completedUnverified)
        let afterFirst = try XCTUnwrap(first.currentClipboardReceipt)

        // Another app writes to the clipboard before SnapBrief republishes.
        clipboard.externalWrite()

        let republishExpectation = expectation(description: "republish rejected")
        var republishError: Error?
        clipboard.setPackageGuarded(
            paths: ["a.png"], text: "Снимок A.", expectedSequence: afterFirst.sequence
        ) { result in
            if case .failure(let error) = result { republishError = error }
            republishExpectation.fulfill()
        }
        wait(for: [republishExpectation], timeout: 5)

        XCTAssertNotNil(republishError)
        // The rejected guarded write must not have touched the clipboard's write log.
        XCTAssertEqual(clipboard.writes, ["a.png"])
    }

    // MARK: - Helpers

    private func completeSequential(
        _ service: CodexDesktopPasteCompletionService, intent: PasteIntent, receipt: ClipboardSnapshot,
        paths: [String], prompt: String, cancellationToken: PasteCancellationToken = PasteCancellationToken()
    ) -> CodexPasteCompletionResult {
        let expectation = expectation(description: "completeSequential")
        var result: CodexPasteCompletionResult?
        service.completeSequential(
            intent: intent, ownedPackageReceipt: receipt, immutableImagePaths: paths, immutablePromptText: prompt,
            cancellationToken: cancellationToken
        ) {
            result = $0
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
        return result ?? CodexPasteCompletionResult(status: .failed, message: "no result")
    }

    private static func makeService(
        clipboard: FakeClipboard, target: FakeTarget, input: FakeGuardedInput
    ) -> CodexDesktopPasteCompletionService {
        CodexDesktopPasteCompletionService(
            clipboard: clipboard, foreground: target, input: input, settlementDelay: 0, imageSettlementDelay: 0,
            altVImageSettlementDelay: 0)
    }

    private static func intent(
        gesture: PasteIntentGesture, sequence: Int, target: ForegroundTarget, intercepted: Bool = true
    ) -> PasteIntent {
        PasteIntent(
            gesture: gesture, timestamp: Date(), synthetic: false, target: target, clipboardSequence: sequence,
            intercepted: intercepted)
    }

    private static func receipt(_ sequence: Int) -> ClipboardSnapshot {
        ClipboardSnapshot(sequence: sequence, hasText: false, text: nil, filePaths: [], hasImage: false)
    }
}
