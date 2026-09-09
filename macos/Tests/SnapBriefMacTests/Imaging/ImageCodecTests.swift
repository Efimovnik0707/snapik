import CoreGraphics
import Foundation
import XCTest
import SnapBriefCore

@testable import SnapBriefMac

/// PNG/JPEG round-trip coverage for `ImageCodec` (SPEC §1.13), requested alongside the ported
/// `RegionBlurTests`/`ResizeGeometryTests` since `ImageCodec` has no direct Windows test
/// counterpart (the C# side only exercises it indirectly through `LocalImageSave`).
final class ImageCodecTests: XCTestCase {
    func test_PNG_roundTrip_preservesDimensions() throws {
        let image = try XCTUnwrap(makeImage(width: 6, height: 4))

        let data = try XCTUnwrap(ImageCodec.encode(image, format: .png))
        let decoded = try XCTUnwrap(ImageCodec.decodePNG(data))

        XCTAssertEqual(6, decoded.width)
        XCTAssertEqual(4, decoded.height)
    }

    func test_JPEG_roundTrip_preservesDimensions() throws {
        let image = try XCTUnwrap(makeImage(width: 10, height: 8))

        let data = try XCTUnwrap(ImageCodec.encode(image, format: .jpeg(quality: 80)))
        // `decodePNG` decodes via the generic ImageIO source, which auto-detects the actual
        // format from `data`'s contents rather than assuming PNG, so it also round-trips JPEG.
        let decoded = try XCTUnwrap(ImageCodec.decodePNG(data))

        XCTAssertEqual(10, decoded.width)
        XCTAssertEqual(8, decoded.height)
    }

    func test_writeAtomically_thenLoadImage_roundTrips() throws {
        let image = try XCTUnwrap(makeImage(width: 5, height: 5))
        let data = try XCTUnwrap(ImageCodec.encode(image, format: .png))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageCodecTests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("out.png")
        defer { try? FileManager.default.removeItem(at: directory) }

        try ImageCodec.writeAtomically(data, to: fileURL)
        let loaded = try XCTUnwrap(ImageCodec.loadImage(at: fileURL))

        XCTAssertEqual(5, loaded.width)
        XCTAssertEqual(5, loaded.height)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        // Overwriting an existing file must still succeed atomically.
        try ImageCodec.writeAtomically(data, to: fileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    // MARK: - Helpers

    private func makeImage(width: Int, height: Int) -> CGImage? {
        let pixels = [UInt8](repeating: 128, count: width * height * 4)
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
