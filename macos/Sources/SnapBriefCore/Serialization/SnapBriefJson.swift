import Foundation

/// Port of `src/SnapBrief.Infrastructure/Serialization/SnapBriefJson.cs`.
///
/// The C# options use `JsonNamingPolicy.CamelCase` (so PascalCase record properties like
/// `SourceImagePath` serialize as `sourceImagePath`), a camelCase string enum converter, and
/// `WriteIndented = true`. The Swift models below declare `CodingKeys` with the already-camelCase
/// field names directly (no naming-policy conversion needed), and `AnnotationKind`'s raw values
/// already match the camelCase enum member names, so no custom enum coding is required either.
/// `dateEncodingStrategy`/`dateDecodingStrategy` reproduce .NET's `DateTimeOffset` "O" format via
/// `ISO8601Precise` (see that file for why plain `ISO8601DateFormatter`/`Calendar` are avoided).
public enum SnapBriefJson {
    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ISO8601Precise.format(date))
        }
        return encoder
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = ISO8601Precise.parse(string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(string)")
            }
            return date
        }
        return decoder
    }()
}
