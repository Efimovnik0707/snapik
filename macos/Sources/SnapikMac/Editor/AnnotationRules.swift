// Port of `src/Snapik.App/Controls/AnnotationRules.cs` (new file of the round),
// SPEC-DELTA-5-editor.md §1.1 W0-1, §1.2 E-5, E-8.
import AppKit
import SnapikCore

/// The rules of a mark that hold without a canvas: what colour its outline takes, and what a press
/// of the mouse lands on. They live away from `AnnotationCanvasView` on purpose — that one is an
/// `NSView` of a thousand lines and cannot be reached by a test, and these answers are the ones two
/// renderers and every gesture count from.
enum AnnotationRules {
    /// The outline is always drawn in the colour of the mark, whatever stands inside it: the stroke
    /// and the fill are two properties of their own, and a blurred region has no outline at all.
    /// `nil` means "draw no outline".
    ///
    /// The parameter `fillColor` is gone on purpose (`AnnotationRules.cs:17-18`): a mark of 1.5.0
    /// with a blue fill and a red stroke used to be drawn with a blue outline and is now drawn with
    /// the red one. The format is untouched, the reading of it changed.
    static func outlineColorOf(fill: AnnotationFill, color: NSColor) -> NSColor? {
        fill == .blur ? nil : color
    }

    /// What a press of the mouse has landed on, before the canvas acts on it.
    enum PressTarget {
        case pan
        case erase
        case cropDraft
        case activate
        case commentAnchor
        case resizeHandle
        case object
        case deselect
        case empty
    }

    /// What a press of the left button means, in the one order every tool obeys. One rule and not a
    /// branch per tool: whatever is in hand, the corners of the selected mark, the anchor of a
    /// comment and the mark under the cursor answer before a new mark is begun.
    ///
    /// `activatable` is "the mark under the cursor is a caption or a comment", the two that a double
    /// click opens for typing; on a frame or an arrow a double click is two single ones, that is, a
    /// selection. `PressTarget.deselect` is the empty place under a tool that draws nothing: the
    /// selection is dropped and no draft is begun.
    static func pressTargetOf(
        tool: EditorTool, panning: Bool, clickCount: Int,
        onAnchor: Bool, onSelectedHandle: Bool, onObject: Bool, activatable: Bool
    ) -> PressTarget {
        if panning { return .pan }
        if tool == .eraser { return .erase }
        // The crop is not an object tool: its frame is dragged over whatever lies under it.
        if tool == .crop { return .cropDraft }
        if clickCount == 2 && activatable { return .activate }
        if onAnchor { return .commentAnchor }
        if onSelectedHandle { return .resizeHandle }
        if onObject { return .object }
        // The pointer draws nothing of its own: over an empty place it only drops the selection.
        // Without this the drag of a pointer would leave a mark of kind Select in the session, and
        // the export, which knows no such kind, would put a rectangle in the picture.
        if tool == .select { return .deselect }
        return .empty
    }
}
