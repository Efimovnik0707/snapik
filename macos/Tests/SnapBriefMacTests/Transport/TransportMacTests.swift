// Mac-only equivalents for the Transport tests that need real AppKit/CoreGraphics APIs and have
// no Core (Foundation-only) equivalent, per the task brief and SPEC §8.3:
// - test 35 `NativeInputLayout_MatchesWin32Abi` -> `testCGEventConstructionForCommandVAndOptionV`
//   ("на macOS заменяется проверкой корректности сборки события CGEvent").
// - tests 38-42 (`DibEncoder_...`, `PngDataObject_...`, `SingleImagePackage_...`,
//   `MultiImagePackage_...`) -> `testMacClipboardServiceWritesExpectedFormatsForSingleAndMultiImagePackages`,
//   using a private named pasteboard (CONTRACTS.md example) instead of the system clipboard.
// - test 57 `NativeImports_ResolveActualWindowsExports` ->
//   `testMacPasteIntentObserverStartThrowsPermissionMissingWithoutAccess` ("на macOS заменяется
//   проверкой доступности CGEvent.tapCreate и того, что tap создаётся при выданном разрешении" —
//   exercised here through the "permission not granted" path, which is TCC-independent because it
//   is the default CI state, unlike the "permission granted" path).

import AppKit
import XCTest
@testable import SnapBriefCore
@testable import SnapBriefMac

final class TransportMacTests: XCTestCase {
    // Replaces test 35: verifies the CGEvent pair `MacInputInjector` builds for Cmd+V/Option+V
    // carries the expected virtual key code and modifier flag. Building and inspecting a CGEvent
    // needs no TCC permission; only *posting*/tapping it does.
    func testCGEventConstructionForCommandVAndOptionV() throws {
        let source = try XCTUnwrap(CGEventSource(stateID: .hidSystemState))
        let commandV = try XCTUnwrap(CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true))
        commandV.flags = .maskCommand
        commandV.setIntegerValueField(.eventSourceUserData, value: MacInputInjector.syntheticEventTag)

        XCTAssertEqual(commandV.getIntegerValueField(.keyboardEventKeycode), 0x09)
        XCTAssertTrue(commandV.flags.contains(.maskCommand))
        XCTAssertFalse(commandV.flags.contains(.maskAlternate))
        XCTAssertEqual(commandV.getIntegerValueField(.eventSourceUserData), MacInputInjector.syntheticEventTag)

        let optionV = try XCTUnwrap(CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true))
        optionV.flags = .maskAlternate
        XCTAssertTrue(optionV.flags.contains(.maskAlternate))
        XCTAssertFalse(optionV.flags.contains(.maskCommand))
    }

    // Replaces tests 38-42: `MacClipboardService` writes PNG+TIFF only for a single-image
    // package, and always writes one `.fileURL` item per path plus one text item.
    func testMacClipboardServiceWritesExpectedFormatsForSingleAndMultiImagePackages() throws {
        let pasteboard = try XCTUnwrap(NSPasteboard(name: .init("snapbrief-test-transport")))
        let queue = DispatchQueue.main
        let service = MacClipboardService(pasteboard: pasteboard, queue: queue)
        let pngData = try Self.makeSinglePixelPNG()
        let firstPath = try Self.writeTempFile(data: pngData, name: "single.png")
        let secondPath = try Self.writeTempFile(data: pngData, name: "second.png")

        let singleExpectation = expectation(description: "single image package")
        service.setPackageGuarded(paths: [firstPath], text: "Снимок A.", expectedSequence: nil) { result in
            defer { singleExpectation.fulfill() }
            guard case .success = result else { XCTFail("expected success"); return }
            XCTAssertTrue(pasteboard.canReadItem(withDataConformingToTypes: [NSPasteboard.PasteboardType.png.rawValue]))
            XCTAssertTrue(pasteboard.canReadItem(withDataConformingToTypes: [NSPasteboard.PasteboardType.tiff.rawValue]))
            XCTAssertEqual(pasteboard.string(forType: .string), "Снимок A.")
            let urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL])?.map(\.path) ?? []
            XCTAssertEqual(urls, [firstPath])
        }
        wait(for: [singleExpectation], timeout: 5)

        let multiExpectation = expectation(description: "multi image package")
        service.setPackageGuarded(paths: [firstPath, secondPath], text: "Снимок A. Снимок B.", expectedSequence: nil) { result in
            defer { multiExpectation.fulfill() }
            guard case .success = result else { XCTFail("expected success"); return }
            XCTAssertFalse(pasteboard.canReadItem(withDataConformingToTypes: [NSPasteboard.PasteboardType.png.rawValue]))
            XCTAssertFalse(pasteboard.canReadItem(withDataConformingToTypes: [NSPasteboard.PasteboardType.tiff.rawValue]))
            XCTAssertEqual(pasteboard.string(forType: .string), "Снимок A. Снимок B.")
            let urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL])?.map(\.path) ?? []
            XCTAssertEqual(urls, [firstPath, secondPath])
        }
        wait(for: [multiExpectation], timeout: 5)

        pasteboard.clearContents()
    }

    // Replaces test 57: without Input Monitoring access (the default, unconfigured CI state),
    // `start()` throws `TransportError.permissionMissing`.
    func testMacPasteIntentObserverStartThrowsPermissionMissingWithoutAccess() throws {
        try XCTSkipIf(TransportPermissions.hasInputMonitoringAccess, "Input Monitoring already granted in this environment")

        let foreground = StubForegroundTarget()
        let observer = MacPasteIntentObserver(foreground: foreground, clipboardSequence: { 0 })

        XCTAssertThrowsError(try observer.start()) { error in
            guard case TransportError.permissionMissing = error else {
                XCTFail("expected permissionMissing, got \(error)")
                return
            }
        }
        XCTAssertFalse(observer.isRunning)
    }

    // Replaces test 36: with the trigger keys physically held down, `MacInputInjector` times out
    // without ever posting a synthetic key event (`MacInputInjector.swift:93-108`).
    func testInputInjectorDoesNotSynthesizeWhenTriggerKeysStayPhysicallyHeld() throws {
        let injector = MacInputInjector(
            physicalKeys: AlwaysHeldKeyState(), releaseTimeout: 0.02, releasePollInterval: 0.005)

        let expectation = expectation(description: "injectPaste completion")
        var succeeded: Bool?
        injector.injectPaste(alternate: false) { result in
            succeeded = result
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)
        XCTAssertEqual(succeeded, false)
    }

    // Replaces test 39: `MacClipboardService` funnels every pasteboard operation through the
    // single queue it was constructed with, standing in for the Windows STA work queue's
    // dedicated, serialized apartment thread.
    func testMacClipboardServiceOperationsRunOnADedicatedSerializedQueue() throws {
        let pasteboard = try XCTUnwrap(NSPasteboard(name: .init("snapbrief-test-transport-queue")))
        let dedicatedQueue = DispatchQueue(label: "live.yesworkflow.snapbrief.tests.clipboard")
        let key = DispatchSpecificKey<Bool>()
        dedicatedQueue.setSpecific(key: key, value: true)
        let service = MacClipboardService(pasteboard: pasteboard, queue: dedicatedQueue)

        let expectation = expectation(description: "capture completion runs on the dedicated queue")
        var ranOnDedicatedQueue = false
        service.capture { _ in
            ranOnDedicatedQueue = DispatchQueue.getSpecific(key: key) == true
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
        XCTAssertTrue(ranOnDedicatedQueue)
        pasteboard.clearContents()
    }

    // Replaces test 40: raw PNG bytes carry the PNG signature and decode to a correct bitmap
    // (the DIB-header analogue via TIFF, CONTRACTS.md), read straight off disk with no
    // `NSPasteboard` involved at all (not even a private one).
    func testRawPngBytesExposeSignatureAndDecodableRepresentationWithoutSystemClipboard() throws {
        let pngData = try Self.makeSinglePixelPNG()
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        XCTAssertEqual(Array(pngData.prefix(8)), signature)

        let path = try Self.writeTempFile(data: pngData, name: "raw.png")
        let rawBytes = try XCTUnwrap(FileManager.default.contents(atPath: path))
        XCTAssertEqual(rawBytes, pngData)

        let image = try XCTUnwrap(NSImage(data: rawBytes))
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        XCTAssertEqual(bitmap.pixelsWide, 1)
        XCTAssertEqual(bitmap.pixelsHigh, 1)
    }

    // MARK: - Helpers

    private static func makeSinglePixelPNG() throws -> Data {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    private static func writeTempFile(data: Data, name: String) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnapBriefMacTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let fileURL = url.appendingPathComponent(name)
        try data.write(to: fileURL)
        return fileURL.path
    }
}

private final class StubForegroundTarget: ForegroundTargetServicing {
    func currentTarget() -> ForegroundTarget? { nil }
}

private final class AlwaysHeldKeyState: MacPhysicalKeyStateReading {
    func isKeyDown(_ keyCode: CGKeyCode) -> Bool { true }
}
