// Port of `tests/Snapik.App.Imaging.Tests/StripResizeGeometryTests.cs`, SPEC-DELTA-3 §1.3 S-9.
//
// The widths are the ones of 1.5.0: 244 is both the default and the floor, because the field under
// the shadow grew to 20 and the panel behind it stays 204 (SPEC-DELTA-4 §2.5). The heights are the
// same numbers on both sides.
import XCTest

@testable import SnapikCore

final class StripResizeGeometryTests: XCTestCase {
    func test_Dragging_the_left_edge_keeps_the_right_edge_where_it_was() {
        // Both widths stay above the minimum, which is 244 since the field under the shadow grew:
        // a drag that runs into the floor is the case right below this one.
        let grown = StripResizeGeometry.widthFromStart(right: 1920, startWidth: 300, pointerDelta: -40, leftLimit: 0)
        XCTAssertEqual(1580, grown.left)
        XCTAssertEqual(340, grown.width)

        let shrunk = StripResizeGeometry.widthFromStart(right: 1920, startWidth: 300, pointerDelta: 40, leftLimit: 0)
        XCTAssertEqual(1660, shrunk.left)
        XCTAssertEqual(260, shrunk.width)
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
            // A width stored by a build whose minimum was 200, 208 or 224 is lifted to the new one:
            // the panel it stood for is narrower than the one the strip draws now.
            (240, 1920, StripResizeGeometry.minimumWidth),
            (400, 1920, 400),
            (40, 1920, StripResizeGeometry.minimumWidth),
            // The working area less the gap at the edge is the ceiling, on both screens; the gap is
            // nil now, because the field under the shadow is what stands between panel and edge.
            (5000, 1920, 1920),
            // A width dragged out on a large monitor, opened on a laptop.
            (1600, 1366, 1366),
            (.nan, 1920, StripResizeGeometry.defaultWidth),
            // No screen to ask yet: the default stands, and the minimum is still a floor.
            (40, 0, StripResizeGeometry.minimumWidth),
        ]
        for (stored, workWidth, expected) in cases {
            XCTAssertEqual(
                expected, StripResizeGeometry.clampWidth(stored, workWidth: workWidth), "\(stored) \(workWidth)")
        }
    }

    // MARK: - The list by its contents (SPEC-DELTA-5 §1.10)

    /// The stored number is the ceiling and not the height: an empty strip is the hint alone, one
    /// card is 100 and every card after it adds the pitch. The minimum of 180 is no floor here — it
    /// belongs to the stored number, and a single capture opens a list of 100.
    func test_The_list_is_as_tall_as_what_it_holds_and_stops_at_the_ceiling() {
        let cases: [(Int, Double, Double)] = [
            (0, StripResizeGeometry.defaultListHeight, 92),
            (1, StripResizeGeometry.defaultListHeight, 100),
            (2, StripResizeGeometry.defaultListHeight, 130),
            (5, StripResizeGeometry.defaultListHeight, 220),
            // Twelve cards want 430 and the default ceiling holds them at 372.
            (12, StripResizeGeometry.defaultListHeight, 372),
            (12, 500, 430),
            (12, 130, 130),
            // A ceiling that is nonsense falls back to the default one.
            (12, .nan, 372),
        ]
        for (count, cap, expected) in cases {
            XCTAssertEqual(
                expected, StripResizeGeometry.listHeightForCount(count, cap: cap), "\(count) \(cap)")
        }
    }

    /// Dragged by hand the stored number is the height itself, empty strip included; automatic it is
    /// the height of the contents, and the same number is only the ceiling.
    func test_A_height_dragged_by_hand_is_the_number_itself_and_an_automatic_one_is_the_contents() {
        let cases: [(Int, Double, Bool, Double)] = [
            (3, 310, true, 310),
            (3, 310, false, 160),
            (15, 310, true, 310),
            (0, 310, true, 310),
            (0, 310, false, 92),
        ]
        for (count, stored, manual, expected) in cases {
            XCTAssertEqual(
                expected, StripResizeGeometry.listHeight(count: count, stored: stored, manual: manual),
                "\(count) \(stored) \(manual)")
        }
    }

    /// The capsule keeps the right edge of the strip it came out of, not the edge of the monitor.
    func test_The_capsule_keeps_the_right_edge_of_the_strip() {
        XCTAssertEqual(
            1664, StripResizeGeometry.capsuleLeft(stripLeft: 1600, stripWidth: 244, capsuleWidth: 180))
    }

    /// A strip dragged away from the edge stays where it was left; only one that no longer fits is
    /// brought back, and a working area of no size at all moves nothing.
    func test_The_strip_comes_back_into_the_working_area_only_when_it_no_longer_fits() {
        let inside = StripResizeGeometry.restoreRect(
            x: 1600, y: 100, width: 244, height: 372,
            workX: 0, workY: 0, workWidth: 1920, workHeight: 1080)
        XCTAssertEqual(1600, inside.x)
        XCTAssertEqual(100, inside.y)

        let outside = StripResizeGeometry.restoreRect(
            x: 1800, y: 900, width: 244, height: 372,
            workX: 0, workY: 0, workWidth: 1920, workHeight: 1080)
        XCTAssertEqual(1676, outside.x)
        XCTAssertEqual(708, outside.y)

        let noScreen = StripResizeGeometry.restoreRect(
            x: 1800, y: 900, width: 244, height: 372,
            workX: 0, workY: 0, workWidth: 0, workHeight: 0)
        XCTAssertEqual(1800, noScreen.x)
        XCTAssertEqual(900, noScreen.y)
    }
}
