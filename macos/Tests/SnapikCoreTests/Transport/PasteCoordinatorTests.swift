// XCTest port of tests/Snapik.Windows.Tests/PasteCoordinatorTests.cs, SPEC §8.3 items 27-37, 43.
//
// Not ported (no Core/Foundation equivalent, or macOS-replaced per the task brief):
// - 34 (Enter-in-gesture half): structurally impossible — macOS gestures are `Bool` (Cmd+V/
//   Option+V), there is no way to construct an Enter gesture. The "single package must share one
//   gesture" half is ported below.
// - 35 `NativeInputLayout_MatchesWin32Abi`, 38 `DibEncoder_WritesStandardBottomUpBitmapInfo`,
//   39 `StaWorkQueue_HasStaApartmentAndMessageDispatcher`: Windows OLE/STA-specific, no Core
//   equivalent; see `Tests/SnapikMacTests/Transport` for the macOS analogues (CGEvent
//   construction, NSPasteboard package formatting).
// - 40-42 (`PngDataObject_...`, `SingleImagePackage_...`, `MultiImagePackage_...`): exercise
//   `WindowsClipboardService`'s OLE `DataObject` construction directly; the macOS analogue
//   (`MacClipboardService` writing to `NSPasteboard`) is a Mac-target concern, covered in
//   `Tests/SnapikMacTests/Transport`.
// - 43 `EmptyPackage_IsRejectedBeforeClipboardAccess`: folded into
//   `testEmptyImagePathsAreRejectedBeforeAnyClipboardAccess` below (validated through the
//   coordinator's public `paste` entry point rather than a private data-object constructor).

import XCTest
@testable import SnapikCore

final class PasteCoordinatorTests: XCTestCase {
    /// Mirrors the old private `FakeTarget`'s fixed target constant.
    private static let target = ForegroundTarget(
        processName: "Target", bundleIdentifier: nil, windowTitle: "Draft", windowId: 1, focusedElementId: "2")

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnapikCoreTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    // 27. StagedPaste_PreservesOrder_NeverUsesEnter_AndCanBeVerified
    func testStagedPastePreservesOrderAndCanBeVerified() throws {
        let package = try makePackage(count: 3)
        let clipboard = FakeClipboard(sequence: 10)
        let input = FakeGuardedInput()
        let observer = FakeObserver(images: [.accepted, .accepted, .accepted], text: .accepted)
        let coordinator = PasteCoordinator(clipboard: clipboard, foreground: FakeTarget(Self.target), input: input, observer: observer)

        var result: PasteResult?
        coordinator.paste(package: package, profile: Self.profile()) { result = $0 }

        let final = try XCTUnwrap(result)
        XCTAssertEqual(final.status, .completedVerified)
        XCTAssertEqual(clipboard.writes, package.imagePaths + ["TEXT"])
        XCTAssertEqual(input.gestures.count, 4)
        XCTAssertEqual(final.imagesConfirmed, 3)
        XCTAssertTrue(final.textConfirmed)
    }

    // 28. ExternalClipboardWrite_BeforeNextStage_IsNotOverwritten
    func testExternalClipboardWriteBeforeNextStageIsNotOverwritten() throws {
        let package = try makePackage(count: 2)
        let clipboard = FakeClipboard(sequence: 10)
        let observer = FakeObserver(images: [.accepted])
        observer.afterImage = { _ in clipboard.externalWrite() }
        let coordinator = PasteCoordinator(clipboard: clipboard, foreground: FakeTarget(Self.target), input: FakeGuardedInput(), observer: observer)

        var result: PasteResult?
        coordinator.paste(package: package, profile: Self.profile()) { result = $0 }

        let final = try XCTUnwrap(result)
        XCTAssertEqual(final.status, .clipboardChanged)
        XCTAssertEqual(clipboard.writes, [package.imagePaths[0]])
    }

    // 29. CancellationAfterDispatch_PreservesPartialProgress
    func testCancellationAfterDispatchPreservesPartialProgress() throws {
        let package = try makePackage(count: 2)
        let token = PasteCancellationToken()
        let observer = FakeObserver(images: [.accepted])
        observer.beforeImage = { _ in token.cancel() }
        let coordinator = PasteCoordinator(clipboard: FakeClipboard(sequence: 10), foreground: FakeTarget(Self.target), input: FakeGuardedInput(), observer: observer)

        var result: PasteResult?
        coordinator.paste(package: package, profile: Self.profile(), cancellationToken: token) { result = $0 }

        let final = try XCTUnwrap(result)
        XCTAssertEqual(final.status, .cancelled)
        XCTAssertEqual(final.imagesDispatched, 1)
        XCTAssertEqual(final.imagesConfirmed, 0)
    }

    // 30. TimeoutAfterConfirmedPrefix_ProvidesSafeResumeBoundary
    func testTimeoutAfterConfirmedPrefixProvidesSafeResumeBoundary() throws {
        let package = try makePackage(count: 3)
        let observer = FakeObserver(images: [.accepted, .timedOut])
        let coordinator = PasteCoordinator(clipboard: FakeClipboard(sequence: 10), foreground: FakeTarget(Self.target), input: FakeGuardedInput(), observer: observer)

        var result: PasteResult?
        coordinator.paste(package: package, profile: Self.profile()) { result = $0 }

        let final = try XCTUnwrap(result)
        XCTAssertEqual(final.status, .acceptanceTimedOut)
        XCTAssertEqual(final.imagesDispatched, 2)
        XCTAssertEqual(final.imagesConfirmed, 1)
        XCTAssertEqual(final.safeResumeToken?.confirmedImageCount, 1)
    }

    // 31. UnobservableStep_RemovesSafeResumeBoundary_AndReportsUnverified
    func testUnobservableStepRemovesSafeResumeBoundaryAndReportsUnverified() throws {
        let package = try makePackage(count: 2)
        let observer = FakeObserver(images: [.notObservable, .accepted], text: .notObservable)
        let coordinator = PasteCoordinator(clipboard: FakeClipboard(sequence: 10), foreground: FakeTarget(Self.target), input: FakeGuardedInput(), observer: observer)

        var result: PasteResult?
        coordinator.paste(package: package, profile: Self.profile()) { result = $0 }

        let final = try XCTUnwrap(result)
        XCTAssertEqual(final.status, .completedUnverified)
        XCTAssertNil(final.safeResumeToken)
        XCTAssertFalse(final.deliveryWasObserved)
    }

    // 32. FocusedChildChange_StopsBeforeAnyClipboardWrite
    func testFocusedChildChangeStopsBeforeAnyClipboardWrite() throws {
        let package = try makePackage(count: 1)
        let target = FakeTarget(Self.target)
        // Call 1 is the coordinator's initial, unconditional capture (must still succeed); call 2
        // is the first `checkTarget` re-check inside `stageImage`, before any clipboard write
        // (must observe the target as gone).
        var checks = 0
        target.beforeCurrentTarget = {
            checks += 1
            if checks >= 2 { target.current = nil }
        }
        let clipboard = FakeClipboard(sequence: 10)
        let coordinator = PasteCoordinator(clipboard: clipboard, foreground: target, input: FakeGuardedInput(), observer: FakeObserver(images: []))

        var result: PasteResult?
        coordinator.paste(package: package, profile: Self.profile()) { result = $0 }

        let final = try XCTUnwrap(result)
        XCTAssertEqual(final.status, .targetChanged)
        XCTAssertTrue(clipboard.writes.isEmpty)
    }

    // 33. SinglePackage_DoesNotInferTextAcceptanceFromImages
    func testSinglePackageDoesNotInferTextAcceptanceFromImages() throws {
        let package = try makePackage(count: 2)
        let observer = FakeObserver(images: [])
        observer.package = PackageAcceptanceOutcome(images: .accepted, text: .notObservable)
        let profile = Self.profile(transport: .singleClipboardPackage, image: false, text: false)
        let coordinator = PasteCoordinator(clipboard: FakeClipboard(sequence: 10), foreground: FakeTarget(Self.target), input: FakeGuardedInput(), observer: observer)

        var result: PasteResult?
        coordinator.paste(package: package, profile: profile) { result = $0 }

        let final = try XCTUnwrap(result)
        XCTAssertEqual(final.status, .completedUnverified)
        XCTAssertEqual(final.imagesConfirmed, 2)
        XCTAssertFalse(final.textConfirmed)
    }

    // 34 (half). ProfilesRejectEnterAndSinglePackageWithTwoGestures — the Enter half is
    // structurally impossible on macOS (see file header); only the shared-gesture rule remains.
    func testProfileValidationRejectsSharedGestureMismatchForSinglePackage() {
        let profile = Self.profile(transport: .singleClipboardPackage, image: false, text: true)
        XCTAssertThrowsError(try profile.validate())
    }

    // 37. Coordinator_EnforcesObserverTimeout
    func testCoordinatorEnforcesObserverTimeout() throws {
        let package = try makePackage(count: 1)
        let profile = TargetProfile(
            id: "timeout", displayName: "Timeout", transport: .stagedSequence,
            imagePasteIsAlternate: true, textPasteIsAlternate: false,
            allowedBundleIdentifiers: [], allowedLocalizedNames: ["Target"],
            acceptanceTimeout: 0.02, unobservableSettlementDelay: 0, verification: .unverified)
        let coordinator = PasteCoordinator(clipboard: FakeClipboard(sequence: 10), foreground: FakeTarget(Self.target), input: FakeGuardedInput(), observer: NeverObserver())

        let expectation = expectation(description: "timeout")
        var result: PasteResult?
        coordinator.paste(package: package, profile: profile) {
            result = $0
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)

        let final = try XCTUnwrap(result)
        XCTAssertEqual(final.status, .acceptanceTimedOut)
        XCTAssertEqual(final.imagesDispatched, 1)
    }

    // 43. EmptyPackage_IsRejectedBeforeClipboardAccess (ported through the coordinator's public
    // entry point; there is no standalone `CreatePackageDataObject` equivalent to call directly).
    func testEmptyImagePathsAreRejectedBeforeAnyClipboardAccess() {
        let package = PreparedPastePackage(exportId: SBGuid(), imagePaths: [], promptText: "text")
        let clipboard = FakeClipboard(sequence: 10)
        let coordinator = PasteCoordinator(clipboard: clipboard, foreground: FakeTarget(Self.target), input: FakeGuardedInput(), observer: FakeObserver(images: []))

        var result: PasteResult?
        coordinator.paste(package: package, profile: Self.profile()) { result = $0 }

        XCTAssertEqual(result?.status, .invalidPackage)
        XCTAssertTrue(clipboard.writes.isEmpty)
    }

    // MARK: - Helpers

    private func makePackage(count: Int) throws -> PreparedPastePackage {
        var paths: [String] = []
        for index in 0..<count {
            let path = tempDirectory.appendingPathComponent("\(index).png").path
            try Data([137, 80, 78, 71]).write(to: URL(fileURLWithPath: path))
            paths.append(path)
        }
        return PreparedPastePackage(exportId: SBGuid(), imagePaths: paths, promptText: "Русский текст\nwith emoji 🧭")
    }

    private static func profile(
        transport: PasteTransport = .stagedSequence, image: Bool = true, text: Bool = false
    ) -> TargetProfile {
        TargetProfile(
            id: "test", displayName: "Test", transport: transport,
            imagePasteIsAlternate: image, textPasteIsAlternate: text,
            allowedBundleIdentifiers: [], allowedLocalizedNames: ["Target"],
            acceptanceTimeout: 1, unobservableSettlementDelay: 0, verification: .unverified)
    }
}

// MARK: - Fakes

private final class NeverObserver: PasteAcceptanceObserving {
    func waitForPackage(
        target: ForegroundTarget, profile: TargetProfile, cancellationToken: PasteCancellationToken,
        completion: @escaping (Result<PackageAcceptanceOutcome, Error>) -> Void
    ) {}
    func waitForImage(
        target: ForegroundTarget, imageIndex: Int, profile: TargetProfile, cancellationToken: PasteCancellationToken,
        completion: @escaping (Result<AcceptanceOutcome, Error>) -> Void
    ) {}
    func waitForText(
        target: ForegroundTarget, profile: TargetProfile, cancellationToken: PasteCancellationToken,
        completion: @escaping (Result<AcceptanceOutcome, Error>) -> Void
    ) {}
}

private final class FakeObserver: PasteAcceptanceObserving {
    private var imageOutcomes: [AcceptanceOutcome]
    private let textOutcome: AcceptanceOutcome
    var beforeImage: ((Int) -> Void)?
    var afterImage: ((Int) -> Void)?
    var package = PackageAcceptanceOutcome(images: .accepted, text: .accepted)

    init(images: [AcceptanceOutcome], text: AcceptanceOutcome = .accepted) {
        imageOutcomes = images
        textOutcome = text
    }

    func waitForPackage(
        target: ForegroundTarget, profile: TargetProfile, cancellationToken: PasteCancellationToken,
        completion: @escaping (Result<PackageAcceptanceOutcome, Error>) -> Void
    ) {
        completion(.success(package))
    }

    func waitForImage(
        target: ForegroundTarget, imageIndex: Int, profile: TargetProfile, cancellationToken: PasteCancellationToken,
        completion: @escaping (Result<AcceptanceOutcome, Error>) -> Void
    ) {
        beforeImage?(imageIndex)
        if cancellationToken.isCancelled {
            completion(.failure(TransportError.cancelled))
            return
        }
        let outcome = imageOutcomes.removeFirst()
        afterImage?(imageIndex)
        completion(.success(outcome))
    }

    func waitForText(
        target: ForegroundTarget, profile: TargetProfile, cancellationToken: PasteCancellationToken,
        completion: @escaping (Result<AcceptanceOutcome, Error>) -> Void
    ) {
        completion(.success(textOutcome))
    }
}
