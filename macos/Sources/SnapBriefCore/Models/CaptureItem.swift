import Foundation

/// Port of `src/SnapBrief.Core/Models/CaptureItem.cs`.
/// JSON fields: `id`, `sourceImagePath`, `pixelWidth`, `pixelHeight`, `dpiX`, `dpiY`, `title`,
/// `note`, `annotations`.
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

    public init(
        id: SBGuid,
        sourceImagePath: String,
        pixelWidth: Int,
        pixelHeight: Int,
        dpiX: Double,
        dpiY: Double,
        title: String,
        note: String,
        annotations: [AnnotationItem]
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
    }
}
