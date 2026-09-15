// Port of Windows/PasteCoordinator.cs, SPEC §5.2 (state machine, transitions, exact Russian
// messages). Not used in the main scenario (SPEC §5: "получателя не выбирают"), but remains part
// of the contract, covered by tests.
//
// The C# original is a sequence of `await`s inside one `async Task<PasteResult>` method. Without
// async/await this becomes continuation-passing style: each `await` point becomes a completion
// closure, and the per-operation `OperationState` class plus the shared `translate(error:)`/
// `checkTarget`/`checkAfterWrite`/`stopForAcceptance` helpers reproduce the original control flow
// step for step.

import Foundation

public final class PasteCoordinator {
    private let clipboard: ClipboardServicing
    private let foreground: ForegroundTargetServicing
    private let input: InputInjecting
    private let observer: PasteAcceptanceObserving
    private let scheduler: TransportScheduler

    public init(
        clipboard: ClipboardServicing,
        foreground: ForegroundTargetServicing,
        input: InputInjecting,
        observer: PasteAcceptanceObserving,
        scheduler: TransportScheduler = DispatchQueueScheduler()
    ) {
        self.clipboard = clipboard
        self.foreground = foreground
        self.input = input
        self.observer = observer
        self.scheduler = scheduler
    }

    /// Port of `PasteCoordinator.PasteAsync` (`:11-47`).
    public func paste(
        package: PreparedPastePackage,
        profile: TargetProfile,
        resumeToken: PasteResumeToken? = nil,
        cancellationToken: PasteCancellationToken = PasteCancellationToken(),
        progress: ((PasteProgress) -> Void)? = nil,
        completion: @escaping (PasteResult) -> Void
    ) {
        let state = OperationState(exportId: package.exportId, resume: resumeToken)

        do {
            try profile.validate()
        } catch {
            completion(translate(error, state: state))
            return
        }

        if let validationMessage = Self.validatePackage(package, resume: resumeToken) {
            completion(state.result(status: .invalidPackage, message: validationMessage))
            return
        }

        progress?(state.progress(
            phase: .validating,
            total: package.imagePaths.count,
            message: "Проверяем пакет, буфер обмена и активное поле."))

        guard let target = foreground.currentTarget(), profile.matches(target) else {
            completion(state.result(
                status: .targetMismatch,
                message: "Активное окно не соответствует выбранному профилю."))
            return
        }

        clipboard.capture { [weak self] originalClipboard in
            guard let self else { return }
            if cancellationToken.isCancelled {
                completion(self.translate(TransportError.cancelled, state: state))
                return
            }
            switch profile.transport {
            case .singleClipboardPackage:
                self.pasteSinglePackage(
                    package: package, profile: profile, target: target, originalClipboard: originalClipboard,
                    state: state, cancellationToken: cancellationToken, progress: progress, completion: completion)
            case .stagedSequence:
                self.stageImage(
                    index: state.safeResumePrefix, expectedSequence: originalClipboard.sequence,
                    package: package, profile: profile, target: target, originalClipboard: originalClipboard,
                    state: state, cancellationToken: cancellationToken, progress: progress, completion: completion)
            }
        }
    }

    // MARK: SingleClipboardPackage branch (`:49-85`)

    private func pasteSinglePackage(
        package: PreparedPastePackage, profile: TargetProfile, target: ForegroundTarget,
        originalClipboard: ClipboardSnapshot, state: OperationState, cancellationToken: PasteCancellationToken,
        progress: ((PasteProgress) -> Void)?, completion: @escaping (PasteResult) -> Void
    ) {
        if let targetError = checkTarget(target, state: state) {
            completion(targetError)
            return
        }
        let total = package.imagePaths.count
        progress?(state.progress(
            phase: .preparingClipboard, total: total,
            message: "Копируем отдельные PNG и текст в один буферный пакет."))

        clipboard.setPackageGuarded(
            paths: package.imagePaths, text: package.promptText, expectedSequence: originalClipboard.sequence
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                completion(self.translate(error, state: state))
            case .success(let receipt):
                self.checkAfterWrite(
                    target: target, expectedSequence: receipt.sequence, state: state,
                    cancellationToken: cancellationToken
                ) { guardResult in
                    if let guardResult { completion(guardResult); return }

                    self.input.injectPaste(alternate: profile.imagePasteIsAlternate) { _ in
                        state.imagesDispatched = total
                        state.textDispatched = true

                        self.waitWithTimeout(
                            timeout: profile.acceptanceTimeout,
                            work: { done in
                                self.observer.waitForPackage(
                                    target: target, profile: profile, cancellationToken: cancellationToken,
                                    completion: done)
                            },
                            onTimeout: { .success(PackageAcceptanceOutcome(images: .timedOut, text: .timedOut)) }
                        ) { result in
                            switch result {
                            case .failure(let error):
                                completion(self.translate(error, state: state))
                            case .success(let observed):
                                if observed.images == .targetLost || observed.text == .targetLost {
                                    completion(state.result(
                                        status: .targetChanged,
                                        message: "Активное окно или поле ввода изменилось во время ожидания."))
                                    return
                                }
                                if observed.images == .timedOut || observed.text == .timedOut {
                                    completion(state.result(
                                        status: .acceptanceTimedOut,
                                        message: "Получатель не подтвердил весь пакет вовремя. Проверьте черновик перед повтором."))
                                    return
                                }
                                state.imagesConfirmed = observed.images == .accepted ? total : 0
                                state.textConfirmed = observed.text == .accepted
                                state.canResume = false
                                let verified = state.imagesConfirmed == total && state.textConfirmed
                                let result = state.result(
                                    status: verified ? .completedVerified : .completedUnverified,
                                    message: verified
                                        ? "Все отдельные вложения и текст подтверждены получателем. Запрос оставлен черновиком."
                                        : "Комбинация вставки отправлена; весь пакет нельзя проверить автоматически. Проверьте черновик. Запрос не отправлен.")
                                self.restoreWhenSafe(profile: profile, original: originalClipboard, current: receipt, result: result) {
                                    progress?(state.progress(phase: .completed, total: total, message: result.message))
                                    completion(result)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: StagedSequence branch (`:87-158`)

    private func stageImage(
        index: Int, expectedSequence: Int,
        package: PreparedPastePackage, profile: TargetProfile, target: ForegroundTarget,
        originalClipboard: ClipboardSnapshot, state: OperationState, cancellationToken: PasteCancellationToken,
        progress: ((PasteProgress) -> Void)?, completion: @escaping (PasteResult) -> Void
    ) {
        let total = package.imagePaths.count
        if index >= total {
            stageText(
                expectedSequence: expectedSequence, package: package, profile: profile, target: target,
                originalClipboard: originalClipboard, state: state, cancellationToken: cancellationToken,
                progress: progress, completion: completion)
            return
        }
        if let targetError = checkTarget(target, state: state) {
            completion(targetError)
            return
        }
        progress?(state.progress(
            phase: .preparingClipboard, total: total,
            message: "Готовим изображение \(index + 1) из \(total)."))

        clipboard.setPNGGuarded(path: package.imagePaths[index], expectedSequence: expectedSequence) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                completion(self.translate(error, state: state))
            case .success(let receipt):
                self.checkAfterWrite(
                    target: target, expectedSequence: receipt.sequence, state: state,
                    cancellationToken: cancellationToken
                ) { guardResult in
                    if let guardResult { completion(guardResult); return }

                    progress?(state.progress(
                        phase: .sendingImage, total: total, message: "Вставляем изображение \(index + 1) из \(total)."))
                    self.input.injectPaste(alternate: profile.imagePasteIsAlternate) { _ in
                        state.imagesDispatched += 1
                        progress?(state.progress(phase: .waitingForImage, total: total, message: "Ждём приёма вложения."))

                        self.waitWithTimeout(
                            timeout: profile.acceptanceTimeout,
                            work: { done in
                                self.observer.waitForImage(
                                    target: target, imageIndex: index, profile: profile,
                                    cancellationToken: cancellationToken, completion: done)
                            },
                            onTimeout: { .success(.timedOut) }
                        ) { result in
                            switch result {
                            case .failure(let error):
                                completion(self.translate(error, state: state))
                            case .success(let outcome):
                                switch outcome {
                                case .accepted:
                                    state.imagesConfirmed += 1
                                    if state.canResume && state.safeResumePrefix == index {
                                        state.safeResumePrefix += 1
                                    }
                                case .notObservable:
                                    state.canResume = false
                                case .timedOut, .targetLost:
                                    completion(self.stopForAcceptance(outcome, state: state))
                                    return
                                }

                                self.checkAfterWrite(
                                    target: target, expectedSequence: receipt.sequence, state: state,
                                    cancellationToken: cancellationToken
                                ) { guardResult2 in
                                    if let guardResult2 { completion(guardResult2); return }
                                    self.stageImage(
                                        index: index + 1, expectedSequence: receipt.sequence, package: package,
                                        profile: profile, target: target, originalClipboard: originalClipboard,
                                        state: state, cancellationToken: cancellationToken, progress: progress,
                                        completion: completion)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func stageText(
        expectedSequence: Int,
        package: PreparedPastePackage, profile: TargetProfile, target: ForegroundTarget,
        originalClipboard: ClipboardSnapshot, state: OperationState, cancellationToken: PasteCancellationToken,
        progress: ((PasteProgress) -> Void)?, completion: @escaping (PasteResult) -> Void
    ) {
        if let targetError = checkTarget(target, state: state) {
            completion(targetError)
            return
        }
        let total = package.imagePaths.count
        progress?(state.progress(phase: .preparingClipboard, total: total, message: "Готовим текст задания."))

        clipboard.setTextGuarded(text: package.promptText, expectedSequence: expectedSequence) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                completion(self.translate(error, state: state))
            case .success(let receipt):
                self.checkAfterWrite(
                    target: target, expectedSequence: receipt.sequence, state: state,
                    cancellationToken: cancellationToken
                ) { guardResult in
                    if let guardResult { completion(guardResult); return }

                    progress?(state.progress(
                        phase: .sendingText, total: total, message: "Вставляем текст задания без отправки."))
                    self.input.injectPaste(alternate: profile.textPasteIsAlternate) { _ in
                        state.textDispatched = true

                        self.waitWithTimeout(
                            timeout: profile.acceptanceTimeout,
                            work: { done in
                                self.observer.waitForText(
                                    target: target, profile: profile, cancellationToken: cancellationToken,
                                    completion: done)
                            },
                            onTimeout: { .success(.timedOut) }
                        ) { result in
                            switch result {
                            case .failure(let error):
                                completion(self.translate(error, state: state))
                            case .success(let outcome):
                                switch outcome {
                                case .accepted:
                                    state.textConfirmed = true
                                case .notObservable:
                                    state.canResume = false
                                case .timedOut, .targetLost:
                                    completion(self.stopForAcceptance(outcome, state: state))
                                    return
                                }

                                let verified = state.imagesConfirmed == package.imagePaths.count && state.textConfirmed
                                let result = state.result(
                                    status: verified ? .completedVerified : .completedUnverified,
                                    message: verified
                                        ? "Все изображения и текст подтверждены получателем. Запрос оставлен черновиком."
                                        : "Все комбинации вставки отправлены; часть приёма нельзя проверить автоматически. Проверьте черновик. Запрос не отправлен.")
                                self.restoreWhenSafe(profile: profile, original: originalClipboard, current: receipt, result: result) {
                                    progress?(state.progress(phase: .completed, total: total, message: result.message))
                                    completion(result)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Shared helpers

    /// Port of the private `CheckTarget` (`:160-161`).
    private func checkTarget(_ target: ForegroundTarget, state: OperationState) -> PasteResult? {
        guard let current = foreground.currentTarget(), current == target else {
            return state.result(
                status: .targetChanged,
                message: "Активное окно или поле ввода изменилось. Вставка остановлена.")
        }
        return nil
    }

    /// Port of `CheckAfterWriteAsync` (`:163-171`).
    private func checkAfterWrite(
        target: ForegroundTarget, expectedSequence: Int, state: OperationState,
        cancellationToken: PasteCancellationToken, completion: @escaping (PasteResult?) -> Void
    ) {
        if cancellationToken.isCancelled {
            completion(translate(TransportError.cancelled, state: state))
            return
        }
        if let targetError = checkTarget(target, state: state) {
            completion(targetError)
            return
        }
        clipboard.capture { snapshot in
            if snapshot.sequence == expectedSequence {
                completion(nil)
            } else {
                completion(state.result(
                    status: .clipboardChanged,
                    message: "Буфер обмена изменён другим приложением. Вставка остановлена без перезаписи новых данных."))
            }
        }
    }

    /// Port of `StopForAcceptance` (`:173-178`).
    private func stopForAcceptance(_ outcome: AcceptanceOutcome, state: OperationState) -> PasteResult {
        if outcome == .timedOut {
            return state.result(
                status: .acceptanceTimedOut,
                message: "Получатель не подтвердил приём вовремя. Проверьте черновик перед повтором.")
        }
        return state.result(
            status: .targetChanged,
            message: "Активное окно или поле ввода изменилось во время ожидания.")
    }

    /// Port of the top-level `try`/`catch` in `PasteAsync` (`:34-46`).
    private func translate(_ error: Error, state: OperationState) -> PasteResult {
        switch error {
        case TransportError.cancelled:
            return state.result(
                status: .cancelled,
                message: "Вставка отменена. Проверьте черновик перед повтором; подготовленный экспорт сохранён.",
                error: error)
        case TransportError.clipboardChanged:
            return state.result(
                status: .clipboardChanged,
                message: "Буфер обмена изменён другим приложением. Вставка остановлена без перезаписи новых данных.",
                error: error)
        default:
            return state.result(
                status: .failed,
                message: "Не удалось выполнить вставку. Проверьте черновик перед повтором; подготовленный экспорт сохранён.",
                error: error)
        }
    }

    /// Port of `RestoreWhenSafeAsync` (`:217-221`). The reduced `ClipboardSnapshot` here has no
    /// image bytes (only a `hasImage` flag), so only a text-only original clipboard can actually
    /// be restored; anything else is a safe no-op. None of the built-in profiles set
    /// `restoreClipboardWhenSafe`, so this only matters for custom profiles.
    private func restoreWhenSafe(
        profile: TargetProfile, original: ClipboardSnapshot, current: ClipboardSnapshot, result: PasteResult,
        completion: @escaping () -> Void
    ) {
        guard profile.restoreClipboardWhenSafe, result.status == .completedVerified else {
            completion()
            return
        }
        guard original.hasText, let text = original.text, !original.hasImage, original.filePaths.isEmpty else {
            completion()
            return
        }
        clipboard.setTextGuarded(text: text, expectedSequence: current.sequence) { _ in completion() }
    }

    /// Port of `WithTimeoutAsync`/`WithPackageTimeoutAsync` (`:192-215`): races `work` against a
    /// scheduled timeout, invoking whichever settles first exactly once.
    private func waitWithTimeout<T>(
        timeout: TimeInterval,
        work: (@escaping (Result<T, Error>) -> Void) -> Void,
        onTimeout: @escaping () -> Result<T, Error>,
        completion: @escaping (Result<T, Error>) -> Void
    ) {
        let box = SettleOnce()
        var timerToken: TransportCancellable?
        timerToken = scheduler.schedule(after: timeout) {
            if box.settle() { completion(onTimeout()) }
        }
        work { result in
            if box.settle() {
                timerToken?.cancel()
                completion(result)
            }
        }
    }

    private final class SettleOnce {
        private var settled = false
        /// Returns `true` the first time it is called, `false` on every subsequent call.
        func settle() -> Bool {
            if settled { return false }
            settled = true
            return true
        }
    }

    /// Port of `ValidatePackage` (`:180-190`).
    private static func validatePackage(_ package: PreparedPastePackage, resume: PasteResumeToken?) -> String? {
        if package.exportId == .empty {
            return "У подготовленного пакета отсутствует export ID."
        }
        if package.imagePaths.isEmpty {
            return "В пакете нет изображений."
        }
        let hasInvalidPath = package.imagePaths.contains { path in
            !path.hasPrefix("/")
                || (path as NSString).pathExtension.lowercased() != "png"
                || !FileManager.default.fileExists(atPath: path)
        }
        if hasInvalidPath {
            return "Все изображения должны быть существующими PNG с абсолютными путями."
        }
        if package.promptText.isEmpty {
            return "Текст задания пуст."
        }
        if let resume,
            resume.exportId != package.exportId
                || resume.confirmedImageCount < 0
                || resume.confirmedImageCount > package.imagePaths.count
                || resume.textConfirmed {
            return "Точка продолжения не относится к этому экспорту или уже завершена."
        }
        return nil
    }

    /// Port of the private `OperationState` (`:223-251`).
    private final class OperationState {
        let exportId: SBGuid
        var imagesDispatched: Int
        var imagesConfirmed: Int
        var safeResumePrefix: Int
        var textDispatched = false
        var textConfirmed = false
        var canResume = true

        init(exportId: SBGuid, resume: PasteResumeToken?) {
            self.exportId = exportId
            let prefix = resume?.confirmedImageCount ?? 0
            safeResumePrefix = prefix
            imagesConfirmed = prefix
            imagesDispatched = prefix
        }

        func result(status: PasteStatus, message: String, error: Error? = nil) -> PasteResult {
            let token: PasteResumeToken? = (canResume && safeResumePrefix > 0 && !textConfirmed)
                ? PasteResumeToken(exportId: exportId, confirmedImageCount: safeResumePrefix, textConfirmed: false)
                : nil
            return PasteResult(
                status: status, imagesDispatched: imagesDispatched, imagesConfirmed: imagesConfirmed,
                textDispatched: textDispatched, textConfirmed: textConfirmed, safeResumeToken: token,
                message: message, error: error)
        }

        func progress(phase: PastePhase, total: Int, message: String) -> PasteProgress {
            PasteProgress(
                phase: phase, imagesDispatched: imagesDispatched, imagesConfirmed: imagesConfirmed,
                totalImages: total, textDispatched: textDispatched, textConfirmed: textConfirmed, message: message)
        }
    }
}
