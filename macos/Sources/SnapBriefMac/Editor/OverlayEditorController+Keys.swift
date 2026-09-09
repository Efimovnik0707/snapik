// Port of `OnWindowKeyDown` (`OverlayEditorWindow.xaml.cs:729-764`), SPEC §7.5, §7.6.
import AppKit

/// `NSTextView` used by both comment chip kinds. Adds one behavior AppKit doesn't give a plain
/// `NSTextView` for free: SPEC §7.5 point 2 wants **plain** Escape (no modifiers) inside a text
/// field to move focus back to the canvas, which is not a standard text-editing key binding.
/// Everything else (typing, arrow keys, Cmd+C copy) is left to the normal `NSTextView`/`NSText`
/// machinery untouched.
final class EditorTextView: NSTextView {
    var onEscape: (() -> Void)?
    /// SPEC-DELTA-2.md §1.3 "`PreviewKeyDown` Enter без модификаторов = `Finish()`": plain Return
    /// (no Shift) commits/collapses the chip instead of inserting a newline; Shift+Return falls
    /// through to the normal `NSTextView` newline-insertion behavior.
    var onCommit: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == Keycode.escape, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
            onEscape?()
            return
        }
        if event.keyCode == Keycode.enter || event.keyCode == Keycode.enterAlternate {
            if event.modifierFlags.contains(.shift) {
                insertNewline(nil)
            } else {
                onCommit?()
            }
            return
        }
        super.keyDown(with: event)
    }
}

@MainActor
extension OverlayEditorController {
    /// Wires one window's Cmd-modified shortcuts (SPEC §7.5 points 1, 4, 5). AppKit routes
    /// `performKeyEquivalent(with:)` to the window before ordinary `keyDown` delivery, which is
    /// exactly the "checked first, even before the text-field-focus check" priority SPEC §7.5
    /// describes for Cmd+S; for Cmd+Z/Shift+Cmd+Z/Cmd+C this handler explicitly steps aside
    /// (`return false`) whenever a chip's text view is the first responder, so normal text
    /// editing/copy (SPEC §7.5 point 2's "Ctrl+C внутри текстового поля — обычное копирование")
    /// is untouched. CHECK-API: relies on AppKit's standard `performKeyEquivalent` dispatch order
    /// (window before first-responder `keyDown`), which could not be verified without a compiler.
    func wireKeyEquivalents(_ window: OverlayWindow) {
        window.onKeyEquivalent = { [weak self] event in
            guard let self else { return false }
            guard event.modifierFlags.contains(.command) else { return false }

            if event.charactersIgnoringModifiers?.lowercased() == "s", !event.modifierFlags.contains(.shift) {
                self.saveToFile()
                return true
            }

            let focusedIsTextEditing = window.firstResponder is NSText
            if focusedIsTextEditing { return false }

            switch event.charactersIgnoringModifiers?.lowercased() {
            case "z" where event.modifierFlags.contains(.shift):
                self.performRedo()
                return true
            case "z":
                self.performUndo()
                return true
            case "c":
                self.commit(addNext: false)
                return true
            default:
                return false
            }
        }
    }

    /// Port of the Escape / tool-letter / Delete branches of `OnWindowKeyDown` (`:729-764`).
    /// Only reached when `OverlayContentView` itself (not a chip's text field) is first
    /// responder — SPEC §7.5's "внутри поля — обычный ввод текста" is therefore automatic: text
    /// fields simply receive `keyDown` directly and this method never runs.
    func handleKeyDown(_ event: NSEvent) {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty else { return }

        if event.keyCode == Keycode.escape {
            if capture == nil {
                if selectionStartLocal == nil { close(); delegate?.overlayEditorDidCancel(self) }
                return
            }
            cancelEditing()
            return
        }

        guard let key = event.charactersIgnoringModifiers?.uppercased(), let tool = EditorTool(rawValue: key) else { return }
        // SPEC-DELTA-2B.md §C7: the `N` hotkey routes through `commentButtonClicked()` (which
        // captures `commentParentId` from whatever is currently selected) instead of the plain
        // `selectTool(_:)` every other letter uses.
        if tool == .comment {
            commentButtonClicked()
        } else {
            selectTool(tool)
        }
    }
}
