using System;
using System.Windows.Media;

namespace SnapBrief.App.Imaging;

/// <summary>
/// The colour a spectrum is picked in and the colour a mark is painted with, converted both ways.
/// Hue is degrees (0..360, 360 is the same red as 0), saturation and brightness are 0..1. Pure
/// functions with no picker behind them: the round trip is what the tests hold on to, and the macOS
/// port carries the same two.
/// </summary>
internal static class ColorConversion
{
    internal static Color HsvToRgb(double hue, double saturation, double value)
    {
        var s = Math.Clamp(saturation, 0, 1);
        var v = Math.Clamp(value, 0, 1);
        // A hue outside the circle is the same hue one turn further: -30 is 330, and 360 is 0.
        var h = double.IsNaN(hue) ? 0 : ((hue % 360) + 360) % 360;
        var sector = (int)Math.Floor(h / 60) % 6;
        var offset = h / 60 - Math.Floor(h / 60);
        var max = v;
        var min = v * (1 - s);
        var falling = v * (1 - s * offset);
        var rising = v * (1 - s * (1 - offset));
        var (r, g, b) = sector switch
        {
            0 => (max, rising, min),
            1 => (falling, max, min),
            2 => (min, max, rising),
            3 => (min, falling, max),
            4 => (rising, min, max),
            _ => (max, min, falling)
        };
        return Color.FromRgb(Channel(r), Channel(g), Channel(b));
    }

    internal static (double Hue, double Saturation, double Value) RgbToHsv(Color color)
    {
        var r = color.R / 255d;
        var g = color.G / 255d;
        var b = color.B / 255d;
        var max = Math.Max(r, Math.Max(g, b));
        var min = Math.Min(r, Math.Min(g, b));
        var span = max - min;
        // Grey has no hue of its own: it keeps the one it was being dragged through, and the caller
        // is the one holding that. Zero is what a colour read on its own answers with.
        var hue = span == 0 ? 0
            : max == r ? 60 * (((g - b) / span + 6) % 6)
            : max == g ? 60 * ((b - r) / span + 2)
            : 60 * ((r - g) / span + 4);
        return (hue, max == 0 ? 0 : span / max, max);
    }

    private static byte Channel(double value) => (byte)Math.Clamp(Math.Round(value * 255), 0, 255);
}
