import Foundation

/// Port of `src/Snapik.Core/Models/SnapikSession.cs`.
/// JSON fields: `id`, `schemaVersion`, `createdAtUtc`, `modifiedAtUtc`, `revision`, `globalNote`,
/// `selectedTargetProfileId`, `captures`.
public struct SnapikSession: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var id: SBGuid
    public var schemaVersion: Int
    public var createdAtUtc: Date
    public var modifiedAtUtc: Date
    public var revision: Int
    public var globalNote: String
    public var selectedTargetProfileId: String?
    public var captures: [CaptureItem]

    public init(
        id: SBGuid,
        schemaVersion: Int,
        createdAtUtc: Date,
        modifiedAtUtc: Date,
        revision: Int,
        globalNote: String,
        selectedTargetProfileId: String?,
        captures: [CaptureItem]
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.createdAtUtc = createdAtUtc
        self.modifiedAtUtc = modifiedAtUtc
        self.revision = revision
        self.globalNote = globalNote
        self.selectedTargetProfileId = selectedTargetProfileId
        self.captures = captures
    }

    /// Port of `SnapikSession.Create`.
    public static func create(nowUtc: Date) -> SnapikSession {
        SnapikSession(
            id: SBGuid(),
            schemaVersion: currentSchemaVersion,
            createdAtUtc: nowUtc,
            modifiedAtUtc: nowUtc,
            revision: 0,
            globalNote: "",
            selectedTargetProfileId: nil,
            captures: [])
    }

    enum CodingKeys: String, CodingKey {
        case id
        case schemaVersion
        case createdAtUtc
        case modifiedAtUtc
        case revision
        case globalNote
        case selectedTargetProfileId
        case captures
    }
}
