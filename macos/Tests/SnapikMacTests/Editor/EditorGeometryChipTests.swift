// Port of the geometry assertions behind SPEC-DELTA-2.md §1.3's `FindChipPlacement`/
// `FindMoveEdge`, SPEC-DELTA-2B.md §F ("`findChipPlacement` без пересечений, `findMoveEdge`").
import CoreGraphics
import Foundation
import XCTest

@testable import SnapikMac

final class EditorGeometryChipTests: XCTestCase {
    private let work = CGRect(x: 0, y: 0, width: 1200, height: 800)
    private let chipSize = CGSize(width: 270, height: 90)

    // MARK: - findChipPlacement

    func test_findChipPlacement_usesPreferredWhenFree() {
        let preferred = CGPoint(x: 200, y: 200)
        let rect = EditorGeometry.findChipPlacement(preferred: preferred, size: chipSize, work: work, occupied: [])
        XCTAssertEqual(rect.origin, preferred)
        XCTAssertEqual(rect.size, chipSize)
    }

    func test_findChipPlacement_spiralsAwayFromOccupiedRect() {
        let preferred = CGPoint(x: 200, y: 200)
        let occupied = CGRect(origin: preferred, size: chipSize)
        let rect = EditorGeometry.findChipPlacement(preferred: preferred, size: chipSize, work: work, occupied: [occupied])
        XCTAssertFalse(occupied.insetBy(dx: -6, dy: -6).intersects(rect))
        XCTAssertTrue(work.contains(rect))
    }

    func test_findChipPlacement_manyChipsNeverOverlap() {
        // 5 chips all preferring nearly the same spot; the work area is generously sized so the
        // spiral always finds room well within its 14-ring budget.
        var occupied: [CGRect] = []
        for i in 0..<5 {
            let preferred = CGPoint(x: 400 + CGFloat(i) * 3, y: 400 + CGFloat(i) * 3)
            let rect = EditorGeometry.findChipPlacement(preferred: preferred, size: chipSize, work: work, occupied: occupied)
            for existing in occupied {
                XCTAssertFalse(existing.insetBy(dx: -6, dy: -6).intersects(rect), "chip \(i) overlaps an earlier chip")
            }
            occupied.append(rect)
        }
    }

    func test_findChipPlacement_clampsIntoWorkArea() {
        let preferred = CGPoint(x: -500, y: -500)
        let rect = EditorGeometry.findChipPlacement(preferred: preferred, size: chipSize, work: work, occupied: [])
        XCTAssertGreaterThanOrEqual(rect.minX, work.minX)
        XCTAssertGreaterThanOrEqual(rect.minY, work.minY)
        XCTAssertLessThanOrEqual(rect.maxX, work.maxX)
        XCTAssertLessThanOrEqual(rect.maxY, work.maxY)
    }

    // MARK: - findMoveEdge

    func test_findMoveEdge_hitsTheBorderBand() {
        let bounds = CGRect(x: 100, y: 100, width: 200, height: 150)
        XCTAssertTrue(EditorGeometry.findMoveEdge(displayBounds: bounds, point: CGPoint(x: bounds.midX, y: bounds.minY)))
        XCTAssertTrue(EditorGeometry.findMoveEdge(displayBounds: bounds, point: CGPoint(x: bounds.minX, y: bounds.midY)))
    }

    func test_findMoveEdge_missesTheInterior() {
        let bounds = CGRect(x: 100, y: 100, width: 200, height: 150)
        XCTAssertFalse(EditorGeometry.findMoveEdge(displayBounds: bounds, point: CGPoint(x: bounds.midX, y: bounds.midY)))
    }

    func test_findMoveEdge_missesOutsideTheOuterRing() {
        let bounds = CGRect(x: 100, y: 100, width: 200, height: 150)
        XCTAssertFalse(EditorGeometry.findMoveEdge(displayBounds: bounds, point: CGPoint(x: bounds.minX - 20, y: bounds.midY)))
    }

    func test_findMoveEdge_tinyRect_insetNeverExceedsHalfSize() {
        // `min(6, w/2)`/`min(6, h/2)`: a rect smaller than 12x12 must still have a non-inverted
        // inner ring (SPEC-DELTA-2B.md §C3).
        let bounds = CGRect(x: 50, y: 50, width: 4, height: 4)
        XCTAssertTrue(EditorGeometry.findMoveEdge(displayBounds: bounds, point: CGPoint(x: bounds.midX, y: bounds.midY)))
    }
}
