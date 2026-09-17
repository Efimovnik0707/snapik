// Port of `src/Snapik.App/Imaging/NoteBadgeGeometry.cs`, SPEC-DELTA-3 §1.4 E-20,
// SPEC-DELTA-5-editor.md §1.1 W0-3, §1.3 E-9.
import CoreGraphics
import Foundation
import SnapikCore

/// The room the exported picture needs around itself, in its own pixels.
public struct ExportMargin: Equatable {
    public let left: Int
    public let top: Int
    public let right: Int
    public let bottom: Int

    public static let none = ExportMargin(left: 0, top: 0, right: 0, bottom: 0)

    public init(left: Int, top: Int, right: Int, bottom: Int) {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
    }

    public var isEmpty: Bool { left == 0 && top == 0 && right == 0 && bottom == 0 }
}

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
        create(anchor: anchor, diameter: exportDiameter(label), offset: offset, gap: exportGap, topMargin: topMargin)
    }

    /// How much larger the exported badge is than the one on screen, never below 1. One number for
    /// everything that has to grow with the badge: the leader, the dot of a comment and its rim.
    public static func exportScale(_ label: String) -> CGFloat {
        max(1, exportDiameter(label) / screenDiameter(label))
    }

    /// The leader of an exported badge, in pixels: the badge itself is drawn larger than the one on
    /// screen, so the line grows with it instead of thinning out to a thread, and never below 1 px.
    public static func exportLeaderThickness(_ label: String) -> CGFloat { exportScale(label) }

    /// The air between the point of a mark and the rim of its badge in the export.
    private static let exportGap: CGFloat = 4

    /// The room kept between a badge and the edge of the field it was given.
    private static let padding: CGFloat = 8

    /// The dot a comment is pinned by, on screen and, scaled by `exportScale`, in the export. It
    /// lives here and not in the canvas because the leader has to start on its rim in both drawers,
    /// and they would drift apart on two copies of the number.
    public static let anchorRadius: CGFloat = 5

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

    /// The field around the capture that the badges need. Counted in the pixels of the capture,
    /// without the header of the export: a picture whose badges all stand inside it comes out byte
    /// for byte as before. A badge that was never dragged counts too — it is drawn above the point
    /// it belongs to, and a comment near the top edge hangs over the capture without any dragging.
    /// The centre is the one `create` gives: the same lift of half a diameter and the gap, or the
    /// field would be measured from a circle nobody draws.
    public static func exportMargins(
        badges: [(anchor: NormalizedPoint, offset: NormalizedPoint?, label: String)], width: Int, height: Int
    ) -> ExportMargin {
        var left: CGFloat = 0, top: CGFloat = 0, right: CGFloat = 0, bottom: CGFloat = 0
        for badge in badges {
            // A comment without a number has no badge to fit in.
            if badge.label.isEmpty { continue }
            let shift = badge.offset ?? NormalizedPoint(0, 0)
            let diameter = exportDiameter(badge.label)
            let radius = diameter / 2 + padding
            let centerX = CGFloat(badge.anchor.x + shift.x) * CGFloat(width)
            let centerY = CGFloat(badge.anchor.y + shift.y) * CGFloat(height) - diameter / 2 - exportGap
            left = max(left, radius - centerX)
            top = max(top, radius - centerY)
            right = max(right, centerX + radius - CGFloat(width))
            bottom = max(bottom, centerY + radius - CGFloat(height))
        }
        return ExportMargin(
            left: ceiling(left), top: ceiling(top), right: ceiling(right), bottom: ceiling(bottom))
    }

    private static func ceiling(_ value: CGFloat) -> Int {
        value <= 0 ? 0 : Int(value.rounded(.up))
    }

    /// The thin leader between the mark and a badge the user moved away from it: it starts on the
    /// outline of the mark and stops on the rim of the badge, so neither is covered by the line.
    /// `nil` when the badge still sits on its mark and there is nothing to draw.
    ///
    /// A comment has no outline to start from — its mark is the dot itself, so it passes the radius
    /// of that dot as `fromRadius` and a degenerate rectangle as the bounds: the line then begins on
    /// the rim of the dot instead of in its middle. Zero keeps the old picture.
    public static func leader(bounds: CGRect, badge: NoteBadge, fromRadius: CGFloat = 0) -> (from: CGPoint, to: CGPoint)? {
        var from = CGPoint(
            x: min(max(badge.center.x, bounds.minX), bounds.maxX),
            y: min(max(badge.center.y, bounds.minY), bounds.maxY))
        var direction = CGPoint(x: badge.center.x - from.x, y: badge.center.y - from.y)
        let length = (direction.x * direction.x + direction.y * direction.y).squareRoot()
        guard length > badge.radius + fromRadius + 1 else { return nil }
        direction = CGPoint(x: direction.x / length, y: direction.y / length)
        from = CGPoint(x: from.x + direction.x * fromRadius, y: from.y + direction.y * fromRadius)
        return (from, CGPoint(x: badge.center.x - direction.x * badge.radius, y: badge.center.y - direction.y * badge.radius))
    }
}
