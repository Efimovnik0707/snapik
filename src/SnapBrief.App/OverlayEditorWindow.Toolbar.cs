using System;
using System.Linq;
using System.Windows;

namespace SnapBrief.App;

public partial class OverlayEditorWindow
{
    internal static Rect PlaceToolbar(Rect crop, Rect work, Size size, Rect[] notes)
    {
        const double gap = 10;
        var left = Math.Clamp(crop.Left + (crop.Width - size.Width) / 2, work.Left + 8, Math.Max(work.Left + 8, work.Right - size.Width - 8));
        var sideTop = Math.Clamp(crop.Top + (crop.Height - size.Height) / 2, work.Top + 8, Math.Max(work.Top + 8, work.Bottom - size.Height - 8));
        var candidates = new[]
        {
            new Rect(left, crop.Bottom + gap, size.Width, size.Height),
            new Rect(left, crop.Top - size.Height - gap, size.Width, size.Height),
            new Rect(crop.Right + gap, sideTop, size.Width, size.Height),
            new Rect(crop.Left - size.Width - gap, sideTop, size.Width, size.Height)
        }.Where(r => work.Contains(r) && !r.IntersectsWith(crop)).ToArray();
        // Preserve the image even when every outside position is near a note.
        foreach (var candidate in candidates)
            if (!notes.Any(n => n.IntersectsWith(candidate))) return candidate;
        if (candidates.Length > 0) return candidates[0];
        // A full-screen selection has no exterior space on its monitor.
        var bottom = Math.Clamp(crop.Bottom - size.Height - gap, work.Top + 8, Math.Max(work.Top + 8, work.Bottom - size.Height - 8));
        var top = Math.Clamp(crop.Top + gap, work.Top + 8, Math.Max(work.Top + 8, work.Bottom - size.Height - 8));
        var fallback = new Rect(left, bottom, size.Width, size.Height);
        var alternate = new Rect(left, top, size.Width, size.Height);
        return notes.Any(n => n.IntersectsWith(fallback)) && !notes.Any(n => n.IntersectsWith(alternate)) ? alternate : fallback;
    }
}
