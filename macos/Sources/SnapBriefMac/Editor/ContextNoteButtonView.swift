// Port of `ContextNoteButton` (`OverlayEditorWindow.xaml:54-62`), SPEC §1.4.
import AppKit

/// Compact "add comment" affordance shown near a selected non-Rectangle annotation, or near the
/// capture's top-right corner when nothing is selected (SPEC §1.4). 32x32, cloud icon with a blue
/// indicator dot.
final class ContextNoteButtonView: NSView {
    var onClick: (() -> Void)?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: CGRect(x: 0, y: 0, width: 32, height: 32))
        toolTip = EditorStrings.addComment("ru")
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: EditorTheme.buttonCornerRadius, yRadius: EditorTheme.buttonCornerRadius)
        EditorTheme.contextNoteButtonBackground.setFill()
        path.fill()
        path.lineWidth = 1
        EditorTheme.contextNoteButtonBorder.setStroke()
        path.stroke()

        let iconRect = CGRect(x: (bounds.width - 15) / 2, y: (bounds.height - 15) / 2, width: 15, height: 15)
        IconPath.draw(
            "M2,2 L13,2 L13,10 L7,10 L4,13 L4,10 L2,10 Z",
            in: iconRect, nativeSize: 15, stroke: EditorTheme.textPrimary, lineWidth: 1.6)

        let dotDiameter: CGFloat = 6
        let dot = CGRect(x: bounds.width - dotDiameter - 4, y: 4, width: dotDiameter, height: dotDiameter)
        EditorTheme.accent.setFill()
        NSBezierPath(ovalIn: dot).fill()
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
