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

    /// <summary>
    /// What a press of the left button means, in the one order every tool obeys. One rule and not a
    /// branch per tool: whatever is in hand, the corners of the selected mark, the anchor of a
    /// comment and the mark under the cursor answer before a new mark is begun.
    /// <paramref name="activatable"/> is "the mark under the cursor is a caption or a comment", the
    /// two that a double click opens for typing; on a frame or an arrow a double click is two
    /// single ones, that is, a selection.
    /// </summary>
    internal static PressTarget PressTargetOf(EditorTool tool, bool panning, int clickCount,
        bool onAnchor, bool onSelectedHandle, bool onObject, bool activatable) =>
            panning                        ? PressTarget.Pan
          : tool == EditorTool.Eraser      ? PressTarget.Erase
          // The crop is not an object tool: its frame is dragged over whatever lies under it.
          : tool == EditorTool.Crop        ? PressTarget.CropDraft
          : clickCount == 2 && activatable ? PressTarget.Activate
          : onAnchor                       ? PressTarget.CommentAnchor
          : onSelectedHandle               ? PressTarget.ResizeHandle
          : onObject                       ? PressTarget.Object
          :                                  PressTarget.Empty;
}
