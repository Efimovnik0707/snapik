using Snapik.Core.Models;

namespace Snapik.Core.Editing;

public sealed class SessionHistory
{
    private readonly Stack<SnapikSession> _undo = new();
    private readonly Stack<SnapikSession> _redo = new();
    private readonly TimeProvider _timeProvider;

    public SessionHistory(SnapikSession initial, TimeProvider? timeProvider = null)
    {
        Current = initial;
        _timeProvider = timeProvider ?? TimeProvider.System;
    }

    public SnapikSession Current { get; private set; }
    public bool CanUndo => _undo.Count > 0;
    public bool CanRedo => _redo.Count > 0;

    public void Apply(Func<SnapikSession, SnapikSession> operation)
    {
        ArgumentNullException.ThrowIfNull(operation);
        var next = operation(Current);
        if (ReferenceEquals(Current, next) || Current == next)
        {
            return;
        }

        _undo.Push(Current);
        _redo.Clear();
        Current = next;
    }

    public bool Undo()
    {
        if (!CanUndo)
        {
            return false;
        }

        var previous = _undo.Pop();
        _redo.Push(Current);
        Current = RestoreAsNewRevision(previous, Current);
        return true;
    }

    public bool Redo()
    {
        if (!CanRedo)
        {
            return false;
        }

        var next = _redo.Pop();
        _undo.Push(Current);
        Current = RestoreAsNewRevision(next, Current);
        return true;
    }

    private SnapikSession RestoreAsNewRevision(SnapikSession snapshot, SnapikSession current) =>
        snapshot with
        {
            Revision = checked(current.Revision + 1),
            ModifiedAtUtc = _timeProvider.GetUtcNow()
        };
}
