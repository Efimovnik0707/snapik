namespace SnapBrief.Core.Exporting;

/// <summary>
/// The two rules the strip and the export must agree on once captures can be marked as sent:
/// a package carries only the captures that were not sent yet, and letters are handed out to
/// exactly those captures, starting at A. Sent captures keep the letter they had when they left.
/// </summary>
public static class SentCaptureRules
{
    /// <summary>
    /// How many captures the strip holds, sent ones included. Twenty-six because the letters of the
    /// strip then stop exactly at Z: past that <c>CaptureLabels.ForIndex</c> goes on with AA and AB,
    /// which the code can do but the 20 px badge of a card cannot show.
    /// </summary>
    public const int MaxStripCaptures = 26;

    /// <summary>
    /// The number the strip warns about once, gently, and goes on adding past: a chat usually takes
    /// about twenty images in one paste, and a larger package is more likely to be cut than refused.
    /// </summary>
    public const int SoftStripWarning = 20;

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
