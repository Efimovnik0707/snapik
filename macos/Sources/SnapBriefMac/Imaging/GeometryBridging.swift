// Bridges Core's Foundation-only `GeometryRect`/`GeometryPoint` (SPEC §2.9,
// `Sources/SnapBriefCore/Geometry/ResizeGeometry.swift`) to the CoreGraphics types used
// throughout the AppKit editor, plus CG-typed overloads of `ResizeGeometry` with the same
// semantic argument labels.
import CoreGraphics
import SnapBriefCore

extension GeometryRect {
    init(_ rect: CGRect) {
        self.init(Double(rect.origin.x), Double(rect.origin.y), Double(rect.size.width), Double(rect.size.height))
    }

    var cgRect: CGRect {
        CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height))
    }
}

extension GeometryPoint {
    init(_ point: CGPoint) {
        self.init(Double(point.x), Double(point.y))
    }

    var cgPoint: CGPoint {
        CGPoint(x: CGFloat(x), y: CGFloat(y))
    }
}

extension ResizeGeometry {
    static func resize(
        original: CGRect,
        corner: Int,
        point: CGPoint,
        limit: CGRect,
        minimum: CGFloat
    ) -> CGRect {
        resize(
            original: GeometryRect(original), corner: corner, point: GeometryPoint(point),
            limit: GeometryRect(limit), minimum: Double(minimum)
        ).cgRect
    }

    static func map(_ point: CGPoint, original: CGRect, resized: CGRect) -> CGPoint {
        map(GeometryPoint(point), original: GeometryRect(original), resized: GeometryRect(resized)).cgPoint
    }

    static func hitCorner(bounds: CGRect, point: CGPoint, radius: CGFloat) -> Int {
        hitCorner(bounds: GeometryRect(bounds), point: GeometryPoint(point), radius: Double(radius))
    }
}
