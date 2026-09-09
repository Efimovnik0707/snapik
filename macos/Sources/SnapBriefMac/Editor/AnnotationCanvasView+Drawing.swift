// Port of `AnnotationCanvas.OnRender`/`DrawAnnotation`/`RenderAnnotated`, SPEC §1.7, §6.3.
//
// On-screen rendering here is implemented directly against the exact per-pixel formulas in
// SPEC §6.3 (colors, thickness floor, arrow geometry, label sizing, draw-pass ordering — in
// particular "подписи-номера всегда поверх форм") rather than by delegating to the shared
// `AnnotationPainter.draw` from `Sources/SnapBriefMac/Imaging` (which did not exist yet at the
// time this file was written, and whose exact per-annotation draw-call ordering is not knowable
// in advance — delegating risks the label/conceal z-order the spec explicitly calls out as
// important). `renderFinalImage()` (used only for the Cmd+S save path, SPEC §1.13) *does* call
// `AnnotationPainter.draw`, matching CONTRACTS.md's "рендер на экране и в экспорте совпадал"
// intent for anything that leaves the app as a file. Live blur (SPEC §1.7) always goes through
// the real `RegionBlur.blur` (Imaging).
import AppKit
import SnapBriefCore

extension AnnotationCanvasView {
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let capture else { return }
        recomputeImageRect()

        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(imageRect)

        let displayImage = applyBlurAnnotations(capture.image)
        NSImage(cgImage: displayImage, size: imageRect.size).draw(in: imageRect)

        for annotation in capture.annotations where annotation.kind != .blur && annotation.kind != .conceal {
            drawAnnotation(ctx, annotation, target: imageRect, includeSelection: false, drawLabel: false)
        }
        for annotation in capture.annotations where annotation.kind == .conceal {
            drawAnnotation(ctx, annotation, target: imageRect, includeSelection: false, drawLabel: false)
        }
        for annotation in capture.annotations {
            drawAnnotation(ctx, annotation, target: imageRect, includeSelection: true, drawShape: false)
        }

        if isManipulatingBlur, let selected = selectedAnnotation {
            let bounds = displayBounds(of: selected)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fill(bounds)
            ctx.setStrokeColor(EditorTheme.accent.cgColor)
            ctx.setLineWidth(1.5)
            ctx.stroke(bounds)
        }

        if let draft {
            drawAnnotation(ctx, draft, target: imageRect)
        }
    }

    /// Port of `DrawAnnotation` (`AnnotationCanvas.cs:328-415`).
    func drawAnnotation(
        _ ctx: CGContext, _ item: EditorAnnotation, target: CGRect,
        includeSelection: Bool = true, drawShape: Bool = true, drawLabel: Bool = true
    ) {
        guard let capture, !item.points.isEmpty else { return }
        let imageWidth = CGFloat(capture.image.width)
        let imageHeight = CGFloat(capture.image.height)
        func map(_ p: CGPoint) -> CGPoint {
            CGPoint(x: target.minX + p.x * target.width / imageWidth, y: target.minY + p.y * target.height / imageHeight)
        }
        let scale = target.width / imageWidth
        let thickness = max(1.5, item.thickness * scale)
        let color = item.color

        if drawShape, item.kind == .pen || item.kind == .highlight {
            let isHighlight = item.kind == .highlight
            let strokeColor = color.withAlphaComponent(isHighlight ? 0.35 : 1)
            ctx.setStrokeColor(strokeColor.cgColor)
            ctx.setLineWidth(isHighlight ? thickness * 4 : thickness)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            for segment in [item.points] + item.additionalPathSegments where segment.count > 1 {
                ctx.beginPath()
                ctx.move(to: map(segment[0]))
                for point in segment.dropFirst() { ctx.addLine(to: map(point)) }
                ctx.strokePath()
            }
        } else if drawShape, item.points.count > 1 {
            let start = map(item.points[0])
            let end = map(item.points[1])
            let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
            switch item.kind {
            case .rectangle:
                ctx.setStrokeColor(color.cgColor)
                ctx.setLineWidth(thickness)
                ctx.stroke(rect)
            case .conceal:
                ctx.setFillColor(NSColor.black.cgColor)
                ctx.fill(rect)
            case .blur:
                ctx.setFillColor(EditorTheme.blurPreviewFill.cgColor)
                ctx.fill(rect)
                ctx.setStrokeColor(EditorTheme.accent.cgColor)
                ctx.setLineWidth(1.5)
                ctx.stroke(rect)
            case .crop:
                ctx.setFillColor(EditorTheme.cropPreviewFill.cgColor)
                ctx.fill(rect)
                ctx.setStrokeColor(EditorTheme.accent.cgColor)
                ctx.setLineWidth(1.5)
                ctx.setLineDash(phase: 0, lengths: [4, 3])
                ctx.stroke(rect)
                ctx.setLineDash(phase: 0, lengths: [])
            case .text:
                let fontSize = max(14, 18 * scale)
                let attributes: [NSAttributedString.Key: Any] = [.font: EditorTheme.systemFont(fontSize), .foregroundColor: color]
                NSAttributedString(string: item.text, attributes: attributes).draw(at: start)
            case .arrow:
                ctx.setStrokeColor(color.cgColor)
                ctx.setLineWidth(thickness)
                ctx.setLineCap(.round)
                ctx.setLineJoin(.round)
                ctx.beginPath()
                ctx.move(to: start)
                ctx.addLine(to: end)
                ctx.strokePath()
                drawArrowHead(ctx, from: start, to: end, thickness: thickness, color: color)
            case .select, .pen, .highlight:
                break
            }
        }

        if drawLabel, !item.label.isEmpty {
            drawLabelBadge(ctx, label: item.label, at: map(item.points[0]))
        }

        if includeSelection, item === selectedAnnotation {
            drawSelectionOutline(ctx, item: item, map: map)
        }
    }

    private func drawArrowHead(_ ctx: CGContext, from start: CGPoint, to end: CGPoint, thickness: CGFloat, color: NSColor) {
        var vector = CGPoint(x: start.x - end.x, y: start.y - end.y)
        let length = (vector.x * vector.x + vector.y * vector.y).squareRoot()
        guard length > 0 else { return }
        vector = CGPoint(x: vector.x / length, y: vector.y / length)
        let side = CGPoint(x: -vector.y, y: vector.x)
        let size = max(10, thickness * 3.2)
        let p1 = CGPoint(x: end.x + vector.x * size + side.x * size * 0.45, y: end.y + vector.y * size + side.y * size * 0.45)
        let p2 = CGPoint(x: end.x + vector.x * size - side.x * size * 0.45, y: end.y + vector.y * size - side.y * size * 0.45)
        ctx.setFillColor(color.cgColor)
        ctx.beginPath()
        ctx.move(to: end)
        ctx.addLine(to: p1)
        ctx.addLine(to: p2)
        ctx.closePath()
        ctx.fillPath()
    }

    /// Port of the label-badge drawing at the end of `DrawAnnotation` (`:393-402`).
    private func drawLabelBadge(_ ctx: CGContext, label: String, at anchor: CGPoint) {
        let diameter = max(26, CGFloat(label.count * 7 + 12))
        let center = CGPoint(x: anchor.x, y: anchor.y - diameter / 2 - 3)
        ctx.setFillColor(EditorTheme.accent.cgColor)
        ctx.fillEllipse(in: CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter))
        let attributes: [NSAttributedString.Key: Any] = [.font: EditorTheme.systemFont(11, weight: .semibold), .foregroundColor: NSColor.white]
        let text = NSAttributedString(string: label, attributes: attributes)
        let size = text.size()
        text.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))
    }

    /// Port of the dashed selection rectangle + 4 corner handles (`:404-414`).
    private func drawSelectionOutline(_ ctx: CGContext, item: EditorAnnotation, map: (CGPoint) -> CGPoint) {
        let bounds = EditorGeometry.boundsOf(points: item.points, additionalSegments: item.additionalPathSegments)
        let topLeft = map(CGPoint(x: bounds.minX, y: bounds.minY))
        let bottomRight = map(CGPoint(x: bounds.maxX, y: bounds.maxY))
        let selectedRect = CGRect(
            x: min(topLeft.x, bottomRight.x), y: min(topLeft.y, bottomRight.y),
            width: abs(bottomRight.x - topLeft.x), height: abs(bottomRight.y - topLeft.y))

        ctx.setStrokeColor(EditorTheme.selectionOutline.cgColor)
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [4, 2])
        ctx.stroke(selectedRect)
        ctx.setLineDash(phase: 0, lengths: [])

        for corner in EditorGeometry.corners(selectedRect) {
            let handleRect = CGRect(x: corner.x - 4, y: corner.y - 4, width: 8, height: 8)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(handleRect)
            ctx.setStrokeColor(EditorTheme.handleBorder.cgColor)
            ctx.setLineWidth(1.5)
            ctx.stroke(handleRect)
        }
    }

    // MARK: - Blur compositing (SPEC §1.7)

    var isManipulatingBlur: Bool {
        manipulating && selectedAnnotation?.kind == .blur
    }

    /// Port of `ApplyBlurAnnotations` (`:441-461`): sequentially applies `RegionBlur.blur` for
    /// every Blur annotation, cached by a hash of the source image identity plus each blur
    /// annotation's id/thickness/points. While the selected Blur annotation is actively being
    /// moved/resized, the previous cached raster is reused unconditionally (SPEC §1.7: "Во время
    /// манипуляции используется прежний raster-кэш").
    func applyBlurAnnotations(_ source: CGImage) -> CGImage {
        guard let capture else { return source }
        let blurAnnotations = capture.annotations.filter { $0.kind == .blur && $0.points.count > 1 }
        guard !blurAnnotations.isEmpty else {
            blurCache = nil
            blurCacheKey = nil
            return source
        }

        if isManipulatingBlur, let cache = blurCache {
            return cache
        }

        // CHECK-API: relies on `CGImage` being usable with `ObjectIdentifier` (true for the
        // Swift CoreGraphics overlay's toll-free-bridged `CGImage` class on Apple platforms).
        var hasher = Hasher()
        hasher.combine(ObjectIdentifier(source))
        for annotation in blurAnnotations {
            hasher.combine(annotation.id)
            hasher.combine(annotation.thickness)
            for point in annotation.points {
                hasher.combine(point.x)
                hasher.combine(point.y)
            }
        }
        let key = hasher.finalize()
        if let cache = blurCache, blurCacheKey == key { return cache }

        var result = source
        for annotation in blurAnnotations {
            let bounds = EditorGeometry.boundsOf(points: annotation.points, additionalSegments: annotation.additionalPathSegments)
            let region = pixelRect(from: bounds, width: source.width, height: source.height)
            guard region.width > 0, region.height > 0 else { continue }
            result = RegionBlur.blur(result, region: region, radius: EditorGeometry.blurRadius(thickness: annotation.thickness))
        }
        blurCacheKey = key
        blurCache = result
        return result
    }

    private func pixelRect(from bounds: CGRect, width: Int, height: Int) -> CGRect {
        let left = EditorGeometry.clampInt(Int(bounds.minX.rounded(.down)), 0, width)
        let top = EditorGeometry.clampInt(Int(bounds.minY.rounded(.down)), 0, height)
        let right = EditorGeometry.clampInt(Int(bounds.maxX.rounded(.up)), left, width)
        let bottom = EditorGeometry.clampInt(Int(bounds.maxY.rounded(.up)), top, height)
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    // MARK: - Cmd+S final render (SPEC §1.13)

    /// Port of `AnnotationCanvas.RenderAnnotated()` (`:270-289`), used only by the Cmd+S save
    /// path. Renders at full source-image pixel resolution via the shared `AnnotationPainter`
    /// (Imaging), matching CONTRACTS.md's "рендер на экране и в экспорте совпадал" for files that
    /// leave the app. CHECK-API: `AnnotationPaintOptions`'s memberwise-init argument order/labels
    /// and `AnnotationPainter.draw`'s exact per-annotation rendering (thickness, label placement)
    /// are assumed to match `CONTRACTS.md`'s declared signature; that file did not exist yet at
    /// the time this was written.
    func renderFinalImage() -> CGImage? {
        guard let capture else { return nil }
        let width = capture.image.width
        let height = capture.image.height
        let colorSpace = capture.image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard
            let ctx = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        ctx.draw(capture.image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let coreAnnotations = capture.annotations.map { $0.toCore(imageWidth: width, imageHeight: height) }
        let labeled = CaptureLabels.forNotedAnnotations(captureLabel: capture.displayLabel, capture: capture.toCore())
        let labelById = Dictionary(uniqueKeysWithValues: labeled.map { ($0.annotation.id, $0.displayLabel) })
        let options = AnnotationPaintOptions(
            showLabels: true,
            labelFor: { annotation in labelById[annotation.id] },
            sourceImage: capture.image)
        AnnotationPainter.draw(coreAnnotations, imageSize: CGSize(width: width, height: height), in: ctx, options: options)

        return ctx.makeImage()
    }
}
