using System;

namespace Snapik.App;

/// <summary>
/// The slider of the settings against what the ear hears. <see cref="System.Windows.Media.MediaPlayer.Volume"/>
/// is an amplitude, and amplitude halved is only −6 dB, which is nearly the same loudness: a slider
/// that walked it linearly did almost nothing over its first half. Squaring it spends the travel
/// where the ear notices, a quarter of the way giving −24 dB. The top is left alone on purpose: at
/// 100 the answer is the mix of the sound itself, so "as loud as it gets" does not move after an
/// update. The mix (<paramref name="gain"/>) is how loud that one sound is meant to be among the rest.
/// </summary>
internal static class SoundVolumeCurve
{
    internal static double Amplitude(int volume, double gain)
    {
        var level = Math.Clamp(volume, 0, 100) / 100.0;
        return level * level * Math.Clamp(gain, 0, 1);
    }
}
