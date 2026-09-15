using System.Text.RegularExpressions;

namespace Snapik.Windows;

/// <summary>
/// Detects when a foreground application that just received a pasted Snapik package
/// writes its own rendering of that paste back to the clipboard (a "receiver echo") — for
/// example a terminal host that mirrors the pasted text as its own copy. Pure classification,
/// no clipboard I/O.
/// </summary>
public static partial class ClipboardEchoDetector
{
    [GeneratedRegex(@"\[Image #\d+\]")]
    private static partial Regex ImagePlaceholderPattern();

    [GeneratedRegex(@"\s+")]
    private static partial Regex WhitespacePattern();

    private static readonly string[] FileFormats = ["FileDrop"];
    private static readonly string[] ImageFormats = ["Bitmap", "DeviceIndependentBitmap", "PNG"];
    private static readonly string[] TextFormats = ["UnicodeText", "Text"];

    /// <summary>
    /// True when <paramref name="snapshot"/> looks like a receiver's echo of
    /// <paramref name="promptText"/>: no files, no image, and a normalized text match.
    /// </summary>
    public static bool IsReceiverEcho(ClipboardSnapshot snapshot, string promptText)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        if (string.IsNullOrEmpty(promptText)) return false;

        if (ContainsAnyFormat(snapshot, FileFormats)) return false;
        if (ContainsAnyFormat(snapshot, ImageFormats)) return false;

        var candidateText = FirstTextFormat(snapshot);
        if (candidateText is null) return false;

        var normalizedCandidate = Normalize(candidateText);
        if (normalizedCandidate.Length == 0) return false;
        var normalizedPrompt = Normalize(promptText);
        if (normalizedPrompt.Length == 0) return false;

        return normalizedCandidate == normalizedPrompt || normalizedCandidate.Contains(normalizedPrompt, StringComparison.Ordinal);
    }

    private static bool ContainsAnyFormat(ClipboardSnapshot snapshot, IReadOnlyList<string> formats)
    {
        foreach (var format in formats)
            if (snapshot.Data.ContainsKey(format)) return true;
        return false;
    }

    private static string? FirstTextFormat(ClipboardSnapshot snapshot)
    {
        foreach (var format in TextFormats)
            if (snapshot.Data.TryGetValue(format, out var value) && value is string text) return text;
        return null;
    }

    private static string Normalize(string text)
    {
        var withoutPlaceholders = ImagePlaceholderPattern().Replace(text, string.Empty);
        var collapsed = WhitespacePattern().Replace(withoutPlaceholders, " ");
        return collapsed.Trim();
    }
}
