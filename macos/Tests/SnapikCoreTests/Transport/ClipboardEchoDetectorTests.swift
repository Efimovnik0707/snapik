// XCTest port of tests/Snapik.Windows.Tests/ClipboardEchoDetectorTests.cs (5 tests),
// SPEC-DELTA-2 Part 1 §5.

import XCTest
@testable import SnapikCore

final class ClipboardEchoDetectorTests: XCTestCase {
    private static let prompt = "Снимок A.\r\n  A1: тест1"

    // ReceiverEchoWithImagePlaceholder_IsDetected
    func testReceiverEchoWithImagePlaceholderIsDetected() {
        let snapshot = Self.textOnly("[Image #2]Снимок A.\r\n  A1: тест1")
        XCTAssertTrue(ClipboardEchoDetector.isReceiverEcho(snapshot, promptText: Self.prompt))
    }

    // ReceiverEchoWithExtraWhitespaceAndCrlf_IsDetected
    func testReceiverEchoWithExtraWhitespaceAndCrlfIsDetected() {
        let snapshot = Self.textOnly("  Снимок   A.\n\n  A1:   тест1  \r\n")
        XCTAssertTrue(ClipboardEchoDetector.isReceiverEcho(snapshot, promptText: Self.prompt))
    }

    // UnrelatedForeignText_IsNotAnEcho
    func testUnrelatedForeignTextIsNotAnEcho() {
        let snapshot = Self.textOnly("Совершенно другой текст")
        XCTAssertFalse(ClipboardEchoDetector.isReceiverEcho(snapshot, promptText: Self.prompt))
    }

    // ForeignTextWithFiles_IsNotAnEcho
    func testForeignTextWithFilesIsNotAnEcho() {
        let snapshot = ClipboardSnapshot(
            sequence: 1, hasText: true, text: Self.prompt, filePaths: ["/tmp/a.png"], hasImage: false)
        XCTAssertFalse(ClipboardEchoDetector.isReceiverEcho(snapshot, promptText: Self.prompt))
    }

    // ClipboardWithImage_IsNotAnEcho
    func testClipboardWithImageIsNotAnEcho() {
        let snapshot = ClipboardSnapshot(sequence: 1, hasText: true, text: Self.prompt, filePaths: [], hasImage: true)
        XCTAssertFalse(ClipboardEchoDetector.isReceiverEcho(snapshot, promptText: Self.prompt))
    }

    // Empty prompt text is never an echo (guard in `isReceiverEcho`'s first line).
    func testEmptyPromptIsNeverAnEcho() {
        let snapshot = Self.textOnly(Self.prompt)
        XCTAssertFalse(ClipboardEchoDetector.isReceiverEcho(snapshot, promptText: ""))
    }

    private static func textOnly(_ text: String) -> ClipboardSnapshot {
        ClipboardSnapshot(sequence: 1, hasText: true, text: text, filePaths: [], hasImage: false)
    }
}
