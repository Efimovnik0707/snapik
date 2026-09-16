// Port of `src/Snapik.App/UiSoundService.cs`, SPEC-DELTA-3 §1.5 G-10, G-11. Replaces
// `CaptureFeedbackSound` (two camera WAVs, on or off) with the three sounds of this round, each
// mixed at a gain of its own on top of the `SoundVolume` preference.
import AppKit
import Foundation
import SnapikCore

/// The three interface sounds: the shutter of a capture, the tick of the strip and the note that
/// says the package went to the clipboard. `AVAudioPlayer` and not `NSSound`: it has a volume of its
/// own, so the user can turn the sounds down instead of only off, and the three can be mixed to sit
/// at the same loudness (`UiSoundService.cs`'s `MediaPlayer` for the same reason).
///
/// Called from `App/AppCoordinator+OverlayEditorDelegate.swift`, `App/AppCoordinator+Package.swift`
/// and `Stack/EdgeStackWindowController.swift` (CONTRACTS.md "Shell (звук)").
enum UiSoundService {
    /// The shutter is mixed well below the other two: it fires on every capture, and the file that
    /// replaced the old one is hotter by about 6 dB, so the gain has to give that back and more
    /// (`macos/Resources/AUDIO-README.md` carries the provenance and the measurements).
    private static let shutter = Sound(fileName: "shutter-1-039s", gain: 0.6)
    private static let tickSound = Sound(fileName: "click-tiny-005s", gain: 0.25)
    private static let copiedSound = Sound(fileName: "notify-soft-040", gain: 0.7)

    private static let tickThrottleNanoseconds: UInt64 = 170_000_000
    private static let captureSuppressionNanoseconds: UInt64 = 400_000_000

    private static let gate = NSLock()
    private static var lastCaptureTimestamp: UInt64?
    private static var lastTickTimestamp: UInt64?

    static func capture(_ settings: HotkeySettings) {
        // The shutter mutes the ticks even when the sounds are off: turning them on mid-capture must
        // not let a tick through on the tail of a shutter nobody heard.
        gate.lock()
        lastCaptureTimestamp = DispatchTime.now().uptimeNanoseconds
        gate.unlock()
        guard settings.playSounds else { return }
        shutter.play(volume: settings.soundVolume)
    }

    static func tick(_ settings: HotkeySettings) {
        guard settings.playSounds else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        gate.lock()
        if let captureTimestamp = lastCaptureTimestamp, now - captureTimestamp < captureSuppressionNanoseconds {
            gate.unlock()
            return
        }
        if let previous = lastTickTimestamp, now - previous < tickThrottleNanoseconds {
            gate.unlock()
            return
        }
        lastTickTimestamp = now
        gate.unlock()
        tickSound.play(volume: settings.soundVolume)
    }

    static func copied(_ settings: HotkeySettings) {
        guard settings.playSounds else { return }
        copiedSound.play(volume: settings.soundVolume)
    }

    /// Port of `VerifyAssets`; called first from `SmokeTestRunner` (SPEC §8.4). The three files are
    /// shipped, are not empty and really start as an MP3 stream.
    static func verifyAssets() throws {
        for sound in [shutter, tickSound, copiedSound] {
            guard let data = sound.data(), data.count >= 3 else {
                throw SnapikError.invalidData("The bundled sound \"\(sound.fileName).mp3\" is missing or empty.")
            }
            let header = [UInt8](data.prefix(3))
            let tagged = header[0] == 0x49 && header[1] == 0x44 && header[2] == 0x33
            let frameSync = header[0] == 0xFF && (header[1] & 0xE0) == 0xE0
            guard tagged || frameSync else {
                throw SnapikError.invalidData(
                    "The bundled sound \"\(sound.fileName).mp3\" does not start as an MP3 stream.")
            }
        }
    }

    // MARK: - One sound

    private final class Sound {
        let fileName: String
        private let gain: Double
        private let gate = NSLock()
        private var player: NSSound?
        private var failed = false

        init(fileName: String, gain: Double) {
            self.fileName = fileName
            self.gain = gain
        }

        func data() -> Data? {
            guard let url = Self.resourceURL(named: fileName) else { return nil }
            return try? Data(contentsOf: url)
        }

        /// Port of `Sound.Play`: the volume of the preference, scaled by the gain of this sound, and
        /// the sound restarted from its beginning. Audio feedback must never interrupt a capture, so
        /// a sound that cannot be opened is switched off instead of throwing.
        func play(volume: Int) {
            gate.lock()
            if failed {
                gate.unlock()
                return
            }
            if player == nil {
                guard let data = data(), let opened = NSSound(data: data) else {
                    failed = true
                    gate.unlock()
                    return
                }
                player = opened
            }
            let sound = player
            gate.unlock()

            guard let sound else { return }
            sound.volume = Float(Double(max(0, min(100, volume))) / 100.0 * gain)
            sound.stop()
            sound.play()
        }

        private static func resourceURL(named name: String) -> URL? {
            if let url = Bundle.main.url(forResource: name, withExtension: "mp3") {
                return url
            }
            #if SWIFT_PACKAGE
            if let url = Bundle.module.url(forResource: name, withExtension: "mp3") {
                return url
            }
            #endif
            return nil
        }
    }
}
