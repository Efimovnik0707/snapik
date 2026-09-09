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
    /// HIGH-2 fix: `currentTarget()` can now run synchronously inside the CGEvent tap callback on
    /// every V keystroke (`MacPasteIntentObserver.handle(type:event:)`, SPEC-DELTA-2A §1.2's "the
    /// handler must be... as short as possible"); `CGWindowListCopyWindowInfo` walks every
    /// on-screen window and is too expensive to call there each time. Instead this caches the
    /// front app's window id/title, refreshed only when `NSWorkspace` reports the frontmost
    /// application actually changed — a stale window id from switching windows *within* the same
    /// still-frontmost app is an accepted approximation (SPEC-DELTA-2A review: "допустимо").
    private var cachedWindow: (pid: pid_t, windowId: Int, title: String?)?
    private var activationObserver: NSObjectProtocol?

    public init() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            self?.refreshCachedWindow(forPid: app.processIdentifier)
        }
        if let app = NSWorkspace.shared.frontmostApplication {
            refreshCachedWindow(forPid: app.processIdentifier)
        }
    }

    deinit {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
    }

    public func currentTarget() -> ForegroundTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = app.processIdentifier

        let windowId: Int
        let windowTitle: String?
        if let cached = cachedWindow, cached.pid == pid {
            windowId = cached.windowId
            windowTitle = cached.title
        } else {
            // Cache miss: the frontmost app changed since the last `didActivateApplicationNotification`
            // we observed (e.g. this is the very first call). Falls back to the direct lookup once
            // and primes the cache so the next call (almost always the matching `keyUp`, or the
            // next V keystroke) hits the fast path above.
            let resolved = Self.frontWindow(forPid: pid)
            cachedWindow = (pid, resolved.windowId, resolved.title)
            windowId = resolved.windowId
            windowTitle = resolved.title
        }
        let focusedElementId = TransportPermissions.hasAccessibilityAccess ? Self.focusedElementId(forPid: pid) : nil

        return ForegroundTarget(
            processName: app.localizedName ?? "",
            bundleIdentifier: app.bundleIdentifier,
            windowTitle: windowTitle,
            windowId: windowId,
            focusedElementId: focusedElementId)
    }

    private func refreshCachedWindow(forPid pid: pid_t) {
        let resolved = Self.frontWindow(forPid: pid)
        cachedWindow = (pid, resolved.windowId, resolved.title)
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
