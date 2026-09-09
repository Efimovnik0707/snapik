import XCTest

@testable import SnapBriefCore

/// Port of `tests/SnapBrief.Core.Tests/CaptureCropperTests.cs`.
final class CaptureCropperTests: XCTestCase {
    func test_Crop_preserves_identity_and_notes_clips_geometry_and_reports_removed_annotations() throws {
        let arrow = AnnotationItem.create(
            kind: .arrow, points: [NormalizedPoint(0.1, 0.5), NormalizedPoint(0.9, 0.5)], note: "Arrow note")
        let box = AnnotationItem.create(
            kind: .blur, points: [NormalizedPoint(0.1, 0.1), NormalizedPoint(0.4, 0.4)], note: "Blur note")
        let outside = AnnotationItem.create(
            kind: .redaction, points: [NormalizedPoint(0.8, 0.8), NormalizedPoint(0.9, 0.9)], note: "Outside")
        var source = CaptureItem.create(
            sourceImagePath: "source/original.png", pixelWidth: 1000, pixelHeight: 800, dpiX: 144, dpiY: 144,
            title: "Title", note: "Capture note")
        source.annotations = [arrow, box, outside]

        let result = try CaptureCropper.crop(
            source: source,
            cropBounds: NormalizedRect(0.25, 0.25, 0.5, 0.5),
            croppedSourceImagePath: "source/cropped.png",
            croppedPixelWidth: 500,
            croppedPixelHeight: 400)

        XCTAssertEqual(result.previousCapture, source)
        XCTAssertEqual(source.id, result.croppedCapture.id)
        XCTAssertEqual(source.title, result.croppedCapture.title)
        XCTAssertEqual(source.note, result.croppedCapture.note)
        XCTAssertEqual(source.dpiX, result.croppedCapture.dpiX)
        XCTAssertEqual(source.dpiY, result.croppedCapture.dpiY)
        XCTAssertEqual("source/cropped.png", result.croppedCapture.sourceImagePath)
        XCTAssertEqual(500, result.croppedCapture.pixelWidth)
        XCTAssertEqual(400, result.croppedCapture.pixelHeight)
        XCTAssertEqual([arrow.id, box.id], result.croppedCapture.annotations.map { $0.id })
        XCTAssertEqual([outside.id], result.removedAnnotationIds)

        assertPoint(result.croppedCapture.annotations[0].points[0], 0, 0.5)
        assertPoint(result.croppedCapture.annotations[0].points[1], 1, 0.5)
        assertPoint(result.croppedCapture.annotations[1].points[0], 0, 0)
        assertPoint(result.croppedCapture.annotations[1].points[1], 0.3, 0.3)
    }

    func test_Crop_preserves_all_visible_polyline_runs_without_joining_disconnected_segments() throws {
        let stroke = AnnotationItem.create(
            kind: .freehand,
            points: [
                NormalizedPoint(0.3, 0.3), NormalizedPoint(0.4, 0.4), NormalizedPoint(0.8, 0.4),
                NormalizedPoint(0.8, 0.6), NormalizedPoint(0.4, 0.6), NormalizedPoint(0.5, 0.5),
                NormalizedPoint(0.6, 0.4),
            ])
        var source = CaptureItem.create(sourceImagePath: "source/original.png", pixelWidth: 100, pixelHeight: 100)
        source.annotations = [stroke]

        let result = try CaptureCropper.crop(
            source: source,
            cropBounds: NormalizedRect(0.25, 0.25, 0.5, 0.5),
            croppedSourceImagePath: "source/crop.png",
            croppedPixelWidth: 50,
            croppedPixelHeight: 50)

        let cropped = try XCTUnwrap(result.croppedCapture.annotations.first)
        XCTAssertEqual(1, result.croppedCapture.annotations.count)
        let segments = cropped.getPathSegments()
        XCTAssertEqual(2, segments.count)
        XCTAssertEqual(segments[0], cropped.points)
        XCTAssertNotEqual(segments[0].last, segments[1].first)
        for point in segments.flatMap({ $0 }) {
            XCTAssertGreaterThanOrEqual(point.x, 0)
            XCTAssertLessThanOrEqual(point.x, 1)
            XCTAssertGreaterThanOrEqual(point.y, 0)
            XCTAssertLessThanOrEqual(point.y, 1)
        }
        XCTAssertFalse(result.removedAnnotationIds.contains(stroke.id))
        XCTAssertEqual(result.previousCapture, source)
        XCTAssertTrue(source.annotations[0].pathSegments.isEmpty)
        XCTAssertEqual(stroke.points, source.annotations[0].points)
    }

    func test_Crop_rejects_invalid_bounds_without_mutating_the_source() throws {
        let source = CaptureItem.create(sourceImagePath: "source/original.png", pixelWidth: 100, pixelHeight: 100)

        XCTAssertThrowsError(
            try CaptureCropper.crop(
                source: source,
                cropBounds: NormalizedRect(0.75, 0.75, 0.5, 0.5),
                croppedSourceImagePath: "source/crop.png",
                croppedPixelWidth: 50,
                croppedPixelHeight: 50)
        ) { error in
            guard let snapError = error as? SnapBriefError else {
                return XCTFail("Expected SnapBriefError, got \(error)")
            }
            switch snapError {
            case .argumentOutOfRange:
                break
            default:
                XCTFail("Expected argumentOutOfRange, got \(snapError)")
            }
        }
        XCTAssertEqual("source/original.png", source.sourceImagePath)
        XCTAssertEqual(100, source.pixelWidth)
        XCTAssertEqual(100, source.pixelHeight)
    }

    private func assertPoint(_ actual: NormalizedPoint, _ expectedX: Double, _ expectedY: Double, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(expectedX, actual.x, accuracy: 1e-10, file: file, line: line)
        XCTAssertEqual(expectedY, actual.y, accuracy: 1e-10, file: file, line: line)
    }
}
