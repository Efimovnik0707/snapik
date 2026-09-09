// Port of `CapturePreviewWindow.xaml.cs:98-112` (`CalculatePreviewBounds`) and `:235-243`
// (`UpdateFitZoom`), SPEC-DELTA-2 §1.5, SPEC-DELTA-2B §D.
import CoreGraphics

/// Pure geometry helpers for the preview window: no AppKit types, so they are trivially unit
/// testable without a window/screen.
enum PreviewGeometry {
    /// Port of `CalculatePreviewBounds`. Unlike Windows (which juggles DIP/pixel/DPI), macOS
    /// `NSScreen.visibleFrame` is already in points, so there is no DPI-scale parameter here —
    /// `workArea` is assumed to already be in points.
    static func previewBounds(workArea: CGRect) -> (frame: CGRect, minSize: CGSize) {
        let availableWidth = max(1, workArea.width - 32)
        let availableHeight = max(1, workArea.height - 32)
        let minSize = CGSize(width: min(720, availableWidth), height: min(500, availableHeight))
        let width = min(1100, availableWidth)
        let height = min(760, availableHeight)
        let frame = CGRect(
            x: workArea.minX + (workArea.width - width) / 2,
            y: workArea.minY + (workArea.height - height) / 2,
            width: width,
            height: height)
        return (frame, minSize)
    }

    /// Port of `UpdateFitZoom`'s formula: `Min((viewportW-8)/imageW, (viewportH-8)/imageH)`,
    /// clamped to `[0.05, 4]`. Returns `1` when `viewport`/`image` are degenerate (matches the
    /// Windows early-return, which simply leaves `_zoom` unchanged — callers of this pure
    /// function are expected to keep the previous zoom in that case instead of using this
    /// fallback, but `1` is a harmless default for direct unit testing).
    static func fitZoom(viewport: CGSize, image: CGSize) -> CGFloat {
        guard image.width > 0, image.height > 0, viewport.width > 8, viewport.height > 8 else { return 1 }
        let zoom = min((viewport.width - 8) / image.width, (viewport.height - 8) / image.height)
        return min(max(zoom, 0.05), 4)
    }
}
