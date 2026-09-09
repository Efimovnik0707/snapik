import XCTest

@testable import SnapBriefCore

/// Port of `tests/SnapBrief.Core.Tests/SessionModelTests.cs`.
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
            SnapBriefSession.create(nowUtc: start), capture: first, nowUtc: start.addingTimeInterval(60))
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
        var session = try SessionOperations.addCapture(SnapBriefSession.create(nowUtc: start), capture: capture, nowUtc: start)
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
}
