// Port of `CapturePreviewWindow.xaml.cs:314-365` (`RunPreviewProbe`), coverage for
// `PreviewCommentsModel`, SPEC-DELTA-2 §1.5, SPEC-DELTA-2B §D/§F.
import AppKit
import CoreGraphics
import XCTest

@testable import SnapBriefCore
@testable import SnapBriefMac

@MainActor
final class PreviewModelTests: XCTestCase {
    private func makeCapture(width: Int = 200, height: Int = 100) -> CaptureItem {
        CaptureItem.create(sourceImagePath: "probe.png", pixelWidth: width, pixelHeight: height)
    }

    func test_addComment_startsEmptyWithPlusLabel() {
        let model = PreviewCommentsModel(capture: makeCapture(), displayLabel: "A", language: "ru")
        let entry = model.addComment()

        XCTAssertEqual(entry.label, "+")
        XCTAssertEqual(entry.text, "")
        XCTAssertNotNil(entry.annotationId)
    }

    func test_setText_assignsExportLabelMatchingCaptureLabels() {
        let model = PreviewCommentsModel(capture: makeCapture(), displayLabel: "A", language: "ru")
        let entry = model.addComment()
        model.setText("Второй", for: entry)

        let expected = CaptureLabels.forNotedAnnotations(captureLabel: "A", capture: model.capture).last?.displayLabel
        let updated = model.entries.first(where: { $0.id == entry.id })
        XCTAssertEqual(updated?.label, expected)
    }

    func test_delete_closesTheNumberingGap() {
        let model = PreviewCommentsModel(capture: makeCapture(), displayLabel: "A", language: "ru")
        let first = model.addComment()
        model.setText("Первый", for: first)
        let second = model.addComment()
        model.setText("Второй", for: second)

        model.delete(model.entries[0])

        XCTAssertEqual(model.entries.count, 1)
        let expected = CaptureLabels.forNotedAnnotations(captureLabel: "A", capture: model.capture).first?.displayLabel
        XCTAssertEqual(model.entries[0].label, expected)
        XCTAssertEqual(model.entries[0].text, "Второй")
    }

    func test_rebuild_doesNotTruncateThreeHundredComments() {
        let model = PreviewCommentsModel(capture: makeCapture(), displayLabel: "A", language: "ru")
        for index in 0..<300 {
            let entry = model.addComment()
            model.setText("Комментарий \(index + 1)", for: entry)
        }

        XCTAssertEqual(model.entries.count, 300)
        model.rebuild()
        XCTAssertEqual(model.entries.count, 300)
    }

    func test_capturePreviewProbe_runsEndToEnd() throws {
        let image = try XCTUnwrap(makeImage(width: 40, height: 30))
        try CapturePreviewProbe.run(image: image)
    }

    private func makeImage(width: Int, height: Int) -> CGImage? {
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
