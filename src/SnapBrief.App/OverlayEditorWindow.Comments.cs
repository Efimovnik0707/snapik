using System;
using System.Linq;
using System.Windows;
using SnapBrief.App.Controls;

namespace SnapBrief.App;

public partial class OverlayEditorWindow
{
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
