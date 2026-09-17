// Port of `src/Snapik.App/OverlayEditorWindow.Appearance.cs`, SPEC §1.3, §6.2,
// SPEC-DELTA-3 §1.4 E-1, E-2, E-3, E-16, E-17, E-18, §5 L-1 ([ТЗ№4 D1] colour model).
import AppKit
import SnapikCore

/// Which of the four popovers of the panel is on screen. The pattern of a stroke has none of its
/// own any more: it is one sheet with the thickness, the way the reference draws it
/// (SPEC-DELTA-5-editor.md §3.10).
enum EditorPopoverKind {
    case color
    case thickness
    case fill
    case fontSize
    case shortcutSheet
}

@MainActor
extension OverlayEditorController {
    // MARK: - The set of one tool (`AppearanceOf`, `.Appearance.cs:99-100`)

    /// The one door to the dictionary of the six sets. `select`, `eraser`, `crop` and `comment` have
    /// no settings of their own and are not in it — and a capture reopened from the strip arms
    /// `select` — so indexing it straight would answer with nothing on every second opening. A tool
    /// without a set of its own borrows the frame's.
    func appearance(of tool: EditorTool) -> ToolAppearance {
        tools[tool] ?? tools[.rectangle] ?? ToolAppearance()
    }

    /// What a new mark is born with right now: the set of the tool in the hand, whatever is selected.
    var armedAppearance: ToolAppearance {
        appearance(of: canvasView?.tool ?? .rectangle)
    }

    /// The frame and the blur share one shape: it is kept on the frame, and the blur is written from
    /// it so the settings file says the same thing whichever of the two wrote it.
    var activeShape: AnnotationShape {
        appearance(of: .rectangle).shape
    }

    /// Port of `SyncSurfaceDefaults` (`.Appearance.cs:106-117`): what the next mark is drawn with is
    /// decided apart from what the block shows — the tool in the hand owns it, whatever mark the
    /// pointer happens to have selected.
    func syncSurfaceDefaults() {
        guard let canvasView else { return }
        let kept = appearance(of: canvasView.tool)
        canvasView.activeColor = kept.color
        canvasView.activeThickness = kept.thickness
        canvasView.activeShape = activeShape
        canvasView.activeFill = kept.fill
        canvasView.activeFillColor = kept.fillColor
        canvasView.activeLineStyle = kept.lineStyle
        canvasView.activeFontSize = kept.fontSize
        canvasView.activeArrowStyle = kept.arrowStyle
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
            self.rememberCustomColor(self.inspectedAppearance.color)
        }
        controller.onEyedropper = { [weak self] in self?.pickColorFromScreen() }
        controller.onCloseClicked = { [weak self] in self?.activePopover?.close() }
        colorPopoverController = controller
        controller.setPalette(activePalette, selected: inspectedAppearance.color)
        return controller
    }

    /// The width and the pattern of a stroke are one sheet since 1.6.0: the popover of the pattern is
    /// gone and its three segments stand under the slider (SPEC-DELTA-5-editor.md §3.10).
    private func makeThicknessPopover() -> EditorThicknessPopoverViewController {
        let controller = EditorThicknessPopoverViewController(language: language)
        controller.onPresetSelected = { [weak self] value in self?.applyAppearance(thickness: value) }
        controller.onSliderChanged = { [weak self] value in
            guard let self, !self.syncingAppearance else { return }
            self.applyAppearance(thickness: value.rounded())
        }
        controller.onStyleSelected = { [weak self] style in self?.applyAppearance(lineStyle: style) }
        thicknessPopoverController = controller
        return controller
    }

    private func makeFillPopover() -> EditorFillPopoverViewController {
        let controller = EditorFillPopoverViewController(language: language)
        controller.onFillSelected = { [weak self] fill in self?.applyAppearance(fill: fill) }
        controller.onFillColorSelected = { [weak self] color in self?.applyAppearance(fillColor: color) }
        fillPopoverController = controller
        let kept = inspectedAppearance
        controller.setPalette(activePalette, selected: kept.fillColor ?? kept.color)
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

    // MARK: - Syncing the panel (`SyncAppearance`, `.Appearance.cs:204-357`)

    /// The set the properties block belongs to: the selected mark owns it, and with nothing selected
    /// it is the tool in the hand (`InspectedTool`).
    var inspectedAppearance: ToolAppearance {
        appearance(of: EditorInspector.inspectedTool(
            selected: canvasView?.selectedAnnotation, armed: canvasView?.tool ?? .rectangle))
    }

    /// Two capsules and no more — the colour of the outline with the square of the fill beside it,
    /// and the width and pattern of a stroke, the size of a caption or the shape of a mark. The block
    /// keeps one width under every tool, so the panel never jumps.
    func syncAppearance() {
        guard let toolbarView, let canvasView else { return }
        syncingAppearance = true
        defer { syncingAppearance = false }
        refreshUndoRedoButtons()

        let selected = canvasView.selectedAnnotation
        let tool = EditorInspector.inspectedTool(selected: selected, armed: canvasView.tool)
        let view = EditorInspector.inspectorViewOf(tool)
        let kept = appearance(of: tool)
        let color = selected?.color ?? kept.color
        let thickness = selected?.thickness ?? kept.thickness
        // The pattern belongs to the marks drawn with one: the highlighter carries a width and no
        // dashes, and the rule lives in `StrokePattern`, where both renderers read it.
        let patterned = StrokePattern.participates(EditorAnnotation.coreKind(of: tool))
        let lineStyle = patterned ? (selected?.lineStyle ?? kept.lineStyle) : AnnotationLineStyle.solid
        let fill = selected?.fill ?? kept.fill
        let fillColor = (selected != nil ? selected?.fillColor : kept.fillColor) ?? color
        let fontSize = selected?.fontSize ?? kept.fontSize
        let shape = (selected?.kind == .rectangle || selected?.kind == .blur)
            ? (selected?.shape ?? activeShape) : activeShape

        // What the next mark is drawn with is decided apart from what the block shows.
        syncSurfaceDefaults()
        toolbarView.setActiveTool(canvasView.tool)

        // The first capsule: the circle of the outline and the square of what stands inside it. A
        // blur has no colour at all, so the capsule is hidden and not dimmed; a tool with no settings
        // of its own keeps both capsules in place and switched off, and the block holds its width.
        // Hidden and not removed on purpose: a view that is gone would take its place with it.
        toolbarView.colorCapsule.isHidden = !view.stroke
        toolbarView.colorCapsule.isEnabled = view.enabled
        toolbarView.colorCapsule.alphaValue = view.enabled ? 1 : 0.28
        toolbarView.colorCapsule.strokeColor = color
        toolbarView.colorCapsule.showsFillSquare = view.fillSwatch
        toolbarView.colorCapsule.fillSquare.fill = fill
        toolbarView.colorCapsule.fillSquare.fillColor = fillColor

        // The second capsule: the width and the pattern of a stroke, the size of a caption, or the
        // shape a mark is cut in. A tool with nothing of its own to set hides it the way the colour
        // capsule hides, and a hidden capsule says nothing: the tip it was left standing with used to
        // hang over a tool that sets no thickness at all.
        toolbarView.lineCapsule.isHidden = view.second == .none
        toolbarView.lineCapsule.isEnabled = view.enabled
        toolbarView.lineCapsule.alphaValue = view.enabled ? 1 : 0.28
        toolbarView.lineCapsule.toolTip = lineCapsuleTooltip(view.second)
        toolbarView.lineCapsule.setAccessibilityLabel(lineCapsuleTooltip(view.second))
        toolbarView.lineCapsule.glyph = lineCapsuleGlyph(view.second)
        toolbarView.lineCapsule.value = lineCapsuleValue(view.second, thickness: thickness, fontSize: fontSize, shape: shape)
        toolbarView.lineCapsule.sampleThickness = view.second == .line ? min(max(CGFloat(thickness), 1), 6) : 0
        toolbarView.lineCapsule.sampleLineStyle = lineStyle
        toolbarView.lineCapsule.needsDisplay = true

        colorPopoverController?.sync(selectedColor: color)
        thicknessPopoverController?.sync(
            presets: EditorAppearance.thicknessPresets(for: tool), range: EditorAppearance.thicknessRange(for: tool),
            value: thickness, color: color, lineStyle: lineStyle, highlight: tool == .highlight,
            enabled: view.second == .line, patterned: patterned)
        fillPopoverController?.sync(fill: fill, fillColor: fillColor, enabled: view.fillSwatch)
        fontSizePopoverController?.sync(value: fontSize, color: color)
    }

    /// The tip of the second capsule, by what it is showing.
    private func lineCapsuleTooltip(_ second: SecondCapsule) -> String {
        switch second {
        case .fontSize: return EditorStrings.fontSize(language)
        case .shape: return EditorStrings.shape(language)
        case .none: return ""
        case .line: return EditorStrings.thickness(language)
        }
    }

    private func lineCapsuleGlyph(_ second: SecondCapsule) -> String {
        switch second {
        case .fontSize: return "A"
        case .shape: return "\u{25A2}"
        case .none, .line: return ""
        }
    }

    private func lineCapsuleValue(_ second: SecondCapsule, thickness: Double, fontSize: Double, shape: AnnotationShape) -> String {
        switch second {
        case .fontSize: return EditorStrings.pointLabel(fontSize)
        case .shape: return EditorStrings.text(EditorStrings.shapeNameKey(shape), language: language)
        case .none: return ""
        case .line: return EditorStrings.pixelLabel(thickness)
        }
    }

    // MARK: - Applying (`ApplyAppearance`, `.Appearance.cs:369-441`)

    /// Rule 2 of the specification: with a mark selected the change goes into that mark and nowhere
    /// else; with nothing selected it goes into the tool it belongs to, and every mark that tool
    /// draws from now on carries it. A tool with no settings of its own takes nothing at all, and
    /// what may be taken at all is the fields of `InspectorView` and not five predicates of its own.
    func applyAppearance(
        color: NSColor? = nil, thickness: Double? = nil, shape: AnnotationShape? = nil,
        fill: AnnotationFill? = nil, arrowStyle: String? = nil, fillColor: NSColor? = nil,
        fontSize: Double? = nil, lineStyle: AnnotationLineStyle? = nil
    ) {
        guard let canvasView else { return }
        let selected = canvasView.selectedAnnotation
        let tool = EditorInspector.inspectedTool(selected: selected, armed: canvasView.tool)
        let view = EditorInspector.inspectorViewOf(tool)

        func keep(_ change: (ToolAppearance) -> ToolAppearance) {
            guard let before = tools[tool] else { return }
            let after = change(before)
            appearanceDefaultsChanged = appearanceDefaultsChanged || after != before
            tools[tool] = after
        }

        if let color, view.stroke {
            if let selected {
                selected.color = color
                appearanceChanged = true
            } else {
                keep { before in
                    var after = before
                    after.color = color
                    return after
                }
            }
        }
        if let thickness, view.second == .line {
            if let selected {
                selected.thickness = thickness
                appearanceChanged = true
            } else {
                keep { before in
                    var after = before
                    after.thickness = thickness
                    return after
                }
            }
        }
        // The shape belongs to the frame and to nothing else on the panel: a blur, selected or in the
        // hand, is drawn with the shape the frame carries and has no say of its own in it.
        if let shape, tool == .rectangle {
            if let selected {
                selected.shape = shape
                appearanceChanged = true
            } else {
                // One shape for the frame and the blur: it is kept on the frame and mirrored onto the
                // blur, so the settings file says the same thing whichever of the two wrote it.
                appearanceDefaultsChanged = appearanceDefaultsChanged || activeShape != shape
                var frame = appearance(of: .rectangle)
                frame.shape = shape
                tools[.rectangle] = frame
                var blur = appearance(of: .blur)
                blur.shape = shape
                tools[.blur] = blur
            }
        }
        if let fill, view.fillSwatch {
            if let selected {
                selected.fill = fill
                appearanceChanged = true
            } else {
                keep { before in
                    var after = before
                    after.fill = fill
                    return after
                }
            }
        }
        if let fillColor, view.fillSwatch {
            if let selected {
                selected.fillColor = fillColor
                appearanceChanged = true
            } else {
                keep { before in
                    var after = before
                    after.fillColor = fillColor
                    return after
                }
            }
        }
        if let arrowStyle, tool == .arrow {
            if let selected {
                selected.arrowStyle = arrowStyle
                appearanceChanged = true
            } else {
                keep { before in
                    var after = before
                    after.arrowStyle = arrowStyle
                    return after
                }
            }
        }
        if let lineStyle, StrokePattern.participates(EditorAnnotation.coreKind(of: tool)) {
            if let selected {
                selected.lineStyle = lineStyle
                appearanceChanged = true
            } else {
                keep { before in
                    var after = before
                    after.lineStyle = lineStyle
                    return after
                }
            }
        }
        if let fontSize, view.second == .fontSize {
            let clamped = TextMarkMetrics.clamp(fontSize)
            if let selected {
                selected.fontSize = clamped
                // The box of a caption is its letters, and they just changed size.
                canvasView.fitTextMark(selected)
                appearanceChanged = true
            } else {
                keep { before in
                    var after = before
                    after.fontSize = clamped
                    return after
                }
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
        let kept = inspectedAppearance
        colorPopoverController?.setPalette(palette, selected: kept.color)
        fillPopoverController?.setPalette(palette, selected: kept.fillColor ?? kept.color)
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
            let kept = inspectedAppearance
            colorPopoverController?.setPalette(activePalette, selected: kept.color)
            fillPopoverController?.setPalette(activePalette, selected: kept.fillColor ?? kept.color)
        }
        syncAppearance()
    }

    // MARK: - Eyedropper (E-18)

    /// Port of `OnEyedropperClick` (`:499-508`): the popover is in the way of the screen under it, so
    /// it is closed for the picking and opened again with the colour. A picking given up puts back
    /// the colour it started with.
    func pickColorFromScreen() {
        guard let toolbarView else { return }
        let before = inspectedAppearance.color
        activePopover?.close()
        let picked = ScreenColorPicker.pick(language: language) { [weak self] colour in
            self?.applyAppearance(color: colour)
        }
        applyAppearance(color: picked ?? before)
        togglePopover(.color, relativeTo: toolbarView.colorCapsule)
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

    /// Port of `FlushAppearanceDefaults`/`SaveAppearanceDefaults` (`.Appearance.cs` of the round of
    /// 1.6.0): rule 6 of the round — every tool keeps its own set, and all six of them are written,
    /// the shape and the fill included, so a second window opens with what this one was set to. The
    /// three keys that are common and not per tool (the palette, the own colours and which half of
    /// the pencil capsule is armed) are written in the same pass: this method is their only writer,
    /// and losing them here would quietly undo the round before this one.
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
        // The store writes the six sets and mirrors the four old common keys beside them, so the
        // file goes on being read whole by 1.5.0 (§3.1).
        var stored = ToolAppearanceStore.write(HotkeySettings.load(path: path), tools: tools)
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
