// Port of `CaptureFeedbackSound.VerifyWaveHeaders` + `HotkeySettings` back-compat decode,
// SPEC-DELTA-2B.md §F.
import Foundation
import XCTest
import SnapBriefCore

@testable import SnapBriefMac

final class CaptureFeedbackSoundTests: XCTestCase {
    func test_verifyWaveHeaders_does_not_throw() {
        XCTAssertNoThrow(try CaptureFeedbackSound.verifyWaveHeaders())
    }

    /// "Риски компиляции" #2 (SPEC-DELTA-2B.md): a `settings.json` written before sync 2 (no
    /// `AutoSaveCaptures`/`PlaySounds` keys) must still decode, falling back to the documented
    /// defaults instead of failing the whole decode.
    func test_HotkeySettings_decodes_without_the_new_keys_using_defaults() throws {
        let legacyJSON = """
            {
                "CaptureId": "ctrl-alt-s",
                "PasteId": "ctrl-alt-v",
                "CaptureEnabled": true,
                "FullscreenSaveEnabled": false,
                "FullscreenSaveId": "custom:4:44",
                "ShowNotifications": true,
                "RememberRegion": false,
                "CaptureCursor": false,
                "SaveFormat": "png",
                "JpegQuality": 90,
                "SaveDirectory": "/tmp/SnapBrief",
                "Language": "ru"
            }
            """
        let decoded = try JSONDecoder().decode(HotkeySettings.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(decoded.autoSaveCaptures, false)
        XCTAssertEqual(decoded.playSounds, true)
        XCTAssertEqual(decoded.captureId, "ctrl-alt-s")
    }
}
