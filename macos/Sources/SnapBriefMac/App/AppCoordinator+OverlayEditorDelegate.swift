// Port of the overlay-commit handling in `CaptureLoopAsync`/`OnOpenCaptureClick`
// (`EdgeStackWindow.xaml.cs:234-261, 287-309`), SPEC §1.2, §1.9.
import Foundation
import SnapBriefCore

extension AppCoordinator: OverlayEditorDelegate {
    /// The capture's source PNG is already saved to disk by the editor (CONTRACTS.md "Editor":
    /// "снимок уже сохранён на диск через SessionAssetStore"); this only needs to fold it into
    /// the session — as a replacement if it is an existing capture being re-edited, or a new
    /// entry otherwise — persist, refresh the clipboard package, and let the stack UI refresh.
    ///
    /// Finding 5/21: the fold-in + save-and-copy runs as a tracked `Task` (`pendingCommitTask`)
    /// instead of a fire-and-forget one, so `overlayEditorRequestsNextCapture` can await its
    /// result — both to know whether copying actually succeeded before starting the next capture
    /// (SPEC §1.8 step 5: "если копирование прошло и был запрошен следующий снимок"), and so the
    /// next capture's `nextCaptureIndex` is only computed after this capture is actually appended.
    /// The stack is revealed here in every case (SPEC §1.8 step 6: "в любом случае стопка
    /// показывается без активации") — if a next capture follows, `beginOverlayCapture` hides it
    /// again before the new overlay appears, matching the observed Windows behavior.
    func overlayEditor(_ editor: OverlayEditorController, didCommit capture: CaptureItem, annotations: [AnnotationItem]) {
        var committed = capture
        committed.annotations = annotations

        if editor === overlay { overlay = nil }

        pendingCommitTask = Task { @MainActor in
            do {
                if self.workspace.session.captures.contains(where: { $0.id == committed.id }) {
                    try self.workspace.replaceCapture(committed)
                } else {
                    try self.workspace.appendCapture(committed)
                }
                self.stackWindow?.refresh()
                let succeeded = await self.saveAndCopyCommittedPackage()
                self.stackWindow?.reveal()
                return succeeded
            } catch {
                self.stackWindow?.setStatus(StatusStrings.captureNotCompleted("\(error)"), isError: true)
                self.stackWindow?.reveal()
                return false
            }
        }
    }

    /// Port of Esc-before-selection (`:107`): session unchanged, overlay closes.
    func overlayEditorDidCancel(_ editor: OverlayEditorController) {
        if editor === overlay { overlay = nil }
        stackWindow?.reveal()
    }

    /// Port of the "commit current and start next capture" branch of `handleGlobalHotkey`
    /// (SPEC §1.2 point 2): the previous overlay has already committed via `didCommit`; wait for
    /// that commit's save-and-copy to actually finish, and only start the next capture if it
    /// succeeded (finding 5).
    func overlayEditorRequestsNextCapture(_ editor: OverlayEditorController) {
        if editor === overlay { overlay = nil }
        Task { @MainActor in
            let succeeded = await self.pendingCommitTask?.value ?? false
            guard succeeded else { return }
            await self.beginOverlayCapture()
        }
    }

    /// Port of the "Сохранить на компьютер" notification (SPEC §1.15).
    func overlayEditor(_ editor: OverlayEditorController, didSaveFileAt url: URL) {
        // Finding 4: the "Уведомления о копировании и сохранении" setting was only read by the
        // settings UI, never actually gating a notification.
        guard settings.showNotifications else { return }
        notificationService.notify("Снимок сохранён", language: language)
    }
}
