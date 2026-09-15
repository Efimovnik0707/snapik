// Port of `src/Snapik.App/Controls/ColorSpectrum.xaml(.cs)`, SPEC-DELTA-3 §1.4 E-17.
import AppKit
import SnapikCore

/// The whole circle of colours in two pieces: a square where saturation runs left to right and
/// brightness top to bottom, and a strip of hue beside it. What is picked here is a colour like any
/// other, and the HEX field beside it shows the same one.
///
/// The hue, the saturation and the brightness are kept as numbers rather than read back out of the
/// colour every time: black has no hue and grey has no saturation, so a marker dragged into the
/// corner would otherwise jump back to red on the way out.
final class ColorSpectrumView: NSView {
    static let squareSide: CGFloat = 160
    static let hueWidth: CGFloat = 16
    static let gap: CGFloat = 12
    static let totalSize = NSSize(width: squareSide + gap + hueWidth, height: squareSide)

    private var hue: Double = 0
    private var saturation: Double = 1
    private var brightness: Double = 1
    private var draggingSquare = false
    private var draggingHue = false

    /// Raised while the colour is being picked, on every move of a marker.
    var onColorChanged: ((NSColor) -> Void)?
    /// Raised once the picking is over: what the row of saved colours listens to.
    var onColorCommitted: ((NSColor) -> Void)?

    override var isFlipped: Bool { true }

    init(language: String) {
        super.init(frame: CGRect(origin: .zero, size: Self.totalSize))
        setAccessibilityLabel(EditorStrings.text("Насыщенность и яркость", language: language))
        toolTip = EditorStrings.text("Оттенок", language: language)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The colour the markers stand on. Set from outside (the HEX field, a swatch) it moves them; a
    /// colour without a hue of its own leaves the strip where it is.
    var selectedColor: NSColor {
        get {
            let rgb = ColorConversion.hsvToRgb(hue: hue, saturation: saturation, value: brightness)
            return NSColor(srgbRed: CGFloat(rgb.red) / 255, green: CGFloat(rgb.green) / 255, blue: CGFloat(rgb.blue) / 255, alpha: 1)
        }
        set {
            guard let rgb = newValue.usingColorSpace(.sRGB) else { return }
            let converted = ColorConversion.rgbToHsv(
                RgbColor(
                    red: UInt8((rgb.redComponent * 255).rounded()),
                    green: UInt8((rgb.greenComponent * 255).rounded()),
                    blue: UInt8((rgb.blueComponent * 255).rounded())))
            if converted.saturation > 0 { hue = converted.hue }
            saturation = converted.saturation
            brightness = converted.value
            needsDisplay = true
        }
    }

    private var squareRect: CGRect { CGRect(x: 0, y: 0, width: Self.squareSide, height: Self.squareSide) }
    private var hueRect: CGRect { CGRect(x: Self.squareSide + Self.gap, y: 0, width: Self.hueWidth, height: Self.squareSide) }

    // MARK: - Picking

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if squareRect.contains(point) {
            draggingSquare = true
            pickInSquare(CGPoint(x: point.x - squareRect.minX, y: point.y - squareRect.minY))
        } else if hueRect.contains(point) {
            draggingHue = true
            pickInHue(CGPoint(x: point.x - hueRect.minX, y: point.y - hueRect.minY))
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if draggingSquare {
            pickInSquare(CGPoint(x: point.x - squareRect.minX, y: point.y - squareRect.minY))
        } else if draggingHue {
            pickInHue(CGPoint(x: point.x - hueRect.minX, y: point.y - hueRect.minY))
        }
    }

    // The press is what the picking runs on, and the release is what it is remembered by: a colour
    // dragged through is shown, a colour let go of can be saved.
    override func mouseUp(with event: NSEvent) {
        guard draggingSquare || draggingHue else { return }
        draggingSquare = false
        draggingHue = false
        onColorCommitted?(selectedColor)
    }

    override func resetCursorRects() {
        addCursorRect(squareRect, cursor: .crosshair)
        addCursorRect(hueRect, cursor: .crosshair)
    }

    /// Not private: the smoke probe picks without a pointer on screen (`ColorSpectrum.RunProbe`).
    func pickInSquare(_ position: CGPoint) {
        saturation = Double(min(max(position.x / Self.squareSide, 0), 1))
        brightness = 1 - Double(min(max(position.y / Self.squareSide, 0), 1))
        needsDisplay = true
        onColorChanged?(selectedColor)
    }

    func pickInHue(_ position: CGPoint) {
        hue = Double(min(max(position.y / Self.squareSide, 0), 1)) * 360
        needsDisplay = true
        onColorChanged?(selectedColor)
    }

    /// Where the hue marker stands, for the probe that checks a colour given from outside moved it.
    var hueMarkerCenterY: CGFloat { CGFloat(hue / 360) * Self.squareSide }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        drawSquare(ctx)
        drawHue(ctx)
        drawMarkers(ctx)
    }

    private func pureHueColor() -> NSColor {
        let rgb = ColorConversion.hsvToRgb(hue: hue, saturation: 1, value: 1)
        return NSColor(srgbRed: CGFloat(rgb.red) / 255, green: CGFloat(rgb.green) / 255, blue: CGFloat(rgb.blue) / 255, alpha: 1)
    }

    /// Saturation runs left to right over the hue in force, brightness top to bottom over black: two
    /// layers, because a single gradient cannot be both.
    private func drawSquare(_ ctx: CGContext) {
        let rounded = NSBezierPath(roundedRect: squareRect, xRadius: 6, yRadius: 6)
        ctx.saveGState()
        rounded.addClip()
        if let saturationGradient = NSGradient(starting: .white, ending: pureHueColor()) {
            saturationGradient.draw(in: squareRect, angle: 0)
        }
        if let brightnessGradient = NSGradient(starting: NSColor.black.withAlphaComponent(0), ending: .black) {
            brightnessGradient.draw(in: squareRect, angle: -90)
        }
        ctx.restoreGState()
        EditorTheme.appearanceHexFieldBorder.setStroke()
        rounded.lineWidth = 1
        rounded.stroke()
    }

    private func drawHue(_ ctx: CGContext) {
        let rounded = NSBezierPath(roundedRect: hueRect, xRadius: 6, yRadius: 6)
        ctx.saveGState()
        rounded.addClip()
        let stops: [NSColor] = (0...6).map { index in
            let rgb = ColorConversion.hsvToRgb(hue: Double(index) * 60, saturation: 1, value: 1)
            return NSColor(srgbRed: CGFloat(rgb.red) / 255, green: CGFloat(rgb.green) / 255, blue: CGFloat(rgb.blue) / 255, alpha: 1)
        }
        if let gradient = NSGradient(colors: stops, atLocations: [0, 1.0 / 6, 2.0 / 6, 0.5, 4.0 / 6, 5.0 / 6, 1], colorSpace: .sRGB) {
            // The view is flipped, so "down the strip" is `-90` in AppKit's own angle convention.
            gradient.draw(in: hueRect, angle: -90)
        }
        ctx.restoreGState()
        EditorTheme.appearanceHexFieldBorder.setStroke()
        rounded.lineWidth = 1
        rounded.stroke()
    }

    /// A white ring over a black one: the marker has to be seen on both ends of the square.
    private func drawMarkers(_ ctx: CGContext) {
        let x = squareRect.minX + CGFloat(saturation) * Self.squareSide
        let y = squareRect.minY + CGFloat(1 - brightness) * Self.squareSide
        let marker = NSBezierPath(ovalIn: CGRect(x: x - 7, y: y - 7, width: 14, height: 14))
        marker.lineWidth = 3
        NSColor.black.withAlphaComponent(0.4).setStroke()
        marker.stroke()
        marker.lineWidth = 1.5
        NSColor.white.setStroke()
        marker.stroke()

        let hueY = hueRect.minY + hueMarkerCenterY
        let hueMarker = NSBezierPath(roundedRect: CGRect(x: hueRect.midX - 11, y: hueY - 2, width: 22, height: 4), xRadius: 2, yRadius: 2)
        NSColor.white.setFill()
        hueMarker.fill()
        hueMarker.lineWidth = 1
        NSColor.black.withAlphaComponent(0.4).setStroke()
        hueMarker.stroke()
    }

    // MARK: - Smoke probe (port of `ColorSpectrum.RunProbe`)

    /// The strip moves the hue, the square moves the saturation and the brightness, a colour given
    /// from outside puts both markers where that colour lives, and a colour without a hue of its own
    /// leaves the strip where it stands.
    @MainActor
    @discardableResult
    static func smokeVerifySpectrum() -> Bool {
        let spectrum = ColorSpectrumView(language: "en")
        var changes = 0
        spectrum.onColorChanged = { _ in changes += 1 }
        spectrum.pickInHue(CGPoint(x: 8, y: 80))
        spectrum.pickInSquare(CGPoint(x: 160, y: 0))
        guard changes == 2, spectrum.selectedColor.hexRGB == "#00FFFF" else { return false }

        let blue = NSColor(srgbRed: 0x2F / 255, green: 0x8C / 255, blue: 0xFF / 255, alpha: 1)
        spectrum.selectedColor = blue
        let blueHue = ColorConversion.rgbToHsv(RgbColor(red: 0x2F, green: 0x8C, blue: 0xFF)).hue
        guard spectrum.selectedColor.hexRGB == blue.hexRGB else { return false }
        guard abs(spectrum.hueMarkerCenterY - CGFloat(blueHue / 360) * squareSide) <= 0.5 else { return false }

        // Black has no hue of its own; the strip must not jump back to red under it.
        spectrum.selectedColor = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        spectrum.pickInSquare(CGPoint(x: 160, y: 0))
        let expected = ColorConversion.hsvToRgb(hue: blueHue, saturation: 1, value: 1)
        let expectedColor = NSColor(
            srgbRed: CGFloat(expected.red) / 255, green: CGFloat(expected.green) / 255,
            blue: CGFloat(expected.blue) / 255, alpha: 1)
        return spectrum.selectedColor.hexRGB == expectedColor.hexRGB
    }
}
