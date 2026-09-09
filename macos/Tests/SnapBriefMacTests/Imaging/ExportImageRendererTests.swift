import AppKit
import CoreGraphics
import Foundation
import XCTest

@testable import SnapBriefCore
@testable import SnapBriefMac

/// Smoke coverage for `ExportImageRenderer` (SPEC §4.5): the rendered PNG must be exactly 48px
/// taller than the source image and must decode back successfully.
final class ExportImageRendererTests: XCTestCase {
    func test_renderPNG_addsHeaderHeightAndDecodes() async throws {
        let width = 40
        let height = 30
        let sourceImage = try XCTUnwrap(makeImage(width: width, height: height))
        let sourceData = try XCTUnwrap(ImageCodec.encode(sourceImage, format: .png))

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExportImageRendererTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appendingPathComponent("source.png")
        try ImageCodec.writeAtomically(sourceData, to: sourceURL)

        let notedAnnotation = AnnotationItem.create(
            kind: .rectangle,
            points: [NormalizedPoint(0.1, 0.1), NormalizedPoint(0.4, 0.4)],
            strokeColor: "#FF2F8CFF",
            thickness: 4,
            note: "Check this")
        var capture = CaptureItem.create(sourceImagePath: "source.png", pixelWidth: width, pixelHeight: height)
        capture.annotations = [notedAnnotation]

        let renderer = ExportImageRenderer()
        let data = try await renderer.renderPNG(
            capture: capture,
            annotations: capture.annotations,
            context: ExportImageContext(displayLabel: "A", captureIndex: 0, sourceImagePath: sourceURL))

        let decoded = try XCTUnwrap(ImageCodec.decodePNG(data))
        XCTAssertEqual(width, decoded.width)
        XCTAssertEqual(height + 48, decoded.height)
    }

    /// R4 regression coverage (finding R4): a vertical-flip bug in the source blit would swap
    /// which row lands where in the export, so an asymmetric 2x2 source (top row red, bottom row
    /// blue) makes that unambiguous — the exported row right below the 48px header must be red,
    /// the row after it blue.
    func test_renderPNG_preservesSourceRowOrder() async throws {
        let width = 2
        let sourceImage = try XCTUnwrap(makeTwoRowImage(width: width, topColor: (255, 0, 0), bottomColor: (0, 0, 255)))
        let sourceData = try XCTUnwrap(ImageCodec.encode(sourceImage, format: .png))

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExportImageRendererTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appendingPathComponent("source.png")
        try ImageCodec.writeAtomically(sourceData, to: sourceURL)

        let capture = CaptureItem.create(sourceImagePath: "source.png", pixelWidth: width, pixelHeight: 2)
        let renderer = ExportImageRenderer()
        let data = try await renderer.renderPNG(
            capture: capture,
            annotations: [],
            context: ExportImageContext(displayLabel: "A", captureIndex: 0, sourceImagePath: sourceURL))

        let decoded = try XCTUnwrap(ImageCodec.decodePNG(data))
        let bitmap = NSBitmapImageRep(cgImage: decoded)
        let topRow = try XCTUnwrap(bitmap.colorAt(x: 0, y: 48)?.usingColorSpace(.deviceRGB))
        let bottomRow = try XCTUnwrap(bitmap.colorAt(x: 0, y: 49)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(topRow.redComponent, 0.9)
        XCTAssertLessThan(topRow.blueComponent, 0.1)
        XCTAssertGreaterThan(bottomRow.blueComponent, 0.9)
        XCTAssertLessThan(bottomRow.redComponent, 0.1)
    }

    /// R4 regression coverage: `AnnotationPainter.draw` with no annotations, in the flipped
    /// (top-left-origin, Y-down) context it documents as its contract, must not disturb row order
    /// on the way through its internal "unflip, draw, restore" blit.
    func test_annotationPainterDraw_noAnnotations_preservesTopRow() throws {
        let width = 2
        let height = 2
        let sourceImage = try XCTUnwrap(makeTwoRowImage(width: width, topColor: (255, 0, 0), bottomColor: (0, 0, 255)))

        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        let ctx = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo))
        // `AnnotationPainter.draw`'s documented contract: `(0,0)` is top-left, Y grows downward.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)

        let options = AnnotationPaintOptions(showLabels: false, labelFor: { _ in nil }, sourceImage: sourceImage)
        AnnotationPainter.draw([], imageSize: CGSize(width: width, height: height), in: ctx, options: options)

        let rendered = try XCTUnwrap(ctx.makeImage())
        let bitmap = NSBitmapImageRep(cgImage: rendered)
        let topRow = try XCTUnwrap(bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(topRow.redComponent, 0.9)
        XCTAssertLessThan(topRow.blueComponent, 0.1)
    }

    private func makeImage(width: Int, height: Int) -> CGImage? {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            pixels[offset] = 200
            pixels[offset + 1] = 200
            pixels[offset + 2] = 200
            pixels[offset + 3] = 255
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent)
    }

    /// A 2-row `topColor`-over-`bottomColor` image (row 0 = `topColor`, matching
    /// `NSBitmapImageRep.colorAt(x:y:)`'s top-left-origin `y == 0`), used by the R4 row-order
    /// regression tests above. `.premultipliedFirst` + `.byteOrder32Little` stores each pixel as
    /// `[B, G, R, A]` in memory, matching `makeImage(width:height:)`'s own bitmap info.
    private func makeTwoRowImage(width: Int, topColor: (UInt8, UInt8, UInt8), bottomColor: (UInt8, UInt8, UInt8)) -> CGImage? {
        let height = 2
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        func fillRow(_ row: Int, _ color: (UInt8, UInt8, UInt8)) {
            for column in 0..<width {
                let offset = (row * width + column) * 4
                pixels[offset] = color.2
                pixels[offset + 1] = color.1
                pixels[offset + 2] = color.0
                pixels[offset + 3] = 255
            }
        }
        fillRow(0, topColor)
        fillRow(1, bottomColor)
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent)
    }
}
