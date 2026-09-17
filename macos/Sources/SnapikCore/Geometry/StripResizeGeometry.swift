// Port of `src/Snapik.App/Controls/StripResizeGeometry.cs`, SPEC-DELTA-3 §1.3 S-9, §2.5,
// SPEC-DELTA-4 §2.5, §3.1.
import Foundation

/// The width of the strip, dragged by its left edge. The right edge is fixed while the drag lasts,
/// so the card grows into the screen instead of walking away from it. Sizes are window sizes: the
/// visible panel is 20 points narrower on each side, and that field carries the shadow
/// (`StackMetrics.shadowMargin`, the Stack zone).
///
/// Every figure is taken **from the start of the drag**, never as a sum of deltas: a delta added to
/// the width of the moment keeps the travel already spent beyond a clamp, and the strip then ignores
/// the whole way back until the pointer has given that travel up again — the dead zone the strip was
/// reported to have.
public enum StripResizeGeometry {
    /// 244 on both edges: the panel the user sees is 204 wide and the field under the shadow takes
    /// 20 on each side (`204 + 2 · 20`). A width stored by a build whose floor was 200, 208 or the
    /// 224 of the intermediate round is lifted to this one by `clampWidth`: the panel it stood for
    /// is narrower than the one the strip draws now (SPEC-DELTA-4 §2.5).
    public static let minimumWidth: Double = 244
    public static let defaultWidth: Double = 244

    /// The gap the strip keeps between itself and the right edge of the working area. It is also the
    /// ceiling of the width: a strip as wide as the whole working area would have to start outside
    /// of it to keep that gap. The field under the shadow is the gap that is seen now, so this one
    /// is zero and the panel still stands 20 points away from the edge.
    public static let edgeGap: Double = 0

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
    public static let estimatedChromeHeight: Double = 160

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

    // MARK: - The list by its contents (SPEC-DELTA-5 §1.10, `StripResizeGeometry.cs:37-103`)

    /// The hint that stands where the list is while the strip holds nothing.
    public static let emptyListHeight: Double = 92

    public static let listTopPadding: Double = 14
    public static let listBottomPadding: Double = 8

    /// The paddings of the capture list are not the same on both sides: the right one carries the
    /// scroll bar, which stands over the cards and needs a field of its own, and the left one gives
    /// those four points back so that the card keeps the 168 of the reference shot. The strip reads
    /// them through `StackMetrics`, which derives its numbers from these ones.
    public static let listPaddingLeft: Double = 4
    public static let listPaddingRight: Double = 12

    /// A card and the part of it the next card lies over; the difference is the pitch.
    public static let cardHeight: Double = 78
    public static let cardOverlap: Double = 48
    public static let cardPitch: Double = cardHeight - cardOverlap

    /// The height the capture list wants for `count` cards, and the ceiling the corner grip has
    /// written into the settings. The grip sets the ceiling, not the height: a list of two cards is
    /// 130 tall whatever the settings say, and it stops growing at the ceiling.
    /// `minimumListHeight` is no floor here — it belongs to the stored number alone, otherwise a
    /// single capture would open a list of 180 instead of 100.
    public static func listHeightForCount(_ count: Int, cap: Double) -> Double {
        if count <= 0 { return emptyListHeight }
        let content = listTopPadding + Double(count - 1) * cardPitch + cardHeight + listBottomPadding
        let ceiling = cap.isFinite && cap > 0 ? cap : defaultListHeight
        return min(content, ceiling)
    }

    /// The height of the list: dragged by hand it is the stored number itself, automatic it is the
    /// height of what the list holds. The stored number and the clamps it went through are the same
    /// in both; what the drag changes is whether that number is a ceiling or the height.
    public static func listHeight(count: Int, stored: Double, manual: Bool) -> Double {
        manual ? stored : listHeightForCount(count, cap: stored)
    }

    /// The left edge of the capsule, so that it keeps the right edge of the strip it came from
    /// rather than the edge of the monitor: both windows carry the same field under their shadow,
    /// so the sides the user sees line up.
    public static func capsuleLeft(stripLeft: Double, stripWidth: Double, capsuleWidth: Double)
        -> Double
    {
        stripLeft + stripWidth - capsuleWidth
    }

    /// The rectangle the strip had before the capsule, moved back into the working area only when it
    /// no longer fits: a strip dragged away from the edge stays where the user left it.
    ///
    /// Plain numbers and not a `CGRect`, because Core knows Foundation alone (SPEC-DELTA-5 §2.5);
    /// the caller in the Stack zone takes the two rectangles apart. The width and the height never
    /// move, so the answer is the point. `work` is read as "from `workX`/`workY`, `workWidth` wide
    /// and `workHeight` tall", which is the same pair of edges on either axis direction: what
    /// Windows calls `Top`/`Bottom` is the smaller and the larger edge here too.
    public static func restoreRect(
        x: Double, y: Double, width: Double, height: Double,
        workX: Double, workY: Double, workWidth: Double, workHeight: Double
    ) -> (x: Double, y: Double) {
        let workRight = workX + workWidth
        let workBottom = workY + workHeight
        // The order of the guards is the one of `!work.IsEmpty && work.Width > 0 &&
        // work.Height > 0 && !work.Contains(stored)`: an empty working area is exactly the one with
        // no width or no height here, so the first of the four guards has nothing of its own left
        // to ask. `Rect.Contains(Rect)` is "every edge of the stored one is inside".
        let contains =
            workX <= x && workY <= y && workRight >= x + width && workBottom >= y + height
        if workWidth > 0 && workHeight > 0 && !contains {
            return (
                min(max(x, workX), max(workX, workRight - width)),
                min(max(y, workY), max(workY, workBottom - height))
            )
        }
        return (x, y)
    }
}
