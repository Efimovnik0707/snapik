import Foundation

/// Port of .NET's `TimeProvider` abstraction (`TimeProvider.System`, `GetUtcNow()`), used by
/// `SessionHistory` and `FileExportService` so tests can inject a frozen clock
/// (see `FrozenTimeProvider` in `SessionModelTests.cs` / `PersistenceAndExportTests.cs`).
public protocol TimeProvider {
    func utcNow() -> Date
}

/// Port of `TimeProvider.System`.
public struct SystemTimeProvider: TimeProvider {
    public init() {}
    public func utcNow() -> Date { Date() }
}
