// Port of `tests/Snapik.App.Imaging.Tests/StripResizeGeometryTests.cs`, SPEC-DELTA-3 §1.3 S-9.
//
// The widths are the ones of this round: 224 is both the default and the floor ([ТЗ№4 C4]), where
// Windows 1.4.0 still carries 208 and 200. The heights are the same numbers on both sides.
import XCTest

@testable import SnapikCore

final class StripResizeGeometryTests: XCTestCase {
    func test_Dragging_the_left_edge_keeps_the_right_edge_where_it_was() {
        let grown = StripResizeGeometry.widthFromStart(right: 1920, startWidth: 260, pointerDelta: -40, leftLimit: 0)
        XCTAssertEqual(1620, grown.left)
        XCTAssertEqual(300, grown.width)

        // 220 is below the floor of this round, so the strip stops at 224 instead.
        let shrunk = StripResizeGeometry.widthFromStart(right: 1920, startWidth: 260, pointerDelta: 40, leftLimit: 0)
        XCTAssertEqual(1696, shrunk.left)
        XCTAssertEqual(StripResizeGeometry.minimumWidth, shrunk.width)
    }

    /// A drag far past the left edge of a 1920 working area stops at that edge, not at a number.
    func test_The_width_stops_at_the_working_area_and_at_the_minimum() {
        for (delta, expected) in [(-2000.0, 1920.0), (1000.0, StripResizeGeometry.minimumWidth)] {
            let result = StripResizeGeometry.widthFromStart(
                right: 1920, startWidth: 260, pointerDelta: delta, leftLimit: 0)
            XCTAssertEqual(expected, result.width)
            XCTAssertEqual(1920 - expected, result.left)
        }
    }

    func test_The_strip_stretches_to_half_of_the_screen() {
        // The strip sits at the right edge of a 1920 screen, the grip travels 700 points to the left.
        let result = StripResizeGeometry.widthFromStart(
            right: 1910, startWidth: 260, pointerDelta: -700, leftLimit: 0)

        XCTAssertEqual(960, result.width)
        XCTAssertEqual(950, result.left)
    }

    func test_The_strip_does_not_grow_past_the_left_edge_of_the_working_area() {
        let result = StripResizeGeometry.widthFromStart(
            right: 1500, startWidth: 260, pointerDelta: -1000, leftLimit: 1250)

        XCTAssertEqual(250, result.width)
        XCTAssertEqual(1250, result.left)
    }

    /// The pointer runs 2000 points to the left, where the strip stops at the edge of a 1920 working
    /// area, and then gives 1720 of that travel back. Counted from the start of the drag the strip
    /// answers at once; counted from the width of the moment it would owe the whole run first, and
    /// that debt is the dead zone the strip was reported to have.
    func test_A_pointer_on_its_way_back_from_a_clamp_resizes_on_the_first_pixel() {
        let stopped = StripResizeGeometry.widthFromStart(
            right: 1920, startWidth: 260, pointerDelta: -2000, leftLimit: 0)
        let released = StripResizeGeometry.widthFromStart(
            right: 1920, startWidth: 260, pointerDelta: -280, leftLimit: 0)

        XCTAssertEqual(1920, stopped.width)
        XCTAssertEqual(540, released.width)

        // The same for the height: the list fills a 2000 working area, then the pointer comes back.
        XCTAssertEqual(
            1900,
            StripResizeGeometry.listHeightFromStart(
                startListHeight: 372, pointerDelta: 2000, chromeHeight: 100, top: 0, workBottom: 2000))
        XCTAssertEqual(
            412,
            StripResizeGeometry.listHeightFromStart(
                startListHeight: 372, pointerDelta: 40, chromeHeight: 100, top: 0, workBottom: 2000))
    }

    func test_A_pointer_delta_of_nonsense_leaves_the_geometry_of_the_start_alone() {
        let result = StripResizeGeometry.widthFromStart(
            right: 1920, startWidth: 260, pointerDelta: .nan, leftLimit: 0)
        XCTAssertEqual(1660, result.left)
        XCTAssertEqual(260, result.width)

        XCTAssertEqual(
            372,
            StripResizeGeometry.listHeightFromStart(
                startListHeight: 372, pointerDelta: .nan, chromeHeight: 100, top: 0, workBottom: 2000))
    }

    /// 100 of the working area below the strip is the chrome of the window, so the list may take the
    /// rest of it; a drag of 60 points takes 60 points of that.
    func test_Dragging_the_corner_down_grows_the_list_and_leaves_the_top_edge_alone() {
        XCTAssertEqual(
            432,
            StripResizeGeometry.listHeightFromStart(
                startListHeight: 372, pointerDelta: 60, chromeHeight: 100, top: 200, workBottom: 1040))
        XCTAssertEqual(
            312,
            StripResizeGeometry.listHeightFromStart(
                startListHeight: 372, pointerDelta: -60, chromeHeight: 100, top: 200, workBottom: 1040))
    }

    func test_The_list_height_stops_at_the_working_area_and_at_the_minimum() {
        let cases: [(Double, Double)] = [
            (-1000, StripResizeGeometry.minimumListHeight),
            // 2000 of working area less 100 of chrome is all the list may take.
            (2000, 1900),
        ]
        for (delta, expected) in cases {
            XCTAssertEqual(
                expected,
                StripResizeGeometry.listHeightFromStart(
                    startListHeight: 372, pointerDelta: delta, chromeHeight: 100, top: 0, workBottom: 2000))
        }
    }

    func test_The_list_stops_at_the_bottom_of_the_working_area() {
        // 1040 - 700 - 140 = 200 left for the list, even though the drag would allow more.
        XCTAssertEqual(
            200,
            StripResizeGeometry.listHeightFromStart(
                startListHeight: 372, pointerDelta: 500, chromeHeight: 140, top: 700, workBottom: 1040))
        // A strip that is already lower than its own chrome still gets a usable list.
        XCTAssertEqual(
            StripResizeGeometry.minimumListHeight,
            StripResizeGeometry.listHeightFromStart(
                startListHeight: 372, pointerDelta: 500, chromeHeight: 140, top: 1000, workBottom: 1040))
    }

    func test_A_stored_list_height_is_clamped_by_the_range_and_by_the_screen() {
        let cases: [(Double, Double, Double, Double)] = [
            (300, 1040, 130, 300),
            (40, 1040, 130, StripResizeGeometry.minimumListHeight),
            // The ceiling is the working area less the chrome, 910 here, and nothing below that.
            (1000, 1040, 130, 910),
            (900, 500, 130, 370),
            (.nan, 1040, 130, StripResizeGeometry.defaultListHeight),
            // A chrome taller than the screen still leaves a list somebody can use.
            (600, 300, 400, StripResizeGeometry.minimumListHeight),
            // Nothing measured yet: the estimate stands in for the chrome.
            (900, 728, 0, 728 - StripResizeGeometry.estimatedChromeHeight),
        ]
        for (stored, workHeight, chrome, expected) in cases {
            XCTAssertEqual(
                expected,
                StripResizeGeometry.clampListHeight(stored, workHeight: workHeight, chromeHeight: chrome),
                "\(stored) \(workHeight) \(chrome)")
        }
    }

    /// The laptop of the report: a working area of 728 points and a height of 720 stored on a big
    /// monitor. The window is the list plus its chrome, and all of it has to fit on the screen, or
    /// the corner grip that would bring it back is below the bottom edge.
    func test_A_stored_list_height_leaves_room_for_the_chrome_of_the_window() {
        let chrome: Double = 130
        let height = StripResizeGeometry.clampListHeight(720, workHeight: 728, chromeHeight: chrome)

        XCTAssertEqual(598, height)
        XCTAssertTrue(height + chrome <= 728)
    }

    func test_A_stored_width_is_clamped_by_the_screen_and_nonsense_falls_back() {
        let cases: [(Double, Double, Double)] = [
            (240, 1920, 240),
            (40, 1920, StripResizeGeometry.minimumWidth),
            // The working area less the gap at the edge is the ceiling, on both screens.
            (5000, 1920, 1910),
            // A width dragged out on a large monitor, opened on a laptop.
            (1600, 1366, 1356),
            (.nan, 1920, StripResizeGeometry.defaultWidth),
            // No screen to ask yet: the default stands, and the minimum is still a floor.
            (40, 0, StripResizeGeometry.minimumWidth),
        ]
        for (stored, workWidth, expected) in cases {
            XCTAssertEqual(
                expected, StripResizeGeometry.clampWidth(stored, workWidth: workWidth), "\(stored) \(workWidth)")
        }
    }
}
