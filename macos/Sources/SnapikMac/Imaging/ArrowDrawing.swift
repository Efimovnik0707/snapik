// Port of `src/Snapik.App/Imaging/ArrowDrawing.cs`, SPEC-DELTA-2.md §1.2, SPEC-DELTA-2B.md §C1.
// Single renderer shared by the on-screen editor canvas (`AnnotationCanvasView+Drawing.swift`),
// the shared `AnnotationPainter` (export + Cmd+S save), and the arrow-style menu's sample icons
// (`OverlayEditorController+Editing.swift`'s `showArrowStyleMenu()`).
import AppKit
import CoreGraphics

public enum ArrowDrawing {
    /// `style` is `AnnotationItem.arrowStyle` (`"straight"`/`"curved"`/`"bold"`/`"wide"`); any
    /// other value is treated as `"straight"`. `ctx` is assumed to already be in the caller's
    /// target coordinate space (screen point space for the live canvas, pixel space for export).
    public static func draw(in ctx: CGContext, from start: CGPoint, to end: CGPoint, color: CGColor, thickness: CGFloat, style: String) {
        let vector = CGPoint(x: end.x - start.x, y: end.y - start.y)
        let length = (vector.x * vector.x + vector.y * vector.y).squareRoot()
        guard length >= 0.01 else { return }

        let bold = style == "bold"
        let wide = style == "wide"
        let curved = style == "curved"
        let lineWidth = thickness * (bold ? 2 : 1)

        // Tip direction: the vector the arrowhead points "back" along from `end`. Straight ->
        // `start - end`; curved -> `control - end` (SPEC-DELTA-2.md §1.2 "Направление наконечника
        // от control − end").
        var tipDirection = CGPoint(x: start.x - end.x, y: start.y - end.y)

        ctx.saveGState()
        ctx.setStrokeColor(color)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.beginPath()
        ctx.move(to: start)
        if curved {
            let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
            let control = CGPoint(x: mid.x - vector.y * 0.25, y: mid.y + vector.x * 0.25)
            ctx.addQuadCurve(to: end, control: control)
            tipDirection = CGPoint(x: control.x - end.x, y: control.y - end.y)
        } else {
            ctx.addLine(to: end)
        }
        ctx.strokePath()
        ctx.restoreGState()

        let dirLength = (tipDirection.x * tipDirection.x + tipDirection.y * tipDirection.y).squareRoot()
        guard dirLength > 0 else { return }
        let direction = CGPoint(x: tipDirection.x / dirLength, y: tipDirection.y / dirLength)
        let side = CGPoint(x: -direction.y, y: direction.x)
        let size = min(length * 0.7, max(10, lineWidth * 3.2))
        let halfWidth = size * (wide ? 0.85 : 0.45)
        let p1 = CGPoint(x: end.x + direction.x * size + side.x * halfWidth, y: end.y + direction.y * size + side.y * halfWidth)
        let p2 = CGPoint(x: end.x + direction.x * size - side.x * halfWidth, y: end.y + direction.y * size - side.y * halfWidth)

        ctx.saveGState()
        ctx.setFillColor(color)
        ctx.beginPath()
        ctx.move(to: end)
        ctx.addLine(to: p1)
        ctx.addLine(to: p2)
        ctx.closePath()
        ctx.fillPath()
        ctx.restoreGState()
    }

    /// Port of the arrow-style menu's per-item sample (`OverlayEditorWindow.Arrows.cs:16-19`):
    /// a white `(4,24) -> (60,8)` arrow, thickness 2, drawn into a `size`-sized image.
    /// CHECK-API: `NSImage(size:flipped:drawingHandler:)`'s handler is `(NSRect) -> Bool`.
    public static func sampleImage(style: String, size: NSSize = NSSize(width: 64, height: 28)) -> NSImage {
        NSImage(size: size, flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            draw(in: ctx, from: CGPoint(x: 4, y: 24), to: CGPoint(x: 60, y: 8), color: NSColor.white.cgColor, thickness: 2, style: style)
            return true
        }
    }
}
