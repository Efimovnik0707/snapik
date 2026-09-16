// Port of `tests/Snapik.App.Imaging.Tests/ShapeMaskTests.cs`, SPEC-DELTA-3 §6.
import CoreGraphics
import Foundation
import SnapikCore
import XCTest

@testable import SnapikMac

final class ShapeMaskTests: XCTestCase {
    func test_coverageOfARectangleIsWholeEverywhereInItsBox() {
        XCTAssertEqual(1, ShapeMask.coverage(.rectangle, width: 100, height: 60, x: 0, y: 0))
        XCTAssertEqual(1, ShapeMask.coverage(.rectangle, width: 100, height: 60, x: 50, y: 30))
        XCTAssertEqual(1, ShapeMask.coverage(.rectangle, width: 100, height: 60, x: 99, y: 59))
    }

    func test_coverageOfAnEllipseIsWholeInTheCentreAndNoneInTheCornerOfItsBox() {
        XCTAssertEqual(1, ShapeMask.coverage(.ellipse, width: 100, height: 60, x: 50, y: 30))
        XCTAssertEqual(0, ShapeMask.coverage(.ellipse, width: 100, height: 60, x: 0, y: 0))
        XCTAssertEqual(0, ShapeMask.coverage(.ellipse, width: 100, height: 60, x: 99, y: 59))
    }

    func test_coverageOfAnEllipseFadesOverOnePixelAtItsEdge() {
        // The edge is smoothed by the signed distance, so an oval blur does not come out jagged: the
        // partly covered pixels form a band one pixel wide along the outline, and nowhere else.
        var partial = 0
        for y in 0..<60 {
            for x in 0..<100 {
                let coverage = ShapeMask.coverage(.ellipse, width: 100, height: 60, x: Double(x), y: Double(y))
                if coverage > 0.05 && coverage < 0.95 { partial += 1 }
            }
        }
        XCTAssertGreaterThanOrEqual(partial, 60)
        XCTAssertLessThanOrEqual(partial, 600)
    }

    func test_coverageOfARoundedFrameCutsOnlyItsCorners() {
        XCTAssertEqual(1, ShapeMask.coverage(.rounded, width: 100, height: 60, x: 50, y: 30))
        // The middle of every side stays inside, only the corners are taken away.
        XCTAssertEqual(1, ShapeMask.coverage(.rounded, width: 100, height: 60, x: 50, y: 0))
        XCTAssertEqual(1, ShapeMask.coverage(.rounded, width: 100, height: 60, x: 0, y: 30))
        XCTAssertEqual(0, ShapeMask.coverage(.rounded, width: 100, height: 60, x: 0, y: 0))
    }

    func test_cornerRadiusFollowsTheShorterSideUpToFourteenPixels() {
        XCTAssertEqual(14, ShapeMask.cornerRadius(width: 100, height: 60))
        XCTAssertEqual(5, ShapeMask.cornerRadius(width: 40, height: 20))
        XCTAssertEqual(2, ShapeMask.cornerRadius(width: 8, height: 200))
    }

    func test_coverageOfAnEmptyBoxIsNone() {
        XCTAssertEqual(0, ShapeMask.coverage(.ellipse, width: 0, height: 60, x: 0, y: 0))
        XCTAssertEqual(0, ShapeMask.coverage(.rectangle, width: 100, height: 0, x: 0, y: 0))
    }
}
