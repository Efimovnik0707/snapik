// Port of Windows/WindowsPasteIntentObserver.cs, SPEC §5.8, §9.2.
//
// Windows installs a low-level keyboard hook (`WH_KEYBOARD_LL`), no permission required. The
// macOS equivalent is a listen-only `CGEvent` tap (`.cgSessionEventTap`, `.listenOnly`,
// `keyDown | keyUp | flagsChanged`), which requires Input Monitoring
// (`kTCCServiceListenEvent`, SPEC §9.2); without it `start()` throws `TransportError.permissionMissing`,
// matching the degraded-but-running behavior SPEC §9.2/§1.11 describes (no autorotation, the main
// scenario stays intact).
//
// The `CGEventTapCallBack` must be a non-capturing closure convertible to a C function pointer, so
// `self` travels through the `userInfo` opaque pointer via `Unmanaged`, exactly as CONTRACTS.md
// specifies ("реализуй через CGEvent.tapCreate с C-callback и Unmanaged для передачи self").

import CoreGraphics
import Foundation
import SnapBriefCore

public final class MacPasteIntentObserver: PasteIntentObserving {
    public var onPasteIntent: ((PasteIntent) -> Void)?

    private let foreground: ForegroundTargetServicing
    private let clipboardSequence: () -> Int
    private let keyState = PasteIntentKeyState()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// `clipboardSequence` returns the current `NSPasteboard.changeCount`
    /// (SPEC §5.8: "снимать `NSPasteboard.general.changeCount` в момент события").
    public init(foreground: ForegroundTargetServicing, clipboardSequence: @escaping () -> Int) {
        self.foreground = foreground
        self.clipboardSequence = clipboardSequence
    }

    public var isRunning: Bool { eventTap != nil }

    /// Port of `Start` (`Windows/WindowsPasteIntentObserver.cs:31-40`).
    public func start() throws {
        if eventTap != nil { return }
        guard TransportPermissions.hasInputMonitoringAccess else {
            throw TransportError.permissionMissing("Отслеживание вставки недоступно: нет разрешения Input Monitoring.")
        }

        let mask: CGEventMask =
            (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: mask,
                callback: { _, type, event, userInfo in
                    if let userInfo {
                        Unmanaged<MacPasteIntentObserver>.fromOpaque(userInfo).takeUnretainedValue()
                            .handle(type: type, event: event)
                    }
                    return Unmanaged.passUnretained(event)
                },
                userInfo: refcon)
        else {
            throw TransportError.permissionMissing("Отслеживание вставки недоступно: не удалось создать перехватчик событий.")
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            throw TransportError.other("Could not create the paste-intent run loop source.")
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
    }

    /// Port of `Stop` (`:42-51`).
    public func stop() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        keyState.reset()
    }

    /// Port of `OnKeyboardHook` (`:53-83`): must be short and never throw, per SPEC §5.8
    /// ("обработчик обязан быть невыбрасывающим и максимально коротким").
    fileprivate func handle(type: CGEventType, event: CGEvent) {
        // Ignore SnapBrief's own synthetic paste keys (SPEC §5.8: mandatory analogue of
        // `LLKHF_INJECTED`), tagged by `MacInputInjector`.
        if event.getIntegerValueField(.eventSourceUserData) == MacInputInjector.syntheticEventTag { return }
        // Ignore events belonging to our own process.
        if pid_t(event.getIntegerValueField(.eventTargetUnixProcessID)) == ProcessInfo.processInfo.processIdentifier {
            return
        }

        switch type {
        case .flagsChanged:
            let keyCode = CGKeyCode(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
            guard let role = Self.modifierRole(for: keyCode) else { return }
            keyState.observeModifier(role, isKeyDown: Self.isModifierDown(role: role, flags: event.flags), isInjected: false)
        case .keyDown, .keyUp:
            let keyCode = CGKeyCode(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
            guard keyCode == MacPasteIntentObserver.VirtualKeyV else { return }
            guard let gesture = keyState.observeV(isKeyDown: type == .keyDown, isInjected: false) else { return }
            guard type == .keyDown else { return }
            emitIntent(alternate: gesture == .optionV)
        default:
            break
        }
    }

    private func emitIntent(alternate: Bool) {
        let target = foreground.currentTarget()
        let sequence = clipboardSequence()
        let intent = PasteIntent(
            alternate: alternate, timestamp: Date(), synthetic: false, target: target, clipboardSequence: sequence)
        DispatchQueue.main.async { [weak self] in self?.onPasteIntent?(intent) }
    }

    private static let VirtualKeyV: CGKeyCode = 0x09

    private static func modifierRole(for keyCode: CGKeyCode) -> PasteIntentModifierKey? {
        switch keyCode {
        case 0x37: return .command // kVK_Command
        case 0x3A: return .option // kVK_Option
        case 0x38: return .shift // kVK_Shift
        case 0x3B: return .control // kVK_Control
        default: return nil
        }
    }

    private static func isModifierDown(role: PasteIntentModifierKey, flags: CGEventFlags) -> Bool {
        switch role {
        case .command: return flags.contains(.maskCommand)
        case .option: return flags.contains(.maskAlternate)
        case .shift: return flags.contains(.maskShift)
        case .control: return flags.contains(.maskControl)
        }
    }

    deinit {
        stop()
    }
}
