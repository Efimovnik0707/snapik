// Port of `tests/Snapik.App.Imaging.Tests/HotkeyRulesTests.cs`, SPEC-DELTA-3 §2.4, §6.
// The blacklist of system combinations is the one of this platform, so the facts about it are ours.
import XCTest

@testable import SnapikCore

final class HotkeyRulesTests: XCTestCase {
    /// A bare left arrow is what an older build recorded when a stray Tab put the focus on the
    /// field; registered globally it never reached the window it was pressed in again. A bare letter
    /// and a bare Escape go the same way.
    func test_A_stored_shortcut_without_a_modifier_is_refused() {
        for stored in ["custom:0:37", "custom:0:83", "custom:0:27"] {
            XCTAssertNil(HotkeyRules.parseCustom(stored), stored)
        }
    }

    /// A modifier where the key of the shortcut belongs: "Cmd + LeftShift" is what an older build
    /// wrote when Shift was let go of with Cmd still down, and it answered every Cmd+Shift there is.
    func test_A_stored_shortcut_that_ends_with_a_modifier_is_refused() {
        for stored in ["custom:2:161", "custom:6:17", "custom:1:18", "custom:2:91"] {
            XCTAssertNil(HotkeyRules.parseCustom(stored), stored)
        }
    }

    /// Print Screen and Pause are shortcuts on their own. Neither key is on a Mac keyboard, but a
    /// `settings.json` written on Windows carries them and must stay readable.
    func test_Print_screen_and_pause_stand_on_their_own() {
        for (stored, virtualKey) in [("custom:0:44", 0x2C), ("custom:0:19", 0x13)] {
            let parsed = HotkeyRules.parseCustom(stored)
            XCTAssertEqual(0, parsed?.modifiers)
            XCTAssertEqual(virtualKey, parsed?.virtualKey)
        }
    }

    func test_A_shortcut_with_a_modifier_is_read_as_it_was_stored() {
        for (stored, modifiers, key) in [("custom:2:37", UInt32(2), 37), ("custom:6:83", UInt32(6), 83)] {
            let parsed = HotkeyRules.parseCustom(stored)
            XCTAssertEqual(modifiers, parsed?.modifiers)
            XCTAssertEqual(key, parsed?.virtualKey)
        }
    }

    /// The name of a preset is not a custom id, a modifier bit nothing maps to is not one either,
    /// and a key outside the range never was.
    func test_Anything_else_is_not_a_custom_shortcut() {
        for stored in ["ctrl-alt-s", "custom:16:83", "custom:2:255", "custom:2:0", "custom:2", "custom:two:83"] {
            XCTAssertNil(HotkeyRules.parseCustom(stored), stored)
        }
    }

    /// What macOS answers before any application does: the three screenshot keys, the switcher,
    /// Spotlight, force quit, the lock screen, and the two function keys of Mission Control.
    func test_A_combination_the_system_answers_first_is_reserved() {
        let reserved: [(HotkeyModifiers, Int)] = [
            ([.control, .shift], 0x33),
            ([.control, .shift], 0x34),
            ([.control, .shift], 0x35),
            ([.control], 0x09),
            ([.control], 0x51),
            ([.control], 0x20),
            ([.control, .alt], 0x1B),
            ([.control, .windows], 0x51),
            ([], 0x7A),
            ([], 0x7B),
        ]
        for (modifiers, key) in reserved {
            XCTAssertTrue(
                HotkeyRules.isSystemReserved(modifiers: modifiers, virtualKey: key),
                "\(modifiers.rawValue):\(key)")
        }
    }

    /// The combinations the application itself ships with are nobody else's, and neither is a
    /// screenshot key with another modifier held.
    func test_A_combination_nothing_holds_is_free() {
        let free: [(HotkeyModifiers, Int)] = [
            ([.control, .alt], 0x53),
            ([.control, .alt, .shift], 0x53),
            ([.alt], 0x53),
            ([.control, .shift], 0x53),
            ([.control, .alt, .shift], 0x34),
            ([.alt], 0x20),
            ([], 0x2C),
            ([], 0x13),
        ]
        for (modifiers, key) in free {
            XCTAssertFalse(
                HotkeyRules.isSystemReserved(modifiers: modifiers, virtualKey: key),
                "\(modifiers.rawValue):\(key)")
        }
    }

    /// The preset and the custom id are one shortcut written two ways; comparing the strings would
    /// let the same combination be assigned to two actions at once.
    func test_Two_ids_for_one_combination_are_the_same_gesture() {
        for (first, second) in [("print-screen", "custom:0:44"), ("ctrl-alt-s", "custom:3:83"), ("alt-v", "custom:1:86")] {
            XCTAssertTrue(HotkeyRules.sameGesture(first, second), "\(first) \(second)")
            XCTAssertTrue(HotkeyRules.sameGesture(second, first), "\(second) \(first)")
        }
    }

    func test_Anything_else_is_a_different_gesture() {
        let pairs = [
            ("print-screen", "custom:0:19"),
            ("ctrl-alt-s", "ctrl-shift-s"),
            ("ctrl-alt-s", "custom:0:37"),
            ("nothing-like-a-shortcut", "ctrl-alt-s"),
        ]
        for (first, second) in pairs {
            XCTAssertFalse(HotkeyRules.sameGesture(first, second), "\(first) \(second)")
        }
    }

    /// The queue of the chip. It starts at Cmd + Option + Shift + S rather than at Print Screen:
    /// that key does not exist here, and a suggestion the user cannot press is not one.
    func test_The_suggestion_is_the_first_combination_nothing_holds() {
        XCTAssertEqual("custom:7:83", HotkeyRules.suggestFree(taken: []))
        XCTAssertEqual("ctrl-shift-s", HotkeyRules.suggestFree(taken: ["custom:7:83"]))
        XCTAssertEqual("alt-s", HotkeyRules.suggestFree(taken: ["custom:7:83", "ctrl-shift-s"]))
    }

    /// Nothing left to offer means no chip beside the field, not a chip offering something taken.
    func test_With_every_candidate_held_there_is_nothing_to_suggest() {
        XCTAssertNil(HotkeyRules.suggestFree(taken: ["custom:7:83", "ctrl-shift-s", "alt-s"]))
    }

    /// The queue of the chip is offered as ids, and every one of them has to be an id the settings
    /// know: a candidate nothing resolves would be a chip that assigns nothing.
    func test_Every_candidate_of_the_queue_resolves_to_a_shortcut() {
        for candidate in HotkeyRules.candidates {
            XCTAssertTrue(HotkeyRules.sameGesture(candidate, candidate), candidate)
        }
    }
}
