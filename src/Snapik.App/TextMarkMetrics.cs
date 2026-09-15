using System;
using System.Globalization;
using System.Windows;
using System.Windows.Media;

namespace Snapik.App;

// The box of a text mark is the letters themselves and not the point the hand clicked at. Without
// it the hit test, the eraser, the move handle and the selection all worked on a 16 px square beside
// the word, so a double click on a caption made a second caption instead of opening the first.
internal static class TextMarkMetrics
{
    internal const string FamilyName = "Segoe UI Variable Text";
    internal const double DefaultFontSize = 20;
    internal const double MinimumFontSize = 8;
    internal const double MaximumFontSize = 96;
    internal static readonly double[] FontSizePresets = [12, 16, 20, 24, 32, 48];

    // A size out of a settings file or a session written by hand still has to draw: FormattedText
    // throws on anything that is not a positive number.
    internal static double Clamp(double fontSize) =>
        double.IsFinite(fontSize) ? Math.Clamp(fontSize, MinimumFontSize, MaximumFontSize) : DefaultFontSize;

    // Measured in the pixels of the capture, with one pixel per dip, which is what the export
    // renderer draws with: the same numbers on screen and in the PNG.
    internal static Size Measure(string text, double fontSize)
    {
        var size = Clamp(fontSize);
        var formatted = new FormattedText(
            string.IsNullOrEmpty(text) ? " " : text, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight,
            new Typeface(FamilyName), size, Brushes.Black, 1);
        return new Size(
            Math.Max(size / 2, formatted.WidthIncludingTrailingWhitespace),
            Math.Max(size, formatted.Height));
    }

    // The second point of a text mark is not what the hand drew, it is what the letters take.
    internal static void Fit(AnnotationItem item)
    {
        if (item.Kind != EditorTool.Text || item.Points.Count == 0) return;
        var size = Measure(item.Text, item.FontSize);
        var anchor = item.Points[0];
        if (item.Points.Count < 2) item.Points.Add(anchor);
        item.Points[1] = new Point(anchor.X + size.Width, anchor.Y + size.Height);
    }
}
