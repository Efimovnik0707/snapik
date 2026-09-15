using System;

namespace Snapik.App;

/// <summary>
/// The rules that change a settings file rather than read it. They live apart from
/// <see cref="HotkeySettings"/> on purpose: nothing here touches WPF, so the rules are covered by the
/// ordinary unit tests instead of only by the smoke run.
/// </summary>
internal static class SettingsMigration
{
    /// <summary>The schema version a file gets once every rule below has been applied to it.</summary>
    internal const int CurrentVersion = 2;

    /// <summary>How loud the interface sounds are on a machine that has never chosen.</summary>
    internal const int DefaultSoundVolume = 40;

    // Version 1 lowers the default volume together with a softer shutter. Only the value that used to
    // be the default is moved: somebody who dragged the slider to 75, or deliberately to 60 after
    // this version, keeps what they picked, because the file then already carries the new version.
    private const int PreviousDefaultSoundVolume = 60;

    internal static bool NeedsMigration(int storedVersion) => storedVersion < CurrentVersion;

    // Every rule asks the version it was introduced in and not the current one. A shared threshold
    // would mean that raising the version for the theme runs the volume rule a second time over the
    // files of version 1, and everybody who set 60 by hand after the first migration is quietly
    // taken back down to 40.
    internal static int SoundVolume(int storedVersion, int storedVolume) =>
        storedVersion < 1 && storedVolume == PreviousDefaultSoundVolume ? DefaultSoundVolume : storedVolume;

    /// <summary>
    /// Version 2 retires the flat light palette: the dawn theme is the light one now. Such a file
    /// would open dark anyway, because an unknown theme falls back there; the rule is what makes the
    /// file say so too, so the card the settings show is the theme that is on screen.
    /// </summary>
    internal static string Theme(int storedVersion, string storedTheme) =>
        storedVersion < 2 && string.Equals(storedTheme, "light", StringComparison.OrdinalIgnoreCase) ? "dark" : storedTheme;
}
