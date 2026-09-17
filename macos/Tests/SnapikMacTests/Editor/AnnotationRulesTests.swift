// Port of `tests/Snapik.App.Imaging.Tests/AnnotationRulesTests.cs:13, 23`,
// SPEC-DELTA-5-editor.md §4.1.
//
// The rules a mark keeps away from the canvas, so that both renderers answer the same.
import AppKit
import SnapikCore
import XCTest

@testable import SnapikMac

final class AnnotationRulesTests: XCTestCase {
    private let stroke = NSColor(srgbRed: 1, green: 59.0 / 255.0, blue: 48.0 / 255.0, alpha: 1)

    func test_The_outline_keeps_the_colour_of_the_mark_whatever_stands_inside_it() {
        XCTAssertEqual(stroke, AnnotationRules.outlineColorOf(fill: AnnotationFill.none, color: stroke))
        XCTAssertEqual(stroke, AnnotationRules.outlineColorOf(fill: .solid, color: stroke))
        XCTAssertEqual(stroke, AnnotationRules.outlineColorOf(fill: .translucent, color: stroke))
        // A blurred region has no outline at all.
        XCTAssertNil(AnnotationRules.outlineColorOf(fill: .blur, color: stroke))
    }

    func test_A_press_of_the_mouse_is_named_in_one_order_for_every_tool() {
        // A drag of the picture beats everything, and the two tools that draw over whatever lies
        // under them answer before the marks do.
        XCTAssertEqual(AnnotationRules.PressTarget.pan, target(.rectangle, panning: true, onObject: true))
        XCTAssertEqual(AnnotationRules.PressTarget.erase, target(.eraser, onObject: true))
        XCTAssertEqual(AnnotationRules.PressTarget.cropDraft, target(.crop, onObject: true))
        // A caption and a comment open for typing on the second click; a frame is only selected.
        XCTAssertEqual(
            AnnotationRules.PressTarget.activate,
            target(.select, clickCount: 2, onObject: true, activatable: true))
        XCTAssertEqual(AnnotationRules.PressTarget.object, target(.select, clickCount: 2, onObject: true))
        // The anchor of a comment answers to any tool, then the corners of the selected mark.
        XCTAssertEqual(AnnotationRules.PressTarget.commentAnchor, target(.arrow, onAnchor: true, onObject: true))
        XCTAssertEqual(AnnotationRules.PressTarget.resizeHandle, target(.arrow, onSelectedHandle: true, onObject: true))
        XCTAssertEqual(AnnotationRules.PressTarget.object, target(.conceal, onObject: true))
        XCTAssertEqual(AnnotationRules.PressTarget.empty, target(.rectangle))
        // The pointer draws nothing of its own: over an empty place it only drops the selection, so
        // that a drag of it never becomes a mark the export would have to give a shape to.
        XCTAssertEqual(AnnotationRules.PressTarget.deselect, target(.select))
        XCTAssertEqual(AnnotationRules.PressTarget.deselect, target(.select, clickCount: 2))
    }

    private func target(
        _ tool: EditorTool, panning: Bool = false, clickCount: Int = 1,
        onAnchor: Bool = false, onSelectedHandle: Bool = false, onObject: Bool = false, activatable: Bool = false
    ) -> AnnotationRules.PressTarget {
        AnnotationRules.pressTargetOf(
            tool: tool, panning: panning, clickCount: clickCount, onAnchor: onAnchor,
            onSelectedHandle: onSelectedHandle, onObject: onObject, activatable: activatable)
    }
}
