// XCTest port of tests/Snapik.Windows.Tests/PasteIntentObserverTests.cs, SPEC §8.3 items 58-62.
// Item 57 (`NativeImports_ResolveActualWindowsExports`) is Mac-replaced per the task brief; see
// `Tests/SnapikMacTests/Transport` for the `CGEvent.tapCreate`/permission-gated equivalent.
//
// Windows tracks individual left/right Control/Alt/Shift/Windows key codes via a `HashSet`; the
// macOS port (`PasteIntentKeyState`) tracks the same held-set idea through the abstract
// `PasteIntentModifierKey` (Command/Option/Shift/Control) instead of raw keycodes, since
// `CGEventFlags` does not distinguish left/right variants. Each test below is the direct
// behavioral analogue of its Windows counterpart, substituting Command for Control and Option for
// Alt.

import XCTest
@testable import SnapikCore

final class PasteIntentKeyStateTests: XCTestCase {
    // 58. ControlV_IsReportedOnceUntilVIsReleased -> CommandV analogue.
    func testCommandVIsReportedOnceUntilVIsReleased() {
        let state = PasteIntentKeyState()
        state.observeModifier(.command, isKeyDown: true, isInjected: false)
        XCTAssertEqual(state.observeV(isKeyDown: true, isInjected: false), .commandV)
        XCTAssertNil(state.observeV(isKeyDown: true, isInjected: false))
        XCTAssertNil(state.observeV(isKeyDown: false, isInjected: false))
        XCTAssertEqual(state.observeV(isKeyDown: true, isInjected: false), .commandV)
    }

    // 59. AltV_IsReportedWithEitherAltKey -> OptionV analogue (CGEventFlags does not distinguish
    // left/right Option, so there is only one case to exercise here).
    func testOptionVIsReported() {
        let state = PasteIntentKeyState()
        state.observeModifier(.option, isKeyDown: true, isInjected: false)
        XCTAssertEqual(state.observeV(isKeyDown: true, isInjected: false), .optionV)
    }

    // 60. PlainV_ControlAltV_ExtraModifierV_AndInjectedV_AreIgnored.
    func testPlainCommandAndOptionTogetherExtraModifierAndInjectedVAreIgnored() {
        let plain = PasteIntentKeyState()
        XCTAssertNil(plain.observeV(isKeyDown: true, isInjected: false))

        let both = PasteIntentKeyState()
        both.observeModifier(.command, isKeyDown: true, isInjected: false)
        both.observeModifier(.option, isKeyDown: true, isInjected: false)
        XCTAssertNil(both.observeV(isKeyDown: true, isInjected: false))

        let shifted = PasteIntentKeyState()
        shifted.observeModifier(.command, isKeyDown: true, isInjected: false)
        shifted.observeModifier(.shift, isKeyDown: true, isInjected: false)
        XCTAssertNil(shifted.observeV(isKeyDown: true, isInjected: false))

        let injected = PasteIntentKeyState()
        injected.observeModifier(.command, isKeyDown: true, isInjected: false)
        XCTAssertNil(injected.observeV(isKeyDown: true, isInjected: true))
    }

    // 61. ReleasedModifierDoesNotRemainLatched.
    func testReleasedModifierDoesNotRemainLatched() {
        let state = PasteIntentKeyState()
        state.observeModifier(.command, isKeyDown: true, isInjected: false)
        state.observeModifier(.command, isKeyDown: false, isInjected: false)
        XCTAssertNil(state.observeV(isKeyDown: true, isInjected: false))
    }

    // 62. ResetClearsHeldAndRepeatState.
    func testResetClearsHeldAndRepeatState() {
        let state = PasteIntentKeyState()
        state.observeModifier(.option, isKeyDown: true, isInjected: false)
        XCTAssertEqual(state.observeV(isKeyDown: true, isInjected: false), .optionV)
        state.reset()
        XCTAssertNil(state.observeV(isKeyDown: true, isInjected: false))
    }

    // SPEC-DELTA-2A поправка: Control+V (no Cmd/Option/Shift) is recognized as `.controlV`.
    func testControlVIsRecognizedAsControlVGesture() {
        let state = PasteIntentKeyState()
        state.observeModifier(.control, isKeyDown: true, isInjected: false)
        XCTAssertEqual(state.observeV(isKeyDown: true, isInjected: false), .controlV)
        XCTAssertNil(state.observeV(isKeyDown: true, isInjected: false))
        XCTAssertNil(state.observeV(isKeyDown: false, isInjected: false))
        XCTAssertEqual(state.observeV(isKeyDown: true, isInjected: false), .controlV)
    }
}

// MARK: - PasteIntentInterceptionState (SPEC-DELTA-2A §1.4/§7)

final class PasteIntentInterceptionStateTests: XCTestCase {
    // testInterceptedPhysicalVSuppressesInitialAndRepeatKeyDownsUntilRelease
    func testInterceptedPhysicalVSuppressesInitialAndRepeatKeyDownsUntilRelease() {
        let state = PasteIntentInterceptionState()
        XCTAssertTrue(state.shouldSuppress(isVKey: true, isKeyDown: true, isInjected: false, interceptThisGesture: true))
        // Auto-repeat: the caller stops passing `interceptThisGesture: true` (the gesture was
        // already reported once), but suppression must keep latching until keyUp.
        XCTAssertTrue(state.shouldSuppress(isVKey: true, isKeyDown: true, isInjected: false, interceptThisGesture: false))
        XCTAssertTrue(state.shouldSuppress(isVKey: true, isKeyDown: true, isInjected: false, interceptThisGesture: false))
        XCTAssertFalse(state.shouldSuppress(isVKey: true, isKeyDown: false, isInjected: false, interceptThisGesture: false))
        // After release, a fresh non-intercepted keyDown is not suppressed.
        XCTAssertFalse(state.shouldSuppress(isVKey: true, isKeyDown: true, isInjected: false, interceptThisGesture: false))
    }

    // testInterceptionNeverSuppressesInjectedOrUnrelatedKeys
    func testInterceptionNeverSuppressesInjectedOrUnrelatedKeys() {
        let state = PasteIntentInterceptionState()
        XCTAssertFalse(state.shouldSuppress(isVKey: true, isKeyDown: true, isInjected: true, interceptThisGesture: true))
        XCTAssertFalse(state.shouldSuppress(isVKey: false, isKeyDown: true, isInjected: false, interceptThisGesture: true))
    }

    // testInterceptedPhysicalControlVSuppressesGestureAndOwnInjectedReleaseIsNotSuppressed
    func testInterceptedPhysicalControlVSuppressesGestureAndOwnInjectedReleaseIsNotSuppressed() {
        let state = PasteIntentInterceptionState()
        XCTAssertTrue(state.shouldSuppress(isVKey: true, isKeyDown: true, isInjected: false, interceptThisGesture: true))
        // Snapik's own synthetic Control+V (posted while completing the intercepted gesture)
        // must never be suppressed, even while the latch from the physical keyDown is still set.
        XCTAssertFalse(state.shouldSuppress(isVKey: true, isKeyDown: true, isInjected: true, interceptThisGesture: false))
        XCTAssertFalse(state.shouldSuppress(isVKey: true, isKeyDown: false, isInjected: true, interceptThisGesture: false))
        // The physical release still clears the latch.
        XCTAssertFalse(state.shouldSuppress(isVKey: true, isKeyDown: false, isInjected: false, interceptThisGesture: false))
    }
}
