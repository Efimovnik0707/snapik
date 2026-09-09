// Port of the virtual-key numbering used by SnapBrief.Windows hotkey ids, SPEC §7.6.
//
// `HotkeySettings` (Core) persists hotkeys as `"custom:{modifiers}:{virtualKey}"`, where
// `virtualKey` is a Win32 VK_* code (see `HotkeySettingsWindow.xaml.cs:57-76` on Windows). To keep
// a `settings.json` file readable by either build, the Mac port keeps storing the Windows VK
// number and translates it to a Carbon virtual key code (`kVK_*`, from
// `Carbon.HIToolbox/Events.h`) only at the point of registration/recording. This file is that
// translation table, in both directions.
import Foundation

enum KeyCodeMapping {
    /// (Windows VK_*, macOS kVK_*, human-readable key name for hotkey labels)
    ///
    /// Letters/digits/F1-F12/common navigation and editing keys are standard, well-known
    /// constants on both platforms. F13-F20, Print Screen and Pause/Break have no true macOS
    /// hardware equivalent; the mappings below are best-effort placeholders that keep the id
    /// numerically round-trippable, not a hardware-accuracy claim.
    // CHECK-API: kVK_* constants transcribed from Carbon.HIToolbox's public Events.h; verify
    // against the actual SDK header if hotkey registration silently no-ops on a real Mac.
    private static let table: [(win: Int, mac: Int, name: String)] = [
        // Letters (VK_A...VK_Z = 0x41...0x5A)
        (0x41, 0x00, "A"), (0x42, 0x0B, "B"), (0x43, 0x08, "C"), (0x44, 0x02, "D"),
        (0x45, 0x0E, "E"), (0x46, 0x03, "F"), (0x47, 0x05, "G"), (0x48, 0x04, "H"),
        (0x49, 0x22, "I"), (0x4A, 0x26, "J"), (0x4B, 0x28, "K"), (0x4C, 0x25, "L"),
        (0x4D, 0x2E, "M"), (0x4E, 0x2D, "N"), (0x4F, 0x1F, "O"), (0x50, 0x23, "P"),
        (0x51, 0x0C, "Q"), (0x52, 0x0F, "R"), (0x53, 0x01, "S"), (0x54, 0x11, "T"),
        (0x55, 0x20, "U"), (0x56, 0x09, "V"), (0x57, 0x0D, "W"), (0x58, 0x07, "X"),
        (0x59, 0x10, "Y"), (0x5A, 0x06, "Z"),
        // Digits (VK_0...VK_9 = 0x30...0x39)
        (0x30, 0x1D, "0"), (0x31, 0x12, "1"), (0x32, 0x13, "2"), (0x33, 0x14, "3"),
        (0x34, 0x15, "4"), (0x35, 0x17, "5"), (0x36, 0x16, "6"), (0x37, 0x1A, "7"),
        (0x38, 0x1C, "8"), (0x39, 0x19, "9"),
        // Function keys F1-F12 (VK_F1...VK_F12 = 0x70...0x7B)
        (0x70, 0x7A, "F1"), (0x71, 0x78, "F2"), (0x72, 0x63, "F3"), (0x73, 0x76, "F4"),
        (0x74, 0x60, "F5"), (0x75, 0x61, "F6"), (0x76, 0x62, "F7"), (0x77, 0x64, "F8"),
        (0x78, 0x65, "F9"), (0x79, 0x6D, "F10"), (0x7A, 0x67, "F11"), (0x7B, 0x6F, "F12"),
        // F13-F20 (VK_F13...VK_F20 = 0x7C...0x83): positional best-effort mapping.
        // CHECK-API: not verified against a real extended keyboard.
        (0x7C, 0x69, "F13"), (0x7D, 0x6B, "F14"), (0x7E, 0x71, "F15"), (0x7F, 0x6A, "F16"),
        (0x80, 0x40, "F17"), (0x81, 0x4F, "F18"), (0x82, 0x50, "F19"), (0x83, 0x5A, "F20"),
        // Navigation and editing
        (0x08, 0x33, "Backspace"),
        (0x09, 0x30, "Tab"),
        (0x0D, 0x24, "Return"),
        (0x1B, 0x35, "Escape"),
        (0x20, 0x31, "Space"),
        (0x21, 0x74, "Page Up"),
        (0x22, 0x79, "Page Down"),
        (0x23, 0x77, "End"),
        (0x24, 0x73, "Home"),
        (0x25, 0x7B, "Left Arrow"),
        (0x26, 0x7E, "Up Arrow"),
        (0x27, 0x7C, "Right Arrow"),
        (0x28, 0x7D, "Down Arrow"),
        (0x2E, 0x75, "Delete"),
        // No macOS hardware equivalent; CHECK-API best-effort placeholders only, chosen so the
        // stored id stays parseable (SPEC §7.2 fallback still applies for anything unparseable).
        (0x2C, 0x69, "Print Screen"),
        (0x13, 0x71, "Pause / Break"),
    ]

    private static let winToMac: [Int: (mac: Int, name: String)] = {
        var map: [Int: (Int, String)] = [:]
        for entry in table { map[entry.win] = (entry.mac, entry.name) }
        return map
    }()

    /// First-inserted-wins for collisions (e.g. F13 and Print Screen share `kVK_F13`): a key
    /// recorded on that physical key round-trips to the function-key id, not the placeholder.
    private static let macToWin: [Int: Int] = {
        var map: [Int: Int] = [:]
        for entry in table where map[entry.mac] == nil { map[entry.mac] = entry.win }
        return map
    }()

    static func macKeyCode(forWindowsVK vk: Int) -> Int? { winToMac[vk]?.mac }

    static func name(forWindowsVK vk: Int) -> String? { winToMac[vk]?.name }

    static func windowsVK(forMacKeyCode keyCode: Int) -> Int? { macToWin[keyCode] }
}
