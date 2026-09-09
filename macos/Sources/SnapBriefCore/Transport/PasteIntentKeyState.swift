// Port of Windows/WindowsPasteIntentObserver.cs (PasteIntentKeyState), SPEC §5.8.
//
// Windows tracks individual virtual-key codes (distinct left/right Ctrl/Alt/Shift/Win) via
// WM_KEYDOWN/WM_KEYUP. On macOS the equivalent signal is `CGEventFlags` (`.maskCommand`,
// `.maskAlternate`, `.maskShift`, `.maskControl`), which do not distinguish left/right variants,
// delivered through `flagsChanged` events; `Mac*Observer` (Sources/SnapBriefMac/Transport) maps
// `CGEvent` keyCodes to `PasteIntentModifierKey` before calling into this Foundation-only state
// machine, keeping the same held-modifier-set + "V already down" repeat-gate algorithm as Windows
// (SPEC §5.8: "с теми же правилами: ровно один из Cmd и Option, отсутствие Shift и Control,
// гашение авто-повтора").

import Foundation

/// Abstract modifier identity used by `PasteIntentKeyState`, decoupled from any platform keycode
/// so this type stays Foundation-only.
public enum PasteIntentModifierKey: Hashable {
    case command
    case option
    case shift
    case control
}

/// Port of the `HotkeyGesture.CtrlV`/`AltV` distinction, reduced to the two macOS gestures
/// `InputInjecting` can send.
public enum PasteIntentGesture: Equatable {
    case commandV
    case optionV
}

/// Port of `PasteIntentKeyState` (`Windows/WindowsPasteIntentObserver.cs:141-215`).
public final class PasteIntentKeyState {
    private var heldModifiers: Set<PasteIntentModifierKey> = []
    private var vDown = false

    public init() {}

    /// Port of the modifier-tracking half of `Observe` (`:165-181`): records a Command/Option/
    /// Shift/Control key transition. Injected modifier events are ignored, same as key events.
    public func observeModifier(_ key: PasteIntentModifierKey, isKeyDown: Bool, isInjected: Bool) {
        if isInjected { return }
        if isKeyDown {
            heldModifiers.insert(key)
        } else {
            heldModifiers.remove(key)
        }
    }

    /// Port of the "V" half of `Observe` (`:183-196`).
    public func observeV(isKeyDown: Bool, isInjected: Bool) -> PasteIntentGesture? {
        if isInjected { return nil }
        if !isKeyDown {
            vDown = false
            return nil
        }
        if vDown { return nil }
        vDown = true

        let commandDown = heldModifiers.contains(.command)
        let optionDown = heldModifiers.contains(.option)
        if commandDown == optionDown { return nil }
        if heldModifiers.contains(.shift) || heldModifiers.contains(.control) { return nil }
        return commandDown ? .commandV : .optionV
    }

    /// Port of `Reset` (`:198-204`).
    public func reset() {
        heldModifiers.removeAll()
        vDown = false
    }
}
