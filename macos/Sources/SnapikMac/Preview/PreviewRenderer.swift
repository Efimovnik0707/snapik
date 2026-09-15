// Port of `CapturePreviewWindow.xaml.cs:76-84` (`RenderPreview`), SPEC-DELTA-2 §1.5,
// SPEC-DELTA-2B §D.
import CoreGraphics
import Foundation
import SnapikCore

enum PreviewRenderer {
    /// Renders `image` with every annotation (including blur) and its export-numbered label
    /// applied, exactly like `AnnotationCanvas { ImagePadding = 0 }.RenderAnnotated()`. Returns
    /// `nil` only if `capture`'s pixel size is degenerate or the backing `CGContext` could not be
    /// allocated.
    static func render(capture: CaptureItem, image: CGImage, displayLabel: String) -> CGImage? {
        let width = capture.pixelWidth
        let height = capture.pixelHeight
        guard width > 0, height > 0 else { return nil }
        guard
            let ctx = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        // `AnnotationPainter.draw` assumes `ctx` is already in the top-left-origin, Y-down
        // convention that normalized annotation points use (see its type doc comment); flip once
        // here for the whole draw call.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)

        let labeled = CaptureLabels.forNotedAnnotations(captureLabel: displayLabel, capture: capture)
        var labelsById: [SBGuid: String] = [:]
        for item in labeled { labelsById[item.annotation.id] = item.displayLabel }

        let options = AnnotationPaintOptions(
            showLabels: true,
            labelFor: { annotation in labelsById[annotation.id] },
            sourceImage: image,
            labelStyle: .screen)
        AnnotationPainter.draw(
            capture.annotations, imageSize: CGSize(width: width, height: height), in: ctx, options: options)
        return ctx.makeImage()
    }
}
