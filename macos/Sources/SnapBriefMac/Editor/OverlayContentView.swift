// Port of the `OverlayEditorWindow.xaml` layer stack (`DesktopImage`, `Shade`), SPEC §1.2 steps
// 5-7, §6.2 "Слои окна снизу вверх". One instance per `NSScreen` (see `OverlayWindow`).
import AppKit

/// Root content view for one screen's `OverlayWindow`. Owns only the two always-present bottom
/// layers (frozen desktop image, even-odd shade hole) plus the hint chip; the editing-mode layers
/// (crop border + `AnnotationCanvasView`, capture handles, comment chips, toolbar) are added as
/// subviews by `OverlayEditorController+Editing` only on the one screen that becomes "active"
/// once a selection is made (SPEC §1.4's `GetCropMonitorWorkArea` — "монитор, в центре которого
/// находится снимок" — is the same screen-selection rule used here).
final class OverlayContentView: NSView {
    /// This screen's slice of `DesktopFrame.image` (already cropped/scaled by the controller to
    /// this window's pixel footprint).
    var desktopImage: CGImage? { didSet { needsDisplay = true } }

    /// The even-odd shade hole, in this view's local (top-left origin, Y-down) point space, or
    /// `nil`/empty for "fully shaded, no selection yet".
    var holeRectLocal: CGRect? { didSet { needsDisplay = true } }

    let hintView = HintChipView(frame: .zero)

    /// Screen index this view belongs to, assigned once by the controller (used to tag callbacks
    /// below so the controller knows which screen originated a selection-mode gesture).
    var screenIndex = 0

    /// Selection-mode mouse callbacks (SPEC §1.2 steps 7-9), only relevant before a capture
    /// exists. `point` is in this view's own local (flipped) coordinate space.
    var onMouseDown: ((Int, CGPoint) -> Void)?
    var onMouseDragged: ((Int, CGPoint) -> Void)?
    var onMouseUp: ((Int, CGPoint) -> Void)?
    /// Fired for a plain click (mouse down+up with no capture in progress) directly on the
    /// desktop image once a capture already exists — SPEC §1.8 "Клик вне снимка по затемнённому
    /// фону".
    var onBackgroundClick: ((Int, CGPoint) -> Void)?
    var onKeyDown: ((NSEvent) -> Void)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(hintView)
        hintView.text = EditorStrings.selectHint("ru")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var mouseDownPoint: CGPoint?

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        mouseDownPoint = point
        onMouseDown?(screenIndex, point)
    }

    override func mouseDragged(with event: NSEvent) {
        onMouseDragged?(screenIndex, convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let down = mouseDownPoint, (down.x - point.x) == 0, (down.y - point.y) == 0 {
            onBackgroundClick?(screenIndex, point)
        }
        mouseDownPoint = nil
        onMouseUp?(screenIndex, point)
    }

    override func keyDown(with event: NSEvent) {
        onKeyDown?(event)
    }

    override func layout() {
        super.layout()
        let size = hintView.intrinsicContentSize
        hintView.frame = CGRect(x: (bounds.width - size.width) / 2, y: 24, width: size.width, height: size.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        EditorTheme.overlayWindowBackground.setFill()
        NSBezierPath(rect: bounds).fill()

        if let desktopImage {
            NSImage(cgImage: desktopImage, size: bounds.size).draw(in: bounds)
        }

        let shadePath = NSBezierPath(rect: bounds)
        shadePath.windingRule = .evenOdd
        if let holeRectLocal, holeRectLocal.width > 0, holeRectLocal.height > 0 {
            shadePath.append(NSBezierPath(rect: holeRectLocal))
        }
        EditorTheme.shade.setFill()
        shadePath.fill()
    }
}
