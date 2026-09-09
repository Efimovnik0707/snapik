// Port of `InitializeCaptureHandles`/`_resizeOutline` (`OverlayEditorWindow.Resize.cs:18-101`),
// SPEC §1.6.
import AppKit

/// One of the four capture-corner resize handles. 22x22 hit target (SPEC §1.6); the visible
/// marker is an 8x8 white square with a 1.5pt `#2F8CFF` border, centered in the hit area.
/// Corner numbering is clockwise (0 = top-left, 1 = top-right, 2 = bottom-right, 3 = bottom-left,
/// SPEC §1.6 / `ResizeGeometry.Corners`).
final class CaptureHandleView: NSView {
    let corner: Int

    var onDragStarted: (() -> Void)?
    /// `pointInParent` is in the hosting `OverlayContentView`'s local coordinate space.
    var onDragChanged: ((_ pointInParent: CGPoint) -> Void)?
    var onDragEnded: ((_ cancelled: Bool) -> Void)?

    private var dragging = false

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(corner: Int) {
        self.corner = corner
        super.init(frame: CGRect(x: 0, y: 0, width: 22, height: 22))
        toolTip = EditorStrings.resizeCaptureBounds("ru")
        setAccessibilityLabel(EditorStrings.captureCorner("ru", corner + 1))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func draw(_ dirtyRect: NSRect) {
        let markerRect = CGRect(x: (bounds.width - 8) / 2, y: (bounds.height - 8) / 2, width: 8, height: 8)
        let path = NSBezierPath(roundedRect: markerRect, xRadius: 2, yRadius: 2)
        NSColor.white.setFill()
        path.fill()
        path.lineWidth = 1.5
        EditorTheme.handleBorder.setStroke()
        path.stroke()
    }

    override func resetCursorRects() {
        // CHECK-API: no public diagonal (NWSE/NESW) resize cursor in AppKit; `.crosshair` used
        // for both corner families (see the same note in `AnnotationCanvasView.mouseMoved`).
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        dragging = true
        onDragStarted?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragging, let superview else { return }
        let pointInParent = superview.convert(event.locationInWindow, from: nil)
        onDragChanged?(pointInParent)
    }

    override func mouseUp(with event: NSEvent) {
        guard dragging else { return }
        dragging = false
        onDragEnded?(false)
    }
}

/// Port of `_resizeOutline` (`Resize.cs:19-24`): the `#2F8CFF` 2pt outline shown over the capture
/// while a corner is being dragged. Never hit-tested (matches `IsHitTestVisible = false`).
final class ResizeOutlineView: NSView {
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
        path.lineWidth = 2
        EditorTheme.cropBorder.setStroke()
        path.stroke()
    }
}
