// The widgets every popover of the panel is built out of (`OverlayEditorWindow.xaml:283-437`,
// `OverlayEditorWindow.Appearance.cs`), SPEC §1.3, §6.2, SPEC-DELTA-3 §1.4 E-3, E-16, E-17.
// View layer only; `OverlayEditorController+Appearance.swift` owns the `NSPopover` lifecycle and
// every state/history decision.
import AppKit
import SnapikCore

/// One 34x34 colour swatch (`Appearance.cs:188-206`): a 22x22 filled circle, a white ring when this
/// swatch's colour is the one in force. An empty slot of the own palette is the same cell with a
/// dashed outline and nothing to click.
final class AppearanceColorSwatchView: NSView {
    let color: NSColor?
    var isSelected = false { didSet { needsDisplay = true } }
    private var isHovering = false { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?

    override var isFlipped: Bool { true }

    init(color: NSColor?, tooltip: String?) {
        self.color = color
        super.init(frame: CGRect(x: 0, y: 0, width: 34, height: 34))
        toolTip = tooltip
        if let tooltip { setAccessibilityLabel(tooltip) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        guard color != nil else { return }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }
    override func mouseExited(with event: NSEvent) { isHovering = false }
    // Clicking a swatch never closes the popover — that guarantee lives in the popover's
    // `.semitransient` behavior, not here.
    override func mouseDown(with event: NSEvent) { if color != nil { onClick?() } }
    override func resetCursorRects() { if color != nil { addCursorRect(bounds, cursor: .pointingHand) } }

    override func draw(_ dirtyRect: NSRect) {
        let buttonPath = NSBezierPath(roundedRect: bounds, xRadius: EditorTheme.buttonCornerRadius, yRadius: EditorTheme.buttonCornerRadius)
        (isHovering ? EditorTheme.toolHoverBackground : .clear).setFill()
        buttonPath.fill()

        let oval = NSBezierPath(ovalIn: bounds.insetBy(dx: 6, dy: 6))
        guard let color else {
            // The row of the own palette keeps its twelve cells from the first colour to the last,
            // so it holds its shape while it fills up instead of growing under the spectrum.
            oval.lineWidth = 1
            oval.setLineDash([2, 2], count: 2, phase: 0)
            EditorTheme.appearanceHexFieldBorder.setStroke()
            oval.stroke()
            return
        }
        color.setFill()
        oval.fill()
        oval.lineWidth = 1
        (isSelected ? NSColor.white : ToolbarColorDotView.ringColor).setStroke()
        oval.stroke()
    }
}

/// Lays `AppearanceColorSwatchView`s left-to-right, wrapping to a new row when one would overflow
/// `width` (`WrapPanel`, `xaml:300`).
final class AppearanceSwatchWrapView: NSView {
    private(set) var swatches: [AppearanceColorSwatchView] = []
    override var isFlipped: Bool { true }

    func setSwatches(_ swatches: [AppearanceColorSwatchView]) {
        for swatch in self.swatches { swatch.removeFromSuperview() }
        self.swatches = swatches
        for swatch in swatches { addSubview(swatch) }
    }

    @discardableResult
    func layoutSwatches(width: CGFloat) -> CGFloat {
        let itemSize: CGFloat = 34
        let gap: CGFloat = 6
        var x: CGFloat = 0
        var y: CGFloat = 0
        for swatch in swatches {
            if x + itemSize > width, x > 0 {
                x = 0
                y += itemSize + gap
            }
            swatch.frame = CGRect(x: x, y: y, width: itemSize, height: itemSize)
            x += itemSize + gap
        }
        return swatches.isEmpty ? 0 : y + itemSize
    }
}

/// One segment of a segmented row (`SegmentButton`): a rounded cell that fills with the accent while
/// it is the chosen one, carrying either a caption or a drawn sample.
final class EditorSegmentView: NSView {
    let tag: String
    var isChosen = false { didSet { needsDisplay = true } }
    var isEnabled = true {
        didSet {
            alphaValue = isEnabled ? 1 : 0.4
            needsDisplay = true
        }
    }
    private var isHovering = false { didSet { needsDisplay = true } }
    private let caption: String?
    /// Draws the sample inside the cell, when the segment carries one instead of a caption.
    var drawSample: ((CGRect, NSColor) -> Void)?
    var onClick: (() -> Void)?

    override var isFlipped: Bool { true }

    init(tag: String, caption: String? = nil, tooltip: String? = nil) {
        self.tag = tag
        self.caption = caption
        super.init(frame: .zero)
        toolTip = tooltip ?? caption
        setAccessibilityLabel(tooltip ?? caption ?? tag)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }
    override func mouseExited(with event: NSEvent) { isHovering = false }
    override func mouseDown(with event: NSEvent) { if isEnabled { onClick?() } }
    override func resetCursorRects() { if isEnabled { addCursorRect(bounds, cursor: .pointingHand) } }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
        if isChosen {
            AccentPalette.wash(alpha: 0.28).setFill()
            path.fill()
        } else if isHovering, isEnabled {
            EditorTheme.toolHoverBackground.setFill()
            path.fill()
        }
        let content = isChosen ? NSColor.white : EditorTheme.textSecondaryD9
        if let caption {
            let text = NSAttributedString(string: caption, attributes: [.font: EditorTheme.systemFont(12), .foregroundColor: content])
            let size = text.size()
            text.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
        } else {
            drawSample?(bounds, content)
        }
    }
}

/// A row of segments inside a rounded `ElevatedBrush` tray (`Border ... UniformGrid`).
final class EditorSegmentedRowView: NSView {
    private(set) var segments: [EditorSegmentView] = []
    var isEnabled = true {
        didSet {
            alphaValue = isEnabled ? 1 : 0.4
            for segment in segments { segment.isEnabled = isEnabled }
        }
    }

    override var isFlipped: Bool { true }

    func setSegments(_ segments: [EditorSegmentView]) {
        for segment in self.segments { segment.removeFromSuperview() }
        self.segments = segments
        for segment in segments { addSubview(segment) }
        needsLayout = true
    }

    func choose(_ tag: String) {
        for segment in segments { segment.isChosen = segment.tag == tag }
    }

    override func layout() {
        super.layout()
        guard !segments.isEmpty else { return }
        let padding: CGFloat = 3
        let width = (bounds.width - padding * 2) / CGFloat(segments.count)
        for (index, segment) in segments.enumerated() {
            segment.frame = CGRect(x: padding + CGFloat(index) * width, y: padding, width: width, height: bounds.height - padding * 2)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        EditorTheme.appearancePreviewBackground.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
    }
}

/// The stroke preview strip (`StrokePreview`/`LineStylePreview`): the background tray is always
/// drawn; the line itself is hidden when the active tool has no stroke.
final class EditorStrokePreviewView: NSView {
    var strokeColor: NSColor = EditorTheme.defaultAnnotationColor { didSet { needsDisplay = true } }
    var strokeThickness: CGFloat = 4 { didSet { needsDisplay = true } }
    var lineStyle: AnnotationLineStyle = .solid { didSet { needsDisplay = true } }
    var isHighlight = false { didSet { needsDisplay = true } }
    var strokeHidden = false { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let background = NSBezierPath(roundedRect: bounds, xRadius: EditorTheme.appearancePreviewCornerRadius, yRadius: EditorTheme.appearancePreviewCornerRadius)
        EditorTheme.appearancePreviewBackground.setFill()
        background.fill()
        guard !strokeHidden, let ctx = NSGraphicsContext.current?.cgContext else { return }

        // A stroke 24 pt wide would not fit a strip 36 pt tall, so the sample is capped — a
        // highlighter that wide is drawn with its own transparency and its own square ends.
        let width = min(24, strokeThickness)
        let y = bounds.midY
        AnnotationPainter.strokePath(
            [[CGPoint(x: 15, y: y), CGPoint(x: max(15, bounds.width - 15), y: y)]],
            in: ctx, color: strokeColor, thickness: width, lineStyle: lineStyle, highlight: isHighlight)
    }
}

/// Hand-drawn slider, replacing `StrokeSliderStyle`'s custom `ControlTemplate` (`xaml:40-52`): a
/// 4 pt track — filled `#5EAAFF` up to the thumb, empty `#465366` after it — and a 16x16 round thumb.
/// `IsMoveToPointEnabled="True"`'s "click anywhere on the track jumps the thumb there" is folded into
/// `mouseDown`; dragging fires continuously like the WPF `ValueChanged`.
final class EditorSliderView: NSView {
    private(set) var minValue: Double = 1
    private(set) var maxValue: Double = 16
    private(set) var value: Double = 4
    var isEnabled = true { didSet { alphaValue = isEnabled ? 1 : 0.4 } }
    var onValueChanged: ((Double) -> Void)?

    private static let thumbRadius: CGFloat = 8
    private static let trackHeight: CGFloat = 4

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect.height > 0 ? frameRect : CGRect(x: 0, y: 0, width: frameRect.width, height: 26))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The range belongs to the tool in the hand: the pencil counts in a few pixels, the highlighter
    /// in tens of them, a caption in its own eight to ninety-six (`SyncAppearance:283-284`).
    func setRange(_ range: ClosedRange<Double>) {
        minValue = range.lowerBound
        maxValue = range.upperBound
        setValue(value, notify: false)
    }

    /// Sets the current value (clamped and rounded to the nearest integer pixel, matching
    /// `IsSnapToTickEnabled="True" TickFrequency="1"`). `notify: false` is used when the controller
    /// is echoing state back into the slider, to avoid a feedback loop.
    func setValue(_ newValue: Double, notify: Bool) {
        value = min(max(newValue, minValue), maxValue).rounded()
        needsDisplay = true
        if notify { onValueChanged?(value) }
    }

    private func value(at point: CGPoint) -> Double {
        let trackStart = Self.thumbRadius
        let trackEnd = bounds.width - Self.thumbRadius
        guard trackEnd > trackStart else { return minValue }
        let fraction = EditorGeometry.clamp((point.x - trackStart) / (trackEnd - trackStart), 0, 1)
        return minValue + Double(fraction) * (maxValue - minValue)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        setValue(value(at: convert(event.locationInWindow, from: nil)), notify: true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEnabled else { return }
        setValue(value(at: convert(event.locationInWindow, from: nil)), notify: true)
    }

    override func resetCursorRects() { if isEnabled { addCursorRect(bounds, cursor: .pointingHand) } }

    override func draw(_ dirtyRect: NSRect) {
        let trackY = bounds.midY
        let trackStart = Self.thumbRadius
        let trackEnd = bounds.width - Self.thumbRadius
        guard trackEnd > trackStart, maxValue > minValue else { return }
        let fraction = CGFloat((value - minValue) / (maxValue - minValue))
        let thumbX = trackStart + fraction * (trackEnd - trackStart)

        let filledRect = CGRect(x: trackStart, y: trackY - Self.trackHeight / 2, width: max(0, thumbX - trackStart), height: Self.trackHeight)
        let emptyRect = CGRect(x: thumbX, y: trackY - Self.trackHeight / 2, width: max(0, trackEnd - thumbX), height: Self.trackHeight)
        EditorTheme.appearanceSliderFilledTrack.setFill()
        NSBezierPath(roundedRect: filledRect, xRadius: 2, yRadius: 2).fill()
        EditorTheme.appearanceSliderEmptyTrack.setFill()
        NSBezierPath(roundedRect: emptyRect, xRadius: 2, yRadius: 2).fill()

        let thumbRect = CGRect(x: thumbX - Self.thumbRadius, y: trackY - Self.thumbRadius, width: Self.thumbRadius * 2, height: Self.thumbRadius * 2)
        let thumb = NSBezierPath(ovalIn: thumbRect)
        EditorTheme.appearanceSliderThumbFill.setFill()
        thumb.fill()
        thumb.lineWidth = 1
        EditorTheme.appearanceSliderThumbBorder.setStroke()
        thumb.stroke()
    }
}

/// A small square button with a system symbol on it, for the two beside the HEX field: the
/// eyedropper and the "+" that puts the colour in force into the own palette.
final class EditorIconButtonView: NSView {
    private let symbolName: String
    private var isHovering = false { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?

    override var isFlipped: Bool { true }

    init(symbolName: String, tooltip: String, size: CGFloat = 34) {
        self.symbolName = symbolName
        super.init(frame: CGRect(x: 0, y: 0, width: size, height: size))
        toolTip = tooltip
        setAccessibilityLabel(tooltip)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }
    override func mouseExited(with event: NSEvent) { isHovering = false }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: EditorTheme.buttonCornerRadius, yRadius: EditorTheme.buttonCornerRadius)
        (isHovering ? EditorTheme.toolHoverBackground : .clear).setFill()
        path.fill()
        EditorIcon.draw(symbol: symbolName, in: bounds, color: EditorTheme.textPrimary, pointSize: 14)
    }
}

/// Small helpers shared by every popover content view below.
enum EditorPopoverChrome {
    static func label(_ string: String, bold: Bool = false, color: NSColor = EditorTheme.textPrimary, alignment: NSTextAlignment = .left) -> NSTextField {
        let field = NSTextField(labelWithString: string)
        field.font = EditorTheme.systemFont(13, weight: bold ? .semibold : .regular)
        field.textColor = color
        field.alignment = alignment
        field.backgroundColor = .clear
        field.isBezeled = false
        field.isEditable = false
        field.isSelectable = false
        return field
    }
}
