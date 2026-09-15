using System.Diagnostics;
using Snapik.App;

namespace Snapik.App.Imaging.Tests;

public sealed class SoundThrottleTests
{
    // Timestamps are Stopwatch ticks; the offset keeps them away from 0, which means "never".
    private static long At(double milliseconds) => 1 + (long)(milliseconds / 1000.0 * Stopwatch.Frequency);

    [Fact]
    public void First_tick_plays_and_the_next_one_inside_the_window_does_not()
    {
        var throttle = new SoundThrottle();

        Assert.True(throttle.AllowTick(At(0)));
        Assert.False(throttle.AllowTick(At(SoundThrottle.TickThrottleMilliseconds - 20)));
        Assert.True(throttle.AllowTick(At(SoundThrottle.TickThrottleMilliseconds + 20)));
    }

    [Fact]
    public void A_dropped_tick_does_not_restart_the_window()
    {
        var throttle = new SoundThrottle();

        Assert.True(throttle.AllowTick(At(0)));
        Assert.False(throttle.AllowTick(At(100)));
        Assert.False(throttle.AllowTick(At(160)));
        Assert.True(throttle.AllowTick(At(SoundThrottle.TickThrottleMilliseconds + 1)));
    }

    [Fact]
    public void The_shutter_mutes_the_ticks_that_follow_it()
    {
        var throttle = new SoundThrottle();
        throttle.Capture(At(0));

        Assert.False(throttle.AllowTick(At(SoundThrottle.CaptureSuppressionMilliseconds - 50)));
        Assert.True(throttle.AllowTick(At(SoundThrottle.CaptureSuppressionMilliseconds + 50)));
    }
}
