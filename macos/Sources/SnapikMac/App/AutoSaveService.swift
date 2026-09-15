// Port of `EdgeStackWindow.Saving.cs:17-35` (`AutoSaveCaptureAsync`), SPEC-DELTA-2.md §1.8,
// SPEC-DELTA-2B.md §E3.
import CoreGraphics
import Foundation
import SnapikCore

/// Renders one committed capture (image + annotations, screen-style labels, no header/badge — this
/// is a plain "save what you see" render, not the export PNG) straight to the user's save folder,
/// without touching the clipboard package (mirrors `FastSaveService`'s scope).
enum AutoSaveService {
    static func save(
        capture: CaptureItem,
        displayLabel: String,
        sessionDirectory: URL,
        settings: HotkeySettings
    ) throws -> URL {
        let sourceURL = sessionDirectory.appendingPathComponent(capture.sourceImagePath)
        guard let sourceImage = ImageCodec.loadImage(at: sourceURL) else {
            throw SnapikError.fileNotFound("AutoSaveService: could not load the source image at \(sourceURL.path).")
        }

        let width = sourceImage.width
        let height = sourceImage.height
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard
            let ctx = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo)
        else {
            throw SnapikError.invalidOperation("AutoSaveService: failed to create the render context.")
        }
        // Top-left origin, Y grows downward, matching `AnnotationPainter`'s contract.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)

        var labelsById: [SBGuid: String] = [:]
        for labeled in CaptureLabels.forNotedAnnotations(captureLabel: displayLabel, capture: capture) {
            labelsById[labeled.annotation.id] = labeled.displayLabel
        }
        let options = AnnotationPaintOptions(
            showLabels: true,
            labelFor: { labelsById[$0.id] },
            sourceImage: sourceImage,
            labelStyle: .screen)
        AnnotationPainter.draw(
            capture.annotations, imageSize: CGSize(width: width, height: height), in: ctx, options: options)

        guard let rendered = ctx.makeImage() else {
            throw SnapikError.invalidOperation("AutoSaveService: failed to rasterize the annotated image.")
        }

        let format: ImageCodec.Format =
            settings.saveFormat == "jpeg" ? .jpeg(quality: max(1, min(100, settings.jpegQuality))) : .png
        guard let data = ImageCodec.encode(rendered, format: format) else {
            throw SnapikError.invalidData("AutoSaveService: could not encode the annotated image.")
        }

        let destination = FastSaveService.newPath(
            directory: URL(fileURLWithPath: settings.saveDirectory), format: settings.saveFormat)
        try ImageCodec.writeAtomically(data, to: destination)
        return destination
    }
}
