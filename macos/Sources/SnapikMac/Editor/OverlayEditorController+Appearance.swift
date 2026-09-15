// Port of `src/Snapik.App/OverlayEditorWindow.Appearance.cs`, SPEC §1.3, §6.2,
// SPEC-DELTA-3 §1.4 E-1, E-2, E-3, E-16, E-17, E-18, §5 L-1 ([ТЗ№4 D1] colour model).
import AppKit
import SnapikCore

/// Which of the five popovers of the panel is on screen.
enum EditorPopoverKind {
    case color
    case thickness
    case lineStyle
    case fill
    case fontSize
    case shortcutSheet
}

@MainActor
extension OverlayEditorController {
    // MARK: - Thickness of the tool in the hand (E-3)

    /// Port of `ActiveThicknessFor` (`Appearance.cs:100-101`): the highlighter keeps one width of its
    /// own, everything else with a stroke shares the other.
    func activeThickness(for tool: EditorTool) -> Double {
        tool == .highlight ? activeHighlightThickness : activeThickness
    }

    /// Port of `SetActiveThickness` (`:103-116`).
    func setActiveThickness(_ value: Double, for tool: EditorTool) {
        if tool == .highlight {
            appearanceDefaultsChanged = appearanceDefaultsChanged || value != activeHighlightThickness
            activeHighlightThickness = value
        } else {
            appearanceDefaultsChanged = appearanceDefaultsChanged || value != activeThickness
            activeThickness = value
        }
        canvasView?.activeThickness = activeThickness(for: canvasView?.tool ?? .rectangle)
    }

    // MARK: - Opening a popover (`OpenAppearance`/`OpenThickness`/… `:130-180`)

    /// Every popover of the panel opens the same way: the one on screen closes, the baseline for the
    /// single history entry is taken, the content is filled in and the popover is shown against the
    /// button that owns it.
    func togglePopover(_ kind: EditorPopoverKind, relativeTo anchor: NSView) {
        if activePopoverKind == kind, activePopover?.isShown == true {
            activePopover?.close()
            return
        }
        closePopovers()
        guard capture != nil else { return }
        appearanceBefore = snapshotState()
        appearanceChanged = false

        let controller: EditorPopoverViewController
        switch kind {
        case .color: controller = makeColorPopover()
        case .thickness: controller = makeThicknessPopover()
        case .lineStyle: controller = makeLineStylePopover()
        case .fill: controller = makeFillPopover()
        case .fontSize: controller = makeFontSizePopover()
        case .shortcutSheet: controller = EditorShortcutSheetViewController(language: language)
        }

        let popover = NSPopover()
        popover.contentViewController = controller
        popover.behavior = .semitransient
        popover.appearance = NSAppearance(named: .darkAqua)
        let delegate = AppearancePopoverDelegateProxy(controller: self)
        popover.delegate = delegate
        controller.onEscape = { [weak self] in self?.activePopover?.close() }
        appearancePopoverDelegate = delegate
        activePopover = popover
        activePopoverKind = kind

        syncAppearance()
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
    }

    /// Port of `ClosePopovers` (`:622-630`).
    func closePopovers() {
        activePopover?.close()
    }

    private func makeColorPopover() -> EditorColorPopoverViewController {
        let controller = EditorColorPopoverViewController(language: language)
        controller.onSwatchSelected = { [weak self] color in self?.applyAppearance(color: color) }
        controller.onHexCommitted = { [weak self] hex in self?.applyHex(hex) }
        controller.onPaletteSelected = { [weak self] id in self?.selectPalette(id) }
        controller.onSpectrumChanged = { [weak self] color in
            guard let self, !self.syncingAppearance else { return }
            self.applyAppearance(color: color)
        }
        // [ТЗ№4 D1] The colour is no longer remembered by itself: the "+" is what puts it into the
        // own palette, from whichever palette is showing (`D-editor.md` §2.6).
        controller.onAddToCustomPalette = { [weak self] in
            guard let self else { return }
            self.rememberCustomColor(self.activeColor)
        }
        controller.onEyedropper = { [weak self] in self?.pickColorFromScreen() }
        controller.onCloseClicked = { [weak self] in self?.activePopover?.close() }
        colorPopoverController = controller
        controller.setPalette(activePalette, selected: activeColor)
        return controller
    }

    private func makeThicknessPopover() -> EditorThicknessPopoverViewController {
        let controller = EditorThicknessPopoverViewController(language: language)
        controller.onPresetSelected = { [weak self] value in self?.applyAppearance(thickness: value) }
        controller.onSliderChanged = { [weak self] value in
            guard let self, !self.syncingAppearance else { return }
            self.applyAppearance(thickness: value.rounded())
        }
        thicknessPopoverController = controller
        return controller
    }

    private func makeLineStylePopover() -> EditorLineStylePopoverViewController {
        let controller = EditorLineStylePopoverViewController(language: language)
        controller.onStyleSelected = { [weak self] style in self?.applyAppearance(lineStyle: style) }
        lineStylePopoverController = controller
        return controller
    }

    private func makeFillPopover() -> EditorFillPopoverViewController {
        let controller = EditorFillPopoverViewController(language: language)
        controller.onFillSelected = { [weak self] fill in self?.applyAppearance(fill: fill) }
        controller.onFillColorSelected = { [weak self] color in self?.applyAppearance(fillColor: color) }
        fillPopoverController = controller
        controller.setPalette(activePalette, selected: activeFillColor ?? activeColor)
        return controller
    }

    private func makeFontSizePopover() -> EditorFontSizePopoverViewController {
        let controller = EditorFontSizePopoverViewController(language: language)
        controller.onPresetSelected = { [weak self] value in self?.applyAppearance(fontSize: value) }
        controller.onSliderChanged = { [weak self] value in
            guard let self, !self.syncingAppearance else { return }
            self.applyAppearance(fontSize: value.rounded())
        }
        fontSizePopoverController = controller
        return controller
    }

    // MARK: - Syncing the panel (`SyncAppearance`, `:242-376`)

    func syncAppearance() {
        guard let toolbarView, let canvasView else { return }
        syncingAppearance = true
        defer { syncingAppearance = false }
        refreshUndoRedoButtons()

        let selected = canvasView.selectedAnnotation
        let tool = selected?.kind ?? canvasView.tool
        // [ТЗ№4 D1] One colour, and the circle on the panel always shows it: `PanelPaintsFill` is
        // gone, so a filled frame no longer swaps the meaning of the button under the hand.
        let color = selected?.color ?? activeColor
        let thickness = selected?.thickness ?? activeThickness(for: tool)
        let fill = selected?.fill ?? activeFill
        let fillColor = (selected != nil ? selected?.fillColor : activeFillColor) ?? color
        let lineStyle = selected.map { EditorAppearance.hasLineStyle($0.kind) ? $0.lineStyle : activeLineStyle } ?? activeLineStyle
        let fontSize = selected?.fontSize ?? activeFontSize

        // The next mark takes the thickness of the tool in the hand, not of the mark under the
        // cursor; the same for everything else a new mark is born with.
        canvasView.activeColor = activeColor
        canvasView.activeThickness = activeThickness(for: canvasView.tool)
        canvasView.activeShape = activeShape
        canvasView.activeFill = activeFill
        canvasView.activeFillColor = activeFillColor
        canvasView.activeLineStyle = activeLineStyle
        canvasView.activeFontSize = activeFontSize

        toolbarView.setActiveTool(canvasView.tool)
        toolbarView.appearanceButton.color = color
        toolbarView.setQuickColors(activePalette.quick, current: color)

        // A tool without the property keeps the last value on its button, dimmed by the disabled
        // state: an empty caption is what used to make the panel jump (SPEC-DELTA-3 §1.4 E-11).
        let hasStroke = EditorAppearance.hasStroke(tool)
        toolbarView.thicknessButton.isEnabled = hasStroke
        toolbarView.thicknessButton.text = EditorStrings.pixelLabel(hasStroke ? thickness : activeThickness(for: tool))

        let hasLineStyle = EditorAppearance.hasLineStyle(tool)
        toolbarView.lineStyleButton.isEnabled = hasLineStyle
        toolbarView.lineStyleButton.text = ""
        toolbarView.lineStyleButton.drawPreview = { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return }
            AnnotationPainter.strokePath(
                [[CGPoint(x: rect.minX, y: rect.midY), CGPoint(x: rect.maxX, y: rect.midY)]],
                in: ctx, color: EditorTheme.textPrimary, thickness: 2, lineStyle: lineStyle, highlight: false)
        }

        // The button of the fill is dimmed only while a mark that cannot be filled is selected: with
        // another tool in the hand it arms the region itself, so it stays pressable.
        toolbarView.fillButton.isEnabled = selected == nil || EditorAppearance.hasFill(tool)
        toolbarView.fillButton.text = EditorStrings.text(EditorAppearance.fillNameKey(fill), language: language)
        toolbarView.fillButton.drawPreview = { rect in
            let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
            if let inside = EditorAppearance.fillColor(fillColor, fill: fill) {
                inside.setFill()
                path.fill()
            } else if fill == .blur {
                EditorTheme.blurPreviewFill.setFill()
                path.fill()
            }
            path.lineWidth = 1.5
            EditorTheme.textPrimary.setStroke()
            path.stroke()
        }

        let hasFontSize = EditorAppearance.hasFontSize(tool)
        toolbarView.fontSizeButton.isEnabled = hasFontSize
        toolbarView.fontSizeButton.text = EditorStrings.pixelLabel(hasFontSize ? fontSize : activeFontSize)

        colorPopoverController?.sync(selectedColor: color)
        thicknessPopoverController?.sync(
            presets: EditorAppearance.thicknessPresets(for: tool), range: EditorAppearance.thicknessRange(for: tool),
            value: thickness, color: color, lineStyle: lineStyle, highlight: tool == .highlight, enabled: hasStroke)
        lineStylePopoverController?.sync(style: lineStyle, color: color, thickness: thickness, enabled: hasLineStyle)
        fillPopoverController?.sync(fill: fill, fillColor: fillColor, enabled: EditorAppearance.hasFill(tool))
        fontSizePopoverController?.sync(value: fontSize, color: color)
    }

    // MARK: - Applying (`ApplyAppearance`, `:378-409`)

    /// [ТЗ№4 D1] The colour is accepted with **every** tool in the hand, the Comment and the Select
    /// included: the condition `HasColor(tool)` is gone (`D-editor.md` §2.1). The rest still belongs
    /// to the marks that have it.
    func applyAppearance(
        color: NSColor? = nil, thickness: Double? = nil, shape: AnnotationShape? = nil,
        fill: AnnotationFill? = nil, arrowStyle: String? = nil, fillColor: NSColor? = nil,
        fontSize: Double? = nil, lineStyle: AnnotationLineStyle? = nil
    ) {
        guard let canvasView else { return }
        let selected = canvasView.selectedAnnotation
        let tool = selected?.kind ?? canvasView.tool

        if let color {
            appearanceDefaultsChanged = appearanceDefaultsChanged || !EditorAppearance.sameColor(color, activeColor)
            activeColor = color
            canvasView.activeColor = color
            if let selected {
                selected.color = color
                appearanceChanged = true
            }
        }
        if let thickness, EditorAppearance.hasStroke(tool) {
            setActiveThickness(thickness, for: tool)
            if let selected {
                selected.thickness = thickness
                appearanceChanged = true
            }
        }
        if let shape, EditorAppearance.hasShape(tool) {
            activeShape = shape
            canvasView.activeShape = shape
            if let selected {
                selected.shape = shape
                appearanceChanged = true
            }
        }
        if let fill, EditorAppearance.hasFill(tool) {
            activeFill = fill
            canvasView.activeFill = fill
            if let selected {
                selected.fill = fill
                appearanceChanged = true
            }
        }
        if let fillColor, EditorAppearance.hasFill(tool) {
            activeFillColor = fillColor
            canvasView.activeFillColor = fillColor
            if let selected {
                selected.fillColor = fillColor
                appearanceChanged = true
            }
        }
        if let arrowStyle, tool == .arrow {
            canvasView.activeArrowStyle = arrowStyle
            if let selected {
                selected.arrowStyle = arrowStyle
                appearanceChanged = true
            }
        }
        if let lineStyle, EditorAppearance.hasLineStyle(tool) {
            activeLineStyle = lineStyle
            canvasView.activeLineStyle = lineStyle
            if let selected {
                selected.lineStyle = lineStyle
                appearanceChanged = true
            }
        }
        if let fontSize, EditorAppearance.hasFontSize(tool) {
            let clamped = TextMarkMetrics.clamp(fontSize)
            appearanceDefaultsChanged = appearanceDefaultsChanged || clamped != activeFontSize
            activeFontSize = clamped
            canvasView.activeFontSize = clamped
            if let selected {
                selected.fontSize = clamped
                // The box of a caption is its letters, and they just changed size.
                canvasView.fitTextMark(selected)
                appearanceChanged = true
            }
            resizeTextEditor()
        }
        canvasView.needsDisplay = true
        syncAppearance()
    }

    /// Port of `ApplyAppearanceNow` (`:413-419`): a change made outside a popover and outside a menu
    /// has nothing to close after it, so its history entry goes in at once.
    func applyAppearanceNow(color: NSColor? = nil, thickness: Double? = nil) {
        let pushEntry = canvasView?.selectedAnnotation != nil && capture != nil && appearanceBefore == nil
        if pushEntry, let before = snapshotState() {
            history.pushWithoutClearingRedo(before)
            history.clearRedo()
        }
        applyAppearance(color: color, thickness: thickness)
        if pushEntry {
            lastSnapshot = snapshotState()
            syncAppearance()
        }
    }

    /// Port of `ApplyHex` (`:589-601`). Accepts `#RGB`, `#RRGGBB` and `#AARRGGBB` — a superset of the
    /// Windows field, which is capped at seven characters. [ТЗ№4 D1] a colour typed in is no longer
    /// saved by itself: the "+" beside the field is what saves it.
    private func applyHex(_ raw: String) {
        guard let color = EditorAppearance.color(fromHex: raw) else {
            colorPopoverController?.markHexInvalid()
            return
        }
        applyAppearance(color: color)
    }

    // MARK: - Palettes (`SelectPalette`/`RememberCustomColor`, `:549-569`)

    func selectPalette(_ id: String) {
        let palette = id == "custom" ? EditorAppearance.customPalette(customColors) : EditorAppearance.parsePalette(id)
        guard palette.id != activePalette.id || palette.colors != activePalette.colors else {
            syncAppearance()
            return
        }
        activePalette = palette
        appearanceDefaultsChanged = true
        colorPopoverController?.setPalette(palette, selected: activeColor)
        fillPopoverController?.setPalette(palette, selected: activeFillColor ?? activeColor)
        syncAppearance()
    }

    /// Port of `RememberCustomColor` (`:549-558`): the newest goes first, a colour that is already in
    /// the row moves up instead of standing in it twice, and the row is never longer than the file
    /// allows. [ТЗ№4 D1] the early exit on a foreign active palette is gone — the "+" puts a colour
    /// into the own palette from any of the three, and the row under the hand is not switched.
    func rememberCustomColor(_ color: NSColor) {
        let hex = color.hexRGB
        customColors.removeAll(where: { $0.caseInsensitiveCompare(hex) == .orderedSame })
        customColors.insert(hex, at: 0)
        if customColors.count > HotkeySettings.maxCustomPaletteColors {
            customColors.removeLast(customColors.count - HotkeySettings.maxCustomPaletteColors)
        }
        appearanceDefaultsChanged = true
        if activePalette.id == "custom" {
            activePalette = EditorAppearance.customPalette(customColors)
            colorPopoverController?.setPalette(activePalette, selected: activeColor)
            fillPopoverController?.setPalette(activePalette, selected: activeFillColor ?? activeColor)
        }
        syncAppearance()
    }

    // MARK: - Eyedropper (E-18)

    /// Port of `OnEyedropperClick` (`:499-508`): the popover is in the way of the screen under it, so
    /// it is closed for the picking and opened again with the colour. A picking given up puts back
    /// the colour it started with.
    func pickColorFromScreen() {
        guard let toolbarView else { return }
        let before = activeColor
        activePopover?.close()
        let picked = ScreenColorPicker.pick(language: language) { [weak self] colour in
            self?.applyAppearance(color: colour)
        }
        applyAppearance(color: picked ?? before)
        togglePopover(.color, relativeTo: toolbarView.appearanceButton)
    }

    // MARK: - Closing one edit session (`OnAppearanceClosed`/`CommitAppearanceEdit`, `:631-656`)

    /// One history entry for everything a popover or a tool menu changed while it was open. Shared by
    /// `appearancePopoverDidClose()` and the probes, which have no real popover to close.
    func commitAppearanceSession() {
        if appearanceChanged, let before = appearanceBefore, capture != nil {
            history.pushWithoutClearingRedo(before)
            history.clearRedo()
            lastSnapshot = snapshotState()
        }
        appearanceBefore = nil
        appearanceChanged = false
        flushAppearanceDefaults()
    }

    /// Port of `FlushAppearanceDefaults`/`SaveAppearanceDefaults` (`:651-684`). [ТЗ№4 D1] only what
    /// travels between captures is written: the colour, the two thicknesses, the size of a caption,
    /// the palette, the own colours and which half of the pencil capsule is armed (`D-editor.md`
    /// §2.5). The shape, the fill, its colour and the outline flag are not written at all.
    func flushAppearanceDefaults() {
        guard appearanceDefaultsChanged else { return }
        appearanceDefaultsChanged = false
        // Load-modify-write over a file that exists but cannot be read would drop every other
        // setting, so a file that is there and does not parse is left alone. `HotkeySettings.load`
        // answers with the defaults in that case, which is exactly what must not be written back.
        let path = workspaceContext.settingsPath
        if FileManager.default.fileExists(atPath: path.path) {
            guard let data = try? Data(contentsOf: path),
                (try? JSONDecoder().decode(HotkeySettings.self, from: data)) != nil
            else { return }
        }
        var stored = HotkeySettings.load(path: path)
        stored.annotationColor = activeColor.hexRGB
        stored.annotationThickness = min(max(activeThickness, EditorAppearance.minimumThickness), EditorAppearance.maximumThickness)
        stored.annotationHighlightThickness = min(
            max(activeHighlightThickness, EditorAppearance.minimumHighlightThickness),
            EditorAppearance.maximumHighlightThickness)
        stored.annotationFontSize = TextMarkMetrics.clamp(activeFontSize)
        stored.annotationPalette = activePalette.id
        stored.customPaletteColors = customColors
        stored.annotationPencil = activePencil == .highlight ? "highlight" : "pen"
        try? stored.save(path: path)
    }

    /// Port of `OnAppearanceClosed` (`:631-635`) in full.
    func appearancePopoverDidClose() {
        commitAppearanceSession()
        activePopover = nil
        activePopoverKind = nil
        colorPopoverController = nil
        thicknessPopoverController = nil
        lineStylePopoverController = nil
        fillPopoverController = nil
        fontSizePopoverController = nil
        appearancePopoverDelegate = nil
        syncAppearance()
        refreshUndoRedoButtons()
        window(for: activeScreenIndex ?? 0)?.makeFirstResponder(canvasView)
    }

    // MARK: - Escape ladder (`NextEscapeStep`, `:614-620`)

    /// What Escape gives up, in order: an open popover, then the Comment tool, then the selection,
    /// and only with nothing left to give up, the capture itself. The mark being drawn is taken by
    /// the canvas before the window is asked at all.
    enum EscapeStep {
        case popover
        case comment
        case selection
        case capture
    }

    func nextEscapeStep() -> EscapeStep {
        if activePopover?.isShown == true { return .popover }
        if canvasView?.tool == .comment { return .comment }
        if canvasView?.selectedAnnotation != nil { return .selection }
        return .capture
    }
}

/// `NSPopover` needs an `NSObject` delegate; forwards the close notification to the controller
/// (mirrors `MoreToolsMenuTarget`'s reasoning in `OverlayEditorController+Editing.swift`).
@MainActor
final class AppearancePopoverDelegateProxy: NSObject, NSPopoverDelegate {
    weak var controller: OverlayEditorController?

    init(controller: OverlayEditorController) {
        self.controller = controller
    }

    func popoverDidClose(_ notification: Notification) {
        controller?.appearancePopoverDidClose()
    }
}
