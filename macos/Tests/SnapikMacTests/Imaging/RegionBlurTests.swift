import CoreGraphics
import Foundation
import XCTest
import SnapikCore

@testable import SnapikMac

/// Port of `tests/Snapik.App.Imaging.Tests/RegionBlurTests.cs`. Tests 13-18 (SPEC §8.2).
///
/// Adapted from the C# `BitmapSource`-based tests: `CGImage` carries no DPI metadata and is
/// already immutable by construction (no `IsFrozen` concept), so test 13 only asserts
/// dimensions and byte-for-byte unchanged source pixels, dropping the DPI/frozen assertions.
/// Tests 13-16 (pixel behavior) go through `RegionBlur.blur` (the `CONTRACTS.md`-declared,
/// non-throwing entry point); tests 17-18 (invalid radius) go through the internal throwing
/// `RegionBlur.blurStrict`, since `blur` itself now clamps instead of rejecting — see
/// `RegionBlur.swift` for why.
final class RegionBlurTests: XCTestCase {
    /// Test 13 (adapted): `Apply_PreservesDimensionsDpiAndOriginalPixels`.
    func test_13_Apply_PreservesDimensionsAndOriginalPixels() throws {
        let originalPixels = gradientPixels(width: 7, height: 5)
        let source = try XCTUnwrap(makeBGRAImage(width: 7, height: 5, pixels: originalPixels))

        let result = RegionBlur.blur(source, region: CGRect(x: 1, y: 1, width: 5, height: 3), radius: 2)

        XCTAssertEqual(7, result.width)
        XCTAssertEqual(5, result.height)
        XCTAssertEqual(originalPixels, try XCTUnwrap(readBGRAPixels(source)))
    }

    /// Test 14: `Apply_BlursAnImpulseButLeavesOutsideRegionUnchanged`.
    func test_14_Apply_BlursAnImpulseButLeavesOutsideRegionUnchanged() throws {
        let width = 7
        let height = 7
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        fillOpaque(&pixels)
        setPixel(&pixels, width: width, x: 3, y: 3, blue: 255, green: 255, red: 255, alpha: 255)
        setPixel(&pixels, width: width, x: 0, y: 0, blue: 20, green: 30, red: 40, alpha: 255)
        let source = try XCTUnwrap(makeBGRAImage(width: width, height: height, pixels: pixels))

        let result = RegionBlur.blur(source, region: CGRect(x: 1, y: 1, width: 5, height: 5), radius: 1)
        let blurred = try XCTUnwrap(readBGRAPixels(result))

        XCTAssertEqual([20, 30, 40, 255], pixel(blurred, width: width, x: 0, y: 0))
        let center = pixel(blurred, width: width, x: 3, y: 3)
        XCTAssertGreaterThanOrEqual(center[0], 1)
        XCTAssertLessThanOrEqual(center[0], 254)
        XCTAssertGreaterThan(pixel(blurred, width: width, x: 3, y: 2)[0], 0)
    }

    /// Test 15: `Apply_ClipsPartiallyOutOfBoundsRectangle`.
    func test_15_Apply_ClipsPartiallyOutOfBoundsRectangle() throws {
        let pixels = gradientPixels(width: 4, height: 4)
        let source = try XCTUnwrap(makeBGRAImage(width: 4, height: 4, pixels: pixels))

        let result = RegionBlur.blur(source, region: CGRect(x: -3, y: -2, width: 5, height: 4), radius: 2)
        let output = try XCTUnwrap(readBGRAPixels(result))

        XCTAssertNotEqual(pixel(pixels, width: 4, x: 0, y: 0), pixel(output, width: 4, x: 0, y: 0))
        XCTAssertEqual(pixel(pixels, width: 4, x: 3, y: 3), pixel(output, width: 4, x: 3, y: 3))
    }

    /// Test 16: `Apply_EmptyIntersectionReturnsIndependentUnchangedBitmap`.
    func test_16_Apply_EmptyIntersectionReturnsIndependentUnchangedBitmap() throws {
        let pixels = gradientPixels(width: 3, height: 2)
        let source = try XCTUnwrap(makeBGRAImage(width: 3, height: 2, pixels: pixels))

        let result = RegionBlur.blur(source, region: CGRect(x: 10, y: 10, width: 2, height: 2), radius: 3)

        XCTAssertEqual(pixels, try XCTUnwrap(readBGRAPixels(result)))
    }

    /// Test 17: `Apply_RejectsInvalidRadius(0)`.
    ///
    /// Exercised against `blurStrict` (internal): the `CONTRACTS.md`-declared `blur(...)` entry
    /// point is non-throwing (`Sources/SnapikMac/Editor/AnnotationCanvasView+Drawing.swift`
    /// already calls it without `try`) and clamps an out-of-range radius instead of rejecting it,
    /// so `blurStrict` is the only entry point left that still exhibits the ported Windows
    /// "reject invalid radius" behavior these two tests are about.
    func test_17_Apply_RejectsInvalidRadius_zero() throws {
        let source = try XCTUnwrap(makeBGRAImage(width: 1, height: 1, pixels: [0, 0, 0, 255]))
        XCTAssertThrowsError(try RegionBlur.blurStrict(source, region: CGRect(x: 0, y: 0, width: 1, height: 1), radius: 0)) { error in
            guard case .argumentOutOfRange = error as? SnapikError else {
                return XCTFail("Expected argumentOutOfRange, got \(error)")
            }
        }
    }

    /// Test 18: `Apply_RejectsInvalidRadius(513)`.
    func test_18_Apply_RejectsInvalidRadius_tooLarge() throws {
        let source = try XCTUnwrap(makeBGRAImage(width: 1, height: 1, pixels: [0, 0, 0, 255]))
        XCTAssertThrowsError(try RegionBlur.blurStrict(source, region: CGRect(x: 0, y: 0, width: 1, height: 1), radius: 513)) { error in
            guard case .argumentOutOfRange = error as? SnapikError else {
                return XCTFail("Expected argumentOutOfRange, got \(error)")
            }
        }
    }

    // MARK: - Sync 3 (SPEC-DELTA-3 §6: the oval mask and the radius from the size of the region)

    /// Port of `Apply_WithAnOvalMaskBlursTheCentreAndLeavesTheCornerOfItsBox`.
    func test_Apply_WithAnOvalMaskBlursTheCentreAndLeavesTheCornerOfItsBox() throws {
        let side = 24
        let pixels = checkerPixels(width: side, height: side)
        let source = try XCTUnwrap(makeBGRAImage(width: side, height: side, pixels: pixels))

        let result = RegionBlur.blur(source, region: CGRect(x: 2, y: 2, width: 20, height: 20), radius: 3, shape: .ellipse)
        let output = try XCTUnwrap(readBGRAPixels(result))

        XCTAssertNotEqual(pixel(pixels, width: side, x: 12, y: 12), pixel(output, width: side, x: 12, y: 12))
        // The corner of the bounding box is outside the oval: the picture there is untouched.
        XCTAssertEqual(pixel(pixels, width: side, x: 2, y: 2), pixel(output, width: side, x: 2, y: 2))
        XCTAssertEqual(pixel(pixels, width: side, x: 21, y: 21), pixel(output, width: side, x: 21, y: 21))
    }

    /// Port of `RadiusFor_FollowsTheShorterSideBetweenSixAndThirtySix`.
    func test_RadiusFor_FollowsTheShorterSideBetweenSixAndThirtySix() {
        XCTAssertEqual(6, RegionBlur.radiusFor(width: 40, height: 40))
        XCTAssertEqual(20, RegionBlur.radiusFor(width: 240, height: 600))
        XCTAssertEqual(36, RegionBlur.radiusFor(width: 2000, height: 1000))
    }

    /// The rectangle is the shape that covers every pixel of its box, so it comes back byte for byte
    /// as it always did — the blend by the mask is skipped for it entirely.
    func test_Apply_WithARectangleMaskIsByteForByteTheOldBlur() throws {
        let side = 16
        let pixels = checkerPixels(width: side, height: side)
        let source = try XCTUnwrap(makeBGRAImage(width: side, height: side, pixels: pixels))

        let masked = RegionBlur.blur(source, region: CGRect(x: 2, y: 2, width: 10, height: 10), radius: 2, shape: .rectangle)
        let plain = RegionBlur.blur(source, region: CGRect(x: 2, y: 2, width: 10, height: 10), radius: 2)

        XCTAssertEqual(try XCTUnwrap(readBGRAPixels(plain)), try XCTUnwrap(readBGRAPixels(masked)))
    }

    // MARK: - Test helpers (BGRA8 premultiplied, top-down, matching `RegionBlur`'s own layout)

    private func checkerPixels(width: Int, height: Int) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let value: UInt8 = (x + y) % 2 == 0 ? 255 : 0
                setPixel(&pixels, width: width, x: x, y: y, blue: value, green: value, red: value, alpha: 255)
            }
        }
        return pixels
    }

    private func makeBGRAImage(width: Int, height: Int, pixels: [UInt8]) -> CGImage? {
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

    private func readBGRAPixels(_ image: CGImage) -> [UInt8]? {
        guard let data = image.dataProvider?.data else { return nil }
        return [UInt8](data as Data)
    }

    private func gradientPixels(width: Int, height: Int) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                setPixel(
                    &pixels, width: width, x: x, y: y,
                    blue: UInt8((x * 31) % 256), green: UInt8((y * 37) % 256), red: UInt8(((x + y) * 19) % 256), alpha: 255)
            }
        }
        return pixels
    }

    private func fillOpaque(_ pixels: inout [UInt8]) {
        var offset = 3
        while offset < pixels.count {
            pixels[offset] = 255
            offset += 4
        }
    }

    private func setPixel(_ pixels: inout [UInt8], width: Int, x: Int, y: Int, blue: UInt8, green: UInt8, red: UInt8, alpha: UInt8) {
        let offset = (y * width + x) * 4
        pixels[offset] = blue
        pixels[offset + 1] = green
        pixels[offset + 2] = red
        pixels[offset + 3] = alpha
    }

    private func pixel(_ pixels: [UInt8], width: Int, x: Int, y: Int) -> [UInt8] {
        let offset = (y * width + x) * 4
        return Array(pixels[offset..<offset + 4])
    }
}
