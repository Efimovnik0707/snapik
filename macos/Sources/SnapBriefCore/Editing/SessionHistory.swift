import Foundation

/// Port of `src/SnapBrief.Core/Editing/SessionHistory.cs`.
///
/// C# uses `Stack<T>` (`_undo`/`_redo`) with `Push`/`Pop`; Swift arrays used as a LIFO stack via
/// `append`/`removeLast` are the direct equivalent. Record equality (`Current == next`) in C#
/// compares all properties structurally except that `ImmutableArray<T>.Equals` is reference-based
/// for the underlying array; `SnapBriefSession`'s synthesized `Equatable` here is fully
/// structural, which is a strictly finer-grained (never coarser) comparison and produces the same
/// observable skip-if-unchanged behavior for every call site in this codebase.
public final class SessionHistory {
    private var undoStack: [SnapBriefSession] = []
    private var redoStack: [SnapBriefSession] = []
    private let timeProvider: TimeProvider

    public private(set) var current: SnapBriefSession

    public init(initial: SnapBriefSession, timeProvider: TimeProvider = SystemTimeProvider()) {
        self.current = initial
        self.timeProvider = timeProvider
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// Port of `Apply(Func<SnapBriefSession, SnapBriefSession> operation)`.
    public func apply(_ operation: (SnapBriefSession) throws -> SnapBriefSession) rethrows {
        let next = try operation(current)
        if next == current {
            return
        }

        undoStack.append(current)
        redoStack.removeAll()
        current = next
    }

    @discardableResult
    public func undo() -> Bool {
        guard canUndo else { return false }

        let previous = undoStack.removeLast()
        redoStack.append(current)
        current = restoreAsNewRevision(previous, current)
        return true
    }

    @discardableResult
    public func redo() -> Bool {
        guard canRedo else { return false }

        let next = redoStack.removeLast()
        undoStack.append(current)
        current = restoreAsNewRevision(next, current)
        return true
    }

    private func restoreAsNewRevision(_ snapshot: SnapBriefSession, _ current: SnapBriefSession) -> SnapBriefSession {
        var restored = snapshot
        restored.revision = current.revision + 1
        restored.modifiedAtUtc = timeProvider.utcNow()
        return restored
    }
}
