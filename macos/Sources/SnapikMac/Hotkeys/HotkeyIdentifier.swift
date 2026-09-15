// Port of the hotkey-id parsing/formatting rules in `HotkeySettingsWindow.xaml.cs:57-76`,
// SPEC §7.2, §7.3, §7.6.
import Foundation
import SnapikCore

/// A parsed hotkey id: modifiers + a Windows VK number (the format the id string always carries,
/// see `KeyCodeMapping.swift`), plus the display label (delegated to Core's
/// `HotkeySettings.find(_:)`, which already ports the label-building rule verbatim).
struct HotkeyIdentifier: Equatable {
    let id: String
    let modifiers: HotkeyModifiers
    let windowsVirtualKey: Int
    let label: String

    private static let presets: [String: (mods: HotkeyModifiers, vk: Int)] = [
        "ctrl-alt-s": ([.control, .alt, .noRepeat], 0x53),
        "ctrl-shift-s": ([.control, .shift, .noRepeat], 0x53),
        "alt-s": ([.alt, .noRepeat], 0x53),
        "print-screen": ([.noRepeat], 0x2C),
        "ctrl-alt-v": ([.control, .alt, .noRepeat], 0x56),
        "ctrl-shift-v": ([.control, .shift, .noRepeat], 0x56),
        "alt-v": ([.alt, .noRepeat], 0x56),
    ]

    private init(presetId: String, mods: HotkeyModifiers, vk: Int) {
        self.id = presetId
        self.modifiers = mods
        self.windowsVirtualKey = vk
        self.label = HotkeySettings.find(presetId).label
    }

    private init(customId: String, mods: HotkeyModifiers, vk: Int) {
        self.id = customId
        self.modifiers = mods
        self.windowsVirtualKey = vk
        self.label = HotkeySettings.find(customId).label
    }

    /// The verified fallback for corrupt/unknown ids (SPEC §7.2: "возвращается первый пресет").
    static let fallback: HotkeyIdentifier = {
        let preset = presets["ctrl-alt-s"]!
        return HotkeyIdentifier(presetId: "ctrl-alt-s", mods: preset.mods, vk: preset.vk)
    }()

    /// Port of §7.2 parsing: known preset id, else `"custom:{mods}:{vk}"` with the documented
    /// validity rules, else fall back to `ctrl-alt-s`.
    static func parse(_ id: String) -> HotkeyIdentifier {
        if let preset = presets[id] {
            return HotkeyIdentifier(presetId: id, mods: preset.mods, vk: preset.vk)
        }

        let parts = id.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count == 3, parts[0] == "custom",
            let modsValue = UInt32(parts[1]), let keyValue = UInt32(parts[2]),
            keyValue > 0, keyValue < 255, (modsValue & ~UInt32(15)) == 0
        {
            let mods = HotkeyModifiers(rawValue: modsValue).union(.noRepeat)
            return HotkeyIdentifier(customId: id, mods: mods, vk: Int(keyValue))
        }

        return fallback
    }

    /// Port of `RecordKey` (§7.3): builds a `"custom:{mods}:{vk}"` id from a recorded macOS
    /// (Carbon) key code plus the live modifier state. Returns `nil` if the key has no known
    /// Windows-VK equivalent or falls outside the valid `1..254` range (SPEC §7.3: "виртуальный
    /// код вне диапазона 1..254 игнорируется").
    static func makeCustomId(macKeyCode: Int, modifiers: HotkeyModifiers) -> String? {
        guard let winVK = KeyCodeMapping.windowsVK(forMacKeyCode: macKeyCode), winVK > 0, winVK < 255 else {
            return nil
        }
        let storedModifiers = modifiers.rawValue & 0xF
        return "custom:\(storedModifiers):\(winVK)"
    }
}
