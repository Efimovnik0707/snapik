// The five popovers of the panel and the key cheat sheet (`OverlayEditorWindow.xaml:283-437`),
// SPEC-DELTA-3 §1.4 E-3, E-16, E-17, E-18, E-19. View layer only: every decision about what a click
// means lives in `OverlayEditorController+Appearance.swift`.
import AppKit
import SnapikCore

/// Shared background of every popover: `NSPopover` clips and rounds its own bezel, so this only
/// fills a flat dark rectangle.
class EditorPopoverContentView: NSView {
    let outerPadding: CGFloat = 18
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        EditorTheme.appearancePopoverBackground.setFill()
        bounds.fill()
    }
}

/// `NSViewController` shell every popover below shares: it owns the content view and hands Escape
/// back to the controller.
@MainActor
class EditorPopoverViewController: NSViewController {
    let content: EditorPopoverContentView
    var onEscape: (() -> Void)?

    init(content: EditorPopoverContentView) {
        self.content = content
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Overridden by every subclass: the natural size of its content.
    func contentSize() -> NSSize { NSSize(width: 280, height: 200) }

    override func loadView() {
        view = content
        let size = contentSize()
        preferredContentSize = size
        content.frame = CGRect(origin: .zero, size: size)
    }

    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

// MARK: - Colour (E-16, E-17, E-18)

/// Port of `AppearancePopup` (`xaml:283-316`): three palette segments, the spectrum, the row of
/// twelve colours, the HEX field with "+" and the eyedropper beside it.
///
/// [ТЗ№4 D1] the spectrum and the eyedropper are shown with **every** palette, not only with the own
/// one, and the colour is no longer put into the own palette by itself: the "+" beside the HEX field
/// is what does that (`D-editor.md` §2.6).
final class EditorColorPopoverContentView: EditorPopoverContentView {
    static let width: CGFloat = 280

    let closeButton: EditorIconButtonView
    let paletteRow = EditorSegmentedRowView(frame: .zero)
    let spectrum: ColorSpectrumView
    let swatchWrap = AppearanceSwatchWrapView(frame: .zero)
    let hexField = NSTextField()
    let addToCustomButton: EditorIconButtonView
    let eyedropperButton: EditorIconButtonView
    private let titleLabel: NSTextField
    private let savedLabel: NSTextField

    init(language: String) {
        closeButton = EditorIconButtonView(symbolName: EditorIcon.close, tooltip: EditorStrings.closeTooltip(language), size: 22)
        spectrum = ColorSpectrumView(language: language)
        // The pair of its own this tooltip was waiting for arrived with the 1.5.0 round
        // (SPEC-DELTA-4 §3.4): the button says what it does instead of naming the palette it fills.
        addToCustomButton = EditorIconButtonView(symbolName: EditorIcon.add, tooltip: EditorStrings.addColorToCustomPalette(language))
        eyedropperButton = EditorIconButtonView(symbolName: EditorIcon.eyedropper, tooltip: EditorStrings.pickColorFromScreen(language))
        titleLabel = EditorPopoverChrome.label(EditorStrings.colorHeading(language), bold: true)
        savedLabel = EditorPopoverChrome.label(EditorStrings.savedColors(language), color: EditorTheme.textSecondary9A)
        savedLabel.font = EditorTheme.systemFont(11)
        super.init(frame: CGRect(x: 0, y: 0, width: Self.width, height: 0))

        addSubview(titleLabel)
        addSubview(closeButton)
        addSubview(paletteRow)
        addSubview(spectrum)
        addSubview(savedLabel)
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
        hexField.setAccessibilityLabel(EditorStrings.colorHexAccessibilityName(language))
        addSubview(hexField)
        addSubview(addToCustomButton)
        addSubview(eyedropperButton)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Port of `ColorHex.BorderBrush` toggling between `#465366` and `#FF6E6E` (`Appearance.cs:600`).
    func setHexFieldValid(_ valid: Bool) {
        hexField.layer?.borderColor = (valid ? EditorTheme.appearanceHexFieldBorder : EditorTheme.appearanceHexFieldErrorBorder).cgColor
    }

    private var contentWidth: CGFloat { Self.width - outerPadding * 2 }

    func fittingHeight() -> CGFloat {
        var y = outerPadding
        y += 22 + 12
        y += 34 + 12
        y += ColorSpectrumView.totalSize.height + 12
        y += 16 + 6
        y += max(swatchWrap.layoutSwatches(width: contentWidth), 34) + 10
        y += 34
        return y + outerPadding
    }

    override func layout() {
        super.layout()
        var y = outerPadding
        titleLabel.frame = CGRect(x: outerPadding, y: y, width: contentWidth - 28, height: 22)
        closeButton.frame = CGRect(x: bounds.width - outerPadding - 22, y: y, width: 22, height: 22)
        y += 22 + 12

        paletteRow.frame = CGRect(x: outerPadding, y: y, width: contentWidth, height: 34)
        y += 34 + 12

        spectrum.frame = CGRect(
            x: outerPadding + (contentWidth - ColorSpectrumView.totalSize.width) / 2, y: y,
            width: ColorSpectrumView.totalSize.width, height: ColorSpectrumView.totalSize.height)
        y += ColorSpectrumView.totalSize.height + 12

        savedLabel.frame = CGRect(x: outerPadding, y: y, width: contentWidth, height: 16)
        y += 16 + 6

        let wrapHeight = max(swatchWrap.layoutSwatches(width: contentWidth), 34)
        swatchWrap.frame = CGRect(x: outerPadding, y: y, width: contentWidth, height: wrapHeight)
        y += wrapHeight + 10

        let buttons: CGFloat = 34 * 2 + 6 * 2
        hexField.frame = CGRect(x: outerPadding, y: y + 2, width: contentWidth - buttons, height: 30)
        addToCustomButton.frame = CGRect(x: outerPadding + contentWidth - buttons + 6, y: y, width: 34, height: 34)
        eyedropperButton.frame = CGRect(x: outerPadding + contentWidth - 34, y: y, width: 34, height: 34)
    }
}

@MainActor
final class EditorColorPopoverViewController: EditorPopoverViewController, NSTextFieldDelegate {
    private let colorContent: EditorColorPopoverContentView
    private let language: String

    var onSwatchSelected: ((NSColor) -> Void)?
    var onHexCommitted: ((String) -> Void)?
    var onPaletteSelected: ((String) -> Void)?
    var onSpectrumChanged: ((NSColor) -> Void)?
    var onAddToCustomPalette: (() -> Void)?
    var onEyedropper: (() -> Void)?
    var onCloseClicked: (() -> Void)?

    init(language: String) {
        self.language = language
        colorContent = EditorColorPopoverContentView(language: language)
        super.init(content: colorContent)

        colorContent.paletteRow.setSegments(
            EditorAppearance.palettes.map { palette in
                let segment = EditorSegmentView(tag: palette.id, caption: EditorStrings.paletteName(palette.nameKey, language))
                segment.onClick = { [weak self] in self?.onPaletteSelected?(palette.id) }
                return segment
            })
        colorContent.hexField.delegate = self
        colorContent.closeButton.onClick = { [weak self] in self?.onCloseClicked?() }
        colorContent.addToCustomButton.onClick = { [weak self] in self?.onAddToCustomPalette?() }
        colorContent.eyedropperButton.onClick = { [weak self] in self?.onEyedropper?() }
        colorContent.spectrum.onColorChanged = { [weak self] color in self?.onSpectrumChanged?(color) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func contentSize() -> NSSize {
        NSSize(width: EditorColorPopoverContentView.width, height: colorContent.fittingHeight())
    }

    /// Port of `BuildColorPalette`/`BuildSwatches` (`Appearance.cs:184-216`): the twelve cells of the
    /// active palette, the own one padded out with empty slots so the row keeps its shape.
    func setPalette(_ palette: EditorPalette, selected: NSColor) {
        var swatches: [AppearanceColorSwatchView] = palette.colors.compactMap { hex in
            guard let color = EditorAppearance.color(fromHex: hex) else { return nil }
            let swatch = AppearanceColorSwatchView(color: color, tooltip: hex)
            swatch.onClick = { [weak self] in self?.onSwatchSelected?(color) }
            return swatch
        }
        if palette.id == "custom", swatches.count < HotkeySettings.maxCustomPaletteColors {
            for _ in swatches.count..<HotkeySettings.maxCustomPaletteColors {
                swatches.append(AppearanceColorSwatchView(color: nil, tooltip: nil))
            }
        }
        colorContent.swatchWrap.setSwatches(swatches)
        colorContent.paletteRow.choose(palette.id)
        colorContent.needsLayout = true
        preferredContentSize = contentSize()
        sync(selectedColor: selected)
    }

    /// Port of `SyncAppearance`'s colour-popover half.
    func sync(selectedColor: NSColor) {
        for swatch in colorContent.swatchWrap.swatches {
            swatch.isSelected = swatch.color.map { EditorAppearance.sameColor($0, selectedColor) } ?? false
        }
        if colorContent.hexField.currentEditor() == nil {
            colorContent.hexField.stringValue = selectedColor.hexRGB
        }
        colorContent.setHexFieldValid(true)
        colorContent.spectrum.selectedColor = selectedColor
    }

    func markHexInvalid() { colorContent.setHexFieldValid(false) }

    /// The smoke probe drives the spectrum without a pointer on screen.
    var spectrumView: ColorSpectrumView { colorContent.spectrum }
    var paletteSegments: EditorSegmentedRowView { colorContent.paletteRow }
    var swatchCount: Int { colorContent.swatchWrap.swatches.count }
    var filledSwatchCount: Int { colorContent.swatchWrap.swatches.filter { $0.color != nil }.count }
    var isSpectrumVisible: Bool { !colorContent.spectrum.isHidden }
    var isEyedropperVisible: Bool { !colorContent.eyedropperButton.isHidden }

    // MARK: - NSTextFieldDelegate (hex field Enter / focus-loss commit, Escape cancel)

    func controlTextDidEndEditing(_ obj: Notification) {
        onHexCommitted?(colorContent.hexField.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            onEscape?()
            return true
        }
        return false
    }
}

// MARK: - Thickness (E-3)

/// Port of `ThicknessPopup` (`xaml:319-350`): four presets, a slider whose range belongs to the tool
/// in the hand, and a preview of the stroke.
final class EditorValuePopoverContentView: EditorPopoverContentView {
    let titleLabel: NSTextField
    let valueLabel: NSTextField
    let presetRow = EditorSegmentedRowView(frame: .zero)
    let slider = EditorSliderView(frame: .zero)
    let preview: NSView
    /// The block of the pattern of a stroke, merged into this sheet with the round of 1.6.0
    /// (SPEC-DELTA-5-editor.md §3.10). `nil` in the popover of the size of a caption, which has no
    /// pattern to show.
    let lineStyleLabel: NSTextField?
    let lineStyleRow: EditorSegmentedRowView?
    private let previewHeight: CGFloat
    private let width: CGFloat

    init(width: CGFloat, title: String, preview: NSView, previewHeight: CGFloat, lineStyleTitle: String? = nil) {
        self.width = width
        self.preview = preview
        self.previewHeight = previewHeight
        titleLabel = EditorPopoverChrome.label(title, bold: true)
        valueLabel = EditorPopoverChrome.label("", color: EditorTheme.textSecondary9A, alignment: .right)
        lineStyleLabel = lineStyleTitle.map { EditorPopoverChrome.label($0, bold: true) }
        lineStyleRow = lineStyleTitle == nil ? nil : EditorSegmentedRowView(frame: .zero)
        super.init(frame: CGRect(x: 0, y: 0, width: width, height: 0))
        addSubview(titleLabel)
        addSubview(valueLabel)
        addSubview(presetRow)
        addSubview(slider)
        addSubview(preview)
        if let lineStyleLabel { addSubview(lineStyleLabel) }
        if let lineStyleRow { addSubview(lineStyleRow) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func fittingHeight() -> CGFloat {
        let base = outerPadding + 22 + 12 + 34 + 12 + 26 + 12 + previewHeight + outerPadding
        return lineStyleRow == nil ? base : base + 12 + 22 + 12 + 34
    }

    override func layout() {
        super.layout()
        let contentWidth = width - outerPadding * 2
        var y = outerPadding
        titleLabel.frame = CGRect(x: outerPadding, y: y, width: contentWidth - 90, height: 22)
        valueLabel.frame = CGRect(x: outerPadding + contentWidth - 90, y: y, width: 90, height: 22)
        y += 22 + 12
        presetRow.frame = CGRect(x: outerPadding, y: y, width: contentWidth, height: 34)
        y += 34 + 12
        slider.frame = CGRect(x: outerPadding, y: y, width: contentWidth, height: 26)
        y += 26 + 12
        preview.frame = CGRect(x: outerPadding, y: y, width: contentWidth, height: previewHeight)
        guard let lineStyleLabel, let lineStyleRow else { return }
        y += previewHeight + 12
        lineStyleLabel.frame = CGRect(x: outerPadding, y: y, width: contentWidth, height: 22)
        y += 22 + 12
        lineStyleRow.frame = CGRect(x: outerPadding, y: y, width: contentWidth, height: 34)
    }
}

@MainActor
final class EditorThicknessPopoverViewController: EditorPopoverViewController {
    private let valueContent: EditorValuePopoverContentView
    private let strokePreview = EditorStrokePreviewView(frame: .zero)

    var onPresetSelected: ((Double) -> Void)?
    var onSliderChanged: ((Double) -> Void)?
    /// The pattern of a stroke is picked in this same sheet since 1.6.0.
    var onStyleSelected: ((AnnotationLineStyle) -> Void)?

    init(language: String) {
        valueContent = EditorValuePopoverContentView(
            width: 252, title: EditorStrings.thickness(language), preview: strokePreview, previewHeight: 36,
            lineStyleTitle: EditorStrings.lineStyle(language))
        super.init(content: valueContent)
        valueContent.slider.setAccessibilityLabel(EditorStrings.strokeThicknessAccessibilityName(language))
        valueContent.slider.onValueChanged = { [weak self] value in self?.onSliderChanged?(value) }

        let titles: [(AnnotationLineStyle, String)] = [
            (.solid, EditorStrings.lineSolid(language)),
            (.dashed, EditorStrings.lineDashed(language)),
            (.dotted, EditorStrings.lineDotted(language)),
        ]
        valueContent.lineStyleRow?.setSegments(
            titles.map { style, title in
                let segment = EditorSegmentView(tag: style.rawValue, tooltip: title)
                segment.drawSample = { rect, color in
                    guard let ctx = NSGraphicsContext.current?.cgContext else { return }
                    AnnotationPainter.strokePath(
                        [[CGPoint(x: rect.minX + 6, y: rect.midY), CGPoint(x: rect.maxX - 6, y: rect.midY)]],
                        in: ctx, color: color, thickness: 2, lineStyle: style, highlight: false)
                }
                segment.onClick = { [weak self] in self?.onStyleSelected?(style) }
                return segment
            })
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func contentSize() -> NSSize { NSSize(width: 252, height: valueContent.fittingHeight()) }

    /// Port of `SyncAppearance`'s thickness half (`Appearance.cs:282-311`): the four presets and the
    /// range of the slider belong to the tool in the hand — the pencil counts in a few pixels, the
    /// highlighter in tens of them.
    func sync(
        presets: [Double], range: ClosedRange<Double>, value: Double, color: NSColor,
        lineStyle: AnnotationLineStyle, highlight: Bool, enabled: Bool, patterned: Bool
    ) {
        valueContent.presetRow.setSegments(
            presets.map { preset in
                let segment = EditorSegmentView(tag: "\(Int(preset))", tooltip: EditorStrings.pixelLabel(preset))
                segment.drawSample = { rect, color in
                    let height = min(20, CGFloat(preset))
                    let bar = CGRect(x: rect.midX - 12, y: rect.midY - height / 2, width: 24, height: height)
                    color.setFill()
                    NSBezierPath(roundedRect: bar, xRadius: height / 2, yRadius: height / 2).fill()
                }
                segment.onClick = { [weak self] in self?.onPresetSelected?(preset) }
                return segment
            })
        valueContent.presetRow.isEnabled = enabled
        valueContent.presetRow.choose(presets.contains(where: { abs($0 - value) < 0.001 }) ? "\(Int(value))" : "")
        valueContent.presetRow.needsLayout = true
        valueContent.valueLabel.stringValue = enabled ? EditorStrings.pixelLabel(value) : "\u{2014}"
        valueContent.slider.isEnabled = enabled
        valueContent.slider.setRange(range)
        valueContent.slider.setValue(value, notify: false)
        strokePreview.strokeColor = color
        strokePreview.strokeThickness = CGFloat(value)
        strokePreview.lineStyle = lineStyle
        strokePreview.isHighlight = highlight
        strokePreview.strokeHidden = !enabled
        valueContent.lineStyleRow?.isEnabled = patterned
        valueContent.lineStyleRow?.choose(lineStyle.rawValue)
    }
}

// MARK: - Fill (E-1)

/// Port of `FillPopup` (`xaml:409-437`): four segments and the twelve colours the inside of a region
/// can take. [ТЗ№4 D1] the fill stays a property of the shape, with a colour of its own.
final class EditorFillPopoverContentView: EditorPopoverContentView {
    static let width: CGFloat = 280
    let titleLabel: NSTextField
    let valueLabel: NSTextField
    let segmentRow = EditorSegmentedRowView(frame: .zero)
    let colorLabel: NSTextField
    let swatchWrap = AppearanceSwatchWrapView(frame: .zero)

    init(language: String) {
        titleLabel = EditorPopoverChrome.label(EditorStrings.fill(language), bold: true)
        valueLabel = EditorPopoverChrome.label("", color: EditorTheme.textSecondary9A, alignment: .right)
        colorLabel = EditorPopoverChrome.label(EditorStrings.fillColorHeading(language), bold: true)
        super.init(frame: CGRect(x: 0, y: 0, width: Self.width, height: 0))
        addSubview(titleLabel)
        addSubview(valueLabel)
        addSubview(segmentRow)
        addSubview(colorLabel)
        addSubview(swatchWrap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var contentWidth: CGFloat { Self.width - outerPadding * 2 }

    func fittingHeight() -> CGFloat {
        outerPadding + 22 + 12 + 34 + 18 + 18 + 8 + max(swatchWrap.layoutSwatches(width: contentWidth), 34) + outerPadding
    }

    override func layout() {
        super.layout()
        var y = outerPadding
        titleLabel.frame = CGRect(x: outerPadding, y: y, width: contentWidth - 120, height: 22)
        valueLabel.frame = CGRect(x: outerPadding + contentWidth - 120, y: y, width: 120, height: 22)
        y += 22 + 12
        segmentRow.frame = CGRect(x: outerPadding, y: y, width: contentWidth, height: 34)
        y += 34 + 18
        colorLabel.frame = CGRect(x: outerPadding, y: y, width: contentWidth, height: 18)
        y += 18 + 8
        let wrapHeight = max(swatchWrap.layoutSwatches(width: contentWidth), 34)
        swatchWrap.frame = CGRect(x: outerPadding, y: y, width: contentWidth, height: wrapHeight)
    }
}

@MainActor
final class EditorFillPopoverViewController: EditorPopoverViewController {
    private let fillContent: EditorFillPopoverContentView
    private let language: String

    var onFillSelected: ((AnnotationFill) -> Void)?
    var onFillColorSelected: ((NSColor) -> Void)?

    init(language: String) {
        self.language = language
        fillContent = EditorFillPopoverContentView(language: language)
        super.init(content: fillContent)

        let kinds: [(AnnotationFill, String)] = [
            (AnnotationFill.none, EditorStrings.fillOutline(language)),
            (.solid, EditorStrings.fillSolid(language)),
            (.translucent, EditorStrings.fillTranslucent(language)),
            (.blur, EditorStrings.fillBlur(language)),
        ]
        fillContent.segmentRow.setSegments(
            kinds.map { fill, title in
                let segment = EditorSegmentView(tag: fill.rawValue, tooltip: title)
                segment.drawSample = { rect, color in
                    let box = CGRect(x: rect.midX - 10, y: rect.midY - 7, width: 20, height: 14)
                    let path = NSBezierPath(roundedRect: box, xRadius: 2, yRadius: 2)
                    switch fill {
                    case .solid:
                        color.setFill()
                        path.fill()
                    case .translucent:
                        color.withAlphaComponent(64.0 / 255.0).setFill()
                        path.fill()
                    case .blur:
                        EditorTheme.blurPreviewFill.setFill()
                        path.fill()
                    case .none:
                        break
                    }
                    path.lineWidth = 1.5
                    color.setStroke()
                    path.stroke()
                }
                segment.onClick = { [weak self] in self?.onFillSelected?(fill) }
                return segment
            })
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func contentSize() -> NSSize {
        NSSize(width: EditorFillPopoverContentView.width, height: fillContent.fittingHeight())
    }

    func setPalette(_ palette: EditorPalette, selected: NSColor) {
        let swatches: [AppearanceColorSwatchView] = palette.colors.compactMap { hex in
            guard let color = EditorAppearance.color(fromHex: hex) else { return nil }
            let swatch = AppearanceColorSwatchView(color: color, tooltip: hex)
            swatch.onClick = { [weak self] in self?.onFillColorSelected?(color) }
            return swatch
        }
        fillContent.swatchWrap.setSwatches(swatches)
        fillContent.needsLayout = true
        preferredContentSize = contentSize()
        syncSelectedColor(selected)
    }

    func syncSelectedColor(_ color: NSColor) {
        for swatch in fillContent.swatchWrap.swatches {
            swatch.isSelected = swatch.color.map { EditorAppearance.sameColor($0, color) } ?? false
        }
    }

    /// Port of `SyncAppearance`'s fill half (`Appearance.cs:356-374`): a blurred region shows the
    /// picture under it and has no colour of its own to pick.
    func sync(fill: AnnotationFill, fillColor: NSColor, enabled: Bool) {
        fillContent.segmentRow.choose(fill.rawValue)
        fillContent.segmentRow.isEnabled = enabled
        fillContent.valueLabel.stringValue = EditorStrings.text(EditorAppearance.fillNameKey(fill), language: language)
        fillContent.swatchWrap.alphaValue = enabled && (fill == .solid || fill == .translucent) ? 1 : 0.4
        syncSelectedColor(fillColor)
    }
}

// MARK: - Caption size (E-6)

/// Port of `FontSizePopup` (`xaml:380-406`): six presets, a slider over 8..96 and the letters at the
/// size they will be typed in.
final class EditorFontSizePreviewView: NSView {
    var color: NSColor = EditorTheme.defaultAnnotationColor { didSet { needsDisplay = true } }
    var fontSize: CGFloat = 20 { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        EditorTheme.appearancePreviewBackground.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: EditorTheme.appearancePreviewCornerRadius, yRadius: EditorTheme.appearancePreviewCornerRadius).fill()
        let text = NSAttributedString(
            string: "Ag", attributes: [.font: EditorTheme.systemFont(min(44, fontSize)), .foregroundColor: color])
        let size = text.size()
        text.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
    }
}

@MainActor
final class EditorFontSizePopoverViewController: EditorPopoverViewController {
    private let valueContent: EditorValuePopoverContentView
    private let sizePreview = EditorFontSizePreviewView(frame: .zero)

    var onPresetSelected: ((Double) -> Void)?
    var onSliderChanged: ((Double) -> Void)?

    init(language: String) {
        valueContent = EditorValuePopoverContentView(
            width: 276, title: EditorStrings.fontSize(language), preview: sizePreview, previewHeight: 66)
        super.init(content: valueContent)
        valueContent.slider.setAccessibilityLabel(EditorStrings.fontSizeAccessibilityName(language))
        valueContent.slider.setRange(TextMarkMetrics.minimumFontSize...TextMarkMetrics.maximumFontSize)
        valueContent.slider.onValueChanged = { [weak self] value in self?.onSliderChanged?(value) }
        valueContent.presetRow.setSegments(
            TextMarkMetrics.fontSizePresets.map { preset in
                let segment = EditorSegmentView(tag: "\(Int(preset))", caption: "\(Int(preset))", tooltip: EditorStrings.pixelLabel(preset))
                segment.onClick = { [weak self] in self?.onPresetSelected?(preset) }
                return segment
            })
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func contentSize() -> NSSize { NSSize(width: 276, height: valueContent.fittingHeight()) }

    func sync(value: Double, color: NSColor) {
        let clamped = TextMarkMetrics.clamp(value)
        valueContent.valueLabel.stringValue = EditorStrings.pixelLabel(clamped)
        valueContent.presetRow.choose(
            TextMarkMetrics.fontSizePresets.contains(where: { abs($0 - clamped) < 0.001 }) ? "\(Int(clamped))" : "")
        valueContent.slider.setValue(clamped, notify: false)
        sizePreview.color = color
        sizePreview.fontSize = CGFloat(clamped)
    }
}

// MARK: - Key cheat sheet (E-19)

/// The key itself, in the capsule the cheat sheet and the tooltips show it in (`KeyCapsule`).
final class EditorKeyCapsuleView: NSView {
    private let label: NSTextField

    override var isFlipped: Bool { true }

    init(text: String) {
        label = EditorPopoverChrome.label(text, bold: true, color: EditorTheme.textPrimary, alignment: .center)
        label.font = EditorTheme.systemFont(11, weight: .semibold)
        super.init(frame: .zero)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func fittingWidth() -> CGFloat { label.attributedStringValue.size().width + 16 }

    override func layout() {
        super.layout()
        let size = label.attributedStringValue.size()
        label.frame = CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5)
        EditorTheme.appearancePreviewBackground.setFill()
        path.fill()
        path.lineWidth = 1
        EditorTheme.appearanceHexFieldBorder.setStroke()
        path.stroke()
    }
}

/// Port of `ShortcutSheetPopup` (`xaml:262-276`): two columns of rows, each a name and the key it is
/// on, shown as a capsule.
final class EditorShortcutSheetContentView: EditorPopoverContentView {
    private let titleLabel: NSTextField
    private let toolsHeader: NSTextField
    private let actionsHeader: NSTextField
    private var toolRows: [(name: NSTextField, key: EditorKeyCapsuleView)] = []
    private var actionRows: [(name: NSTextField, key: EditorKeyCapsuleView)] = []
    private let columnGap: CGFloat = 34
    private let rowHeight: CGFloat = 26

    init(language: String) {
        titleLabel = EditorPopoverChrome.label(EditorStrings.shortcutSheet(language), bold: true)
        toolsHeader = EditorPopoverChrome.label(EditorStrings.shortcutTools(language), bold: true, color: EditorTheme.textSecondary9A)
        toolsHeader.font = EditorTheme.systemFont(11, weight: .semibold)
        actionsHeader = EditorPopoverChrome.label(EditorStrings.shortcutActions(language), bold: true, color: EditorTheme.textSecondary9A)
        actionsHeader.font = EditorTheme.systemFont(11, weight: .semibold)
        super.init(frame: .zero)
        addSubview(titleLabel)
        addSubview(toolsHeader)
        addSubview(actionsHeader)

        for shortcut in EditorShortcuts.tools {
            let name = EditorPopoverChrome.label(EditorStrings.text(shortcut.nameKey, language: language))
            let key = EditorKeyCapsuleView(text: shortcut.caption)
            addSubview(name)
            addSubview(key)
            toolRows.append((name, key))
        }
        for action in EditorShortcuts.actions {
            let name = EditorPopoverChrome.label(EditorStrings.text(action.nameKey, language: language))
            let key = EditorKeyCapsuleView(text: action.caption)
            addSubview(name)
            addSubview(key)
            actionRows.append((name, key))
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func columnWidth(_ rows: [(name: NSTextField, key: EditorKeyCapsuleView)]) -> CGFloat {
        rows.reduce(CGFloat(0)) { widest, row in
            max(widest, row.name.attributedStringValue.size().width + 12 + row.key.fittingWidth())
        }
    }

    func fittingSize() -> NSSize {
        let left = max(columnWidth(toolRows), toolsHeader.attributedStringValue.size().width)
        let right = max(columnWidth(actionRows), actionsHeader.attributedStringValue.size().width)
        let rows = CGFloat(max(toolRows.count, actionRows.count))
        return NSSize(
            width: outerPadding * 2 + left + columnGap + right,
            height: outerPadding * 2 + 22 + 13 + 18 + 7 + rows * rowHeight)
    }

    override func layout() {
        super.layout()
        let left = max(columnWidth(toolRows), toolsHeader.attributedStringValue.size().width)
        let right = max(columnWidth(actionRows), actionsHeader.attributedStringValue.size().width)
        let rightX = outerPadding + left + columnGap

        titleLabel.frame = CGRect(x: outerPadding, y: outerPadding, width: bounds.width - outerPadding * 2, height: 22)
        let headerY = outerPadding + 22 + 13
        toolsHeader.frame = CGRect(x: outerPadding, y: headerY, width: left, height: 18)
        actionsHeader.frame = CGRect(x: rightX, y: headerY, width: right, height: 18)

        func place(_ rows: [(name: NSTextField, key: EditorKeyCapsuleView)], x: CGFloat, width: CGFloat) {
            var y = headerY + 18 + 7
            for row in rows {
                let keyWidth = row.key.fittingWidth()
                row.name.frame = CGRect(x: x, y: y + 4, width: width - keyWidth - 12, height: 18)
                row.key.frame = CGRect(x: x + width - keyWidth, y: y + 1, width: keyWidth, height: 22)
                y += rowHeight
            }
        }
        place(toolRows, x: outerPadding, width: left)
        place(actionRows, x: rightX, width: right)
    }
}

@MainActor
final class EditorShortcutSheetViewController: EditorPopoverViewController {
    private let sheetContent: EditorShortcutSheetContentView

    init(language: String) {
        sheetContent = EditorShortcutSheetContentView(language: language)
        super.init(content: sheetContent)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func contentSize() -> NSSize { sheetContent.fittingSize() }
}
