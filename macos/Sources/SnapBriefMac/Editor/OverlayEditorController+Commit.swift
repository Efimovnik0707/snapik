// Port of `Complete`, `OnClosing`/`CancelEdit`, disk persistence half of `OnWindowMouseUp`/
// `OnCropRequested`, SPEC §1.8, §3.4.
import AppKit
import SnapBriefCore

@MainActor
extension OverlayEditorController {
    /// Port of `Complete(bool addNext)` (`OverlayEditorWindow.xaml.cs:719-727`, SPEC §1.8). All
    /// five completion paths (background click, Cmd+C, "Готово", "+ Снимок", repeated hotkey)
    /// funnel through here. `addNext` does **not** reuse these windows for a second capture: a
    /// fresh `DesktopFrame` requires a new screenshot, which only the shell's `ScreenCaptureService`
    /// can take (SPEC §1.2 point 3's "цикл захвата" is owned by `AppCoordinator`, out of this
    /// zone). This controller always tears itself down on commit; `addNext` only changes which
    /// delegate callback(s) fire, so the shell knows to start a brand-new
    /// `OverlayEditorController` right away.
    func commit(addNext: Bool) {
        guard let capture, !busyCrop, !isModalOpen, captureResizeCorner < 0, canvasView?.manipulating != true else { return }

        rememberCurrentRegionIfNeeded()
        if let shotNoteChipView, shotNoteChipView.superview != nil {
            capture.note = shotNoteChipView.note
        }

        // R1 fix: this edit is being kept, so the pre-edit backup (if any) written by
        // `backUpOriginalSourceIfNeeded` is no longer needed.
        deleteOriginalSourceBackupIfNeeded(capture)

        let coreCapture = capture.toCore()
        let coreAnnotations = coreCapture.annotations
        close()
        delegate?.overlayEditor(self, didCommit: coreCapture, annotations: coreAnnotations)
        if addNext {
            delegate?.overlayEditorRequestsNextCapture(self)
        }
    }

    /// Port of `OnWindowKeyDown`'s Escape branch (`:737-742`) + `CancelEdit`/`OnClosing`
    /// (`:768-778`). For a brand-new (never-committed) capture, the one PNG written so far
    /// (SPEC §3.4) is deleted. For a *reopened* capture (finding R1), a crop/resize during this
    /// edit may already have overwritten `source/{captureId}.png` on disk even though nothing was
    /// ever committed; the pre-edit backup written by `backUpOriginalSourceIfNeeded` is restored
    /// here so cancelling truly leaves the capture untouched. Nothing is reported back except
    /// cancellation either way.
    func cancelEditing() {
        if let capture, isNewCapture {
            deleteCurrentSourceIfExists(capture)
        } else if let capture, hasBackedUpOriginalSource {
            restoreOriginalSourceBackup(capture)
        }
        close()
        delegate?.overlayEditorDidCancel(self)
    }

    // MARK: - Disk persistence (SPEC §3.4)

    /// Port of the PNG-write half of `SessionWorkspace.AddImageAsync`/`SaveDerivedImageAsync`.
    /// Every crop/resize during one edit reuses `capture.id`, so `DefaultSessionAssetStore`
    /// (keyed only by `(sessionId, captureId)`) simply overwrites the same file each time — see
    /// the note on `currentSourcePath` in `OverlayEditorController.swift`.
    func persistCurrentSource(_ image: CGImage, completion: @escaping (Result<String, Error>) -> Void) {
        guard let data = ImageCodec.encode(image, format: .png) else {
            completion(.failure(SnapBriefError.invalidData("PNG encoding failed.")))
            return
        }
        guard let captureId = capture?.id else {
            completion(.failure(SnapBriefError.invalidOperation("No capture to save.")))
            return
        }
        // R1 fix: this is about to overwrite `source/{captureId}.png` on disk immediately, ahead
        // of any commit. For a reopened capture (never for a brand-new one — `isNewCapture`
        // already gets a clean delete-on-cancel above), snapshot the pre-edit bytes once, before
        // the very first such overwrite in this edit session.
        if !isNewCapture {
            backUpOriginalSourceIfNeeded(captureId: captureId)
        }
        let sessionId = workspaceContext.session.id
        let store = workspaceContext.assetStore
        Task {
            do {
                let path = try await store.saveOriginalPNG(sessionId: sessionId, captureId: captureId, pngContent: data)
                await MainActor.run {
                    self.capture?.sourceImagePath = path
                    self.currentSourcePath = path
                    completion(.success(path))
                }
            } catch {
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }

    /// Best-effort cleanup for a cancelled brand-new capture (SPEC §1.8 point 3's Windows
    /// counterpart deletes *temporary* sources; here there is at most one file to remove, at
    /// `sessionDirectory/source/{captureId}.png`, matching `DefaultSessionAssetStore`'s layout).
    private func deleteCurrentSourceIfExists(_ capture: EditorCapture) {
        guard currentSourcePath != nil else { return }
        let url = workspaceContext.sessionDirectory.appendingPathComponent("source/\(capture.id.digitsLowercase).png")
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Reopened-capture pre-edit backup (SPEC §1.8 point 3 / §3.4, finding R1)

    /// `DefaultSessionAssetStore.saveOriginalPNG` always writes to this exact path, keyed only by
    /// `(sessionId, captureId)` (see the doc comment on `currentSourcePath` in
    /// `OverlayEditorController.swift`), so it is also the one place a reopened capture's pre-edit
    /// bytes live on disk before the first crop/resize of this edit session overwrites them.
    private func originalSourceURL(captureId: SBGuid) -> URL {
        workspaceContext.sessionDirectory.appendingPathComponent("source/\(captureId.digitsLowercase).png")
    }

    private func originalSourceBackupURL(captureId: SBGuid) -> URL {
        workspaceContext.sessionDirectory.appendingPathComponent("source/\(captureId.digitsLowercase).orig.tmp")
    }

    /// Snapshots the pre-edit PNG once per edit session, before `persistCurrentSource`'s first
    /// overwrite for a *reopened* capture. A no-op for a brand-new capture (`isNewCapture`, guarded
    /// by the caller) and for every crop/resize after the first in this session.
    private func backUpOriginalSourceIfNeeded(captureId: SBGuid) {
        guard !hasBackedUpOriginalSource else { return }
        hasBackedUpOriginalSource = true
        let source = originalSourceURL(captureId: captureId)
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        let backup = originalSourceBackupURL(captureId: captureId)
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.copyItem(at: source, to: backup)
    }

    /// Port of `CancelEdit`'s "leave the file untouched" guarantee for a *reopened* capture: undoes
    /// `persistCurrentSource`'s immediate on-disk overwrite by atomically swapping the pre-edit
    /// backup back into place.
    private func restoreOriginalSourceBackup(_ capture: EditorCapture) {
        let backup = originalSourceBackupURL(captureId: capture.id)
        guard FileManager.default.fileExists(atPath: backup.path) else { return }
        let destination = originalSourceURL(captureId: capture.id)
        do {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: backup)
        } catch {
            try? FileManager.default.removeItem(at: backup)
        }
        hasBackedUpOriginalSource = false
    }

    /// This edit is being kept (commit), so the pre-edit backup — if `persistCurrentSource` ever
    /// wrote one — is discarded rather than left behind on disk.
    private func deleteOriginalSourceBackupIfNeeded(_ capture: EditorCapture) {
        guard hasBackedUpOriginalSource else { return }
        try? FileManager.default.removeItem(at: originalSourceBackupURL(captureId: capture.id))
        hasBackedUpOriginalSource = false
    }

    // MARK: - Errors (SPEC §1.2 step 8 error text, §1.6 step 6, §1.13 point 10)

    /// Reuses the hint chip for error text, matching the Windows source's own reuse of
    /// `Hint.Child.Text` for both the selection prompt and error messages.
    func showHintError(_ message: String) {
        guard let screenIndex = activeScreenIndex ?? selectionScreenIndex ?? slots.indices.first else { return }
        let hint = slots[screenIndex].contentView.hintView
        hint.text = message
        hint.isHidden = false
    }
}
