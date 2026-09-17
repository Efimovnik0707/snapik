import Foundation

/// Port of `src/Snapik.Core/Exporting/PromptGenerator.cs`. UI strings are Russian verbatim
/// (matches the app's Russian-first prompt text; `UiLanguage` only translates chrome, not this
/// generated document).
public struct PromptGenerator {
    /// The letter of a package made of one capture, when that capture already carries one
    /// elsewhere: copying the card "B" alone must not rename it "A" in the text while the card and
    /// the toast keep saying "B". A package of two or more captures numbers itself by position as
    /// it always did.
    private let singleCaptureLabel: String?

    /// Written out rather than left to the memberwise one: a stored property takes the free
    /// initializer away, and the memberwise one of a public struct is internal in any case, so
    /// every `PromptGenerator()` outside this module would stop compiling.
    public init(singleCaptureLabel: String? = nil) {
        self.singleCaptureLabel = singleCaptureLabel
    }

    public func generate(_ session: SnapikSession) throws -> String {
        try SessionValidation.validate(session)
        var sections: [String] = []

        if ExportText.hasContent(session.globalNote) {
            sections.append("Общее пожелание:\n\(session.globalNote)")
        }

        for (captureIndex, capture) in session.captures.enumerated() {
            // `CaptureLabels.forIndex` throws here, unlike the Windows one, so the branch is
            // written out: `try` may not stand to the right of an operator.
            let captureLabel: String
            if let only = singleCaptureLabel, session.captures.count == 1 {
                captureLabel = only
            } else {
                captureLabel = try CaptureLabels.forIndex(captureIndex)
            }
            let labeled = CaptureLabels.forNotedAnnotations(captureLabel: captureLabel, capture: capture)
            // Port of `PromptGenerator.cs:23`: a whole-screen shot has no title of its own, and
            // without a word the receiver cannot tell it from a region — the kind speaks for it and
            // counts as content of its own (SPEC-DELTA-4 §2.1).
            let title =
                ExportText.hasContent(capture.title)
                ? capture.title : (PromptGenerator.kindTitle(capture.kind) ?? "")
            // Port of `PromptGenerator.cs:26-29`: a capture the user said nothing about adds nothing
            // to the text — the image speaks for itself, and a bare "Снимок A." line would only
            // pollute the receiving prompt. Letters still come from the position in the package, so
            // the badges keep matching the text.
            if !ExportText.hasContent(title) && !ExportText.hasContent(capture.note)
                && labeled.isEmpty
            {
                continue
            }

            var section = "Снимок \(captureLabel)"
            if ExportText.hasContent(title) {
                section += " — \(title)"
            }
            section += "."

            if ExportText.hasContent(capture.note) {
                section += "\nКомментарий к снимку:\n\(capture.note)"
            }

            let labelsById = Dictionary(
                uniqueKeysWithValues: labeled.map { ($0.annotation.id, $0.displayLabel) })

            for entry in labeled {
                section += "\n\(entry.displayLabel): \(entry.annotation.note)"
                // Port of SPEC-DELTA-2B §B: a comment with a linked parent that itself has a
                // number (i.e. is present in `labelsById`) gets a " (к области <МЕТКА>)" suffix.
                if let parentId = entry.annotation.parentAnnotationId, let parentLabel = labelsById[parentId] {
                    section += " (к области \(parentLabel))"
                }
            }

            sections.append(section)
        }

        return sections.joined(separator: "\n\n")
    }

    /// Port of `PromptGenerator.KindTitle` (`PromptGenerator.cs:66`). `prompt.md` is Russian from
    /// the first line to the last, so the word for the kind is a literal here and does not travel
    /// through `UiLanguage`. An imported capture speaks through its `title` (the name of the file
    /// it came from), a region says nothing.
    static func kindTitle(_ kind: CaptureKind) -> String? {
        kind == .fullscreen ? "весь экран" : nil
    }
}
