using Snapik.Core.Models;

namespace Snapik.Core.Exporting;

public readonly record struct LabeledAnnotation(string DisplayLabel, AnnotationItem Annotation);

public static class CaptureLabels
{
    public static string ForIndex(int zeroBasedIndex)
    {
        if (zeroBasedIndex < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(zeroBasedIndex));
        }

        var value = (long)zeroBasedIndex + 1;
        var label = string.Empty;
        while (value > 0) { value--; label = (char)('A' + value % 26) + label; value /= 26; }
        return label;
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
