// Port of the overlay-commit handling in `CaptureLoopAsync`/`OnOpenCaptureClick`
// (`EdgeStackWindow.xaml.cs:234-261, 287-309`), SPEC §1.2, §1.9.
import Foundation
import SnapBriefCore

extension AppCoordinator: OverlayEditorDelegate {
    /// The capture's source PNG is already saved to disk by the editor (CONTRACTS.md "Editor":
    /// "снимок уже сохранён на диск через SessionAssetStore"); this only needs to fold it into
    /// the session — as a replacement if it is an existing capture being re-edited, or a new
    /// entry otherwise — persist, refresh the clipboard package, and let the stack UI refresh.
    func overlayEditor(_ editor: OverlayEditorController, didCommit capture: CaptureItem, annotations: [AnnotationItem]) {
        var committed = capture
        committed.annotations = annotations

        if editor === overlay { overlay = nil }

        Task {
            do {
                if self.workspace.session.captures.contains(where: { $0.id == committed.id }) {
                    try self.workspace.replaceCapture(committed)
                } else {
                    try self.workspace.appendCapture(committed)
                }
                self.stackWindow?.refresh()
                _ = await self.saveAndCopyCommittedPackage()
            } catch {
                self.stackWindow?.setStatus(StatusStrings.captureNotCompleted("\(error)"), isError: true)
            }
        }
    }

    /// Port of Esc-before-selection (`:107`): session unchanged, overlay closes.
    func overlayEditorDidCancel(_ editor: OverlayEditorController) {
        if editor === overlay { overlay = nil }
        stackWindow?.reveal()
    }

    /// Port of the "commit current and start next capture" branch of `handleGlobalHotkey`
    /// (SPEC §1.2 point 2): the previous overlay has already committed via `didCommit`; take a
    /// fresh desktop frame and present a new overlay for the next region.
    func overlayEditorRequestsNextCapture(_ editor: OverlayEditorController) {
        if editor === overlay { overlay = nil }
        Task { await self.beginOverlayCapture() }
    }

    /// Port of the "Сохранить на компьютер" notification (SPEC §1.15).
    func overlayEditor(_ editor: OverlayEditorController, didSaveFileAt url: URL) {
        notificationService.notify("Снимок сохранён", language: language)
    }
}
