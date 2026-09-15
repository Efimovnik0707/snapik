// Port of `src/Snapik.App/Imaging/ShapeMask.cs`, SPEC-DELTA-3 §1.4 E-1.
import CoreGraphics
import Foundation
import SnapikCore

/// How much of one pixel a frame covers inside its bounding box, from 0 (outside) to 1 (inside).
/// The blur of a region is mixed with the untouched picture by this number, so an oval blur is an
/// oval on screen and in the exported PNG: both renderers ask the same code.
public enum ShapeMask {
    /// The corner of a rounded frame never grows past this, in image pixels.
    public static let maximumCornerRadius: Double = 14

    /// The radius the outline of a rounded frame is drawn with, in image pixels.
    public static func cornerRadius(width: Double, height: Double) -> Double {
        min(maximumCornerRadius, min(width, height) / 4)
    }

    /// The coverage of the pixel at column `x` and row `y` of a box `width` by `height` pixels. The
    /// edge is smoothed over one pixel by the signed distance to the shape, so an oval does not come
    /// out jagged.
    public static func coverage(_ shape: AnnotationShape, width: Double, height: Double, x: Double, y: Double) -> Double {
        guard width > 0, height > 0 else { return 0 }
        if shape == .rectangle { return 1 }
        let centerX = x + 0.5 - width / 2
        let centerY = y + 0.5 - height / 2
        let distance =
            shape == .ellipse
            ? ellipseDistance(centerX, centerY, radiusX: width / 2, radiusY: height / 2)
            : roundedDistance(
                centerX, centerY, halfWidth: width / 2, halfHeight: height / 2,
                radius: cornerRadius(width: width, height: height))
        return min(max(0.5 - distance, 0), 1)
    }

    // The distance to an ellipse has no short exact form; this is the standard first-order estimate
    // of it, exact enough within the one pixel the edge is smoothed over.
    private static func ellipseDistance(_ x: Double, _ y: Double, radiusX: Double, radiusY: Double) -> Double {
        guard radiusX > 0, radiusY > 0 else { return .infinity }
        let normalized = x * x / (radiusX * radiusX) + y * y / (radiusY * radiusY)
        let gradient = 2 * (x * x / (radiusX * radiusX * radiusX * radiusX) + y * y / (radiusY * radiusY * radiusY * radiusY)).squareRoot()
        // The centre of the ellipse: no gradient to follow, and nothing near the edge either.
        return gradient <= .ulpOfOne ? -min(radiusX, radiusY) : (normalized - 1) / gradient
    }

    private static func roundedDistance(_ x: Double, _ y: Double, halfWidth: Double, halfHeight: Double, radius: Double) -> Double {
        let cornerX = abs(x) - (halfWidth - radius)
        let cornerY = abs(y) - (halfHeight - radius)
        let outside = (max(cornerX, 0) * max(cornerX, 0) + max(cornerY, 0) * max(cornerY, 0)).squareRoot()
        return outside + min(max(cornerX, cornerY), 0) - radius
    }

    /// The outline of one boxed mark, in whatever coordinate space `rect` is given in. `scale` is
    /// the ratio between that space and the pixels of the capture, so a rounded corner on screen and
    /// the same corner in the exported PNG are the same corner (`AnnotationCanvas.DrawBoxShape`).
    public static func path(_ shape: AnnotationShape, rect: CGRect, scale: CGFloat) -> CGPath {
        switch shape {
        case .ellipse:
            return CGPath(ellipseIn: rect, transform: nil)
        case .rounded:
            let radius = min(CGFloat(maximumCornerRadius) * scale, min(rect.width, rect.height) / 4)
            return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        case .rectangle:
            return CGPath(rect: rect, transform: nil)
        }
    }
}
