import XCTest

@testable import SnapikCore

/// Port of `tests/Snapik.Core.Tests/SessionModelTests.cs`.
final class SessionModelTests: XCTestCase {
    private static let start = ISO8601Precise.makeUTC(year: 2026, month: 9, day: 8, hour: 20, minute: 0, second: 0)

    private struct FrozenTimeProvider: TimeProvider {
        let value: Date
        func utcNow() -> Date { value }
    }

    func test_Reorder_remove_and_undo_preserve_capture_identity_and_labels_follow_order() throws {
        let start = Self.start
        let first = CaptureItem.create(sourceImagePath: "source/first.png", pixelWidth: 100, pixelHeight: 100, title: "Первый")
        let second = CaptureItem.create(sourceImagePath: "source/second.png", pixelWidth: 100, pixelHeight: 100, title: "Второй")
        var session = try SessionOperations.addCapture(
            SnapikSession.create(nowUtc: start), capture: first, nowUtc: start.addingTimeInterval(60))
        session = try SessionOperations.addCapture(session, capture: second, nowUtc: start.addingTimeInterval(120))
        let history = SessionHistory(initial: session, timeProvider: FrozenTimeProvider(value: start.addingTimeInterval(600)))

        try history.apply { value in try SessionOperations.moveCapture(value, captureId: second.id, destinationIndex: 0, nowUtc: start.addingTimeInterval(180)) }
        try history.apply { value in try SessionOperations.removeCapture(value, captureId: first.id, nowUtc: start.addingTimeInterval(240)) }

        XCTAssertEqual(1, history.current.captures.count)
        XCTAssertEqual(second.id, history.current.captures[0].id)
        XCTAssertTrue(history.undo())
        XCTAssertEqual([second.id, first.id], history.current.captures.map { $0.id })
        XCTAssertEqual(5, history.current.revision)

        let prompt = try PromptGenerator().generate(history.current)
        XCTAssertTrue(prompt.contains("Снимок A — Второй."))
        XCTAssertTrue(prompt.contains("Снимок B — Первый."))
    }

    func test_Prompt_preserves_unicode_line_breaks_and_skips_empty_annotation_notes() throws {
        let start = Self.start
        var capture = CaptureItem.create(
            sourceImagePath: "source/a.png", pixelWidth: 100, pixelHeight: 100, note: "Строка 1\nСтрока 2 🙂")
        capture.annotations = [
            AnnotationItem.create(kind: .arrow, points: [NormalizedPoint(0.1, 0.2), NormalizedPoint(0.8, 0.9)], note: "Сделать шире"),
            AnnotationItem.create(kind: .rectangle, points: [NormalizedPoint(0.2, 0.2), NormalizedPoint(0.4, 0.4)]),
        ]
        var session = try SessionOperations.addCapture(SnapikSession.create(nowUtc: start), capture: capture, nowUtc: start)
        session.globalNote = "Сохранить цвета"

        let prompt = try PromptGenerator().generate(session)

        XCTAssertTrue(prompt.contains("Сохранить цвета"))
        XCTAssertTrue(prompt.contains("Строка 1\nСтрока 2 🙂"))
        XCTAssertTrue(prompt.contains("A1: Сделать шире"))
        XCTAssertFalse(prompt.contains("A2:"))
        XCTAssertEqual(
            ["A1"],
            CaptureLabels.forNotedAnnotations(captureLabel: "A", capture: capture).map { $0.displayLabel })
    }

    /// Port of `SessionModelTests.Captures_without_notes_get_no_section_and_a_silent_session_gets_no_text`.
    func test_Captures_without_notes_get_no_section_and_a_silent_session_gets_no_text() throws {
        let start = Self.start
        var silent = CaptureItem.create(sourceImagePath: "source/a.png", pixelWidth: 100, pixelHeight: 100)
        silent.annotations = [
            AnnotationItem.create(kind: .rectangle, points: [NormalizedPoint(0.2, 0.2), NormalizedPoint(0.4, 0.4)])
        ]
        var noted = CaptureItem.create(sourceImagePath: "source/b.png", pixelWidth: 100, pixelHeight: 100)
        noted.annotations = [
            AnnotationItem.create(
                kind: .arrow, points: [NormalizedPoint(0.1, 0.2), NormalizedPoint(0.8, 0.9)], note: "Сделать шире")
        ]
        let silentSession = try SessionOperations.addCapture(
            SnapikSession.create(nowUtc: start), capture: silent, nowUtc: start)
        let mixedSession = try SessionOperations.addCapture(
            silentSession, capture: noted, nowUtc: start.addingTimeInterval(1))

        XCTAssertEqual("", try PromptGenerator().generate(silentSession))

        let prompt = try PromptGenerator().generate(mixedSession)

        XCTAssertFalse(prompt.contains("Снимок A"))
        XCTAssertTrue(prompt.contains("Снимок B."))
        XCTAssertTrue(prompt.contains("B1: Сделать шире"))

        var withGlobalNote = silentSession
        withGlobalNote.globalNote = "Сохранить цвета"
        XCTAssertEqual(
            "Общее пожелание:\nСохранить цвета", try PromptGenerator().generate(withGlobalNote))
    }

    /// Port of `SessionModelTests.Sent_captures_leave_the_package_and_give_their_letters_to_the_waiting_ones`.
    func test_Sent_captures_leave_the_package_and_give_their_letters_to_the_waiting_ones() throws {
        var first = CaptureItem.create(sourceImagePath: "source/first.png", pixelWidth: 100, pixelHeight: 100)
        first.sent = true
        let second = CaptureItem.create(sourceImagePath: "source/second.png", pixelWidth: 100, pixelHeight: 100)
        var third = CaptureItem.create(sourceImagePath: "source/third.png", pixelWidth: 100, pixelHeight: 100)
        third.sent = true
        let fourth = CaptureItem.create(sourceImagePath: "source/fourth.png", pixelWidth: 100, pixelHeight: 100)
        let captures = [first, second, third, fourth]

        let package = SentCaptureRules.forPackage(captures) { $0.sent }
        let labels = try SentCaptureRules.stripLabels(captures.map { $0.sent })

        XCTAssertEqual([second.id, fourth.id], package.map { $0.id })
        XCTAssertEqual([nil, "A", nil, "B"], labels)
        XCTAssertEqual(["A", "B"] as [String?], try SentCaptureRules.stripLabels([false, false]))
        XCTAssertTrue(SentCaptureRules.forPackage(captures) { _ in true }.isEmpty)
    }

    /// Port of `SessionModelTests.A_full_strip_stops_at_twenty_six_captures_and_its_last_letter_is_Z`.
    /// The limit of the strip and its letters are one rule: a full strip asks for the letter Z and
    /// never for the one after it. The soft warning is below the limit, or it would never be said.
    func test_A_full_strip_stops_at_twenty_six_captures_and_its_last_letter_is_Z() throws {
        XCTAssertEqual(26, SentCaptureRules.maxStripCaptures)
        XCTAssertTrue(SentCaptureRules.softStripWarning < SentCaptureRules.maxStripCaptures)

        let labels = try SentCaptureRules.stripLabels(
            Array(repeating: false, count: SentCaptureRules.maxStripCaptures))

        XCTAssertEqual(SentCaptureRules.maxStripCaptures, labels.count)
        XCTAssertEqual("A", labels.first ?? nil)
        XCTAssertEqual("Z", labels.last ?? nil)
    }

}
