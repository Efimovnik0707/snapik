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
}
