namespace Snapik.Windows;

public sealed class CodexDesktopPasteCompletionService : ICodexDesktopPasteCompletionService
{
    private static readonly TimeSpan DefaultSettlementDelay = TimeSpan.FromMilliseconds(500);
    private static readonly TimeSpan DefaultImageSettlementDelay = TimeSpan.FromMilliseconds(700);
    private static readonly TimeSpan DefaultAltVImageSettlementDelay = TimeSpan.FromMilliseconds(1200);

    private readonly IClipboardService clipboard;
    private readonly IForegroundTargetService foreground;
    private readonly IGuardedInputInjector input;
    private readonly TimeSpan settlementDelay;
    private readonly TimeSpan imageSettlementDelay;
    private readonly TimeSpan altVImageSettlementDelay;

    public CodexDesktopPasteCompletionService(
        IClipboardService clipboard,
        IForegroundTargetService foreground,
        IGuardedInputInjector input,
        TimeSpan? settlementDelay = null,
        TimeSpan? imageSettlementDelay = null,
        TimeSpan? altVImageSettlementDelay = null)
    {
        this.clipboard = clipboard ?? throw new ArgumentNullException(nameof(clipboard));
        this.foreground = foreground ?? throw new ArgumentNullException(nameof(foreground));
        this.input = input ?? throw new ArgumentNullException(nameof(input));
        this.settlementDelay = settlementDelay ?? DefaultSettlementDelay;
        this.imageSettlementDelay = imageSettlementDelay ?? DefaultImageSettlementDelay;
        this.altVImageSettlementDelay = altVImageSettlementDelay ?? DefaultAltVImageSettlementDelay;
        if (this.settlementDelay < TimeSpan.Zero) throw new ArgumentOutOfRangeException(nameof(settlementDelay));
        if (this.imageSettlementDelay < TimeSpan.Zero) throw new ArgumentOutOfRangeException(nameof(imageSettlementDelay));
        if (this.altVImageSettlementDelay < TimeSpan.Zero) throw new ArgumentOutOfRangeException(nameof(altVImageSettlementDelay));
    }

    public async Task<CodexPasteCompletionResult> CompleteAsync(
        PasteIntentObserved intent,
        ClipboardWriteReceipt ownedPackageReceipt,
        string immutablePromptText,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(intent);
        ArgumentNullException.ThrowIfNull(immutablePromptText);

        // This executes synchronously before the first await so the focused child is
        // captured at the physical paste intent, not after the settlement delay.
        var target = foreground.Capture();
        if (intent.Gesture != HotkeyGesture.CtrlV ||
            intent.IsIntercepted ||
            !target.IsUsable ||
            target.WindowHandle != intent.ForegroundWindowHandle ||
            target.ProcessId != intent.ForegroundProcessId ||
            !foreground.Matches(target, TargetProfiles.CodexDesktop))
        {
            return Result(CodexPasteCompletionStatus.NotApplicable, "Paste completion applies only to a physical Ctrl+V in Codex Desktop.");
        }

        if (intent.ClipboardSequenceNumber != ownedPackageReceipt.SequenceNumber)
            return Result(CodexPasteCompletionStatus.StaleIntent, "The paste intent does not refer to Snapik's current package.");

        // A package whose captures carry no notes has no text step: the user's own Ctrl+V already
        // delivered the images, so there is nothing left to dispatch and nothing failed.
        if (immutablePromptText.Length == 0)
            return Result(CodexPasteCompletionStatus.CompletedUnverified, "The package has no prompt text; the images were pasted by the user.");

        ClipboardWriteReceipt? textReceipt = null;
        try
        {
            await Task.Delay(settlementDelay, cancellationToken);
            if (!await clipboard.IsCurrentAsync(ownedPackageReceipt, cancellationToken))
                return Result(CodexPasteCompletionStatus.ClipboardChanged, "The clipboard changed before the text paste.");
            if (!foreground.IsSame(target))
                return Result(CodexPasteCompletionStatus.TargetLost, "Codex focus changed before the text paste.");

            textReceipt = await clipboard.SetTextGuardedAsync(
                immutablePromptText,
                ownedPackageReceipt.SequenceNumber,
                cancellationToken);

            var rejectedStatus = CodexPasteCompletionStatus.ClipboardChanged;
            var dispatched = await input.SendGuardedAsync(
                HotkeyGesture.CtrlV,
                async guardCancellationToken =>
                {
                    if (!await clipboard.IsCurrentAsync(textReceipt.Value, guardCancellationToken))
                    {
                        rejectedStatus = CodexPasteCompletionStatus.ClipboardChanged;
                        return false;
                    }
                    if (!foreground.IsSame(target))
                    {
                        rejectedStatus = CodexPasteCompletionStatus.TargetLost;
                        return false;
                    }
                    return true;
                },
                cancellationToken);
            if (!dispatched)
            {
                var message = rejectedStatus == CodexPasteCompletionStatus.TargetLost
                    ? "Codex focus changed while the paste keys were being released."
                    : "The clipboard changed while the paste keys were being released.";
                return Result(rejectedStatus, message, textReceipt);
            }
            return Result(
                CodexPasteCompletionStatus.CompletedUnverified,
                "Prompt text paste was dispatched to Codex; receiver acceptance was not observable.",
                textReceipt);
        }
        catch (ClipboardChangedException ex)
        {
            return Result(CodexPasteCompletionStatus.ClipboardChanged, ex.Message, textReceipt, ex);
        }
        catch (OperationCanceledException ex) when (cancellationToken.IsCancellationRequested)
        {
            return Result(CodexPasteCompletionStatus.Cancelled, "The guarded text paste was cancelled.", textReceipt, ex);
        }
        catch (Exception ex)
        {
            return Result(CodexPasteCompletionStatus.Failed, $"The guarded text paste failed: {ex.Message}", textReceipt, ex);
        }
    }

    public async Task<CodexPasteCompletionResult> CompleteSequentialAsync(
        PasteIntentObserved intent,
        ClipboardWriteReceipt ownedPackageReceipt,
        IReadOnlyList<string> immutableImagePaths,
        string immutablePromptText,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(intent);
        ArgumentNullException.ThrowIfNull(immutableImagePaths);
        ArgumentNullException.ThrowIfNull(immutablePromptText);

        var target = foreground.Capture();
        if (!intent.IsIntercepted ||
            (intent.Gesture != HotkeyGesture.CtrlV && intent.Gesture != HotkeyGesture.AltV) ||
            !target.IsUsable ||
            target.WindowHandle != intent.ForegroundWindowHandle ||
            target.ProcessId != intent.ForegroundProcessId ||
            foreground.Matches(target, TargetProfiles.CodexDesktop))
        {
            return Result(CodexPasteCompletionStatus.NotApplicable, "Intercepted paste completion applies only to a physical Ctrl+V or Alt+V outside Codex Desktop.");
        }

        if (intent.ClipboardSequenceNumber != ownedPackageReceipt.SequenceNumber)
            return Result(CodexPasteCompletionStatus.StaleIntent, "The paste intent does not refer to Snapik's current package.");
        if (immutableImagePaths.Count == 0)
            return Result(CodexPasteCompletionStatus.NothingToDispatch, "The package needs at least one image.");

        var imageGesture = intent.Gesture;
        var perImageDelay = imageGesture == HotkeyGesture.AltV ? altVImageSettlementDelay : imageSettlementDelay;

        ClipboardWriteReceipt? currentReceipt = null;
        ClipboardWriteReceipt? textReceipt = null;
        try
        {
            var expectedSequenceNumber = ownedPackageReceipt.SequenceNumber;
            for (var imageIndex = 0; imageIndex < immutableImagePaths.Count; imageIndex++)
            {
                // Chromium (Claude Desktop) and Claude Code's clipboard readers detect an image
                // through CF_DIB/CF_BITMAP; a registered "PNG"-only data object is invisible to
                // them, so the image paste was a no-op and only the text arrived. Publish the
                // standard bitmap formats alongside PNG for every per-image paste.
                currentReceipt = await clipboard.SetPngGuardedAsync(
                    immutableImagePaths[imageIndex],
                    expectedSequenceNumber,
                    cancellationToken);
                expectedSequenceNumber = currentReceipt.Value.SequenceNumber;

                var imageRejectedStatus = CodexPasteCompletionStatus.ClipboardChanged;
                if (!await SendGuardedAsync(imageGesture, target, currentReceipt.Value, status => imageRejectedStatus = status, cancellationToken))
                    return GuardRejectedResult(imageRejectedStatus, $"image {imageIndex + 1}", currentReceipt);

                await Task.Delay(perImageDelay, cancellationToken);
                if (!await clipboard.IsCurrentAsync(currentReceipt.Value, cancellationToken))
                    return Result(CodexPasteCompletionStatus.ClipboardChanged, $"The clipboard changed after image {imageIndex + 1} paste.", currentReceipt);
                if (!foreground.IsSame(target))
                    return Result(CodexPasteCompletionStatus.TargetLost, $"Focus changed after image {imageIndex + 1} paste.", currentReceipt);
            }

            // A package without notes has no text step; the images are the whole package.
            if (immutablePromptText.Length == 0)
                return Result(
                    CodexPasteCompletionStatus.CompletedUnverified,
                    "Image paste shortcuts were dispatched in order; the package has no prompt text.",
                    currentReceipt);

            // The terminal pastes text with Ctrl+V even when Alt+V is the image shortcut.
            textReceipt = await clipboard.SetTextGuardedAsync(
                immutablePromptText,
                currentReceipt!.Value.SequenceNumber,
                cancellationToken);
            var rejectedStatus = CodexPasteCompletionStatus.ClipboardChanged;
            if (!await SendGuardedAsync(HotkeyGesture.CtrlV, target, textReceipt.Value, status => rejectedStatus = status, cancellationToken))
                return GuardRejectedResult(rejectedStatus, "text", textReceipt);

            return Result(
                CodexPasteCompletionStatus.CompletedUnverified,
                "Image and prompt paste shortcuts were dispatched in order; receiver acceptance was not observable.",
                textReceipt);
        }
        catch (ClipboardChangedException ex)
        {
            return Result(CodexPasteCompletionStatus.ClipboardChanged, ex.Message, textReceipt ?? currentReceipt, ex);
        }
        catch (OperationCanceledException ex) when (cancellationToken.IsCancellationRequested)
        {
            return Result(CodexPasteCompletionStatus.Cancelled, "The guarded sequential paste was cancelled.", textReceipt ?? currentReceipt, ex);
        }
        catch (Exception ex)
        {
            return Result(CodexPasteCompletionStatus.Failed, $"The guarded sequential paste failed: {ex.Message}", textReceipt ?? currentReceipt, ex);
        }
    }

    /// <summary>Backward-compatible name for <see cref="CompleteSequentialAsync"/>.</summary>
    public Task<CodexPasteCompletionResult> CompleteClaudeAsync(
        PasteIntentObserved intent,
        ClipboardWriteReceipt ownedPackageReceipt,
        IReadOnlyList<string> immutableImagePaths,
        string immutablePromptText,
        CancellationToken cancellationToken = default) =>
        CompleteSequentialAsync(intent, ownedPackageReceipt, immutableImagePaths, immutablePromptText, cancellationToken);

    private async Task<bool> SendGuardedAsync(
        HotkeyGesture gesture,
        TargetSnapshot target,
        ClipboardWriteReceipt receipt,
        Action<CodexPasteCompletionStatus> reject,
        CancellationToken cancellationToken) => await input.SendGuardedAsync(
            gesture,
            async guardCancellationToken =>
            {
                if (!await clipboard.IsCurrentAsync(receipt, guardCancellationToken))
                {
                    reject(CodexPasteCompletionStatus.ClipboardChanged);
                    return false;
                }
                if (!foreground.IsSame(target))
                {
                    reject(CodexPasteCompletionStatus.TargetLost);
                    return false;
                }
                return true;
            },
            cancellationToken);

    private static CodexPasteCompletionResult GuardRejectedResult(
        CodexPasteCompletionStatus status,
        string stage,
        ClipboardWriteReceipt? textReceipt)
    {
        var reason = status == CodexPasteCompletionStatus.TargetLost
            ? "Claude focus changed"
            : "The clipboard changed";
        return Result(status, $"{reason} while the {stage} paste keys were being released.", textReceipt);
    }

    private static CodexPasteCompletionResult Result(
        CodexPasteCompletionStatus status,
        string message,
        ClipboardWriteReceipt? receipt = null,
        Exception? error = null) => new(status, message, receipt, error);
}
