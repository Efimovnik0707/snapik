// Port of `SingleInstanceActivation.cs`, SPEC §1.18, §9.6.
//
// Windows uses a named mutex plus a `named pipe` protocol with strict timeouts. macOS has no
// mutex; SPEC §9.6 prescribes relying on `NSRunningApplication` to detect another instance and a
// `DistributedNotificationCenter` broadcast (unacknowledged, best-effort) as the activation
// channel instead of a byte-exact pipe protocol.
import AppKit
import Foundation

enum SingleInstanceCoordinator {
    static let bundleIdentifier = "live.yesworkflow.snapik"
    static let activationNotificationName = Notification.Name("com.snapik.activation.show")
    /// The distinguishing payload, analogous to Windows' exact 5-byte `"SHOW\n"` command — any
    /// other object value is ignored by the observer.
    static let activationCommand = "SHOW"

    /// Port of `App.OnStartup`'s mutex check: if another instance of this bundle is already
    /// running, ask it to show itself and report whether we should exit.
    static func activateExistingInstanceIfRunning() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return false }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        guard let other = others.first else { return false }

        DistributedNotificationCenter.default().postNotificationName(
            activationNotificationName, object: activationCommand, userInfo: nil, deliverImmediately: true)
        other.activate(options: [])
        return true
    }

    /// Registers `handler` to run when another (second) instance broadcasts the activation
    /// command. The exact-value check on `object` mirrors Windows' exact-5-bytes check
    /// (`IsShowCommand`).
    static func observeActivationRequests(_ handler: @escaping () -> Void) -> NSObjectProtocol {
        DistributedNotificationCenter.default().addObserver(
            forName: activationNotificationName, object: nil, queue: .main
        ) { notification in
            guard notification.object as? String == activationCommand else { return }
            handler()
        }
    }

    static func stopObserving(_ token: NSObjectProtocol) {
        DistributedNotificationCenter.default().removeObserver(token)
    }
}
