// Port of `src/Snapik.App/Imaging/NoteBadgeGeometry.cs`, SPEC-DELTA-3 §1.4 E-20.
import CoreGraphics
import Foundation

/// The circle with the number of a noted mark: where its middle is and how far its rim reaches.
public struct NoteBadge: Equatable {
    public let center: CGPoint
    public let radius: CGFloat

    public init(center: CGPoint, radius: CGFloat) {
        self.center = center
        self.radius = radius
    }

    public func contains(_ point: CGPoint, slack: CGFloat = 0) -> Bool {
        let dx = point.x - center.x
        let dy = point.y - center.y
        return (dx * dx + dy * dy).squareRoot() <= radius + slack
    }
}

/// One place for the circle with the number of a noted mark. The editor canvas draws it, hit-tests
/// it and places the note pill over it; the export renderer draws the same circle in image pixels.
/// Both must agree, otherwise a note the user dragged would sit elsewhere in the exported PNG.
public enum NoteBadgeGeometry {
    public static func screen(anchor: CGPoint, label: String, offset: CGPoint) -> NoteBadge {
        create(anchor: anchor, diameter: screenDiameter(label), offset: offset, gap: 3, topMargin: -.greatestFiniteMagnitude)
    }

    /// The same circle in the pixels of the exported picture. `topMargin` is the first row the badge
    /// may touch: the export draws a white header the badge must stay under.
    public static func export(anchor: CGPoint, label: String, offset: CGPoint, topMargin: CGFloat) -> NoteBadge {
        create(anchor: anchor, diameter: exportDiameter(label), offset: offset, gap: 4, topMargin: topMargin)
    }

    /// The leader of an exported badge, in pixels: the badge itself is drawn larger than the one on
    /// screen, so the line grows with it instead of thinning out to a thread, and never below 1 px.
    public static func exportLeaderThickness(_ label: String) -> CGFloat {
        max(1, exportDiameter(label) / screenDiameter(label))
    }

    public static func screenDiameter(_ label: String) -> CGFloat {
        max(26, CGFloat(label.count) * 7 + 12)
    }

    public static func exportDiameter(_ label: String) -> CGFloat {
        max(34, CGFloat(label.count) * 9 + 16)
    }

    private static func create(anchor: CGPoint, diameter: CGFloat, offset: CGPoint, gap: CGFloat, topMargin: CGFloat) -> NoteBadge {
        let center = CGPoint(
            x: anchor.x + offset.x,
            y: max(topMargin + diameter / 2, anchor.y + offset.y - diameter / 2 - gap))
        return NoteBadge(center: center, radius: diameter / 2)
    }

    /// The thin leader between the mark and a badge the user moved away from it: it starts on the
    /// outline of the mark and stops on the rim of the badge, so neither is covered by the line.
    /// `nil` when the badge still sits on its mark and there is nothing to draw.
    public static func leader(bounds: CGRect, badge: NoteBadge) -> (from: CGPoint, to: CGPoint)? {
        let from = CGPoint(
            x: min(max(badge.center.x, bounds.minX), bounds.maxX),
            y: min(max(badge.center.y, bounds.minY), bounds.maxY))
        var direction = CGPoint(x: badge.center.x - from.x, y: badge.center.y - from.y)
        let length = (direction.x * direction.x + direction.y * direction.y).squareRoot()
        guard length > badge.radius + 1 else { return nil }
        direction = CGPoint(x: direction.x / length, y: direction.y / length)
        return (from, CGPoint(x: badge.center.x - direction.x * badge.radius, y: badge.center.y - direction.y * badge.radius))
    }
}
