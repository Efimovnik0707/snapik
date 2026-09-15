using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Media;

namespace Snapik.App;

/// <summary>
/// The three interface sounds. <see cref="MediaPlayer"/> instead of <c>SoundPlayer</c>: it has a
/// volume of its own, so the user can turn the sounds down instead of only off, and every sound is
/// mixed at a gain that makes the three sit at the same loudness. The files are ordinary content
/// next to the executable, because MediaPlayer does not open <c>pack://application</c> resources.
/// Every call happens on the UI thread: MediaPlayer belongs to the dispatcher that created it.
/// </summary>
internal static class UiSoundService
{
    private const string ShutterFile = "shutter-1-039s.mp3";
    private const string TickFile = "click-tiny-005s.mp3";
    private const string CopiedFile = "notify-soft-040.mp3";
    // The shutter is mixed well below the other two: it fires on every capture, and the file that
    // replaced the old one is hotter by about 6 dB, so the gain has to give that back and more.
    private static readonly Sound Shutter = new(ShutterFile, 0.6);
    private static readonly Sound TickSound = new(TickFile, 0.25);
    private static readonly Sound CopiedSound = new(CopiedFile, 0.7);
    private static readonly SoundThrottle Throttle = new();

    internal static void Capture(HotkeySettings settings)
    {
        // The shutter mutes the ticks even when the sounds are off: turning them on mid-capture must
        // not let a tick through on the tail of a shutter nobody heard.
        Throttle.Capture(Stopwatch.GetTimestamp());
        if (!settings.PlaySounds) return;
        Shutter.Play(settings.SoundVolume);
    }

    internal static void Tick(HotkeySettings settings)
    {
        if (!settings.PlaySounds) return;
        if (!Throttle.AllowTick(Stopwatch.GetTimestamp())) return;
        TickSound.Play(settings.SoundVolume);
    }

    internal static void Copied(HotkeySettings settings)
    {
        if (!settings.PlaySounds) return;
        CopiedSound.Play(settings.SoundVolume);
    }

    /// <summary>Opens the files while the strip starts, so the first sound is not the one that waits for the disk.</summary>
    internal static void Preload()
    {
        Shutter.Open();
        TickSound.Open();
        CopiedSound.Open();
    }

    /// <summary>Smoke check: the three files are shipped next to the assembly and are really MP3.</summary>
    internal static void VerifyAssets()
    {
        foreach (var fileName in new[] { ShutterFile, TickFile, CopiedFile })
        {
            var path = PathOf(fileName);
            if (!File.Exists(path))
                throw new InvalidOperationException($"The bundled sound \"{fileName}\" is missing next to the assembly.");
            var header = new byte[3];
            using var stream = File.OpenRead(path);
            if (stream.Length == 0 || stream.Read(header, 0, header.Length) != header.Length)
                throw new InvalidOperationException($"The bundled sound \"{fileName}\" is empty.");
            var tagged = header[0] == 0x49 && header[1] == 0x44 && header[2] == 0x33;
            var frameSync = header[0] == 0xFF && (header[1] & 0xE0) == 0xE0;
            if (!tagged && !frameSync)
                throw new InvalidOperationException($"The bundled sound \"{fileName}\" does not start as an MP3 stream.");
        }
    }

    private static string PathOf(string fileName) => Path.Combine(AppContext.BaseDirectory, "Assets", "Audio", fileName);

    private sealed class Sound(string fileName, double gain)
    {
        private MediaPlayer? _player;
        private bool _failed;

        internal void Open()
        {
            // Nothing but the exception of a missing codec or a missing file can happen here, and a
            // sound that cannot be opened must not stop a capture.
            try { _ = Player(); } catch { _failed = true; }
        }

        internal void Play(int volume)
        {
            if (_failed) return;
            try
            {
                var player = Player();
                player.Volume = Math.Clamp(volume, 0, 100) / 100.0 * gain;
                player.Position = TimeSpan.Zero;
                player.Play();
            }
            catch { /* Audio feedback must never interrupt capture or strip interaction. */ }
        }

        private MediaPlayer Player()
        {
            if (_player is { } opened) return opened;
            var player = new MediaPlayer();
            player.MediaFailed += (_, _) => _failed = true;
            // The player is kept before the file is opened, and a throwing Open switches the sound
            // off: otherwise every play would build another MediaPlayer on the same broken file.
            _player = player;
            try { player.Open(new Uri(PathOf(fileName), UriKind.Absolute)); }
            catch { _failed = true; throw; }
            return player;
        }
    }
}
