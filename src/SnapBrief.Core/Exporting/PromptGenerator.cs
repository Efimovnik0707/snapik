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

            foreach (var labeled in CaptureLabels.ForNotedAnnotations(captureLabel, capture))
            {
                section.Append('\n')
                    .Append(labeled.DisplayLabel)
                    .Append(": ")
                    .Append(labeled.Annotation.Note);
            }

            sections.Add(section.ToString());
        }

        return string.Join("\n\n", sections);
    }
}
