// Port of `src/Snapik.App/Controls/ScreenColorPicker.cs` plus the magnifier of
// `tasks/tz-005-details/D-editor.md` §3.2, SPEC-DELTA-3 §1.4 E-18.
import AppKit
import SnapikCore

/// The eyedropper: a colour taken from whatever is on the screen, Snapik included. A nearly
/// transparent window is laid over every monitor to hold the pointer and the keyboard, and the pixel
/// under the cursor is read out of a copy of the screen taken **before** that window was shown — the
/// overlay needs an alpha to be clickable at all, and reading through it takes a little off every
/// channel.
@MainActor
enum ScreenColorPicker {
    /// Runs the picking until a click or Escape. The colour under the cursor is handed to `preview`
    /// on every move; the return value is the colour that was clicked, or `nil` if the picking was
    /// given up, in which case the caller puts back what it had.
    @discardableResult
    static func pick(language: String, preview: @escaping (NSColor) -> Void) -> NSColor? {
        guard let copy = ScreenCopy.take() else { return nil }
        let unionRect = ScreenGeometry.globalPointsRect
        guard unionRect.width > 0, unionRect.height > 0 else { return nil }

        let window = NSWindow(contentRect: unionRect, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        // Not fully transparent: a window with nothing in it takes no clicks, and this one is here
        // to take them. One percent of black is invisible and still hit-testable.
        window.backgroundColor = NSColor.black.withAlphaComponent(0.01)
        window.level = .screenSaver
        window.ignoresMouseEvents = false
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let content = ScreenColorPickerView(frame: NSRect(origin: .zero, size: unionRect.size), copy: copy)
        window.contentView = content

        var picked: NSColor?
        content.onMoved = { color in preview(color) }
        content.onPicked = { color in
            picked = color
            NSApp.stopModal()
        }
        content.onCancelled = {
            picked = nil
            NSApp.stopModal()
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.runModal(for: window)
        window.orderOut(nil)
        return picked
    }

    /// The whole virtual screen as it stood when the picking began, plus the corner it starts at, so
    /// that a cursor position can be turned into a pixel of the copy.
    final class ScreenCopy {
        let image: CGImage
        let originPoints: CGPoint
        let scale: CGFloat

        private init(image: CGImage, originPoints: CGPoint, scale: CGFloat) {
            self.image = image
            self.originPoints = originPoints
            self.scale = scale
        }

        static func take() -> ScreenCopy? {
            let rect = ScreenGeometry.globalPointsRect
            guard rect.width > 0, rect.height > 0 else { return nil }
            // CHECK-API: `CGWindowListCreateImage` is soft-deprecated in favour of the asynchronous
            // `SCScreenshotManager`, but the eyedropper needs the pixels *before* it returns, on the
            // main thread, and the rest of this target already takes the same route
            // (`DemoSessionFactory`). Screen-recording permission is the same one the capture path
            // already asks for.
            guard let image = CGWindowListCreateImage(.infinite, .optionOnScreenOnly, kCGNullWindowID, []) else { return nil }
            let scale = rect.width > 0 ? CGFloat(image.width) / rect.width : 1
            return ScreenCopy(image: image, originPoints: CGPoint(x: rect.minX, y: rect.maxY), scale: max(scale, 0.01))
        }

        /// The pixel of the copy an AppKit screen point (Y-up) stands on.
        func pixel(atScreenPoint point: CGPoint) -> CGPoint {
            CGPoint(x: (point.x - originPoints.x) * scale, y: (originPoints.y - point.y) * scale)
        }

        func color(atScreenPoint point: CGPoint) -> NSColor? {
            let pixel = self.pixel(atScreenPoint: point)
            let x = Int(pixel.x.rounded(.down))
            let y = Int(pixel.y.rounded(.down))
            guard x >= 0, y >= 0, x < image.width, y < image.height else { return nil }
            guard let cropped = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else { return nil }
            var bytes = [UInt8](repeating: 0, count: 4)
            let info = CGImageAlphaInfo.premultipliedLast.rawValue
            guard
                let ctx = CGContext(
                    data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info)
            else { return nil }
            ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return NSColor(srgbRed: CGFloat(bytes[0]) / 255, green: CGFloat(bytes[1]) / 255, blue: CGFloat(bytes[2]) / 255, alpha: 1)
        }

        /// The 16x16 pixel square around the cursor the magnifier shows at 8x.
        func magnifierCrop(atScreenPoint point: CGPoint) -> CGImage? {
            let pixel = self.pixel(atScreenPoint: point)
            let side = ScreenColorPickerView.magnifierPixels
            let x = min(max(Int(pixel.x.rounded(.down)) - side / 2, 0), max(0, image.width - side))
            let y = min(max(Int(pixel.y.rounded(.down)) - side / 2, 0), max(0, image.height - side))
            guard image.width >= side, image.height >= side else { return nil }
            guard let crop = image.cropping(to: CGRect(x: x, y: y, width: side, height: side)) else { return nil }
            return Self.opaque(crop) ?? crop
        }

        /// The glass of the loupe must not be see-through: a copy of the screen carries whatever the
        /// window server left in its alpha channel, and the desktop has no transparency to give, so
        /// the copy is redrawn without an alpha channel at all before it is shown
        /// (`Controls/ScreenColorPicker.cs:217-228`, SPEC-DELTA-4 §5 point 5).
        private static func opaque(_ source: CGImage) -> CGImage? {
            guard let context = CGContext(
                data: nil, width: source.width, height: source.height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
            else { return nil }
            context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
            return context.makeImage()
        }
    }
}

/// The content of the eyedropper overlay: the magnifier capsule beside the cursor and nothing else.
@MainActor
final class ScreenColorPickerView: NSView {
    /// Sixteen pixels shown over 128 points is the magnification of 8x the spec asks for.
    static let magnifierPixels = 16
    static let magnifierSide: CGFloat = 128
    private static let padding: CGFloat = 6
    private static let hexHeight: CGFloat = 22
    private static let cursorOffset: CGFloat = 20

    private let copy: ScreenColorPicker.ScreenCopy
    private var cursorScreenPoint: CGPoint?
    private var currentColor: NSColor?
    private var trackingArea: NSTrackingArea?

    var onMoved: ((NSColor) -> Void)?
    var onPicked: ((NSColor) -> Void)?
    var onCancelled: (() -> Void)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(frame frameRect: NSRect, copy: ScreenColorPicker.ScreenCopy) {
        self.copy = copy
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        NSCursor.crosshair.set()
        refresh(at: NSEvent.mouseLocation)
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func mouseMoved(with event: NSEvent) { refresh(at: NSEvent.mouseLocation) }

    override func mouseDragged(with event: NSEvent) { refresh(at: NSEvent.mouseLocation) }

    override func mouseUp(with event: NSEvent) {
        refresh(at: NSEvent.mouseLocation)
        guard let color = currentColor else {
            onCancelled?()
            return
        }
        onPicked?(color)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == Keycode.escape {
            onCancelled?()
            return
        }
        super.keyDown(with: event)
    }

    private func refresh(at screenPoint: CGPoint) {
        cursorScreenPoint = screenPoint
        if let color = copy.color(atScreenPoint: screenPoint) {
            currentColor = color
            onMoved?(color)
        }
        needsDisplay = true
    }

    /// The local, Y-down point the cursor stands on inside this window-sized view.
    private func localCursorPoint(_ screenPoint: CGPoint) -> CGPoint {
        let flipped = ScreenGeometry.flipToTopLeft(screenPoint)
        return CGPoint(x: flipped.x, y: flipped.y)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let screenPoint = cursorScreenPoint, let color = currentColor else { return }
        let capsuleSize = NSSize(
            width: Self.magnifierSide + Self.padding * 2,
            height: Self.magnifierSide + Self.hexHeight + Self.padding * 3)
        let cursor = localCursorPoint(screenPoint)

        // The capsule sits below and to the right of the cursor, and mirrors to the other side when
        // it would leave the working area of the monitor the cursor is on.
        var origin = CGPoint(x: cursor.x + Self.cursorOffset, y: cursor.y + Self.cursorOffset)
        let work = workAreaLocal(forScreenPoint: screenPoint)
        if origin.x + capsuleSize.width > work.maxX { origin.x = cursor.x - Self.cursorOffset - capsuleSize.width }
        if origin.y + capsuleSize.height > work.maxY { origin.y = cursor.y - Self.cursorOffset - capsuleSize.height }
        origin.x = min(max(origin.x, work.minX), max(work.minX, work.maxX - capsuleSize.width))
        origin.y = min(max(origin.y, work.minY), max(work.minY, work.maxY - capsuleSize.height))

        let capsule = CGRect(origin: origin, size: capsuleSize)
        let background = NSBezierPath(roundedRect: capsule, xRadius: 8, yRadius: 8)
        EditorTheme.hintBackground.setFill()
        background.fill()

        let magnifier = CGRect(x: capsule.minX + Self.padding, y: capsule.minY + Self.padding, width: Self.magnifierSide, height: Self.magnifierSide)
        drawMagnifier(in: magnifier, screenPoint: screenPoint)

        let hex = NSAttributedString(
            string: color.hexRGB,
            attributes: [.font: EditorTheme.systemFont(12), .foregroundColor: EditorTheme.textSecondaryD9])
        let size = hex.size()
        hex.draw(at: CGPoint(x: capsule.midX - size.width / 2, y: magnifier.maxY + Self.padding + (Self.hexHeight - size.height) / 2))
    }

    private func drawMagnifier(in rect: CGRect, screenPoint: CGPoint) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.clip(to: rect)
        if let crop = copy.magnifierCrop(atScreenPoint: screenPoint) {
            ctx.interpolationQuality = .none
            // The view is flipped; unflip locally so the crop is not mirrored (`macos/README.md`).
            ctx.translateBy(x: 0, y: rect.minY + rect.maxY)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(crop, in: rect)
            ctx.scaleBy(x: 1, y: -1)
            ctx.translateBy(x: 0, y: -(rect.minY + rect.maxY))
        }

        // One line per magnified pixel, so the grid says which square the colour comes from.
        let step = rect.width / CGFloat(Self.magnifierPixels)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.2).cgColor)
        ctx.setLineWidth(1)
        ctx.beginPath()
        for index in 1..<Self.magnifierPixels {
            let offset = rect.minX + CGFloat(index) * step
            ctx.move(to: CGPoint(x: offset, y: rect.minY))
            ctx.addLine(to: CGPoint(x: offset, y: rect.maxY))
            ctx.move(to: CGPoint(x: rect.minX, y: rect.minY + CGFloat(index) * step))
            ctx.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + CGFloat(index) * step))
        }
        ctx.strokePath()

        // The pixel that will be taken, outlined twice so it reads on white and on black alike.
        let center = CGRect(x: rect.midX - step / 2, y: rect.midY - step / 2, width: step, height: step)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(2)
        ctx.stroke(center.insetBy(dx: -1, dy: -1))
        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(center)
        ctx.restoreGState()
    }

    /// The working area of the monitor the cursor is on, in this view's own local space.
    private func workAreaLocal(forScreenPoint point: CGPoint) -> CGRect {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return bounds }
        let topLeft = ScreenGeometry.flipToTopLeft(CGPoint(x: visible.minX, y: visible.maxY))
        let bottomRight = ScreenGeometry.flipToTopLeft(CGPoint(x: visible.maxX, y: visible.minY))
        return CGRect(
            x: min(topLeft.x, bottomRight.x), y: min(topLeft.y, bottomRight.y),
            width: abs(bottomRight.x - topLeft.x), height: abs(bottomRight.y - topLeft.y))
    }
}
