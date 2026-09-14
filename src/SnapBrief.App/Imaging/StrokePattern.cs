using System.Windows.Media;
using SnapBrief.Core.Models;

namespace SnapBrief.App.Imaging;

// The pattern of a stroke, in one place for both renderers. The dashes of a DashStyle are measured
// in thicknesses of the pen and not in pixels, so one pattern gives the same stroke on the screen,
// where the thickness is multiplied by the scale of the view, and in the exported PNG, where it is
// the thickness in the pixels of the capture. No arithmetic stands between the two.
internal static class StrokePattern
{
    // Which marks have a stroke to pattern: the frame and the oval (one kind with two shapes), the
    // arrow and the pencil. A highlighter would fall apart into blots, and a caption, a blur and a
    // comment have no stroke at all, so they are drawn solid whatever their mark carries.
    internal static bool Participates(EditorTool kind) => kind is EditorTool.Rectangle or EditorTool.Arrow or EditorTool.Pen;

    internal static bool Participates(AnnotationKind kind) => kind is AnnotationKind.Rectangle or AnnotationKind.Arrow or AnnotationKind.Freehand;

    internal static AnnotationLineStyle Of(EditorTool kind, AnnotationLineStyle style) =>
        Participates(kind) ? style : AnnotationLineStyle.Solid;

    internal static AnnotationLineStyle Of(AnnotationKind kind, AnnotationLineStyle style) =>
        Participates(kind) ? style : AnnotationLineStyle.Solid;

    // Applied before the pen is frozen: three to two for a dash, and a gap of two with round ends
    // for a dot, which is a dash of no length at all.
    internal static Pen Apply(Pen pen, AnnotationLineStyle style)
    {
        switch (style)
        {
            case AnnotationLineStyle.Dashed:
                pen.DashStyle = new DashStyle([3, 2], 0);
                pen.DashCap = PenLineCap.Flat;
                break;
            case AnnotationLineStyle.Dotted:
                pen.DashStyle = new DashStyle([0, 2], 0);
                pen.DashCap = PenLineCap.Round;
                break;
        }
        return pen;
    }
}
