// Port of `tests/Snapik.App.Imaging.Tests/EditorGeometryTests.cs:125-170`,
// SPEC-DELTA-5-editor.md §4.1.
//
// How many rows the markup panel takes, and where it goes when there is nowhere outside to go.
import CoreGraphics
import XCTest

@testable import SnapikMac

final class ToolbarLayoutTests: XCTestCase {
    // The blocks of the reference shot: the tools, the properties block of a fixed 176 and the
    // buttons on the right. 1077 is the free width without the comments panel, 781 with it.
    private let tools = CGSize(width: 430, height: 36)
    private let properties = CGSize(width: 176, height: 36)
    private let actions = CGSize(width: 220, height: 36)

    func test_thePanelWrapsOnlyWhenOneRowDoesNotFit() {
        XCTAssertEqual(
            ToolbarRows.one,
            ToolbarLayout.measure(tools: tools, properties: properties, actions: actions, freeWidth: 1077).rows)
        XCTAssertEqual(
            ToolbarRows.two,
            ToolbarLayout.measure(tools: tools, properties: properties, actions: actions, freeWidth: 781).rows)
    }

    func test_twoRowsAreTallerByARowAndTheGapBetweenThem() {
        let one = ToolbarLayout.measure(tools: tools, properties: properties, actions: actions, freeWidth: 1077)
        let two = ToolbarLayout.measure(tools: tools, properties: properties, actions: actions, freeWidth: 781)
        XCTAssertEqual(one.size.height + 36 + 7, two.size.height)
        XCTAssertLessThanOrEqual(two.size.width, 781)
    }

    func test_theNumberOfRowsDoesNotDependOnTheToolInHand() {
        // The properties block is one width for every tool, so the shape of the panel is one too.
        for height in [CGFloat(30), 36, 40] {
            XCTAssertEqual(
                ToolbarRows.one,
                ToolbarLayout.measure(
                    tools: tools, properties: CGSize(width: 176, height: height),
                    actions: actions, freeWidth: 1077).rows)
        }
    }

    func test_aPanelThatHasNowhereOutsideToGoStaysOffTheCaptureUnlessItMayOverlap() {
        let work = CGRect(x: 0, y: 0, width: 1536, height: 824)
        let crop = CGRect(x: 0, y: 0, width: 1536, height: 824)
        let size = CGSize(width: 460, height: 50)
        XCTAssertFalse(
            EditorGeometry.placeToolbar(crop: crop, work: work, size: size, notes: [], mayOverlap: false)
                .intersects(CGRect(x: 0, y: 0, width: 1536, height: 760)))
        XCTAssertTrue(
            EditorGeometry.placeToolbar(crop: crop, work: work, size: size, notes: [], mayOverlap: true)
                .intersects(crop))
    }

    func test_thePanelGoesUnderTheCaptureWhileThereIsRoomForIt() {
        let work = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let crop = CGRect(x: 500, y: 400, width: 540, height: 120)
        let placed = EditorGeometry.placeToolbar(
            crop: crop, work: work, size: CGSize(width: 460, height: 50), notes: [], mayOverlap: false)
        XCTAssertEqual(crop.maxY + 10, placed.minY)
        XCTAssertFalse(placed.intersects(crop))
    }
}
