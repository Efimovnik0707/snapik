import XCTest

@testable import SnapBriefCore

/// Port of `tests/SnapBrief.App.Imaging.Tests/ResizeGeometryTests.cs`. Tests 19-24 (SPEC §8.2).
final class ResizeGeometryTests: XCTestCase {
    private let original = GeometryRect(20, 30, 100, 90)
    private let limit = GeometryRect(0, 0, 200, 200)

    /// Test 19: `EachCornerKeepsOppositeCornerFixed(corner=0)`.
    func test_19_EachCornerKeepsOppositeCornerFixed_corner0() {
        let result = ResizeGeometry.resize(original: original, corner: 0, point: GeometryPoint(10, 15), limit: limit, minimum: 12)
        XCTAssertEqual(GeometryRect(10, 15, 110, 105), result)
    }

    /// Test 20: `EachCornerKeepsOppositeCornerFixed(corner=1)`.
    func test_20_EachCornerKeepsOppositeCornerFixed_corner1() {
        let result = ResizeGeometry.resize(original: original, corner: 1, point: GeometryPoint(180, 15), limit: limit, minimum: 12)
        XCTAssertEqual(GeometryRect(20, 15, 160, 105), result)
    }

    /// Test 21: `EachCornerKeepsOppositeCornerFixed(corner=2)`.
    func test_21_EachCornerKeepsOppositeCornerFixed_corner2() {
        let result = ResizeGeometry.resize(original: original, corner: 2, point: GeometryPoint(180, 170), limit: limit, minimum: 12)
        XCTAssertEqual(GeometryRect(20, 30, 160, 140), result)
    }

    /// Test 22: `EachCornerKeepsOppositeCornerFixed(corner=3)`.
    func test_22_EachCornerKeepsOppositeCornerFixed_corner3() {
        let result = ResizeGeometry.resize(original: original, corner: 3, point: GeometryPoint(10, 170), limit: limit, minimum: 12)
        XCTAssertEqual(GeometryRect(10, 30, 110, 140), result)
    }

    /// Test 23: `ResizeClampsToCapturedPixelsAndPreventsInversion`.
    func test_23_ResizeClampsToCapturedPixelsAndPreventsInversion() {
        let expanded = ResizeGeometry.resize(original: original, corner: 2, point: GeometryPoint(500, 500), limit: limit, minimum: 12)
        XCTAssertEqual(GeometryRect(20, 30, 180, 170), expanded)

        let shrunk = ResizeGeometry.resize(original: original, corner: 0, point: GeometryPoint(500, 500), limit: limit, minimum: 12)
        XCTAssertEqual(GeometryRect(108, 108, 12, 12), shrunk)
    }

    /// Test 24: `CornerHitUsesDisplayPixelsAndMapsAllPathPoints`.
    func test_24_CornerHitUsesDisplayPixelsAndMapsAllPathPoints() {
        XCTAssertEqual(0, ResizeGeometry.hitCorner(bounds: original, point: GeometryPoint(23, 33), radius: 10))
        XCTAssertEqual(-1, ResizeGeometry.hitCorner(bounds: original, point: GeometryPoint(70, 75), radius: 10))
        XCTAssertEqual(
            GeometryPoint(100, 100),
            ResizeGeometry.map(GeometryPoint(70, 75), original: original, resized: GeometryRect(0, 0, 200, 200)))
    }
}
