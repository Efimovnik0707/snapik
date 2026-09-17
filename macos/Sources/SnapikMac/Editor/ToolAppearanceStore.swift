// Port of `ToolAppearance` and `ToolAppearanceStore` (`src/Snapik.App/ToolAppearance.cs:12-155`),
// SPEC-DELTA-5 §2.8, §2.9, §3.1.
//
// Not in Core, unlike `ToolAppearanceEntry`: `EditorTool` is declared in `Editor/EditorModels.swift`
// and Core cannot see it, so the dictionary of the six sets lives on this side. The same split
// Windows makes, where `HotkeySettings` is public and `ToolAppearance` is not.
import AppKit
import SnapikCore

/// What one tool of the markup panel is set to. Every tool keeps its own set, so a red dashed frame
/// and a yellow highlighter live side by side instead of overwriting one colour between them.
struct ToolAppearance: Equatable {
    /// The red the panel starts with; the editor holds the same one, and it is written here because
    /// the window it lives on cannot be reached from a test.
    static let defaultColor = NSColor(srgbRed: 1.0, green: 59.0 / 255.0, blue: 48.0 / 255.0, alpha: 1)
    static let defaultThickness: Double = 4

    var color: NSColor = ToolAppearance.defaultColor
    var thickness: Double = ToolAppearance.defaultThickness
    var lineStyle: AnnotationLineStyle = .solid
    var fill: AnnotationFill = AnnotationFill.none
    /// `nil` = "as the outline": the same meaning `AnnotationItem.fillColor` and `session.json`
    /// carry.
    var fillColor: NSColor? = nil
    var fontSize: Double = TextMarkMetrics.defaultFontSize
    var arrowStyle: String = "straight"
    var shape: AnnotationShape = .rectangle
}

/// The settings file on one side and the six sets of the panel on the other. The old common keys
/// (`annotationColor` and the three beside it) stay and go on being written as a mirror of the
/// frame, the highlighter and the caption, so a file written here is read whole by 1.5.0; a file
/// without the new key hands every tool those same old values, and opens exactly as it looked.
enum ToolAppearanceStore {
    /// The six tools that carry settings of their own; the rest borrow the frame's.
    static let tools: [EditorTool] = [.rectangle, .arrow, .pen, .highlight, .text, .blur]

    /// The name of a tool in `settings.json`. `EditorTool.rawValue` is the letter of its hotkey
    /// ("R", "B"), and a file holding those letters is a file Windows cannot read.
    static let names: [EditorTool: String] = [
        .rectangle: "rectangle", .arrow: "arrow", .pen: "pen",
        .highlight: "highlight", .text: "text", .blur: "blur",
    ]

    static func read(_ settings: HotkeySettings) -> [EditorTool: ToolAppearance] {
        let color = parseColor(settings.annotationColor, fallback: ToolAppearance.defaultColor)
        var kept: [EditorTool: ToolAppearance] = [:]
        for tool in tools {
            kept[tool] = ToolAppearance(
                color: color,
                thickness: tool == .highlight
                    ? settings.annotationHighlightThickness : settings.annotationThickness,
                fontSize: settings.annotationFontSize)
        }
        for (name, entry) in settings.toolAppearance {
            // A tool this build does not know is passed over in silence: a file from a newer build
            // must not break an older one.
            guard let tool = EditorTool(appearanceKey: name), let fallback = kept[tool] else {
                continue
            }
            kept[tool] = apply(entry, onto: fallback)
        }
        return kept
    }

    static func write(_ settings: HotkeySettings, tools: [EditorTool: ToolAppearance]) -> HotkeySettings {
        var written: [String: ToolAppearanceEntry] = [:]
        for tool in ToolAppearanceStore.tools {
            guard let name = tool.appearanceKey, let kept = tools[tool] else { continue }
            written[name] = entry(of: kept)
        }
        var mirrored = settings
        mirrored.toolAppearance = written
        // The mirror 1.5.0 reads: the colour and the thickness of the frame, the thickness of the
        // highlighter and the size of the letters. A tool that is not handed over keeps its number.
        if let frame = tools[.rectangle] {
            mirrored.annotationColor = frame.color.hexRGB
            mirrored.annotationThickness = frame.thickness
        }
        if let highlight = tools[.highlight] {
            mirrored.annotationHighlightThickness = highlight.thickness
        }
        if let text = tools[.text] {
            mirrored.annotationFontSize = text.fontSize
        }
        return mirrored
    }

    private static func apply(_ entry: ToolAppearanceEntry, onto fallback: ToolAppearance) -> ToolAppearance {
        ToolAppearance(
            color: parseColor(entry.color, fallback: fallback.color),
            thickness: finite(entry.thickness) ?? fallback.thickness,
            lineStyle: AnnotationLineStyle(rawValue: lowered(entry.lineStyle)) ?? fallback.lineStyle,
            fill: AnnotationFill(rawValue: lowered(entry.fill)) ?? fallback.fill,
            // An empty string is not "as the outline" written down, it is a file written by hand:
            // it falls back to the colour of the outline, which is what a missing key means.
            fillColor: isBlank(entry.fillColor)
                ? nil : parseColor(entry.fillColor, fallback: fallback.color),
            fontSize: finite(entry.fontSize) ?? fallback.fontSize,
            arrowStyle: entry.arrowStyle.flatMap { isBlank($0) ? nil : $0 } ?? fallback.arrowStyle,
            shape: AnnotationShape(rawValue: lowered(entry.shape)) ?? fallback.shape)
    }

    private static func entry(of kept: ToolAppearance) -> ToolAppearanceEntry {
        ToolAppearanceEntry(
            color: kept.color.hexRGB,
            thickness: kept.thickness,
            lineStyle: kept.lineStyle.rawValue,
            fill: kept.fill.rawValue,
            fillColor: kept.fillColor?.hexRGB,
            fontSize: kept.fontSize,
            arrowStyle: kept.arrowStyle,
            shape: kept.shape.rawValue)
    }

    /// `init(rawValue:)` is case sensitive and Windows parses with `ignoreCase: true`, so a file
    /// holding "Rounded" from a hand edit is read the same on both sides. A digit is not a name:
    /// `AnnotationShape(rawValue: "2")` is `nil` here without a rule of its own.
    private static func lowered(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func finite(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }

    private static func isBlank(_ value: String?) -> Bool {
        guard let value else { return true }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func parseColor(_ value: String?, fallback: NSColor) -> NSColor {
        guard let value, let parsed = EditorAppearance.color(fromHex: value) else { return fallback }
        return parsed
    }
}

extension EditorTool {
    /// The name of the tool in `settings.json`, and not the letter of its key: `rawValue` is "R"
    /// for the frame and "B" for the blur. `nil` for the tools that carry no settings of their own
    /// (select, conceal, crop, comment, eraser) — they never reach the file.
    var appearanceKey: String? { ToolAppearanceStore.names[self] }

    /// The way back, read the way Windows reads it: the case of the name in the file does not
    /// matter, and a name this build does not know is no tool at all.
    init?(appearanceKey: String) {
        let wanted = appearanceKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let match = ToolAppearanceStore.names.first(where: { $0.value == wanted }) else {
            return nil
        }
        self = match.key
    }
}
