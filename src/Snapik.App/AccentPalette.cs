using System.Windows;
using System.Windows.Media;

namespace Snapik.App;

/// <summary>
/// The one place the accent is read from for everything that draws. Before this, a dozen renderers
/// wrote the blue down by hand, and a violet accent stopped at the chrome.
///
/// Two rules hold it together. The fallback lives here and nowhere else: the unit tests and part of
/// the probes run without an Application behind them, and a null resource dictionary must not become
/// a null brush halfway down a render. And every brush and pen handed out is a frozen clone, never
/// the resource itself: a renderer that sets Opacity or a transform on what it was given would be
/// changing the accent of the whole application, and a caller must not have to know whether the
/// dictionary froze its brushes.
/// </summary>
internal static class AccentPalette
{
    /// <summary>The accent to fall back on when there is no application to read one from.</summary>
    private static readonly Color Fallback = Color.FromRgb(0x2F, 0x8C, 0xFF);

    /// <summary>
    /// The accent as a single colour: the accent itself when it is solid, the first stop when it is
    /// a gradient. For alpha mixes and for the exported PNG, where a Color is what fits.
    /// </summary>
    internal static Color Flat =>
        Application.Current?.Resources["AccentFlatColor"] is Color colour ? colour : Fallback;

    /// <summary>What paints: a solid brush or a gradient, whichever the accent is.</summary>
    internal static Brush Brush => Frozen(Application.Current?.Resources["AccentBrush"] as Brush);

    internal static Pen Pen(double thickness)
    {
        var pen = new Pen(Brush, thickness);
        pen.Freeze();
        return pen;
    }

    /// <summary>The accent thinned down to a wash: a fill behind a mark, a highlighted row.</summary>
    internal static Brush Wash(byte alpha)
    {
        var brush = new SolidColorBrush(Color.FromArgb(alpha, Flat.R, Flat.G, Flat.B));
        brush.Freeze();
        return brush;
    }

    private static Brush Frozen(Brush? brush)
    {
        var copy = brush?.CloneCurrentValue() ?? new SolidColorBrush(Fallback);
        copy.Freeze();
        return copy;
    }
}
