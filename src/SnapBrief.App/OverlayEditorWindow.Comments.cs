using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using SnapBrief.App.Controls;

namespace SnapBrief.App;

public partial class OverlayEditorWindow
{
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

    private bool IsInsideChipLayer(DependencyObject? source)
    {
        while (source is not null)
        {
            if (ReferenceEquals(source, ChipLayer)) return true;
            source = source is Visual or System.Windows.Media.Media3D.Visual3D ? VisualTreeHelper.GetParent(source) : LogicalTreeHelper.GetParent(source);
        }
        return false;
    }

    private static Rect FindChipPlacement(Point preferred, Size size, Rect work, IReadOnlyList<Rect> occupied)
    {
        const double gap = 6;
        Rect Clamp(Point point)
        {
            var x = Math.Clamp(point.X, work.Left + 8, Math.Max(work.Left + 8, work.Right - size.Width - 8));
            var y = Math.Clamp(point.Y, work.Top + 8, Math.Max(work.Top + 8, work.Bottom - size.Height - 8));
            return new Rect(x, y, size.Width, size.Height);
        }
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
