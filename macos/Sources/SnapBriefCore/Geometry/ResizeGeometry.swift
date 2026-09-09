// Port of `src/SnapBrief.App/Controls/ResizeGeometry.cs`, SPEC §2.9.
import Foundation

/// Port of WPF's `Point`. Foundation-only (no CoreGraphics), so this compiles cross-platform
/// alongside the rest of `SnapBriefCore`.
public struct GeometryPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }
}

/// Port of WPF's `Rect` (`Left`/`Top`/`Right`/`Bottom` derived from `X`/`Y`/`Width`/`Height`).
public struct GeometryRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(_ x: Double, _ y: Double, _ width: Double, _ height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// Port of the WPF `Rect(Point, Point)` constructor: normalizes two arbitrary corners into
    /// a positive-size rectangle.
    public init(_ pointA: GeometryPoint, _ pointB: GeometryPoint) {
        self.x = min(pointA.x, pointB.x)
        self.y = min(pointA.y, pointB.y)
        self.width = abs(pointB.x - pointA.x)
        self.height = abs(pointB.y - pointA.y)
    }

    public var left: Double { x }
    public var top: Double { y }
    public var right: Double { x + width }
    public var bottom: Double { y + height }

    public var topLeft: GeometryPoint { GeometryPoint(left, top) }
    public var topRight: GeometryPoint { GeometryPoint(right, top) }
    public var bottomRight: GeometryPoint { GeometryPoint(right, bottom) }
    public var bottomLeft: GeometryPoint { GeometryPoint(left, bottom) }
}

/// Port of `src/SnapBrief.App/Controls/ResizeGeometry.cs`: shared math for corner-drag resize
/// handles, used both for annotation bounds and for the capture's own crop handles (SPEC §1.6,
/// §2.9, §6.3).
public enum ResizeGeometry {
    /// Port of `Corners`: clockwise starting at top-left (top-left, top-right, bottom-right,
    /// bottom-left).
    public static func corners(_ bounds: GeometryRect) -> [GeometryPoint] {
        [bounds.topLeft, bounds.topRight, bounds.bottomRight, bounds.bottomLeft]
    }

    /// Port of `HitCorner`: index of the first corner (checked clockwise from index 0) within
    /// `radius` of `point`, or `-1` if none match.
    public static func hitCorner(bounds: GeometryRect, point: GeometryPoint, radius: Double) -> Int {
        let corners = corners(bounds)
        for index in corners.indices {
            let dx = corners[index].x - point.x
            let dy = corners[index].y - point.y
            if (dx * dx + dy * dy).squareRoot() <= radius {
                return index
            }
        }
        return -1
    }

    /// Port of `Resize`: drags `corner` of `original` to `point`, keeping the opposite corner
    /// fixed, clamped to `limit` and never inverting below `minimum` (shrunk to `original`'s own
    /// size first, if it is already smaller than `minimum`).
    public static func resize(
        original: GeometryRect,
        corner: Int,
        point: GeometryPoint,
        limit: GeometryRect,
        minimum: Double
    ) -> GeometryRect {
        let minimumX = min(minimum, original.width)
        let minimumY = min(minimum, original.height)
        var left = original.left
        var top = original.top
        var right = original.right
        var bottom = original.bottom

        if corner == 0 || corner == 3 {
            left = min(max(point.x, limit.left), right - minimumX)
        } else {
            right = min(max(point.x, left + minimumX), limit.right)
        }
        if corner == 0 || corner == 1 {
            top = min(max(point.y, limit.top), bottom - minimumY)
        } else {
            bottom = min(max(point.y, top + minimumY), limit.bottom)
        }
        return GeometryRect(GeometryPoint(left, top), GeometryPoint(right, bottom))
    }

    /// Port of `Map`: proportionally carries `point` (measured against `original`) into the
    /// `resized` rectangle. The divisor is guarded against zero exactly like the C# `Math.Max(1, ...)`.
    public static func map(_ point: GeometryPoint, original: GeometryRect, resized: GeometryRect) -> GeometryPoint {
        GeometryPoint(
            resized.left + (point.x - original.left) * resized.width / max(1, original.width),
            resized.top + (point.y - original.top) * resized.height / max(1, original.height))
    }
}
