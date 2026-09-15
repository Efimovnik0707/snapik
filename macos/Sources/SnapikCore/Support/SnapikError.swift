import Foundation

/// Port of the .NET exception types thrown across `src/Snapik.Core` and
/// `src/Snapik.Infrastructure` (`InvalidDataException`, `ArgumentException`,
/// `ArgumentOutOfRangeException`, `ArgumentNullException`, `KeyNotFoundException`,
/// `InvalidOperationException`, `FileNotFoundException`). Swift has no exception type
/// hierarchy equivalent, so every C# throw site maps to one case here; callers that need to
/// distinguish cases (as the xUnit/XCTest suites do with `Assert.Throws<T>`) can switch on it.
public enum SnapikError: Error, CustomStringConvertible, Equatable {
    case invalidData(String)
    case argument(String)
    case argumentOutOfRange(String)
    case argumentNull(String)
    case keyNotFound(String)
    case invalidOperation(String)
    case fileNotFound(String)

    public var description: String {
        switch self {
        case .invalidData(let message): return message
        case .argument(let message): return message
        case .argumentOutOfRange(let message): return message
        case .argumentNull(let message): return message
        case .keyNotFound(let message): return message
        case .invalidOperation(let message): return message
        case .fileNotFound(let message): return message
        }
    }
}
