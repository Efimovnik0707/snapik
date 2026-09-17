using Snapik.App;

namespace Snapik.App.Imaging.Tests;

// The slider of the settings is squared before it reaches the player, so that its travel is spent
// where the ear notices. The three gains are the ones the three sounds are mixed with.
public sealed class SoundVolumeCurveTests
{
    private const double Shutter = 0.6;
    private const double Tick = 0.25;
    private const double Copied = 0.7;

    [Fact]
    public void The_top_of_the_slider_stays_where_it_was() =>
        Assert.Equal(Shutter, SoundVolumeCurve.Amplitude(100, Shutter), 6);

    [Fact]
    public void Half_the_slider_is_a_quarter_of_the_sound() =>
        Assert.Equal(0.15, SoundVolumeCurve.Amplitude(50, Shutter), 6);

    [Fact]
    public void A_quarter_of_the_slider_is_a_sixteenth_of_the_sound() =>
        Assert.Equal(0.0375, SoundVolumeCurve.Amplitude(25, Shutter), 6);

    [Fact]
    public void Zero_is_silence_and_not_a_whisper()
    {
        Assert.Equal(0, SoundVolumeCurve.Amplitude(0, Shutter), 6);
        Assert.Equal(0, SoundVolumeCurve.Amplitude(0, Copied), 6);
    }

    [Fact]
    public void A_value_outside_the_slider_is_pulled_back_onto_it()
    {
        Assert.Equal(0, SoundVolumeCurve.Amplitude(-5, Shutter), 6);
        Assert.Equal(Shutter, SoundVolumeCurve.Amplitude(250, Shutter), 6);
    }

    [Fact]
    public void The_curve_only_ever_rises()
    {
        foreach (var gain in new[] { Tick, Shutter, Copied })
            for (var volume = 1; volume <= 100; volume++)
                Assert.True(SoundVolumeCurve.Amplitude(volume, gain) > SoundVolumeCurve.Amplitude(volume - 1, gain));
    }
}
