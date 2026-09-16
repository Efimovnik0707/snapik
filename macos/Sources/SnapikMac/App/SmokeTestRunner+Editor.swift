// The probes of the editor added by sync 3 (SPEC-DELTA-3 §1.7 K-2, §7 "волна 1"). They live in a
// file of their own so the three parallel portions of wave 1 never touch the same lines of
// `SmokeTestRunner.swift`; wave 2 (W2-1) folds `editorProbes` into `SmokeTestRunner.run` and gives
// the results their exit codes.
import AppKit
import SnapikCore

extension SmokeTestRunner {
    /// One named result per probe, in the order they are run. Named apart from the existing private
    /// `EditorProbeResult` of `SmokeTestRunner.swift`, which is a different thing: a bag of flags for
    /// one controller run, not a row of the report.
    struct EditorSyncProbeResult {
        let name: String
        let passed: Bool
    }

    /// Runs every sync-3 editor probe against a controller that is already in markup mode (a capture
    /// selected, the panel built). Returns one row per probe so the caller can report them by name.
    @MainActor
    static func editorProbes(on controller: OverlayEditorController) -> [EditorSyncProbeResult] {
        [
            EditorSyncProbeResult(name: "editor: one active colour for every tool", passed: controller.smokeVerifyOneActiveColor()),
            EditorSyncProbeResult(name: "editor: the spectrum and the eyedropper come with every palette", passed: controller.smokeVerifyPalettes()),
            EditorSyncProbeResult(name: "editor: the comment tool grabs what is already there", passed: controller.smokeVerifyCommentGrab()),
            EditorSyncProbeResult(name: "editor: the pattern of a stroke survives a copy and the export", passed: controller.smokeVerifyLineStyleRoundTrip()),
            EditorSyncProbeResult(name: "editor: a region filled with blur reuses the cached frame", passed: controller.smokeVerifyBlurCache()),
            EditorSyncProbeResult(name: "editor: a caption owns the box its letters take", passed: controller.smokeVerifyCaptionSize()),
            EditorSyncProbeResult(name: "editor: the panel keeps its width and wraps when it must", passed: controller.smokeVerifyToolbarLayout()),
        ]
    }

    /// The probes that need no controller behind them: the spectrum and the two hit-test rules of the
    /// canvas (SPEC-DELTA-3 §1.4 E-9, E-13, E-17).
    @MainActor
    static func editorProbesWithoutController(probeImage: CGImage) -> [EditorSyncProbeResult] {
        [
            EditorSyncProbeResult(name: "editor: the spectrum answers the strip and the square", passed: ColorSpectrumView.smokeVerifySpectrum()),
            EditorSyncProbeResult(name: "editor: hover manipulation and the comment tool", passed: AnnotationCanvasView.smokeVerifyHoverManipulation(image: probeImage)),
        ]
    }
}
