// Port of `App/WpfExportImageRenderer.cs:82-142` (`DrawAnnotation`) and
// `App/Controls/AnnotationCanvas.cs:270-289,328-415` (`RenderAnnotated`/`DrawAnnotation`),
// SPEC §4.5, §4.6, §6.3, SPEC-DELTA-3 §1.4 E-1, E-2, E-20.
import AppKit
import CoreGraphics
import SnapikCore

/// Shared options for `AnnotationPainter.draw`.
///
/// The `labelStyle` field is an addition on top of the `CONTRACTS.md` sketch
/// (`showLabels`/`labelFor`/`sourceImage` only): SPEC §4.5 (export PNG) and §4.6 (screen
/// save / `RenderAnnotated`) use two different label-circle sizes and font sizes, and both
/// call through this same painter, so a style selector is needed to keep them faithful to their
/// respective source methods. Defaults to `.screen` (§4.6).
public struct AnnotationPaintOptions {
    /// Draw circular labels for annotations `labelFor` returns text for (SPEC §4.1: only
    /// annotations with a non-empty note get a label). When `false`, phase 3 (labels) is skipped
    /// entirely — shapes are still drawn.
    public var showLabels: Bool
    public var labelFor: (AnnotationItem) -> String?
    /// When set, `draw` first applies every blurred annotation's region (SPEC-DELTA-3 §1.4 E-1
    /// radius formula) onto this image via `RegionBlur.blur` and draws the result to fill
    /// `imageSize`, before any annotation shapes — i.e. this single call reproduces "draw the image
    /// with all blur applied, then shapes, then labels" (§4.5 steps 2-6 and §4.6's
    /// `RenderAnnotated`) in one place, so screen and export rendering can never drift apart. When
    /// `nil`, the caller is responsible for having already drawn the base image into `ctx`.
    public var sourceImage: CGImage?
    public var labelStyle: LabelStyle
    /// The first row a badge may touch, in this painter's own coordinate space: the export draws a
    /// white header the badge has to stay under (`NoteBadgeGeometry.Export`'s `topMargin`).
    public var labelTopMargin: CGFloat

    public init(
        showLabels: Bool,
        labelFor: @escaping (AnnotationItem) -> String?,
        sourceImage: CGImage? = nil,
        labelStyle: LabelStyle = .screen,
        labelTopMargin: CGFloat = -CGFloat.greatestFiniteMagnitude
    ) {
        self.showLabels = showLabels
        self.labelFor = labelFor
        self.sourceImage = sourceImage
        self.labelStyle = labelStyle
        self.labelTopMargin = labelTopMargin
    }

    public enum LabelStyle {
        /// SPEC §4.6 (`AnnotationCanvas.cs:393-402`): diameter `max(26, len*7+12)`, font 11
        /// SemiBold, gap 3.
        case screen
        /// SPEC §4.5 (`WpfExportImageRenderer.cs:132-141`): diameter `max(34, len*9+16)`, font 13
        /// Bold, gap 4.
        case export
    }
}

/// Single shared drawer for every `AnnotationKind`, used both for the export PNG (SPEC §4.5) and
/// the plain screen-save render (SPEC §4.6, `AnnotationCanvas.RenderAnnotated`) so the two stay
/// pixel-consistent by construction. Assumes `ctx` is already set up so `(0,0)` is the top-left
/// of `imageSize` and Y grows downward (the same convention normalized points already use), e.g.
/// via `NSGraphicsContext(cgContext:flipped:true)` or an equivalent manual CTM flip.
public enum AnnotationPainter {
    public static func draw(
        _ annotations: [AnnotationItem],
        imageSize: CGSize,
        in ctx: CGContext,
        options: AnnotationPaintOptions
    ) {
        if let source = options.sourceImage {
            let composed = applyBlurAnnotations(annotations, to: source)
            // `ctx` is Y-flipped (top-left origin) per this painter's contract; `draw(_:in:)`
            // honours the CTM and would mirror the bitmap vertically. Unflip locally for the blit.
            ctx.saveGState()
            ctx.translateBy(x: 0, y: imageSize.height)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(composed, in: CGRect(origin: .zero, size: imageSize))
            ctx.restoreGState()
        }

        // Phase 1: every shape except a blurred one (its pixels are baked above) and an opaque
        // fill, which hides whatever stands under it and is therefore drawn last of the shapes.
        for annotation in annotations where !isBlurred(annotation) && !hasOpaqueFill(annotation) {
            drawShape(annotation, imageSize: imageSize, in: ctx)
        }
        // Phase 2: the opaque fills, on top of phase 1.
        for annotation in annotations where hasOpaqueFill(annotation) {
            drawShape(annotation, imageSize: imageSize, in: ctx)
        }
        // Phase 3: labels only, on top of every shape.
        guard options.showLabels else { return }
        for annotation in annotations {
            guard let label = options.labelFor(annotation), !label.isEmpty else { continue }
            drawLabel(
                label, for: annotation, imageSize: imageSize, in: ctx,
                style: options.labelStyle, topMargin: options.labelTopMargin)
        }
    }

    // MARK: - What is blurred and what covers (SPEC-DELTA-3 §1.4 E-1, E-14)

    /// Port of `AnnotationCanvas.IsBlurred`: the blur tool and a region filled with blur bake the
    /// same pixels into the picture, so one rule decides what is blurred and every caller asks it.
    public static func isBlurred(_ item: AnnotationItem) -> Bool {
        item.kind == .blur || (item.kind == .rectangle && item.fill == .blur)
    }

    /// Port of `AnnotationCanvas.HasOpaqueFill`: an opaque fill is drawn after every other mark,
    /// because it hides whatever stands under it — that is what the conceal tool used to do, and a
    /// solid region does the same. A legacy `redaction` mark counts too.
    public static func hasOpaqueFill(_ item: AnnotationItem) -> Bool {
        (item.kind == .rectangle && item.fill == .solid) || item.kind == .redaction
    }

    // MARK: - Blur application (SPEC §4.5 `ApplyBlurAnnotations`)

    private static func applyBlurAnnotations(_ annotations: [AnnotationItem], to source: CGImage) -> CGImage {
        var result = source
        let width = CGFloat(source.width)
        let height = CGFloat(source.height)
        for item in annotations where isBlurred(item) && item.points.count > 1 {
            let p0x = CGFloat(item.points[0].x)
            let p0y = CGFloat(item.points[0].y)
            let p1x = CGFloat(item.points[1].x)
            let p1y = CGFloat(item.points[1].y)
            let left = min(max(floor(min(p0x, p1x) * width), 0), width)
            let top = min(max(floor(min(p0y, p1y) * height), 0), height)
            let right = min(max(ceil(max(p0x, p1x) * width), left), width)
            let bottom = min(max(ceil(max(p0y, p1y) * height), top), height)
            guard right > left, bottom > top else { continue }
            let region = CGRect(x: left, y: top, width: right - left, height: bottom - top)
            // The strength comes from the size of the region and no longer from the thickness of a
            // stroke a blur does not even draw (SPEC-DELTA-3 §1.4 E-1).
            let radius = RegionBlur.radiusFor(width: Double(region.width), height: Double(region.height))
            result = RegionBlur.blur(result, region: region, radius: radius, shape: item.shape)
        }
        return result
    }

    // MARK: - Shape drawing (SPEC §4.5 `DrawAnnotation` / §4.6 `AnnotationCanvas.DrawAnnotation`)

    private static func mapPoint(_ p: NormalizedPoint, imageSize: CGSize) -> CGPoint {
        CGPoint(x: CGFloat(p.x) * imageSize.width, y: CGFloat(p.y) * imageSize.height)
    }

    private static func drawShape(_ item: AnnotationItem, imageSize: CGSize, in ctx: CGContext) {
        guard !item.points.isEmpty else { return }
        let color = NSColor(argbHex: item.strokeColor)
        let thickness = CGFloat(item.thickness)
        let lineStyle = StrokePattern.of(item.kind, item.lineStyle)

        switch item.kind {
        case .freehand, .highlight:
            let segments = item.getPathSegments().map { $0.map { mapPoint($0, imageSize: imageSize) } }
            strokePath(
                segments, in: ctx, color: color, thickness: thickness,
                lineStyle: lineStyle, highlight: item.kind == .highlight)

        case .rectangle, .redaction, .text, .arrow:
            guard item.points.count > 1 else { return }
            let start = mapPoint(item.points[0], imageSize: imageSize)
            let end = mapPoint(item.points[1], imageSize: imageSize)
            let rect = CGRect(
                x: min(start.x, end.x), y: min(start.y, end.y),
                width: abs(end.x - start.x), height: abs(end.y - start.y))

            switch item.kind {
            case .rectangle:
                let fillColor = EditorAppearance.parseFillColor(item.fillColor) ?? color
                drawBoxShape(
                    in: ctx, shape: item.shape, rect: rect, scale: 1,
                    fill: EditorAppearance.fillColor(fillColor, fill: item.fill),
                    outline: AnnotationRules.outlineColorOf(fill: item.fill, color: color),
                    thickness: thickness, lineStyle: lineStyle)

            case .redaction:
                // A mark of a build that still had the conceal tool: a solid black box, whatever
                // `strokeColor` it carries (SPEC-DELTA-3 §2.1).
                ctx.saveGState()
                ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
                ctx.fill(rect)
                ctx.restoreGState()

            case .text:
                // The size the caption was typed in, in the pixels of the capture: the letters in
                // the PNG are the letters on screen (SPEC-DELTA-3 §2.1).
                drawText(
                    item.text, fontSize: CGFloat(TextMarkMetrics.clamp(item.fontSize)), weight: .regular,
                    color: color.cgColor, in: ctx, topLeft: start)

            case .arrow:
                ArrowDrawing.draw(
                    in: ctx, from: start, to: end, color: color.cgColor, thickness: thickness,
                    style: item.arrowStyle, lineStyle: lineStyle)

            default:
                break
            }

        default:
            break
        }
    }

    /// Port of `AnnotationCanvas.DrawBoxShape` (`:721-738`): the outline follows the shape, what
    /// stands inside it follows the fill, and both renderers draw the same three shapes from the
    /// same numbers. `scale` is points-per-image-pixel, so a rounded corner keeps its size.
    public static func drawBoxShape(
        in ctx: CGContext, shape: AnnotationShape, rect: CGRect, scale: CGFloat,
        fill: NSColor?, outline: NSColor?, thickness: CGFloat, lineStyle: AnnotationLineStyle
    ) {
        let path = ShapeMask.path(shape, rect: rect, scale: scale)
        ctx.saveGState()
        if let fill {
            ctx.addPath(path)
            ctx.setFillColor(fill.cgColor)
            ctx.fillPath()
        }
        if let outline {
            ctx.setLineWidth(thickness)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            StrokePattern.apply(lineStyle, thickness: thickness, to: ctx)
            ctx.setStrokeColor(outline.cgColor)
            ctx.addPath(path)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    /// Port of `StrokeGeometry` + `DrawHighlightStroke` (`:678-704`): a stroke is one geometry and
    /// not a line per pair of points, and a highlighter is that one geometry laid down once under a
    /// single transparency, with square ends — transparent ink laid segment by segment piles up at
    /// every joint.
    public static func strokePath(
        _ segments: [[CGPoint]], in ctx: CGContext, color: NSColor, thickness: CGFloat,
        lineStyle: AnnotationLineStyle, highlight: Bool
    ) {
        let drawable = segments.filter { $0.count > 1 }
        guard !drawable.isEmpty else { return }
        ctx.saveGState()
        if highlight {
            ctx.setAlpha(EditorAppearance.highlightOpacity)
            ctx.setLineCap(.square)
            ctx.setLineJoin(.bevel)
        } else {
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            StrokePattern.apply(lineStyle, thickness: thickness, to: ctx)
        }
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(thickness)
        ctx.beginPath()
        for segment in drawable {
            ctx.move(to: segment[0])
            for point in segment.dropFirst() { ctx.addLine(to: point) }
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - Labels (circular number badges, SPEC-DELTA-3 §1.4 E-20)

    /// The circle of one noted mark in the coordinate space `imageSize` is given in.
    public static func badge(
        for item: AnnotationItem, label: String, imageSize: CGSize,
        style: AnnotationPaintOptions.LabelStyle, topMargin: CGFloat
    ) -> NoteBadge? {
        guard let first = item.points.first else { return nil }
        let anchor = mapPoint(first, imageSize: imageSize)
        let offset = item.noteOffset.map { CGPoint(x: CGFloat($0.x) * imageSize.width, y: CGFloat($0.y) * imageSize.height) } ?? .zero
        switch style {
        case .screen: return NoteBadgeGeometry.screen(anchor: anchor, label: label, offset: offset)
        case .export: return NoteBadgeGeometry.export(anchor: anchor, label: label, offset: offset, topMargin: topMargin)
        }
    }

    private static func drawLabel(
        _ label: String, for item: AnnotationItem, imageSize: CGSize, in ctx: CGContext,
        style: AnnotationPaintOptions.LabelStyle, topMargin: CGFloat
    ) {
        guard let badge = badge(for: item, label: label, imageSize: imageSize, style: style, topMargin: topMargin) else { return }
        let accent = AccentPalette.flat

        // A badge dragged away from its mark keeps one hair line back to it.
        if item.noteOffset != nil {
            let all = item.getPathSegments().flatMap { $0 } + item.points
            if let minX = all.map(\.x).min(), let minY = all.map(\.y).min(),
                let maxX = all.map(\.x).max(), let maxY = all.map(\.y).max()
            {
                let outline = CGRect(
                    x: CGFloat(minX) * imageSize.width, y: CGFloat(minY) * imageSize.height,
                    width: CGFloat(maxX - minX) * imageSize.width, height: CGFloat(maxY - minY) * imageSize.height)
                if let leader = NoteBadgeGeometry.leader(bounds: outline, badge: badge) {
                    ctx.saveGState()
                    ctx.setStrokeColor(accent.cgColor)
                    ctx.setLineWidth(style == .export ? NoteBadgeGeometry.exportLeaderThickness(label) : 1)
                    ctx.setLineDash(phase: 0, lengths: [])
                    ctx.beginPath()
                    ctx.move(to: leader.from)
                    ctx.addLine(to: leader.to)
                    ctx.strokePath()
                    ctx.restoreGState()
                }
            }
        }

        ctx.saveGState()
        ctx.setFillColor(accent.cgColor)
        ctx.fillEllipse(
            in: CGRect(
                x: badge.center.x - badge.radius, y: badge.center.y - badge.radius,
                width: badge.radius * 2, height: badge.radius * 2))
        ctx.restoreGState()

        drawText(
            label, fontSize: style == .export ? 13 : 11, weight: style == .export ? .bold : .semibold,
            color: CGColor(red: 1, green: 1, blue: 1, alpha: 1), in: ctx, centeredAt: badge.center)
    }

    // MARK: - Text (SPEC: use `NSFont.systemFont` + `NSAttributedString.draw` in a flipped context)

    /// Draws `text` either anchored at `topLeft` (its bounding box's top-left corner, matching
    /// WPF's `DrawText(formatted, point)`) or centered at `centeredAt`. Relies on `ctx` already
    /// being a top-left/Y-down context (see the type doc comment); `NSGraphicsContext(cgContext:
    /// flipped: true)` tells AppKit's text drawing to treat `ctx` that way regardless of its own
    /// CTM, so this stays correct however the caller set `ctx` up.
    static func drawText(
        _ text: String,
        fontSize: CGFloat,
        weight: NSFont.Weight,
        color: CGColor,
        in ctx: CGContext,
        topLeft: CGPoint = .zero,
        centeredAt: CGPoint? = nil
    ) {
        guard !text.isEmpty else { return }
        let font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        let nsColor = NSColor(cgColor: color) ?? .white
        let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: nsColor])

        let origin: CGPoint
        if let centeredAt {
            let size = attributed.size()
            origin = CGPoint(x: centeredAt.x - size.width / 2, y: centeredAt.y - size.height / 2)
        } else {
            origin = topLeft
        }

        let graphicsContext = NSGraphicsContext(cgContext: ctx, flipped: true)
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = graphicsContext
        attributed.draw(at: origin)
        NSGraphicsContext.current = previous
    }
}
