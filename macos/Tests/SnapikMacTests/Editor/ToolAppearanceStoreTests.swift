// Port of `tests/Snapik.App.Imaging.Tests/ToolAppearanceStoreTests.cs`, SPEC-DELTA-5 §2.9, §3.1.
//
// The store lives in the Mac target, because `EditorTool` does: Core holds the shape of the file
// (`ToolAppearanceEntry`) and nothing else. Colours are built out of their hex the way the file
// hands them over, so a round trip compares the very same numbers on both sides.
import AppKit
import SnapikCore
import XCTest

@testable import SnapikMac

final class ToolAppearanceStoreTests: XCTestCase {
    private func settings() -> HotkeySettings {
        var settings = HotkeySettings.default
        settings.annotationColor = "#0A84FF"
        settings.annotationThickness = 6
        settings.annotationHighlightThickness = 24
        settings.annotationFontSize = 32
        return settings
    }

    private func colour(_ hex: String) throws -> NSColor {
        try XCTUnwrap(EditorAppearance.color(fromHex: hex))
    }

    /// A file of 1.5.0 opens exactly as it looked: every one of the six tools takes the four common
    /// keys, and the highlighter takes the thickness of its own.
    func test_A_file_without_the_key_hands_every_tool_the_common_values() {
        let kept = ToolAppearanceStore.read(settings())

        XCTAssertEqual(6, kept.count)
        for tool in ToolAppearanceStore.tools {
            XCTAssertEqual("#0A84FF", kept[tool]?.color.hexRGB, "\(tool)")
            XCTAssertEqual(32, kept[tool]?.fontSize, "\(tool)")
            XCTAssertEqual(AnnotationLineStyle.solid, kept[tool]?.lineStyle, "\(tool)")
            XCTAssertEqual(AnnotationFill.none, kept[tool]?.fill, "\(tool)")
            XCTAssertEqual(AnnotationShape.rectangle, kept[tool]?.shape, "\(tool)")
            XCTAssertNil(kept[tool]?.fillColor, "\(tool)")
        }
        XCTAssertEqual(6, kept[.rectangle]?.thickness)
        XCTAssertEqual(24, kept[.highlight]?.thickness)
    }

    /// What the key holds is laid over those common values; a tool without a record of its own keeps
    /// them, and a name this build has never heard of is passed over in silence.
    func test_What_the_key_holds_is_read_and_a_tool_this_build_does_not_know_is_passed_over() {
        var stored = settings()
        stored.toolAppearance = [
            "rectangle": ToolAppearanceEntry(
                color: "#FF3B30", thickness: 2, lineStyle: "Dashed", fill: "translucent",
                fillColor: "#FFD60A", shape: "Rounded"),
            "telepathy": ToolAppearanceEntry(color: "#000000", thickness: 99),
        ]

        let kept = ToolAppearanceStore.read(stored)

        XCTAssertEqual(6, kept.count)
        XCTAssertEqual("#FF3B30", kept[.rectangle]?.color.hexRGB)
        XCTAssertEqual(2, kept[.rectangle]?.thickness)
        // The case of a name in a hand-edited file does not matter, the way Windows reads it.
        XCTAssertEqual(AnnotationLineStyle.dashed, kept[.rectangle]?.lineStyle)
        XCTAssertEqual(AnnotationFill.translucent, kept[.rectangle]?.fill)
        XCTAssertEqual(AnnotationShape.rounded, kept[.rectangle]?.shape)
        XCTAssertEqual("#FFD60A", kept[.rectangle]?.fillColor?.hexRGB)
        // The frame said nothing about the size of the letters, so the common key still speaks.
        XCTAssertEqual(32, kept[.rectangle]?.fontSize)
        // The arrow has no record of its own and is the file of 1.5.0 all over.
        XCTAssertEqual("#0A84FF", kept[.arrow]?.color.hexRGB)
        XCTAssertEqual(6, kept[.arrow]?.thickness)
        XCTAssertEqual(AnnotationLineStyle.solid, kept[.arrow]?.lineStyle)
    }

    /// A number in place of a name, and a colour that is not one, fall back to the value of that
    /// same tool instead of quietly picking a member of the enumeration.
    func test_A_number_instead_of_a_name_and_a_broken_colour_fall_back() {
        var stored = settings()
        stored.toolAppearance = [
            "pen": ToolAppearanceEntry(
                color: "not a colour", thickness: .nan, lineStyle: "2", fill: "",
                fontSize: .infinity, arrowStyle: "   ", shape: "7")
        ]

        let kept = ToolAppearanceStore.read(stored)

        XCTAssertEqual("#0A84FF", kept[.pen]?.color.hexRGB)
        XCTAssertEqual(6, kept[.pen]?.thickness)
        XCTAssertEqual(AnnotationLineStyle.solid, kept[.pen]?.lineStyle)
        XCTAssertEqual(AnnotationFill.none, kept[.pen]?.fill)
        XCTAssertEqual(32, kept[.pen]?.fontSize)
        XCTAssertEqual("straight", kept[.pen]?.arrowStyle)
        XCTAssertEqual(AnnotationShape.rectangle, kept[.pen]?.shape)
    }

    /// Everything written comes back, and the four common keys go on mirroring the frame, the
    /// highlighter and the caption, so a file written here is still read whole by 1.5.0. A tool
    /// without a fill colour leaves no `fillColor` behind.
    func test_The_round_trip_keeps_every_tool_and_mirrors_the_common_keys() throws {
        var frame = ToolAppearance()
        frame.color = try colour("#0080FF")
        frame.thickness = 8
        frame.lineStyle = .dotted
        frame.fill = .solid
        frame.fillColor = try colour("#FFFF00")
        frame.shape = .ellipse
        var highlight = ToolAppearance()
        highlight.thickness = 18
        var caption = ToolAppearance()
        caption.fontSize = 44
        var arrow = ToolAppearance()
        arrow.arrowStyle = "curved"

        let written = ToolAppearanceStore.write(
            settings(),
            tools: [
                .rectangle: frame, .arrow: arrow, .pen: ToolAppearance(),
                .highlight: highlight, .text: caption, .blur: ToolAppearance(),
            ])

        XCTAssertEqual(6, written.toolAppearance.count)
        XCTAssertEqual("#0080FF", written.toolAppearance["rectangle"]?.color)
        XCTAssertEqual("#FFFF00", written.toolAppearance["rectangle"]?.fillColor)
        XCTAssertNil(written.toolAppearance["arrow"]?.fillColor)
        XCTAssertEqual("#0080FF", written.annotationColor)
        XCTAssertEqual(8, written.annotationThickness)
        XCTAssertEqual(18, written.annotationHighlightThickness)
        XCTAssertEqual(44, written.annotationFontSize)

        let reread = ToolAppearanceStore.read(written)

        XCTAssertEqual(frame, reread[.rectangle])
        XCTAssertEqual(arrow, reread[.arrow])
        XCTAssertEqual(highlight, reread[.highlight])
        XCTAssertEqual(caption, reread[.text])
    }

    /// The name in the file is the name of the tool and never the letter of its key, and the five
    /// tools that carry no settings never reach the file at all.
    func test_The_name_in_the_file_is_the_name_of_the_tool_and_not_its_letter() {
        XCTAssertEqual("rectangle", EditorTool.rectangle.appearanceKey)
        XCTAssertEqual("blur", EditorTool.blur.appearanceKey)
        XCTAssertNil(EditorTool.select.appearanceKey)
        XCTAssertNil(EditorTool.comment.appearanceKey)
        XCTAssertNil(EditorTool.eraser.appearanceKey)
        XCTAssertEqual(EditorTool.highlight, EditorTool(appearanceKey: "Highlight"))
        XCTAssertNil(EditorTool(appearanceKey: "R"))
        XCTAssertNil(EditorTool(appearanceKey: "telepathy"))
    }
}
