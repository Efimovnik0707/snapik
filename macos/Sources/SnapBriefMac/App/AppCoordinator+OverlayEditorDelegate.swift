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

        // R5 fix: `editor` was built against a specific session (`workspaceContext.session.id`,
        // frozen at `beginOverlayCapture`/`openCapture` time). If a paste-intent-driven
        // `startNewSession()` rotated the session while this edit was still open, `committed`'s
        // `sourceImagePath` and index belong to the *old* session, not the current one — folding
        // it in here would silently corrupt the new session instead.
        guard editor.workspaceContext.session.id == workspace.session.id else {
            captureSeriesPreviousApp = nil
            stackWindow?.setStatus(StatusStrings.couldNotSave("сессия изменилась"), isError: true)
            stackWindow?.reveal()
            return
        }

        // R8 fix: `overlayEditorRequestsNextCapture` (if it's coming at all for this commit) is
        // called synchronously right after this method returns, from the same
        // `OverlayEditorController.commit(addNext:)` call. Deferring the check by one turn lets
        // that synchronous call set `nextCaptureRequested` first, telling "+ Снимок" (chain
        // continues, keep `captureSeriesPreviousApp`) apart from "Готово" (chain ends here) without
        // threading `addNext` through the `OverlayEditorDelegate` protocol.
        nextCaptureRequested = false
        Task { @MainActor [weak self] in
            guard let self, !self.nextCaptureRequested else { return }
            self.captureSeriesPreviousApp = nil
        }

        pendingCommitTask = Task { @MainActor in
            do {
                let isNewCapture = !self.workspace.session.captures.contains(where: { $0.id == committed.id })
                if isNewCapture {
                    try self.workspace.appendCapture(committed)
                } else {
                    try self.workspace.replaceCapture(committed)
                    // R2 fix: `replaceCapture` reuses the same `captureId`, so the stack's
                    // thumbnail cache (keyed only on that id) must be dropped or `refresh()` right
                    // below would keep showing the pre-edit bitmap.
                    self.stackWindow?.invalidateThumbnail(for: committed.id)
                }
                self.stackWindow?.refresh()
                let succeeded = await self.saveAndCopyCommittedPackage()
                // SPEC-DELTA-2B §E2/§E3: capture-shutter feedback + optional auto-save, only for a
                // brand-new capture (not a re-edit of an existing one), right after the package is
                // copied to the clipboard.
                if isNewCapture {
                    CaptureFeedbackSound.capture(enabled: self.settings.playSounds)
                    await self.autoSave(committed)
                }
                self.stackWindow?.reveal()
                // R3 fix: only non-nil while this fold-in is actually in flight, so
                // `AppCoordinator.handleHotkey`'s reentrancy guard reliably reflects that.
                self.pendingCommitTask = nil
                return succeeded
            } catch {
                self.stackWindow?.setStatus(StatusStrings.captureNotCompleted("\(error)"), isError: true)
                self.stackWindow?.reveal()
                self.pendingCommitTask = nil
                return false
            }
        }
    }

    /// Port of Esc-before-selection (`:107`): session unchanged, overlay closes.
    func overlayEditorDidCancel(_ editor: OverlayEditorController) {
        if editor === overlay { overlay = nil }
        // R8 fix: cancelling always ends the "+ Снимок" chain (there is no "cancel, but keep
        // going" path), so the remembered pre-chain frontmost app is forgotten here.
        captureSeriesPreviousApp = nil
        stackWindow?.reveal()
    }

    /// Port of the "commit current and start next capture" branch of `handleGlobalHotkey`
    /// (SPEC §1.2 point 2): the previous overlay has already committed via `didCommit`; wait for
    /// that commit's save-and-copy to actually finish, and only start the next capture if it
    /// succeeded (finding 5).
    func overlayEditorRequestsNextCapture(_ editor: OverlayEditorController) {
        // R8 fix: must be set synchronously, before this method returns — see the doc comment on
        // `overlayEditor(_:didCommit:)`'s deferred check above.
        nextCaptureRequested = true
        if editor === overlay { overlay = nil }
        Task { @MainActor in
            let succeeded = await self.pendingCommitTask?.value ?? false
            guard succeeded else {
                self.captureSeriesPreviousApp = nil
                return
            }
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

    /// Port of `AutoSaveCaptureAsync` (SPEC-DELTA-2.md §1.8, SPEC-DELTA-2B.md §E3): renders and
    /// writes the just-committed capture to the user's save folder when "Автоматически сохранять
    /// готовые снимки" is on. Never interrupts the capture flow — a failure only sets status text.
    private func autoSave(_ capture: CaptureItem) async {
        guard settings.autoSaveCaptures else { return }
        let index = workspace.session.captures.firstIndex(where: { $0.id == capture.id }) ?? 0
        let displayLabel = (try? CaptureLabels.forIndex(index)) ?? "A"
        do {
            _ = try AutoSaveService.save(
                capture: capture, displayLabel: displayLabel, sessionDirectory: workspace.sessionDirectory,
                settings: settings)
            if settings.showNotifications { notificationService.notify("Снимок сохранён", language: language) }
        } catch {
            stackWindow?.setStatus(
                "\(MacUiText.text("Автосохранение не выполнено", language: language)): \(error)", isError: true)
        }
    }
}
