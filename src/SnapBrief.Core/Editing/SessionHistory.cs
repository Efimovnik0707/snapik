using SnapBrief.Core.Models;

namespace SnapBrief.Core.Editing;

public sealed class SessionHistory
{
    private readonly Stack<SnapBriefSession> _undo = new();
    private readonly Stack<SnapBriefSession> _redo = new();
    private readonly TimeProvider _timeProvider;

    public SessionHistory(SnapBriefSession initial, TimeProvider? timeProvider = null)
    {
        Current = initial;
        _timeProvider = timeProvider ?? TimeProvider.System;
    }

    public SnapBriefSession Current { get; private set; }
    public bool CanUndo => _undo.Count > 0;
    public bool CanRedo => _redo.Count > 0;

    public void Apply(Func<SnapBriefSession, SnapBriefSession> operation)
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

    private SnapBriefSession RestoreAsNewRevision(SnapBriefSession snapshot, SnapBriefSession current) =>
        snapshot with
        {
            Revision = checked(current.Revision + 1),
            ModifiedAtUtc = _timeProvider.GetUtcNow()
        };
}
