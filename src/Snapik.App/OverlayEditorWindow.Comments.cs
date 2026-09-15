using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Snapik.App.Controls;

namespace Snapik.App;

public partial class OverlayEditorWindow
{
    private const double CommentsPanelWidth = 280;
    private const double CommentsPanelGap = 16;

    // The work area the markup is laid out in: with the comments panel on screen it is the monitor
    // minus the strip that panel takes, so the capture never hides under it.
    private Rect LayoutWorkArea() => WithoutCommentsStrip(GetCropMonitorWorkArea(), _commentsPanelVisible);

    private static Rect WithoutCommentsStrip(Rect work, bool panelVisible) =>
        panelVisible
            ? new Rect(work.Left, work.Top, Math.Max(240, work.Width - CommentsPanelWidth - CommentsPanelGap), work.Height)
            : work;

    private void PositionCommentsPanel()
    {
        CommentsPanel.Visibility = _commentsPanelVisible ? Visibility.Visible : Visibility.Collapsed;
        if (!_commentsPanelVisible) return;
        var work = GetCropMonitorWorkArea();
        CommentsPanel.Margin = new Thickness(Math.Max(work.Left, work.Right - CommentsPanelWidth - 8), work.Top + 8, 0, 0);
        CommentsPanel.Height = Math.Max(160, work.Height - 16);
    }

    // The rows the panel shows: every comment pin, even one still without text, and every mark that
    // carries a note. The numbers are the numbers of the export, taken from the same code.
    private IEnumerable<(AnnotationItem Annotation, string Label)> CommentRows()
    {
        if (_capture is null) yield break;
        foreach (var annotation in _capture.Annotations)
            if (annotation.Kind == EditorTool.Comment || !string.IsNullOrWhiteSpace(annotation.Note))
                yield return (annotation, string.IsNullOrEmpty(annotation.Label) ? "+" : annotation.Label);
    }

    // Called after every change of the notes: the rows are rebuilt only when the set of them
    // changed, otherwise the numbers and the text are refreshed in place.
    private void SyncCommentsPanel()
    {
        if (!_commentsPanelVisible || _capture is null) return;
        var rows = CommentRows().ToArray();
        var current = CommentsList.Children.OfType<CommentListEntry>().ToArray();
        if (!current.Select(entry => entry.AnnotationId).SequenceEqual(rows.Select(row => row.Annotation.Id)))
        {
            CommentsList.Children.Clear();
            foreach (var (annotation, _) in rows)
            {
                var entry = new CommentListEntry(annotation.Id);
                entry.Activated += (_, _) => ActivateCommentRow(annotation.Id);
                CommentsList.Children.Add(entry);
            }
            current = [.. CommentsList.Children.OfType<CommentListEntry>()];
        }
        for (var i = 0; i < rows.Length; i++)
        {
            var (annotation, label) = rows[i];
            current[i].Label = label;
            current[i].Text = annotation.Note;
            current[i].Relation = RelationOf(annotation);
        }
        CommentsEmpty.Visibility = rows.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
        HighlightCommentRow(Surface.SelectedAnnotation?.Id);
    }

    private string RelationOf(AnnotationItem annotation)
    {
        if (annotation.Kind != EditorTool.Comment) return string.Empty;
        if (_capture is null) return string.Empty;
        var parent = annotation.ParentAnnotationId is { } parentId
            ? _capture.Annotations.FirstOrDefault(item => item.Id == parentId)
            : null;
        return parent is { Label.Length: > 0 }
            ? $"{UiLanguage.Text("К отметке")} {parent.Label}"
            : $"{UiLanguage.Text("К снимку")} {_capture.DisplayLabel}";
    }

    // A click on a row selects the mark on the capture and opens its pill, without taking the focus
    // off the capture; the highlight travels the other way as well, through OnSelectionChanged.
    private void ActivateCommentRow(Guid annotationId)
    {
        Surface.SelectAnnotation(annotationId);
        if (_chipExpanders.TryGetValue(annotationId, out var expand)) expand(true);
        HighlightCommentRow(annotationId);
    }

    private void HighlightCommentRow(Guid? annotationId)
    {
        if (!_commentsPanelVisible) return;
        var offset = 0d;
        var found = -1d;
        foreach (var entry in CommentsList.Children.OfType<CommentListEntry>())
        {
            entry.IsCurrent = annotationId is { } id && entry.AnnotationId == id;
            if (entry.IsCurrent) found = offset;
            offset += entry.ActualHeight + entry.Margin.Top + entry.Margin.Bottom;
        }
        // Scrolled to by the heights of the rows above it: a row that was never laid out has no
        // position to transform into the panel.
        if (found >= 0) CommentsScroll.ScrollToVerticalOffset(found);
    }

    private bool HasFocusedChipOtherThan(Guid id) =>
        _chipBorders.Any(entry => entry.Key != id && entry.Value.IsKeyboardFocusWithin);

    private void CollapseOtherChips(Guid activeId)
    {
        foreach (var entry in _chipExpanders.Where(entry => entry.Key != activeId).ToArray())
        {
            if (_chipBorders.TryGetValue(entry.Key, out var chip) && chip.IsKeyboardFocusWithin) continue;
            entry.Value(false);
        }
    }

    private void FinishExpandedChipIfOutside(DependencyObject? source)
    {
        if (_expandedChipId is not { } id || IsInsideChipLayer(source)) return;
        if (_chipFinishers.TryGetValue(id, out var finish)) finish();
    }

    private bool IsInsideChipLayer(DependencyObject? source) => IsInside(source, ChipLayer);

    // Whether a press landed inside a given part of the window: the layer of the note pills, or the
    // text box a caption is being typed in.
    private static bool IsInside(DependencyObject? source, DependencyObject root)
    {
        while (source is not null)
        {
            if (ReferenceEquals(source, root)) return true;
            source = source is Visual or System.Windows.Media.Media3D.Visual3D ? VisualTreeHelper.GetParent(source) : LogicalTreeHelper.GetParent(source);
        }
        return false;
    }

    // A chip never leaves the work area of its monitor, wherever it is asked to go.
    private static Rect ClampChip(Point point, Size size, Rect work) => new(
        Math.Clamp(point.X, work.Left + 8, Math.Max(work.Left + 8, work.Right - size.Width - 8)),
        Math.Clamp(point.Y, work.Top + 8, Math.Max(work.Top + 8, work.Bottom - size.Height - 8)),
        size.Width, size.Height);

    private static Rect FindChipPlacement(Point preferred, Size size, Rect work, IReadOnlyList<Rect> occupied)
    {
        const double gap = 6;
        Rect Clamp(Point point) => ClampChip(point, size, work);
        bool IsFree(Rect candidate) => occupied.All(rect => !Inflate(rect, gap).IntersectsWith(candidate));

        var first = Clamp(preferred);
        if (IsFree(first)) return first;
        for (var ring = 1; ring <= 14; ring++)
        {
            var horizontal = (size.Width + gap) * ring;
            var vertical = (Math.Max(40, size.Height) + gap) * ring;
            foreach (var offset in new[]
            {
                new Vector(0, vertical), new Vector(horizontal, 0), new Vector(-horizontal, 0), new Vector(0, -vertical),
                new Vector(horizontal, vertical), new Vector(-horizontal, vertical), new Vector(horizontal, -vertical), new Vector(-horizontal, -vertical)
            })
            {
                var candidate = Clamp(preferred + offset);
                if (IsFree(candidate)) return candidate;
            }
        }
        return first;

        static Rect Inflate(Rect rect, double amount)
        {
            rect.Inflate(amount, amount);
            return rect;
        }
    }

    private void MoveLinkedComments()
    {
        if (_capture is null || _lastSnapshot is null) return;
        foreach (var comment in _capture.Annotations.Where(a => a.ParentAnnotationId is not null))
        {
            var parent = _capture.Annotations.FirstOrDefault(a => a.Id == comment.ParentAnnotationId);
            if (parent is null) { comment.ParentAnnotationId = null; continue; }
            var before = _lastSnapshot.Capture.Annotations.FirstOrDefault(a => a.Id == parent.Id);
            if (before is null || before.Points.Count == 0 || parent.Points.Count == 0) continue;
            var oldBounds = Bounds(before); var newBounds = Bounds(parent);
            if (oldBounds == newBounds) continue;
            for (var i = 0; i < comment.Points.Count; i++)
            {
                var mapped = oldBounds.Width > 0 && oldBounds.Height > 0 ? ResizeGeometry.Map(comment.Points[i], oldBounds, newBounds) : comment.Points[i] + (parent.Points[0] - before.Points[0]);
                comment.Points[i] = new Point(Math.Clamp(mapped.X, 0, _capture.Image.PixelWidth), Math.Clamp(mapped.Y, 0, _capture.Image.PixelHeight));
            }
        }
        static Rect Bounds(AnnotationItem item) => new(new Point(item.Points.Min(p => p.X), item.Points.Min(p => p.Y)), new Point(item.Points.Max(p => p.X), item.Points.Max(p => p.Y)));
    }
}
