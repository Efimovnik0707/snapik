import Foundation

/// Port of `src/Snapik.Core/Exporting/SentCaptureRules.cs`.
///
/// The two rules the strip and the export must agree on once captures can be marked as sent: a
/// package carries only the captures that were not sent yet, and letters are handed out to exactly
/// those captures, starting at A. Sent captures keep the letter they had when they left.
public enum SentCaptureRules {
    /// How many captures the strip holds, sent ones included. Twenty-six because the letters of the
    /// strip then stop exactly at Z: past that `CaptureLabels.forIndex` goes on with AA and AB,
    /// which the code can do but the 20 px badge of a card cannot show.
    public static let maxStripCaptures = 26

    /// The number the strip warns about once, gently, and goes on adding past: a chat usually takes
    /// about twenty images in one paste, and a larger package is more likely to be cut than refused.
    public static let softStripWarning = 20

    /// Port of `ForPackage<T>`: the captures that have not been sent yet, in their own order.
    public static func forPackage<T>(_ captures: [T], isSent: (T) -> Bool) -> [T] {
        captures.filter { !isSent($0) }
    }

    /// Port of `StripLabels`: strip letters in capture order — A, B, … for captures still waiting,
    /// `nil` for sent ones.
    public static func stripLabels(_ sent: [Bool]) throws -> [String?] {
        var labels: [String?] = []
        labels.reserveCapacity(sent.count)
        var nextLabelIndex = 0
        for isSent in sent {
            if isSent {
                labels.append(nil)
            } else {
                labels.append(try CaptureLabels.forIndex(nextLabelIndex))
                nextLabelIndex += 1
            }
        }
        return labels
    }
}
