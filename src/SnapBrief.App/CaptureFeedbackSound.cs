using System;
using System.Diagnostics;
using System.IO;
using System.Media;
using System.Threading;

namespace SnapBrief.App;

internal static class CaptureFeedbackSound
{
    private const int SampleRate = 44_100;
    private const long TickThrottleMilliseconds = 80;
    private static readonly object Gate = new();
    private static readonly SoundPlayer Player = new();
    private static readonly byte[] CaptureWave = CreateCaptureWave();
    private static readonly byte[] TickWave = CreateTickWave();
    private static readonly MemoryStream CaptureStream = new(CaptureWave, writable: false);
    private static readonly MemoryStream TickStream = new(TickWave, writable: false);
    private static long _lastTickTimestamp;

    internal static void Capture(bool enabled)
    {
        if (enabled) Play(CaptureStream);
    }

    internal static void Tick(bool enabled)
    {
        if (!enabled) return;
        var now = Stopwatch.GetTimestamp();
        var previous = Interlocked.Read(ref _lastTickTimestamp);
        if (previous != 0 && Stopwatch.GetElapsedTime(previous, now).TotalMilliseconds < TickThrottleMilliseconds) return;
        Interlocked.Exchange(ref _lastTickTimestamp, now);
        Play(TickStream);
    }

    internal static void VerifyWaveHeaders()
    {
        VerifyWave(CaptureWave);
        VerifyWave(TickWave);
    }

    private static void Play(MemoryStream stream)
    {
        try
        {
            lock (Gate)
            {
                Player.Stop();
                stream.Position = 0;
                Player.Stream = stream;
                // The blobs are tiny; loading them here prevents the asynchronous player from
                // reading a stream after the next feedback sound has rebound the single player.
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
            throw new InvalidOperationException("Generated capture feedback is not a valid PCM WAV stream.");
    }

    private static byte[] CreateCaptureWave()
    {
        const double duration = .115;
        var samples = new short[(int)(SampleRate * duration)];
        uint noise = 0x51A7C0DE;
        var filteredNoise = 0d;
        for (var i = 0; i < samples.Length; i++)
        {
            var time = i / (double)SampleRate;
            noise = noise * 1_664_525u + 1_013_904_223u;
            var white = ((noise >> 8) / 8_388_607.5) - 1;
            filteredNoise += .38 * (white - filteredNoise);

            var first = Math.Exp(-time * 82) * (Math.Sin(2 * Math.PI * 2_450 * time) * .28 + filteredNoise * .22);
            var secondTime = time - .047;
            var second = secondTime < 0 ? 0 : Math.Exp(-secondTime * 68) *
                (Math.Sin(2 * Math.PI * 1_720 * secondTime) * .22 + filteredNoise * .16);
            samples[i] = ToPcm16((first + second) * .72);
        }
        return WriteWave(samples);
    }

    private static byte[] CreateTickWave()
    {
        const double duration = .026;
        var samples = new short[(int)(SampleRate * duration)];
        uint noise = 0x0C11C5E1;
        var filteredNoise = 0d;
        for (var i = 0; i < samples.Length; i++)
        {
            var time = i / (double)SampleRate;
            noise = noise * 1_664_525u + 1_013_904_223u;
            var white = ((noise >> 8) / 8_388_607.5) - 1;
            filteredNoise += .22 * (white - filteredNoise);
            var envelope = Math.Exp(-time * 190);
            var sample = envelope * (Math.Sin(2 * Math.PI * 3_050 * time) * .11 + filteredNoise * .055);
            samples[i] = ToPcm16(sample);
        }
        return WriteWave(samples);
    }

    private static short ToPcm16(double sample) => (short)Math.Round(Math.Clamp(sample, -1, 1) * short.MaxValue);

    private static byte[] WriteWave(short[] samples)
    {
        using var stream = new MemoryStream(44 + samples.Length * sizeof(short));
        using var writer = new BinaryWriter(stream);
        writer.Write("RIFF"u8);
        writer.Write(36 + samples.Length * sizeof(short));
        writer.Write("WAVE"u8);
        writer.Write("fmt "u8);
        writer.Write(16);
        writer.Write((short)1);
        writer.Write((short)1);
        writer.Write(SampleRate);
        writer.Write(SampleRate * sizeof(short));
        writer.Write((short)sizeof(short));
        writer.Write((short)16);
        writer.Write("data"u8);
        writer.Write(samples.Length * sizeof(short));
        foreach (var sample in samples) writer.Write(sample);
        writer.Flush();
        return stream.ToArray();
    }
}
