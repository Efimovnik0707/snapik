// Port of `App/WpfExportImageRenderer.cs:82-142` (`DrawAnnotation`) and
// `App/Controls/AnnotationCanvas.cs:270-289,328-415` (`RenderAnnotated`/`DrawAnnotation`),
// SPEC §4.5, §4.6, §6.3.
import AppKit
import CoreGraphics
import SnapBriefCore

/// Shared options for `AnnotationPainter.draw`.
///
/// The `labelStyle` field is an addition on top of the `CONTRACTS.md` sketch
/// (`showLabels`/`labelFor`/`sourceImage` only): SPEC §4.5 (export PNG) and §4.6 (screen
/// save / `RenderAnnotated`) use two different label-circle formulas and font sizes, and both
/// call through this same painter, so a style selector is needed to keep them byte-for-byte
/// faithful to their respective source methods. Defaults to `.screen` (§4.6).
public struct AnnotationPaintOptions {
    /// Draw circular labels for annotations `labelFor` returns text for (SPEC §4.1: only
    /// annotations with a non-empty note get a label). When `false`, phase 3 (labels) is skipped
    /// entirely — shapes are still drawn.
    public var showLabels: Bool
    public var labelFor: (AnnotationItem) -> String?
    /// When set, `draw` first applies every `Blur` annotation's region (SPEC §2.8 radius formula)
    /// onto this image via `RegionBlur.blur` and draws the result to fill `imageSize`, before any
    /// annotation shapes — i.e. this single call reproduces "draw the image with all blur applied,
    /// then shapes, then labels" (§4.5 steps 2-6 and §4.6's `RenderAnnotated`) in one place, so
    /// screen and export rendering can never drift apart. When `nil`, the caller is responsible
    /// for having already drawn the base image into `ctx`.
    public var sourceImage: CGImage?
    public var labelStyle: LabelStyle

    public init(
        showLabels: Bool,
        labelFor: @escaping (AnnotationItem) -> String?,
        sourceImage: CGImage? = nil,
        labelStyle: LabelStyle = .screen
    ) {
        self.showLabels = showLabels
        self.labelFor = labelFor
        self.sourceImage = sourceImage
        self.labelStyle = labelStyle
    }

    public enum LabelStyle {
        /// SPEC §4.6 (`AnnotationCanvas.cs:393-402`): diameter `max(26, len*7+12)`, font 11
        /// SemiBold, circle center `anchor.y - diameter/2 - 3`.
        case screen
        /// SPEC §4.5 (`WpfExportImageRenderer.cs:132-141`): diameter `max(34, len*9+16)`, font 13
        /// Bold, circle center `max(diameter/2+2, anchor.y - diameter/2 - 4)`.
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

        // Phase 1: every shape except Blur (pixels only, no outline) and Redaction (must sit on
        // top of everything else it might cover).
        for annotation in annotations where annotation.kind != .blur && annotation.kind != .redaction {
            drawShape(annotation, imageSize: imageSize, in: ctx)
        }
        // Phase 2: Redaction shapes, on top of phase 1.
        for annotation in annotations where annotation.kind == .redaction {
            drawShape(annotation, imageSize: imageSize, in: ctx)
        }
        // Phase 3: labels only, on top of every shape.
        guard options.showLabels else { return }
        for annotation in annotations {
            guard let label = options.labelFor(annotation), !label.isEmpty else { continue }
            drawLabel(label, for: annotation, imageSize: imageSize, in: ctx, style: options.labelStyle)
        }
    }

    // MARK: - Blur application (SPEC §4.5 `ApplyBlurAnnotations`)

    private static func applyBlurAnnotations(_ annotations: [AnnotationItem], to source: CGImage) -> CGImage {
        var result = source
        let width = CGFloat(source.width)
        let height = CGFloat(source.height)
        for item in annotations where item.kind == .blur && item.points.count > 1 {
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
            // Always within `1...512`, so the non-throwing `RegionBlur.blur` never needs to fall
            // back to clamping here.
            let radius = min(max(Int((item.thickness * 3).rounded()), 4), 36)
            result = RegionBlur.blur(result, region: region, radius: radius)
        }
        return result
    }

    // MARK: - Shape drawing (SPEC §4.5 `DrawAnnotation` / §4.6 `AnnotationCanvas.DrawAnnotation`)

    private static func mapPoint(_ p: NormalizedPoint, imageSize: CGSize) -> CGPoint {
        CGPoint(x: CGFloat(p.x) * imageSize.width, y: CGFloat(p.y) * imageSize.height)
    }

    private static func drawShape(_ item: AnnotationItem, imageSize: CGSize, in ctx: CGContext) {
        guard !item.points.isEmpty else { return }
        let color = cgColor(fromAARRGGBB: item.strokeColor)
        let thickness = CGFloat(item.thickness)

        switch item.kind {
        case .freehand, .highlight:
            let lineColor = item.kind == .highlight ? (color.copy(alpha: 90.0 / 255.0) ?? color) : color
            let lineWidth = item.kind == .highlight ? thickness * 4 : thickness
            ctx.saveGState()
            ctx.setStrokeColor(lineColor)
            ctx.setLineWidth(lineWidth)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            for segment in item.getPathSegments() where segment.count > 1 {
                ctx.beginPath()
                ctx.move(to: mapPoint(segment[0], imageSize: imageSize))
                for p in segment.dropFirst() {
                    ctx.addLine(to: mapPoint(p, imageSize: imageSize))
                }
                ctx.strokePath()
            }
            ctx.restoreGState()

        case .rectangle, .redaction, .text, .arrow:
            guard item.points.count > 1 else { return }
            let start = mapPoint(item.points[0], imageSize: imageSize)
            let end = mapPoint(item.points[1], imageSize: imageSize)
            let rect = CGRect(
                x: min(start.x, end.x), y: min(start.y, end.y),
                width: abs(end.x - start.x), height: abs(end.y - start.y))

            switch item.kind {
            case .rectangle:
                ctx.saveGState()
                ctx.setStrokeColor(color)
                ctx.setLineWidth(thickness)
                ctx.setLineCap(.round)
                ctx.setLineJoin(.round)
                ctx.stroke(rect)
                ctx.restoreGState()

            case .redaction:
                // Always solid black, regardless of `item.strokeColor` (matches the C# renderers,
                // which both hard-code `Brushes.Black` here).
                ctx.saveGState()
                ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
                ctx.fill(rect)
                ctx.restoreGState()

            case .text:
                let fontSize = max(16, thickness * 4.5)
                drawText(item.text, fontSize: fontSize, weight: .semibold, color: color, in: ctx, topLeft: start)

            case .arrow:
                // Port of `WpfExportImageRenderer.cs:110-112` (SPEC-DELTA-2.md §1.2, §1.9): the
                // shared `ArrowDrawing` renderer, keyed by `item.arrowStyle`.
                ArrowDrawing.draw(in: ctx, from: start, to: end, color: color, thickness: thickness, style: item.arrowStyle)

            default:
                break
            }

        default:
            break
        }
    }

    // MARK: - Labels (circular number badges)

    private static func drawLabel(
        _ label: String, for item: AnnotationItem, imageSize: CGSize, in ctx: CGContext, style: AnnotationPaintOptions.LabelStyle
    ) {
        guard let first = item.points.first else { return }
        let anchor = mapPoint(first, imageSize: imageSize)
        let diameter: CGFloat
        let fontSize: CGFloat
        let weight: NSFont.Weight
        let centerY: CGFloat
        switch style {
        case .screen:
            diameter = max(26, CGFloat(label.count) * 7 + 12)
            fontSize = 11
            weight = .semibold
            centerY = anchor.y - diameter / 2 - 3
        case .export:
            diameter = max(34, CGFloat(label.count) * 9 + 16)
            fontSize = 13
            weight = .bold
            centerY = max(diameter / 2 + 2, anchor.y - diameter / 2 - 4)
        }
        let center = CGPoint(x: anchor.x, y: centerY)

        ctx.saveGState()
        ctx.setFillColor(CGColor(red: 47.0 / 255.0, green: 140.0 / 255.0, blue: 255.0 / 255.0, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter))
        ctx.restoreGState()

        drawText(
            label, fontSize: fontSize, weight: weight,
            color: CGColor(red: 1, green: 1, blue: 1, alpha: 1), in: ctx, centeredAt: center)
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

    // MARK: - Color

    /// Parses SPEC §2.3's `#AARRGGBB` format. Falls back to opaque black on malformed input
    /// (should not happen for annotations created through the editor).
    static func cgColor(fromAARRGGBB hex: String) -> CGColor {
        var value = hex
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 8, let intValue = UInt32(value, radix: 16) else {
            return CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        }
        let a = CGFloat((intValue >> 24) & 0xFF) / 255
        let r = CGFloat((intValue >> 16) & 0xFF) / 255
        let g = CGFloat((intValue >> 8) & 0xFF) / 255
        let b = CGFloat(intValue & 0xFF) / 255
        return CGColor(red: r, green: g, blue: b, alpha: a)
    }
}
