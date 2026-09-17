// Port of `src/Snapik.App/ToolAppearance.cs:158-192`, SPEC-DELTA-5-editor.md §1.1 W0-2, §1.2 E-3,
// §1.3 E-11, SPEC-DELTA-5 §2.8.
//
// The dictionary of the six sets and the store that reads it live in `ToolAppearanceStore.swift`;
// what the properties block of the panel shows out of one of them lives here.
import Foundation

/// Which capsule the properties block shows beside the colour of the tool in hand.
enum SecondCapsule {
    case none
    case line
    case fontSize
    case shape
}

/// What the properties block of the panel shows, and whether it answers at all.
struct InspectorView: Equatable {
    let stroke: Bool
    let fillSwatch: Bool
    let second: SecondCapsule
    let enabled: Bool

    init(stroke: Bool, fillSwatch: Bool, second: SecondCapsule, enabled: Bool) {
        self.stroke = stroke
        self.fillSwatch = fillSwatch
        self.second = second
        self.enabled = enabled
    }
}

/// Whose settings the properties block shows, and which of them it shows. Two pure rules, away from
/// the window: the block is redrawn on every selection and on every tool, and both answers have to
/// be the same wherever they are asked for.
enum EditorInspector {
    static func inspectorViewOf(_ tool: EditorTool) -> InspectorView {
        switch tool {
        case .rectangle:
            return InspectorView(stroke: true, fillSwatch: true, second: .line, enabled: true)
        case .arrow:
            return InspectorView(stroke: true, fillSwatch: false, second: .line, enabled: true)
        case .pen:
            return InspectorView(stroke: true, fillSwatch: false, second: .line, enabled: true)
        // The highlighter has a colour and a thickness; the pattern of a stroke it has none of.
        case .highlight:
            return InspectorView(stroke: true, fillSwatch: false, second: .line, enabled: true)
        case .text:
            return InspectorView(stroke: true, fillSwatch: false, second: .fontSize, enabled: true)
        // The blur has neither colour nor settings of its own: it takes the shape of the frame, so
        // the block stands empty. It had a shape capsule of its own until 1.7.0, and choosing from
        // it with nothing selected switched the hand to the frame — the blur fell out of the hand.
        case .blur:
            return InspectorView(stroke: false, fillSwatch: false, second: .none, enabled: true)
        // No tool of the panel draws a conceal any more, but a mark of one read out of an old
        // session can be selected, and then the block belongs to that mark: it is a filled region
        // and shows what a region shows. Reached through `inspectedTool` alone, never through a hand.
        case .conceal:
            return InspectorView(stroke: true, fillSwatch: true, second: .line, enabled: true)
        // Select, eraser, crop and comment carry no settings, so the block is there but dead.
        case .select, .eraser, .crop, .comment:
            return InspectorView(stroke: true, fillSwatch: true, second: .line, enabled: false)
        }
    }

    /// A mark that is selected owns the block; with nothing selected it is the tool in hand.
    static func inspectedTool(selected: EditorAnnotation?, armed: EditorTool) -> EditorTool {
        selected?.kind ?? armed
    }
}
