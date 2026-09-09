import Foundation

/// Port of .NET `Guid` semantics used throughout `src/SnapBrief.Core` and `src/SnapBrief.Infrastructure`.
///
/// .NET's default `Guid.ToString()` / System.Text.Json serialization produces the lowercase
/// `"d"` format (`8-4-4-4-12`, no braces). Foundation's `UUID.uuidString` is uppercase, so this
/// wrapper normalizes casing on encode while remaining case-insensitive on decode (matching
/// `Guid.Parse`). `digitsLowercase` mirrors `Guid.ToString("N")`, used for file/directory names
/// (`sessionId.ToString("N")`, `{captureId:N}.png`).
public struct SBGuid: Hashable, Codable, CustomStringConvertible, Sendable {
    public let uuid: UUID

    public init() {
        self.uuid = UUID()
    }

    public init(uuid: UUID) {
        self.uuid = uuid
    }

    public init?(uuidString: String) {
        guard let uuid = UUID(uuidString: uuidString) else { return nil }
        self.uuid = uuid
    }

    /// Port of `Guid.Empty`.
    public static let empty = SBGuid(uuid: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)

    /// Port of `Guid.ToString()` / `Guid.ToString("d")`: lowercase, hyphenated, no braces.
    public var description: String { uuid.uuidString.lowercased() }

    /// Port of `Guid.ToString("N")`: lowercase hex digits with no hyphens (32 characters).
    public var digitsLowercase: String {
        uuid.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let uuid = UUID(uuidString: string) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid GUID string: \(string)")
        }
        self.uuid = uuid
    }
}
