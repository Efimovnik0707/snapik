using System.Windows.Media;

namespace Snapik.App.Imaging.Tests;

public sealed class ColorConversionTests
{
    [Theory]
    // The corners of the cube, a grey, a black and a white: what the spectrum has to give back
    // unchanged after a colour was read out of it and written into it again.
    [InlineData(0xFF, 0x00, 0x00)]
    [InlineData(0x00, 0xFF, 0x00)]
    [InlineData(0x00, 0x00, 0xFF)]
    [InlineData(0xFF, 0xFF, 0x00)]
    [InlineData(0x00, 0xFF, 0xFF)]
    [InlineData(0xFF, 0x00, 0xFF)]
    [InlineData(0x2F, 0x8C, 0xFF)]
    [InlineData(0xFF, 0x3B, 0x30)]
    [InlineData(0x8E, 0x8E, 0x93)]
    [InlineData(0x00, 0x00, 0x00)]
    [InlineData(0xFF, 0xFF, 0xFF)]
    [InlineData(0x01, 0x02, 0x03)]
    public void A_colour_survives_the_way_there_and_back(byte red, byte green, byte blue)
    {
        var colour = Color.FromRgb(red, green, blue);
        var (hue, saturation, value) = ColorConversion.RgbToHsv(colour);
        Assert.Equal(colour, ColorConversion.HsvToRgb(hue, saturation, value));
    }

    [Theory]
    // Grey has no hue and black has neither hue nor saturation: they are read as such, and putting
    // them back gives the same grey whatever hue the slider is standing on.
    [InlineData(0x80, 0x80, 0x80)]
    [InlineData(0x00, 0x00, 0x00)]
    public void A_colour_without_a_hue_is_the_same_on_every_hue(byte red, byte green, byte blue)
    {
        var colour = Color.FromRgb(red, green, blue);
        var (_, saturation, value) = ColorConversion.RgbToHsv(colour);
        Assert.Equal(0, saturation);
        foreach (var hue in new double[] { 0, 90, 210, 359 })
            Assert.Equal(colour, ColorConversion.HsvToRgb(hue, saturation, value));
    }

    [Fact]
    // A hue outside the circle is the same hue one turn further: the marker of the spectrum is
    // allowed to run off both ends of the strip.
    public void A_hue_outside_the_circle_wraps_around()
    {
        Assert.Equal(ColorConversion.HsvToRgb(0, 1, 1), ColorConversion.HsvToRgb(360, 1, 1));
        Assert.Equal(ColorConversion.HsvToRgb(330, 1, 1), ColorConversion.HsvToRgb(-30, 1, 1));
    }

    [Fact]
    // What the six corners of the circle are, so that a broken sector cannot pass as a round trip.
    public void The_corners_of_the_circle_are_the_pure_colours()
    {
        Assert.Equal(Color.FromRgb(0xFF, 0x00, 0x00), ColorConversion.HsvToRgb(0, 1, 1));
        Assert.Equal(Color.FromRgb(0xFF, 0xFF, 0x00), ColorConversion.HsvToRgb(60, 1, 1));
        Assert.Equal(Color.FromRgb(0x00, 0xFF, 0x00), ColorConversion.HsvToRgb(120, 1, 1));
        Assert.Equal(Color.FromRgb(0x00, 0xFF, 0xFF), ColorConversion.HsvToRgb(180, 1, 1));
        Assert.Equal(Color.FromRgb(0x00, 0x00, 0xFF), ColorConversion.HsvToRgb(240, 1, 1));
        Assert.Equal(Color.FromRgb(0xFF, 0x00, 0xFF), ColorConversion.HsvToRgb(300, 1, 1));
    }
}
