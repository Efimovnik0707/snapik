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

/// The first capsule of the properties block (`ColorCapsule`, `xaml:272-292`): the circle of the
/// colour of the outline and, beside it, the square of what stands inside the mark. The square is a
/// view of its own with a press of its own, so that a click on it opens the fill and a click on the
/// rest of the capsule opens the outline (SPEC-DELTA-5-editor.md §1.2 E-3, H-1).
final class ToolbarColorCapsuleView: ToolbarButtonBaseView {
    static let width: CGFloat = 63

    var strokeColor: NSColor = EditorTheme.defaultAnnotationColor { didSet { needsDisplay = true } }
    /// The square of the fill stands only for the marks that have one; the capsule keeps its width
    /// either way, so the block never changes size with the tool in the hand.
    var showsFillSquare = true {
        didSet {
            fillSquare.isHidden = !showsFillSquare
            needsDisplay = true
        }
    }

    let fillSquare = ToolbarFillSquareView(frame: CGRect(x: 0, y: 0, width: 18, height: 18))

    init(tooltip: String) {
        super.init(frame: CGRect(x: 0, y: 0, width: Self.width, height: 36))
        toolTip = tooltip
        setAccessibilityLabel(tooltip)
        addSubview(fillSquare)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        fillSquare.frame = CGRect(x: 10 + 18 + 7, y: (bounds.height - 18) / 2, width: 18, height: 18)
    }

    override func drawContent() {
        let circle = NSBezierPath(ovalIn: CGRect(x: 10, y: bounds.midY - 9, width: 18, height: 18))
        strokeColor.setFill()
        circle.fill()
        circle.lineWidth = 1
        EditorTheme.textSecondaryD9.setStroke()
        circle.stroke()
    }
}

/// The square inside the capsule of the colour (`FillSquare`, `FillSquareNone`, `FillSquareBlur`):
/// what stands inside the mark, and the door to the popover of the fill.
final class ToolbarFillSquareView: ToolbarButtonBaseView {
    var fill: AnnotationFill = AnnotationFill.none { didSet { needsDisplay = true } }
    var fillColor: NSColor = EditorTheme.defaultAnnotationColor { didSet { needsDisplay = true } }

    override func drawContent() {
        let square = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        switch fill {
        case .solid:
            fillColor.setFill()
            square.fill()
        case .translucent:
            fillColor.withAlphaComponent(64.0 / 255.0).setFill()
            square.fill()
        case .blur:
            EditorTheme.blurPreviewFill.setFill()
            square.fill()
        case .none:
            break
        }
        square.lineWidth = 1
        EditorTheme.textSecondaryD9.setStroke()
        square.stroke()
        guard fill == .none else { return }
        // A stroke across the square is "nothing inside", the way the reference draws it.
        let slash = NSBezierPath()
        slash.move(to: CGPoint(x: bounds.minX + 3, y: bounds.maxY - 3))
        slash.line(to: CGPoint(x: bounds.maxX - 3, y: bounds.minY + 3))
        slash.lineWidth = 1.6
        NSColor(hex: "#FF5C5C").setStroke()
        slash.stroke()
    }
}

/// The second capsule of the properties block (`LineCapsule`, `xaml:293-305`): the width and the
/// pattern of a stroke, the size of a caption, or the shape a mark is cut in — one capsule for the
/// three of them, as the reference draws it.
final class ToolbarLineCapsuleView: ToolbarButtonBaseView {
    static let width: CGFloat = 105

    /// `A` for the size of a caption, `▢` for a shape, nothing for a stroke.
    var glyph = "" { didSet { needsDisplay = true } }
    var value = "" { didSet { needsDisplay = true } }
    /// Zero hides the sample of the stroke: only the width of a stroke carries one.
    var sampleThickness: CGFloat = 0 { didSet { needsDisplay = true } }
    var sampleLineStyle: AnnotationLineStyle = .solid { didSet { needsDisplay = true } }

    init(tooltip: String) {
        super.init(frame: CGRect(x: 0, y: 0, width: Self.width, height: 36))
        toolTip = tooltip
        setAccessibilityLabel(tooltip)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func drawContent() {
        var x: CGFloat = 10
        if !glyph.isEmpty {
            let text = NSAttributedString(
                string: glyph,
                attributes: [.font: EditorTheme.systemFont(13), .foregroundColor: EditorTheme.textSecondaryD9])
            let size = text.size()
            text.draw(at: CGPoint(x: x, y: bounds.midY - size.height / 2))
            x += size.width + 6
        }
        if !value.isEmpty {
            let text = NSAttributedString(
                string: value,
                attributes: [.font: EditorTheme.systemFont(12), .foregroundColor: EditorTheme.textPrimary])
            let size = text.size()
            text.draw(at: CGPoint(x: x, y: bounds.midY - size.height / 2))
            x += size.width + 6
        }
        let chevron = CGRect(x: bounds.maxX - 19, y: bounds.midY - 3, width: 9, height: 6)
        EditorIcon.draw(symbol: EditorIcon.chevronDown, in: chevron, color: contentColor, pointSize: 9, weight: .semibold)
        guard sampleThickness > 0, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let sample = CGRect(x: max(x, chevron.minX - 28), y: bounds.midY - 3, width: 22, height: 6)
        AnnotationPainter.strokePath(
            [[CGPoint(x: sample.minX, y: sample.midY), CGPoint(x: sample.maxX, y: sample.midY)]],
            in: ctx, color: EditorTheme.textSecondaryD9, thickness: Double(sampleThickness),
            lineStyle: sampleLineStyle, highlight: false)
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
    /// The properties block is two capsules and no more (`E §1.2 E-3`): the colour of the outline
    /// with the square of the fill inside it, and the width, the size or the shape beside it.
    let colorCapsule: ToolbarColorCapsuleView
    let lineCapsule: ToolbarLineCapsuleView
    let commentButton: ToolbarToggleButtonView
    let shortcutSheetButton: ToolbarActionButtonView
    let undoButton: ToolbarActionButtonView
    let redoButton: ToolbarActionButtonView
    let saveButton: ToolbarActionButtonView
    /// The picture goes to the clipboard whole, with its marks and its notes, without the editor
    /// being closed (`CopyImageButton`, `xaml:313-315`).
    let copyButton: ToolbarActionButtonView
    let doneButton: ToolbarActionButtonView
    private let divider = ToolbarDividerView(frame: .zero)

    private var toolButtons: [ToolbarToggleButtonView] = []
    /// The three blocks of the panel (`ToolbarTools`, `ToolbarProperties`, `ToolbarActions`,
    /// `xaml:212-221`): the tools, the properties of the one in hand and the buttons on the right.
    /// They are laid out apart, and the properties are the block that goes to the second row.
    private var toolsOrder: [NSView] = []
    private var propertiesOrder: [NSView] = []
    private var actionsOrder: [NSView] = []

    var onToolSelected: ((EditorTool) -> Void)?
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
        // Built apart and assigned: nothing of `self` may be read before `super.init`.
        let capsule = ToolbarColorCapsuleView(tooltip: EditorStrings.colorHeading(language))
        capsule.fillSquare.toolTip = EditorStrings.fill(language)
        capsule.fillSquare.setAccessibilityLabel(EditorStrings.fill(language))
        colorCapsule = capsule
        lineCapsule = ToolbarLineCapsuleView(tooltip: EditorStrings.thickness(language))
        commentButton = toggle(.comment, EditorIcon.comment)
        shortcutSheetButton = ToolbarActionButtonView(symbolName: EditorIcon.shortcutSheet, tooltip: EditorStrings.shortcutSheet(language), width: 30)
        // Undo/redo/save show the Mac keyboard mapping (§7.6: Cmd+Z / Shift+Cmd+Z / Cmd+S), appended
        // here to the pair Windows carries without keys in it.
        undoButton = ToolbarActionButtonView(symbolName: EditorIcon.undo, tooltip: "\(EditorStrings.undo(language)) (Cmd+Z)")
        redoButton = ToolbarActionButtonView(symbolName: EditorIcon.redo, tooltip: "\(EditorStrings.redo(language)) (Shift+Cmd+Z)")
        saveButton = ToolbarActionButtonView(
            symbolName: EditorIcon.save, tooltip: "\(EditorStrings.saveToComputer(language)) (Cmd+S)")
        copyButton = ToolbarActionButtonView(
            symbolName: EditorIcon.copy, tooltip: "\(EditorStrings.copyCapture(language)) (Shift+Cmd+C)")
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
        toolsOrder = [
            selectButton, rectangleButton, shapeMenuButton, arrowButton, arrowOptionsButton,
            pencilButton, pencilMenuButton, textButton, eraserButton, blurButton, cropButton,
            commentButton, shortcutSheetButton,
        ]
        propertiesOrder = [colorCapsule, lineCapsule]
        actionsOrder = [divider, undoButton, redoButton, saveButton, copyButton, doneButton]
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
