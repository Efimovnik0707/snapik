// Port of `src/Snapik.App/SoundVolumeCurve.cs`, SPEC-DELTA-5 §3.3.
import Foundation

/// The slider of the settings against what the ear hears. Lives in Core and not beside the player
/// so an ordinary test can hold it, the same reason `SettingsMigration` lives here.
public enum SoundVolumeCurve {
    /// An amplitude halved is only −6 dB, so a linear slider did almost nothing over the first half
    /// of its travel. The square spends the travel where the ear notices it: a quarter of the way
    /// is −24 dB. The top is untouched — at 100 the answer is the mix of the sound itself, and
    /// "as loud as it goes" does not move after the update.
    ///
    /// Both builds have to count this the same way, otherwise one number sounds different on the
    /// two platforms. `NSSound.volume` is an amplitude of 0…1, exactly like `MediaPlayer.Volume`:
    /// no curve of AppKit's own is added on top.
    public static func amplitude(volume: Int, gain: Double) -> Double {
        let level = Double(min(max(volume, 0), 100)) / 100.0
        return level * level * min(max(gain, 0), 1)
    }
}
