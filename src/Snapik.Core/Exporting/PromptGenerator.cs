using System.Text;
using Snapik.Core.Models;

namespace Snapik.Core.Exporting;

/// <param name="singleCaptureLabel">
/// The letter of a package made of one capture, when that capture already carries one elsewhere:
/// copying the card "B" alone must not rename it "A" in the text while the card and the toast keep
/// saying "B". A package of two or more captures numbers itself by position as it always did.
/// </param>
public sealed class PromptGenerator(string? singleCaptureLabel = null)
{
    public string Generate(SnapikSession session)
    {
        SessionValidation.Validate(session);
        var sections = new List<string>();

        if (ExportText.HasContent(session.GlobalNote))
        {
            sections.Add($"Общее пожелание:\n{session.GlobalNote}");
        }

        for (var captureIndex = 0; captureIndex < session.Captures.Length; captureIndex++)
        {
            var capture = session.Captures[captureIndex];
            var captureLabel = singleCaptureLabel is { } only && session.Captures.Length == 1
                ? only
                : CaptureLabels.ForIndex(captureIndex);
            var labeledAnnotations = CaptureLabels.ForNotedAnnotations(captureLabel, capture).ToArray();
            // A whole-screen shot has no title of its own, and without a word the receiver cannot
            // tell it from a region: the kind speaks for it and counts as content of its own.
            var title = ExportText.HasContent(capture.Title) ? capture.Title : KindTitle(capture.Kind);
            // A capture the user said nothing about adds nothing to the text: the image speaks for
            // itself, and a bare "Снимок A." line would only pollute the receiving prompt. Letters
            // still come from the position in the package, so the badges keep matching the text.
            if (!ExportText.HasContent(title) && !ExportText.HasContent(capture.Note) && labeledAnnotations.Length == 0)
            {
                continue;
            }

            var section = new StringBuilder($"Снимок {captureLabel}");
            if (ExportText.HasContent(title))
            {
                section.Append(" — ").Append(title);
            }

            section.Append('.');
            if (ExportText.HasContent(capture.Note))
            {
                section.Append("\nКомментарий к снимку:\n").Append(capture.Note);
            }

            var labelsById = labeledAnnotations.ToDictionary(item => item.Annotation.Id, item => item.DisplayLabel);
            foreach (var labeled in labeledAnnotations)
            {
                section.Append('\n')
                    .Append(labeled.DisplayLabel)
                    .Append(": ")
                    .Append(labeled.Annotation.Note);
                if (labeled.Annotation.ParentAnnotationId is { } parentId)
                {
                    var parentLabel = labelsById.GetValueOrDefault(parentId);
                    if (!string.IsNullOrEmpty(parentLabel)) section.Append(" (к области ").Append(parentLabel).Append(')');
                }
            }

            sections.Add(section.ToString());
        }

        return string.Join("\n\n", sections);
    }

    // prompt.md is Russian from the first line to the last, so the word for the kind is a literal
    // here and does not travel through the interface table.
    private static string? KindTitle(CaptureKind kind) => kind == CaptureKind.Fullscreen ? "весь экран" : null;
}
