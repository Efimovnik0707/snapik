// Port of Windows/WindowsPasteIntentObserver.cs (PasteIntentKeyState), SPEC §5.8.
//
// Windows tracks individual virtual-key codes (distinct left/right Ctrl/Alt/Shift/Win) via
// WM_KEYDOWN/WM_KEYUP. On macOS the equivalent signal is `CGEventFlags` (`.maskCommand`,
// `.maskAlternate`, `.maskShift`, `.maskControl`), which do not distinguish left/right variants,
// delivered through `flagsChanged` events; `Mac*Observer` (Sources/SnapikMac/Transport) maps
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

/// Port of the `HotkeyGesture.CtrlV`/`AltV` distinction, extended per SPEC-DELTA-2A's поправка to
/// the three macOS gestures `InputInjecting` can send: Cmd+V (primary), Ctrl+V ("так Claude Code
/// вставляет картинки на Mac"), and Option+V (parity with Windows' Alt+V).
public enum PasteIntentGesture: Equatable {
    case commandV
    case optionV
    case controlV
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

    /// Port of the "V" half of `Observe` (`:183-196`), extended per SPEC-DELTA-2A's поправка:
    /// Control alone (no Cmd/Option/Shift) is now a recognized gesture (`.controlV`) instead of
    /// being treated as "an extra modifier" that cancels recognition — "PasteIntentKeyState
    /// перестаёт отбрасывать Control как «лишний модификатор» (Control без Cmd/Option = жест
    /// .controlV)".
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
        let controlDown = heldModifiers.contains(.control)
        let shiftDown = heldModifiers.contains(.shift)

        if commandDown != optionDown, !shiftDown, !controlDown {
            return commandDown ? .commandV : .optionV
        }
        if controlDown, !commandDown, !optionDown, !shiftDown {
            return .controlV
        }
        return nil
    }

    /// Port of `Reset` (`:198-204`).
    public func reset() {
        heldModifiers.removeAll()
        vDown = false
    }
}

// MARK: - Interception (SPEC-DELTA-2A §1.4)

/// Port of `PasteIntentInterceptionState` (`Windows/WindowsPasteIntentObserver.cs:167-185`):
/// tracks whether the physical V keystroke currently in progress must keep being suppressed
/// (initial `keyDown` plus every auto-repeat `keyDown`) until its `keyUp`, independent of
/// `PasteIntentKeyState`'s "already reported once" gate. `MacPasteIntentObserver.stop()` resets
/// this alongside `PasteIntentKeyState.reset()`.
public final class PasteIntentInterceptionState {
    private var suppressPhysicalVUntilRelease = false

    public init() {}

    /// Port of `ShouldSuppress` (`:171-182`). `isInjected` or a non-V key never suppress
    /// (`false`); a `keyUp` always clears the latch and is never itself suppressed (`false`); a
    /// `keyDown` that starts an intercepted gesture (`interceptThisGesture == true`) latches
    /// suppression on, and every subsequent `keyDown` (auto-repeat) keeps returning `true` while
    /// the latch is set, regardless of `interceptThisGesture` on that later call.
    public func shouldSuppress(isVKey: Bool, isKeyDown: Bool, isInjected: Bool, interceptThisGesture: Bool) -> Bool {
        guard isVKey, !isInjected else { return false }
        guard isKeyDown else {
            suppressPhysicalVUntilRelease = false
            return false
        }
        if interceptThisGesture {
            suppressPhysicalVUntilRelease = true
        }
        return suppressPhysicalVUntilRelease
    }

    /// Port of `Reset` (called from `Stop()`, `:44-51`).
    public func reset() {
        suppressPhysicalVUntilRelease = false
    }
}
