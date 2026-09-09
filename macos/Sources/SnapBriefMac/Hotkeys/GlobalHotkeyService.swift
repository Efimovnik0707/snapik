// Port of `src/SnapBrief.Windows/WindowsGlobalHotkeyService.cs` using Carbon `RegisterEventHotKey`,
// SPEC §7.1, §7.6.
import Carbon.HIToolbox
import Foundation
import SnapBriefCore

/// Global hotkey registration via the Carbon Event Manager (works without any TCC permission,
/// unlike a `CGEvent` tap — SPEC §7.6, "вариант по умолчанию"). Registration ids are handed out
/// sequentially starting at `0x4000`, mirroring the Windows service (`:14`, `:32`).
final class GlobalHotkeyService {
    enum HotkeyError: Error, CustomStringConvertible {
        case emptyName
        case alreadyRegistered(String)
        case registrationFailed(String, OSStatus)
        case unsupportedKey(String)

        var description: String {
            switch self {
            case .emptyName: return "A hotkey id is required."
            case .alreadyRegistered(let name): return "Hotkey \(name) is already registered."
            case .registrationFailed(let name, let status): return "Could not register global hotkey \(name) (\(status))."
            case .unsupportedKey(let name): return "Hotkey \(name) has no macOS key equivalent."
            }
        }

        /// Carbon's conflict status (`eventHotKeyExistsErr`, -9878) is the direct analogue of
        /// Windows' `ERROR_HOTKEY_ALREADY_REGISTERED` (1409) — SPEC §7.6.
        var isConflict: Bool {
            if case .registrationFailed(_, let status) = self { return status == -9878 }
            return false
        }
    }

    private struct Registration {
        let carbonId: UInt32
        let ref: EventHotKeyRef
    }

    // 'SBKY' — arbitrary 4-byte signature distinguishing our hotkeys from any other app's.
    private static let signature: OSType = 0x53424B59

    private var handlerRef: EventHandlerRef?
    private var nextCarbonId: UInt32 = 0x4000
    private var registrations: [String: Registration] = [:]

    /// Called on the main thread with the registered name (`"capture"`, `"fullscreen-save"`, ...)
    /// when its hotkey fires.
    var onHotkeyPressed: ((String) -> Void)?

    init() {
        installHandler()
    }

    deinit {
        unregisterAll()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
    }

    // CHECK-API: EventHandlerUPP bridging verified against the documented Carbon.HIToolbox
    // signature (`typealias EventHandlerUPP = @convention(c) (EventHandlerCallRef?, EventRef?,
    // UnsafeMutableRawPointer?) -> OSStatus`); no compiler available locally to confirm.
    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let callback: EventHandlerUPP = { _, eventRef, userData in
            guard let userData, let eventRef else { return noErr }
            let service = Unmanaged<GlobalHotkeyService>.fromOpaque(userData).takeUnretainedValue()
            var hotKeyId = EventHotKeyID()
            let status = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyId)
            if status == noErr && hotKeyId.signature == GlobalHotkeyService.signature {
                service.handlePressed(carbonId: hotKeyId.id)
            }
            return noErr
        }

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, selfPointer, &handlerRef)
    }

    private func handlePressed(carbonId: UInt32) {
        guard let name = registrations.first(where: { $0.value.carbonId == carbonId })?.key else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onHotkeyPressed?(name)
        }
    }

    /// Port of `Register(string id, HotkeyGesture gesture)` (`:27-37`). `identifier.modifiers`'
    /// `.noRepeat` bit has no Carbon equivalent (global hotkeys do not auto-repeat) and is ignored
    /// here; it is preserved only for on-disk format compatibility (SPEC §7.6).
    func register(name: String, identifier: HotkeyIdentifier) throws {
        guard !name.isEmpty else { throw HotkeyError.emptyName }
        guard registrations[name] == nil else { throw HotkeyError.alreadyRegistered(name) }
        guard let macKeyCode = KeyCodeMapping.macKeyCode(forWindowsVK: identifier.windowsVirtualKey) else {
            throw HotkeyError.unsupportedKey(name)
        }

        let carbonModifiers = Self.carbonModifiers(for: identifier.modifiers)

        let carbonId = nextCarbonId
        nextCarbonId += 1
        let hotKeyId = EventHotKeyID(signature: Self.signature, id: carbonId)

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(macKeyCode), carbonModifiers, hotKeyId, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            throw HotkeyError.registrationFailed(name, status)
        }

        registrations[name] = Registration(carbonId: carbonId, ref: ref)
    }

    /// Port of `Unregister` (`:39-44`): idempotent, unknown names are silently ignored.
    func unregister(_ name: String) {
        guard let entry = registrations.removeValue(forKey: name) else { return }
        UnregisterEventHotKey(entry.ref)
    }

    func unregisterAll() {
        for name in Array(registrations.keys) { unregister(name) }
    }

    /// Pure bit translation, exposed for unit testing: Alt=1->Option, Control=2->Command,
    /// Shift=4->Shift, Windows=8->(Mac) Control (SPEC §7.6).
    static func carbonModifiers(for modifiers: HotkeyModifiers) -> UInt32 {
        var carbonModifiers: UInt32 = 0
        if modifiers.contains(.alt) { carbonModifiers |= UInt32(optionKey) }
        if modifiers.contains(.control) { carbonModifiers |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        if modifiers.contains(.windows) { carbonModifiers |= UInt32(controlKey) }
        return carbonModifiers
    }
}
