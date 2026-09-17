import AppKit
import CoreGraphics
import Foundation
import XCTest

@testable import SnapikCore
@testable import SnapikMac

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
        // The header of 48 and, since SPEC-DELTA-5-editor.md §1.3 E-7, the field the badges ask for:
        // the badge of this mark stands above a point three pixels from the top of a capture of
        // forty by thirty, so it hangs over two edges and the sheet grows by what it needs.
        let margin = NoteBadgeGeometry.exportMargins(
            badges: [(anchor: NormalizedPoint(0.1, 0.1), offset: nil, label: "A1")],
            width: width, height: height)
        XCTAssertGreaterThan(margin.top, 0)
        XCTAssertGreaterThan(margin.left, 0)
        XCTAssertEqual(margin.left + width + margin.right, decoded.width)
        XCTAssertEqual(48 + margin.top + height + margin.bottom, decoded.height)
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

    /// SPEC-DELTA-5-editor.md §1.3 E-9, E-10, §4.2: a comment whose badge was carried away puts the
    /// dot it is pinned by into the exported picture, with its white rim, and the field the badge
    /// asked for moves the whole capture down by exactly the margin `captureOrigin` counts.
    func test_renderPNG_drawsTheDotOfADraggedComment() async throws {
        let width = 200
        let height = 140
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExportImageRendererTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appendingPathComponent("source.png")
        let sourceImage = try XCTUnwrap(makeImage(width: width, height: height))
        try ImageCodec.writeAtomically(try XCTUnwrap(ImageCodec.encode(sourceImage, format: .png)), to: sourceURL)

        let comment = AnnotationItem.create(
            kind: .comment,
            points: [NormalizedPoint(0.5, 0.5), NormalizedPoint(0.54, 0.557)],
            strokeColor: "#FFFF3B30",
            thickness: 4,
            note: "Отметка")
        var dragged = comment
        dragged.noteOffset = NormalizedPoint(0.2, -0.3)
        var capture = CaptureItem.create(sourceImagePath: "source.png", pixelWidth: width, pixelHeight: height)
        capture.annotations = [dragged]

        let renderer = ExportImageRenderer()
        let data = try await renderer.renderPNG(
            capture: capture, annotations: capture.annotations,
            context: ExportImageContext(displayLabel: "A", captureIndex: 0, sourceImagePath: sourceURL))
        let decoded = try XCTUnwrap(ImageCodec.decodePNG(data))

        // The badge was carried above the capture, so the sheet grew by the field it asked for.
        let margin = NoteBadgeGeometry.exportMargins(
            badges: [(anchor: NormalizedPoint(0.5, 0.5), offset: NormalizedPoint(0.2, -0.3), label: "A1")],
            width: width, height: height)
        XCTAssertGreaterThan(margin.top, 0)
        XCTAssertEqual(margin.left + width + margin.right, decoded.width)
        XCTAssertEqual(48 + margin.top + height + margin.bottom, decoded.height)

        let origin = ExportImageRenderer.captureOrigin(margin)
        let centre = CGPoint(x: origin.x + CGFloat(width) * 0.5, y: origin.y + CGFloat(height) * 0.5)
        let bitmap = NSBitmapImageRep(cgImage: decoded)
        let middle = try XCTUnwrap(bitmap.colorAt(x: Int(centre.x), y: Int(centre.y))?.usingColorSpace(.deviceRGB))
        // A corner of the capture, where nothing is drawn: the grey the source was painted with, read
        // through the same colour space as the dot, so the two numbers can be held against each other.
        let untouched = try XCTUnwrap(
            bitmap.colorAt(x: Int(origin.x) + 2, y: Int(origin.y) + 2)?.usingColorSpace(.deviceRGB))
        // The dot is the accent and not the picture under it. The swatch is an sRGB colour and the
        // sheet is a device-RGB bitmap, so the two agree as a swatch and not byte for byte — hence a
        // tolerance wider than a rounding, and the line above, which is what keeps a tolerance that
        // wide from passing a dot nobody drew.
        let accent = try XCTUnwrap(AccentPalette.flat.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(abs(Double(middle.redComponent) - Double(untouched.redComponent)), 0.1)
        XCTAssertEqual(Double(accent.redComponent), Double(middle.redComponent), accuracy: 0.12)
        XCTAssertEqual(Double(accent.greenComponent), Double(middle.greenComponent), accuracy: 0.12)
        XCTAssertEqual(Double(accent.blueComponent), Double(middle.blueComponent), accuracy: 0.12)

        // And the rim around it, one and a half pixels of white grown by the same scale as the dot.
        // The sample is taken on `anchorRadius * scale` itself, which is the line the stroke is
        // centred on: the band is 1.5·scale wide, so a pixel a whole point outside it is already the
        // capture with a little antialiasing over it, not the rim.
        let radius = NoteBadgeGeometry.anchorRadius * NoteBadgeGeometry.exportScale("A1")
        let rim = try XCTUnwrap(
            bitmap.colorAt(x: Int(centre.x + radius), y: Int(centre.y))?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(rim.redComponent, 0.85)
        XCTAssertGreaterThan(rim.greenComponent, 0.85)
        XCTAssertGreaterThan(rim.blueComponent, 0.85)
    }

    /// The other half of the same rule, on a second capture of its own: the list of noted marks is
    /// one per picture, and a second comment in the same one would take the number apart. A comment
    /// nobody dragged shows neither a dot nor a line, and the sheet is the size it always was.
    func test_renderPNG_leavesACommentThatWasNotDraggedAlone() async throws {
        let width = 200
        let height = 140
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExportImageRendererTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appendingPathComponent("source.png")
        let sourceImage = try XCTUnwrap(makeImage(width: width, height: height))
        try ImageCodec.writeAtomically(try XCTUnwrap(ImageCodec.encode(sourceImage, format: .png)), to: sourceURL)

        let comment = AnnotationItem.create(
            kind: .comment,
            points: [NormalizedPoint(0.5, 0.5), NormalizedPoint(0.54, 0.557)],
            strokeColor: "#FFFF3B30",
            thickness: 4,
            note: "Отметка")
        var capture = CaptureItem.create(sourceImagePath: "source.png", pixelWidth: width, pixelHeight: height)
        capture.annotations = [comment]

        let renderer = ExportImageRenderer()
        let data = try await renderer.renderPNG(
            capture: capture, annotations: capture.annotations,
            context: ExportImageContext(displayLabel: "A", captureIndex: 0, sourceImagePath: sourceURL))
        let decoded = try XCTUnwrap(ImageCodec.decodePNG(data))

        XCTAssertEqual(width, decoded.width)
        XCTAssertEqual(height + 48, decoded.height)
        let bitmap = NSBitmapImageRep(cgImage: decoded)
        let middle = try XCTUnwrap(bitmap.colorAt(x: width / 2, y: 48 + height / 2)?.usingColorSpace(.deviceRGB))
        // The grey the source is painted with, untouched: no dot was drawn over it. Held against a
        // corner of the same picture and not against the byte the source was written with, because
        // the two sides of that comparison would be read through two different colour spaces.
        let corner = try XCTUnwrap(bitmap.colorAt(x: 2, y: 48 + 2)?.usingColorSpace(.deviceRGB))
        XCTAssertEqual(Double(corner.redComponent), Double(middle.redComponent), accuracy: 0.01)
        XCTAssertEqual(Double(corner.blueComponent), Double(middle.blueComponent), accuracy: 0.01)
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
