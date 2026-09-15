using System.Diagnostics;
using System.Threading;

namespace Snapik.App;

/// <summary>
/// The clock of the interface sounds: a tick plays at most once per throttle window, and the shutter
/// mutes ticks for a moment after itself, because the pointer lands on the strip while the shutter
/// is still sounding. Timestamps come from <see cref="Stopwatch.GetTimestamp"/>; 0 means "never".
/// </summary>
internal sealed class SoundThrottle
{
    internal const double TickThrottleMilliseconds = 170;
    internal const double CaptureSuppressionMilliseconds = 400;
    private long _lastCapture;
    private long _lastTick;

    internal void Capture(long timestamp) => Interlocked.Exchange(ref _lastCapture, timestamp);

    internal bool AllowTick(long timestamp)
    {
        var capture = Interlocked.Read(ref _lastCapture);
        if (capture != 0 && Stopwatch.GetElapsedTime(capture, timestamp).TotalMilliseconds < CaptureSuppressionMilliseconds) return false;
        var previous = Interlocked.Read(ref _lastTick);
        if (previous != 0 && Stopwatch.GetElapsedTime(previous, timestamp).TotalMilliseconds < TickThrottleMilliseconds) return false;
        Interlocked.Exchange(ref _lastTick, timestamp);
        return true;
    }
}
