// Port of `src/Snapik.App/Controls/StripResizeGeometry.cs`, SPEC-DELTA-3 §1.3 S-9, §2.5.
import Foundation

/// The width of the strip, dragged by its left edge. The right edge is fixed while the drag lasts,
/// so the card grows into the screen instead of walking away from it. Sizes are window sizes: the
/// visible card is narrower by the margin that carries the shadow (`StackMetrics`, the Stack zone).
///
/// Every figure is taken **from the start of the drag**, never as a sum of deltas: a delta added to
/// the width of the moment keeps the travel already spent beyond a clamp, and the strip then ignores
/// the whole way back until the pointer has given that travel up again — the dead zone the strip was
/// reported to have.
public enum StripResizeGeometry {
    /// [ТЗ№4 C4] 224 on both edges: the strip of this round is 224 wide and never narrower. On
    /// Windows 1.4.0 the pair is still 200/208.
    public static let minimumWidth: Double = 224
    public static let defaultWidth: Double = 224

    /// The gap the strip keeps between itself and the right edge of the working area. It is also the
    /// ceiling of the width: a strip as wide as the whole working area would have to start outside
    /// of it to keep that gap.
    public static let edgeGap: Double = 10

    /// The height of the strip is the height of the capture list, not of the window: the window
    /// derives its own height from this one. The card and the overlap stay as they are, the visible
    /// part of the list is what grows. There is no number above: the working area of the monitor is
    /// the only ceiling.
    public static let minimumListHeight: Double = 180
    public static let defaultListHeight: Double = 372

    /// Everything of the strip window that is not the list: the header, the capture button, the
    /// toast, the status line and the paddings of the card. The window measures its own before the
    /// first drag; this is the figure used until there is something to measure, and it is on the
    /// generous side on purpose — a list clamped a little short still fits on the screen.
    public static let estimatedChromeHeight: Double = 140

    /// A width from the settings file. The ceiling is the working area of the screen the strip opens
    /// on, less the gap it keeps at the edge, so a width dragged out on a large monitor is pulled
    /// back in on a small one; nonsense falls back to the default. When the working area is unknown
    /// there is no ceiling, only the minimum.
    public static func clampWidth(_ width: Double, workWidth: Double) -> Double {
        let ceiling =
            workWidth.isFinite && workWidth > 0
            ? max(minimumWidth, workWidth - edgeGap)
            : Double.infinity
        if !width.isFinite { return min(defaultWidth, ceiling) }
        return min(max(width, minimumWidth), ceiling)
    }

    /// The left edge and the width for a pointer that has travelled `pointerDelta` points from where
    /// it was when the drag began, measured against `startWidth`, the width the strip had at that
    /// same moment. The strip never crosses `leftLimit`, the left edge of the working area it sits in.
    public static func widthFromStart(
        right: Double,
        startWidth: Double,
        pointerDelta: Double,
        leftLimit: Double
    ) -> (left: Double, width: Double) {
        let start = startWidth.isFinite ? startWidth : defaultWidth
        let delta = pointerDelta.isFinite ? pointerDelta : 0
        let allowed = max(minimumWidth, right - leftLimit)
        let resized = min(max(start - delta, minimumWidth), allowed)
        return (right - resized, resized)
    }

    /// A list height from the settings file: out of range is clamped, nonsense falls back to the
    /// default. The working area is a ceiling of its own, and the window is taller than its list by
    /// `chromeHeight`, so a height stored on a large monitor opens a window that still fits on the
    /// screen it comes back on, together with the corner grip that resizes it.
    public static func clampListHeight(_ height: Double, workHeight: Double, chromeHeight: Double)
        -> Double
    {
        let chrome = chromeHeight.isFinite && chromeHeight > 0 ? chromeHeight : estimatedChromeHeight
        let ceiling =
            workHeight.isFinite && workHeight > 0
            ? max(minimumListHeight, workHeight - chrome)
            : Double.infinity
        let stored = height.isFinite ? height : defaultListHeight
        return min(max(stored, minimumListHeight), ceiling)
    }

    /// The height of the capture list for a pointer that has travelled `pointerDelta` points
    /// downwards from where it was when the drag began, measured against `startListHeight`, the
    /// height the list had at that same moment — the way back from a clamp then moves the strip on
    /// the first pixel. The top edge stays where it was, so the strip grows down; `chromeHeight` is
    /// everything of the window that is not the list, and it keeps the bottom of the window inside
    /// `workBottom`.
    public static func listHeightFromStart(
        startListHeight: Double,
        pointerDelta: Double,
        chromeHeight: Double,
        top: Double,
        workBottom: Double
    ) -> Double {
        let start = startListHeight.isFinite ? startListHeight : defaultListHeight
        let delta = pointerDelta.isFinite ? pointerDelta : 0
        let available = workBottom - top - max(0, chromeHeight)
        let ceiling = max(minimumListHeight, available)
        return min(max(start + delta, minimumListHeight), ceiling)
    }
}
