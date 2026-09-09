using System.Collections.Immutable;
using SnapBrief.Core.Models;

namespace SnapBrief.Core.Editing;

public static class SessionOperations
{
    public static SnapBriefSession AddCapture(SnapBriefSession session, CaptureItem capture, DateTimeOffset nowUtc)
    {
        ArgumentNullException.ThrowIfNull(capture);
        return Touch(session with { Captures = session.Captures.Add(capture) }, nowUtc);
    }

    public static SnapBriefSession RemoveCapture(SnapBriefSession session, Guid captureId, DateTimeOffset nowUtc)
    {
        var index = IndexOf(session.Captures, captureId);
        return Touch(session with { Captures = session.Captures.RemoveAt(index) }, nowUtc);
    }

    public static SnapBriefSession MoveCapture(SnapBriefSession session, Guid captureId, int destinationIndex, DateTimeOffset nowUtc)
    {
        if (destinationIndex < 0 || destinationIndex >= session.Captures.Length)
        {
            throw new ArgumentOutOfRangeException(nameof(destinationIndex));
        }

        var sourceIndex = IndexOf(session.Captures, captureId);
        if (sourceIndex == destinationIndex)
        {
            return session;
        }

        var capture = session.Captures[sourceIndex];
        var reordered = session.Captures.RemoveAt(sourceIndex).Insert(destinationIndex, capture);
        return Touch(session with { Captures = reordered }, nowUtc);
    }

    public static SnapBriefSession UpdateGlobalNote(SnapBriefSession session, string note, DateTimeOffset nowUtc) =>
        session.GlobalNote == note ? session : Touch(session with { GlobalNote = note }, nowUtc);

    public static SnapBriefSession UpdateCapture(SnapBriefSession session, CaptureItem capture, DateTimeOffset nowUtc)
    {
        var index = IndexOf(session.Captures, capture.Id);
        return session.Captures[index] == capture
            ? session
            : Touch(session with { Captures = session.Captures.SetItem(index, capture) }, nowUtc);
    }

    private static SnapBriefSession Touch(SnapBriefSession session, DateTimeOffset nowUtc)
    {
        var updated = session with { ModifiedAtUtc = nowUtc, Revision = checked(session.Revision + 1) };
        SessionValidation.Validate(updated);
        return updated;
    }

    private static int IndexOf(ImmutableArray<CaptureItem> captures, Guid captureId)
    {
        for (var index = 0; index < captures.Length; index++)
        {
            if (captures[index].Id == captureId)
            {
                return index;
            }
        }

        throw new KeyNotFoundException($"Capture {captureId} does not exist in this session.");
    }
}

