using System.Text;
using Snapik.Core.Models;

namespace Snapik.Core.Exporting;

public sealed class PromptGenerator
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
            var captureLabel = CaptureLabels.ForIndex(captureIndex);
            var labeledAnnotations = CaptureLabels.ForNotedAnnotations(captureLabel, capture).ToArray();
            // A capture the user said nothing about adds nothing to the text: the image speaks for
            // itself, and a bare "Снимок A." line would only pollute the receiving prompt. Letters
            // still come from the position in the package, so the badges keep matching the text.
            if (!ExportText.HasContent(capture.Title) && !ExportText.HasContent(capture.Note) && labeledAnnotations.Length == 0)
            {
                continue;
            }

            var section = new StringBuilder($"Снимок {captureLabel}");
            if (ExportText.HasContent(capture.Title))
            {
                section.Append(" — ").Append(capture.Title);
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
}
