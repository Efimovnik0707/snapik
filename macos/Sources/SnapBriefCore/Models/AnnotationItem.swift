import Foundation

/// Port of `src/SnapBrief.Core/Models/AnnotationItem.cs`.
public enum AnnotationKind: String, Codable, Equatable, CaseIterable, Sendable {
    case arrow
    case rectangle
    case highlight
    case freehand
    case text
    case redaction
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
/// JSON fields: `id`, `kind`, `points`, `strokeColor`, `thickness`, `text`, `note`, `pathSegments`.
///
/// `pathSegments` is decoded leniently (defaults to `[]` when the key is absent) to support
/// loading schema-1 sessions saved before multi-segment paths existed
/// (see `Json_store_loads_schema_one_annotations_without_path_segments`).
public struct AnnotationItem: Codable, Equatable, Sendable {
    public var id: SBGuid
    public var kind: AnnotationKind
    public var points: [NormalizedPoint]
    public var strokeColor: String
    public var thickness: Double
    public var text: String
    public var note: String
    public var pathSegments: [[NormalizedPoint]]

    public init(
        id: SBGuid,
        kind: AnnotationKind,
        points: [NormalizedPoint],
        strokeColor: String,
        thickness: Double,
        text: String,
        note: String,
        pathSegments: [[NormalizedPoint]] = []
    ) {
        self.id = id
        self.kind = kind
        self.points = points
        self.strokeColor = strokeColor
        self.thickness = thickness
        self.text = text
        self.note = note
        self.pathSegments = pathSegments
    }

    /// Port of `AnnotationItem.Create`.
    public static func create(
        kind: AnnotationKind,
        points: [NormalizedPoint],
        strokeColor: String = "#FF3B30",
        thickness: Double = 3,
        text: String? = nil,
        note: String? = nil
    ) -> AnnotationItem {
        AnnotationItem(
            id: SBGuid(),
            kind: kind,
            points: points,
            strokeColor: strokeColor,
            thickness: thickness,
            text: text ?? "",
            note: note ?? "")
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
    }
}
