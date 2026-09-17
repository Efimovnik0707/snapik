// Port of `tests/Snapik.App.Imaging.Tests/EditorGeometryTests.cs:14-58` (SPEC-DELTA-4 §6):
// the six facts behind the scaled view of the editor.
import CoreGraphics
import Foundation
import XCTest

@testable import SnapikMac

final class EditorGeometryTests: XCTestCase {
    // The box a 1920×1080 monitor at 125 % leaves the editor: 1198×593 points, the numbers the
    // analysis of this round was written against.
    private let boxWidth: Double = 1198
    private let boxHeight: Double = 593

    func test_aCaptureOfTwoMonitorsIsFittedByItsWidth() {
        XCTAssertEqual(
            0.312,
            EditorGeometry.fit(imageWidth: 3840, imageHeight: 1125, boxWidth: boxWidth, boxHeight: boxHeight),
            accuracy: 0.0005)
    }

    func test_aTallImportedFileIsFittedByItsHeight() {
        XCTAssertEqual(
            0.247,
            EditorGeometry.fit(imageWidth: 1080, imageHeight: 2400, boxWidth: boxWidth, boxHeight: boxHeight),
            accuracy: 0.0005)
    }

    func test_aCaptureSmallerThanTheBoxIsNotScaled() {
        XCTAssertEqual(
            1, EditorGeometry.fit(imageWidth: 100, imageHeight: 100, boxWidth: boxWidth, boxHeight: boxHeight))
    }

    func test_theOffsetNeverLetsAnEdgeOfThePictureInsideTheViewport() {
        let image = CGSize(width: 3840, height: 1125)
        let viewport = CGSize(width: 1200, height: 600)
        // Dragged past the left edge and past the right one: both stop where the picture ends.
        XCTAssertEqual(
            CGPoint(x: 0, y: 0),
            EditorGeometry.clampOffset(image: image, scale: 1, viewport: viewport, offset: CGPoint(x: -400, y: -400)))
        XCTAssertEqual(
            CGPoint(x: 2640, y: 525),
            EditorGeometry.clampOffset(image: image, scale: 1, viewport: viewport, offset: CGPoint(x: 9000, y: 9000)))
        XCTAssertEqual(
            CGPoint(x: 1000, y: 300),
            EditorGeometry.clampOffset(image: image, scale: 1, viewport: viewport, offset: CGPoint(x: 1000, y: 300)))
    }

    func test_anAxisShorterThanTheViewportIsCentred() {
        // 3840×1125 at a quarter is 960×281: both sides are shorter than the viewport, so whatever
        // the offset was, the picture stands in the middle of it.
        let offset = EditorGeometry.clampOffset(
            image: CGSize(width: 3840, height: 1125), scale: 0.25, viewport: CGSize(width: 1200, height: 600),
            offset: CGPoint(x: 500, y: -500))
        XCTAssertEqual(CGPoint(x: -120, y: -159.375), offset)
    }

    func test_thePointUnderTheCursorStaysWhereItIsWhileTheScaleChanges() {
        let image = CGSize(width: 3840, height: 1125)
        // A viewport both sides of the picture are longer than: with an axis at its end the clamp is
        // what holds the picture, and the point under the cursor is allowed to travel.
        let viewport = CGSize(width: 1200, height: 400)
        let cursor = CGPoint(x: 800, y: 200)
        let from: Double = 0.5
        let offset = EditorGeometry.clampOffset(image: image, scale: from, viewport: viewport, offset: CGPoint(x: 400, y: 100))
        // The pixel of the capture the cursor stands on before the wheel is turned.
        let before = CGPoint(x: Double(cursor.x + offset.x) / from, y: Double(cursor.y + offset.y) / from)
        let to = from * 1.1
        let zoomed = EditorGeometry.clampOffset(
            image: image, scale: to, viewport: viewport,
            offset: EditorGeometry.zoomAround(cursor: cursor, offset: offset, fromScale: from, toScale: to))
        let after = CGPoint(x: Double(cursor.x + zoomed.x) / to, y: Double(cursor.y + zoomed.y) / to)
        XCTAssertEqual(Double(before.x), Double(after.x), accuracy: 0.05)
        XCTAssertEqual(Double(before.y), Double(after.y), accuracy: 0.05)
        XCTAssertLessThanOrEqual(hypot(before.x - after.x, before.y - after.y), 0.5)
    }

    // MARK: - Where the capture stands (`EditorGeometryTests.cs:72-123`)

    // The working area of a 1920×1080 monitor at 125 %, the one every number of this round was
    // written against, and the panel one row tall and two rows tall.
    private let work = CGRect(x: 0, y: 0, width: 1536, height: 824)
    private let oneRowPanel = CGSize(width: 1000, height: 50)
    private let twoRowPanel = CGSize(width: 780, height: 94)

    func test_aCaptureThatFitsUnderThePanelOpensAtItsOwnSize() {
        // 1420 fits 1536 - 16 and 700 fits 824 - 16 - 50 - 10: the capture that opened at 85 %.
        let placed = EditorGeometry.placeCapture(
            image: CGSize(width: 1420, height: 700), work: work, panel: oneRowPanel)
        XCTAssertEqual(CGSize(width: 1420, height: 700), placed.size)
    }

    func test_aCaptureTooTallForTheRoomLeftByThePanelIsFittedByItsHeight() {
        let placed = EditorGeometry.placeCapture(
            image: CGSize(width: 1420, height: 900), work: work, panel: oneRowPanel)
        XCTAssertEqual(748, Double(placed.height), accuracy: 0.001)
        XCTAssertEqual(1420 * (748.0 / 900.0), Double(placed.width), accuracy: 0.001)
    }

    func test_aCaptureOfTwoMonitorsIsFittedByItsWidthIntoTheWorkingArea() {
        let placed = EditorGeometry.placeCapture(
            image: CGSize(width: 3840, height: 1125), work: work, panel: oneRowPanel)
        XCTAssertEqual(1520, Double(placed.width), accuracy: 0.001)
    }

    func test_aSecondRowOfThePanelTakesTheCaptureOffItsOwnSize() {
        // 720 fits under one row (824 - 16 - 50 - 10 = 748) and does not fit under two
        // (824 - 16 - 94 - 10 = 704), which is the honest border between the two shapes.
        XCTAssertEqual(
            CGSize(width: 1420, height: 720),
            EditorGeometry.placeCapture(
                image: CGSize(width: 1420, height: 720), work: work, panel: oneRowPanel).size)
        XCTAssertLessThan(
            EditorGeometry.placeCapture(
                image: CGSize(width: 1420, height: 720), work: work, panel: twoRowPanel).height, 720)
    }

    func test_theCommentsPanelTakesItsWidthOffTheCapture() {
        // The working area the editor counts with the comments panel out: 797 wide.
        let narrow = CGRect(x: 0, y: 0, width: 797, height: 576)
        let placed = EditorGeometry.placeCapture(
            image: CGSize(width: 900, height: 400), work: narrow, panel: oneRowPanel)
        XCTAssertLessThan(placed.width, 900)
        XCTAssertEqual(781, Double(placed.width), accuracy: 0.001)
    }

    func test_theCaptureKeepsItsMarginAndTheRoomThePanelNeeds() {
        let images = [
            CGSize(width: 1420, height: 700), CGSize(width: 3840, height: 1125),
            CGSize(width: 1080, height: 2400), CGSize(width: 80, height: 60),
        ]
        for image in images {
            let placed = EditorGeometry.placeCapture(image: image, work: work, panel: oneRowPanel)
            XCTAssertGreaterThanOrEqual(Double(placed.minX), Double(work.minX) - 0.001)
            XCTAssertLessThanOrEqual(Double(placed.maxX), Double(work.maxX) + 0.001)
            XCTAssertGreaterThanOrEqual(Double(placed.minY), Double(work.minY) + 8 - 0.001)
            XCTAssertLessThanOrEqual(
                Double(placed.maxY) + 10 + Double(oneRowPanel.height), Double(work.maxY) + 0.001)
        }
    }
}
