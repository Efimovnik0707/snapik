// Port of the `Toolbar` floating panel (`OverlayEditorWindow.xaml:190-282`), SPEC §6.2,
// SPEC-DELTA-3 §1.4 E-3, E-4, E-5, E-11, E-19.
import AppKit
import SnapikCore

/// Shared chrome of every button on the panel: a rounded rect that fills on hover, on "armed" and
/// on "checked", and reports a click. Subclasses only draw their content.
class ToolbarButtonBaseView: NSView {
    var isChecked = false { didSet { needsDisplay = true } }
    /// The soft accent behind the chevron half of a split capsule whose tool is armed
    /// (`SyncAppearance`'s `ShapeMenuButton.Background`, `Appearance.cs:330-333`).
    var isArmed = false { didSet { needsDisplay = true } }
    var isEnabled = true {
        didSet {
            alphaValue = isEnabled ? 1 : 0.4
            needsDisplay = true
        }
    }
    private(set) var isHovering = false { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }
    override func mouseExited(with event: NSEvent) { isHovering = false }
    override func mouseDown(with event: NSEvent) { if isEnabled { onClick?() } }
    override func resetCursorRects() { if isEnabled { addCursorRect(bounds, cursor: .pointingHand) } }

    /// The colour the content is drawn with: white while the button is checked, muted otherwise.
    var contentColor: NSColor {
        isChecked ? .white : EditorTheme.textSecondaryD9
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: EditorTheme.toolCornerRadius, yRadius: EditorTheme.toolCornerRadius)
        if isChecked {
            EditorTheme.toolActiveBackground.setFill()
            path.fill()
            path.lineWidth = 1
            EditorTheme.accent.setStroke()
            path.stroke()
        } else if isArmed {
            AccentPalette.wash(alpha: 0.22).setFill()
            path.fill()
        } else if isHovering, isEnabled {
            EditorTheme.toolHoverBackground.setFill()
            path.fill()
        }
        drawContent()
    }

    /// Overridden by every subclass; the base draws nothing of its own.
    func drawContent() {}
}

/// 36x36 tool toggle (SPEC §6.2). Draws a system symbol, or — for the blur waves, the one mark with
/// no system glyph — a path in its own 16-unit box (`EditorIcon`).
final class ToolbarToggleButtonView: ToolbarButtonBaseView {
    let tool: EditorTool
    private let symbolName: String?
    private let pathData: String?

    init(tool: EditorTool, tooltip: String, symbolName: String? = nil, pathData: String? = nil) {
        self.tool = tool
        self.symbolName = symbolName
        self.pathData = pathData
        super.init(frame: CGRect(x: 0, y: 0, width: 36, height: 36))
        toolTip = tooltip
        setAccessibilityLabel(tooltip)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func drawContent() {
        if let symbolName {
            EditorIcon.draw(symbol: symbolName, in: bounds, color: contentColor)
        } else if let pathData {
            IconPath.draw(pathData, in: bounds.insetBy(dx: 10, dy: 10), nativeSize: 16, stroke: contentColor, lineWidth: 1.4)
        }
    }
}

/// The chevron half of a split capsule (`OverlayToolChevron`, width 23): the shape menu beside the
/// region, the style menu beside the arrow, the pen/highlighter menu beside the pencil.
final class ToolbarChevronButtonView: ToolbarButtonBaseView {
    init(tooltip: String) {
        super.init(frame: CGRect(x: 0, y: 0, width: 23, height: 36))
        toolTip = tooltip
        setAccessibilityLabel(tooltip)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func drawContent() {
        EditorIcon.draw(symbol: EditorIcon.chevronDown, in: bounds, color: contentColor, pointSize: 9, weight: .semibold)
    }
}

/// A fixed-width button carrying a value that is never blanked (`ThicknessButton`, `LineStyleButton`,
/// `FillButton`, `FontSizeButton`): SPEC-DELTA-3 §1.4 E-11 — the panel must not change width when
/// the tool in the hand changes, so a tool without the property keeps the last value, dimmed.
final class ToolbarValueButtonView: ToolbarButtonBaseView {
    private let label = NSTextField(labelWithString: "")
    private let previewWidth: CGFloat
    /// Draws whatever stands to the left of the caption, inside the rect it is given.
    var drawPreview: ((CGRect) -> Void)?

    var text: String {
        get { label.stringValue }
        set {
            label.stringValue = newValue
            needsLayout = true
            needsDisplay = true
        }
    }

    init(width: CGFloat, tooltip: String, previewWidth: CGFloat = 0) {
        self.previewWidth = previewWidth
        super.init(frame: CGRect(x: 0, y: 0, width: width, height: 36))
        toolTip = tooltip
        setAccessibilityLabel(tooltip)
        label.font = EditorTheme.systemFont(13)
        label.textColor = EditorTheme.textPrimary
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        label.isSelectable = false
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        let size = label.attributedStringValue.size()
        let contentWidth = previewWidth > 0 ? previewWidth + 7 + size.width : size.width
        let left = (bounds.width - contentWidth) / 2
        label.frame = CGRect(
            x: left + (previewWidth > 0 ? previewWidth + 7 : 0), y: (bounds.height - size.height) / 2,
            width: size.width, height: size.height)
    }

    override func drawContent() {
        guard previewWidth > 0, let drawPreview else { return }
        let size = label.attributedStringValue.size()
        let contentWidth = previewWidth + 7 + size.width
        let left = (bounds.width - contentWidth) / 2
        drawPreview(CGRect(x: left, y: (bounds.height - 14) / 2, width: previewWidth, height: 14))
    }
}

/// The colour button: a circle and nothing else (`AppearanceButton`, `xaml:229-231`). [ТЗ№4 D1] it
/// is never disabled — a colour is accepted with every tool in the hand, the Comment included.
final class ToolbarSwatchButtonView: ToolbarButtonBaseView {
    var color: NSColor = EditorTheme.defaultAnnotationColor { didSet { needsDisplay = true } }

    init(tooltip: String) {
        super.init(frame: CGRect(x: 0, y: 0, width: 36, height: 36))
        toolTip = tooltip
        setAccessibilityLabel(tooltip)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func drawContent() {
        let circle = NSBezierPath(ovalIn: CGRect(x: bounds.midX - 8, y: bounds.midY - 8, width: 16, height: 16))
        color.setFill()
        circle.fill()
        circle.lineWidth = 1
        EditorTheme.textPrimary.setStroke()
        circle.stroke()
    }
}

/// One dot of the quick row on the panel (`ColorDots`, `Appearance.cs:220-240`): 22 pt of button and
/// 14 of colour, ringed in white when it is the colour in force.
final class ToolbarColorDotView: ToolbarButtonBaseView {
    static let ringColor = NSColor(hex: "#788292")

    let color: NSColor
    var isCurrent = false { didSet { needsDisplay = true } }

    init(color: NSColor, tooltip: String) {
        self.color = color
        super.init(frame: CGRect(x: 0, y: 0, width: 22, height: 22))
        toolTip = tooltip
        setAccessibilityLabel(tooltip)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func drawContent() {
        let circle = NSBezierPath(ovalIn: CGRect(x: bounds.midX - 7, y: bounds.midY - 7, width: 14, height: 14))
        color.setFill()
        circle.fill()
        circle.lineWidth = 1
        (isCurrent ? NSColor.white : Self.ringColor).setStroke()
        circle.stroke()
    }
}

/// Variable-width action button (undo/redo/save/`Готово`, SPEC §6.2). Height 36, min width 36.
final class ToolbarActionButtonView: ToolbarButtonBaseView {
    private let symbolName: String?
    private let textLabel: NSTextField?
    private let filledBackground: NSColor?

    /// Text-content button (`Готово`).
    init(text: String, tooltip: String? = nil, filledBackground: NSColor? = nil, bold: Bool = false) {
        symbolName = nil
        self.filledBackground = filledBackground
        let label = NSTextField(labelWithString: text)
        label.font = EditorTheme.systemFont(13, weight: bold ? .semibold : .regular)
        label.textColor = filledBackground != nil ? .white : EditorTheme.textPrimary
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        label.isSelectable = false
        textLabel = label
        super.init(frame: .zero)
        toolTip = tooltip
        setAccessibilityLabel(tooltip ?? text)
        addSubview(label)
        let size = label.attributedStringValue.size()
        frame.size = NSSize(width: max(36, size.width + 22), height: 36)
    }

    /// Symbol-content button (undo/redo/save/cheat sheet).
    init(symbolName: String, tooltip: String, width: CGFloat = 36) {
        self.symbolName = symbolName
        filledBackground = nil
        textLabel = nil
        super.init(frame: CGRect(x: 0, y: 0, width: width, height: 36))
        toolTip = tooltip
        setAccessibilityLabel(tooltip)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        guard let textLabel else { return }
        let size = textLabel.attributedStringValue.size()
        textLabel.frame = CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        if let filledBackground {
            let path = NSBezierPath(roundedRect: bounds, xRadius: EditorTheme.buttonCornerRadius, yRadius: EditorTheme.buttonCornerRadius)
            filledBackground.setFill()
            path.fill()
            return
        }
        super.draw(dirtyRect)
    }

    override func drawContent() {
        guard let symbolName else { return }
        EditorIcon.draw(symbol: symbolName, in: bounds, color: EditorTheme.textPrimary)
    }
}

/// The `Border Width="1" Height="22" Background="#3A424E"` separator between the tool group and the
/// undo/redo/save/done group (SPEC §6.2).
final class ToolbarDividerView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        EditorTheme.toolbarDivider.setFill()
        NSBezierPath(rect: bounds).fill()
    }
}

/// The floating toolbar container (SPEC §6.2). Owns the exact button set and order and forwards
/// clicks via closures; `OverlayEditorController+Editing`/`+Appearance` own positioning and state.
///
/// SPEC-DELTA-3 §1.4 E-11: the row never changes width with the tool in the hand (every value button
/// has a fixed width and a caption that is never blanked), and when the working area is narrower than
/// the row, the tail wraps onto a second line instead of running off the screen.
final class EditorToolbarView: NSView {
    let selectButton: ToolbarToggleButtonView
    let rectangleButton: ToolbarToggleButtonView
    let shapeMenuButton: ToolbarChevronButtonView
    let arrowButton: ToolbarToggleButtonView
    let arrowOptionsButton: ToolbarChevronButtonView
    let pencilButton: ToolbarToggleButtonView
    let pencilMenuButton: ToolbarChevronButtonView
    let textButton: ToolbarToggleButtonView
    let eraserButton: ToolbarToggleButtonView
    let blurButton: ToolbarToggleButtonView
    let cropButton: ToolbarToggleButtonView
    let colorDotsView = NSView(frame: .zero)
    let appearanceButton: ToolbarSwatchButtonView
    let thicknessButton: ToolbarValueButtonView
    let lineStyleButton: ToolbarValueButtonView
    let fillButton: ToolbarValueButtonView
    let fontSizeButton: ToolbarValueButtonView
    let commentButton: ToolbarToggleButtonView
    let shortcutSheetButton: ToolbarActionButtonView
    let undoButton: ToolbarActionButtonView
    let redoButton: ToolbarActionButtonView
    let saveButton: ToolbarActionButtonView
    let doneButton: ToolbarActionButtonView
    private let divider = ToolbarDividerView(frame: .zero)

    private var toolButtons: [ToolbarToggleButtonView] = []
    private var dotViews: [ToolbarColorDotView] = []
    private var dotHexes: [String] = []
    /// The three blocks of the panel (`ToolbarTools`, `ToolbarProperties`, `ToolbarActions`,
    /// `xaml:212-221`): the tools, the properties of the one in hand and the buttons on the right.
    /// They are laid out apart, and the properties are the block that goes to the second row.
    private var toolsOrder: [NSView] = []
    private var propertiesOrder: [NSView] = []
    private var actionsOrder: [NSView] = []

    var onToolSelected: ((EditorTool) -> Void)?
    var onQuickColor: ((NSColor) -> Void)?
    /// The panel is dragged by its free place; the three are separate so that a probe can move it
    /// without an `NSEvent` to carry a pointer (SPEC-DELTA-5-editor.md §1.2 E-2). Points are in the
    /// space of the superview, which is the one the frame of the panel lives in.
    var onDragBegan: ((CGPoint) -> Void)?
    var onDragMoved: ((CGPoint) -> Void)?
    var onDragEnded: (() -> Void)?

    /// The widest the row may lay itself out in; the controller sets it from the working area of the
    /// monitor the capture is on (SPEC-DELTA-3 §1.4 E-11 — the probe measures against a synthetic
    /// rectangle, not against a live monitor).
    var maximumWidth: CGFloat = .greatestFiniteMagnitude

    override var isFlipped: Bool { true }

    init(language: String) {
        func toggle(_ tool: EditorTool, _ symbol: String?, _ path: String? = nil) -> ToolbarToggleButtonView {
            ToolbarToggleButtonView(tool: tool, tooltip: EditorShortcuts.caption(tool, language: language), symbolName: symbol, pathData: path)
        }

        selectButton = toggle(.select, EditorIcon.select)
        rectangleButton = toggle(.rectangle, EditorIcon.rectangle)
        shapeMenuButton = ToolbarChevronButtonView(tooltip: EditorStrings.shape(language))
        arrowButton = toggle(.arrow, EditorIcon.arrow)
        arrowOptionsButton = ToolbarChevronButtonView(tooltip: EditorStrings.arrowStyle(language))
        pencilButton = toggle(.pen, EditorIcon.pencil)
        pencilMenuButton = ToolbarChevronButtonView(tooltip: EditorStrings.toolPencil(language))
        textButton = toggle(.text, EditorIcon.text)
        eraserButton = toggle(.eraser, EditorIcon.eraser)
        blurButton = toggle(.blur, nil, EditorIcon.blurPath)
        cropButton = toggle(.crop, EditorIcon.crop)
        appearanceButton = ToolbarSwatchButtonView(tooltip: EditorStrings.colorHeading(language))
        thicknessButton = ToolbarValueButtonView(width: 64, tooltip: EditorStrings.thickness(language))
        lineStyleButton = ToolbarValueButtonView(width: 64, tooltip: EditorStrings.lineStyle(language), previewWidth: 28)
        fillButton = ToolbarValueButtonView(width: 96, tooltip: EditorStrings.fill(language), previewWidth: 20)
        fontSizeButton = ToolbarValueButtonView(width: 64, tooltip: EditorStrings.fontSize(language))
        commentButton = toggle(.comment, EditorIcon.comment)
        shortcutSheetButton = ToolbarActionButtonView(symbolName: EditorIcon.shortcutSheet, tooltip: EditorStrings.shortcutSheet(language), width: 30)
        // Undo/redo/save show the Mac keyboard mapping (§7.6: Cmd+Z / Shift+Cmd+Z / Cmd+S), appended
        // here to the pair Windows carries without keys in it.
        undoButton = ToolbarActionButtonView(symbolName: EditorIcon.undo, tooltip: "\(EditorStrings.undo(language)) (Cmd+Z)")
        redoButton = ToolbarActionButtonView(symbolName: EditorIcon.redo, tooltip: "\(EditorStrings.redo(language)) (Shift+Cmd+Z)")
        saveButton = ToolbarActionButtonView(
            symbolName: EditorIcon.save, tooltip: "\(EditorStrings.saveToComputer(language)) (Cmd+S)")
        doneButton = ToolbarActionButtonView(text: EditorStrings.done(language), filledBackground: EditorTheme.accent, bold: true)

        super.init(frame: .zero)

        toolButtons = [
            selectButton, rectangleButton, arrowButton, pencilButton, textButton, eraserButton,
            blurButton, cropButton, commentButton,
        ]
        for button in toolButtons {
            button.onClick = { [weak self, weak button] in
                guard let button else { return }
                self?.onToolSelected?(button.tool)
            }
        }
        thicknessButton.text = EditorStrings.pixelLabel(EditorAppearance.defaultAnnotationThickness)
        fontSizeButton.text = EditorStrings.pixelLabel(TextMarkMetrics.defaultFontSize)
        fillButton.text = EditorStrings.fillOutline(language)

        toolsOrder = [
            selectButton, rectangleButton, shapeMenuButton, arrowButton, arrowOptionsButton,
            pencilButton, pencilMenuButton, textButton, eraserButton, blurButton, cropButton,
            commentButton, shortcutSheetButton,
        ]
        propertiesOrder = [
            colorDotsView, appearanceButton, thicknessButton, lineStyleButton, fillButton,
            fontSizeButton,
        ]
        actionsOrder = [divider, undoButton, redoButton, saveButton, doneButton]
        for view in toolsOrder + propertiesOrder + actionsOrder { addSubview(view) }
        setActiveTool(.rectangle)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - State

    func setActiveTool(_ tool: EditorTool) {
        for button in toolButtons { button.isChecked = button.tool == tool }
        // The pencil capsule shows whichever half is armed (`PencilCapsuleGlyph`,
        // `OverlayEditorWindow.xaml.cs:1008`).
        pencilButton.isChecked = tool == .pen || tool == .highlight
        // The chevron half of a split capsule carries the state of its own tool, so the capsule
        // reads as one control (`Appearance.cs:330-333`).
        shapeMenuButton.isArmed = tool == .rectangle
        arrowOptionsButton.isArmed = tool == .arrow
        pencilMenuButton.isArmed = tool == .pen || tool == .highlight
    }

    func setUndoRedoEnabled(canUndo: Bool, canRedo: Bool) {
        undoButton.isEnabled = canUndo
        redoButton.isEnabled = canRedo
    }

    /// Port of `BuildColorDots` (`Appearance.cs:220-240`): the quick row of the active palette. The
    /// row is rebuilt only when the palette behind it changed — every sync of the panel calls this,
    /// and a colour dragged through the spectrum syncs on every move of the mouse.
    func setQuickColors(_ hexes: [String], current: NSColor) {
        guard dotHexes != hexes else {
            setCurrentQuickColor(current)
            return
        }
        dotHexes = hexes
        for dot in dotViews { dot.removeFromSuperview() }
        dotViews = hexes.compactMap { hex in
            guard let color = EditorAppearance.color(fromHex: hex) else { return nil }
            let dot = ToolbarColorDotView(color: color, tooltip: hex)
            dot.onClick = { [weak self] in self?.onQuickColor?(color) }
            return dot
        }
        for dot in dotViews { colorDotsView.addSubview(dot) }
        colorDotsView.frame.size = NSSize(width: max(0, CGFloat(dotViews.count) * 24), height: 36)
        var x: CGFloat = 0
        for dot in dotViews {
            dot.frame = CGRect(x: x + 1, y: 7, width: 22, height: 22)
            x += 24
        }
        setCurrentQuickColor(current)
    }

    func setCurrentQuickColor(_ color: NSColor) {
        for dot in dotViews { dot.isCurrent = EditorAppearance.sameColor(dot.color, color) }
    }

    // MARK: - Layout (SPEC-DELTA-5-editor.md §1.2 E-2, `xaml.cs:1926-1962`)

    /// The width of the properties block, whatever stands in it (`ToolbarPropertiesWidth`). It is a
    /// requirement and not a nicety: while the block measures itself by its contents, "one row or
    /// two" changes with the tool in the hand and the panel jumps under the cursor.
    static let propertiesWidth: CGFloat = 176

    private static let padding: CGFloat = 7
    private static let itemMargin: CGFloat = 2
    private static let rowHeight: CGFloat = 36
    /// The air between the two rows (`ToolbarLayout.Measure`'s `rowGap`).
    private static let rowGap: CGFloat = 7

    /// Measures the three blocks, asks `ToolbarLayout` for the shape of the panel, lays the blocks
    /// out by it and sizes `self` to fit. One row holds the tools, the properties and the buttons on
    /// the right with the free place between the last two; two hold the tools and the buttons in the
    /// first and the properties in the second.
    @discardableResult
    func sizeToFitContent() -> ToolbarShape {
        let tools = CGSize(width: blockWidth(toolsOrder), height: Self.rowHeight)
        let properties = CGSize(width: Self.propertiesWidth, height: Self.rowHeight)
        let actions = CGSize(width: blockWidth(actionsOrder), height: Self.rowHeight)
        let shape = ToolbarLayout.measure(
            tools: tools, properties: properties, actions: actions, freeWidth: max(200, maximumWidth))

        let padding = Self.padding
        let actionsLeft = max(padding, shape.size.width - padding - actions.width)
        switch shape.rows {
        case .one:
            layoutBlock(toolsOrder, from: padding, y: padding)
            layoutBlock(propertiesOrder, from: padding + tools.width, y: padding)
            layoutBlock(actionsOrder, from: actionsLeft, y: padding)
        case .two:
            layoutBlock(toolsOrder, from: padding, y: padding)
            layoutBlock(actionsOrder, from: actionsLeft, y: padding)
            layoutBlock(propertiesOrder, from: padding, y: padding + Self.rowHeight + Self.rowGap)
        }

        frame.size = shape.size
        return shape
    }

    /// The width one block asks for: its views side by side, with the margin of the panel between
    /// them and none hanging off either end. A view that is hidden keeps its place, the way
    /// `Visibility.Hidden` does on Windows — the block must not change width with the tool in hand.
    private func blockWidth(_ views: [NSView]) -> CGFloat {
        var width: CGFloat = 0
        for view in views { width += itemWidth(view) + Self.itemMargin * 2 }
        return max(0, width - Self.itemMargin * 2)
    }

    private func itemWidth(_ view: NSView) -> CGFloat {
        view === divider ? 15 : max(view.frame.width, 1)
    }

    private func layoutBlock(_ views: [NSView], from originX: CGFloat, y: CGFloat) {
        var x = originX
        for view in views {
            let width = itemWidth(view)
            if view === divider {
                view.frame = CGRect(x: x + 7, y: y + 7, width: 1, height: 22)
            } else {
                view.frame = CGRect(x: x, y: y, width: width, height: Self.rowHeight)
            }
            x += width + Self.itemMargin * 2
        }
    }

    // MARK: - Dragging the panel (`xaml.cs:1968-2030`)

    /// The panel is dragged by whatever of it is not a button: `ToolbarButtonBaseView.mouseDown`
    /// takes the press first, which is the same "the buttons take it before the body does" Windows
    /// leans on. AppKit needs no mouse capture of its own — the view gets the whole track up to
    /// `mouseUp` — so the risk of "the capture was never released and the drawing hung" has nothing
    /// to port.
    override func mouseDown(with event: NSEvent) {
        onDragBegan?(dragPoint(of: event))
    }

    override func mouseDragged(with event: NSEvent) {
        onDragMoved?(dragPoint(of: event))
    }

    override func mouseUp(with event: NSEvent) {
        onDragEnded?()
    }

    private func dragPoint(of event: NSEvent) -> CGPoint {
        superview?.convert(event.locationInWindow, from: nil) ?? convert(event.locationInWindow, from: nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: EditorTheme.toolbarCornerRadius, yRadius: EditorTheme.toolbarCornerRadius)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
        shadow.shadowBlurRadius = 22
        shadow.shadowOffset = NSSize(width: 0, height: -5)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        EditorTheme.toolbarBackground.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}
