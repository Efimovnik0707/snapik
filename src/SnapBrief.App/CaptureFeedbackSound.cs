using System;
using System.Diagnostics;
using System.IO;
using System.Media;
using System.Threading;

namespace SnapBrief.App;

internal static class CaptureFeedbackSound
{
    private const int SampleRate = 44_100;
    private const long TickThrottleMilliseconds = 170;
    private const long CaptureSuppressionMilliseconds = 400;
    private const string ResourcePrefix = "SnapBrief.App.Assets.Audio.";
    private static readonly object Gate = new();
    private static readonly SoundPlayer Player = new();
    private static readonly Lazy<SoundAsset?> CaptureAsset = new(() => LoadAsset("camera-shutter.wav"));
    private static readonly Lazy<SoundAsset?> TickAsset = new(() => LoadAsset("camera-dial-click.wav"));
    private static long _lastCaptureTimestamp;
    private static long _lastTickTimestamp;

    internal static void Capture(bool enabled)
    {
        if (!enabled) return;
        Interlocked.Exchange(ref _lastCaptureTimestamp, Stopwatch.GetTimestamp());
        Play(CaptureAsset.Value);
    }

    internal static void Tick(bool enabled)
    {
        if (!enabled) return;
        var now = Stopwatch.GetTimestamp();
        var captureTimestamp = Interlocked.Read(ref _lastCaptureTimestamp);
        if (captureTimestamp != 0 && Stopwatch.GetElapsedTime(captureTimestamp, now).TotalMilliseconds < CaptureSuppressionMilliseconds) return;
        var previous = Interlocked.Read(ref _lastTickTimestamp);
        if (previous != 0 && Stopwatch.GetElapsedTime(previous, now).TotalMilliseconds < TickThrottleMilliseconds) return;
        Interlocked.Exchange(ref _lastTickTimestamp, now);
        Play(TickAsset.Value);
    }

    internal static void VerifyWaveHeaders()
    {
        VerifyWave(CaptureAsset.Value?.Wave ?? throw new InvalidOperationException("Bundled camera shutter WAV is missing."));
        VerifyWave(TickAsset.Value?.Wave ?? throw new InvalidOperationException("Bundled camera dial WAV is missing."));
    }

    private static SoundAsset? LoadAsset(string fileName)
    {
        try
        {
            using var resource = typeof(CaptureFeedbackSound).Assembly.GetManifestResourceStream(ResourcePrefix + fileName);
            if (resource is null) return null;
            using var buffer = new MemoryStream();
            resource.CopyTo(buffer);
            var wave = buffer.ToArray();
            return new SoundAsset(wave, new MemoryStream(wave, writable: false));
        }
        catch { return null; }
    }

    private static void Play(SoundAsset? asset)
    {
        if (asset is null) return;
        try
        {
            lock (Gate)
            {
                Player.Stop();
                asset.Stream.Position = 0;
                Player.Stream = asset.Stream;
                Player.Load();
                Player.Play();
            }
        }
        catch { /* Audio feedback must never interrupt capture or stack interaction. */ }
    }

    private static void VerifyWave(byte[] wave)
    {
        if (wave.Length < 44 || !wave.AsSpan(0, 4).SequenceEqual("RIFF"u8) ||
            !wave.AsSpan(8, 4).SequenceEqual("WAVE"u8) || !wave.AsSpan(36, 4).SequenceEqual("data"u8) ||
            BitConverter.ToInt32(wave, 4) != wave.Length - 8 || BitConverter.ToInt16(wave, 20) != 1 ||
            BitConverter.ToInt16(wave, 22) != 1 || BitConverter.ToInt32(wave, 24) != SampleRate ||
            BitConverter.ToInt16(wave, 34) != 16 || BitConverter.ToInt32(wave, 40) != wave.Length - 44)
            throw new InvalidOperationException("Bundled capture feedback is not a valid 44.1 kHz mono PCM WAV stream.");
    }

    private sealed record SoundAsset(byte[] Wave, MemoryStream Stream);
}
