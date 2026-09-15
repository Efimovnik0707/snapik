namespace Snapik.App;

/// <summary>
/// The rules that change a settings file rather than read it. They live apart from
/// <see cref="HotkeySettings"/> on purpose: nothing here touches WPF, so the rules are covered by the
/// ordinary unit tests instead of only by the smoke run.
/// </summary>
internal static class SettingsMigration
{
    /// <summary>The schema version a file gets once every rule below has been applied to it.</summary>
    internal const int CurrentVersion = 1;

    /// <summary>How loud the interface sounds are on a machine that has never chosen.</summary>
    internal const int DefaultSoundVolume = 40;

    // Version 1 lowers the default volume together with a softer shutter. Only the value that used to
    // be the default is moved: somebody who dragged the slider to 75, or deliberately to 60 after
    // this version, keeps what they picked, because the file then already carries the new version.
    private const int PreviousDefaultSoundVolume = 60;

    internal static bool NeedsMigration(int storedVersion) => storedVersion < CurrentVersion;

    internal static int SoundVolume(int storedVersion, int storedVolume) =>
        NeedsMigration(storedVersion) && storedVolume == PreviousDefaultSoundVolume ? DefaultSoundVolume : storedVolume;
}
