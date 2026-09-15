using System;

namespace Snapik.App;

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
    /// Whether a paste intent is about the package this application published: something with files
    /// in it has to be published, and the clipboard has to still hold the write that published it.
    /// The sequence number compared here is the one of that write (the receipt this window owns),
    /// not the one of the package.
    /// </summary>
    internal static bool IsOwnPaste(PublishedPackage? published, uint? ownedSequenceNumber, uint intentSequenceNumber) =>
        published is { Paths.Length: > 0 } && ownedSequenceNumber == intentSequenceNumber;
}
