using System;
using System.Linq;
using System.Windows;

namespace Snapik.App.Controls;

/// <summary>How many rows the markup panel took.</summary>
internal enum ToolbarRows { One, Two }

/// <summary>The shape of the markup panel: its rows and the size it asks for.</summary>
internal readonly record struct ToolbarShape(ToolbarRows Rows, Size Size);

/// <summary>
/// Where the markup panel goes and how tall it is. Both are pure functions: the place of the
/// capture is worked out before the panel is laid out, and the two counts have to agree.
/// </summary>
internal static class ToolbarLayout
{
    /// <summary>
    /// How many rows the panel takes and how large it is. One row holds the tools, the properties,
    /// a free gap and the buttons on the right; two hold the tools and the buttons in the first and
    /// the properties in the second. It is measured from the three blocks and not from the finished
    /// panel, because the room for the capture is counted before the panel is arranged.
    /// </summary>
    internal static ToolbarShape Measure(Size tools, Size properties, Size actions, double freeWidth,
                                         double padding = 14, double gap = 12, double rowGap = 7)
    {
        var row = Math.Max(Math.Max(tools.Height, properties.Height), actions.Height);
        var oneRow = padding + tools.Width + properties.Width + gap + actions.Width;
        if (oneRow <= freeWidth) return new ToolbarShape(ToolbarRows.One, new Size(oneRow, padding + row));
        var twoRow = padding + Math.Max(tools.Width + gap + actions.Width, properties.Width);
        return new ToolbarShape(ToolbarRows.Two, new Size(Math.Min(twoRow, Math.Max(freeWidth, 380)),
                                                          padding + row * 2 + rowGap));
    }

    /// <summary>
    /// The place of the panel: under the capture, above it, to its right, to its left, and away
    /// from the pills of the notes if any of those positions allows it. When nothing outside fits,
    /// <paramref name="mayOverlap"/> decides: a full screen selection has no exterior space and the
    /// panel goes over the picture, while a capture that reserved room for the panel below it keeps
    /// that promise and the panel sits at the bottom of the working area instead.
    /// </summary>
    internal static Rect PlaceToolbar(Rect crop, Rect work, Size size, Rect[] notes, bool mayOverlap)
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
        // Nothing outside the capture fits, and the capture was placed leaving no room for the
        // panel: the bottom of the working area is the one place that is not over the picture.
        if (!mayOverlap) return new Rect(left, Math.Max(work.Top + 8, work.Bottom - size.Height - 8), size.Width, size.Height);
        // A full-screen selection has no exterior space on its monitor.
        var bottom = Math.Clamp(crop.Bottom - size.Height - gap, work.Top + 8, Math.Max(work.Top + 8, work.Bottom - size.Height - 8));
        var top = Math.Clamp(crop.Top + gap, work.Top + 8, Math.Max(work.Top + 8, work.Bottom - size.Height - 8));
        var fallback = new Rect(left, bottom, size.Width, size.Height);
        var alternate = new Rect(left, top, size.Width, size.Height);
        return notes.Any(n => n.IntersectsWith(fallback)) && !notes.Any(n => n.IntersectsWith(alternate)) ? alternate : fallback;
    }
}
