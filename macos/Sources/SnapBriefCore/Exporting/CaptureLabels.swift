import Foundation

/// Port of `src/SnapBrief.Core/Exporting/CaptureLabels.cs`.
public struct LabeledAnnotation: Equatable, Sendable {
    public let displayLabel: String
    public let annotation: AnnotationItem
}

public enum CaptureLabels {
    /// Port of `ForIndex` (SPEC-DELTA-2B §B): 0 -> "A", 1 -> "B", ..., 25 -> "Z", 26 -> "AA", ...
    /// (bijective base-26). Errors only when `zeroBasedIndex < 0`; unlike the pre-sync-2 version,
    /// there is no upper bound.
    public static func forIndex(_ zeroBasedIndex: Int) throws -> String {
        guard zeroBasedIndex >= 0 else {
            throw SnapBriefError.argumentOutOfRange("zeroBasedIndex")
        }
        var value = zeroBasedIndex + 1
        var label = ""
        while value > 0 {
            value -= 1
            let scalar = Unicode.Scalar(UInt8(65 + value % 26))
            label = String(Character(scalar)) + label
            value /= 26
        }
        return label
    }

    /// Port of `ForAnnotation`, e.g. ("A", 1) -> "A1".
    public static func forAnnotation(captureLabel: String, oneBasedIndex: Int) -> String {
        "\(captureLabel)\(oneBasedIndex)"
    }

    /// Port of `ForNotedAnnotations`.
    public static func forNotedAnnotations(captureLabel: String, capture: CaptureItem) -> [LabeledAnnotation] {
        var result: [LabeledAnnotation] = []
        var noteNumber = 0
        for annotation in capture.annotations {
            guard ExportText.hasContent(annotation.note) else { continue }
            noteNumber += 1
            result.append(
                LabeledAnnotation(
                    displayLabel: forAnnotation(captureLabel: captureLabel, oneBasedIndex: noteNumber),
                    annotation: annotation))
        }
        return result
    }
}
