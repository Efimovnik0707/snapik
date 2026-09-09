using System.Text;
using SnapBrief.Core.Models;

namespace SnapBrief.Core.Exporting;

public sealed class PromptGenerator
{
    public string Generate(SnapBriefSession session)
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

            var labeledAnnotations = CaptureLabels.ForNotedAnnotations(captureLabel, capture).ToArray();
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
