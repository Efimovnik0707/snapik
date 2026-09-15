import Foundation

/// Port of `src/Snapik.Core/Exporting/ExportText.cs`.
public enum ExportText {
    /// Port of `!string.IsNullOrWhiteSpace(value)`.
    public static func hasContent(_ value: String?) -> Bool {
        guard let value else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
