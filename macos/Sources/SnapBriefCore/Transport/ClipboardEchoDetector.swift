// Port of Windows/ClipboardEchoDetector.cs, SPEC-DELTA-2 Part 1 §4.7; SPEC-DELTA-2A §5.
//
// After SnapBrief republishes its package for reuse (SPEC-DELTA-2A §4), some receivers "echo"
// the pasted prompt text back onto the clipboard (e.g. a chat app that copies the message it just
// sent). That echo would otherwise look exactly like "another app displaced our package" to
// `watchForReceiverEcho`; this detector tells the two apart so SnapBrief can silently re-arm its
// own package instead of giving up on it.

import Foundation

public enum ClipboardEchoDetector {
    /// Port of `ClipboardEchoDetector.IsReceiverEcho` (`ClipboardEchoDetector.cs`). `true` only if
    /// `promptText` is non-empty, the snapshot carries no files and no image, its text is present,
    /// and the normalized text equals or contains the normalized prompt.
    public static func isReceiverEcho(_ snapshot: ClipboardSnapshot, promptText: String) -> Bool {
        guard !promptText.isEmpty else { return false }
        guard !snapshot.hasFiles else { return false }
        guard !snapshot.hasImage else { return false }
        guard let text = snapshot.text else { return false }

        let candidate = normalize(text)
        let prompt = normalize(promptText)
        guard !candidate.isEmpty, !prompt.isEmpty else { return false }
        return candidate == prompt || candidate.contains(prompt)
    }

    /// Port of the normalization step: strip `[Image #N]` placeholders, collapse runs of
    /// whitespace (including newlines) to a single space, then trim.
    static func normalize(_ text: String) -> String {
        var result = text
        if let imagePlaceholder = try? NSRegularExpression(pattern: "\\[Image #\\d+\\]") {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = imagePlaceholder.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }
        if let whitespace = try? NSRegularExpression(pattern: "\\s+") {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = whitespace.stringByReplacingMatches(in: result, range: range, withTemplate: " ")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
