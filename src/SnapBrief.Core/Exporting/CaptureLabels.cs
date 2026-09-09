using SnapBrief.Core.Models;

namespace SnapBrief.Core.Exporting;

public readonly record struct LabeledAnnotation(string DisplayLabel, AnnotationItem Annotation);

public static class CaptureLabels
{
    public static string ForIndex(int zeroBasedIndex)
    {
        if (zeroBasedIndex is < 0 or >= 26)
        {
            throw new ArgumentOutOfRangeException(nameof(zeroBasedIndex));
        }

        return ((char)('A' + zeroBasedIndex)).ToString();
    }

    public static string ForAnnotation(string captureLabel, int oneBasedIndex) =>
        $"{captureLabel}{oneBasedIndex}";

    public static IEnumerable<LabeledAnnotation> ForNotedAnnotations(string captureLabel, CaptureItem capture)
    {
        var noteNumber = 0;
        foreach (var annotation in capture.Annotations)
        {
            if (!ExportText.HasContent(annotation.Note))
            {
                continue;
            }

            noteNumber++;
            yield return new LabeledAnnotation(ForAnnotation(captureLabel, noteNumber), annotation);
        }
    }
}
