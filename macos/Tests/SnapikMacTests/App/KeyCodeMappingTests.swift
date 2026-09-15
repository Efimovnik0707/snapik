// Port of the Windows VK <-> macOS kVK mapping requirements, SPEC §7.6.
import Foundation
import XCTest
import SnapikCore

@testable import SnapikMac

final class KeyCodeMappingTests: XCTestCase {
    func test_windows_S_maps_to_kVK_ANSI_S() {
        XCTAssertEqual(KeyCodeMapping.macKeyCode(forWindowsVK: 0x53), 0x01)
    }

    func test_mapping_round_trips_for_letters() {
        for winVK in 0x41...0x5A {
            guard let macCode = KeyCodeMapping.macKeyCode(forWindowsVK: winVK) else {
                XCTFail("No mac key code for Windows VK 0x\(String(winVK, radix: 16))")
                continue
            }
            XCTAssertEqual(KeyCodeMapping.windowsVK(forMacKeyCode: macCode), winVK)
        }
    }

    func test_unknown_windows_vk_returns_nil() {
        XCTAssertNil(KeyCodeMapping.macKeyCode(forWindowsVK: 0xFFFF))
    }
}
