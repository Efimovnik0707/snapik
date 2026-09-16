// Port of `src/Snapik.App/SettingsMigration.cs`, SPEC-DELTA-3 §1.1 C-9, §2.2.
import Foundation

/// The rules that change a settings file rather than read it. They live apart from `HotkeySettings`
/// on purpose: nothing here touches AppKit, so the rules are covered by the ordinary unit tests
/// instead of only by the smoke run.
public enum SettingsMigration {
    /// The schema version a file gets once every rule below has been applied to it.
    public static let currentVersion = 2

    /// How loud the interface sounds are on a machine that has never chosen.
    public static let defaultSoundVolume = 40

    // Version 1 lowers the default volume together with a softer shutter. Only the value that used
    // to be the default is moved: somebody who dragged the slider to 75, or deliberately to 60 after
    // this version, keeps what they picked, because the file then already carries the new version.
    private static let previousDefaultSoundVolume = 60

    public static func needsMigration(_ storedVersion: Int) -> Bool {
        storedVersion < currentVersion
    }

    // Every rule asks the version it was introduced in and not the current one. A shared threshold
    // would mean that raising the version for the theme runs the volume rule a second time over the
    // files of version 1, and everybody who set 60 by hand after the first migration is quietly
    // taken back down to 40 (SPEC-DELTA-4 §2.4). `needsMigration(_:)` is left as the sign that the
    // file has to be written back at all.
    public static func soundVolume(storedVersion: Int, storedVolume: Int) -> Int {
        storedVersion < 1 && storedVolume == previousDefaultSoundVolume
            ? defaultSoundVolume
            : storedVolume
    }

    /// Version 2 retires the flat light palette: the dawn theme is the light one now. Such a file
    /// would open dark anyway, because an unknown theme falls back there; the rule is what makes the
    /// file say so too, so the card the settings show is the theme that is on screen.
    public static func theme(storedVersion: Int, storedTheme: String) -> String {
        storedVersion < 2 && storedTheme.lowercased() == "light" ? "dark" : storedTheme
    }
}
