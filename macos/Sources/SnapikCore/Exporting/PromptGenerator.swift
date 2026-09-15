import Foundation

/// Port of `src/Snapik.Core/Exporting/PromptGenerator.cs`. UI strings are Russian verbatim
/// (matches the app's Russian-first prompt text; `UiLanguage` only translates chrome, not this
/// generated document).
public struct PromptGenerator {
    public init() {}

    public func generate(_ session: SnapikSession) throws -> String {
        try SessionValidation.validate(session)
        var sections: [String] = []

        if ExportText.hasContent(session.globalNote) {
            sections.append("Общее пожелание:\n\(session.globalNote)")
        }

        for (captureIndex, capture) in session.captures.enumerated() {
            let captureLabel = try CaptureLabels.forIndex(captureIndex)
            let labeled = CaptureLabels.forNotedAnnotations(captureLabel: captureLabel, capture: capture)
            // Port of `PromptGenerator.cs:23-29`: a capture the user said nothing about adds nothing
            // to the text — the image speaks for itself, and a bare "Снимок A." line would only
            // pollute the receiving prompt. Letters still come from the position in the package, so
            // the badges keep matching the text.
            if !ExportText.hasContent(capture.title) && !ExportText.hasContent(capture.note)
                && labeled.isEmpty
            {
                continue
            }

            var section = "Снимок \(captureLabel)"
            if ExportText.hasContent(capture.title) {
                section += " — \(capture.title)"
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
}
