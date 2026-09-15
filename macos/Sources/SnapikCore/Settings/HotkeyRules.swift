// Port of `src/Snapik.App/HotkeyRules.cs`, SPEC-DELTA-3 §1.1 C-10, §2.4.
import Foundation

/// What a stored shortcut id is allowed to say. An id is either the name of a preset or
/// `"custom:{modifiers}:{virtualKey}"`, and the rules live apart from the settings window so that
/// they can be read, and tested, without a window behind them.
///
/// The numbers are the Windows ones on purpose: the id string is shared with the Windows build, and
/// `virtualKey` is always a Win32 VK code (`KeyCodeMapping` translates it at the moment of
/// registration). The modifier bits are Alt = 1, Control = 2, Shift = 4, Windows = 8; on this
/// platform bit 1 is **Option**, bit 2 is **Command** and bit 8 is **Control**
/// (`GlobalHotkeyService.swift:133-140`), so `custom:7:83` is Cmd + Option + Shift + S.
public enum HotkeyRules {
    /// The two keys that are a shortcut on their own: Print Screen and Pause. Everything else needs
    /// a modifier, because a shortcut is registered globally: a key pressed alone is taken away from
    /// every other application on the machine, and a bare arrow leaves nothing to move a cursor
    /// with. Neither key exists on a Mac keyboard, and neither is offered here; they stay readable
    /// because a `settings.json` written on Windows carries them.
    public static func isShortcutOnItsOwn(_ virtualKey: Int) -> Bool {
        virtualKey == 0x2C || virtualKey == 0x13
    }

    /// Ctrl, Alt, Shift and the command keys, in every form the id format names them: they are what
    /// a shortcut is held together with, never what it ends with. Releasing one of them while
    /// another is still down used to write it in as the key of the shortcut, and "Cmd + LeftShift"
    /// then answered every Cmd+Shift on the machine.
    public static func isModifierKey(_ virtualKey: Int) -> Bool {
        virtualKey == 0x10 || virtualKey == 0x11 || virtualKey == 0x12 || virtualKey == 0x5B
            || virtualKey == 0x5C || (virtualKey >= 0xA0 && virtualKey <= 0xA5)
    }

    /// Reads a custom id from the settings file. `nil` means the file holds something that must not
    /// be registered: a malformed id, a key outside the range, a modifier bit nothing maps to, a
    /// modifier standing where the key of the shortcut belongs, or a key pressed alone that is not
    /// one of the two above. The caller answers with the default shortcut, and that is how a bare
    /// arrow recorded by an older build is undone, without the read having to write anything back.
    public static func parseCustom(_ id: String) -> (modifiers: UInt32, virtualKey: Int)? {
        let parts = id.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "custom" else { return nil }
        guard let storedModifiers = UInt32(parts[1]), (storedModifiers & ~UInt32(15)) == 0 else { return nil }
        guard let storedKey = UInt32(parts[2]), storedKey > 0, storedKey < 255 else { return nil }
        let key = Int(storedKey)
        if isModifierKey(key) { return nil }
        if storedModifiers == 0 && !isShortcutOnItsOwn(key) { return nil }
        return (storedModifiers, key)
    }

    /// The combinations macOS answers before any application does, so recording one would give a
    /// shortcut that never fires. The Windows file keeps a list of its own (anything with Win,
    /// Ctrl+Alt+Delete, Alt+Tab, Alt+F4, Ctrl+Escape) and names the macOS one beside it
    /// (`HotkeyRules.cs:64-66`); this is that list together with the additions of SPEC-DELTA-3 §2.4.
    ///
    /// Bare F11 and F12 belong to Mission Control and are refused here as well as by the rule about
    /// a key on its own, so the reason a recording is turned down does not depend on the order the
    /// two checks run in.
    public static func isSystemReserved(modifiers: HotkeyModifiers, virtualKey: Int) -> Bool {
        let command = modifiers.contains(.control)
        let option = modifiers.contains(.alt)
        let shift = modifiers.contains(.shift)
        let control = modifiers.contains(.windows)
        let onlyCommand = command && !option && !shift && !control

        // The screenshot keys of the system: Cmd+Shift+3, Cmd+Shift+4, Cmd+Shift+5.
        if command && shift && !option && !control && (0x33...0x35).contains(virtualKey) { return true }
        // Cmd+Tab, Cmd+Q and Cmd+Space, each of them the system's before it is anybody's.
        if onlyCommand && (virtualKey == 0x09 || virtualKey == 0x51 || virtualKey == 0x20) { return true }
        // Cmd+Option+Esc (force quit) and Ctrl+Cmd+Q (lock screen).
        if command && option && !control && virtualKey == 0x1B { return true }
        if command && control && !option && virtualKey == 0x51 { return true }
        // Mission Control and the desktop.
        return modifiers.intersection([.alt, .control, .shift, .windows]).isEmpty
            && (virtualKey == 0x7A || virtualKey == 0x7B)
    }

    /// Whether two stored ids stand for the same combination. Compared as the combination they parse
    /// to, not as text: `"print-screen"` and `"custom:0:44"` are one shortcut written two ways, and
    /// a window comparing the strings would let both be assigned at once.
    public static func sameGesture(_ idA: String?, _ idB: String?) -> Bool {
        guard let first = parse(idA), let second = parse(idB) else { return false }
        return first.modifiers == second.modifiers && first.virtualKey == second.virtualKey
    }

    /// The first combination of the queue that nothing holds and the system does not answer first,
    /// or `nil` when every one of them is taken. What the "suggest" chip beside an unassigned
    /// shortcut offers, so that the user is never asked to invent one.
    public static func suggestFree(taken: [String]) -> String? {
        candidates.first { candidate in
            guard let parsed = parse(candidate) else { return false }
            return !isSystemReserved(
                modifiers: HotkeyModifiers(rawValue: parsed.modifiers), virtualKey: parsed.virtualKey)
                && !taken.contains { sameGesture($0, candidate) }
        }
    }

    /// The order the chip offers a free combination in. The Windows queue starts with Print Screen;
    /// a Mac keyboard has no such key, so the queue starts at Cmd + Option + Shift + S, which is
    /// also what `FullscreenSaveId` carries by default.
    public static let candidates: [String] = ["custom:7:83", "ctrl-shift-s", "alt-s"]

    // The presets, spelled out here rather than read from `HotkeySettings`: the two lists are the
    // same seven ids, and a preset added there has to be added here.
    private static let presets: [String: (modifiers: UInt32, virtualKey: Int)] = [
        "ctrl-alt-s": (3, 0x53),
        "ctrl-shift-s": (6, 0x53),
        "alt-s": (1, 0x53),
        "print-screen": (0, 0x2C),
        "ctrl-alt-v": (3, 0x56),
        "ctrl-shift-v": (6, 0x56),
        "alt-v": (1, 0x56),
    ]

    private static func parse(_ id: String?) -> (modifiers: UInt32, virtualKey: Int)? {
        guard let id else { return nil }
        if let preset = presets[id] { return preset }
        return parseCustom(id)
    }
}
