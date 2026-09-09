// Mini-parser for the WPF `Path.Data` mini-language strings quoted verbatim in SPEC §6.2/§6.3
// (only M/L/C/Z commands are used anywhere in the icon table), so every icon path below can be
// copy-pasted straight out of the spec instead of hand-transcribed into move/line calls.
import AppKit

enum IconPath {
    /// Builds an `NSBezierPath` from a WPF-style path data string such as
    /// `"M2,3 L14,3 L14,13 L2,13 Z"`. The command letter is glued to the first coordinate pair
    /// that follows it; later bare `"x,y"` tokens repeat the last command (matches every icon
    /// string in SPEC §6.2's toolbar table and §1.4's chip/comment icons).
    static func path(_ data: String) -> NSBezierPath {
        let bezier = NSBezierPath()
        var currentCommand: Character = "M"
        var pendingCubicPoints: [CGPoint] = []

        for rawToken in data.split(whereSeparator: { $0 == " " || $0 == "\n" }) {
            var body = String(rawToken)
            if let first = body.first, "MLCZ".contains(first) {
                currentCommand = first
                body.removeFirst()
            }

            if currentCommand == "Z" {
                bezier.close()
                continue
            }

            guard !body.isEmpty else { continue }
            let parts = body.split(separator: ",").compactMap { Double($0) }
            guard parts.count == 2 else { continue }
            let point = CGPoint(x: parts[0], y: parts[1])

            switch currentCommand {
            case "M":
                bezier.move(to: point)
            case "L":
                bezier.line(to: point)
            case "C":
                pendingCubicPoints.append(point)
                if pendingCubicPoints.count == 3 {
                    bezier.curve(to: pendingCubicPoints[2], controlPoint1: pendingCubicPoints[0], controlPoint2: pendingCubicPoints[1])
                    pendingCubicPoints.removeAll(keepingCapacity: true)
                }
            default:
                break
            }
        }
        return bezier
    }

    /// Draws `path` (defined in its own `nativeSize x nativeSize` coordinate box, per the
    /// `Path Width="16" Height="16"` etc. attributes in SPEC §6.2) centered inside `rect`.
    /// `lineWidth` is in the path's own native coordinate space (e.g. `StrokeThickness="1.7"`
    /// against a 16-unit box) and is scaled along with the geometry by the CTM, matching how WPF
    /// renders a `Path` inside a layout-transformed container.
    static func draw(_ data: String, in rect: CGRect, nativeSize: CGFloat, stroke: NSColor, lineWidth: CGFloat, fill: NSColor? = nil) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let bezier = path(data)
        bezier.lineWidth = lineWidth
        bezier.lineCapStyle = .round
        bezier.lineJoinStyle = .round

        ctx.saveGState()
        let scale = min(rect.width, rect.height) / nativeSize
        ctx.translateBy(x: rect.minX + (rect.width - nativeSize * scale) / 2, y: rect.minY + (rect.height - nativeSize * scale) / 2)
        ctx.scaleBy(x: scale, y: scale)

        if let fill {
            fill.setFill()
            bezier.fill()
        }
        stroke.setStroke()
        bezier.stroke()
        ctx.restoreGState()
    }
}
