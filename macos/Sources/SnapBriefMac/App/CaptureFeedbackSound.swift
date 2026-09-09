// Port of `src/SnapBrief.App/CaptureFeedbackSound.cs`, SPEC-DELTA-2.md §1.6, SPEC-DELTA-2B.md §E2.
import AppKit
import Foundation
import SnapBriefCore

/// Plays the bundled camera-shutter/dial-click WAVs on capture and stack-card hover/scroll.
/// `capture`/`tick` are called from `App/AppCoordinator+OverlayEditorDelegate.swift` and
/// `Stack/ThumbnailCardView.swift` (CONTRACTS.md "Shell (звук)").
enum CaptureFeedbackSound {
    private static let tickThrottleNanoseconds: UInt64 = 170_000_000
    private static let captureSuppressionNanoseconds: UInt64 = 400_000_000

    private static let gate = NSLock()
    private static var lastCaptureTimestamp: UInt64?
    private static var lastTickTimestamp: UInt64?

    private static let captureSound: NSSound? = loadSound(named: "camera-shutter")
    private static let tickSound: NSSound? = loadSound(named: "camera-dial-click")

    static func capture(enabled: Bool) {
        guard enabled else { return }
        gate.lock()
        lastCaptureTimestamp = DispatchTime.now().uptimeNanoseconds
        gate.unlock()
        play(captureSound)
    }

    static func tick(enabled: Bool) {
        guard enabled else { return }
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
        play(tickSound)
    }

    /// Port of `VerifyWaveHeaders`; called first from `SmokeTestRunner` (SPEC §8.4).
    static func verifyWaveHeaders() throws {
        try verifyWave(dataFor: "camera-shutter")
        try verifyWave(dataFor: "camera-dial-click")
    }

    // MARK: - Loading

    private static func resourceURL(named name: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: "wav") {
            return url
        }
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: name, withExtension: "wav") {
            return url
        }
        #endif
        return nil
    }

    private static func loadSound(named name: String) -> NSSound? {
        guard let url = resourceURL(named: name), let data = try? Data(contentsOf: url) else { return nil }
        return NSSound(data: data)
    }

    private static func play(_ sound: NSSound?) {
        guard let sound else { return }
        // Port of `Play`: `Stop(); Position=0; Play()` — restart from the beginning on every call.
        sound.stop()
        sound.play()
    }

    // MARK: - Header verification (SPEC §1.6)

    private static func verifyWave(dataFor name: String) throws {
        guard let url = resourceURL(named: name), let data = try? Data(contentsOf: url) else {
            throw SnapBriefError.invalidData("Bundled capture feedback WAV \"\(name).wav\" is missing.")
        }
        try verifyWaveHeader(data)
    }

    private static func verifyWaveHeader(_ data: Data) throws {
        let invalid = SnapBriefError.invalidData(
            "Bundled capture feedback is not a valid 44.1 kHz mono PCM WAV stream.")
        guard data.count >= 44 else { throw invalid }

        func tag(_ offset: Int) -> String { String(decoding: data.subdata(in: offset..<offset + 4), as: UTF8.self) }
        func u32(_ offset: Int) -> UInt32 {
            let bytes = data.subdata(in: offset..<offset + 4)
            return bytes.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        }
        func i16(_ offset: Int) -> Int16 {
            let bytes = data.subdata(in: offset..<offset + 2)
            return bytes.withUnsafeBytes { $0.loadUnaligned(as: Int16.self) }
        }

        guard tag(0) == "RIFF", tag(8) == "WAVE", tag(36) == "data",
            u32(4) == UInt32(data.count - 8),
            i16(20) == 1,  // PCM
            i16(22) == 1,  // mono
            u32(24) == 44_100,
            i16(34) == 16,  // 16-bit
            u32(40) == UInt32(data.count - 44)
        else {
            throw invalid
        }
    }
}
