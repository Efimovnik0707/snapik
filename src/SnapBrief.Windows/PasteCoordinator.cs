using System.IO;

namespace SnapBrief.Windows;

public sealed class PasteCoordinator(
    IClipboardService clipboard,
    IForegroundTargetService foreground,
    IInputInjector input,
    IPasteAcceptanceObserver observer) : IPasteCoordinator
{
    public async Task<PasteResult> PasteAsync(
        PreparedPastePackage package,
        TargetProfile profile,
        PasteResumeToken? resumeToken = null,
        IProgress<PasteProgress>? progress = null,
        CancellationToken cancellationToken = default)
    {
        var state = new OperationState(package.ExportId, resumeToken);
        try
        {
            profile.Validate();
            var validationError = ValidatePackage(package, resumeToken);
            if (validationError is not null) return state.Result(PasteStatus.InvalidPackage, validationError);

            progress?.Report(state.Progress(PastePhase.Validating, package.ImagePaths.Count, "Проверяем пакет, буфер обмена и активное поле."));
            var target = foreground.Capture();
            if (!target.IsUsable || !foreground.Matches(target, profile))
                return state.Result(PasteStatus.TargetMismatch, "Активное окно не соответствует выбранному профилю.");

            var originalClipboard = await clipboard.CaptureAsync(cancellationToken);
            return profile.Transport == PasteTransport.SingleClipboardPackage
                ? await PasteSinglePackageAsync(package, profile, target, originalClipboard, state, progress, cancellationToken)
                : await PasteStagedAsync(package, profile, target, originalClipboard, state, progress, cancellationToken);
        }
        catch (ClipboardChangedException)
        {
            return state.Result(PasteStatus.ClipboardChanged, "Буфер обмена изменён другим приложением. Вставка остановлена без перезаписи новых данных.");
        }
        catch (OperationCanceledException)
        {
            return state.Result(PasteStatus.Cancelled, "Вставка отменена. Проверьте черновик перед повтором; подготовленный экспорт сохранён.");
        }
        catch (Exception ex)
        {
            return state.Result(PasteStatus.Failed, "Не удалось выполнить вставку. Проверьте черновик перед повтором; подготовленный экспорт сохранён.", ex);
        }
    }

    private async Task<PasteResult> PasteSinglePackageAsync(
        PreparedPastePackage package, TargetProfile profile, TargetSnapshot target,
        ClipboardSnapshot originalClipboard, OperationState state,
        IProgress<PasteProgress>? progress, CancellationToken cancellationToken)
    {
        var targetError = CheckTarget(target, state);
        if (targetError is not null) return targetError;
        progress?.Report(state.Progress(PastePhase.PreparingClipboard, package.ImagePaths.Count, "Копируем отдельные PNG и текст в один буферный пакет."));
        var receipt = await clipboard.SetPackageGuardedAsync(package.ImagePaths, package.PromptText, originalClipboard.SequenceNumber, cancellationToken);
        var guard = await CheckAfterWriteAsync(target, receipt, state, cancellationToken);
        if (guard is not null) return guard;

        await input.SendAsync(profile.ImagePasteGesture, cancellationToken);
        state.ImagesDispatched = package.ImagePaths.Count;
        state.TextDispatched = true;
        var observed = await WithPackageTimeoutAsync(
            token => observer.WaitForPackageAsync(target, profile, token),
            profile.AcceptanceTimeout,
            cancellationToken);
        if (observed.Images == AcceptanceOutcome.TargetLost || observed.Text == AcceptanceOutcome.TargetLost)
            return state.Result(PasteStatus.TargetChanged, "Активное окно или поле ввода изменилось во время ожидания.");
        if (observed.Images == AcceptanceOutcome.TimedOut || observed.Text == AcceptanceOutcome.TimedOut)
            return state.Result(PasteStatus.AcceptanceTimedOut, "Получатель не подтвердил весь пакет вовремя. Проверьте черновик перед повтором.");

        state.ImagesConfirmed = observed.Images == AcceptanceOutcome.Accepted ? package.ImagePaths.Count : 0;
        state.TextConfirmed = observed.Text == AcceptanceOutcome.Accepted;
        state.CanResume = false;
        var verified = state.ImagesConfirmed == package.ImagePaths.Count && state.TextConfirmed;
        var result = state.Result(
            verified ? PasteStatus.CompletedVerified : PasteStatus.CompletedUnverified,
            verified
                ? "Все отдельные вложения и текст подтверждены получателем. Запрос оставлен черновиком."
                : "Комбинация вставки отправлена; весь пакет нельзя проверить автоматически. Проверьте черновик. Запрос не отправлен.");
        await RestoreWhenSafeAsync(profile, originalClipboard, receipt, result, cancellationToken);
        progress?.Report(state.Progress(PastePhase.Completed, package.ImagePaths.Count, result.Message));
        return result;
    }

    private async Task<PasteResult> PasteStagedAsync(
        PreparedPastePackage package, TargetProfile profile, TargetSnapshot target,
        ClipboardSnapshot originalClipboard, OperationState state,
        IProgress<PasteProgress>? progress, CancellationToken cancellationToken)
    {
        var expectedSequence = originalClipboard.SequenceNumber;
        ClipboardWriteReceipt? lastReceipt = null;

        for (var index = state.SafeResumePrefix; index < package.ImagePaths.Count; index++)
        {
            var targetError = CheckTarget(target, state);
            if (targetError is not null) return targetError;
            progress?.Report(state.Progress(PastePhase.PreparingClipboard, package.ImagePaths.Count, $"Готовим изображение {index + 1} из {package.ImagePaths.Count}."));
            lastReceipt = await clipboard.SetPngGuardedAsync(package.ImagePaths[index], expectedSequence, cancellationToken);
            expectedSequence = lastReceipt.Value.SequenceNumber;
            var guard = await CheckAfterWriteAsync(target, lastReceipt.Value, state, cancellationToken);
            if (guard is not null) return guard;

            progress?.Report(state.Progress(PastePhase.SendingImage, package.ImagePaths.Count, $"Вставляем изображение {index + 1} из {package.ImagePaths.Count}."));
            await input.SendAsync(profile.ImagePasteGesture, cancellationToken);
            state.ImagesDispatched++;
            progress?.Report(state.Progress(PastePhase.WaitingForImage, package.ImagePaths.Count, "Ждём приёма вложения."));
            var outcome = await WithTimeoutAsync(
                token => observer.WaitForImageAsync(target, index, profile, token),
                profile.AcceptanceTimeout,
                cancellationToken);
            if (outcome == AcceptanceOutcome.Accepted)
            {
                state.ImagesConfirmed++;
                if (state.CanResume && state.SafeResumePrefix == index) state.SafeResumePrefix++;
            }
            else if (outcome == AcceptanceOutcome.NotObservable)
            {
                state.CanResume = false;
            }
            else
            {
                return StopForAcceptance(outcome, state);
            }

            guard = await CheckAfterWriteAsync(target, lastReceipt.Value, state, cancellationToken);
            if (guard is not null) return guard;
        }

        // A package whose captures carry no notes has no text step at all.
        var hasText = package.PromptText.Length > 0;
        if (hasText)
        {
            var beforeTextError = CheckTarget(target, state);
            if (beforeTextError is not null) return beforeTextError;
            progress?.Report(state.Progress(PastePhase.PreparingClipboard, package.ImagePaths.Count, "Готовим текст задания."));
            lastReceipt = await clipboard.SetTextGuardedAsync(package.PromptText, expectedSequence, cancellationToken);
            var textGuard = await CheckAfterWriteAsync(target, lastReceipt.Value, state, cancellationToken);
            if (textGuard is not null) return textGuard;

            progress?.Report(state.Progress(PastePhase.SendingText, package.ImagePaths.Count, "Вставляем текст задания без отправки."));
            await input.SendAsync(profile.TextPasteGesture, cancellationToken);
            state.TextDispatched = true;
            var textOutcome = await WithTimeoutAsync(
                token => observer.WaitForTextAsync(target, profile, token),
                profile.AcceptanceTimeout,
                cancellationToken);
            if (textOutcome == AcceptanceOutcome.Accepted) state.TextConfirmed = true;
            else if (textOutcome == AcceptanceOutcome.NotObservable) state.CanResume = false;
            else return StopForAcceptance(textOutcome, state);
        }

        var verified = state.ImagesConfirmed == package.ImagePaths.Count && (state.TextConfirmed || !hasText);
        var result = state.Result(
            verified ? PasteStatus.CompletedVerified : PasteStatus.CompletedUnverified,
            verified
                ? "Все изображения и текст подтверждены получателем. Запрос оставлен черновиком."
                : "Все комбинации вставки отправлены; часть приёма нельзя проверить автоматически. Проверьте черновик. Запрос не отправлен.");
        if (lastReceipt is { } receipt) await RestoreWhenSafeAsync(profile, originalClipboard, receipt, result, cancellationToken);
        progress?.Report(state.Progress(PastePhase.Completed, package.ImagePaths.Count, result.Message));
        return result;
    }

    private PasteResult? CheckTarget(TargetSnapshot target, OperationState state) =>
        foreground.IsSame(target) ? null : state.Result(PasteStatus.TargetChanged, "Активное окно или поле ввода изменилось. Вставка остановлена.");

    private async Task<PasteResult?> CheckAfterWriteAsync(TargetSnapshot target, ClipboardWriteReceipt receipt, OperationState state, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var targetError = CheckTarget(target, state);
        if (targetError is not null) return targetError;
        return await clipboard.IsCurrentAsync(receipt, cancellationToken)
            ? null
            : state.Result(PasteStatus.ClipboardChanged, "Буфер обмена изменён другим приложением. Вставка остановлена без перезаписи новых данных.");
    }

    private static PasteResult StopForAcceptance(AcceptanceOutcome outcome, OperationState state) =>
        state.Result(
            outcome == AcceptanceOutcome.TimedOut ? PasteStatus.AcceptanceTimedOut : PasteStatus.TargetChanged,
            outcome == AcceptanceOutcome.TimedOut
                ? "Получатель не подтвердил приём вовремя. Проверьте черновик перед повтором."
                : "Активное окно или поле ввода изменилось во время ожидания.");

    private static string? ValidatePackage(PreparedPastePackage package, PasteResumeToken? resume)
    {
        if (package.ExportId == Guid.Empty) return "У подготовленного пакета отсутствует export ID.";
        if (package.ImagePaths.Count == 0) return "В пакете нет изображений.";
        if (package.ImagePaths.Any(path => !Path.IsPathFullyQualified(path) || !string.Equals(Path.GetExtension(path), ".png", StringComparison.OrdinalIgnoreCase) || !File.Exists(path)))
            return "Все изображения должны быть существующими PNG с абсолютными путями.";
        if (resume is not null && (resume.ExportId != package.ExportId || resume.ConfirmedImageCount < 0 || resume.ConfirmedImageCount > package.ImagePaths.Count || resume.TextConfirmed))
            return "Точка продолжения не относится к этому экспорту или уже завершена.";
        return null;
    }

    private static async Task<AcceptanceOutcome> WithTimeoutAsync(
        Func<CancellationToken, Task<AcceptanceOutcome>> wait,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        using var timeoutSource = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeoutSource.CancelAfter(timeout);
        try { return await wait(timeoutSource.Token); }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested) { return AcceptanceOutcome.TimedOut; }
    }

    private static async Task<PackageAcceptanceOutcome> WithPackageTimeoutAsync(
        Func<CancellationToken, Task<PackageAcceptanceOutcome>> wait,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        using var timeoutSource = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeoutSource.CancelAfter(timeout);
        try { return await wait(timeoutSource.Token); }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            return new(AcceptanceOutcome.TimedOut, AcceptanceOutcome.TimedOut);
        }
    }

    private async Task RestoreWhenSafeAsync(TargetProfile profile, ClipboardSnapshot original, ClipboardWriteReceipt current, PasteResult result, CancellationToken cancellationToken)
    {
        if (profile.RestoreClipboardWhenSafe && result.Status == PasteStatus.CompletedVerified)
            await clipboard.RestoreIfCurrentAsync(original, current, cancellationToken);
    }

    private sealed class OperationState
    {
        public OperationState(Guid exportId, PasteResumeToken? resume)
        {
            ExportId = exportId;
            SafeResumePrefix = resume?.ConfirmedImageCount ?? 0;
            ImagesConfirmed = SafeResumePrefix;
            ImagesDispatched = SafeResumePrefix;
        }

        public Guid ExportId { get; }
        public int ImagesDispatched { get; set; }
        public int ImagesConfirmed { get; set; }
        public int SafeResumePrefix { get; set; }
        public bool TextDispatched { get; set; }
        public bool TextConfirmed { get; set; }
        public bool CanResume { get; set; } = true;

        public PasteResult Result(PasteStatus status, string message, Exception? error = null)
        {
            var token = CanResume && SafeResumePrefix > 0 && !TextConfirmed
                ? new PasteResumeToken(ExportId, SafeResumePrefix, false)
                : null;
            return new(status, ImagesDispatched, ImagesConfirmed, TextDispatched, TextConfirmed, token, message, error);
        }

        public PasteProgress Progress(PastePhase phase, int total, string message) =>
            new(phase, ImagesDispatched, ImagesConfirmed, total, TextDispatched, TextConfirmed, message);
    }
}
