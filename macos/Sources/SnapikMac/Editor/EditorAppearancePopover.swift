// Port of the `AppearancePopup` (`OverlayEditorWindow.xaml:147-158`,
// `OverlayEditorWindow.Appearance.cs`), SPEC §1.3, §6.2 "Дополнение 2026-09-09". View layer only;
// `OverlayEditorController+Appearance.swift` owns the `NSPopover` lifecycle and every state/
// history decision.
import AppKit

/// One 34x34 color swatch button inside the popover's 12-swatch wrap panel
/// (`OverlayEditorWindow.Appearance.cs:27-36`): a 22x22 filled circle, a white ring when this
/// swatch's color is the currently-active one (mirrors the WPF swatch's `BorderBrush` toggling
/// between `White` and `Transparent` in `SyncAppearance`, `:63-64`).
final class AppearanceColorSwatchView: NSView {
    let color: NSColor
    var isSelected = false { didSet { needsDisplay = true } }
    private var isHovering = false { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?

    override var isFlipped: Bool { true }

    init(color: NSColor, tooltip: String) {
        self.color = color
        super.init(frame: CGRect(x: 0, y: 0, width: 34, height: 34))
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
    // Clicking a swatch never closes the popover (SPEC §1.3 point 2: "не закрывается при выборе
    // образца") — that guarantee lives in the popover's `.semitransient` behavior, not here.
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func draw(_ dirtyRect: NSRect) {
        let buttonPath = NSBezierPath(roundedRect: bounds, xRadius: EditorTheme.buttonCornerRadius, yRadius: EditorTheme.buttonCornerRadius)
        (isHovering ? EditorTheme.toolHoverBackground : .clear).setFill()
        buttonPath.fill()

        let ovalRect = bounds.insetBy(dx: 6, dy: 6)
        let oval = NSBezierPath(ovalIn: ovalRect)
        color.setFill()
        oval.fill()
        oval.lineWidth = 1
        (isSelected ? NSColor.white : .clear).setStroke()
        oval.stroke()
    }
}

/// Lays out `AppearanceColorSwatchView`s left-to-right, wrapping to a new row when a swatch would
/// overflow `width` (`WrapPanel`, `OverlayEditorWindow.xaml:151`). With the popover's fixed
/// 244pt content width and 12 34pt swatches (6pt gap), this always produces exactly 2 rows of 6.
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
            if x + itemSize > width, x > 0 { x = 0; y += itemSize + gap }
            swatch.frame = CGRect(x: x, y: y, width: itemSize, height: itemSize)
            x += itemSize + gap
        }
        return swatches.isEmpty ? 0 : y + itemSize
    }
}

/// The thickness preview strip (`Border Background="#222933" ... <Line StrokePreview .../>`,
/// `OverlayEditorWindow.xaml:155`). The background border is always drawn; the line itself is
/// hidden (not the whole strip) when the active tool has no stroke (SPEC §1.3 point 2: "для
/// текста толщина недоступна").
final class EditorAppearanceStrokePreviewView: NSView {
    var strokeColor: NSColor = EditorTheme.accent { didSet { needsDisplay = true } }
    var strokeThickness: CGFloat = 4 { didSet { needsDisplay = true } }
    var strokeHidden = false { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let background = NSBezierPath(roundedRect: bounds, xRadius: EditorTheme.appearancePreviewCornerRadius, yRadius: EditorTheme.appearancePreviewCornerRadius)
        EditorTheme.appearancePreviewBackground.setFill()
        background.fill()
        guard !strokeHidden else { return }

        let path = NSBezierPath()
        let y = bounds.midY
        path.move(to: CGPoint(x: 15, y: y))
        path.line(to: CGPoint(x: max(15, bounds.width - 15), y: y))
        path.lineWidth = strokeThickness
        path.lineCapStyle = .round
        strokeColor.setStroke()
        path.stroke()
    }
}

/// Hand-drawn 1...16 thickness slider, replacing `StrokeSliderStyle`'s custom `Slider`
/// `ControlTemplate` (`OverlayEditorWindow.xaml:40-52`): a 4pt track — filled `#5EAAFF` up to the
/// thumb, empty `#465366` after it — and a 16x16 round thumb (`#EEF2F8` fill, `#8193AB` 1pt
/// stroke). `IsMoveToPointEnabled="True"`'s "click anywhere on the track jumps the thumb there"
/// behavior is folded into `mouseDown`; dragging fires continuously like the WPF `ValueChanged`.
final class EditorAppearanceStrokeSliderView: NSView {
    let minValue: Double = 1
    let maxValue: Double = 16
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

    /// Sets the current value (clamped + rounded to the nearest integer pixel, matching
    /// `IsSnapToTickEnabled="True" TickFrequency="1"`). `notify: false` is used when the
    /// controller is echoing state back into the slider (`sync`) to avoid a feedback loop.
    func setValue(_ newValue: Double, notify: Bool) {
        let clamped = EditorGeometry.clamp(CGFloat(newValue), CGFloat(minValue), CGFloat(maxValue))
        value = Double(clamped.rounded())
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
        guard trackEnd > trackStart else { return }
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

/// The popover's content (`Border Width="280" Padding="18" ...`, `OverlayEditorWindow.xaml:147-158`):
/// header + close, the 12-swatch wrap panel, the hex field, a thickness header + value, the
/// slider, and the preview strip. NSPopover clips/rounds its own content view, so this draws a
/// plain full-bleed dark fill rather than its own rounded rect.
final class EditorAppearancePopoverContentView: NSView {
    static let width: CGFloat = 280
    private let outerPadding: CGFloat = 18
    private let closeSize: CGFloat = 22
    private let hexFieldHeight: CGFloat = 30
    private let sliderHeight: CGFloat = 26
    private let previewHeight: CGFloat = 36

    private let colorHeaderLabel = NSTextField(labelWithString: "")
    let closeButton: ChipCloseButtonView
    let swatchWrap = AppearanceSwatchWrapView(frame: .zero)
    let hexField = NSTextField()
    private let thicknessHeaderLabel = NSTextField(labelWithString: "")
    let strokeValueLabel = NSTextField(labelWithString: "")
    let strokeSlider = EditorAppearanceStrokeSliderView(frame: .zero)
    let previewView = EditorAppearanceStrokePreviewView(frame: .zero)

    override var isFlipped: Bool { true }

    init(colorTitle: String, closeTooltip: String, thicknessTitle: String, hexAccessibilityName: String, sliderAccessibilityName: String) {
        closeButton = ChipCloseButtonView(size: 22, tooltip: closeTooltip)
        super.init(frame: CGRect(x: 0, y: 0, width: Self.width, height: 0))

        colorHeaderLabel.stringValue = colorTitle
        style(label: colorHeaderLabel, bold: true, color: EditorTheme.textPrimary)
        addSubview(colorHeaderLabel)
        addSubview(closeButton)

        addSubview(swatchWrap)

        hexField.isBezeled = false
        hexField.isBordered = false
        hexField.drawsBackground = true
        hexField.backgroundColor = EditorTheme.appearanceHexFieldBackground
        hexField.textColor = EditorTheme.textPrimary
        hexField.font = EditorTheme.systemFont(13)
        hexField.focusRingType = .none
        hexField.wantsLayer = true
        hexField.layer?.cornerRadius = 7
        hexField.layer?.borderWidth = 1
        hexField.layer?.borderColor = EditorTheme.appearanceHexFieldBorder.cgColor
        hexField.setAccessibilityLabel(hexAccessibilityName)
        addSubview(hexField)

        thicknessHeaderLabel.stringValue = thicknessTitle
        style(label: thicknessHeaderLabel, bold: true, color: EditorTheme.textPrimary)
        addSubview(thicknessHeaderLabel)

        strokeValueLabel.alignment = .right
        style(label: strokeValueLabel, bold: false, color: EditorTheme.textSecondary9A)
        addSubview(strokeValueLabel)

        strokeSlider.setAccessibilityLabel(sliderAccessibilityName)
        addSubview(strokeSlider)

        addSubview(previewView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func style(label: NSTextField, bold: Bool, color: NSColor) {
        label.font = EditorTheme.systemFont(13, weight: bold ? .semibold : .regular)
        label.textColor = color
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        label.isSelectable = false
    }

    /// Port of `ColorHex.BorderBrush` toggling between `#465366` and `#FF6E6E`
    /// (`OverlayEditorWindow.Appearance.cs:56,91`).
    func setHexFieldValid(_ valid: Bool) {
        hexField.layer?.borderColor = (valid ? EditorTheme.appearanceHexFieldBorder : EditorTheme.appearanceHexFieldErrorBorder).cgColor
    }

    /// The content's natural size for `NSViewController.preferredContentSize`.
    func fittingSize() -> NSSize {
        let contentWidth = Self.width - outerPadding * 2
        let wrapHeight = max(swatchWrap.layoutSwatches(width: contentWidth), 34)
        var y: CGFloat = outerPadding
        y += 22 + 14
        y += wrapHeight + 10
        y += hexFieldHeight + 18
        y += 18 + 8
        y += sliderHeight + 12
        y += previewHeight
        y += outerPadding
        return NSSize(width: Self.width, height: y)
    }

    override func layout() {
        super.layout()
        let contentWidth = bounds.width - outerPadding * 2
        var y: CGFloat = outerPadding

        colorHeaderLabel.frame = CGRect(x: outerPadding, y: y, width: contentWidth - closeSize - 6, height: 22)
        closeButton.frame = CGRect(x: bounds.width - outerPadding - closeSize, y: y, width: closeSize, height: closeSize)
        y += 22 + 14

        let wrapHeight = max(swatchWrap.layoutSwatches(width: contentWidth), 34)
        swatchWrap.frame = CGRect(x: outerPadding, y: y, width: contentWidth, height: wrapHeight)
        y += wrapHeight + 10

        hexField.frame = CGRect(x: outerPadding, y: y, width: contentWidth, height: hexFieldHeight)
        y += hexFieldHeight + 18

        thicknessHeaderLabel.frame = CGRect(x: outerPadding, y: y, width: contentWidth - 80, height: 18)
        strokeValueLabel.frame = CGRect(x: outerPadding + contentWidth - 80, y: y, width: 80, height: 18)
        y += 18 + 8

        strokeSlider.frame = CGRect(x: outerPadding, y: y, width: contentWidth, height: sliderHeight)
        y += sliderHeight + 12

        previewView.frame = CGRect(x: outerPadding, y: y, width: contentWidth, height: previewHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        EditorTheme.appearancePopoverBackground.setFill()
        bounds.fill()
    }
}

/// Hosts `EditorAppearancePopoverContentView` inside the `NSPopover`. Builds the 12 fixed swatches
/// once (mirrors `OpenAppearance`'s `ColorPalette.Children.Count == 0` lazy build) and forwards
/// every user interaction to the controller via closures — `OverlayEditorController+Appearance.swift`
/// owns all state/history decisions (CHECK-API: this is this codebase's first `NSPopover`/
/// `NSViewController`/`NSTextFieldDelegate` usage; the `.semitransient` behavior, the popover's
/// own Escape-to-close handling, and `control(_:textView:doCommandBy:)` intercepting
/// `cancelOperation` are standard, well-documented AppKit patterns but were not exercisable
/// without a compiler here).
@MainActor
final class EditorAppearancePopoverViewController: NSViewController, NSTextFieldDelegate {
    private let contentViewInstance: EditorAppearancePopoverContentView
    private var swatchViews: [AppearanceColorSwatchView] = []

    var onSwatchSelected: ((NSColor) -> Void)?
    var onHexCommitted: ((String) -> Void)?
    var onThicknessChanged: ((Double) -> Void)?
    var onCloseClicked: (() -> Void)?
    /// SPEC §1.3 point 2 / §7.5-style convention: plain Escape while the hex field has focus
    /// closes the popover (`OnAppearanceKeyDown`, `OverlayEditorWindow.Appearance.cs:95`).
    var onEscape: (() -> Void)?

    init(language: String) {
        contentViewInstance = EditorAppearancePopoverContentView(
            colorTitle: EditorStrings.colorHeading(language),
            closeTooltip: EditorStrings.closeTooltip(language),
            thicknessTitle: EditorStrings.thickness(language),
            hexAccessibilityName: EditorStrings.colorHexAccessibilityName(language),
            sliderAccessibilityName: EditorStrings.strokeThicknessAccessibilityName(language))
        super.init(nibName: nil, bundle: nil)

        swatchViews = zip(EditorTheme.annotationPaletteHex, EditorTheme.annotationPalette).map { hex, color in
            let swatch = AppearanceColorSwatchView(color: color, tooltip: hex)
            swatch.onClick = { [weak self] in self?.onSwatchSelected?(color) }
            return swatch
        }
        contentViewInstance.swatchWrap.setSwatches(swatchViews)

        contentViewInstance.hexField.delegate = self
        contentViewInstance.closeButton.onClick = { [weak self] in self?.onCloseClicked?() }
        contentViewInstance.strokeSlider.onValueChanged = { [weak self] value in self?.onThicknessChanged?(value) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        view = contentViewInstance
        let size = contentViewInstance.fittingSize()
        preferredContentSize = size
        contentViewInstance.frame = CGRect(origin: .zero, size: size)
    }

    /// Port of `SyncAppearance`'s popover-facing half (`OverlayEditorWindow.Appearance.cs:42-69`).
    func sync(selectedColor: NSColor, hexText: String, thicknessValue: Double, hasStroke: Bool) {
        for swatch in swatchViews { swatch.isSelected = colorsMatch(swatch.color, selectedColor) }
        // Don't clobber text the user is actively typing (defensive; Windows always overwrites
        // `ColorHex.Text` here too, but nothing normally re-syncs mid-keystroke — see this file's
        // header comment on why that's safe there).
        if contentViewInstance.hexField.currentEditor() == nil {
            contentViewInstance.hexField.stringValue = hexText
        }
        contentViewInstance.setHexFieldValid(true)
        contentViewInstance.strokeSlider.isEnabled = hasStroke
        contentViewInstance.strokeSlider.setValue(thicknessValue, notify: false)
        contentViewInstance.strokeValueLabel.stringValue = hasStroke ? EditorStrings.thicknessLabel(thicknessValue) : "\u{2014}"
        contentViewInstance.previewView.strokeColor = selectedColor
        contentViewInstance.previewView.strokeThickness = CGFloat(thicknessValue)
        contentViewInstance.previewView.strokeHidden = !hasStroke
    }

    /// Port of `OnHexLostFocus`/`ApplyHex`'s invalid-input feedback (`:56,91`).
    func markHexInvalid() {
        contentViewInstance.setHexFieldValid(false)
    }

    private func colorsMatch(_ a: NSColor, _ b: NSColor) -> Bool {
        guard let ca = a.usingColorSpace(.deviceRGB), let cb = b.usingColorSpace(.deviceRGB) else { return false }
        return abs(ca.redComponent - cb.redComponent) < 0.004
            && abs(ca.greenComponent - cb.greenComponent) < 0.004
            && abs(ca.blueComponent - cb.blueComponent) < 0.004
    }

    // MARK: - NSTextFieldDelegate (hex field Enter / focus-loss commit, Escape cancel)

    /// Fires on both Return and focus loss (standard `NSTextFieldDelegate` behavior), covering
    /// the Windows source's `OnHexKeyDown` (Enter) and `OnHexLostFocus` in one method.
    func controlTextDidEndEditing(_ obj: Notification) {
        onHexCommitted?(contentViewInstance.hexField.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            onEscape?()
            return true
        }
        return false
    }
}
