// Port of `src/Snapik.App/Imaging/StrokePattern.cs`, SPEC-DELTA-3 §1.4 E-2.
import CoreGraphics
import SnapikCore

/// The pattern of a stroke, in one place for both renderers. The dashes are measured in thicknesses
/// of the pen and not in pixels, so one pattern gives the same stroke on the screen, where the
/// thickness is multiplied by the scale of the view, and in the exported PNG, where it is the
/// thickness in the pixels of the capture. WPF's `DashStyle` counts in pen widths by itself;
/// `CGContext.setLineDash` counts in user-space units, so the multiplication happens here and
/// nowhere else.
public enum StrokePattern {
    /// Which marks have a stroke to pattern: the frame and the oval (one kind with two shapes), the
    /// arrow and the pencil. A highlighter would fall apart into blots, and a caption, a blur and a
    /// comment have no stroke at all, so they are drawn solid whatever their mark carries.
    public static func participates(_ kind: AnnotationKind) -> Bool {
        kind == .rectangle || kind == .arrow || kind == .freehand
    }

    public static func of(_ kind: AnnotationKind, _ style: AnnotationLineStyle) -> AnnotationLineStyle {
        participates(kind) ? style : .solid
    }

    /// The dash pattern in pen widths: three to two for a dash, and a gap of two with round ends for
    /// a dot, which is a dash of no length at all. `nil` is a solid stroke.
    public static func dashes(_ style: AnnotationLineStyle) -> [CGFloat]? {
        switch style {
        case .dashed: return [3, 2]
        case .dotted: return [0, 2]
        case .solid: return nil
        }
    }

    /// Arms `ctx` with the pattern of `style` at `thickness`. A dotted stroke needs round caps, or a
    /// dash of no length at all draws nothing; a dashed one needs butt caps, or the gaps close up.
    /// Leaves the cap alone for a solid stroke: the caller already picked one.
    public static func apply(_ style: AnnotationLineStyle, thickness: CGFloat, to ctx: CGContext) {
        guard let pattern = dashes(style) else {
            ctx.setLineDash(phase: 0, lengths: [])
            return
        }
        ctx.setLineCap(style == .dotted ? .round : .butt)
        ctx.setLineDash(phase: 0, lengths: pattern.map { $0 * max(thickness, 0.01) })
    }
}
