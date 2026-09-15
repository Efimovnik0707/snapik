// Port of `OverlayEditorWindow.Appearance.cs` (new file in the 2026-09-09 Windows "доводка
// панели разметки" sync), SPEC §1.3, §6.2 "Дополнение 2026-09-09".
import AppKit
import SnapikCore

@MainActor
extension OverlayEditorController {
    /// Port of `HasColor(EditorTool)` (`:16`).
    static func hasColor(_ tool: EditorTool) -> Bool {
        switch tool {
        case .rectangle, .arrow, .pen, .highlight, .text: return true
        case .select, .conceal, .blur, .crop, .comment: return false
        }
    }

    /// Port of `HasStroke(EditorTool)` (`:17`): every color tool except Text.
    static func hasStroke(_ tool: EditorTool) -> Bool {
        hasColor(tool) && tool != .text
    }

    /// Port of `OpenAppearance()` (`:19-40`): toggles the popover and, when opening, seeds the
    /// undo baseline for the coalesced edit session it is about to start.
    func toggleAppearancePopover() {
        if let popover = appearancePopover, popover.isShown {
            popover.close()
            return
        }
        guard capture != nil, let toolbarView else { return }
        appearanceBefore = snapshotState()
        appearanceChanged = false

        let popoverViewController = EditorAppearancePopoverViewController(language: language)
        popoverViewController.onSwatchSelected = { [weak self] color in self?.applyAppearance(color: color, thickness: nil) }
        popoverViewController.onHexCommitted = { [weak self] hex in self?.applyHex(hex) }
        popoverViewController.onThicknessChanged = { [weak self] value in
            guard let self, !self.syncingAppearance else { return }
            self.applyAppearance(color: nil, thickness: value.rounded())
        }
        // `NSPopover.close()`, not `performClose(_:)` (that's an `NSWindow`/`NSViewController`
        // pattern; `NSPopover` only exposes the plain no-argument `close()`).
        let closePopover: () -> Void = { [weak self] in self?.appearancePopover?.close() }
        popoverViewController.onCloseClicked = closePopover
        popoverViewController.onEscape = closePopover

        let popover = NSPopover()
        popover.contentViewController = popoverViewController
        popover.behavior = .semitransient
        popover.appearance = NSAppearance(named: .darkAqua)
        let delegate = AppearancePopoverDelegateProxy(controller: self)
        popover.delegate = delegate
        appearancePopoverDelegate = delegate
        appearancePopoverController = popoverViewController
        appearancePopover = popover

        syncAppearance()
        popover.show(relativeTo: toolbarView.appearanceButton.bounds, of: toolbarView.appearanceButton, preferredEdge: .maxY)
    }

    /// Port of `SyncAppearance()` (`:42-69`): refreshes the toolbar's appearance button, the
    /// "•••" button's active-extra-tool highlight, and — when the popover is open — its own
    /// controls.
    func syncAppearance() {
        guard let toolbarView, let canvasView else { return }
        syncingAppearance = true
        refreshUndoRedoButtons()

        let selected = canvasView.selectedAnnotation
        let tool = selected?.kind ?? canvasView.tool
        let color = selected?.color ?? activeColor
        let thickness = selected?.thickness ?? activeThickness

        toolbarView.setAppearance(
            color: color,
            valueText: Self.hasStroke(tool) ? EditorStrings.thicknessLabel(thickness) : "",
            enabled: Self.hasColor(tool))

        // SPEC-DELTA-2B.md §C6: Text moved onto the main toolbar as of the 2026-09-09 sync, so
        // it no longer drives the "•••" button's active-extra-tool highlight.
        let extraTools: Set<EditorTool> = [.pen, .highlight, .conceal]
        let extraActive = extraTools.contains(canvasView.tool)
        toolbarView.setMoreToolsActive(extraActive, tooltip: extraActive ? extraToolsTooltip(for: canvasView.tool) : EditorStrings.moreTools(language))

        if let popoverController = appearancePopoverController, appearancePopover?.isShown == true {
            popoverController.sync(selectedColor: color, hexText: color.hexRGB, thicknessValue: thickness, hasStroke: Self.hasStroke(tool))
        }
        syncingAppearance = false
    }

    private func extraToolsTooltip(for tool: EditorTool) -> String {
        let label: String
        switch tool {
        case .pen: label = "\(EditorStrings.toolPen(language)) (P)"
        case .highlight: label = "\(EditorStrings.toolHighlight(language)) (H)"
        default: label = "\(EditorStrings.toolConcealSolid(language)) (X)"
        }
        return "\(EditorStrings.moreTools(language)) \u{00B7} \(label)"
    }

    /// Port of `ApplyAppearance(Color?, double?)` (`:71-79`). Applies immediately to the selected
    /// annotation (if any) and always updates the tool-level default so the *next* new annotation
    /// picks it up (SPEC §1.3 point 3: "без выделения — применяется к следующим отметкам").
    func applyAppearance(color: NSColor?, thickness: Double?) {
        guard let canvasView else { return }
        let selected = canvasView.selectedAnnotation
        let tool = selected?.kind ?? canvasView.tool
        if let color, Self.hasColor(tool) {
            activeColor = color
            canvasView.activeColor = color
            if let selected {
                selected.color = color
                appearanceChanged = true
            }
        }
        if let thickness, Self.hasStroke(tool) {
            activeThickness = thickness
            canvasView.activeThickness = thickness
            if let selected {
                selected.thickness = thickness
                appearanceChanged = true
            }
        }
        canvasView.needsDisplay = true
        syncAppearance()
    }

    /// Port of `ApplyHex()`/`OnHexLostFocus`/`OnHexKeyDown` (`:85-94`). Accepts `#RGB`,
    /// `#RRGGBB`, and `#AARRGGBB` (SPEC §1.3 point 2) — a superset of the Windows source's
    /// 6-digit-only `uint.TryParse` (that field is also capped at `MaxLength="7"`, so it can
    /// never actually receive an 8-digit value; this popover's field has no such cap).
    private func applyHex(_ raw: String) {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard let color = Self.color(fromHex: value) else {
            appearancePopoverController?.markHexInvalid()
            return
        }
        applyAppearance(color: color, thickness: nil)
    }

    private static func color(fromHex hex: String) -> NSColor? {
        guard [3, 6, 8].contains(hex.count), let value = UInt64(hex, radix: 16) else { return nil }
        switch hex.count {
        case 3:
            let r = (value >> 8) & 0xF, g = (value >> 4) & 0xF, b = value & 0xF
            return NSColor(srgbRed: CGFloat(r * 17) / 255, green: CGFloat(g * 17) / 255, blue: CGFloat(b * 17) / 255, alpha: 1)
        case 6:
            let r = (value >> 16) & 0xFF, g = (value >> 8) & 0xFF, b = value & 0xFF
            return NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
        default:
            let a = (value >> 24) & 0xFF, r = (value >> 16) & 0xFF, g = (value >> 8) & 0xFF, b = value & 0xFF
            return NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
        }
    }

    /// Port of the undo-commit half of `OnAppearanceClosed` (`:97-106`): pushes `appearanceBefore`
    /// unconditionally (not through `pushHistory()`'s `lastSnapshot` diffing — mirrors the C#
    /// source's direct `_undo.Push(_appearanceBefore)`) so every color/thickness edit made while
    /// the popover was open collapses into exactly one undo entry (SPEC §1.3 point 3). Shared by
    /// `appearancePopoverDidClose()` and `smokeUndo()` (`+SmokeTest.swift`), which has no real
    /// popover to close.
    func commitAppearanceSession() {
        if appearanceChanged, let before = appearanceBefore, capture != nil {
            history.pushWithoutClearingRedo(before)
            history.clearRedo()
            lastSnapshot = snapshotState()
        }
        appearanceBefore = nil
        appearanceChanged = false
    }

    /// Port of `OnAppearanceClosed` (`:97-106`) in full.
    func appearancePopoverDidClose() {
        commitAppearanceSession()
        appearancePopover = nil
        appearancePopoverController = nil
        appearancePopoverDelegate = nil
        syncAppearance()
        refreshUndoRedoButtons()
        window(for: activeScreenIndex ?? 0)?.makeFirstResponder(canvasView)
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
