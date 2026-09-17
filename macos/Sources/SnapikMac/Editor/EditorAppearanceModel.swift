// Port of the static half of `src/Snapik.App/OverlayEditorWindow.Appearance.cs` (palettes, presets,
// parsing) and of the fill/outline rule of `tasks/tz-005-details/D-editor.md` §2.7,
// SPEC-DELTA-3 §1.4 E-1, E-3, E-16, §5 L-1.
import AppKit
import SnapikCore

/// A palette is twelve colours plus the five of them that sit on the panel, one click away. The sets
/// are picked in the popover and remembered between captures; replacing the colours of a set is one
/// array and no code.
struct EditorPalette: Equatable {
    let id: String
    /// The Russian key of `UiLanguage`, translated where the segment is built.
    let nameKey: String
    let colors: [String]
    let quick: [String]
}

/// Everything about the look of a mark that does not need a view: the sets of colours, the presets
/// of the two thickness scales, what a tool may carry, and how a fill decides the outline.
enum EditorAppearance {
    // MARK: - Defaults and presets (`Appearance.cs:20-36`)

    static let defaultAnnotationThickness: Double = 4
    /// The highlighter is measured in tens of pixels, not in units of them: its width, its presets
    /// and the range of its slider are its own, and the button on the panel shows whichever is armed.
    static let defaultHighlightThickness: Double = 16
    static let minimumThickness: Double = 1
    static let maximumThickness: Double = 16
    static let minimumHighlightThickness: Double = 4
    static let maximumHighlightThickness: Double = 48
    static let thicknessPresets: [Double] = [2, 4, 6, 8]
    static let highlightThicknessPresets: [Double] = [8, 12, 16, 24]

    /// How transparent a highlighter is (`AnnotationCanvas.HighlightOpacity`). One number for both
    /// renderers, applied to the whole stroke at once rather than to the brush: transparent ink laid
    /// segment by segment piles up at every joint, and a highlighter drawn that way comes out as a
    /// ragged pen.
    static let highlightOpacity: CGFloat = 0.4

    // MARK: - Palettes (`Appearance.cs:55-82`, SPEC-DELTA-3 §1.4 E-16)

    static let standardPalette = EditorPalette(
        id: "standard", nameKey: "Стандартная",
        colors: [
            "#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#32ADE6", "#007AFF",
            "#AF52DE", "#FF2D55", "#FFFFFF", "#000000", "#8E8E93", "#A2845E",
        ],
        quick: ["#FF3B30", "#FFCC00", "#34C759", "#007AFF", "#FFFFFF"])

    static let pastelPalette = EditorPalette(
        id: "pastel", nameKey: "Пастель",
        colors: [
            "#2F8CFF", "#FF4D4F", "#FFBE2E", "#28BE80", "#AF81FF", "#FF79B7",
            "#FFFFFF", "#000000", "#00C8DC", "#FF8C42", "#9BA7B8", "#7754D9",
        ],
        quick: ["#2F8CFF", "#FF4D4F", "#FFBE2E", "#28BE80", "#FFFFFF"])

    /// The own palette holds no colours of its own: they are the ones the user picked, they live in
    /// the settings file, and `customPalette` puts them in.
    static let palettes: [EditorPalette] = [
        standardPalette, pastelPalette, EditorPalette(id: "custom", nameKey: "Своя", colors: [], quick: []),
    ]

    static func customPalette(_ colours: [String]) -> EditorPalette {
        let kept = Array(colours.prefix(HotkeySettings.maxCustomPaletteColors))
        return EditorPalette(id: "custom", nameKey: "Своя", colors: kept, quick: Array(kept.prefix(5)))
    }

    /// The palette a settings file stands for (`PaletteFor`). Everything but the own one is a set
    /// written down above; the own one is built out of the colours the file carries, newest first.
    static func palette(for settings: HotkeySettings) -> EditorPalette {
        let parsed = parsePalette(settings.annotationPalette)
        return parsed.id == "custom" ? customPalette(settings.customPaletteColors) : parsed
    }

    /// A palette written by hand, or by a build that knew other sets, falls back to the standard one.
    static func parsePalette(_ value: String?) -> EditorPalette {
        palettes.first(where: { $0.id.caseInsensitiveCompare(value ?? "") == .orderedSame }) ?? standardPalette
    }

    // MARK: - What a tool carries (`Appearance.cs:37-48`)

    /// Port of `HasStroke` (`:38`), minus the `HasColor` gate that [ТЗ№4 D1] removes: a caption has
    /// no thickness, everything else that draws a line has one. The colour itself is accepted by
    /// every tool now, so there is no `HasColor` any more (`D-editor.md` §2.1).
    static func hasStroke(_ tool: EditorTool) -> Bool {
        switch tool {
        case .rectangle, .arrow, .pen, .highlight: return true
        default: return false
        }
    }

    /// The frame is shared by a region and by a blur: one shape is remembered for both. What stands
    /// inside the frame belongs to the region alone, a blur has its own picture inside it.
    static func hasShape(_ tool: EditorTool) -> Bool { tool == .rectangle || tool == .blur }

    static func hasFill(_ tool: EditorTool) -> Bool { tool == .rectangle }

    /// The size of the letters belongs to a caption, and to nothing else on the panel.
    static func hasFontSize(_ tool: EditorTool) -> Bool { tool == .text }

    /// The pattern of a stroke belongs to the marks that are drawn with one: the frame and the oval,
    /// the arrow and the pencil. The highlighter is left out on purpose — a dashed highlighter falls
    /// apart into blots.
    static func hasLineStyle(_ tool: EditorTool) -> Bool {
        StrokePattern.participates(EditorAnnotation.coreKind(of: tool))
    }

    /// The thickness the panel works on: the highlighter keeps one of its own, everything else with
    /// a stroke shares the other (`ThicknessPresetsFor`).
    static func thicknessPresets(for tool: EditorTool) -> [Double] {
        tool == .highlight ? highlightThicknessPresets : thicknessPresets
    }

    static func thicknessRange(for tool: EditorTool) -> ClosedRange<Double> {
        tool == .highlight ? minimumHighlightThickness...maximumHighlightThickness : minimumThickness...maximumThickness
    }

    // MARK: - Fill and outline (`D-editor.md` §2.7)

    // The colour of the outline is not decided here any more: it is the colour of the mark whatever
    // stands inside it, and that rule lives in `AnnotationRules.outlineColorOf(fill:color:)` where
    // both renderers reach it (`AnnotationRules.cs:17-18`).

    /// The brush inside a boxed mark (`ShapeFillBrush`). A blur fill is baked into the picture before
    /// the marks are drawn, so nothing is painted over the region here.
    static func fillColor(_ color: NSColor, fill: AnnotationFill) -> NSColor? {
        switch fill {
        case .solid: return color
        case .translucent: return color.withAlphaComponent(64.0 / 255.0)
        case .blur, .none: return nil
        }
    }

    /// The name of a fill, for the value beside the title of the popover (`FillName`).
    static func fillNameKey(_ fill: AnnotationFill) -> String {
        switch fill {
        case .solid: return "Сплошная заливка"
        case .translucent: return "Полупрозрачная заливка"
        case .blur: return "Заливка размытием"
        case .none: return "Контур"
        }
    }

    // MARK: - Settings parsing (`Appearance.cs:686-718`)

    static func parseColor(_ value: String?) -> NSColor {
        guard let value, let color = color(fromHex: value) else { return EditorTheme.defaultAnnotationColor }
        return color
    }

    /// An empty value is a real preference: "the fill takes the colour of the outline". Only a value
    /// that cannot be read at all falls back to it as well.
    static func parseFillColor(_ value: String?) -> NSColor? {
        guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return color(fromHex: value)
    }

    /// A settings file written by hand, or by a build that knew other names, falls back to the frame
    /// the editor started with. Only a name counts: a number in the file must not quietly become a
    /// shape.
    static func parseShape(_ value: String?) -> AnnotationShape {
        AnnotationShape(rawValue: (value ?? "").lowercased()) ?? .rectangle
    }

    static func parseFill(_ value: String?) -> AnnotationFill {
        AnnotationFill(rawValue: (value ?? "").lowercased()) ?? AnnotationFill.none
    }

    static func parseLineStyle(_ value: String?) -> AnnotationLineStyle {
        AnnotationLineStyle(rawValue: (value ?? "").lowercased()) ?? .solid
    }

    /// Anything but "highlight" leaves the capsule on the pen, the mode it has always started with.
    static func parsePencil(_ value: String?) -> EditorTool {
        (value ?? "").caseInsensitiveCompare("highlight") == .orderedSame ? .highlight : .pen
    }

    // MARK: - Hex

    /// Accepts `#RGB`, `#RRGGBB` and `#AARRGGBB`; `nil` on anything else.
    static func color(fromHex raw: String) -> NSColor? {
        var hex = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
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

    /// Whether two colours are the same swatch, within the rounding of a hex round trip.
    static func sameColor(_ lhs: NSColor, _ rhs: NSColor) -> Bool {
        lhs.hexRGB == rhs.hexRGB
    }
}
