// [ТЗ№4 D2] Standard glyphs only: the editor draws SF Symbols wherever a system symbol for the
// action exists, and never a picture "in the spirit of" one (SPEC-DELTA-3 §4,
// `tasks/tz-005-details/D-editor.md` §3.3). The one exception is the blur mark: there is no system
// symbol for it on either platform, so the three waves stay a hand-written path, exactly as the
// Windows analysis decided.
import AppKit

enum EditorIcon {
    // The names of the symbols this zone draws. Kept together so the audit of §3.3 can be read off
    // one list instead of a dozen call sites.
    static let select = "cursorarrow"
    static let rectangle = "rectangle"
    static let arrow = "arrow.up.right"
    static let pencil = "pencil"
    static let highlighter = "highlighter"
    static let text = "textformat"
    static let eraser = "eraser"
    static let crop = "crop"
    static let comment = "bubble.left"
    static let undo = "arrow.uturn.backward"
    static let redo = "arrow.uturn.forward"
    static let save = "square.and.arrow.down"
    /// "Копировать снимок": the picture goes to the clipboard, the way the strip copies a package.
    static let copy = "doc.on.doc"
    static let eyedropper = "eyedropper"
    static let close = "xmark"
    static let add = "plus"
    static let chevronDown = "chevron.down"
    static let shortcutSheet = "questionmark"
    /// The two glyphs of the caption of a capture (SPEC-DELTA-4 §3.5): a monitor for the whole
    /// screen, a sheet of paper for a file that was imported.
    static let display = "display"
    static let importedFile = "doc"

    /// The three waves of the blur tool: no system symbol stands for "blur a region" (`D-editor.md`
    /// §3.3, §3.4), so this one glyph stays a path in a 16-unit box.
    static let blurPath = "M2,4 L5,2 L8,4 L11,2 L14,4 M2,8 L5,6 L8,8 L11,6 L14,8 M2,12 L5,10 L8,12 L11,10 L14,12"

    /// Draws the system symbol `name` centered in `rect`, tinted with `color`. Falls back to nothing
    /// when the symbol is missing, so a renamed glyph never crashes a capture in progress.
    static func draw(symbol name: String, in rect: CGRect, color: NSColor, pointSize: CGFloat = 15, weight: NSFont.Weight = .regular) {
        guard let image = image(symbol: name, color: color, pointSize: pointSize, weight: weight) else { return }
        let size = image.size
        let origin = CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
        image.draw(in: CGRect(origin: origin, size: size))
    }

    /// A tinted copy of the system symbol, for the places that need an `NSImage` (menu items).
    static func image(symbol name: String, color: NSColor, pointSize: CGFloat = 15, weight: NSFont.Weight = .regular) -> NSImage? {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let configured = base.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)) ?? base
        let tinted = NSImage(size: configured.size, flipped: false) { rect in
            configured.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.isTemplate = false
        return tinted
    }
}
