import Foundation

/// Port of `src/Snapik.Core/Models/CaptureItem.cs`.
/// JSON fields: `id`, `sourceImagePath`, `pixelWidth`, `pixelHeight`, `dpiX`, `dpiY`, `title`,
/// `note`, `annotations`, `sent`.
public struct CaptureItem: Codable, Equatable, Sendable {
    public var id: SBGuid
    public var sourceImagePath: String
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var dpiX: Double
    public var dpiY: Double
    public var title: String
    public var note: String
    public var annotations: [AnnotationItem]
    /// Port of `CaptureItem.Sent` (`CaptureItem.cs:17`): the capture was already pasted as part of
    /// a package; it stays in the strip, but out of the next one. A file written before the field
    /// reads back as `false`, which is what every capture of it was.
    public var sent: Bool

    public init(
        id: SBGuid,
        sourceImagePath: String,
        pixelWidth: Int,
        pixelHeight: Int,
        dpiX: Double,
        dpiY: Double,
        title: String,
        note: String,
        annotations: [AnnotationItem],
        sent: Bool = false
    ) {
        self.id = id
        self.sourceImagePath = sourceImagePath
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.dpiX = dpiX
        self.dpiY = dpiY
        self.title = title
        self.note = note
        self.annotations = annotations
        self.sent = sent
    }

    /// Port of `CaptureItem.Create`.
    public static func create(
        sourceImagePath: String,
        pixelWidth: Int,
        pixelHeight: Int,
        dpiX: Double = 96,
        dpiY: Double = 96,
        title: String? = nil,
        note: String? = nil
    ) -> CaptureItem {
        CaptureItem(
            id: SBGuid(),
            sourceImagePath: sourceImagePath,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            dpiX: dpiX,
            dpiY: dpiY,
            title: title ?? "",
            note: note ?? "",
            annotations: [])
    }

    enum CodingKeys: String, CodingKey {
        case id
        case sourceImagePath
        case pixelWidth
        case pixelHeight
        case dpiX
        case dpiY
        case title
        case note
        case annotations
        case sent
    }

    /// Explicit `init(from:)`: `sent` is decoded with `decodeIfPresent` so a `session.json`
    /// written before sync 3 still loads (SPEC-DELTA-3 §2.1).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(SBGuid.self, forKey: .id)
        sourceImagePath = try container.decode(String.self, forKey: .sourceImagePath)
        pixelWidth = try container.decode(Int.self, forKey: .pixelWidth)
        pixelHeight = try container.decode(Int.self, forKey: .pixelHeight)
        dpiX = try container.decode(Double.self, forKey: .dpiX)
        dpiY = try container.decode(Double.self, forKey: .dpiY)
        title = try container.decode(String.self, forKey: .title)
        note = try container.decode(String.self, forKey: .note)
        annotations = try container.decode([AnnotationItem].self, forKey: .annotations)
        sent = try container.decodeIfPresent(Bool.self, forKey: .sent) ?? false
    }
}
