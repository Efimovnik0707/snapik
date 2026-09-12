using System;

namespace SnapBrief.App;

/// <summary>
/// The package that is on the clipboard right now: the exact files, text and captures the user can
/// paste. It is not the same thing as the prepared export (<c>_prepared</c>), which is what the next
/// publication will be built from — the two diverge as soon as a capture is sent, removed or
/// reordered, and an intercepted Ctrl+V must paste what was published, not what is being prepared.
/// </summary>
internal sealed record PublishedPackage(
    string[] Paths,
    string Prompt,
    Guid[] CaptureIds,
    string ExportDirectory,
    int NoteCount)
{
    /// <summary>
    /// Whether a paste intent is about the package this application published: something has to be
    /// published, and the clipboard has to still hold the write that published it.
    /// </summary>
    internal static bool IsOwnPaste(PublishedPackage? published, uint? publishedSequenceNumber, uint intentSequenceNumber) =>
        published is not null && publishedSequenceNumber == intentSequenceNumber;
}
