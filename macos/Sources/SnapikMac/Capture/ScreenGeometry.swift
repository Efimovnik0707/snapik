// Port of the Windows/macOS coordinate bridge, SPEC §9.5.
import AppKit
import CoreGraphics

/// The single explicit coordinate-transform layer SPEC §9.5 calls for: AppKit's Y-up,
/// bottom-left-origin, points-based screen space on one side, and `DesktopFrame`'s Y-down,
/// top-left-origin, pixel-based frame space (matching the Windows `DesktopFrame` this whole port
/// is measured against) on the other. Every other formula in SPEC §1/§2/§6 is written against the
/// frame side and is unaffected by which macOS/AppKit convention this file bridges from.
public enum ScreenGeometry {
    /// Union of every `NSScreen.frame`, in points, Y-up (AppKit's native convention).
    public static var globalPointsRect: CGRect {
        NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
    }

    /// `flip(p) = (p.x - globalRect.minX, globalRect.maxY - p.y)`: an AppKit screen point (Y-up,
    /// origin at the main screen's bottom-left) to the frame's Y-down, top-left-origin point
    /// space, still measured in points.
    public static func flipToTopLeft(_ p: CGPoint) -> CGPoint {
        let rect = globalPointsRect
        return CGPoint(x: p.x - rect.minX, y: rect.maxY - p.y)
    }

    /// `pixels(p) = flip(p) * scale`: an AppKit screen point straight to `frame`'s pixel space.
    public static func framePixels(fromScreenPoint p: CGPoint, frame: DesktopFrame) -> CGPoint {
        let flipped = flipToTopLeft(p)
        return CGPoint(x: flipped.x * frame.scale, y: flipped.y * frame.scale)
    }

    /// Inverse of `framePixels(fromScreenPoint:frame:)`: frame pixel coordinates back to an
    /// AppKit Y-up screen point, for positioning `NSWindow`s over the frozen frame.
    public static func screenPoint(fromFramePixels p: CGPoint, frame: DesktopFrame) -> CGPoint {
        let rect = globalPointsRect
        let pointsX = p.x / frame.scale
        let pointsY = p.y / frame.scale
        return CGPoint(x: pointsX + rect.minX, y: rect.maxY - pointsY)
    }
}
