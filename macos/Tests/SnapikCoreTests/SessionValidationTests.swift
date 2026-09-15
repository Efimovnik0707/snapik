import XCTest

@testable import SnapikCore

/// Port of the Windows `SessionValidationTests` (SPEC §8.3): one test per rejection branch in
/// `SessionValidation.validate` (`Sources/SnapikCore/Models/SessionValidation.swift`), each
/// built from an otherwise-valid session/capture/annotation so exactly one rule is violated.
final class SessionValidationTests: XCTestCase {
    private static let now = ISO8601Precise.makeUTC(year: 2026, month: 9, day: 8, hour: 20, minute: 0, second: 0)

    private func validAnnotation() -> AnnotationItem {
        AnnotationItem.create(
            kind: .arrow, points: [NormalizedPoint(0.1, 0.1), NormalizedPoint(0.5, 0.5)],
            thickness: 3, note: "Note")
    }

    private func validCapture(annotations: [AnnotationItem] = []) -> CaptureItem {
        var capture = CaptureItem.create(sourceImagePath: "captures/a.png", pixelWidth: 100, pixelHeight: 100)
        capture.annotations = annotations
        return capture
    }

    private func validSession(captures: [CaptureItem] = []) -> SnapikSession {
        var session = SnapikSession.create(nowUtc: Self.now)
        session.captures = captures
        return session
    }

    private func assertRejected(_ session: SnapikSession, contains fragment: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try SessionValidation.validate(session), file: file, line: line) { error in
            guard case SnapikError.invalidData(let message) = error else {
                XCTFail("expected SnapikError.invalidData, got \(error)", file: file, line: line)
                return
            }
            XCTAssertTrue(message.contains(fragment), "unexpected message: \(message)", file: file, line: line)
        }
    }

    func test_validSessionPasses() throws {
        try SessionValidation.validate(validSession(captures: [validCapture(annotations: [validAnnotation()])]))
    }

    func test_emptySessionIdIsRejected() {
        var session = validSession()
        session.id = .empty
        assertRejected(session, contains: "Session ID cannot be empty")
    }

    func test_unsupportedSchemaVersionIsRejected() {
        var session = validSession()
        session.schemaVersion = SnapikSession.currentSchemaVersion + 1
        assertRejected(session, contains: "Unsupported session schema version")
    }

    func test_negativeRevisionIsRejected() {
        var session = validSession()
        session.revision = -1
        assertRejected(session, contains: "Session revision cannot be negative")
    }

    func test_duplicateCaptureIdsAreRejected() {
        let capture = validCapture()
        let session = validSession(captures: [capture, capture])
        assertRejected(session, contains: "Capture IDs must be non-empty and unique")
    }

    func test_emptyCaptureIdIsRejected() {
        var capture = validCapture()
        capture.id = .empty
        assertRejected(validSession(captures: [capture]), contains: "Capture IDs must be non-empty and unique")
    }

    func test_unsafeCaptureImagePathIsRejected() {
        var capture = validCapture()
        capture.sourceImagePath = "../escape.png"
        assertRejected(validSession(captures: [capture]), contains: "must be relative and cannot escape")
    }

    func test_nonPositiveCaptureDimensionsAreRejected() {
        var capture = validCapture()
        capture.pixelWidth = 0
        assertRejected(validSession(captures: [capture]), contains: "dimensions and DPI must be positive")
    }

    func test_nonPositiveCaptureDpiIsRejected() {
        var capture = validCapture()
        capture.dpiX = 0
        assertRejected(validSession(captures: [capture]), contains: "dimensions and DPI must be positive")
    }

    func test_duplicateAnnotationIdsAreRejected() {
        let annotation = validAnnotation()
        let capture = validCapture(annotations: [annotation, annotation])
        assertRejected(validSession(captures: [capture]), contains: "Annotation IDs must be non-empty and unique")
    }

    func test_emptyAnnotationIdIsRejected() {
        var annotation = validAnnotation()
        annotation.id = .empty
        assertRejected(validSession(captures: [validCapture(annotations: [annotation])]), contains: "Annotation IDs must be non-empty and unique")
    }

    func test_nonPositiveAnnotationThicknessIsRejected() {
        var annotation = validAnnotation()
        annotation.thickness = 0
        assertRejected(
            validSession(captures: [validCapture(annotations: [annotation])]),
            contains: "positive thickness and geometry")
    }

    func test_emptyAnnotationPointsAreRejected() {
        var annotation = validAnnotation()
        annotation.points = []
        assertRejected(
            validSession(captures: [validCapture(annotations: [annotation])]),
            contains: "positive thickness and geometry")
    }

    func test_nonNormalizedAnnotationPointsAreRejected() {
        var annotation = validAnnotation()
        annotation.points = [NormalizedPoint(0.1, 0.1), NormalizedPoint(1.5, 0.5)]
        assertRejected(
            validSession(captures: [validCapture(annotations: [annotation])]),
            contains: "normalized to the [0, 1] image space")
    }

    func test_pathSegmentsOnDisallowedKindAreRejected() {
        var annotation = validAnnotation()
        annotation.kind = .rectangle
        annotation.pathSegments = [[NormalizedPoint(0.1, 0.1), NormalizedPoint(0.2, 0.2)]]
        assertRejected(
            validSession(captures: [validCapture(annotations: [annotation])]),
            contains: "Only freehand and highlight annotations")
    }

    func test_pathSegmentWithFewerThanTwoPointsIsRejected() {
        var annotation = validAnnotation()
        annotation.kind = .freehand
        annotation.pathSegments = [[NormalizedPoint(0.1, 0.1)]]
        assertRejected(
            validSession(captures: [validCapture(annotations: [annotation])]),
            contains: "Only freehand and highlight annotations")
    }

    func test_nonNormalizedPathSegmentCoordinatesAreRejected() {
        var annotation = validAnnotation()
        annotation.kind = .highlight
        annotation.pathSegments = [[NormalizedPoint(0.1, 0.1), NormalizedPoint(2.0, 0.2)]]
        assertRejected(
            validSession(captures: [validCapture(annotations: [annotation])]),
            contains: "path-segment coordinates must be normalized")
    }
}
