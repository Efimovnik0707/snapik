// Port of `tests/Snapik.Core.Tests/ExtendedCommentsTests.cs`, SPEC-DELTA-2.md §5,
// SPEC-DELTA-2B.md §B (linked comments beyond one alphabet).
import XCTest

@testable import SnapikCore

final class ExtendedCommentsTests: XCTestCase {
    func test_Labels_extend_beyond_one_alphabet() throws {
        XCTAssertEqual(try CaptureLabels.forIndex(0), "A")
        XCTAssertEqual(try CaptureLabels.forIndex(25), "Z")
        XCTAssertEqual(try CaptureLabels.forIndex(26), "AA")
        XCTAssertEqual(try CaptureLabels.forIndex(299), "KN")
        XCTAssertThrowsError(try CaptureLabels.forIndex(-1))
    }

    func test_Hundreds_of_comments_preserve_identity_links_and_arrow_style_in_json() throws {
        let parent = AnnotationItem.create(
            kind: .rectangle, points: [NormalizedPoint(0.05, 0.05), NormalizedPoint(0.2, 0.2)], note: "Родитель")

        var comments: [AnnotationItem] = []
        for index in 0..<300 {
            comments.append(
                AnnotationItem.create(
                    kind: .comment,
                    points: [NormalizedPoint(0.5, 0.5), NormalizedPoint(0.51, 0.51)],
                    note: "Комментарий \(index)",
                    parentAnnotationId: parent.id,
                    arrowStyle: "curved"))
        }

        var capture = CaptureItem.create(sourceImagePath: "source/a.png", pixelWidth: 1000, pixelHeight: 800)
        capture.annotations = [parent] + comments

        var session = SnapikSession.create(nowUtc: Date())
        session.captures = [capture]

        let data = try SnapikJson.encoder.encode(session)
        let decoded = try SnapikJson.decoder.decode(SnapikSession.self, from: data)

        XCTAssertEqual(decoded.captures.count, 1)
        let decodedAnnotations = decoded.captures[0].annotations
        XCTAssertEqual(decodedAnnotations.count, 301)
        let decodedComments = decodedAnnotations.filter { $0.kind == .comment }
        XCTAssertEqual(decodedComments.count, 300)
        XCTAssertTrue(decodedComments.allSatisfy { $0.parentAnnotationId == parent.id })
        XCTAssertTrue(decodedComments.allSatisfy { $0.arrowStyle == "curved" })

        let prompt = try PromptGenerator().generate(decoded)
        XCTAssertTrue(prompt.contains("A301: Комментарий 299 (к области A1)"))
    }

    func test_Cropping_keeps_comment_but_clears_a_removed_parent_link() throws {
        let parent = AnnotationItem.create(
            kind: .rectangle, points: [NormalizedPoint(0.6, 0.6), NormalizedPoint(0.9, 0.9)], note: "Parent")
        let comment = AnnotationItem.create(
            kind: .comment, points: [NormalizedPoint(0.1, 0.1), NormalizedPoint(0.11, 0.11)], note: "Keep",
            parentAnnotationId: parent.id, arrowStyle: "straight")

        var source = CaptureItem.create(sourceImagePath: "source/original.png", pixelWidth: 1000, pixelHeight: 800)
        source.annotations = [parent, comment]

        let result = try CaptureCropper.crop(
            source: source,
            cropBounds: NormalizedRect(0, 0, 0.5, 0.5),
            croppedSourceImagePath: "source/cropped.png",
            croppedPixelWidth: 500,
            croppedPixelHeight: 400)

        XCTAssertEqual(result.removedAnnotationIds, [parent.id])
        XCTAssertEqual(result.croppedCapture.annotations.count, 1)
        let retainedComment = try XCTUnwrap(result.croppedCapture.annotations.first)
        XCTAssertEqual(retainedComment.id, comment.id)
        XCTAssertEqual(retainedComment.note, "Keep")
        XCTAssertNil(retainedComment.parentAnnotationId)
    }

    /// Port of `ExtendedCommentsTests.Note_offset_survives_json_and_stays_null_in_a_session_written_without_it`.
    func test_Note_offset_survives_json_and_stays_nil_in_a_session_written_without_it() throws {
        var moved = AnnotationItem.create(
            kind: .comment, points: [NormalizedPoint(0.4, 0.4), NormalizedPoint(0.41, 0.41)], note: "Отведена")
        // A shift, not a coordinate: negative and outside the picture are both legal.
        moved.noteOffset = NormalizedPoint(-0.12, 0.3)
        let untouched = AnnotationItem.create(
            kind: .comment, points: [NormalizedPoint(0.6, 0.6), NormalizedPoint(0.61, 0.61)], note: "На месте")
        var capture = CaptureItem.create(sourceImagePath: "source/a.png", pixelWidth: 1000, pixelHeight: 800)
        capture.annotations = [moved, untouched]
        var session = SnapikSession.create(nowUtc: Date())
        session.captures = [capture]
        try SessionValidation.validate(session)

        let data = try SnapikJson.encoder.encode(session)
        let decoded = try SnapikJson.decoder.decode(SnapikSession.self, from: data)

        XCTAssertEqual(NormalizedPoint(-0.12, 0.3), decoded.captures[0].annotations[0].noteOffset)
        XCTAssertNil(decoded.captures[0].annotations[1].noteOffset)

        // A session written before the field reads back with automatic placement.
        let legacy = try Self.withoutKeys(["noteOffset"], data: data)
        let reread = try SnapikJson.decoder.decode(SnapikSession.self, from: legacy)
        XCTAssertNil(reread.captures[0].annotations[0].noteOffset)
    }

    /// Port of `ExtendedCommentsTests.Shape_and_fill_survive_json_and_default_for_a_session_written_without_them`.
    func test_Shape_and_fill_survive_json_and_default_for_a_session_written_without_them() throws {
        var oval = AnnotationItem.create(
            kind: .rectangle, points: [NormalizedPoint(0.1, 0.1), NormalizedPoint(0.4, 0.4)])
        oval.shape = .ellipse
        oval.fill = .translucent
        var rounded = AnnotationItem.create(
            kind: .blur, points: [NormalizedPoint(0.5, 0.5), NormalizedPoint(0.9, 0.9)])
        rounded.shape = .rounded
        var capture = CaptureItem.create(sourceImagePath: "source/a.png", pixelWidth: 1000, pixelHeight: 800)
        capture.annotations = [oval, rounded]
        var session = SnapikSession.create(nowUtc: Date())
        session.captures = [capture]

        let data = try SnapikJson.encoder.encode(session)
        let decoded = try SnapikJson.decoder.decode(SnapikSession.self, from: data)

        XCTAssertEqual(.ellipse, decoded.captures[0].annotations[0].shape)
        XCTAssertEqual(.translucent, decoded.captures[0].annotations[0].fill)
        XCTAssertEqual(.rounded, decoded.captures[0].annotations[1].shape)
        XCTAssertEqual(AnnotationFill.none, decoded.captures[0].annotations[1].fill)

        let legacy = try Self.withoutKeys(["shape", "fill"], data: data)
        let reread = try SnapikJson.decoder.decode(SnapikSession.self, from: legacy)
        XCTAssertTrue(reread.captures[0].annotations.allSatisfy { $0.shape == .rectangle && $0.fill == AnnotationFill.none })
    }

    /// Drops `keys` from every annotation of every capture: what a `session.json` written before
    /// the field existed looks like.
    private static func withoutKeys(_ keys: [String], data: Data) throws -> Data {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var captures = try XCTUnwrap(json["captures"] as? [[String: Any]])
        for captureIndex in captures.indices {
            var annotations = try XCTUnwrap(captures[captureIndex]["annotations"] as? [[String: Any]])
            for index in annotations.indices {
                for key in keys { annotations[index].removeValue(forKey: key) }
            }
            captures[captureIndex]["annotations"] = annotations
        }
        json["captures"] = captures
        return try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
    }

}
