// Port of `tests/Snapik.App.Imaging.Tests/NoteBadgeGeometryTests.cs:23-68, 74-116`,
// SPEC-DELTA-5-editor.md §4.1.
//
// The field the exported picture needs so that a badge dragged off the capture is not cut away,
// and the leader between a mark and the badge dragged off it.
import CoreGraphics
import SnapikCore
import XCTest

@testable import SnapikMac

final class NoteBadgeGeometryTests: XCTestCase {
    private let side = 1000

    /// The badge of a one-digit number: 34 px across, so 17 of radius, and 8 of padding beside it.
    private let reach = 17 + 8

    /// And it stands above the point it belongs to, by half a diameter and the gap of four.
    private let lift = 17 + 4

    private func margins(
        _ badges: [(anchor: NormalizedPoint, offset: NormalizedPoint?, label: String)]
    ) -> ExportMargin {
        NoteBadgeGeometry.exportMargins(badges: badges, width: side, height: side)
    }

    func test_A_capture_without_badges_needs_no_field() {
        XCTAssertTrue(NoteBadgeGeometry.exportMargins(badges: [], width: side, height: side).isEmpty)
    }

    func test_A_badge_left_where_it_was_born_inside_the_capture_needs_no_field() {
        XCTAssertEqual(
            ExportMargin.none,
            margins([(anchor: NormalizedPoint(0.5, 0.5), offset: nil, label: "1")]))
    }

    /// Nothing has to be dragged for a badge to hang over the edge: it is drawn above its own point,
    /// and a comment put near the top of the capture reaches over it by itself.
    func test_A_badge_that_was_never_moved_still_asks_for_the_room_it_hangs_over() {
        XCTAssertEqual(
            ExportMargin(left: 0, top: reach + lift - 10, right: 0, bottom: 0),
            margins([(anchor: NormalizedPoint(0.5, 0.01), offset: nil, label: "1")]))
    }

    func test_A_badge_moved_inside_the_capture_needs_no_field() {
        XCTAssertEqual(
            ExportMargin.none,
            margins([(anchor: NormalizedPoint(0.4, 0.5), offset: NormalizedPoint(0.1, 0.1), label: "1")]))
    }

    func test_A_badge_dragged_off_the_left_edge_asks_for_a_field_on_the_left() {
        XCTAssertEqual(
            ExportMargin(left: 100 + reach, top: 0, right: 0, bottom: 0),
            margins([(anchor: NormalizedPoint(0, 0.5), offset: NormalizedPoint(-0.1, 0), label: "1")]))
    }

    func test_A_badge_dragged_off_the_right_edge_asks_for_a_field_on_the_right() {
        XCTAssertEqual(
            ExportMargin(left: 0, top: 0, right: 100 + reach, bottom: 0),
            margins([(anchor: NormalizedPoint(1, 0.5), offset: NormalizedPoint(0.1, 0), label: "1")]))
    }

    func test_A_badge_dragged_above_the_capture_asks_for_a_field_on_top() {
        XCTAssertEqual(
            ExportMargin(left: 0, top: 100 + reach + lift, right: 0, bottom: 0),
            margins([(anchor: NormalizedPoint(0.5, 0), offset: NormalizedPoint(0, -0.1), label: "1")]))
    }

    func test_Two_badges_pulled_apart_ask_for_a_field_on_both_sides() {
        XCTAssertEqual(
            ExportMargin(left: 100 + reach, top: 0, right: 50 + reach, bottom: 0),
            margins([
                (anchor: NormalizedPoint(0, 0.5), offset: NormalizedPoint(-0.1, 0), label: "1"),
                (anchor: NormalizedPoint(1, 0.5), offset: NormalizedPoint(0.05, 0), label: "2"),
            ]))
    }

    func test_A_comment_without_a_number_carries_no_badge_and_asks_for_nothing() {
        XCTAssertEqual(
            ExportMargin.none,
            margins([(anchor: NormalizedPoint(0, 0.5), offset: NormalizedPoint(-0.1, 0), label: "")]))
    }

    func test_A_longer_number_asks_for_a_wider_field() {
        let one = margins([(anchor: NormalizedPoint(0, 0.5), offset: NormalizedPoint(-0.1, 0), label: "1")])
        // "10" is 9 px per character plus 16, which is still under the floor of 34; "1234567" is not.
        let many = margins([(anchor: NormalizedPoint(0, 0.5), offset: NormalizedPoint(-0.1, 0), label: "1234567")])
        XCTAssertGreaterThan(many.left, one.left)
    }

    // The leader between a mark and the badge dragged off it. A frame starts it on its own outline,
    // a comment on the rim of its dot; both stop on the rim of the badge.

    func test_The_leader_of_a_frame_starts_on_its_outline() throws {
        let bounds = CGRect(x: 100, y: 100, width: 100, height: 60)
        let badge = NoteBadge(center: CGPoint(x: 400, y: 40), radius: 17)
        let leader = try XCTUnwrap(NoteBadgeGeometry.leader(bounds: bounds, badge: badge))
        XCTAssertEqual(Double(bounds.maxX), Double(leader.from.x), accuracy: 0.000001)
        XCTAssertEqual(Double(bounds.minY), Double(leader.from.y), accuracy: 0.000001)
    }

    func test_The_leader_of_a_comment_starts_on_the_rim_of_its_dot() throws {
        let anchor = CGPoint(x: 200, y: 200)
        let badge = NoteBadge(center: CGPoint(x: 300, y: 120), radius: 17)
        let leader = try XCTUnwrap(
            NoteBadgeGeometry.leader(bounds: CGRect(origin: anchor, size: .zero), badge: badge, fromRadius: 5))
        let started = hypot(leader.from.x - anchor.x, leader.from.y - anchor.y)
        XCTAssertEqual(5, Double(started), accuracy: 0.000001)
        let toBadge = hypot(badge.center.x - anchor.x, badge.center.y - anchor.y)
        XCTAssertEqual(
            Double((badge.center.x - anchor.x) / toBadge),
            Double((leader.from.x - anchor.x) / started), accuracy: 0.000001)
        XCTAssertEqual(
            Double((badge.center.y - anchor.y) / toBadge),
            Double((leader.from.y - anchor.y) / started), accuracy: 0.000001)
    }

    func test_The_leader_stops_on_the_rim_of_the_badge() throws {
        let badge = NoteBadge(center: CGPoint(x: 300, y: 120), radius: 17)
        let leader = try XCTUnwrap(
            NoteBadgeGeometry.leader(bounds: CGRect(x: 100, y: 100, width: 100, height: 60), badge: badge))
        XCTAssertEqual(
            Double(badge.radius),
            Double(hypot(badge.center.x - leader.to.x, badge.center.y - leader.to.y)), accuracy: 0.000001)
    }

    /// A badge almost on top of its dot leaves no room for a line; drawn anyway it would turn inside
    /// out.
    func test_A_leader_shorter_than_the_badge_and_the_dot_is_not_drawn() {
        let anchor = CGPoint(x: 200, y: 200)
        let badge = NoteBadge(center: CGPoint(x: 218, y: 200), radius: 17)
        XCTAssertNil(
            NoteBadgeGeometry.leader(bounds: CGRect(origin: anchor, size: .zero), badge: badge, fromRadius: 5))
    }

    func test_The_exported_dot_grows_by_the_same_scale_as_the_leader() {
        XCTAssertEqual(
            Double(NoteBadgeGeometry.exportLeaderThickness("1")),
            Double(NoteBadgeGeometry.exportScale("1")), accuracy: 0.000001)
        XCTAssertGreaterThan(NoteBadgeGeometry.exportScale("1"), 1)
    }
}
