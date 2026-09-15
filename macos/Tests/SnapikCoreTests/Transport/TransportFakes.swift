// Shared fakes for the sequential/Codex paste-completion tests (SPEC-DELTA-2A §2, §7). Extracted
// out of `CodexDesktopPasteCompletionServiceTests.swift` per SPEC-DELTA-2A §2 so
// `SequentialPasteCompletionServiceTests.swift` can reuse the same clipboard/target/input doubles.

import Foundation
@testable import SnapikCore

/// Port of the Windows `FakeClipboard`: a guarded in-memory clipboard that tracks every write as
/// a short descriptive string (`"PACKAGE:a,b"` / a bare image path / `"TEXT"`), so tests can assert
/// dispatch order without inspecting `NSPasteboard`.
final class FakeClipboard: ClipboardServicing {
    private(set) var sequence: Int
    private(set) var writes: [String] = []
    private(set) var writtenText: String?
    /// If set, the *next* guarded write fails with `TransportError.clipboardChangedDefault`
    /// regardless of `expectedSequence`, then resets itself.
    var failNextWrite = false
    /// If set, every successful `setTextGuarded` bumps `sequence` a second time right after
    /// building its success receipt, simulating another app changing the clipboard immediately
    /// after Snapik's own write settles (the receipt itself still reflects the write).
    var changeAfterWrite = false
    var beforeCapture: (() -> Void)?

    init(sequence: Int) {
        self.sequence = sequence
    }

    func capture(_ completion: @escaping (ClipboardSnapshot) -> Void) {
        beforeCapture?()
        completion(ClipboardSnapshot(sequence: sequence, hasText: false, text: nil, filePaths: [], hasImage: false))
    }

    func setPackageGuarded(
        paths: [String], text: String, expectedSequence: Int?,
        completion: @escaping (Result<ClipboardSnapshot, Error>) -> Void
    ) {
        guard write(guardedBy: expectedSequence) else {
            completion(.failure(TransportError.clipboardChangedDefault))
            return
        }
        writes.append("PACKAGE:\(paths.joined(separator: ","))")
        writtenText = text
        completion(.success(
            ClipboardSnapshot(sequence: sequence, hasText: true, text: text, filePaths: paths, hasImage: !paths.isEmpty)))
    }

    func setPNGGuarded(
        path: String, expectedSequence: Int?, completion: @escaping (Result<ClipboardSnapshot, Error>) -> Void
    ) {
        guard write(guardedBy: expectedSequence) else {
            completion(.failure(TransportError.clipboardChangedDefault))
            return
        }
        writes.append(path)
        writtenText = nil
        completion(.success(
            ClipboardSnapshot(sequence: sequence, hasText: false, text: nil, filePaths: [path], hasImage: true)))
    }

    func setTextGuarded(
        text: String, expectedSequence: Int?, completion: @escaping (Result<ClipboardSnapshot, Error>) -> Void
    ) {
        guard write(guardedBy: expectedSequence) else {
            completion(.failure(TransportError.clipboardChangedDefault))
            return
        }
        writes.append("TEXT")
        writtenText = text
        let receiptSequence = sequence
        if changeAfterWrite { sequence += 1 }
        completion(.success(ClipboardSnapshot(sequence: receiptSequence, hasText: true, text: text, filePaths: [], hasImage: false)))
    }

    /// Port of `FakeClipboard.ExternalWrite`: simulates another app changing the clipboard.
    func externalWrite() {
        sequence += 1
        writtenText = nil
    }

    private func write(guardedBy expectedSequence: Int?) -> Bool {
        if failNextWrite {
            failNextWrite = false
            return false
        }
        guard expectedSequence == nil || expectedSequence == sequence else { return false }
        sequence += 1
        return true
    }
}

/// Reusable `ForegroundTargetServicing` double: returns `current`, optionally running a side
/// effect first (used to simulate a focus change happening exactly while
/// `MacInputInjector`/`GuardedInputInjecting` is waiting on its guard).
final class FakeTarget: ForegroundTargetServicing {
    var current: ForegroundTarget?
    var beforeCurrentTarget: (() -> Void)?

    init(_ current: ForegroundTarget?) {
        self.current = current
    }

    func currentTarget() -> ForegroundTarget? {
        beforeCurrentTarget?()
        return current
    }
}

/// Port of the Windows `FakeInput`: records every gesture actually dispatched (i.e. that passed
/// `finalGuard`), and exposes `beforeFinalGuard`/`afterDispatch` hooks so tests can inject a focus
/// or clipboard change exactly at those points (SPEC-DELTA-2A §7: "FakeInput.afterDispatch").
final class FakeGuardedInput: GuardedInputInjecting {
    private(set) var gestures: [PasteIntentGesture] = []
    var beforeFinalGuard: (() -> Void)?
    var afterDispatch: (() -> Void)?

    func injectPaste(gesture: PasteIntentGesture, completion: @escaping (Bool) -> Void) {
        gestures.append(gesture)
        completion(true)
    }

    func injectPasteGuarded(
        gesture: PasteIntentGesture, finalGuard: @escaping (@escaping (Bool) -> Void) -> Void,
        completion: @escaping (Bool) -> Void
    ) {
        beforeFinalGuard?()
        finalGuard { [weak self] allowed in
            guard allowed else {
                completion(false)
                return
            }
            self?.gestures.append(gesture)
            self?.afterDispatch?()
            completion(true)
        }
    }
}
