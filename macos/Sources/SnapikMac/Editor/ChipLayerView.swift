// New in the 2026-09-09 sync (SPEC-DELTA-2B.md §C7 "Новый `ChipLayerView`"). Host view for every
// comment chip on one screen, sized to the whole `OverlayContentView`. Flipped (matches every
// other editor view's top-left-origin, Y-down convention) and hit-test-transparent outside its
// subviews, so clicks over the desktop/canvas that don't land on a chip fall through to whatever
// is layered underneath instead of being swallowed by this otherwise-invisible full-screen view.
import AppKit

final class ChipLayerView: NSView {
    override var isFlipped: Bool { true }

    /// `point` arrives already in this view's own coordinate system, which — per
    /// `NSView.hitTest(_:)`'s contract — is exactly the coordinate system `subview.hitTest(_:)`
    /// expects for its own `point` argument (its superview's coordinates), so no conversion is
    /// needed between the two calls below.
    override func hitTest(_ point: NSPoint) -> NSView? {
        for subview in subviews.reversed() {
            if let hit = subview.hitTest(point) { return hit }
        }
        return nil
    }
}
