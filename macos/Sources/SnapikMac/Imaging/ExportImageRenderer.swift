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
    /// The field the picture stands on when a badge was carried off it: the same dark the editor
    /// shows beside the capture, so a badge on the field reads as a badge and not as a cut-off one
    /// (`WpfExportImageRenderer.cs:19-22`, SPEC-DELTA-5-editor.md §1.2 E-7).
    private static let fieldColor = CGColor(
        red: 42.0 / 255.0, green: 49.0 / 255.0, blue: 64.0 / 255.0, alpha: 1)

    public init() {}

    /// Where the capture itself begins inside the exported picture: the header stands above it and
    /// the field the badges asked for is around it. Everything measured in the pixels of the capture
    /// — a mark, a badge, the leader between them — is counted from this one point
    /// (`WpfExportImageRenderer.cs:39`).
    static func captureOrigin(_ margin: ExportMargin) -> CGPoint {
        CGPoint(x: CGFloat(margin.left), y: CGFloat(Self.headerHeight + margin.top))
    }

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

        // The list of the marks that carry a number is gathered once: the field around the capture
        // is measured from the badges of exactly those marks, and so are the labels drawn on them.
        var captureForLabels = capture
        captureForLabels.annotations = annotations
        let noted = CaptureLabels.forNotedAnnotations(captureLabel: context.displayLabel, capture: captureForLabels)
        var labelsById: [SBGuid: String] = [:]
        for labeled in noted {
            labelsById[labeled.annotation.id] = labeled.displayLabel
        }
        let badges: [(anchor: NormalizedPoint, offset: NormalizedPoint?, label: String)] = noted.compactMap { labeled in
            guard let first = labeled.annotation.points.first else { return nil }
            return (anchor: first, offset: labeled.annotation.noteOffset, label: labeled.displayLabel)
        }
        // With every badge standing inside the capture the field is empty, the sheet is the size it
        // has always been, and the exported bytes are the ones of the round before this one.
        let margin = NoteBadgeGeometry.exportMargins(badges: badges, width: width, height: height)
        let origin = Self.captureOrigin(margin)
        let sheetWidth = margin.left + width + margin.right
        let sheetHeight = Self.headerHeight + margin.top + height + margin.bottom

        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard
            let ctx = CGContext(
                data: nil,
                width: sheetWidth,
                height: sheetHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: bitmapInfo)
        else {
            throw SnapikError.invalidOperation("ExportImageRenderer: failed to create the render context.")
        }
        // (0,0) is the rendered image's top-left corner and Y grows downward, matching every
        // pixel/point formula in SPEC §4.5 (e.g. `y = p.y * height + 48`).
        ctx.translateBy(x: 0, y: CGFloat(sheetHeight))
        ctx.scaleBy(x: 1, y: -1)

        // 1. The field first, under everything, and the white header across the whole sheet over it.
        ctx.saveGState()
        ctx.setFillColor(Self.fieldColor)
        ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(sheetWidth), height: CGFloat(sheetHeight)))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(sheetWidth), height: CGFloat(Self.headerHeight)))
        ctx.restoreGState()

        // 2, 4-6. Blurred source image, then annotation shapes (non-blur/redaction, then
        // redaction), then labels — all counted from the one origin of the capture.
        let options = AnnotationPaintOptions(
            showLabels: true,
            labelFor: { labelsById[$0.id] },
            sourceImage: sourceImage,
            labelStyle: .export,
            // The clamp under the header is gone: between the header and the capture there is now a
            // field, and that is where a badge carried upwards belongs
            // (`WpfExportImageRenderer.cs:229-231`, SPEC-DELTA-5-editor.md §3.9).
            labelTopMargin: -.greatestFiniteMagnitude)

        // The shift onto the field is made **after** the flip and inside a saved state: the badge of
        // the capture is drawn after the painter and in the coordinates of the sheet, and a shift
        // left standing would carry it away with the picture.
        ctx.saveGState()
        ctx.translateBy(x: origin.x, y: origin.y)
        AnnotationPainter.draw(annotations, imageSize: CGSize(width: CGFloat(width), height: CGFloat(height)), in: ctx, options: options)
        ctx.restoreGState()

        // 3. Capture badge, in the coordinates of the sheet: the header begins at the left edge of
        // the sheet and not at the left edge of the capture, so the `x: 12` of it stands. Drawn after
        // the image/shapes/labels above, but this is pixel-equivalent to the SPEC order (badge, then
        // shapes, then labels): the badge only occupies y∈[8,40] inside the 48px header, and a badge
        // of a mark that climbs that high is stopped by the field under it.
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
