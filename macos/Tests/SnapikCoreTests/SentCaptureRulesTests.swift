// Port of the `ClearsTheStrip` half of `tests/Snapik.App.Imaging.Tests/PublishedPackageTests.cs`,
// SPEC-DELTA-5 §2.2.
import XCTest

@testable import SnapikCore

final class SentCaptureRulesTests: XCTestCase {
    func test_The_setting_clears_the_strip_and_without_it_nothing_is_cleared() {
        XCTAssertTrue(
            SentCaptureRules.clearsTheStrip(isSingleCapture: false, clearStackAfterPaste: true))
        XCTAssertFalse(
            SentCaptureRules.clearsTheStrip(isSingleCapture: false, clearStackAfterPaste: false))
    }

    /// The one case the rule exists for: a capture copied on its own leaves the strip alone even
    /// when the setting is on, because the other cards were never sent anywhere.
    func test_A_capture_copied_on_its_own_never_clears_the_strip() {
        XCTAssertFalse(
            SentCaptureRules.clearsTheStrip(isSingleCapture: true, clearStackAfterPaste: true))
        XCTAssertFalse(
            SentCaptureRules.clearsTheStrip(isSingleCapture: true, clearStackAfterPaste: false))
    }
}
