// Port of Windows/WindowsInputInjector.cs, SPEC §5.6.
//
// Enter is structurally impossible to send: `InputInjecting.injectPaste(alternate:)` only knows
// Cmd+V (`alternate == false`) and Option+V (`alternate == true`), so the native-boundary rejection
// Windows needs (`SnapBrief never injects Enter.`) has no macOS equivalent to port — there is no
// code path that could construct an Enter gesture.
//
// Virtual key codes are the CONTRACTS.md-documented HIToolbox constants
// (`kVK_ANSI_V = 0x09`, `kVK_Command = 0x37`, `kVK_Shift = 0x38`, `kVK_Option = 0x3A`,
// `kVK_Control = 0x3B`), inlined here rather than imported from `Carbon.HIToolbox` to keep this
// file's dependency surface to `CoreGraphics` only.

import CoreGraphics
import SnapBriefCore

/// Port of `IPhysicalKeyState`, injectable for tests that cannot rely on real physical key state.
public protocol MacPhysicalKeyStateReading {
    func isKeyDown(_ keyCode: CGKeyCode) -> Bool
}

/// Port of `WindowsPhysicalKeyState`: `CGEventSource.keyState(.combinedSessionState, key:)` per
/// SPEC §5.6.
public struct SystemPhysicalKeyState: MacPhysicalKeyStateReading {
    public init() {}
    public func isKeyDown(_ keyCode: CGKeyCode) -> Bool {
        CGEventSource.keyState(.combinedSessionState, key: keyCode)
    }
}

public final class MacInputInjector: GuardedInputInjecting {
    /// `0x534E4150` = ASCII "SNAP" (CONTRACTS.md): tags every synthetic event so
    /// `MacPasteIntentObserver` can ignore SnapBrief's own injected keys instead of reacting to them.
    public static let syntheticEventTag: Int64 = 0x534E4150

    private let physicalKeys: MacPhysicalKeyStateReading
    private let releaseTimeout: TimeInterval
    private let releasePollInterval: TimeInterval
    private let scheduler: TransportScheduler

    public init(
        physicalKeys: MacPhysicalKeyStateReading = SystemPhysicalKeyState(),
        releaseTimeout: TimeInterval = 0.75,
        releasePollInterval: TimeInterval = 0.01,
        scheduler: TransportScheduler = DispatchQueueScheduler()
    ) {
        self.physicalKeys = physicalKeys
        self.releaseTimeout = releaseTimeout
        self.releasePollInterval = releasePollInterval
        self.scheduler = scheduler
    }

    public func injectPaste(alternate: Bool, completion: @escaping (Bool) -> Void) {
        sendCore(alternate: alternate, finalGuard: nil, completion: completion)
    }

    public func injectPasteGuarded(
        alternate: Bool,
        finalGuard: @escaping (@escaping (Bool) -> Void) -> Void,
        completion: @escaping (Bool) -> Void
    ) {
        sendCore(alternate: alternate, finalGuard: finalGuard, completion: completion)
    }

    /// Port of `SendCoreAsync` (`Windows/WindowsInputInjector.cs:38-59`).
    private func sendCore(
        alternate: Bool,
        finalGuard: ((@escaping (Bool) -> Void) -> Void)?,
        completion: @escaping (Bool) -> Void
    ) {
        let deadline = Date().addingTimeInterval(releaseTimeout)
        waitForPhysicalRelease(deadline: deadline) { released in
            guard released else {
                // Port of `PhysicalKeysStillHeldException`: refuse to synthesize input while the
                // trigger keys are still physically held.
                completion(false)
                return
            }
            let proceed: (Bool) -> Void = { allowed in
                guard allowed else { completion(false); return }
                completion(Self.postPasteEvents(alternate: alternate))
            }
            if let finalGuard {
                finalGuard(proceed)
            } else {
                proceed(true)
            }
        }
    }

    /// Port of `WaitForPhysicalReleaseAsync` (`:61-70`): polls every `releasePollInterval` until
    /// Control, Shift, Option, Command, and V are all physically released, or `deadline` passes.
    private func waitForPhysicalRelease(deadline: Date, completion: @escaping (Bool) -> Void) {
        let watched: [CGKeyCode] = [
            VirtualKey.control, VirtualKey.shift, VirtualKey.option, VirtualKey.command, VirtualKey.v,
        ]
        if !watched.contains(where: physicalKeys.isKeyDown) {
            completion(true)
            return
        }
        if Date() >= deadline {
            completion(false)
            return
        }
        scheduler.schedule(after: releasePollInterval) { [weak self] in
            self?.waitForPhysicalRelease(deadline: deadline, completion: completion)
        }
    }

    /// Port of the key event sequence in `SendCoreAsync` (`:48-53`): modifier down, V down, V up,
    /// modifier up.
    private static func postPasteEvents(alternate: Bool) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return false }
        let modifierKey = alternate ? VirtualKey.option : VirtualKey.command
        let modifierFlag: CGEventFlags = alternate ? .maskAlternate : .maskCommand

        guard
            let modifierDown = CGEvent(keyboardEventSource: source, virtualKey: modifierKey, keyDown: true),
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: VirtualKey.v, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: VirtualKey.v, keyDown: false),
            let modifierUp = CGEvent(keyboardEventSource: source, virtualKey: modifierKey, keyDown: false)
        else {
            return false
        }

        keyDown.flags = modifierFlag
        keyUp.flags = modifierFlag

        for event in [modifierDown, keyDown, keyUp, modifierUp] {
            event.setIntegerValueField(.eventSourceUserData, value: syntheticEventTag)
            event.post(tap: .cghidEventTap)
        }
        return true
    }

    private enum VirtualKey {
        static let v: CGKeyCode = 0x09
        static let command: CGKeyCode = 0x37
        static let shift: CGKeyCode = 0x38
        static let option: CGKeyCode = 0x3A
        static let control: CGKeyCode = 0x3B
    }
}
