// Port of the `SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE)` policy switch, SPEC §9.8,
// SPEC-DELTA-3 §1.3 S-14 ([ТЗ№4 C7]).
import AppKit

/// [ТЗ№4 C7] The strip no longer hides from every screenshot in the world, only from **ours**. The
/// default is `sharingType = .readOnly`: a screenshot taken with Cmd+Shift+4, a screen recording or
/// a call sharing the display all see the strip, the way every other window of the desktop is seen.
/// `.none` is put on for the length of our own capture and taken off straight after, which is what
/// `beginOwnCapture()`/`endOwnCapture()` are for.
///
/// `isEnabled` stays as the CI-only switch it has always been: `--demo-screenshot` turns the whole
/// mechanism off before any window exists, so the runner's `screencapture` and our own window dumps
/// see everything.
@MainActor
enum WindowCaptureExclusion {
    /// `false` takes the mechanism out of the picture entirely (CI screenshots).
    static var isEnabled = true

    /// `true` only between `beginOwnCapture()` and `endOwnCapture()`.
    private(set) static var isCapturing = false

    /// What a window of ours is created with, and what it goes back to after a capture of ours.
    static var sharingType: NSWindow.SharingType { isEnabled && isCapturing ? .none : .readOnly }

    /// Called by the capture path (the coordinator's `hideForCapture` equivalent) right before our
    /// own frame is taken: every window of ours drops out of the capture for the length of it.
    static func beginOwnCapture() {
        guard isEnabled, !isCapturing else { return }
        isCapturing = true
        applyToOwnWindows()
    }

    static func endOwnCapture() {
        guard isCapturing else { return }
        isCapturing = false
        applyToOwnWindows()
    }

    private static func applyToOwnWindows() {
        let sharing = sharingType
        for window in NSApplication.shared.windows { window.sharingType = sharing }
    }
}
