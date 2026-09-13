namespace SnapBrief.Core.Exporting;

/// <summary>
/// The two rules the strip and the export must agree on once captures can be marked as sent:
/// a package carries only the captures that were not sent yet, and letters are handed out to
/// exactly those captures, starting at A. Sent captures keep the letter they had when they left.
/// </summary>
public static class SentCaptureRules
{
    /// <summary>
    /// How many captures the strip holds, sent ones included. Ten because the letters of the strip
    /// are then never asked to go past J: a package of that size is still one message in a chat.
    /// </summary>
    public const int MaxStripCaptures = 10;

    public static IReadOnlyList<T> ForPackage<T>(IEnumerable<T> captures, Func<T, bool> isSent) =>
        captures.Where(capture => !isSent(capture)).ToArray();

    /// <summary>Strip letters in capture order: A, B, … for captures still waiting, null for sent ones.</summary>
    public static IReadOnlyList<string?> StripLabels(IReadOnlyList<bool> sent)
    {
        var labels = new string?[sent.Count];
        var nextLabelIndex = 0;
        for (var index = 0; index < sent.Count; index++)
        {
            labels[index] = sent[index] ? null : CaptureLabels.ForIndex(nextLabelIndex++);
        }

        return labels;
    }
}
