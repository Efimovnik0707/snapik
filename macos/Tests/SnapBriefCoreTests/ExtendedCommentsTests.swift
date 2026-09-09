// Port of `tests/SnapBrief.Core.Tests/ExtendedCommentsTests.cs`, SPEC-DELTA-2.md §5,
// SPEC-DELTA-2B.md §B (linked comments beyond one alphabet).
import XCTest

@testable import SnapBriefCore

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

        var session = SnapBriefSession.create(nowUtc: Date())
        session.captures = [capture]

        let data = try SnapBriefJson.encoder.encode(session)
        let decoded = try SnapBriefJson.decoder.decode(SnapBriefSession.self, from: data)

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
}
