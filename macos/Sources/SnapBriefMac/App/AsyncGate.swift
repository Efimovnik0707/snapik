// Port of the `SemaphoreSlim(1, 1)` used as `_clipboardPublicationGate` in
// `EdgeStackWindow.xaml.cs`, SPEC-DELTA-2A §4. Swift has no async-aware semaphore in Foundation
// (`DispatchSemaphore.wait()` blocks a thread, which would freeze the run loop under `await`), so
// this reimplements the same "at most one holder, FIFO waiters" contract with a continuation
// queue instead.
import Foundation

/// `@MainActor` because every caller (`AppCoordinator+PasteIntent.swift`) is already
/// `@MainActor`-isolated; `wait()`/`release()` are therefore never called concurrently with each
/// other, which is what makes the plain `isBusy` flag + FIFO array below correct without any
/// additional locking.
@MainActor
final class AsyncGate {
    private(set) var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init() {}

    /// Port of `SemaphoreSlim.WaitAsync()`. Resumes immediately if the gate is free; otherwise
    /// queues the caller and resumes it (still holding the gate) once every earlier holder has
    /// called `release()`.
    func wait() async {
        if !isBusy {
            isBusy = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    /// Port of `SemaphoreSlim.Release()`. Hands the gate straight to the next queued waiter (still
    /// `isBusy == true`) if one exists, otherwise frees it.
    func release() {
        guard isBusy else { return }
        if waiters.isEmpty {
            isBusy = false
        } else {
            let next = waiters.removeFirst()
            next.resume()
        }
    }
}
