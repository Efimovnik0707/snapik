// Port of the `Hint` pill (`OverlayEditorWindow.xaml:65-68`), SPEC §1.2 step 6, §1.13 point 10
// (also reused to show save/crop/resize error text, matching the Windows source's own reuse of
// `Hint`/`Hint.Child` for both purposes).
import AppKit

final class HintChipView: NSView {
    private let label = NSTextField(labelWithString: "")

    override var isFlipped: Bool { true }

    var text: String = "" {
        didSet {
            label.stringValue = text
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.font = EditorTheme.systemFont(13)
        label.textColor = .white
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        label.isSelectable = false
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize {
        let textSize = label.attributedStringValue.size()
        return NSSize(width: textSize.width + 26, height: textSize.height + 16)
    }

    override func layout() {
        super.layout()
        let textSize = label.attributedStringValue.size()
        label.frame = CGRect(x: 13, y: 8, width: textSize.width, height: textSize.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: EditorTheme.hintCornerRadius, yRadius: EditorTheme.hintCornerRadius)
        EditorTheme.hintBackground.setFill()
        path.fill()
    }
}
