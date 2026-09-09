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
    /// (SPEC §3.4) is deleted; nothing is reported back except cancellation.
    func cancelEditing() {
        if let capture, isNewCapture {
            deleteCurrentSourceIfExists(capture)
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
