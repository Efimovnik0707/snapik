using System;

namespace Snapik.App;

/// <summary>
/// The package that is on the clipboard right now: the exact files, text and captures the user can
/// paste. It is not the same thing as the prepared export (<c>_prepared</c>), which is what the next
/// publication will be built from — the two diverge as soon as a capture is sent, removed or
/// reordered, and an intercepted Ctrl+V must paste what was published, not what is being prepared.
/// </summary>
/// <param name="IsSingleCapture">
/// One capture copied on its own ("Copy capture" in the strip or in the editor), not the package of
/// the captures that are waiting. The record lives in memory only, so this says nothing about any
/// file on disk: neither the session nor the settings carry it.
/// </param>
internal sealed record PublishedPackage(
    string[] Paths,
    string Prompt,
    Guid[] CaptureIds,
    string ExportDirectory,
    int NoteCount,
    bool IsSingleCapture = false)
{
    /// <summary>
    /// Whether a paste intent is about the package this application published: something with files
    /// in it has to be published, and the clipboard has to still hold the write that published it.
    /// The sequence number compared here is the one of that write (the receipt this window owns),
    /// not the one of the package.
    /// </summary>
    internal static bool IsOwnPaste(PublishedPackage? published, uint? ownedSequenceNumber, uint intentSequenceNumber) =>
        published is { Paths.Length: > 0 } && ownedSequenceNumber == intentSequenceNumber;

    /// <summary>
    /// Whether a noticed paste of this package clears the strip. "Clear the strip after pasting" is
    /// about the package: it says that everything that has just been sent may go. A capture copied
    /// on its own sends one card out of many, and the rest were never pasted — they only get their
    /// tick, and the undo stack and the session stay where they are.
    /// </summary>
    internal static bool ClearsTheStrip(PublishedPackage published, bool clearStackAfterPaste) =>
        clearStackAfterPaste && !published.IsSingleCapture;
}
