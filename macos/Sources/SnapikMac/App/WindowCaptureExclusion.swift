// Port of `SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE)` policy switch, SPEC §9.8.
import AppKit

/// SPEC §9.8: Snapik's own windows (stack panel, overlay) are excluded from *other* apps'
/// screen captures (`NSWindow.sharingType = .none`). That is the production default. The CI-only
/// `--demo-screenshot` flow needs the opposite so that the runner's `screencapture` and our own
/// `CGWindowListCreateImage` can show the windows; it flips this switch before any window exists.
@MainActor
enum WindowCaptureExclusion {
    /// `true` (default): windows use `sharingType = .none`. `false`: `.readOnly`.
    static var isEnabled = true

    static var sharingType: NSWindow.SharingType { isEnabled ? .none : .readOnly }
}
