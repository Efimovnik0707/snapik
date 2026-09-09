// Port of Windows/WindowsClipboardService.cs, SPEC §5.1, §1.10, CONTRACTS.md "Transport
// (exec-transport)" Mac section.
//
// `NSPasteboard.changeCount` is the direct analogue of `GetClipboardSequenceNumber()`. Windows
// needs a dedicated STA thread (`StaWorkQueue`) because OLE requires it; `NSPasteboard` has no
// apartment requirement, so CONTRACTS.md has all operations run "на главной очереди" (on the main
// queue) instead — no separate worker thread.
//
// Formats written (CONTRACTS.md, SPEC §5.1, §9.14 row 10):
// - every file path: `public.file-url` (`NSPasteboard.PasteboardType.fileURL`), one pasteboard
//   item per path;
// - the prompt text: `public.utf8-plain-text` (`NSPasteboard.PasteboardType.string`), its own item;
// - a single-snapshot package additionally gets a PNG item under `NSPasteboard.PasteboardType.png`
//   (raw PNG bytes) and `.tiff` (`NSImage.tiffRepresentation`), the "universal raster format"
//   analogue of Windows' `CF_DIB` (SPEC §5.1: "аналога CF_DIB не нужно").
//
// Guarded writes compare `changeCount` before writing (no atomicity guarantee on either platform,
// SPEC §5.1: "Атомарности нет ни там, ни там — это best-effort").

import AppKit
import SnapBriefCore

public final class MacClipboardService: ClipboardServicing {
    private let pasteboard: NSPasteboard
    private let queue: DispatchQueue

    /// `pasteboard` defaults to `.general`; tests inject a private named pasteboard
    /// (`NSPasteboard(name: .init("snapbrief-test"))`) so they never touch the real system
    /// clipboard. `queue` defaults to `.main` per CONTRACTS.md ("операции на главной очереди").
    public init(pasteboard: NSPasteboard = .general, queue: DispatchQueue = .main) {
        self.pasteboard = pasteboard
        self.queue = queue
    }

    public func capture(_ completion: @escaping (ClipboardSnapshot) -> Void) {
        queue.async { completion(self.captureCore()) }
    }

    public func setPackageGuarded(
        paths: [String],
        text: String,
        expectedSequence: Int?,
        completion: @escaping (Result<ClipboardSnapshot, Error>) -> Void
    ) {
        queue.async {
            do {
                try self.requireCurrent(expectedSequence)
                self.pasteboard.clearContents()
                var items = paths.map { Self.fileURLItem(for: $0) }
                items.append(Self.textItem(text))
                if paths.count == 1, let imageItem = Self.imageItem(for: paths[0]) {
                    items.append(imageItem)
                }
                self.pasteboard.writeObjects(items)
                completion(.success(self.captureCore()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    public func setPNGGuarded(
        path: String,
        expectedSequence: Int?,
        completion: @escaping (Result<ClipboardSnapshot, Error>) -> Void
    ) {
        queue.async {
            do {
                try self.requireCurrent(expectedSequence)
                self.pasteboard.clearContents()
                var items = [Self.fileURLItem(for: path)]
                if let imageItem = Self.imageItem(for: path) {
                    items.append(imageItem)
                }
                self.pasteboard.writeObjects(items)
                completion(.success(self.captureCore()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    public func setTextGuarded(
        text: String,
        expectedSequence: Int?,
        completion: @escaping (Result<ClipboardSnapshot, Error>) -> Void
    ) {
        queue.async {
            do {
                try self.requireCurrent(expectedSequence)
                self.pasteboard.clearContents()
                self.pasteboard.writeObjects([Self.textItem(text)])
                completion(.success(self.captureCore()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    // MARK: - Internal helpers (called on `queue`)

    private func requireCurrent(_ expectedSequence: Int?) throws {
        guard let expectedSequence else { return }
        if pasteboard.changeCount != expectedSequence {
            throw TransportError.clipboardChangedDefault
        }
    }

    /// Port of `CaptureCore` (`Windows/WindowsClipboardService.cs:68-94`), reduced to the shape
    /// `ClipboardSnapshot` needs. `NSPasteboard` reads are not retried the way OLE reads are on
    /// Windows: pasteboard reads are local snapshots of already-published data, not subject to
    /// the same "another app is mid-write" race the Windows OLE clipboard has.
    private func captureCore() -> ClipboardSnapshot {
        let sequence = pasteboard.changeCount
        let text = pasteboard.string(forType: .string)
        let filePaths = (pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL])?
            .compactMap { $0.isFileURL ? $0.path : nil } ?? []
        let hasImage = pasteboard.canReadItem(withDataConformingToTypes: [
            NSPasteboard.PasteboardType.png.rawValue, NSPasteboard.PasteboardType.tiff.rawValue,
        ])
        return ClipboardSnapshot(
            sequence: sequence, hasText: text != nil, text: text, filePaths: filePaths, hasImage: hasImage)
    }

    private static func fileURLItem(for path: String) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        let url = URL(fileURLWithPath: path)
        item.setString(url.absoluteString, forType: .fileURL)
        return item
    }

    private static func textItem(_ text: String) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        return item
    }

    /// Port of the PNG/DIB/Bitmap trio `CreatePngDataObject` writes for a single image
    /// (`Windows/WindowsClipboardService.cs:187-196`): raw PNG bytes plus a bitmap representation
    /// (TIFF here, the macOS "universal raster format", SPEC §5.1).
    private static func imageItem(for path: String) -> NSPasteboardItem? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        let item = NSPasteboardItem()
        item.setData(data, forType: .png)
        if let image = NSImage(data: data), let tiff = image.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        return item
    }
}
