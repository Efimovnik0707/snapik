// Port of `CapturePreviewWindow.xaml:112-118` (`ImageScroller`/`ZoomHost`) and `:255-260`
// (`OnImageMouseWheel`), SPEC-DELTA-2 §1.5, SPEC-DELTA-2B §D.
import AppKit

/// Flipped (top-left origin) document view that simply blits the current preview `CGImage` at
/// its own bounds size — magnification is handled entirely by `NSScrollView.magnification`
/// rather than by scaling this view's own frame content.
final class PreviewImageContentView: NSView {
    override var isFlipped: Bool { true }

    var image: CGImage? {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let image, let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(origin: .zero, size: bounds.size))
        ctx.restoreGState()
    }
}

/// Port of the `ScrollViewer PanningMode="Both"` + `LayoutTransform/ScaleTransform` combo:
/// native `NSScrollView` magnification (`allowsMagnification`) replaces the manual
/// `ScaleTransform`, and Cmd+wheel replaces `PreviewMouseWheel` with `Control` held (WPF) /
/// `Command` held (macOS convention for zoom-by-wheel, SPEC-DELTA-2B §D).
final class PreviewImageScrollView: NSScrollView {
    let contentImageView = PreviewImageContentView(frame: .zero)

    /// Fired whenever the viewport (visible) size changes, so the controller can recompute
    /// fit-to-window zoom (`PreviewGeometry.fitZoom`).
    var onViewportResized: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        allowsMagnification = true
        minMagnification = 0.05
        maxMagnification = 4
        hasVerticalScroller = true
        hasHorizontalScroller = true
        drawsBackground = true
        backgroundColor = NSColor(hex: "#0A0D11")
        borderType = .noBorder
        wantsLayer = true
        layer?.cornerRadius = 10
        documentView = contentImageView
        // CHECK-API: relying on `NSView.boundsDidChangeNotification` on `contentView` (the
        // clip view) to notice viewport-size changes; not verified against a compiler.
        postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(frameChanged), name: NSView.frameDidChangeNotification, object: self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setImage(_ image: CGImage?, size: CGSize) {
        contentImageView.image = image
        contentImageView.frame = CGRect(origin: .zero, size: size)
    }

    /// Port of `OnImageMouseWheel`: only intercepts wheel events with a modifier held (SPEC-DELTA-2B
    /// §D uses Cmd, the macOS analogue of WPF's Ctrl+wheel), factor `1.12`/`1/1.12`; everything
    /// else falls through to normal scrolling.
    override func scrollWheel(with event: NSEvent) {
        guard event.modifierFlags.contains(.command) else {
            super.scrollWheel(with: event)
            return
        }
        let factor: CGFloat = event.deltaY > 0 ? 1.12 : 1 / 1.12
        let target = min(max(magnification * factor, minMagnification), maxMagnification)
        let centerPoint = contentImageView.convert(event.locationInWindow, from: nil)
        setMagnification(target, centeredAt: centerPoint)
    }

    @objc private func frameChanged() {
        onViewportResized?()
    }
}
