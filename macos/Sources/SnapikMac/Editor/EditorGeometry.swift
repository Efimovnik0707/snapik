// Pure geometry helpers, no AppKit dependency (so they can be unit tested without a window).
// Ports scattered math from `OverlayEditorWindow.xaml.cs`, `OverlayEditorWindow.Resize.cs`,
// `Controls/AnnotationCanvas.cs`, SPEC §1.3, §1.4, §1.6, §1.8, §6.2, §6.3, §9.5.
import CoreGraphics
import Foundation
import SnapikCore

enum EditorGeometry {
    // MARK: - Image fitting (SPEC §6.3 `FitRect`)

    /// Port of `AnnotationCanvas.FitRect` (`:474-481`).
    static func fitRect(imageWidth: Double, imageHeight: Double, width: Double, height: Double, padding: Double) -> CGRect {
        let availableWidth = max(1, width - padding * 2)
        let availableHeight = max(1, height - padding * 2)
        let scale = min(availableWidth / max(1, imageWidth), availableHeight / max(1, imageHeight))
        let w = imageWidth * scale
        let h = imageHeight * scale
        return CGRect(x: (width - w) / 2, y: (height - h) / 2, width: w, height: h)
    }

    // MARK: - Selection (SPEC §1.2, `Normalize`)

    static func normalize(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    // MARK: - Annotation bounds (SPEC §6.3 `BoundsOf`)

    static func boundsOf(points: [CGPoint], additionalSegments: [[CGPoint]] = []) -> CGRect {
        let all = points + additionalSegments.flatMap { $0 }
        guard !all.isEmpty else { return .null }
        let minX = all.map(\.x).min()!
        let minY = all.map(\.y).min()!
        let maxX = all.map(\.x).max()!
        let maxY = all.map(\.y).max()!
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Port of `AnnotationCanvas.GetDisplayBounds` (`:259-268`): maps image-pixel bounds into the
    /// on-screen `imageRect` the canvas fit the image into.
    static func displayBounds(imageBounds: CGRect, imageRect: CGRect, imageWidth: Double, imageHeight: Double) -> CGRect {
        guard imageWidth > 0, imageHeight > 0 else { return .null }
        return CGRect(
            x: imageRect.minX + imageBounds.minX * imageRect.width / imageWidth,
            y: imageRect.minY + imageBounds.minY * imageRect.height / imageHeight,
            width: imageBounds.width * imageRect.width / imageWidth,
            height: imageBounds.height * imageRect.height / imageHeight)
    }

    /// Port of `AnnotationCanvas.GestureHasSize` (`:417-422`, SPEC §1.3 "Порог создания отметки").
    /// SPEC-DELTA-2B.md §C3: `.comment`/`.text` always count as having size — a Comment is a
    /// one-shot single click (no drag threshold at all) and Text already committed with a single
    /// click before this sync.
    /// `scale` is points-per-image-pixel: "press and drag" is measured **on screen** and not in the
    /// pixels of the capture (SPEC-DELTA-3 §1.4 E-10), because at the scale a 1920 px capture is
    /// shown with, three image pixels are under two pixels of hand tremor.
    static func gestureHasSize(kind: EditorTool, points: [CGPoint], scale: CGFloat = 1) -> Bool {
        guard points.count >= 2 else { return false }
        if kind == .comment || kind == .text { return true }
        if kind == .pen || kind == .highlight { return points.count > 2 }
        let dx = points[1].x - points[0].x
        let dy = points[1].y - points[0].y
        return (dx * dx + dy * dy).squareRoot() * scale >= gestureThreshold
    }

    /// Port of `AnnotationCanvas.GestureThreshold` (`:752`).
    static let gestureThreshold: CGFloat = 4

    // MARK: - Hit testing (SPEC §6.3)

    /// Port of the rectangle hit test (`AnnotationCanvas.cs:562-577`, SPEC-DELTA-3 §1.4 E-13). The
    /// box is drawn through the middle of the stroke, so it is widened by half of it and a little to
    /// grab by. Twice the whole width was the same thing while the thickness of the highlighter
    /// meant a quarter of its real one; with the real width it reached 96 px, and the eraser took
    /// strokes the hand was nowhere near.
    static func hitTestInflatedBounds(_ bounds: CGRect, thickness: Double) -> CGRect {
        let inset = -max(8, thickness / 2 + 4)
        return bounds.insetBy(dx: inset, dy: inset)
    }

    /// Port of `DistanceToPolyline`/`DistanceToSegment` (`AnnotationCanvas.cs:861-878`): how far a
    /// point is from a line the hand may grab (the shaft of an arrow, the stroke of a pencil).
    static func distanceToPolyline(_ points: [CGPoint], _ target: CGPoint) -> CGFloat {
        guard let first = points.first else { return .greatestFiniteMagnitude }
        guard points.count > 1 else { return hypot(target.x - first.x, target.y - first.y) }
        var best = CGFloat.greatestFiniteMagnitude
        for index in 1..<points.count {
            best = min(best, distanceToSegment(points[index - 1], points[index], target))
        }
        return best
    }

    private static func distanceToSegment(_ start: CGPoint, _ end: CGPoint, _ target: CGPoint) -> CGFloat {
        let line = CGPoint(x: end.x - start.x, y: end.y - start.y)
        let lengthSquared = line.x * line.x + line.y * line.y
        guard lengthSquared > .ulpOfOne else { return hypot(target.x - start.x, target.y - start.y) }
        let dot = (target.x - start.x) * line.x + (target.y - start.y) * line.y
        let position = min(max(dot / lengthSquared, 0), 1)
        return hypot(target.x - (start.x + line.x * position), target.y - (start.y + line.y * position))
    }

    // MARK: - Comment chip placement / hover-edge hit testing (SPEC-DELTA-2B.md §C3, §C7)

    /// Port of `FindChipPlacement` (SPEC-DELTA-2.md §1.3 "Автораскладка `FindChipPlacement`"):
    /// tries `preferred` first, then spirals outward in rings of 8 offsets (down, right, left, up,
    /// then the 4 diagonals), each ring `ring` chip-widths/heights further out, clamped into `work`
    /// with an 8pt margin. Occupancy is tested against `occupied` inflated by `gap` on every side,
    /// matching the Windows "занятость по инфлейту на 6" rule. Falls back to the (still-clamped)
    /// preferred rect if all 14 rings are occupied.
    static func findChipPlacement(preferred: CGPoint, size: CGSize, work: CGRect, occupied: [CGRect]) -> CGRect {
        let gap: CGFloat = 6
        let margin: CGFloat = 8

        func clampedRect(at origin: CGPoint) -> CGRect {
            let x = clamp(origin.x, work.minX + margin, max(work.minX + margin, work.maxX - size.width - margin))
            let y = clamp(origin.y, work.minY + margin, max(work.minY + margin, work.maxY - size.height - margin))
            return CGRect(x: x, y: y, width: size.width, height: size.height)
        }

        func isFree(_ candidate: CGRect) -> Bool {
            !occupied.contains(where: { $0.insetBy(dx: -gap, dy: -gap).intersects(candidate) })
        }

        let preferredRect = clampedRect(at: preferred)
        if isFree(preferredRect) { return preferredRect }

        for ring in 1...14 {
            let stepX = (size.width + gap) * CGFloat(ring)
            let stepY = (max(40, size.height) + gap) * CGFloat(ring)
            let offsets: [CGPoint] = [
                CGPoint(x: 0, y: stepY), CGPoint(x: stepX, y: 0), CGPoint(x: -stepX, y: 0), CGPoint(x: 0, y: -stepY),
                CGPoint(x: stepX, y: stepY), CGPoint(x: -stepX, y: stepY), CGPoint(x: stepX, y: -stepY), CGPoint(x: -stepX, y: -stepY),
            ]
            for offset in offsets {
                let candidate = clampedRect(at: CGPoint(x: preferred.x + offset.x, y: preferred.y + offset.y))
                if isFree(candidate) { return candidate }
            }
        }
        return preferredRect
    }

    /// Port of `AnnotationCanvas.FindMoveEdge`'s per-annotation hit ring (`:417-428`): the outer
    /// ring is `displayBounds` inflated by 6pt, the inner ring is inset by `min(6, w/2)`/
    /// `min(6, h/2)`; a hit is inside the outer ring but outside the inner one (the border band).
    /// Only meaningful for Rectangle/Blur/Conceal — the caller filters by kind and active tool.
    /// `band` is how wide the grabbable ring around the outline is (`IsMoveHandle`'s default
    /// branch). [ТЗ№4 D3, variant Б] a mark of the **same kind as the tool in the hand** widens it
    /// from 6 to 10, so "a frame is grabbed by the frame" without the empty interior being taken
    /// away from the next drawing (`tasks/tz-005-details/D-editor.md` §4.3).
    static func findMoveEdge(displayBounds: CGRect, point: CGPoint, band: CGFloat = 6) -> Bool {
        let outer = displayBounds.insetBy(dx: -band, dy: -band)
        guard outer.contains(point) else { return false }
        let insetX = min(band, displayBounds.width / 2)
        let insetY = min(band, displayBounds.height / 2)
        let inner = displayBounds.insetBy(dx: insetX, dy: insetY)
        return !inner.contains(point)
    }

    /// Port of `MoveLinkedComments`'s point remap (SPEC-DELTA-2.md §1.3): when the parent's bounds
    /// actually changed, each point is carried through `ResizeGeometry.map` from `oldParent` to
    /// `newParent`; when the parent had zero size before (never resized, only moved), a plain
    /// `parentDelta` shift is used instead. Result is clamped into `[0, imageSize]`.
    static func linkedCommentPoints(_ points: [CGPoint], oldParent: CGRect, newParent: CGRect, parentDelta: CGPoint, imageSize: CGSize) -> [CGPoint] {
        func clampToImage(_ p: CGPoint) -> CGPoint {
            CGPoint(x: clamp(p.x, 0, imageSize.width), y: clamp(p.y, 0, imageSize.height))
        }
        guard oldParent.width > 0, oldParent.height > 0 else {
            return points.map { clampToImage(CGPoint(x: $0.x + parentDelta.x, y: $0.y + parentDelta.y)) }
        }
        return points.map { clampToImage(ResizeGeometry.map($0, original: oldParent, resized: newParent)) }
    }

    // MARK: - Toolbar positioning (SPEC §6.2 `PositionToolbar`, "Дополнение 2026-09-09")

    /// Port of `OverlayEditorWindow.Toolbar.cs::PlaceToolbar` (new in the 2026-09-09 Windows
    /// sync, replacing the old single-side-then-one-alternate `PositionToolbar` body below).
    /// Tries the 4 exterior candidate rects around `crop` (below/above/right/left), preferring
    /// the first that lands fully inside `work` and avoids both `crop` and every rect in `notes`;
    /// falls back to the first crop-avoiding candidate, then — only when `crop` has no exterior
    /// room at all (a full-screen selection) — to a rect that may still overlap a note.
    static func placeToolbar(crop: CGRect, work: CGRect, size: CGSize, notes: [CGRect]) -> CGRect {
        let gap: CGFloat = 10
        let left = clamp(crop.minX + (crop.width - size.width) / 2, work.minX + 8, max(work.minX + 8, work.maxX - size.width - 8))
        let sideTop = clamp(crop.minY + (crop.height - size.height) / 2, work.minY + 8, max(work.minY + 8, work.maxY - size.height - 8))
        let candidates = [
            CGRect(x: left, y: crop.maxY + gap, width: size.width, height: size.height),
            CGRect(x: left, y: crop.minY - size.height - gap, width: size.width, height: size.height),
            CGRect(x: crop.maxX + gap, y: sideTop, width: size.width, height: size.height),
            CGRect(x: crop.minX - size.width - gap, y: sideTop, width: size.width, height: size.height),
        ].filter { work.contains($0) && !$0.intersects(crop) }

        // Preserve the image even when every outside position is near a note.
        if let clear = candidates.first(where: { candidate in !notes.contains(where: { $0.intersects(candidate) }) }) {
            return clear
        }
        if let first = candidates.first { return first }

        // A full-screen selection has no exterior space on its monitor.
        let bottom = clamp(crop.maxY - size.height - gap, work.minY + 8, max(work.minY + 8, work.maxY - size.height - 8))
        let top = clamp(crop.minY + gap, work.minY + 8, max(work.minY + 8, work.maxY - size.height - 8))
        let fallback = CGRect(x: left, y: bottom, width: size.width, height: size.height)
        let alternate = CGRect(x: left, y: top, width: size.width, height: size.height)
        if notes.contains(where: { $0.intersects(fallback) }), !notes.contains(where: { $0.intersects(alternate) }) {
            return alternate
        }
        return fallback
    }

    /// Port of `PositionToolbar` (`:481-511`), now a thin wrapper around `placeToolbar` (SPEC
    /// §6.2 "Дополнение 2026-09-09"). `obstacles` are the currently-visible comment chip /
    /// shot-note-chip rects (same coordinate space). Returns the toolbar's top-left.
    static func positionToolbar(cropRect: CGRect, work: CGRect, toolbarSize rawSize: CGSize, obstacles: [CGRect]) -> CGPoint {
        let width = max(rawSize.width, 380)
        let height = max(rawSize.height, 50)
        return placeToolbar(crop: cropRect, work: work, size: CGSize(width: width, height: height), notes: obstacles).origin
    }

    // MARK: - Capture corner handles (SPEC §1.6)

    /// Clockwise corners of `rect`: 0 = top-left, 1 = top-right, 2 = bottom-right, 3 = bottom-left
    /// in the editor's top-left-origin, Y-down local space (matches `ResizeGeometry.Corners`
    /// applied to a `Rect` whose `.TopLeft`/`.TopRight`/... are already Y-down).
    static func corners(_ rect: CGRect) -> [CGPoint] {
        [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY),
        ]
    }

    /// Port of `UpdateCaptureHandles` handle placement (`Resize.cs:112-119`): `corner - 11`,
    /// clamped into the window bounds, for a 22x22 hit target.
    static func captureHandleOrigins(cropRect: CGRect, windowSize: CGSize, handleSize: CGFloat = 22) -> [CGPoint] {
        corners(cropRect).map { corner in
            CGPoint(
                x: clamp(corner.x - handleSize / 2, 0, max(0, windowSize.width - handleSize)),
                y: clamp(corner.y - handleSize / 2, 0, max(0, windowSize.height - handleSize)))
        }
    }

    // MARK: - Pixel <-> local-point conversions (SPEC §1.2 step 8, §9.5)

    /// Port of the `scaleX/scaleY = frame.PixelWidth/ActualWidth` conversion used both by the
    /// initial selection crop (`OnWindowMouseUp:203-211`) and by `GetCropMonitorWorkArea`
    /// (`:598-611`).
    static func pixelScale(actualSize: CGSize, framePixelSize: CGSize) -> CGPoint {
        CGPoint(x: framePixelSize.width / max(1, actualSize.width), y: framePixelSize.height / max(1, actualSize.height))
    }

    /// Port of the initial-selection pixel rect + clamp in `OnWindowMouseUp` (`:203-211`).
    /// `localRect` is in the selecting window's local point space.
    static func selectionPixelRect(localRect: CGRect, actualSize: CGSize, framePixelSize: CGSize) -> CGRect {
        let scale = pixelScale(actualSize: actualSize, framePixelSize: framePixelSize)
        var x = clampInt(Int((localRect.minX * scale.x).rounded()), 0, max(0, Int(framePixelSize.width) - 1))
        var y = clampInt(Int((localRect.minY * scale.y).rounded()), 0, max(0, Int(framePixelSize.height) - 1))
        var width = max(1, Int((localRect.width * scale.x).rounded()))
        var height = max(1, Int((localRect.height * scale.y).rounded()))
        if x + width > Int(framePixelSize.width) { width = Int(framePixelSize.width) - x }
        if y + height > Int(framePixelSize.height) { height = Int(framePixelSize.height) - y }
        x = max(0, x)
        y = max(0, y)
        width = max(1, width)
        height = max(1, height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Port of the in-canvas crop request pixel rect (`OnCropRequested:671-677`): floor/ceil
    /// clamp, minimum **8x8** image pixels (SPEC §1.3 "Crop как отдельный случай").
    static func cropRequestPixelRect(bounds: CGRect, imageWidth: Int, imageHeight: Int) -> CGRect? {
        let left = clampInt(Int(bounds.minX.rounded(.down)), 0, max(0, imageWidth - 1))
        let top = clampInt(Int(bounds.minY.rounded(.down)), 0, max(0, imageHeight - 1))
        let right = clampInt(Int(bounds.maxX.rounded(.up)), left + 1, imageWidth)
        let bottom = clampInt(Int(bounds.maxY.rounded(.up)), top + 1, imageHeight)
        guard right - left >= 8, bottom - top >= 8 else { return nil }
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    static func normalizedRect(pixelRect: CGRect, imageWidth: Int, imageHeight: Int) -> NormalizedRect {
        NormalizedRect(
            Double(pixelRect.minX) / Double(imageWidth),
            Double(pixelRect.minY) / Double(imageHeight),
            Double(pixelRect.width) / Double(imageWidth),
            Double(pixelRect.height) / Double(imageHeight))
    }

    // MARK: - Capture corner resize (SPEC §1.6)

    struct CaptureResizePlan {
        /// Integer pixel rect within the resize source image.
        let sourcePixelRect: CGRect
        /// The annotation-space scale/offset to remap every point of every annotation into the
        /// new source's coordinate system (SPEC §1.6 step 3 formulas).
        let annotationScale: CGPoint
        let annotationOffset: CGPoint
        /// New crop rect, in the editing window's local point space.
        let newCropRectLocal: CGRect
    }

    /// Port of `ApplyCaptureResizeAsync` (`Resize.cs:140-190`), steps 1 and 3's pixel/offset math
    /// (step 2's disk write and step 4's `CaptureCropper.crop` call happen in the AppKit-facing
    /// controller, which has access to `SessionAssetStore`/`CaptureCropper`).
    static func captureResizePlan(
        requestedRectLocal: CGRect,
        resizeSourceRectLocal: CGRect,
        resizeSourcePixelSize: CGSize,
        currentCropRectLocal: CGRect,
        currentCapturePixelSize: CGSize
    ) -> CaptureResizePlan {
        let sx = resizeSourcePixelSize.width / max(1, resizeSourceRectLocal.width)
        let sy = resizeSourcePixelSize.height / max(1, resizeSourceRectLocal.height)

        let left = clampInt(Int(((requestedRectLocal.minX - resizeSourceRectLocal.minX) * sx).rounded()), 0, Int(resizeSourcePixelSize.width) - 1)
        let top = clampInt(Int(((requestedRectLocal.minY - resizeSourceRectLocal.minY) * sy).rounded()), 0, Int(resizeSourcePixelSize.height) - 1)
        let right = clampInt(Int(((requestedRectLocal.maxX - resizeSourceRectLocal.minX) * sx).rounded()), left + 1, Int(resizeSourcePixelSize.width))
        let bottom = clampInt(Int(((requestedRectLocal.maxY - resizeSourceRectLocal.minY) * sy).rounded()), top + 1, Int(resizeSourcePixelSize.height))
        let sourcePixelRect = CGRect(x: left, y: top, width: right - left, height: bottom - top)

        let offset = CGPoint(
            x: (currentCropRectLocal.minX - resizeSourceRectLocal.minX) * sx,
            y: (currentCropRectLocal.minY - resizeSourceRectLocal.minY) * sy)
        let scale = CGPoint(
            x: currentCropRectLocal.width * sx / max(1, currentCapturePixelSize.width),
            y: currentCropRectLocal.height * sy / max(1, currentCapturePixelSize.height))

        let newCropRect = CGRect(
            x: resizeSourceRectLocal.minX + CGFloat(left) / sx,
            y: resizeSourceRectLocal.minY + CGFloat(top) / sy,
            width: CGFloat(sourcePixelRect.width) / sx,
            height: CGFloat(sourcePixelRect.height) / sy)

        return CaptureResizePlan(
            sourcePixelRect: sourcePixelRect,
            annotationScale: scale,
            annotationOffset: offset,
            newCropRectLocal: newCropRect)
    }

    /// Port of the point remap in `ApplyCaptureResizeAsync` (`:164-167`): `p * scale + offset`.
    static func remapAnnotationPoint(_ point: CGPoint, scale: CGPoint, offset: CGPoint) -> CGPoint {
        CGPoint(x: point.x * scale.x + offset.x, y: point.y * scale.y + offset.y)
    }

    /// Port of the crop-rect rescale after an in-canvas crop (`OnCropRequested:694-699`).
    static func rescaledCropRect(oldCropRectLocal: CGRect, pixelRect: CGRect, imageWidth: Int, imageHeight: Int) -> CGRect {
        CGRect(
            x: oldCropRectLocal.minX + oldCropRectLocal.width * pixelRect.minX / CGFloat(imageWidth),
            y: oldCropRectLocal.minY + oldCropRectLocal.height * pixelRect.minY / CGFloat(imageHeight),
            width: oldCropRectLocal.width * pixelRect.width / CGFloat(imageWidth),
            height: oldCropRectLocal.height * pixelRect.height / CGFloat(imageHeight))
    }

    /// Port of the reopen-from-stack scale rule (SPEC §1.9 point 2, `OverlayEditorWindow.xaml.cs:156-163`):
    /// `min(0.72*W/imgW, 0.72*H/imgH)`, centered in the editing window.
    static func reopenCropRect(imageSize: CGSize, windowSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(0.72 * windowSize.width / imageSize.width, 0.72 * windowSize.height / imageSize.height)
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        return CGRect(x: (windowSize.width - w) / 2, y: (windowSize.height - h) / 2, width: w, height: h)
    }

    // MARK: - Blur radius (SPEC §1.7)

    /// Port of `BlurRadius` (`AnnotationCanvas.cs:463`): `clamp(round(thickness*3), 4, 36)`.
    static func blurRadius(thickness: Double) -> Int {
        clampInt(Int((thickness * 3).rounded()), 4, 36)
    }

    // MARK: - Small numeric helpers

    static func clamp(_ value: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        min(max(value, lo), hi)
    }

    static func clampInt(_ value: Int, _ lo: Int, _ hi: Int) -> Int {
        min(max(value, lo), hi)
    }
}
