// Port of Windows/TransportContracts.cs, SPEC §5.1-§5.8, CONTRACTS.md "Transport (exec-transport)".
//
// The Windows contracts are expressed as async/await `Task<T>` APIs guarded by a shared
// `CancellationToken`. This module avoids Swift concurrency (no actors/async/Sendable per
// CONTRACTS.md), so every asynchronous Windows method becomes a completion-handler method here,
// and `CancellationToken` becomes the injectable `PasteCancellationToken` below. Timers use the
// injectable `TransportScheduler` protocol (CONTRACTS.md: "инъецируемый Clock-протокол для
// тестов, предпочтительно инъецируемый scheduler").
//
// `ClipboardWriteReceipt` has no separate type on macOS: `ClipboardServicing.setXGuarded`
// resolves with the post-write `ClipboardSnapshot` itself, whose `sequence` plays the role of the
// Windows receipt (`NSPasteboard.changeCount`, SPEC §5.1).

import Foundation

// MARK: - Cancellation

/// Port of .NET `CancellationToken`/`CancellationTokenSource`, reduced to the single flag the
/// Transport layer needs. Checked synchronously at the same points the Windows code calls
/// `cancellationToken.ThrowIfCancellationRequested()`.
public final class PasteCancellationToken {
    public init() {}
    public private(set) var isCancelled = false
    public func cancel() { isCancelled = true }
}

// MARK: - Scheduling

/// A pending scheduled work item that can be cancelled before it fires.
public protocol TransportCancellable: AnyObject {
    func cancel()
}

/// Port of the injectable clock/timer abstraction CONTRACTS.md asks for. Production code uses
/// `DispatchQueueScheduler`; tests inject fakes for deterministic timing.
public protocol TransportScheduler: AnyObject {
    @discardableResult
    func schedule(after seconds: TimeInterval, _ work: @escaping () -> Void) -> TransportCancellable
}

/// Default scheduler backed by `DispatchQueue.asyncAfter`.
public final class DispatchQueueScheduler: TransportScheduler {
    private let queue: DispatchQueue

    public init(queue: DispatchQueue = .main) {
        self.queue = queue
    }

    public func schedule(after seconds: TimeInterval, _ work: @escaping () -> Void) -> TransportCancellable {
        let item = DispatchWorkItem(block: work)
        queue.asyncAfter(deadline: .now() + max(0, seconds), execute: item)
        return WorkItemCancellable(item: item)
    }

    private final class WorkItemCancellable: TransportCancellable {
        private let item: DispatchWorkItem
        init(item: DispatchWorkItem) { self.item = item }
        func cancel() { item.cancel() }
    }
}

// MARK: - Errors

/// Port of the .NET exception types thrown by the Windows transport layer
/// (`ClipboardChangedException`, `PhysicalKeysStillHeldException`, `ArgumentException` from
/// `TargetProfile.Validate`, and `TCC`/permission failures that have no Windows equivalent).
public enum TransportError: Error, Equatable {
    /// Port of `ClipboardChangedException`. The associated message mirrors the constructor
    /// message used at the throw site (Windows carries one fixed message; call sites here supply
    /// the Russian `PasteResult.message` text separately, so this string is diagnostic only).
    case clipboardChanged(String)
    /// Port of `OperationCanceledException` as observed by the transport layer.
    case cancelled
    /// Port of `PhysicalKeysStillHeldException`.
    case keysStillHeld
    /// Port of `TargetProfile.Validate`'s `ArgumentException`/`ArgumentOutOfRangeException`.
    case invalidProfile(String)
    /// macOS-only: TCC (Input Monitoring / Accessibility) permission missing (SPEC §9.2, §9.3).
    case permissionMissing(String)
    /// Any other native failure, carrying the underlying description.
    case other(String)

    /// Default message for `ClipboardChangedException`'s parameterless constructor
    /// (`"The clipboard changed before Snapik could publish the next stage."`).
    public static let clipboardChangedDefault = TransportError.clipboardChanged(
        "The clipboard changed before Snapik could publish the next stage.")
}

// MARK: - Clipboard (SPEC §5.1, §1.10)

/// Port of `ClipboardSnapshot` (Windows: `SequenceNumber`, `Data`, `IsComplete`), reduced to the
/// shape the transport layer needs (CONTRACTS.md). `sequence` is `NSPasteboard.changeCount`.
public struct ClipboardSnapshot: Equatable {
    public let sequence: Int
    public let hasText: Bool
    public let text: String?
    public let filePaths: [String]
    public let hasImage: Bool

    public init(sequence: Int, hasText: Bool, text: String?, filePaths: [String], hasImage: Bool) {
        self.sequence = sequence
        self.hasText = hasText
        self.text = text
        self.filePaths = filePaths
        self.hasImage = hasImage
    }
}

/// Port of SPEC-DELTA-2A CONTRACTS.md sync 2 addendum: `ClipboardEchoDetector.isReceiverEcho`
/// needs "no `FileDrop`" as a fast, named check.
extension ClipboardSnapshot {
    public var hasFiles: Bool { !filePaths.isEmpty }
}

/// Port of `IClipboardService` (`Windows/WindowsClipboardService.cs`), reduced to the four
/// operations CONTRACTS.md documents. There is no separate `IsCurrentAsync`/`RestoreIfCurrentAsync`
/// pair: callers verify "still ours" by calling `capture` again and comparing `sequence` to the
/// last known receipt (exactly what `IsCurrentAsync` did internally on Windows).
public protocol ClipboardServicing: AnyObject {
    func capture(_ completion: @escaping (ClipboardSnapshot) -> Void)
    func setPackageGuarded(
        paths: [String],
        text: String,
        expectedSequence: Int?,
        completion: @escaping (Result<ClipboardSnapshot, Error>) -> Void)
    func setPNGGuarded(
        path: String,
        expectedSequence: Int?,
        completion: @escaping (Result<ClipboardSnapshot, Error>) -> Void)
    func setTextGuarded(
        text: String,
        expectedSequence: Int?,
        completion: @escaping (Result<ClipboardSnapshot, Error>) -> Void)
}

// MARK: - Foreground target (SPEC §5.5)

/// Port of `TargetSnapshot` (`Windows/TransportContracts.cs:175-178`). `windowId` stands in for
/// the Windows window handle; `focusedElementId` stands in for the focused-child handle (only
/// available with Accessibility permission, SPEC §9.3).
public struct ForegroundTarget {
    public let processName: String
    public let bundleIdentifier: String?
    public let windowTitle: String?
    public let windowId: Int
    public let focusedElementId: String?

    public init(
        processName: String,
        bundleIdentifier: String?,
        windowTitle: String?,
        windowId: Int,
        focusedElementId: String?
    ) {
        self.processName = processName
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.windowId = windowId
        self.focusedElementId = focusedElementId
    }
}

extension ForegroundTarget: Equatable {
    /// Port of `WindowsForegroundTargetService.IsSame` (`:26-32`): "Заголовок окна в сравнение не
    /// входит" (the window title never participates in sameness comparisons), so it is excluded
    /// here too, deliberately, for every equality check (initial-capture matching and "target
    /// changed" checks alike).
    public static func == (lhs: ForegroundTarget, rhs: ForegroundTarget) -> Bool {
        lhs.processName == rhs.processName
            && lhs.bundleIdentifier == rhs.bundleIdentifier
            && lhs.windowId == rhs.windowId
            && lhs.focusedElementId == rhs.focusedElementId
    }
}

/// Port of `IForegroundTargetService.Capture`. `Matches`/`IsSame` are not separate protocol
/// requirements: `TargetProfile.matches(_:)` covers `Matches`, and callers re-invoke
/// `currentTarget()` and compare with `==` for `IsSame` (title excluded, see `ForegroundTarget.==`).
public protocol ForegroundTargetServicing: AnyObject {
    func currentTarget() -> ForegroundTarget?
}

// MARK: - Input injection (SPEC §5.6)

/// Port of `IInputInjector.SendAsync`. macOS sends Cmd+V, Option+V, or (SPEC-DELTA-2A poправка,
/// "так Claude Code вставляет картинки на Mac") Ctrl+V; Enter is structurally impossible to
/// express, satisfying "Enter не отправляется никогда" (SPEC §5.2) by construction. `gesture` is
/// the primary entry point (CONTRACTS.md sync 2); `alternate` is kept as a two-case (Cmd/Option)
/// convenience wrapper for call sites that predate `PasteIntentGesture` (`PasteCoordinator`,
/// `CodexDesktopPasteCompletionService.complete`), via the default implementation below.
public protocol InputInjecting: AnyObject {
    func injectPaste(gesture: PasteIntentGesture, completion: @escaping (Bool) -> Void)
    func injectPaste(alternate: Bool, completion: @escaping (Bool) -> Void)
}

extension InputInjecting {
    public func injectPaste(alternate: Bool, completion: @escaping (Bool) -> Void) {
        injectPaste(gesture: alternate ? .optionV : .commandV, completion: completion)
    }
}

/// Port of `IGuardedInputInjector.SendGuardedAsync` (`Windows/TransportContracts.cs:192-198`).
/// `finalGuard` is invoked after waiting for physical key release and immediately before the
/// synthetic paste is sent (SPEC §5.6); returning `false` cancels the injection without sending it.
public protocol GuardedInputInjecting: InputInjecting {
    func injectPasteGuarded(
        gesture: PasteIntentGesture,
        finalGuard: @escaping (@escaping (Bool) -> Void) -> Void,
        completion: @escaping (Bool) -> Void)
    func injectPasteGuarded(
        alternate: Bool,
        finalGuard: @escaping (@escaping (Bool) -> Void) -> Void,
        completion: @escaping (Bool) -> Void)
}

extension GuardedInputInjecting {
    public func injectPasteGuarded(
        alternate: Bool,
        finalGuard: @escaping (@escaping (Bool) -> Void) -> Void,
        completion: @escaping (Bool) -> Void
    ) {
        injectPasteGuarded(gesture: alternate ? .optionV : .commandV, finalGuard: finalGuard, completion: completion)
    }
}

// MARK: - Paste intent observation (SPEC §5.8)

/// Port of `PasteIntentObserved` (`Windows/TransportContracts.cs:307-312`), reduced to
/// CONTRACTS.md's three-field shape plus the two extra fields `CodexDesktopPasteCompletionService`
/// needs to reproduce SPEC §5.4 (the Windows event also carries `ForegroundWindowHandle`,
/// `ForegroundProcessId`, and `ClipboardSequenceNumber`): the target captured by the observer at
/// the moment of the physical key event, and the clipboard sequence number at that moment.
public struct PasteIntent {
    public let gesture: PasteIntentGesture
    public let timestamp: Date
    public let synthetic: Bool
    public let target: ForegroundTarget?
    public let clipboardSequence: Int
    /// Port of `PasteIntentObserved.IsIntercepted` (CONTRACTS.md sync 2): `true` only when
    /// `MacPasteIntentObserver`'s `.defaultTap` actually suppressed the physical keystroke (SPEC-
    /// DELTA-2A §1). `false` for every intent observed in `.listenOnly` mode (no Accessibility) or
    /// where the predicate declined to intercept (e.g. Codex Desktop, SPEC-DELTA-2A §1.2).
    public let intercepted: Bool

    public init(
        gesture: PasteIntentGesture,
        timestamp: Date,
        synthetic: Bool,
        target: ForegroundTarget?,
        clipboardSequence: Int,
        intercepted: Bool = false
    ) {
        self.gesture = gesture
        self.timestamp = timestamp
        self.synthetic = synthetic
        self.target = target
        self.clipboardSequence = clipboardSequence
        self.intercepted = intercepted
    }

    /// Port of the Windows `HotkeyGesture.AltV` distinction, reduced to "is this the non-primary
    /// gesture" (`gesture != .commandV`) so pre-sync-2 call sites (`TargetProfile`,
    /// `PasteCoordinator`) keep working unmodified (CONTRACTS.md sync 2: "public var alternate:
    /// Bool { gesture != .commandV }").
    public var alternate: Bool { gesture != .commandV }
}

/// Port of `IPasteIntentObserver`.
public protocol PasteIntentObserving: AnyObject {
    var onPasteIntent: ((PasteIntent) -> Void)? { get set }
    func start() throws
    func stop()
    var isRunning: Bool { get }
}

// MARK: - Acceptance observation (SPEC §5.2, §5.7)

/// Port of `AcceptanceOutcome`.
public enum AcceptanceOutcome: Equatable {
    case accepted
    case notObservable
    case timedOut
    case targetLost
}

/// Port of `PackageAcceptanceOutcome`.
public struct PackageAcceptanceOutcome: Equatable {
    public let images: AcceptanceOutcome
    public let text: AcceptanceOutcome

    public init(images: AcceptanceOutcome, text: AcceptanceOutcome) {
        self.images = images
        self.text = text
    }
}

/// Port of `IPasteAcceptanceObserver`. Failures (including `TransportError.cancelled`) propagate
/// through `Result.failure` instead of being thrown, mirroring how a cancelled `Task.Delay`
/// propagates an `OperationCanceledException` through the awaited chain in the C# original.
public protocol PasteAcceptanceObserving: AnyObject {
    func waitForPackage(
        target: ForegroundTarget,
        profile: TargetProfile,
        cancellationToken: PasteCancellationToken,
        completion: @escaping (Result<PackageAcceptanceOutcome, Error>) -> Void)
    func waitForImage(
        target: ForegroundTarget,
        imageIndex: Int,
        profile: TargetProfile,
        cancellationToken: PasteCancellationToken,
        completion: @escaping (Result<AcceptanceOutcome, Error>) -> Void)
    func waitForText(
        target: ForegroundTarget,
        profile: TargetProfile,
        cancellationToken: PasteCancellationToken,
        completion: @escaping (Result<AcceptanceOutcome, Error>) -> Void)
}

// MARK: - Paste coordinator contracts (SPEC §5.2)

/// Port of `PreparedPastePackage`.
public struct PreparedPastePackage {
    public let exportId: SBGuid
    public let imagePaths: [String]
    public let promptText: String

    public init(exportId: SBGuid, imagePaths: [String], promptText: String) {
        self.exportId = exportId
        self.imagePaths = imagePaths
        self.promptText = promptText
    }
}

/// Port of `PastePhase`.
public enum PastePhase: Equatable {
    case validating
    case preparingClipboard
    case sendingImage
    case waitingForImage
    case sendingText
    case waitingForText
    case completed
    case stopped
}

/// Port of `PasteProgress`.
public struct PasteProgress {
    public let phase: PastePhase
    public let imagesDispatched: Int
    public let imagesConfirmed: Int
    public let totalImages: Int
    public let textDispatched: Bool
    public let textConfirmed: Bool
    public let message: String

    public init(
        phase: PastePhase,
        imagesDispatched: Int,
        imagesConfirmed: Int,
        totalImages: Int,
        textDispatched: Bool,
        textConfirmed: Bool,
        message: String
    ) {
        self.phase = phase
        self.imagesDispatched = imagesDispatched
        self.imagesConfirmed = imagesConfirmed
        self.totalImages = totalImages
        self.textDispatched = textDispatched
        self.textConfirmed = textConfirmed
        self.message = message
    }
}

/// Port of `PasteStatus`.
public enum PasteStatus: Equatable {
    case completedVerified
    case completedUnverified
    case invalidPackage
    case targetMismatch
    case targetChanged
    case clipboardChanged
    case acceptanceTimedOut
    case cancelled
    case failed
}

/// Port of `PasteResumeToken`.
public struct PasteResumeToken: Equatable {
    public let exportId: SBGuid
    public let confirmedImageCount: Int
    public let textConfirmed: Bool

    public init(exportId: SBGuid, confirmedImageCount: Int, textConfirmed: Bool) {
        self.exportId = exportId
        self.confirmedImageCount = confirmedImageCount
        self.textConfirmed = textConfirmed
    }
}

/// Port of `PasteResult`.
public struct PasteResult {
    public let status: PasteStatus
    public let imagesDispatched: Int
    public let imagesConfirmed: Int
    public let textDispatched: Bool
    public let textConfirmed: Bool
    public let safeResumeToken: PasteResumeToken?
    public let message: String
    public let error: Error?

    public init(
        status: PasteStatus,
        imagesDispatched: Int,
        imagesConfirmed: Int,
        textDispatched: Bool,
        textConfirmed: Bool,
        safeResumeToken: PasteResumeToken?,
        message: String,
        error: Error? = nil
    ) {
        self.status = status
        self.imagesDispatched = imagesDispatched
        self.imagesConfirmed = imagesConfirmed
        self.textDispatched = textDispatched
        self.textConfirmed = textConfirmed
        self.safeResumeToken = safeResumeToken
        self.message = message
        self.error = error
    }

    /// Port of `PasteResult.DeliveryWasObserved`.
    public var deliveryWasObserved: Bool { status == .completedVerified }
}

// MARK: - Codex Desktop paste completion (SPEC §5.4)

/// Port of `CodexPasteCompletionStatus`.
public enum CodexPasteCompletionStatus: Equatable {
    case completedUnverified
    case notApplicable
    case nothingToDispatch
    case staleIntent
    case targetLost
    case clipboardChanged
    case cancelled
    case failed
}

/// Port of `CodexPasteCompletionResult`.
public struct CodexPasteCompletionResult {
    public let status: CodexPasteCompletionStatus
    public let message: String
    public let textClipboardReceipt: ClipboardSnapshot?
    public let error: Error?

    public init(
        status: CodexPasteCompletionStatus,
        message: String,
        textClipboardReceipt: ClipboardSnapshot? = nil,
        error: Error? = nil
    ) {
        self.status = status
        self.message = message
        self.textClipboardReceipt = textClipboardReceipt
        self.error = error
    }

    /// Port of `CodexPasteCompletionResult.TextWasDispatched`.
    public var textWasDispatched: Bool { status == .completedUnverified }
}

/// Port of CONTRACTS.md sync 2's `CodexPasteCompletionResult.currentClipboardReceipt`: the caller
/// (`AppCoordinator+PasteIntent.swift`) reads the post-completion receipt uniformly whether it came
/// from `complete` (Codex text catch-up) or `completeSequential` (SPEC-DELTA-2A §2) — both only
/// ever populate `textClipboardReceipt` (the last successful write), so this is a plain alias.
extension CodexPasteCompletionResult {
    public var currentClipboardReceipt: ClipboardSnapshot? { textClipboardReceipt }
}
