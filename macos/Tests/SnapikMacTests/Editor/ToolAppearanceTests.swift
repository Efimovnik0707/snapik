// Port of `tests/Snapik.App.Imaging.Tests/ToolAppearanceTests.cs:21, 47`,
// SPEC-DELTA-5-editor.md §4.1, SPEC-DELTA-5 §2.8.
//
// What the properties block of the panel shows and whose settings it shows. Reading and writing the
// six sets is covered by `ToolAppearanceStoreTests`, the file of the wave the store came with.
import AppKit
import SnapikCore
import XCTest

@testable import SnapikMac

final class ToolAppearanceTests: XCTestCase {
    func test_The_properties_block_shows_what_the_tool_has() {
        // The frames of the reference shot: what the block shows for each tool, and for which of
        // them it is there but dead.
        let expected: [EditorTool: InspectorView] = [
            .rectangle: InspectorView(stroke: true, fillSwatch: true, second: .line, enabled: true),
            .arrow: InspectorView(stroke: true, fillSwatch: false, second: .line, enabled: true),
            .pen: InspectorView(stroke: true, fillSwatch: false, second: .line, enabled: true),
            .highlight: InspectorView(stroke: true, fillSwatch: false, second: .line, enabled: true),
            .text: InspectorView(stroke: true, fillSwatch: false, second: .fontSize, enabled: true),
            // The blur shows nothing at all: no colour, and no shape either, because the shape it is
            // drawn with is the one the frame carries.
            .blur: InspectorView(stroke: false, fillSwatch: false, second: .none, enabled: true),
            // No tool draws a conceal any more, but an old mark of one can be selected, and then the
            // block shows its fields, the way it does for any other filled region.
            .conceal: InspectorView(stroke: true, fillSwatch: true, second: .line, enabled: true),
            .comment: InspectorView(stroke: true, fillSwatch: true, second: .line, enabled: false),
            .eraser: InspectorView(stroke: true, fillSwatch: true, second: .line, enabled: false),
            .crop: InspectorView(stroke: true, fillSwatch: true, second: .line, enabled: false),
            .select: InspectorView(stroke: true, fillSwatch: true, second: .line, enabled: false),
        ]
        for (tool, view) in expected {
            XCTAssertEqual(view, EditorInspector.inspectorViewOf(tool), "\(tool)")
        }
    }

    func test_A_selected_mark_owns_the_block_and_an_empty_canvas_leaves_it_to_the_tool_in_hand() {
        let arrow = EditorAnnotation(
            kind: .arrow, points: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)],
            color: .red, thickness: 4)
        XCTAssertEqual(EditorTool.arrow, EditorInspector.inspectedTool(selected: arrow, armed: .rectangle))
        XCTAssertEqual(EditorTool.rectangle, EditorInspector.inspectedTool(selected: nil, armed: .rectangle))
    }
}
