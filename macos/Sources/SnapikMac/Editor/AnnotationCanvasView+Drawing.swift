// Port of `AnnotationCanvas.OnRender`/`DrawAnnotation`/`RenderAnnotated`, SPEC §1.7, §6.3,
// SPEC-DELTA-3 §1.4 E-1, E-2, E-4, E-6, E-14, E-20.
//
// On-screen rendering maps every mark into the view's own point space and then hands the actual
// geometry to the shared `Imaging` helpers (`AnnotationPainter.drawBoxShape`/`strokePath`,
// `ShapeMask`, `StrokePattern`, `ArrowDrawing`, `NoteBadgeGeometry`), so the canvas and the export
// renderer draw the same shapes from the same numbers at two scales — the rule of SPEC-DELTA-3
// §1.4 E-1 ("оба рендерера берут маску из одного места"). What stays here is only what belongs to
// the screen: the draft being drawn, the selection frame, the eraser outline, the anchor of a
// leader, and the blur placeholder shown while a blurred region is dragged.
import AppKit
import SnapikCore

@MainActor
extension AnnotationCanvasView {
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let capture else { return }
        recomputeImageRect()

        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(imageRect)

        let displayImage = applyBlurAnnotations(capture.image)
        // At its own size the picture must show its own pixels: with smoothing on, the seam between
        // two monitors is spread over two of them (`AnnotationCanvas.cs:83-85`). `NSImage.draw(in:)`
        // reads the interpolation off the context and blits upright in a flipped view — a plain
        // `CGContext.draw` would need the anti-flip of `macos/README.md` around it.
        let interpolation = NSGraphicsContext.current?.imageInterpolation
        NSGraphicsContext.current?.imageInterpolation = viewScale == nil ? .default : .none
        NSImage(cgImage: displayImage, size: imageRect.size).draw(in: imageRect)
        if let interpolation { NSGraphicsContext.current?.imageInterpolation = interpolation }

        for annotation in capture.annotations where !Self.isBlurred(annotation) && !Self.hasOpaqueFill(annotation) {
            drawAnnotation(ctx, annotation, target: imageRect, includeSelection: false, drawLabel: false)
        }
        for annotation in capture.annotations where Self.hasOpaqueFill(annotation) {
            drawAnnotation(ctx, annotation, target: imageRect, includeSelection: false, drawLabel: false)
        }
        for annotation in capture.annotations {
            drawAnnotation(ctx, annotation, target: imageRect, includeSelection: true, drawShape: false)
        }

        // The mark the eraser is about to take is outlined in red, so a click is never a surprise
        // (SPEC-DELTA-3 §1.4 E-5).
        if let erasing = eraseHover, capture.annotations.contains(where: { $0 === erasing }) {
            ctx.saveGState()
            ctx.setLineDash(phase: 0, lengths: [])
            ctx.setStrokeColor(EditorTheme.eraseHoverOutline.cgColor)
            ctx.setLineWidth(1.5)
            ctx.stroke(displayBounds(of: erasing))
            ctx.restoreGState()
        }

        // While a blurred region travels, the frame under it is the cached one, so the region itself
        // is drawn as a cheap placeholder: the same for the blur tool and for a frame filled with
        // blur (SPEC-DELTA-3 §1.4 E-14).
        if manipulating, let selected = selectedAnnotation, Self.isBlurred(selected) {
            AnnotationPainter.drawBoxShape(
                in: ctx, shape: selected.shape, rect: displayBounds(of: selected),
                scale: imageRect.width / CGFloat(max(1, capture.image.width)),
                fill: .black, outline: EditorTheme.accent, thickness: 1.5, lineStyle: .solid)
        }

        if let draft {
            drawAnnotation(ctx, draft, target: imageRect)
        }
    }

    /// Port of `AnnotationCanvas.IsBlurred` for the editor's own model.
    static func isBlurred(_ item: EditorAnnotation) -> Bool {
        item.kind == .blur || (item.kind == .rectangle && item.fill == .blur)
    }

    /// Port of `AnnotationCanvas.HasOpaqueFill`: an opaque fill hides what stands under it, so it is
    /// drawn after every other shape — that is what the conceal tool used to do.
    static func hasOpaqueFill(_ item: EditorAnnotation) -> Bool {
        item.kind == .rectangle && item.fill == .solid
    }

    /// Port of `HasResizeHandles` (`AnnotationCanvas.cs:747`): a caption is not stretched by its
    /// corners — the box around it is the letters, and their size is set by the button on the panel.
    static func hasResizeHandles(_ item: EditorAnnotation) -> Bool {
        item.kind != .comment && item.kind != .text
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
        let lineStyle = StrokePattern.of(item.coreKind, item.lineStyle)

        if drawShape, item.kind == .pen || item.kind == .highlight {
            let segments = ([item.points] + item.additionalPathSegments).map { $0.map(map) }
            AnnotationPainter.strokePath(
                segments, in: ctx, color: color, thickness: thickness,
                lineStyle: lineStyle, highlight: item.kind == .highlight)
        } else if drawShape, item.points.count > 1 {
            let start = map(item.points[0])
            let end = map(item.points[1])
            let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
            switch item.kind {
            case .rectangle:
                let fillColor = item.fillColor ?? color
                AnnotationPainter.drawBoxShape(
                    in: ctx, shape: item.shape, rect: rect, scale: scale,
                    fill: EditorAppearance.fillColor(fillColor, fill: item.fill),
                    outline: EditorAppearance.outlineColor(fill: item.fill, color: color, fillColor: fillColor),
                    thickness: thickness, lineStyle: lineStyle)
            case .conceal:
                // Nothing draws this kind any more: the tool is gone and a legacy `redaction` mark is
                // read back as a rectangle with a solid black fill (SPEC-DELTA-3 §2.1).
                break
            case .blur:
                // The preview of a blur that is still being drawn shows the shape it will take.
                AnnotationPainter.drawBoxShape(
                    in: ctx, shape: item.shape, rect: rect, scale: scale,
                    fill: EditorTheme.blurPreviewFill, outline: EditorTheme.accent,
                    thickness: 1.5, lineStyle: .solid)
            case .crop:
                ctx.saveGState()
                ctx.setFillColor(AccentPalette.wash(alpha: 24.0 / 255.0).cgColor)
                ctx.fill(rect)
                ctx.setStrokeColor(EditorTheme.accent.cgColor)
                ctx.setLineWidth(1.5)
                ctx.setLineDash(phase: 0, lengths: [4, 3])
                ctx.stroke(rect)
                ctx.restoreGState()
            case .text:
                // The mark being typed is drawn by the text field standing over it, not here
                // (SPEC-DELTA-3 §1.4 E-6).
                guard editingTextId != item.id else { break }
                AnnotationPainter.drawText(
                    item.text, fontSize: CGFloat(TextMarkMetrics.clamp(item.fontSize)) * scale, weight: .regular,
                    color: color.cgColor, in: ctx, topLeft: start)
            case .arrow:
                ArrowDrawing.draw(
                    in: ctx, from: start, to: end, color: color.cgColor, thickness: thickness,
                    style: item.arrowStyle, lineStyle: lineStyle)
            case .comment:
                // SPEC-DELTA-2B.md §C1: the pin has no drawn shape of its own, only the badge below.
                break
            case .select, .pen, .highlight, .eraser:
                break
            }
        }

        if drawLabel, !item.label.isEmpty {
            drawLabelBadge(ctx, item: item, target: target, map: map, includeSelection: includeSelection)
        }

        // SPEC-DELTA-2B.md §C4/§C7: a comment pin and a caption never show a resize frame.
        if includeSelection, item === selectedAnnotation, Self.hasResizeHandles(item) {
            drawSelectionOutline(ctx, item: item, map: map)
        }
    }

    /// Port of the badge half of `DrawAnnotation` (`:393-412`): the circle, the leader back to the
    /// mark when the badge was dragged away, and — on screen only — the anchor that end of the
    /// leader is moved by.
    private func drawLabelBadge(
        _ ctx: CGContext, item: EditorAnnotation, target: CGRect,
        map: (CGPoint) -> CGPoint, includeSelection: Bool
    ) {
        let badge = badgeOf(item, target: target)
        let accent = EditorTheme.accent

        ctx.saveGState()
        ctx.setLineDash(phase: 0, lengths: [])
        if item.noteOffset != nil {
            let bounds = EditorGeometry.boundsOf(points: item.points, additionalSegments: item.additionalPathSegments)
            let topLeft = map(CGPoint(x: bounds.minX, y: bounds.minY))
            let bottomRight = map(CGPoint(x: bounds.maxX, y: bounds.maxY))
            let outline = CGRect(
                x: min(topLeft.x, bottomRight.x), y: min(topLeft.y, bottomRight.y),
                width: abs(bottomRight.x - topLeft.x), height: abs(bottomRight.y - topLeft.y))
            if let leader = NoteBadgeGeometry.leader(bounds: outline, badge: badge) {
                ctx.setStrokeColor(accent.cgColor)
                ctx.setLineWidth(1)
                ctx.beginPath()
                ctx.move(to: leader.from)
                ctx.addLine(to: leader.to)
                ctx.strokePath()
            }
        }

        ctx.setFillColor(accent.cgColor)
        ctx.fillEllipse(in: CGRect(x: badge.center.x - badge.radius, y: badge.center.y - badge.radius, width: badge.radius * 2, height: badge.radius * 2))

        // The anchor of the leader, on screen only: `includeSelection` is what separates the canvas
        // from the export, and a circle without a number explains nothing to whoever receives the
        // picture. While the note sits on its mark there is no leader, and the anchor would only
        // cover the number in the badge, so it is drawn for a note dragged away.
        if includeSelection, item.kind == .comment, item.noteOffset != nil {
            let anchor = map(item.points[0])
            let radius = anchorHoverId == item.id ? Self.anchorHoverRadius : Self.anchorRadius
            let circle = CGRect(x: anchor.x - radius, y: anchor.y - radius, width: radius * 2, height: radius * 2)
            ctx.setFillColor(accent.cgColor)
            ctx.fillEllipse(in: circle)
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(1.5)
            ctx.strokeEllipse(in: circle)
        }
        ctx.restoreGState()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: EditorTheme.systemFont(11, weight: .semibold), .foregroundColor: NSColor.white,
        ]
        let text = NSAttributedString(string: item.label, attributes: attributes)
        let size = text.size()
        text.draw(at: CGPoint(x: badge.center.x - size.width / 2, y: badge.center.y - size.height / 2))
    }

    /// Port of the dashed selection rectangle + 4 corner handles (`:404-414`).
    private func drawSelectionOutline(_ ctx: CGContext, item: EditorAnnotation, map: (CGPoint) -> CGPoint) {
        let bounds = EditorGeometry.boundsOf(points: item.points, additionalSegments: item.additionalPathSegments)
        let topLeft = map(CGPoint(x: bounds.minX, y: bounds.minY))
        let bottomRight = map(CGPoint(x: bounds.maxX, y: bounds.maxY))
        let selectedRect = CGRect(
            x: min(topLeft.x, bottomRight.x), y: min(topLeft.y, bottomRight.y),
            width: abs(bottomRight.x - topLeft.x), height: abs(bottomRight.y - topLeft.y))

        ctx.saveGState()
        ctx.setStrokeColor(EditorTheme.accent.cgColor)
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [4, 2])
        ctx.stroke(selectedRect)
        ctx.setLineDash(phase: 0, lengths: [])

        for corner in EditorGeometry.corners(selectedRect) {
            let handleRect = CGRect(x: corner.x - 4, y: corner.y - 4, width: 8, height: 8)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(handleRect)
            ctx.setStrokeColor(EditorTheme.accent.cgColor)
            ctx.setLineWidth(1.5)
            ctx.stroke(handleRect)
        }
        ctx.restoreGState()
    }

    // MARK: - Blur compositing (SPEC §1.7, SPEC-DELTA-3 §1.4 E-14)

    /// Port of `ApplyBlurAnnotations` (`:894-919`): sequentially applies `RegionBlur.blur` for every
    /// **blurred** annotation — the blur tool and a region filled with blur alike, which is what
    /// keeps a 4K capture usable while such a region is dragged: the cache is keyed by the same
    /// predicate, so moving a blur-filled rectangle reuses the previous raster instead of rebuilding
    /// the whole frame on every mouse move.
    func applyBlurAnnotations(_ source: CGImage) -> CGImage {
        guard let capture else { return source }
        let blurAnnotations = capture.annotations.filter { Self.isBlurred($0) && $0.points.count > 1 }
        guard !blurAnnotations.isEmpty else {
            blurCache = nil
            blurCacheKey = nil
            return source
        }

        if manipulating, let dragged = selectedAnnotation, Self.isBlurred(dragged), let cache = blurCache {
            return cache
        }

        // CHECK-API: relies on `CGImage` being usable with `ObjectIdentifier` (true for the
        // Swift CoreGraphics overlay's toll-free-bridged `CGImage` class on Apple platforms).
        var hasher = Hasher()
        hasher.combine(ObjectIdentifier(source))
        for annotation in blurAnnotations {
            hasher.combine(annotation.id)
            hasher.combine(annotation.shape)
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
            result = RegionBlur.blur(
                result, region: region,
                radius: RegionBlur.radiusFor(width: Double(region.width), height: Double(region.height)),
                shape: annotation.shape)
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
    /// leave the app.
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

        // `AnnotationPainter` expects a top-left-origin (Y-down) context and blits the source
        // image itself (`options.sourceImage`), so flip once here and do not draw the image twice.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)

        let coreAnnotations = capture.annotations.map { $0.toCore(imageWidth: width, imageHeight: height) }
        let labeled = CaptureLabels.forNotedAnnotations(captureLabel: capture.displayLabel, capture: capture.toCore())
        let labelById = Dictionary(uniqueKeysWithValues: labeled.map { ($0.annotation.id, $0.displayLabel) })
        let options = AnnotationPaintOptions(
            showLabels: true,
            labelFor: { annotation in labelById[annotation.id] },
            sourceImage: capture.image)
        AnnotationPainter.draw(coreAnnotations, imageSize: CGSize(width: CGFloat(width), height: CGFloat(height)), in: ctx, options: options)

        return ctx.makeImage()
    }
}
