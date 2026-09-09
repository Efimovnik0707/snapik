// Port of `HotkeySettings.Find`'s custom-id parsing/fallback behavior (SPEC §7.2) plus its Mac
// extension (recording a Carbon key code into a Windows-VK-numbered id, SPEC §7.3/§7.6).
import Foundation
import Carbon.HIToolbox
import XCTest

@testable import SnapBriefCore
@testable import SnapBriefMac

final class HotkeyIdentifierTests: XCTestCase {
    func test_round_trip_ctrl_shift_K() {
        // Recorded on macOS as Command+Shift+K: Command -> stored bit "Control" (2),
        // Shift -> stored bit "Shift" (4); kVK_ANSI_K = 0x28 -> Windows VK 0x4B ('K').
        let modifiers: HotkeyModifiers = [.control, .shift, .noRepeat]
        guard let id = HotkeyIdentifier.makeCustomId(macKeyCode: 0x28, modifiers: modifiers) else {
            XCTFail("Expected a custom id for kVK_ANSI_K")
            return
        }
        XCTAssertEqual(id, "custom:6:75")

        let parsed = HotkeyIdentifier.parse(id)
        XCTAssertEqual(parsed.windowsVirtualKey, 0x4B)
        XCTAssertTrue(parsed.modifiers.contains(.control))
        XCTAssertTrue(parsed.modifiers.contains(.shift))
        XCTAssertEqual(KeyCodeMapping.macKeyCode(forWindowsVK: parsed.windowsVirtualKey), 0x28)
    }

    func test_invalid_id_falls_back_to_ctrl_alt_s() {
        let parsed = HotkeyIdentifier.parse("custom:999:13")
        XCTAssertEqual(parsed.id, "ctrl-alt-s")
        XCTAssertEqual(parsed.windowsVirtualKey, 0x53)
    }

    func test_garbage_id_falls_back_to_ctrl_alt_s() {
        XCTAssertEqual(HotkeyIdentifier.parse("not-a-hotkey-id").id, "ctrl-alt-s")
        XCTAssertEqual(HotkeyIdentifier.parse("custom:1").id, "ctrl-alt-s")
    }

    func test_ctrl_alt_modifiers_map_to_command_option() {
        let carbonModifiers = GlobalHotkeyService.carbonModifiers(for: [.control, .alt])
        XCTAssertEqual(carbonModifiers, UInt32(cmdKey) | UInt32(optionKey))
    }
}
