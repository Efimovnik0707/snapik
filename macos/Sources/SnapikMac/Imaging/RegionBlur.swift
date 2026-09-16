// Port of `src/Snapik.App/Imaging/RegionBlur.cs`, SPEC §2.8.
import CoreGraphics
import Foundation
import SnapikCore

/// Blurs exactly one pixel-space rectangle of `image`, leaving every other pixel byte-for-byte
/// unchanged. Operates on a top-down, premultiplied BGRA8 buffer (matching the byte layout the
/// Windows `Bgra32` box blur and its ported tests assume) so the three-pass box blur produces
/// pixel-identical results.
public enum RegionBlur {
    private static let bytesPerPixel = 4
    private static let passCount = 3
    private static let maximumRadius = 512

    /// Port of `RegionBlur.RadiusFor` (SPEC-DELTA-3 §1.4 E-1): how strongly a region is blurred comes
    /// from its own size, so the strength is not a hidden setting of the stroke thickness any more.
    public static func radiusFor(width: Double, height: Double) -> Int {
        Int(min(max(min(width, height) / 12, 6), 36).rounded())
    }

    /// Port of `RegionBlur.Apply`, matching `CONTRACTS.md`'s declared (non-throwing) signature —
    /// `Sources/SnapikMac/Editor/AnnotationCanvasView+Drawing.swift` already calls it this
    /// way. `radius` is clamped into `1...512` instead of trapping on out-of-range input (SPEC
    /// §2.8's C# `ArgumentOutOfRangeException` has no non-throwing Swift equivalent here); on the
    /// rare internal failure (e.g. bitmap context allocation), returns `image` unchanged rather
    /// than crashing. `blurStrict` below preserves the exact reject-invalid-radius behavior for
    /// callers that can handle an error (SPEC §2.8 / ported tests 17-18).
    public static func blur(_ image: CGImage, region: CGRect, radius: Int, shape: AnnotationShape = .rectangle) -> CGImage {
        let clampedRadius = min(max(radius, 1), maximumRadius)
        return (try? blurStrict(image, region: region, radius: clampedRadius, shape: shape)) ?? image
    }

    /// Port of `RegionBlur.Apply`'s full behavior, including the radius range check. Not part of
    /// `CONTRACTS.md`'s sketch (kept internal); exists so tests 13-18 can exercise the exact
    /// ported Windows behavior, including radius rejection, without changing `blur`'s
    /// already-depended-upon non-throwing signature.
    static func blurStrict(_ image: CGImage, region: CGRect, radius: Int, shape: AnnotationShape = .rectangle) throws -> CGImage {
        guard radius >= 1 && radius <= maximumRadius else {
            throw SnapikError.argumentOutOfRange(
                "radius: Blur radius must be between 1 and \(maximumRadius) pixels.")
        }

        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return image }
        let stride = width * bytesPerPixel
        var pixels = try topDownBGRAPixels(of: image, width: width, height: height, stride: stride)

        let clipped = clip(region, imageWidth: width, imageHeight: height)
        if clipped.width > 0 && clipped.height > 0 {
            // The mask is measured against the region the user drew, not against the part of it that
            // fits on the picture: half an oval over the edge stays half an oval.
            blurRegion(&pixels, fullStride: stride, region: clipped, radius: radius, shape: shape, shapeBox: region)
        }

        return try makeImage(pixels: pixels, width: width, height: height, stride: stride)
    }

    // MARK: - Pixel buffer plumbing

    private static func bitmapInfoRawValue() -> UInt32 {
        CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    }

    /// Renders `image` into a top-down (row 0 = image's own top row), BGRA8 premultiplied
    /// buffer, normalizing whatever the source's original pixel format was — mirroring the C#
    /// `FormatConvertedBitmap` step ("если оно уже в нём — используется как есть", generalized
    /// here to "always normalize", which is a byte-exact no-op for images already in this
    /// format). No coordinate flip is applied: drawing a `CGImage` into a freshly created,
    /// default (bottom-left origin) bitmap context and then reading its raw buffer directly
    /// already yields row 0 = the image's own top row (the same reasoning that makes the common
    /// "draw into CGContext, then `makeImage()`" resize idiom work without a manual flip).
    private static func topDownBGRAPixels(of image: CGImage, width: Int, height: Int, stride: Int) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: stride * height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var failed = false
        pixels.withUnsafeMutableBytes { buffer in
            guard
                let context = CGContext(
                    data: buffer.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: stride,
                    space: colorSpace,
                    bitmapInfo: bitmapInfoRawValue())
            else {
                failed = true
                return
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        }
        if failed {
            throw SnapikError.invalidOperation("RegionBlur: failed to create a bitmap context for the source image.")
        }
        return pixels
    }

    private static func makeImage(pixels: [UInt8], width: Int, height: Int, stride: Int) throws -> CGImage {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else {
            throw SnapikError.invalidOperation("RegionBlur: failed to wrap the blurred pixel buffer.")
        }
        guard
            let result = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 8 * bytesPerPixel,
                bytesPerRow: stride,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: bitmapInfoRawValue()),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent)
        else {
            throw SnapikError.invalidOperation("RegionBlur: failed to build the blurred CGImage.")
        }
        return result
    }

    // MARK: - Port of `RegionBlur.Clip`

    private struct PixelRect {
        var x: Int
        var y: Int
        var width: Int
        var height: Int
        static let empty = PixelRect(x: 0, y: 0, width: 0, height: 0)
    }

    private static func clip(_ region: CGRect, imageWidth: Int, imageHeight: Int) -> PixelRect {
        guard region.width > 0, region.height > 0 else { return .empty }
        let left = clampToInt(region.minX, 0, Double(imageWidth))
        let top = clampToInt(region.minY, 0, Double(imageHeight))
        let right = clampToInt(region.minX + region.width, 0, Double(imageWidth))
        let bottom = clampToInt(region.minY + region.height, 0, Double(imageHeight))
        guard right > left, bottom > top else { return .empty }
        return PixelRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    private static func clampToInt(_ value: Double, _ minimum: Double, _ maximum: Double) -> Int {
        Int(min(max(value, minimum), maximum))
    }

    // MARK: - Port of `RegionBlur.BlurRegion` / `BlurHorizontal` / `BlurVertical`

    private static func blurRegion(
        _ fullPixels: inout [UInt8], fullStride: Int, region: PixelRect, radius: Int,
        shape: AnnotationShape, shapeBox: CGRect
    ) {
        let regionStride = region.width * bytesPerPixel
        var regionPixels = [UInt8](repeating: 0, count: regionStride * region.height)
        var scratch = [UInt8](repeating: 0, count: regionPixels.count)

        for row in 0..<region.height {
            let sourceOffset = (region.y + row) * fullStride + region.x * bytesPerPixel
            for byte in 0..<regionStride {
                regionPixels[row * regionStride + byte] = fullPixels[sourceOffset + byte]
            }
        }
        // A rectangle covers every pixel of its box, so it is written back untouched by the blend
        // below and comes out byte for byte as it always did.
        let untouched: [UInt8]? = shape == .rectangle ? nil : regionPixels

        for _ in 0..<passCount {
            blurHorizontal(regionPixels, &scratch, width: region.width, height: region.height, stride: regionStride, radius: radius)
            blurVertical(scratch, &regionPixels, width: region.width, height: region.height, stride: regionStride, radius: radius)
        }
        if let untouched {
            blendByShape(&regionPixels, untouched: untouched, region: region, stride: regionStride, shape: shape, shapeBox: shapeBox)
        }

        for row in 0..<region.height {
            let destinationOffset = (region.y + row) * fullStride + region.x * bytesPerPixel
            for byte in 0..<regionStride {
                fullPixels[destinationOffset + byte] = regionPixels[row * regionStride + byte]
            }
        }
    }

    /// Port of `BlendByShape`: `dst = original * (1 - coverage) + blurred * coverage`, so the picture
    /// comes back untouched outside the shape and the edge of the shape is smooth.
    private static func blendByShape(
        _ blurred: inout [UInt8], untouched: [UInt8], region: PixelRect, stride: Int,
        shape: AnnotationShape, shapeBox: CGRect
    ) {
        let boxWidth = Double(shapeBox.width)
        let boxHeight = Double(shapeBox.height)
        for row in 0..<region.height {
            for column in 0..<region.width {
                let coverage = ShapeMask.coverage(
                    shape, width: boxWidth, height: boxHeight,
                    x: Double(region.x) - Double(shapeBox.minX) + Double(column),
                    y: Double(region.y) - Double(shapeBox.minY) + Double(row))
                if coverage >= 1 { continue }
                let offset = row * stride + column * bytesPerPixel
                for channel in 0..<bytesPerPixel {
                    let mixed = Double(untouched[offset + channel]) * (1 - coverage) + Double(blurred[offset + channel]) * coverage
                    blurred[offset + channel] = UInt8(min(max(mixed.rounded(), 0), 255))
                }
            }
        }
    }

    private static func blurHorizontal(
        _ source: [UInt8], _ destination: inout [UInt8], width: Int, height: Int, stride: Int, radius: Int
    ) {
        let divisor = radius * 2 + 1
        var sums = [Int](repeating: 0, count: bytesPerPixel)
        for y in 0..<height {
            for channel in 0..<bytesPerPixel { sums[channel] = 0 }
            for offset in -radius...radius {
                let x = min(max(offset, 0), width - 1)
                addPixel(source, offset: y * stride + x * bytesPerPixel, sums: &sums, sign: 1)
            }
            for x in 0..<width {
                writeAverage(&destination, offset: y * stride + x * bytesPerPixel, sums: sums, divisor: divisor)
                let outgoingX = min(max(x - radius, 0), width - 1)
                let incomingX = min(max(x + radius + 1, 0), width - 1)
                addPixel(source, offset: y * stride + outgoingX * bytesPerPixel, sums: &sums, sign: -1)
                addPixel(source, offset: y * stride + incomingX * bytesPerPixel, sums: &sums, sign: 1)
            }
        }
    }

    private static func blurVertical(
        _ source: [UInt8], _ destination: inout [UInt8], width: Int, height: Int, stride: Int, radius: Int
    ) {
        let divisor = radius * 2 + 1
        var sums = [Int](repeating: 0, count: bytesPerPixel)
        for x in 0..<width {
            for channel in 0..<bytesPerPixel { sums[channel] = 0 }
            for offset in -radius...radius {
                let y = min(max(offset, 0), height - 1)
                addPixel(source, offset: y * stride + x * bytesPerPixel, sums: &sums, sign: 1)
            }
            for y in 0..<height {
                writeAverage(&destination, offset: y * stride + x * bytesPerPixel, sums: sums, divisor: divisor)
                let outgoingY = min(max(y - radius, 0), height - 1)
                let incomingY = min(max(y + radius + 1, 0), height - 1)
                addPixel(source, offset: outgoingY * stride + x * bytesPerPixel, sums: &sums, sign: -1)
                addPixel(source, offset: incomingY * stride + x * bytesPerPixel, sums: &sums, sign: 1)
            }
        }
    }

    private static func addPixel(_ pixels: [UInt8], offset: Int, sums: inout [Int], sign: Int) {
        for channel in 0..<bytesPerPixel {
            sums[channel] += sign * Int(pixels[offset + channel])
        }
    }

    /// Port of `WriteAverage`: `pixel = (sum + divisor / 2) / divisor` (round to nearest).
    private static func writeAverage(_ pixels: inout [UInt8], offset: Int, sums: [Int], divisor: Int) {
        for channel in 0..<bytesPerPixel {
            pixels[offset + channel] = UInt8((sums[channel] + divisor / 2) / divisor)
        }
    }
}
