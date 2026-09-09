// Port of Windows/WindowsPasteIntentObserver.cs, SPEC §5.8, §9.2; SPEC-DELTA-2A §1.
//
// Windows installs a low-level keyboard hook (`WH_KEYBOARD_LL`) that can *swallow* (return 1 for)
// the physical keystroke, no permission required. On macOS the equivalent that can swallow events
// is an active `CGEvent` tap (`.defaultTap`, `.cgSessionEventTap`), which needs Accessibility
// (`kTCCServiceAccessibility`, SPEC-DELTA-2A §1.1); without it this degrades to the previous
// `.listenOnly` tap (needs Input Monitoring, `kTCCServiceListenEvent`), which can observe but never
// suppress a keystroke — SPEC-DELTA-2A §1.1: "без него перехвата нет: интенты приходят с
// intercepted == false, координатор идёт старым путём". `start()` throws
// `TransportError.permissionMissing` only if *neither* permission is available.
//
// The `CGEventTapCallBack` must be a non-capturing closure convertible to a C function pointer, so
// `self` travels through the `userInfo` opaque pointer via `Unmanaged`, exactly as CONTRACTS.md
// specifies ("реализуй через CGEvent.tapCreate с C-callback и Unmanaged для передачи self").

import CoreGraphics
import Foundation
import SnapBriefCore

/// Port of SPEC-DELTA-2A §1.1's tap-mode selection: `.intercepting` (active `.defaultTap`, can
/// suppress) if Accessibility is granted, else `.listenOnly` (can only observe) if Input
/// Monitoring is granted, else `nil` (no tap possible at all).
public enum PasteIntentTapMode: Equatable {
    case intercepting
    case listenOnly
}

public final class MacPasteIntentObserver: PasteIntentObserving {
    public var onPasteIntent: ((PasteIntent) -> Void)?
    /// Fired if the event tap is disabled by the system (timeout or user input) and cannot be
    /// reactivated (finding 16). Not part of `PasteIntentObserving` — only `AppCoordinator`
    /// (which knows the concrete Mac type) wires this up, to surface SPEC's
    /// "Вставка остановлена: {e}" status (finding 7).
    public var onStopped: ((Error) -> Void)?
    /// SPEC-DELTA-2A CONTRACTS.md sync 2: fires tap-mode/re-enable diagnostic lines (§6);
    /// `AppCoordinator` forwards them to `StartupLog`.
    public var onDiagnostic: ((String) -> Void)?

    private let foreground: ForegroundTargetServicing
    private let clipboardSequence: () -> Int
    /// Port of `WindowsPasteIntentObserver(Func<PasteIntentObserved, bool>? shouldIntercept)`
    /// (CONTRACTS.md sync 2). Evaluated synchronously inside the tap callback (SPEC-DELTA-2A
    /// §1.2): only ever invoked when a fresh gesture is recognized on a physical `keyDown`.
    private let shouldIntercept: ((PasteIntent) -> Bool)?
    private let keyState = PasteIntentKeyState()
    private let interceptionState = PasteIntentInterceptionState()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// SPEC-DELTA-2A CONTRACTS.md sync 2: `private(set) var tapMode: PasteIntentTapMode?`.
    public private(set) var tapMode: PasteIntentTapMode?

    /// `clipboardSequence` returns the current `NSPasteboard.changeCount`
    /// (SPEC §5.8: "снимать `NSPasteboard.general.changeCount` в момент события").
    public init(
        foreground: ForegroundTargetServicing, clipboardSequence: @escaping () -> Int,
        shouldIntercept: ((PasteIntent) -> Bool)? = nil
    ) {
        self.foreground = foreground
        self.clipboardSequence = clipboardSequence
        self.shouldIntercept = shouldIntercept
    }

    public var isRunning: Bool { eventTap != nil }

    /// Port of SPEC-DELTA-2A §1.1's pure tap-mode function.
    public static func preferredTapMode(accessibility: Bool, inputMonitoring: Bool) -> PasteIntentTapMode? {
        if accessibility { return .intercepting }
        if inputMonitoring { return .listenOnly }
        return nil
    }

    /// Port of `Start` (`Windows/WindowsPasteIntentObserver.cs:31-40`), extended per
    /// SPEC-DELTA-2A §1.1: try the mode `preferredTapMode` picked; if `.defaultTap` creation
    /// itself fails (e.g. TCC revoked mid-session), fall back to `.listenOnly` once before
    /// actually throwing.
    public func start() throws {
        if eventTap != nil { return }

        let accessibility = TransportPermissions.hasAccessibilityAccess
        let inputMonitoring = TransportPermissions.hasInputMonitoringAccess
        guard let preferredMode = Self.preferredTapMode(accessibility: accessibility, inputMonitoring: inputMonitoring)
        else {
            throw TransportError.permissionMissing("Отслеживание вставки недоступно: нет разрешения Input Monitoring.")
        }

        let mask: CGEventMask =
            (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)

        // CHECK-API: `CGEventTapCallBack` is a `@convention(c)` function-pointer type; this
        // literal captures nothing (only its parameters and `userInfo`), so it should be
        // representable as one. Reused for both the primary and the `.listenOnly` fallback
        // `tapCreate` call below.
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let observer = Unmanaged<MacPasteIntentObserver>.fromOpaque(userInfo).takeUnretainedValue()
            let suppress = observer.handle(type: type, event: event)
            return suppress ? nil : Unmanaged.passUnretained(event)
        }
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        // CHECK-API: `CGEventTapOptions` is `Equatable` in the CoreGraphics overlay, so `==`
        // below should be valid; flagged because the compiler is unavailable locally.
        var options: CGEventTapOptions = preferredMode == .intercepting ? .defaultTap : .listenOnly
        var tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: options, eventsOfInterest: mask,
            callback: callback, userInfo: refcon)
        if tap == nil, options == .defaultTap {
            // SPEC-DELTA-2A §1.1: "если при .defaultTap вернулся nil — повторить с .listenOnly,
            // только потом бросать".
            options = .listenOnly
            tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap, options: options, eventsOfInterest: mask,
                callback: callback, userInfo: refcon)
        }
        guard let createdTap = tap else {
            throw TransportError.permissionMissing("Отслеживание вставки недоступно: не удалось создать перехватчик событий.")
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, createdTap, 0) else {
            throw TransportError.other("Could not create the paste-intent run loop source.")
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: createdTap, enable: true)
        eventTap = createdTap
        runLoopSource = source
        tapMode = options == .defaultTap ? .intercepting : .listenOnly

        onDiagnostic?(
            "PasteIntent tap mode: \(tapMode == .intercepting ? "intercepting" : "listenOnly") "
            + "(accessibility=\(accessibility), inputMonitoring=\(inputMonitoring))")
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
        tapMode = nil
        keyState.reset()
        interceptionState.reset()
    }

    /// Port of `OnKeyboardHook` (`:53-83`) plus SPEC-DELTA-2A §1.2's interception logic: must be
    /// short and never throw, per SPEC §5.8 ("обработчик обязан быть невыбрасывающим и максимально
    /// коротким"). Returns `true` to suppress (swallow) the physical event, only ever possible
    /// when `tapMode == .intercepting` (a `.listenOnly` tap cannot suppress regardless of the
    /// return value — the OS ignores it — but returning the correct value here keeps the two tap
    /// modes' `handle` behavior identical and testable).
    ///
    /// Not `@MainActor`: a C function pointer cannot carry actor isolation, so this stays
    /// `fileprivate`/nonisolated. It only ever actually runs on the main thread, because the tap's
    /// run loop source is attached to `CFRunLoopGetMain()` (SPEC-DELTA-2A §1.2, risk 6) — the
    /// `shouldIntercept` closure `AppCoordinator` supplies does its own `MainActor.assumeIsolated`
    /// bridging for exactly this reason.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        if Self.isOwnEvent(event) { return false }
        if pid_t(event.getIntegerValueField(.eventTargetUnixProcessID)) == ProcessInfo.processInfo.processIdentifier {
            return false
        }

        switch type {
        case .flagsChanged:
            let keyCode = CGKeyCode(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
            if let role = Self.modifierRole(for: keyCode) {
                keyState.observeModifier(role, isKeyDown: Self.isModifierDown(role: role, flags: event.flags), isInjected: false)
            }
            return false

        case .keyDown, .keyUp:
            let keyCode = CGKeyCode(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
            guard keyCode == Self.virtualKeyV else { return false }

            let isKeyDown = type == .keyDown
            let gesture = keyState.observeV(isKeyDown: isKeyDown, isInjected: false)

            var intercept = false
            var intentToPublish: PasteIntent?
            if let gesture, isKeyDown {
                let target = foreground.currentTarget()
                var intent = PasteIntent(
                    gesture: gesture, timestamp: Date(), synthetic: false, target: target,
                    clipboardSequence: clipboardSequence(), intercepted: false)
                intercept =
                    tapMode == .intercepting && onPasteIntent != nil && target != nil && (shouldIntercept?(intent) ?? false)
                if intercept {
                    intent = PasteIntent(
                        gesture: gesture, timestamp: intent.timestamp, synthetic: false, target: target,
                        clipboardSequence: intent.clipboardSequence, intercepted: true)
                }
                intentToPublish = intent
            }

            // Port of `interceptionState.shouldSuppress` (SPEC-DELTA-2A §1.4): autorepeat
            // `keyDown`s (where `gesture == nil`, `intercept == false` locally) keep being
            // suppressed by the latch this sets on the very first `keyDown`, until `keyUp`.
            let suppress = interceptionState.shouldSuppress(
                isVKey: true, isKeyDown: isKeyDown, isInjected: false, interceptThisGesture: intercept)

            if let intentToPublish {
                DispatchQueue.main.async { [weak self] in self?.onPasteIntent?(intentToPublish) }
            }
            return suppress

        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // Port of finding 16: the system disables the tap under load or explicit user
            // action; re-enable it immediately (Apple's documented recovery), and surface an
            // error if that reactivation didn't actually take.
            guard let tap = eventTap else { return false }
            CGEvent.tapEnable(tap: tap, enable: true)
            if !CGEvent.tapIsEnabled(tap: tap) {
                let error = TransportError.other("Не удалось повторно включить перехватчик событий вставки.")
                DispatchQueue.main.async { [weak self] in self?.onStopped?(error) }
            } else {
                let reason = type == .tapDisabledByTimeout ? "timeout" : "user input"
                onDiagnostic?("PasteIntent tap re-enabled after \(reason)")
            }
            return false

        default:
            return false
        }
    }

    /// Port of SPEC-DELTA-2A §1.3's mandatory own-event check: without the first branch, an
    /// active `.defaultTap` would swallow SnapBrief's own synthetic Cmd+V/Option+V/Ctrl+V before
    /// it ever reaches the target app (`MacInputInjector` posts through `.cghidEventTap`, which
    /// still passes through this session-level tap).
    static func isOwnEvent(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == MacInputInjector.syntheticEventTag
            // CHECK-API: `.eventSourceUnixProcessID` is the pid that *generated* the event (as
            // opposed to `.eventTargetUnixProcessID`, the pid it's addressed to, used below for
            // the "own process" check).
            || pid_t(event.getIntegerValueField(.eventSourceUnixProcessID)) == ProcessInfo.processInfo.processIdentifier
    }

    private static let virtualKeyV: CGKeyCode = 0x09

    private static func modifierRole(for keyCode: CGKeyCode) -> PasteIntentModifierKey? {
        switch keyCode {
        case 0x37, 0x36: return .command // kVK_Command, kVK_RightCommand
        case 0x3A, 0x3D: return .option // kVK_Option, kVK_RightOption
        case 0x38, 0x3C: return .shift // kVK_Shift, kVK_RightShift
        case 0x3B, 0x3E: return .control // kVK_Control, kVK_RightControl
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
