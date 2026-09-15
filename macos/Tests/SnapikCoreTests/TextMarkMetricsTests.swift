// Port of `tests/Snapik.App.Imaging.Tests/TextMarkMetricsTests.cs`, SPEC-DELTA-3 §4, §6.
//
// The numbers are not the Windows ones: the family is the system one here and `Segoe UI Variable
// Text` there. What the facts hold on to is the shape of the box — wider than tall for a word,
// never shorter than the letters, growing with the size and with the number of them — and that is
// the same on both sides.
import XCTest

@testable import SnapikCore

final class TextMarkMetricsTests: XCTestCase {
    func test_Measure_gives_a_wide_box_for_a_word_and_at_least_the_height_of_the_letters() {
        let size = TextMarkMetrics.measure("Привет", fontSize: 32)

        XCTAssertTrue(
            size.width > size.height,
            "A word must be wider than it is tall, it measured \(size.width)x\(size.height).")
        XCTAssertTrue(size.height >= 32)
    }

    func test_Measure_reads_cyrillic_and_latin_alike() {
        let cyrillic = TextMarkMetrics.measure("Привет", fontSize: 20)
        let latin = TextMarkMetrics.measure("Hello", fontSize: 20)

        XCTAssertTrue(cyrillic.width > 0)
        XCTAssertTrue(latin.width > 0)
        XCTAssertTrue(TextMarkMetrics.measure("Привет, мир", fontSize: 20).width > cyrillic.width)
    }

    func test_Measure_of_nothing_is_still_a_box_with_room_for_a_caret() {
        let size = TextMarkMetrics.measure("", fontSize: 20)

        XCTAssertTrue(size.width > 0)
        XCTAssertTrue(size.height >= 20)
    }

    func test_Measure_grows_with_the_size_of_the_letters() {
        XCTAssertTrue(
            TextMarkMetrics.measure("Привет", fontSize: 48).width
                > TextMarkMetrics.measure("Привет", fontSize: 16).width)
    }

    func test_Clamp_brings_a_size_nobody_can_draw_back_into_range() {
        XCTAssertEqual(TextMarkMetrics.minimumFontSize, TextMarkMetrics.clamp(0))
        XCTAssertEqual(TextMarkMetrics.minimumFontSize, TextMarkMetrics.clamp(4))
        XCTAssertEqual(20, TextMarkMetrics.clamp(20))
        XCTAssertEqual(TextMarkMetrics.maximumFontSize, TextMarkMetrics.clamp(400))
    }

    func test_Clamp_takes_a_number_that_is_not_a_number_back_to_the_default() {
        XCTAssertEqual(TextMarkMetrics.defaultFontSize, TextMarkMetrics.clamp(Double.nan))
        XCTAssertEqual(TextMarkMetrics.defaultFontSize, TextMarkMetrics.clamp(.infinity))
    }

    func test_Every_preset_of_the_size_button_is_a_size_the_clamp_leaves_alone() {
        for preset in TextMarkMetrics.fontSizePresets {
            XCTAssertEqual(preset, TextMarkMetrics.clamp(preset))
        }
    }

    func test_Fit_puts_the_second_point_right_of_and_below_the_anchor_without_moving_it() {
        let anchor = GeometryPoint(40, 60)

        let fitted = TextMarkMetrics.fit(anchor: anchor, text: "Привет", fontSize: 24)

        XCTAssertEqual(GeometryPoint(40, 60), anchor)
        XCTAssertTrue(fitted.x > anchor.x)
        XCTAssertTrue(fitted.y > anchor.y)
    }

    func test_Fit_follows_the_size_of_the_letters_and_their_number() {
        let origin = GeometryPoint(0, 0)

        let small = TextMarkMetrics.fit(anchor: origin, text: "Привет", fontSize: 12)
        let large = TextMarkMetrics.fit(anchor: origin, text: "Привет", fontSize: 48)
        let longer = TextMarkMetrics.fit(anchor: origin, text: "Привет, мир", fontSize: 12)

        XCTAssertTrue(large.y > small.y)
        XCTAssertTrue(longer.x > small.x)
    }
}
