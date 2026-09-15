// Port of `src/Snapik.App/SettingsMigration.cs`, SPEC-DELTA-3 §1.1 C-9, §2.2.
import Foundation

/// The rules that change a settings file rather than read it. They live apart from `HotkeySettings`
/// on purpose: nothing here touches AppKit, so the rules are covered by the ordinary unit tests
/// instead of only by the smoke run.
public enum SettingsMigration {
    /// The schema version a file gets once every rule below has been applied to it.
    public static let currentVersion = 1

    /// How loud the interface sounds are on a machine that has never chosen.
    public static let defaultSoundVolume = 40

    // Version 1 lowers the default volume together with a softer shutter. Only the value that used
    // to be the default is moved: somebody who dragged the slider to 75, or deliberately to 60 after
    // this version, keeps what they picked, because the file then already carries the new version.
    private static let previousDefaultSoundVolume = 60

    public static func needsMigration(_ storedVersion: Int) -> Bool {
        storedVersion < currentVersion
    }

    /// Every rule of a future version must ask about **its own** threshold rather than this one, or
    /// raising `currentVersion` would run the volume rule a second time over files that have
    /// already had it (`tasks/tz-005-details/B-themes-accents.md` §2.4).
    public static func soundVolume(storedVersion: Int, storedVolume: Int) -> Int {
        needsMigration(storedVersion) && storedVolume == previousDefaultSoundVolume
            ? defaultSoundVolume
            : storedVolume
    }
}
