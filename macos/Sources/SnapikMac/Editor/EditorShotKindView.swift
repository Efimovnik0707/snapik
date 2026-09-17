// Port of the caption `ShotKindChip` of `OverlayEditorWindow.xaml:175-182`, SPEC-DELTA-4 §1.3 E-7,
// §3.5, §4. The switch of the scale that used to share this file is gone with the round of 1.6.0:
// a capture opens at its own size and the wheel with Cmd is the only way out of it
// (SPEC-DELTA-5-editor.md §1.2 E-1).
import AppKit

/// What the capture is, inside its top right corner: the whole screen with the number of monitors,
/// or a file that was imported, and the size in pixels either way. A capture of a region says
/// nothing and the caption stays away (`ShotKindChip`, `SyncShotKind`).
@MainActor
final class EditorShotKindView: NSView {
    private static let padding = CGSize(width: 10, height: 4)
    private static let glyphWidth: CGFloat = 16
    private static let glyphGap: CGFloat = 6

    private var symbolName = EditorIcon.display
    /// Read back by the smoke probe: the caption is the one string the editor says about the kind of
    /// the capture (SPEC-DELTA-4 §6).
    private(set) var caption = ""

    override var isFlipped: Bool { true }

    /// The caption belongs to the picture under it: it never takes a press away from the canvas
    /// (`IsHitTestVisible="False"`).
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// A monitor for the whole screen, a sheet of paper for a file: the two glyphs the card in the
    /// strip wears for the same two kinds.
    func update(symbolName: String, caption: String) {
        self.symbolName = symbolName
        self.caption = caption
        setAccessibilityLabel(caption)
        needsDisplay = true
    }

    func sizeToFitContent() -> CGSize {
        let measured = NSAttributedString(string: caption, attributes: [.font: EditorTheme.systemFont(12)]).size()
        return CGSize(
            width: Self.padding.width * 2 + Self.glyphWidth + Self.glyphGap + measured.width,
            height: Self.padding.height * 2 + max(measured.height, Self.glyphWidth))
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
        EditorTheme.hintBackground.setFill()
        path.fill()

        let glyph = CGRect(x: Self.padding.width, y: 0, width: Self.glyphWidth, height: bounds.height)
        EditorIcon.draw(symbol: symbolName, in: glyph, color: EditorTheme.textSecondaryD9, pointSize: 12)

        let text = NSAttributedString(
            string: caption,
            attributes: [.font: EditorTheme.systemFont(12), .foregroundColor: EditorTheme.textSecondaryD9])
        let size = text.size()
        text.draw(at: CGPoint(x: glyph.maxX + Self.glyphGap, y: bounds.midY - size.height / 2))
    }
}
