// Port of the close-path buttons in `AddChip`/`ShotNoteChip` (`OverlayEditorWindow.xaml.cs:404-415`,
// `OverlayEditorWindow.xaml:75-77`), SPEC §1.4. Shared by `CommentChipView` and `ShotNoteChipView`.
import AppKit

/// The small `M1,1 L9,9 M9,1 L1,9` close ("×") glyph button used by both comment chip kinds.
final class ChipCloseButtonView: NSView {
    var onClick: (() -> Void)?

    override var isFlipped: Bool { true }

    init(size: CGFloat, tooltip: String) {
        super.init(frame: CGRect(x: 0, y: 0, width: size, height: size))
        toolTip = tooltip
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    override func draw(_ dirtyRect: NSRect) {
        let inset: CGFloat = bounds.width * 0.28
        let iconRect = bounds.insetBy(dx: inset, dy: inset)
        IconPath.draw("M1,1 L9,9 M9,1 L1,9", in: iconRect, nativeSize: 10, stroke: EditorTheme.textSecondaryD9, lineWidth: 1.5)
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
