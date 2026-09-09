// Port of Windows/WindowsForegroundTargetService.cs, SPEC §5.5, §9.3.
//
// Windows reads the foreground window handle, its process, and (via `GetGUIThreadInfo`) the
// focused child control without any permission. macOS has no unprivileged equivalent:
// - front application: `NSWorkspace.shared.frontmostApplication` (`processIdentifier`,
//   `bundleIdentifier`, `localizedName`) needs nothing;
// - the front window's id/title: `CGWindowListCopyWindowInfo` (`kCGWindowLayer == 0`, first
//   match for the front app's pid) needs nothing for the window number, but the *title* is
//   redacted (`kCGWindowName` absent) without Screen Recording on newer macOS (SPEC §5.5);
// - the focused UI element inside that window needs Accessibility
//   (`kAXFocusedUIElementAttribute`); without it this degrades to comparing only the front
//   window, same degradation Windows already documents when `GetGUIThreadInfo` has nothing to
//   report (SPEC §9.3, `Windows/README.md:12`).
//
// `focusedElementId` is `CFHash` of the `AXUIElement`, stringified: `AXUIElement` has no public
// persistent identifier, so this reuses its opaque identity (like a Windows control HWND) purely
// to detect "did the focused element change", never to look the element back up. Flagged for CI
// review: unverified fidelity of `CFHash` remaining stable for the lifetime of one focus session.

import AppKit
import ApplicationServices
import SnapBriefCore

public final class MacForegroundTargetService: ForegroundTargetServicing {
    public init() {}

    public func currentTarget() -> ForegroundTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = app.processIdentifier

        let (windowId, windowTitle) = Self.frontWindow(forPid: pid)
        let focusedElementId = TransportPermissions.hasAccessibilityAccess ? Self.focusedElementId(forPid: pid) : nil

        return ForegroundTarget(
            processName: app.localizedName ?? "",
            bundleIdentifier: app.bundleIdentifier,
            windowTitle: windowTitle,
            windowId: windowId,
            focusedElementId: focusedElementId)
    }

    /// SPEC §5.5: "номер переднего окна из `CGWindowListCopyWindowInfo` с `kCGWindowLayer == 0`",
    /// the first on-screen window (topmost) owned by `pid`.
    private static func frontWindow(forPid pid: pid_t) -> (windowId: Int, title: String?) {
        guard
            let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else {
            return (0, nil)
        }
        for window in info {
            guard
                let ownerPid = window[kCGWindowOwnerPID as String] as? pid_t,
                ownerPid == pid,
                let layer = window[kCGWindowLayer as String] as? Int,
                layer == 0,
                let number = window[kCGWindowNumber as String] as? Int
            else { continue }
            let title = window[kCGWindowName as String] as? String
            return (number, title)
        }
        return (0, nil)
    }

    /// SPEC §5.5: "Сфокусированный элемент — `kAXFocusedUIElementAttribute`, требует TCC Accessibility".
    /// SPEC-DELTA-2A §9 risk 2: `currentTarget()` can now be called synchronously from inside
    /// `MacPasteIntentObserver`'s tap callback (SPEC-DELTA-2A §1.2: "обработчик обязан быть...
    /// максимально коротким"), so this bounds the worst case a hung/unresponsive target app's
    /// Accessibility server can block that callback for.
    private static func focusedElementId(forPid pid: pid_t) -> String? {
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.1)
        var focused: AnyObject?
        let status = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focused)
        guard status == .success, let focused else { return nil }
        guard CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        return String(CFHash(focused))
    }
}
