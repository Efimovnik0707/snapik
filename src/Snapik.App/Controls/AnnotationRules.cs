using System.Windows.Media;
using Snapik.Core.Models;

namespace Snapik.App.Controls;

/// <summary>
/// The rules of a mark that hold without a canvas: what colour its outline takes, and what a press
/// of the mouse lands on. They live away from <see cref="AnnotationCanvas"/> on purpose — that one
/// is a FrameworkElement of a thousand lines and cannot be reached by a test, and these answers are
/// the ones two renderers and every gesture count from.
/// </summary>
internal static class AnnotationRules
{
    // The outline is always drawn in the colour of the mark, whatever stands inside it: the stroke
    // and the fill are two properties of their own, and a blurred region has no outline at all.
    // Null means "draw no outline".
    internal static Color? OutlineColorOf(AnnotationFill fill, Color color) =>
        fill == AnnotationFill.Blur ? null : color;

    /// <summary>What a press of the mouse has landed on, before the canvas acts on it.</summary>
    internal enum PressTarget { Pan, Erase, CropDraft, Activate, CommentAnchor, ResizeHandle, Object, Empty }
}
