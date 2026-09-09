using System.Collections.Immutable;

namespace SnapBrief.Core.Models;

public sealed record SnapBriefSession(
    Guid Id,
    int SchemaVersion,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset ModifiedAtUtc,
    int Revision,
    string GlobalNote,
    string? SelectedTargetProfileId,
    ImmutableArray<CaptureItem> Captures)
{
    public const int CurrentSchemaVersion = 1;

    public static SnapBriefSession Create(DateTimeOffset nowUtc) =>
        new(
            Guid.NewGuid(),
            CurrentSchemaVersion,
            nowUtc,
            nowUtc,
            0,
            string.Empty,
            null,
            ImmutableArray<CaptureItem>.Empty);
}

