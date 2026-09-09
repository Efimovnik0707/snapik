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
    /// SPEC-DELTA-2A §3.1: `pngItem(for:)` includes a `.fileURL` type in the same item as
    /// `.png`/`.tiff` by default. Risk 5 ("Terminal.app по Cmd+V с `.fileURL` может вставить путь
    /// текстом"): set `false` to fall back to PNG/TIFF-only image items.
    private let pngItemIncludesFileURL: Bool

    /// `pasteboard` defaults to `.general`; tests inject a private named pasteboard
    /// (`NSPasteboard(name: .init("snapbrief-test"))`) so they never touch the real system
    /// clipboard. `queue` defaults to `.main` per CONTRACTS.md ("операции на главной очереди").
    public init(pasteboard: NSPasteboard = .general, queue: DispatchQueue = .main, pngItemIncludesFileURL: Bool = true) {
        self.pasteboard = pasteboard
        self.queue = queue
        self.pngItemIncludesFileURL = pngItemIncludesFileURL
    }

    public func capture(_ completion: @escaping (ClipboardSnapshot) -> Void) {
        queue.async { completion(self.captureCore()) }
    }

    /// Port of `SetPngGuardedAsync`'s package-writing counterpart. SPEC-DELTA-2A §3.1: a
    /// single-image package writes one combined `.png`/`.tiff`/`.fileURL` item (via `pngItem`)
    /// exactly like `setPNGGuarded`; a multi-image package (the "as-is" fallback, sent as-is to
    /// whatever the user pastes into rather than staged one at a time) keeps one plain
    /// `.fileURL` item per path — there is no single clipboard item that can hold more than one
    /// image's raw bytes.
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
                var items: [NSPasteboardItem] = []
                if paths.count == 1, let single = self.pngItem(for: paths[0]) {
                    items.append(single)
                } else {
                    items.append(contentsOf: paths.map { Self.fileURLItem(for: $0) })
                }
                items.append(Self.textItem(text))
                self.pasteboard.writeObjects(items)
                completion(.success(self.captureCore()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    /// SPEC-DELTA-2A §3.1: one `NSPasteboardItem` with `.png`, `.tiff`, `.fileURL` (in this order)
    /// so a receiver picks the best type from within a single item, instead of the previous
    /// two-item shape (a bare `.fileURL` item plus a separate `.png`/`.tiff` item) that Chromium/
    /// Electron receivers (Claude Desktop) and `pngpaste`/Claude Code could not see an image in.
    public func setPNGGuarded(
        path: String,
        expectedSequence: Int?,
        completion: @escaping (Result<ClipboardSnapshot, Error>) -> Void
    ) {
        queue.async {
            do {
                try self.requireCurrent(expectedSequence)
                guard let item = self.pngItem(for: path) else {
                    throw TransportError.other("Could not read image data at \(path).")
                }
                self.pasteboard.clearContents()
                self.pasteboard.writeObjects([item])
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
        // LOW-2: without `.urlReadingFileURLsOnly`, `readObjects` also resolves plain-text/HTTP(S)
        // URLs elsewhere on the pasteboard into `NSURL`s, which could leak into `filePaths`.
        let filePaths = (
            pasteboard.readObjects(
                forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        )?.compactMap { $0.isFileURL ? $0.path : nil } ?? []
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
    /// (TIFF here, the macOS "universal raster format", SPEC §5.1), plus the `.fileURL` (SPEC-
    /// DELTA-2A §3.1) so receivers that only accept attachments still get the file, all inside one
    /// `NSPasteboardItem`.
    private func pngItem(for path: String) -> NSPasteboardItem? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        let item = NSPasteboardItem()
        item.setData(data, forType: .png)
        if let image = NSImage(data: data), let tiff = image.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        if pngItemIncludesFileURL {
            let url = URL(fileURLWithPath: path)
            item.setString(url.absoluteString, forType: .fileURL)
        }
        return item
    }

    /// SPEC-DELTA-2A CONTRACTS.md sync 2 addendum: the raw list of pasteboard types currently
    /// present, for the "Clipboard diagnostics: … formats=[…]" log line (SPEC-DELTA-2A §6).
    /// `internal` (not `public`): only used from `AppCoordinator+PasteIntent.swift`, same module.
    func diagnosticTypes() -> [String] {
        pasteboard.pasteboardItems?.flatMap { $0.types.map(\.rawValue) } ?? []
    }
}
