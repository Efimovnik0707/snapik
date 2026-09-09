// Port of Windows/UnobservableAcceptanceObserver.cs, SPEC §5.7.
//
// The default observer, which honestly admits it cannot observe acceptance: it waits
// `profile.unobservableSettlementDelay` and reports `.notObservable` if the target is still the
// same, `.targetLost` otherwise. A successful completion through this observer therefore always
// yields `.completedUnverified`, never `.completedVerified` (Windows/README.md:16).

import Foundation

public final class UnobservableAcceptanceObserver: PasteAcceptanceObserving {
    private let foreground: ForegroundTargetServicing
    private let scheduler: TransportScheduler

    public init(foreground: ForegroundTargetServicing, scheduler: TransportScheduler = DispatchQueueScheduler()) {
        self.foreground = foreground
        self.scheduler = scheduler
    }

    public func waitForPackage(
        target: ForegroundTarget,
        profile: TargetProfile,
        cancellationToken: PasteCancellationToken,
        completion: @escaping (Result<PackageAcceptanceOutcome, Error>) -> Void
    ) {
        wait(target: target, profile: profile, cancellationToken: cancellationToken) { result in
            completion(result.map { PackageAcceptanceOutcome(images: $0, text: $0) })
        }
    }

    public func waitForImage(
        target: ForegroundTarget,
        imageIndex: Int,
        profile: TargetProfile,
        cancellationToken: PasteCancellationToken,
        completion: @escaping (Result<AcceptanceOutcome, Error>) -> Void
    ) {
        wait(target: target, profile: profile, cancellationToken: cancellationToken, completion: completion)
    }

    public func waitForText(
        target: ForegroundTarget,
        profile: TargetProfile,
        cancellationToken: PasteCancellationToken,
        completion: @escaping (Result<AcceptanceOutcome, Error>) -> Void
    ) {
        wait(target: target, profile: profile, cancellationToken: cancellationToken, completion: completion)
    }

    /// Port of the private `WaitAsync` (`:25-32`).
    private func wait(
        target: ForegroundTarget,
        profile: TargetProfile,
        cancellationToken: PasteCancellationToken,
        completion: @escaping (Result<AcceptanceOutcome, Error>) -> Void
    ) {
        scheduler.schedule(after: profile.unobservableSettlementDelay) { [weak self] in
            guard let self else { return }
            if cancellationToken.isCancelled {
                completion(.failure(TransportError.cancelled))
                return
            }
            let current = self.foreground.currentTarget()
            completion(.success(current == target ? .notObservable : .targetLost))
        }
    }
}
