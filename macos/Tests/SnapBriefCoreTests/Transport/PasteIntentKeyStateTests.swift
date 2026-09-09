// XCTest port of tests/SnapBrief.Windows.Tests/PasteIntentObserverTests.cs, SPEC §8.3 items 58-62.
// Item 57 (`NativeImports_ResolveActualWindowsExports`) is Mac-replaced per the task brief; see
// `Tests/SnapBriefMacTests/Transport` for the `CGEvent.tapCreate`/permission-gated equivalent.
//
// Windows tracks individual left/right Control/Alt/Shift/Windows key codes via a `HashSet`; the
// macOS port (`PasteIntentKeyState`) tracks the same held-set idea through the abstract
// `PasteIntentModifierKey` (Command/Option/Shift/Control) instead of raw keycodes, since
// `CGEventFlags` does not distinguish left/right variants. Each test below is the direct
// behavioral analogue of its Windows counterpart, substituting Command for Control and Option for
// Alt.

import XCTest
@testable import SnapBriefCore

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
}
