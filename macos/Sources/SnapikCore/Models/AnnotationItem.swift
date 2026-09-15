import Foundation

/// Port of `src/Snapik.Core/Models/AnnotationItem.cs`.
public enum AnnotationKind: String, Codable, Equatable, CaseIterable, Sendable {
    case arrow
    case rectangle
    case highlight
    case freehand
    case text
    case redaction
    case blur
    case comment
}

/// Port of `AnnotationShape` (`AnnotationItem.cs:20-25`): the outline a boxed mark is drawn with.
/// Two properties instead of new kinds, so the crop, the validation and the hit test keep working
/// on the same box, and a build that does not know them draws the plain rectangle it always drew.
public enum AnnotationShape: String, Codable, Equatable, CaseIterable, Sendable {
    case rectangle
    case rounded
    case ellipse
}

/// Port of `AnnotationLineStyle` (`AnnotationItem.cs:30-35`): the pattern a stroke is drawn with.
/// A frame, an oval, an arrow and a pencil have one; a highlighter, a caption, a blur and a comment
/// have no stroke to pattern. Absent means `solid`, which is what every mark written before the
/// field was drawn with.
public enum AnnotationLineStyle: String, Codable, Equatable, CaseIterable, Sendable {
    case solid
    case dashed
    case dotted
}

/// Port of `AnnotationFill` (`AnnotationItem.cs:37-43`): what stands inside a boxed mark. `blur`
/// is the fourth value and it is compatible forwards only: a build that does not know it reads no
/// fill at all.
public enum AnnotationFill: String, Codable, Equatable, CaseIterable, Sendable {
    case none
    case solid
    case translucent
    case blur
}

/// Port of `NormalizedPoint(double X, double Y)`. JSON fields: `x`, `y`.
public struct NormalizedPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    enum CodingKeys: String, CodingKey {
        case x
        case y
    }
}

/// Port of `AnnotationItem` (record + `PathSegments` init-only property + `GetPathSegments()`).
/// JSON fields: `id`, `kind`, `points`, `strokeColor`, `thickness`, `text`, `note`, `pathSegments`,
/// `parentAnnotationId`, `arrowStyle` (SPEC-DELTA-2B §B, linked comments).
///
/// `pathSegments` is decoded leniently (defaults to `[]` when the key is absent) to support
/// loading schema-1 sessions saved before multi-segment paths existed
/// (see `Json_store_loads_schema_one_annotations_without_path_segments`).
/// `parentAnnotationId` (defaults to `nil`) and `arrowStyle` (defaults to `"straight"`) are
/// likewise decoded leniently so pre-sync-2 sessions keep loading.
public struct AnnotationItem: Codable, Equatable, Sendable {
    public var id: SBGuid
    public var kind: AnnotationKind
    public var points: [NormalizedPoint]
    public var strokeColor: String
    public var thickness: Double
    public var text: String
    public var note: String
    public var pathSegments: [[NormalizedPoint]]
    /// Port of `ParentAnnotationId`: GUID of the annotation this comment is linked to; `nil` means
    /// the comment is linked to the capture itself.
    public var parentAnnotationId: SBGuid?
    /// Port of `ArrowStyle`: `"straight"` (default), `"curved"`, `"bold"`, or `"wide"`.
    public var arrowStyle: String
    /// Port of `NoteOffset` (`AnnotationItem.cs:62`): where the user dragged the numbered badge of
    /// this mark, as a shift from the place the renderer picks by itself, in fractions of the image
    /// size. `nil` means automatic placement, so a session written before the field reads back
    /// exactly as it did. A shift, not a coordinate: it may be negative and point outside the image.
    public var noteOffset: NormalizedPoint?
    /// Port of `Shape` (`AnnotationItem.cs:64`), default `.rectangle`.
    public var shape: AnnotationShape
    /// Port of `Fill` (`AnnotationItem.cs:65`), default `.none`.
    public var fill: AnnotationFill
    /// Port of `LineStyle` (`AnnotationItem.cs:66`), default `.solid`.
    public var lineStyle: AnnotationLineStyle
    /// Port of `FillColor` (`AnnotationItem.cs:70`): what stands inside the box, as `#AARRGGBB`.
    /// Absent means the colour of the outline, which is what every mark written before the field
    /// carried.
    public var fillColor: String?
    /// Port of `HasOutline` (`AnnotationItem.cs:74`): whether the outline of the box is drawn at
    /// all. A solid fill without an outline is how a mark conceals; absent means the outline is
    /// drawn, exactly as it always was. The editor of this round always writes `true`
    /// (SPEC-DELTA-3 §5, L-1); the field stays in the schema so the files of older builds read.
    public var hasOutline: Bool
    /// Port of `FontSize` (`AnnotationItem.cs:79`): the size a text mark is typed in, in the pixels
    /// of the capture, so the screen and the export show the same letters. Absent means 20; the
    /// thickness of a text mark does not stand for its size any more.
    public var fontSize: Double

    public init(
        id: SBGuid,
        kind: AnnotationKind,
        points: [NormalizedPoint],
        strokeColor: String,
        thickness: Double,
        text: String,
        note: String,
        pathSegments: [[NormalizedPoint]] = [],
        parentAnnotationId: SBGuid? = nil,
        arrowStyle: String = "straight",
        noteOffset: NormalizedPoint? = nil,
        shape: AnnotationShape = .rectangle,
        fill: AnnotationFill = .none,
        lineStyle: AnnotationLineStyle = .solid,
        fillColor: String? = nil,
        hasOutline: Bool = true,
        fontSize: Double = AnnotationItem.defaultFontSize
    ) {
        self.id = id
        self.kind = kind
        self.points = points
        self.strokeColor = strokeColor
        self.thickness = thickness
        self.text = text
        self.note = note
        self.pathSegments = pathSegments
        self.parentAnnotationId = parentAnnotationId
        self.arrowStyle = arrowStyle
        self.noteOffset = noteOffset
        self.shape = shape
        self.fill = fill
        self.lineStyle = lineStyle
        self.fillColor = fillColor
        self.hasOutline = hasOutline
        self.fontSize = fontSize
    }

    /// Port of the `FontSize { get; init; } = 20` default (`AnnotationItem.cs:79`).
    public static let defaultFontSize: Double = 20

    /// Port of `AnnotationItem.Create`.
    public static func create(
        kind: AnnotationKind,
        points: [NormalizedPoint],
        strokeColor: String = "#FF3B30",
        thickness: Double = 3,
        text: String? = nil,
        note: String? = nil,
        parentAnnotationId: SBGuid? = nil,
        arrowStyle: String = "straight"
    ) -> AnnotationItem {
        AnnotationItem(
            id: SBGuid(),
            kind: kind,
            points: points,
            strokeColor: strokeColor,
            thickness: thickness,
            text: text ?? "",
            note: note ?? "",
            parentAnnotationId: parentAnnotationId,
            arrowStyle: arrowStyle)
    }

    /// Port of `AnnotationItem.GetPathSegments()`.
    public func getPathSegments() -> [[NormalizedPoint]] {
        if !pathSegments.isEmpty {
            return pathSegments
        }
        return points.isEmpty ? [] : [points]
    }

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case points
        case strokeColor
        case thickness
        case text
        case note
        case pathSegments
        case parentAnnotationId
        case arrowStyle
        case noteOffset
        case shape
        case fill
        case lineStyle
        case fillColor
        case hasOutline
        case fontSize
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(SBGuid.self, forKey: .id)
        kind = try container.decode(AnnotationKind.self, forKey: .kind)
        points = try container.decode([NormalizedPoint].self, forKey: .points)
        strokeColor = try container.decode(String.self, forKey: .strokeColor)
        thickness = try container.decode(Double.self, forKey: .thickness)
        text = try container.decode(String.self, forKey: .text)
        note = try container.decode(String.self, forKey: .note)
        pathSegments = try container.decodeIfPresent([[NormalizedPoint]].self, forKey: .pathSegments) ?? []
        parentAnnotationId = try container.decodeIfPresent(SBGuid.self, forKey: .parentAnnotationId)
        arrowStyle = try container.decodeIfPresent(String.self, forKey: .arrowStyle) ?? "straight"
        // The seven fields of sync 3 are read leniently too: a session written before them keeps
        // loading, with the value the mark was drawn with (SPEC-DELTA-3 §2.1). A `lineStyle`,
        // `shape` or `fill` outside its enumeration is not defaulted but refused: an unknown
        // pattern would be drawn as nothing at all.
        noteOffset = try container.decodeIfPresent(NormalizedPoint.self, forKey: .noteOffset)
        shape = try container.decodeIfPresent(AnnotationShape.self, forKey: .shape) ?? .rectangle
        fill = try container.decodeIfPresent(AnnotationFill.self, forKey: .fill) ?? AnnotationFill.none
        lineStyle = try container.decodeIfPresent(AnnotationLineStyle.self, forKey: .lineStyle) ?? .solid
        fillColor = try container.decodeIfPresent(String.self, forKey: .fillColor)
        hasOutline = try container.decodeIfPresent(Bool.self, forKey: .hasOutline) ?? true
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? AnnotationItem.defaultFontSize
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(points, forKey: .points)
        try container.encode(strokeColor, forKey: .strokeColor)
        try container.encode(thickness, forKey: .thickness)
        try container.encode(text, forKey: .text)
        try container.encode(note, forKey: .note)
        try container.encode(pathSegments, forKey: .pathSegments)
        // `Optional.encode` writes JSON `null` when `parentAnnotationId` is `nil`, matching the
        // Windows `Guid?` serialization (SPEC-DELTA-2B §B).
        try container.encode(parentAnnotationId, forKey: .parentAnnotationId)
        try container.encode(arrowStyle, forKey: .arrowStyle)
        // `Optional.encode` writes JSON `null`, which is what the Windows serializer writes for a
        // `NormalizedPoint?`/`string?` that carries nothing.
        try container.encode(noteOffset, forKey: .noteOffset)
        try container.encode(shape, forKey: .shape)
        try container.encode(fill, forKey: .fill)
        try container.encode(lineStyle, forKey: .lineStyle)
        try container.encode(fillColor, forKey: .fillColor)
        try container.encode(hasOutline, forKey: .hasOutline)
        try container.encode(fontSize, forKey: .fontSize)
    }
}
