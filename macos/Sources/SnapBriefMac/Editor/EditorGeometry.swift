// Pure geometry helpers, no AppKit dependency (so they can be unit tested without a window).
// Ports scattered math from `OverlayEditorWindow.xaml.cs`, `OverlayEditorWindow.Resize.cs`,
// `Controls/AnnotationCanvas.cs`, SPEC §1.3, §1.4, §1.6, §1.8, §6.2, §6.3, §9.5.
import CoreGraphics
import Foundation
import SnapBriefCore

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
    static func gestureHasSize(kind: EditorTool, points: [CGPoint]) -> Bool {
        guard points.count >= 2 else { return false }
        if kind == .pen || kind == .highlight { return points.count > 2 }
        let dx = points[1].x - points[0].x
        let dy = points[1].y - points[0].y
        return (dx * dx + dy * dy).squareRoot() >= 3
    }

    // MARK: - Hit testing (SPEC §6.3)

    /// Port of the inflate-by-`max(8, thickness*2)` rectangle hit test (`:316-326`).
    static func hitTestInflatedBounds(_ bounds: CGRect, thickness: Double) -> CGRect {
        let inset = -max(8, thickness * 2)
        return bounds.insetBy(dx: inset, dy: inset)
    }

    // MARK: - Comment chip / shot note / context button positioning (SPEC §1.4)

    /// Port of `PositionChip` (`OverlayEditorWindow.xaml.cs:459-470`). Returns the chip's
    /// top-left in the same coordinate space as `cropRect`/`work` (the editing window's local,
    /// top-left-origin, Y-down point space — see `ScreenGeometry.flipToTopLeft`).
    static func positionChip(displayBounds bounds: CGRect, cropRect: CGRect, work: CGRect, chipWidth: CGFloat = 226) -> CGPoint {
        var x = cropRect.minX + bounds.minX
        var y = cropRect.minY + bounds.maxY + 8
        if y + 86 > work.maxY { y = cropRect.minY + bounds.minY - 50 }
        x = clamp(x, work.minX + 8, max(work.minX + 8, work.maxX - chipWidth - 4))
        y = clamp(y, work.minY + 8, max(work.minY + 8, work.maxY - 88))
        return CGPoint(x: x, y: y)
    }

    /// Port of `PositionShotNote` (`:472-479`).
    static func positionShotNote(cropRect: CGRect, work: CGRect, width: CGFloat = 250) -> CGPoint {
        let left = clamp(cropRect.maxX - width, work.minX + 8, max(work.minX + 8, work.maxX - width - 8))
        let top = clamp(cropRect.minY, work.minY + 8, max(work.minY + 8, work.maxY - 132))
        return CGPoint(x: left, y: top)
    }

    /// Port of `UpdateContextNoteAffordance` positioning (`:533-563`). `annotationBounds` is the
    /// selected annotation's display bounds, or `nil` when there is no selection (whole-capture
    /// comment button).
    static func positionContextNoteButton(annotationBounds: CGRect?, cropRect: CGRect, work: CGRect) -> CGPoint {
        var x: CGFloat
        var y: CGFloat
        if let bounds = annotationBounds {
            x = cropRect.minX + bounds.maxX + 8
            y = cropRect.minY + bounds.minY - 4
            if x + 36 > work.maxX { x = cropRect.minX + bounds.minX - 40 }
        } else {
            x = cropRect.maxX - 40
            y = cropRect.minY + 8
        }
        x = clamp(x, work.minX + 8, max(work.minX + 8, work.maxX - 40))
        y = clamp(y, work.minY + 8, max(work.minY + 8, work.maxY - 40))
        return CGPoint(x: x, y: y)
    }

    // MARK: - Toolbar positioning (SPEC §6.2 `PositionToolbar`)

    /// Port of `PositionToolbar` (`:481-511`). `obstacles` are the currently-visible comment
    /// chip / shot-note-chip rects (same coordinate space). Returns the toolbar's top-left.
    static func positionToolbar(cropRect: CGRect, work: CGRect, toolbarSize rawSize: CGSize, obstacles: [CGRect]) -> CGPoint {
        let width = max(rawSize.width, 380)
        let height = max(rawSize.height, 50)
        let left = clamp(
            cropRect.minX + (cropRect.width - width) / 2,
            work.minX + 8, max(work.minX + 8, work.maxX - width - 8))

        var top = cropRect.maxY - height - 10
        if cropRect.height < height + 20 { top = cropRect.maxY + 10 }
        if top + height > work.maxY - 8 { top = cropRect.minY - height - 10 }
        top = clamp(top, work.minY + 8, max(work.minY + 8, work.maxY - height - 8))

        let toolbarRect = CGRect(x: left, y: top, width: width, height: height)
        if obstacles.contains(where: { $0.intersects(toolbarRect) }) {
            let alternateTop = clamp(cropRect.minY + 10, work.minY + 8, max(work.minY + 8, work.maxY - height - 8))
            let alternate = CGRect(x: left, y: alternateTop, width: width, height: height)
            if !obstacles.contains(where: { $0.intersects(alternate) }) {
                top = alternateTop
            }
        }
        return CGPoint(x: left, y: top)
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
