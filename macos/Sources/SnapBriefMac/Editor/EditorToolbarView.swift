// Port of the `Toolbar` floating panel (`OverlayEditorWindow.xaml:85-133`), SPEC §6.2
// "Панель инструментов: точный порядок кнопок".
import AppKit

/// 36x36 tool toggle button (SPEC §6.2 rows 1-9, minus the always-hidden Pen/Highlight/Text/
/// Conceal buttons — those live only in the "•••" menu, matching the Windows XAML's hardcoded
/// `Visibility="Collapsed"` on those four controls; the color/thickness button is no longer
/// hidden as of SPEC §1.3, §6.2 "Дополнение 2026-09-09" — see `AppearanceButtonView` below).
final class ToolbarToggleButtonView: NSView {
    let tool: EditorTool
    private let iconData: String
    private let iconNativeSize: CGFloat
    private let iconStrokeWidth: CGFloat

    var isChecked = false { didSet { needsDisplay = true } }
    private var isHovering = false { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?

    override var isFlipped: Bool { true }

    init(tool: EditorTool, tooltip: String, iconData: String, iconNativeSize: CGFloat = 16, iconStrokeWidth: CGFloat = 1.7) {
        self.tool = tool
        self.iconData = iconData
        self.iconNativeSize = iconNativeSize
        self.iconStrokeWidth = iconStrokeWidth
        super.init(frame: CGRect(x: 0, y: 0, width: 36, height: 36))
        toolTip = tooltip
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
        let background: NSColor
        let border: NSColor
        let stroke: NSColor
        if isChecked {
            background = EditorTheme.toolActiveBackground
            border = EditorTheme.accent
            stroke = .white
        } else if isHovering {
            background = EditorTheme.toolHoverBackground
            border = .clear
            stroke = EditorTheme.textSecondaryD9
        } else {
            background = .clear
            border = .clear
            stroke = EditorTheme.textSecondaryD9
        }
        let path = NSBezierPath(roundedRect: bounds, xRadius: EditorTheme.toolCornerRadius, yRadius: EditorTheme.toolCornerRadius)
        background.setFill()
        path.fill()
        if border != .clear {
            path.lineWidth = 1
            border.setStroke()
            path.stroke()
        }
        let iconRect = bounds.insetBy(dx: (bounds.width - iconNativeSize) / 2, dy: (bounds.height - iconNativeSize) / 2)
        IconPath.draw(iconData, in: iconRect, nativeSize: iconNativeSize, stroke: stroke, lineWidth: iconStrokeWidth)
    }
}

/// Variable-width action button (undo/redo/save/comment/`+ Снимок`/`Готово`, SPEC §6.2 rows
/// 12-19). Height 36, min width 36, padding 11,0.
final class ToolbarActionButtonView: NSView {
    private let iconData: String?
    private let iconNativeSize: CGFloat
    private let iconStrokeWidth: CGFloat
    private let iconStrokeColor: NSColor
    private let textLabel: NSTextField?
    private let filledBackground: NSColor?
    /// The "•••" button's active-extra-tool highlight (SPEC §1.3, §6.2 "Дополнение 2026-09-09",
    /// port of `MoreToolsButton.Background`, `OverlayEditorWindow.Appearance.cs:66`). Distinct
    /// from `filledBackground` (fixed at init, used by `doneButton`): this one is mutable and
    /// takes priority over the hover background, but not over `filledBackground`.
    var activeBackground: NSColor? { didSet { needsDisplay = true } }

    private var isHovering = false { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?

    override var isFlipped: Bool { true }

    /// Text-content button (`•••`, `+ Снимок`, `Готово`).
    init(text: String, tooltip: String? = nil, filledBackground: NSColor? = nil, bold: Bool = false) {
        iconData = nil
        iconNativeSize = 0
        iconStrokeWidth = 0
        iconStrokeColor = .clear
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
        addSubview(label)
        sizeToFitContent()
    }

    /// Icon-content button (undo/redo/save/comment).
    init(iconData: String, tooltip: String, iconNativeSize: CGFloat = 16, iconStrokeWidth: CGFloat = 1.7, iconStrokeColor: NSColor = EditorTheme.textSecondaryD9) {
        self.iconData = iconData
        self.iconNativeSize = iconNativeSize
        self.iconStrokeWidth = iconStrokeWidth
        self.iconStrokeColor = iconStrokeColor
        filledBackground = nil
        textLabel = nil
        super.init(frame: CGRect(x: 0, y: 0, width: 36, height: 36))
        toolTip = tooltip
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func sizeToFitContent() {
        guard let textLabel else { return }
        let textSize = textLabel.attributedStringValue.size()
        frame.size = NSSize(width: max(36, textSize.width + 22), height: 36)
    }

    override func layout() {
        super.layout()
        guard let textLabel else { return }
        let textSize = textLabel.attributedStringValue.size()
        textLabel.frame = CGRect(x: (bounds.width - textSize.width) / 2, y: (bounds.height - textSize.height) / 2, width: textSize.width, height: textSize.height)
    }

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
        let background = filledBackground ?? activeBackground ?? (isHovering ? EditorTheme.toolHoverBackground : .clear)
        background.setFill()
        path.fill()
        if let iconData {
            let iconRect = bounds.insetBy(dx: (bounds.width - iconNativeSize) / 2, dy: (bounds.height - iconNativeSize) / 2)
            IconPath.draw(iconData, in: iconRect, nativeSize: iconNativeSize, stroke: iconStrokeColor, lineWidth: iconStrokeWidth)
        }
    }
}

/// The combined color+thickness button (`AppearanceButton`, `OverlayEditorWindow.xaml:129-131`,
/// SPEC §1.3, §6.2 "Дополнение 2026-09-09"): a 16x16 filled circle (current color) + `"{N} px"`
/// text, height 36 / horizontal padding 11 like `ToolbarActionButtonView`'s text buttons.
/// Disabled (dimmed to 0.4 alpha, clicks ignored) when the active tool / selected annotation has
/// no color at all (`HasColor`), matching the XAML diff's new `IsEnabled -> Opacity 0.4` trigger.
final class AppearanceButtonView: NSView {
    private static let swatchSize: CGFloat = 16
    private static let horizontalPadding: CGFloat = 11
    private static let gap: CGFloat = 8

    private let textLabel = NSTextField(labelWithString: "")
    var color: NSColor = EditorTheme.accent { didSet { needsDisplay = true } }
    var isEnabled = true {
        didSet { alphaValue = isEnabled ? 1 : 0.4 }
    }
    var valueText: String = "" {
        didSet {
            textLabel.stringValue = valueText
            sizeToFitContent()
        }
    }
    private var isHovering = false { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?

    override var isFlipped: Bool { true }

    init(tooltip: String) {
        textLabel.font = EditorTheme.systemFont(13)
        textLabel.textColor = EditorTheme.textPrimary
        textLabel.backgroundColor = .clear
        textLabel.isBezeled = false
        textLabel.isEditable = false
        textLabel.isSelectable = false
        super.init(frame: .zero)
        toolTip = tooltip
        addSubview(textLabel)
        sizeToFitContent()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func sizeToFitContent() {
        let textSize = textLabel.attributedStringValue.size()
        let width = Self.horizontalPadding + Self.swatchSize + Self.gap + textSize.width + Self.horizontalPadding
        frame.size = NSSize(width: max(36, width), height: 36)
    }

    override func layout() {
        super.layout()
        let textSize = textLabel.attributedStringValue.size()
        textLabel.frame = CGRect(
            x: Self.horizontalPadding + Self.swatchSize + Self.gap, y: (bounds.height - textSize.height) / 2,
            width: textSize.width, height: textSize.height)
    }

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
        let path = NSBezierPath(roundedRect: bounds, xRadius: EditorTheme.buttonCornerRadius, yRadius: EditorTheme.buttonCornerRadius)
        let background = isHovering && isEnabled ? EditorTheme.toolHoverBackground : .clear
        background.setFill()
        path.fill()

        let swatchRect = CGRect(x: Self.horizontalPadding, y: (bounds.height - Self.swatchSize) / 2, width: Self.swatchSize, height: Self.swatchSize)
        let swatch = NSBezierPath(ovalIn: swatchRect)
        color.setFill()
        swatch.fill()
        swatch.lineWidth = 1
        EditorTheme.textSecondaryD9.setStroke()
        swatch.stroke()
    }
}

/// The floating toolbar container (SPEC §6.2). Owns the exact button set/order and forwards
/// clicks via closures; `OverlayEditorController+Editing` owns positioning
/// (`EditorGeometry.positionToolbar`) and undo/redo enablement.
final class EditorToolbarView: NSView {
    private var toolButtons: [ToolbarToggleButtonView] = []
    let appearanceButton: AppearanceButtonView
    let moreToolsButton: ToolbarActionButtonView
    let commentButton: ToolbarActionButtonView
    let undoButton: ToolbarActionButtonView
    let redoButton: ToolbarActionButtonView
    let saveButton: ToolbarActionButtonView
    let addCaptureButton: ToolbarActionButtonView
    let doneButton: ToolbarActionButtonView
    private let divider = ToolbarDividerView(frame: .zero)

    var onToolSelected: ((EditorTool) -> Void)?

    override var isFlipped: Bool { true }

    init(language: String) {
        func toggle(_ tool: EditorTool, _ tooltip: String, _ icon: String, _ strokeWidth: CGFloat = 1.7) -> ToolbarToggleButtonView {
            ToolbarToggleButtonView(tool: tool, tooltip: tooltip, iconData: icon, iconStrokeWidth: strokeWidth)
        }

        // Tooltips get a trailing hotkey hint (SPEC §7.5/§7.6, §1.3, §6.2 "Дополнение 2026-09-09":
        // main-panel tools show their single-letter shortcut; the letters themselves (V R A B C)
        // are the same in both languages, so no new dictionary entries are needed here — only the
        // base word is translated.
        let selectButton = toggle(.select, "\(EditorStrings.toolSelect(language)) (V)", "M2,1 L14,9 L9,10 L7,15 Z")
        let rectangleButton = toggle(.rectangle, "\(EditorStrings.toolRectangle(language)) (R)", "M2,3 L14,3 L14,13 L2,13 Z")
        let arrowButton = toggle(.arrow, "\(EditorStrings.toolArrow(language)) (A)", "M2,15 L15,2 M9,2 L15,2 L15,8", 1.8)
        let blurButton = toggle(.blur, "\(EditorStrings.toolBlur(language)) (B)", "M2,4 L5,2 L8,4 L11,2 L14,4 M2,8 L5,6 L8,8 L11,6 L14,8 M2,12 L5,10 L8,12 L11,10 L14,12", 1.4)
        let cropButton = toggle(.crop, "\(EditorStrings.toolCrop(language)) (C)", "M4,1 L4,12 L15,12 M1,4 L12,4 L12,15")
        toolButtons = [selectButton, rectangleButton, arrowButton, blurButton, cropButton]

        appearanceButton = AppearanceButtonView(tooltip: EditorStrings.appearanceButtonTooltip(language))
        appearanceButton.valueText = EditorStrings.thicknessLabel(4)
        appearanceButton.setAccessibilityLabel(EditorStrings.appearanceButtonTooltip(language))

        moreToolsButton = ToolbarActionButtonView(text: "\u{2022}\u{2022}\u{2022}", tooltip: EditorStrings.moreTools(language))
        commentButton = ToolbarActionButtonView(iconData: "M2,2 L14,2 L14,11 L8,11 L4,15 L4,11 L2,11 Z", tooltip: EditorStrings.addComment(language), iconStrokeWidth: 1.6)
        // Undo/Redo/Save show the mac keyboard mapping (§7.6: Cmd+Z / Shift+Cmd+Z, not the
        // Windows Ctrl+Z/Ctrl+Y); Save's "(Cmd+S)" already comes from `MacUiText`'s override of
        // `saveToComputer`.
        undoButton = ToolbarActionButtonView(iconData: "M7,3 L2,7 L7,11 M3,7 L10,7 C14,7 15,10 15,13", tooltip: "\(EditorStrings.undo(language)) (Cmd+Z)")
        redoButton = ToolbarActionButtonView(iconData: "M9,3 L14,7 L9,11 M13,7 L6,7 C2,7 1,10 1,13", tooltip: "\(EditorStrings.redo(language)) (Shift+Cmd+Z)")
        saveButton = ToolbarActionButtonView(iconData: "M2,1 L12,1 L16,5 L16,16 L2,16 Z M5,1 L5,6 L12,6 L12,1 M5,16 L5,10 L13,10 L13,16", tooltip: EditorStrings.saveToComputer(language), iconNativeSize: 17, iconStrokeWidth: 1.6)
        addCaptureButton = ToolbarActionButtonView(text: EditorStrings.addCapture(language))
        doneButton = ToolbarActionButtonView(text: EditorStrings.done(language), filledBackground: EditorTheme.accent, bold: true)

        super.init(frame: .zero)

        for button in toolButtons {
            button.onClick = { [weak self] in self?.onToolSelected?(button.tool) }
            addSubview(button)
        }
        addSubview(appearanceButton)
        addSubview(moreToolsButton)
        addSubview(commentButton)
        addSubview(divider)
        addSubview(undoButton)
        addSubview(redoButton)
        addSubview(saveButton)
        addSubview(addCaptureButton)
        addSubview(doneButton)

        setActiveTool(.rectangle)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setActiveTool(_ tool: EditorTool) {
        for button in toolButtons { button.isChecked = button.tool == tool }
    }

    func setUndoRedoEnabled(canUndo: Bool, canRedo: Bool) {
        undoButton.alphaValue = canUndo ? 1 : 0.42
        redoButton.alphaValue = canRedo ? 1 : 0.42
    }

    /// Port of `SyncAppearance`'s `AppearanceButton`/`ColorSwatch`/`AppearanceValue` half
    /// (`OverlayEditorWindow.Appearance.cs:52-54`), SPEC §1.3, §6.2 "Дополнение 2026-09-09".
    func setAppearance(color: NSColor, valueText: String, enabled: Bool) {
        appearanceButton.color = color
        appearanceButton.valueText = valueText
        appearanceButton.isEnabled = enabled
    }

    /// Port of `SyncAppearance`'s `MoreToolsButton.Background`/`ToolTip` half (`:65-67`).
    func setMoreToolsActive(_ active: Bool, tooltip: String) {
        moreToolsButton.activeBackground = active ? EditorTheme.moreToolsActiveBackground : nil
        moreToolsButton.toolTip = tooltip
    }

    /// Lays out the horizontal stack, sizes `self` to fit (SPEC §6.2: `padding 7`, item margin
    /// `2,0`), and returns the fitting size for the caller to position via
    /// `EditorGeometry.positionToolbar`.
    @discardableResult
    func sizeToFitContent() -> CGSize {
        let padding: CGFloat = 7
        let itemMargin: CGFloat = 2
        var x = padding
        let rowHeight: CGFloat = 36

        func place(_ view: NSView, width: CGFloat) {
            view.frame = CGRect(x: x, y: padding, width: width, height: rowHeight)
            x += width + itemMargin * 2
        }

        for button in toolButtons { place(button, width: 36) }
        place(appearanceButton, width: appearanceButton.frame.width)
        place(moreToolsButton, width: moreToolsButton.frame.width)
        place(commentButton, width: 36)
        divider.frame = CGRect(x: x + 7, y: padding + 7, width: 1, height: 22)
        x += 7 * 2 + 1 + itemMargin * 2
        place(undoButton, width: 36)
        place(redoButton, width: 36)
        place(saveButton, width: 36)
        place(addCaptureButton, width: addCaptureButton.frame.width)
        place(doneButton, width: doneButton.frame.width)

        let width = x - itemMargin * 2 + padding
        let height = rowHeight + padding * 2
        frame.size = NSSize(width: width, height: height)
        return frame.size
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

/// The `Border Width="1" Height="22" Background="#3A424E"` separator between the tool group and
/// the undo/redo/save/done group (SPEC §6.2 row 14).
final class ToolbarDividerView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        EditorTheme.toolbarDivider.setFill()
        NSBezierPath(rect: bounds).fill()
    }
}
