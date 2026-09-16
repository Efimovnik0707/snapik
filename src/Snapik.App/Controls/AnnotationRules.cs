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
    // The colour of the outline follows the fill: a solid or a translucent box outlines itself in
    // the colour of its fill, so no separate frame is seen; a blurred one has no outline at all; an
    // empty box keeps the colour of the mark. Null means "draw no outline".
    internal static Color? OutlineColorOf(AnnotationFill fill, Color color, Color? fillColor) => fill switch
    {
        AnnotationFill.Blur => null,
        AnnotationFill.Solid or AnnotationFill.Translucent => fillColor ?? color,
        _ => color
    };

    /// <summary>What a press of the mouse has landed on, before the canvas acts on it.</summary>
    internal enum PressTarget { Pan, Erase, CropDraft, Activate, CommentAnchor, ResizeHandle, Object, Empty }
}
