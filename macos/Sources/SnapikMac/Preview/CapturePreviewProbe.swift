// Port of `CapturePreviewWindow.xaml.cs:314-365` (`RunPreviewProbe`), called from
// `SmokeTestRunner.cs:79` on Windows / `App/SmokeTestRunner.swift` here, SPEC-DELTA-2 §1.5,
// SPEC-DELTA-2B §D/§F.
import CoreGraphics
import Foundation
import SnapikCore

enum CapturePreviewProbeError: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message): return message
        }
    }
}

enum CapturePreviewProbe {
    /// Exercises `PreviewCommentsModel` and `PreviewGeometry` the same way
    /// `CapturePreviewWindow.RunPreviewProbe` does, without opening any window: an empty comment
    /// must show `"+"`; once it has text, its label must match `CaptureLabels`' export numbering;
    /// deleting an earlier numbered comment must close the numbering gap; 300 comments must not
    /// be truncated; and `previewBounds` must stay inside a work area with a negative origin.
    @MainActor
    static func run(image: CGImage) throws {
        var capture = CaptureItem.create(sourceImagePath: "probe.png", pixelWidth: image.width, pixelHeight: image.height)
        let marked = AnnotationItem(
            id: SBGuid(), kind: .rectangle, points: [NormalizedPoint(0.1, 0.1), NormalizedPoint(0.8, 0.8)],
            strokeColor: "#FFFF3B30", thickness: 3, text: "", note: "Первый",
            parentAnnotationId: nil, arrowStyle: "straight")
        let blank = AnnotationItem(
            id: SBGuid(), kind: .comment, points: [NormalizedPoint(0.4, 0.4), NormalizedPoint(0.48, 0.48)],
            strokeColor: "#FF2F8CFF", thickness: 3, text: "", note: "",
            parentAnnotationId: nil, arrowStyle: "straight")
        capture.annotations.append(marked)
        capture.annotations.append(blank)

        let model = PreviewCommentsModel(capture: capture, displayLabel: "A", language: "ru")
        model.rebuild()

        guard let blankEntry = model.entries.first(where: { $0.annotationId == blank.id }) else {
            throw CapturePreviewProbeError.failed("Blank preview comment entry is missing.")
        }
        guard blankEntry.label == "+" else {
            throw CapturePreviewProbeError.failed("An empty preview comment must not claim an export label.")
        }

        model.setText("Второй", for: blankEntry)
        let expectedSecond = CaptureLabels.forNotedAnnotations(captureLabel: "A", capture: model.capture).last?.displayLabel
        guard
            let updatedBlank = model.entries.first(where: { $0.annotationId == blank.id }),
            updatedBlank.label == expectedSecond
        else {
            throw CapturePreviewProbeError.failed("Preview and export comment labels must match.")
        }

        guard let markedEntry = model.entries.first(where: { $0.annotationId == marked.id }) else {
            throw CapturePreviewProbeError.failed("Marked preview comment entry is missing.")
        }
        model.delete(markedEntry)
        let expectedFirst = CaptureLabels.forNotedAnnotations(captureLabel: "A", capture: model.capture).first?.displayLabel
        guard model.entries.count == 1, model.entries[0].label == expectedFirst else {
            throw CapturePreviewProbeError.failed("Comment labels must close the gap after deletion.")
        }

        for index in 0..<299 {
            let extra = AnnotationItem(
                id: SBGuid(), kind: .comment, points: [NormalizedPoint(0.5, 0.5), NormalizedPoint(0.58, 0.58)],
                strokeColor: "#FF2F8CFF", thickness: 3, text: "", note: "Комментарий \(index + 2)",
                parentAnnotationId: nil, arrowStyle: "straight")
            model.capture.annotations.append(extra)
        }
        model.rebuild()
        guard model.entries.count == 300 else {
            throw CapturePreviewProbeError.failed("The preview comment list truncated a large capture.")
        }

        let workArea = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let bounds = PreviewGeometry.previewBounds(workArea: workArea).frame
        guard
            bounds.minX >= workArea.minX, bounds.minY >= workArea.minY,
            bounds.maxX <= workArea.maxX, bounds.maxY <= workArea.maxY
        else {
            throw CapturePreviewProbeError.failed("Preview bounds escaped the stack monitor working area.")
        }
    }
}
