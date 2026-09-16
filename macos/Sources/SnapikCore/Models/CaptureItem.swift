import Foundation

/// Port of `src/Snapik.Core/Models/CaptureItem.cs`.
/// JSON fields: `id`, `sourceImagePath`, `pixelWidth`, `pixelHeight`, `dpiX`, `dpiY`, `title`,
/// `note`, `annotations`, `sent`, `kind`, `monitorCount`.
public struct CaptureItem: Codable, Equatable, Sendable {
    public var id: SBGuid
    public var sourceImagePath: String
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var dpiX: Double
    public var dpiY: Double
    /// Port of `CaptureItem.Title` (`CaptureItem.cs:5-6`): the name of the file an imported capture
    /// came from. A region and a whole-screen shot leave it empty, and the words under a
    /// whole-screen shot are built from `kind` instead.
    public var title: String
    public var note: String
    public var annotations: [AnnotationItem]
    /// Port of `CaptureItem.Sent` (`CaptureItem.cs:17`): the capture was already pasted as part of
    /// a package; it stays in the strip, but out of the next one. A file written before the field
    /// reads back as `false`, which is what every capture of it was.
    public var sent: Bool
    /// Port of `CaptureItem.Kind` (`CaptureItem.cs:21-23`): where the capture came from. A session
    /// written before 1.5.0 carries no `kind` at all and reads back as a region, without a
    /// migration; a word outside the enumeration reads the same way (SPEC-DELTA-4 §2.1).
    public var kind: CaptureKind
    /// Port of `CaptureItem.MonitorCount` (`CaptureItem.cs:25-28`): how many monitors the
    /// whole-screen shot covered; 0 means "not known" and is what every other kind carries. A
    /// negative number from a foreign file dies here, which is why `SessionValidation` knows
    /// nothing about this field.
    public var monitorCount: Int {
        didSet { if monitorCount < 0 { monitorCount = 0 } }
    }

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
        sent: Bool = false,
        kind: CaptureKind = .region,
        monitorCount: Int = 0
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
        self.kind = kind
        // `didSet` does not run on the way through an initializer, so the clamp is spelled out here
        // and in `init(from:)` as well.
        self.monitorCount = max(0, monitorCount)
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
        case kind
        case monitorCount
    }

    /// Explicit `init(from:)`: `sent` is decoded with `decodeIfPresent` so a `session.json`
    /// written before sync 3 still loads (SPEC-DELTA-3 §2.1), and so are `kind` and `monitorCount`
    /// for a file written before 1.5.0 (SPEC-DELTA-4 §2.1).
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
        // A word the enumeration does not know is a region as well: the file of a newer build opens
        // rather than refuses, and nothing downstream has to ask whether the word makes sense.
        let storedKind = try container.decodeIfPresent(String.self, forKey: .kind)
        kind = storedKind.flatMap(CaptureKind.init(rawValue:)) ?? .region
        let storedMonitorCount = try container.decodeIfPresent(Int.self, forKey: .monitorCount) ?? 0
        monitorCount = max(0, storedMonitorCount)
    }
}
