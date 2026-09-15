// Port of the arrow-geometry assertions in SPEC-DELTA-2.md §5 ("300 заметок... arrowStyle" /
// Windows `ArrowDrawing` coverage) and SPEC-DELTA-2B.md §F ("4 стиля в 200×100 → непрозрачные
// пиксели у конца; curved ≠ straight").
import CoreGraphics
import Foundation
import XCTest

@testable import SnapikMac

final class ArrowDrawingTests: XCTestCase {
    private let width = 200
    private let height = 100
    private let start = CGPoint(x: 20, y: 50)
    private let end = CGPoint(x: 180, y: 50)

    func test_allFourStyles_paintOpaquePixelsNearTheEnd() throws {
        for style in ["straight", "curved", "bold", "wide"] {
            let pixels = try XCTUnwrap(renderedAlphaPixels(style: style))
            XCTAssertTrue(
                hasOpaquePixel(pixels, near: end, radius: 12),
                "style \(style) left no opaque pixel near the arrow's end point")
        }
    }

    func test_curved_differsFromStraight() throws {
        let straight = try XCTUnwrap(renderedAlphaPixels(style: "straight"))
        let curved = try XCTUnwrap(renderedAlphaPixels(style: "curved"))
        XCTAssertNotEqual(straight, curved)
    }

    func test_lengthBelowThreshold_drawsNothing() throws {
        let pixels = try XCTUnwrap(renderedAlphaPixels(style: "straight", start: CGPoint(x: 100, y: 50), end: CGPoint(x: 100.001, y: 50)))
        XCTAssertTrue(pixels.allSatisfy { $0 == 0 })
    }

    func test_bold_isThickerThanStraight() throws {
        // Both fully opaque somewhere along the shaft; bold's line width is `thickness * 2`, so it
        // must cover strictly more pixels overall than the plain straight style at the same
        // thickness (SPEC-DELTA-2.md §1.2: "толщина пера thickness * (bold ? 2 : 1)").
        let straightCount = try XCTUnwrap(renderedAlphaPixels(style: "straight")).filter { $0 > 0 }.count
        let boldCount = try XCTUnwrap(renderedAlphaPixels(style: "bold")).filter { $0 > 0 }.count
        XCTAssertGreaterThan(boldCount, straightCount)
    }

    // MARK: - Helpers

    private func renderedAlphaPixels(style: String, start: CGPoint? = nil, end: CGPoint? = nil) -> [UInt8]? {
        guard
            let ctx = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ArrowDrawing.draw(
            in: ctx, from: start ?? self.start, to: end ?? self.end,
            color: CGColor(red: 1, green: 1, blue: 1, alpha: 1), thickness: 2, style: style)
        guard let data = ctx.data else { return nil }
        let count = width * height * 4
        let buffer = data.bindMemory(to: UInt8.self, capacity: count)
        return (0..<(width * height)).map { buffer[$0 * 4 + 3] }
    }

    private func hasOpaquePixel(_ alpha: [UInt8], near point: CGPoint, radius: Int) -> Bool {
        let cx = Int(point.x)
        let cy = Int(point.y)
        for dy in -radius...radius {
            for dx in -radius...radius {
                let x = cx + dx
                let y = cy + dy
                guard x >= 0, x < width, y >= 0, y < height else { continue }
                if alpha[y * width + x] > 0 { return true }
            }
        }
        return false
    }
}
