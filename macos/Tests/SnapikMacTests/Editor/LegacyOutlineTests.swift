// Port of `tests/Snapik.App.Imaging.Tests/LegacyOutlineTests.cs`, SPEC-DELTA-4 §2.2, §6.
//
// "hasOutline" is read but never written any more: `false` on a rectangle means "a solid fill of one
// colour", and everywhere else the field is ignored. The rule lives in `EditorAnnotation.fromCore`,
// which belongs to the Mac target, so the set does too.
import AppKit
import SnapikCore
import XCTest

@testable import SnapikMac

final class LegacyOutlineTests: XCTestCase {
    private func legacy(
        kind: AnnotationKind, hasOutline: Bool?, fillColor: String? = nil
    ) -> AnnotationItem {
        var item = AnnotationItem.create(
            kind: kind, points: [NormalizedPoint(0.1, 0.1), NormalizedPoint(0.4, 0.4)],
            strokeColor: "#FFFF3B30")
        item.legacyHasOutline = hasOutline
        item.fillColor = fillColor
        return item
    }

    private func rgb(_ color: NSColor?) -> [Int]? {
        guard let converted = color?.usingColorSpace(.sRGB) else { return nil }
        return [
            Int((converted.redComponent * 255).rounded()),
            Int((converted.greenComponent * 255).rounded()),
            Int((converted.blueComponent * 255).rounded()),
        ]
    }

    func test_A_frame_written_without_an_outline_takes_the_colour_of_its_stroke() {
        let mark = EditorAnnotation.fromCore(
            legacy(kind: .rectangle, hasOutline: false), imageWidth: 1000, imageHeight: 800)

        XCTAssertEqual(.solid, mark.fill)
        XCTAssertEqual([0xFF, 0x3B, 0x30], rgb(mark.fillColor))
    }

    func test_A_frame_written_without_an_outline_keeps_a_fill_colour_of_its_own() {
        let mark = EditorAnnotation.fromCore(
            legacy(kind: .rectangle, hasOutline: false, fillColor: "#FF101820"),
            imageWidth: 1000, imageHeight: 800)

        XCTAssertEqual(.solid, mark.fill)
        XCTAssertEqual([0x10, 0x18, 0x20], rgb(mark.fillColor))
    }

    func test_A_frame_with_the_flag_set_or_missing_reads_as_an_empty_one() {
        for hasOutline: Bool? in [true, nil] {
            let mark = EditorAnnotation.fromCore(
                legacy(kind: .rectangle, hasOutline: hasOutline), imageWidth: 1000, imageHeight: 800)

            XCTAssertEqual(AnnotationFill.none, mark.fill, "hasOutline: \(String(describing: hasOutline))")
            XCTAssertNil(mark.fillColor, "hasOutline: \(String(describing: hasOutline))")
        }
    }

    func test_An_arrow_written_without_an_outline_is_left_alone() {
        let mark = EditorAnnotation.fromCore(
            legacy(kind: .arrow, hasOutline: false), imageWidth: 1000, imageHeight: 800)

        XCTAssertEqual(.arrow, mark.kind)
        XCTAssertEqual(AnnotationFill.none, mark.fill)
        XCTAssertNil(mark.fillColor)
    }

    /// The other half of the rule: whatever the file carried, the editor writes the flag no more.
    func test_The_editor_does_not_write_the_flag_back() {
        let mark = EditorAnnotation.fromCore(
            legacy(kind: .rectangle, hasOutline: false), imageWidth: 1000, imageHeight: 800)

        let core = mark.toCore(imageWidth: 1000, imageHeight: 800)

        XCTAssertNil(core.legacyHasOutline)
    }
}
