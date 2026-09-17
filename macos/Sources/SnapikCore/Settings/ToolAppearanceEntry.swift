// Port of `ToolAppearanceEntry` (`src/Snapik.App/ToolAppearance.cs:36-48`), SPEC-DELTA-5 §3.1.
import Foundation

/// The shape one tool of the markup panel takes in `settings.json`. A record of its own rather than
/// the appearance the panel works with: the file holds colours as `"#RRGGBB"` and enumerations by
/// their names, and this form is public while the appearance itself lives in the Mac target
/// (`SnapikMac/Editor/ToolAppearanceStore.swift`, which Core cannot see: `EditorTool` is declared
/// there).
///
/// `encode(to:)` is deliberately **not** written by hand. The synthesized one calls
/// `encodeIfPresent` for every optional, so a `nil` `fillColor` disappears from the file instead of
/// being written as `"fillColor": null` — which reads the same but differs byte for byte from the
/// file Windows writes (`[JsonIgnore(Condition = WhenWritingNull)]`, `ToolAppearance.cs:42-43`).
/// The keys are listed in the order Windows declares them, because `JSONEncoder` without
/// `.sortedKeys` writes in the order of `CodingKeys`.
public struct ToolAppearanceEntry: Codable, Equatable, Sendable {
    public var color: String?
    public var thickness: Double?
    /// `solid`, `dashed` or `dotted`.
    public var lineStyle: String?
    /// `none`, `solid`, `translucent` or `blur`.
    public var fill: String?
    /// Absent means "as the outline": the same meaning `AnnotationItem.fillColor` carries.
    public var fillColor: String?
    public var fontSize: Double?
    /// `straight`, `curved`, `bold` or `wide`. The panel stopped offering `bold` in 1.7.0, but a
    /// file that already holds it goes on being read (SPEC-DELTA-5 §3.1).
    public var arrowStyle: String?
    /// `rectangle`, `rounded` or `ellipse`.
    public var shape: String?

    public init(
        color: String? = nil, thickness: Double? = nil, lineStyle: String? = nil,
        fill: String? = nil, fillColor: String? = nil, fontSize: Double? = nil,
        arrowStyle: String? = nil, shape: String? = nil
    ) {
        self.color = color
        self.thickness = thickness
        self.lineStyle = lineStyle
        self.fill = fill
        self.fillColor = fillColor
        self.fontSize = fontSize
        self.arrowStyle = arrowStyle
        self.shape = shape
    }

    enum CodingKeys: String, CodingKey {
        case color, thickness, lineStyle, fill, fillColor, fontSize, arrowStyle, shape
    }
}
