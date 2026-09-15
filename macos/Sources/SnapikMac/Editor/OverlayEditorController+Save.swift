// Port of `OnSaveImageClick`/`LocalImageSave` (`OverlayEditorWindow.Save.cs:14-43`), SPEC §1.13.
import AppKit
import SnapikCore
import UniformTypeIdentifiers

@MainActor
extension OverlayEditorController {
    /// Port of `OnSaveImageClick` (`Save.cs:14-43`). Cancelling the panel does **not** end the
    /// capture (SPEC §1.13 point 4) — this method only ever calls `showHintError`/
    /// `overlayEditor(_:didSaveFileAt:)`, never `commit`/`close`.
    func saveToFile() {
        guard capture != nil, !busyCrop, !isModalOpen, captureResizeCorner < 0, canvasView?.manipulating != true, let screenIndex = activeScreenIndex else { return }
        // Finding 27: the `NSSavePanel` being on screen is tracked by its own flag, not reused
        // from `busyCrop` (which means "a crop/resize PNG write is in flight" everywhere else).
        isModalOpen = true

        let window = slots[screenIndex].window
        let panel = NSSavePanel()
        panel.title = EditorStrings.saveDialogTitle(language)
        panel.message = EditorStrings.saveDialogTitle(language)
        let isJpeg = settings.saveFormat == "jpeg"
        panel.allowedContentTypes = isJpeg ? [.jpeg] : [.png]
        // SPEC §1.13 point 5: the format actually written is decided by the file's final
        // extension, with an explicit error for anything else — so the panel must allow the user
        // to type/keep an extension outside the current filter.
        panel.allowsOtherFileTypes = true
        panel.nameFieldStringValue = defaultFileName()
        panel.showsHiddenFiles = false
        if FileManager.default.fileExists(atPath: settings.saveDirectory) {
            panel.directoryURL = URL(fileURLWithPath: settings.saveDirectory, isDirectory: true)
        } else if let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first {
            panel.directoryURL = pictures
        }

        // "На время диалога Topmost снимается и восстанавливается после" (SPEC §1.13 point 3):
        // the overlay's `.screenSaver` level would otherwise sit above the save panel.
        let originalLevel = window.level
        window.level = .normal

        panel.begin { [weak self] response in
            guard let self else { return }
            self.isModalOpen = false
            if self.isPresented { window.level = originalLevel }
            guard response == .OK, let url = panel.url else { return }
            self.finishSave(to: url)
        }
    }

    private func finishSave(to url: URL) {
        let extensionLowercased = url.pathExtension.lowercased()
        let format: ImageCodec.Format
        switch extensionLowercased {
        case "png":
            format = .png
        case "jpg", "jpeg":
            format = .jpeg(quality: min(max(settings.jpegQuality, 1), 100))
        default:
            showHintError(EditorStrings.choosePngOrJpeg(language))
            return
        }

        guard let rendered = canvasView?.renderFinalImage() else {
            showHintError(EditorStrings.couldNotSaveCapture(language, "render failed"))
            return
        }
        guard let data = ImageCodec.encode(rendered, format: format) else {
            showHintError(EditorStrings.couldNotSaveCapture(language, "encode failed"))
            return
        }

        do {
            try ImageCodec.writeAtomically(data, to: url)
            rememberCurrentRegionIfNeeded()
            showHintError(EditorStrings.captureSaved(language))
            delegate?.overlayEditor(self, didSaveFileAt: url)
        } catch {
            showHintError("\(error)")
        }
    }

    /// Port of `LocalImageSave.NewPath`'s file-name half (`Snapik-yyyy-MM-dd-HHmmss-fff-XXXX`).
    private func defaultFileName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss-SSS"
        let stamp = formatter.string(from: Date())
        let suffix = SBGuid().digitsLowercase.prefix(4)
        return "Snapik-\(stamp)-\(suffix)"
    }
}
