// SPEC §9.2, §9.3. No direct Windows equivalent: `SendInput`/`GetGUIThreadInfo`/the low-level
// keyboard hook need no permissions there. On macOS, listening to global key events needs Input
// Monitoring (`kTCCServiceListenEvent`) and injecting/reading another process' focused element
// needs Accessibility (`kTCCServiceAccessibility`).

import Foundation
import ApplicationServices
import CoreGraphics

public enum TransportPermissions {
    /// SPEC §9.2: `CGPreflightListenEventAccess()`.
    public static var hasInputMonitoringAccess: Bool {
        CGPreflightListenEventAccess()
    }

    /// SPEC §9.2: `CGRequestListenEventAccess()`. Prompts the user if not yet decided.
    @discardableResult
    public static func requestInputMonitoringAccess() -> Bool {
        CGRequestListenEventAccess()
    }

    /// SPEC §9.3: `AXIsProcessTrustedWithOptions`, without the prompt option (read-only check).
    public static var hasAccessibilityAccess: Bool {
        AXIsProcessTrusted()
    }

    /// SPEC §9.3: `AXIsProcessTrustedWithOptions` with the prompt option, so macOS shows its
    /// "Snapik would like to control this computer" dialog.
    @discardableResult
    public static func requestAccessibilityAccess() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
