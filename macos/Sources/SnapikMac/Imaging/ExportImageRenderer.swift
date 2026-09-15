// Port of `src/Snapik.App/WpfExportImageRenderer.cs:17-150`, SPEC §4.5.
import AppKit
import CoreGraphics
import Foundation
import SnapikCore

/// Port of `WpfExportImageRenderer`: renders one capture's export PNG — source image (with all
/// `Blur` annotations applied) below a 48px white header carrying the capture badge, annotation
/// shapes, then annotation number labels.
public final class ExportImageRenderer: ExportImageRendering {
    private static let headerHeight = 48

    public init() {}

    public func renderPNG(
        capture: CaptureItem,
        annotations: [AnnotationItem],
        context: ExportImageContext
    ) async throws -> Data {
        guard let sourceImage = ImageCodec.loadImage(at: context.sourceImagePath) else {
            throw SnapikError.fileNotFound(
                "ExportImageRenderer: could not load the source image at \(context.sourceImagePath.path).")
        }

        let width = sourceImage.width
        let height = sourceImage.height
        let outHeight = height + Self.headerHeight
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard
            let ctx = CGContext(
                data: nil,
                width: width,
                height: outHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: bitmapInfo)
        else {
            throw SnapikError.invalidOperation("ExportImageRenderer: failed to create the render context.")
        }
        // (0,0) is the rendered image's top-left corner and Y grows downward, matching every
        // pixel/point formula in SPEC §4.5 (e.g. `y = p.y * height + 48`).
        ctx.translateBy(x: 0, y: CGFloat(outHeight))
        ctx.scaleBy(x: 1, y: -1)

        // 1. White header background.
        ctx.saveGState()
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(Self.headerHeight)))
        ctx.restoreGState()

        // 2, 4-6. Blurred source image, then annotation shapes (non-blur/redaction, then
        // redaction), then labels — all offset below the header.
        var captureForLabels = capture
        captureForLabels.annotations = annotations
        var labelsById: [SBGuid: String] = [:]
        for labeled in CaptureLabels.forNotedAnnotations(captureLabel: context.displayLabel, capture: captureForLabels) {
            labelsById[labeled.annotation.id] = labeled.displayLabel
        }
        let options = AnnotationPaintOptions(
            showLabels: true,
            labelFor: { labelsById[$0.id] },
            sourceImage: sourceImage,
            labelStyle: .export)

        ctx.saveGState()
        ctx.translateBy(x: 0, y: CGFloat(Self.headerHeight))
        AnnotationPainter.draw(annotations, imageSize: CGSize(width: CGFloat(width), height: CGFloat(height)), in: ctx, options: options)
        ctx.restoreGState()

        // 3. Capture badge. Drawn after the image/shapes/labels above, but this is
        // pixel-equivalent to the SPEC order (badge, then shapes, then labels): the badge only
        // occupies y∈[8,40] inside the 48px header, while every annotation coordinate is offset
        // by +48, so the two regions never overlap regardless of draw order.
        drawCaptureBadge(context.displayLabel, in: ctx)

        guard let rendered = ctx.makeImage() else {
            throw SnapikError.invalidOperation("ExportImageRenderer: failed to rasterize the export image.")
        }
        guard let data = ImageCodec.encode(rendered, format: .png) else {
            throw SnapikError.invalidOperation("ExportImageRenderer: failed to encode the export PNG.")
        }
        return data
    }

    /// Port of `DrawCaptureBadge`.
    private func drawCaptureBadge(_ label: String, in ctx: CGContext) {
        let badge = CGRect(x: 12, y: 8, width: 34, height: 32)
        let path = CGPath(roundedRect: badge, cornerWidth: 7, cornerHeight: 7, transform: nil)
        ctx.saveGState()
        ctx.setFillColor(CGColor(red: 23.0 / 255.0, green: 32.0 / 255.0, blue: 51.0 / 255.0, alpha: 1))
        ctx.addPath(path)
        ctx.fillPath()
        ctx.restoreGState()

        AnnotationPainter.drawText(
            label, fontSize: 16, weight: .bold,
            color: CGColor(red: 1, green: 1, blue: 1, alpha: 1), in: ctx, topLeft: CGPoint(x: 23, y: 13))
        AnnotationPainter.drawText(
            "SNAPIK · СНИМОК", fontSize: 12, weight: .semibold,
            color: CGColor(red: 94.0 / 255.0, green: 104.0 / 255.0, blue: 122.0 / 255.0, alpha: 1),
            in: ctx, topLeft: CGPoint(x: 57, y: 16))
    }
}
