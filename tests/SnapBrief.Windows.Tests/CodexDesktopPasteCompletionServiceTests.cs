namespace SnapBrief.Windows.Tests;

public sealed class CodexDesktopPasteCompletionServiceTests
{
    private static readonly TargetSnapshot Codex = new(101, 202, 303, "ChatGPT", "ChatGPT");

    [Fact]
    public async Task PhysicalCodexCtrlV_StagesAndDispatchesImmutableText_Unverified()
    {
        var clipboard = new FakeClipboard(41);
        var target = new FakeTarget(Codex);
        var input = new FakeInput();
        var service = Create(clipboard, target, input);

        var result = await service.CompleteAsync(Intent(41), new ClipboardWriteReceipt(41), "Снимок A.");

        Assert.Equal(CodexPasteCompletionStatus.CompletedUnverified, result.Status);
        Assert.Equal("Снимок A.", clipboard.WrittenText);
        Assert.Equal(new ClipboardWriteReceipt(42), result.TextClipboardReceipt);
        Assert.Equal([HotkeyGesture.CtrlV], input.Gestures);
        Assert.False(result.Message.Contains("accepted", StringComparison.OrdinalIgnoreCase));
    }

    [Theory]
    [InlineData(1)]
    [InlineData(3)]
    public async Task InterceptedCtrlVInArbitraryApp_DispatchesOrderedPngImagesThenImmutableTextViaCtrlV(int imageCount)
    {
        // Any foreground application (not just a built-in profile) can receive the
        // sequential paste path once its physical Ctrl+V was intercepted.
        var grokBot = new TargetSnapshot(101, 202, 303, "GrokBot", "GrokBot");
        var clipboard = new FakeClipboard(41);
        var target = new FakeTarget(grokBot);
        var input = new FakeInput();
        var service = Create(clipboard, target, input);
        var paths = Enumerable.Range(0, imageCount).Select(index => $@"C:\shots\{index}.png").ToArray();
        var intent = new PasteIntentObserved(
            HotkeyGesture.CtrlV,
            grokBot.WindowHandle,
            grokBot.ProcessId,
            41,
            DateTimeOffset.UtcNow,
            IsIntercepted: true);

        var result = await service.CompleteSequentialAsync(
            intent,
            new ClipboardWriteReceipt(41),
            paths,
            "Снимок A.");

        Assert.Equal(CodexPasteCompletionStatus.CompletedUnverified, result.Status);
        Assert.Equal(paths.Concat(["TEXT"]), clipboard.Writes);
        Assert.Equal("Снимок A.", clipboard.WrittenText);
        Assert.Equal(new ClipboardWriteReceipt((uint)(42 + imageCount)), result.TextClipboardReceipt);
        Assert.Equal(imageCount + 1, input.Gestures.Count);
        Assert.All(input.Gestures, gesture => Assert.Equal(HotkeyGesture.CtrlV, gesture));
        Assert.False(result.Message.Contains("accepted", StringComparison.OrdinalIgnoreCase));
    }

    [Theory]
    [InlineData(1)]
    [InlineData(3)]
    public async Task InterceptedAltVInTerminal_DispatchesOrderedPngImagesViaAltVThenTextViaCtrlV(int imageCount)
    {
        // A terminal hosting Claude Code pastes images with Alt+V but text always with Ctrl+V.
        var terminal = new TargetSnapshot(101, 202, 303, "WindowsTerminal", "WindowsTerminal");
        var clipboard = new FakeClipboard(41);
        var target = new FakeTarget(terminal);
        var input = new FakeInput();
        var service = Create(clipboard, target, input);
        var paths = Enumerable.Range(0, imageCount).Select(index => $@"C:\shots\{index}.png").ToArray();
        var intent = new PasteIntentObserved(
            HotkeyGesture.AltV,
            terminal.WindowHandle,
            terminal.ProcessId,
            41,
            DateTimeOffset.UtcNow,
            IsIntercepted: true);

        var result = await service.CompleteSequentialAsync(
            intent,
            new ClipboardWriteReceipt(41),
            paths,
            "Снимок A.");

        Assert.Equal(CodexPasteCompletionStatus.CompletedUnverified, result.Status);
        Assert.Equal(paths.Concat(["TEXT"]), clipboard.Writes);
        Assert.Equal("Снимок A.", clipboard.WrittenText);
        Assert.Equal(imageCount + 1, input.Gestures.Count);
        Assert.All(input.Gestures.Take(imageCount), gesture => Assert.Equal(HotkeyGesture.AltV, gesture));
        Assert.Equal(HotkeyGesture.CtrlV, input.Gestures[^1]);
    }

    [Fact]
    public async Task UninterceptedIntent_DoesNotWriteOrInject()
    {
        var grokBot = new TargetSnapshot(101, 202, 303, "GrokBot", "GrokBot");
        var clipboard = new FakeClipboard(41);
        var input = new FakeInput();
        var intent = new PasteIntentObserved(HotkeyGesture.CtrlV, 101, 303, 41, DateTimeOffset.UtcNow);

        var result = await Create(clipboard, new FakeTarget(grokBot), input)
            .CompleteSequentialAsync(intent, new ClipboardWriteReceipt(41), [@"C:\shots\0.png"], "text");

        Assert.Equal(CodexPasteCompletionStatus.NotApplicable, result.Status);
        Assert.Empty(clipboard.Writes);
        Assert.Null(clipboard.WrittenText);
        Assert.Empty(input.Gestures);
    }

    [Fact]
    public async Task InterceptedCodexDesktopIntent_StaysOnUnobservedCompleteAsyncPath_DoesNotWriteOrInject()
    {
        // Codex Desktop keeps its original CompleteAsync path even if something upstream
        // marks the intent as intercepted; CompleteSequentialAsync must refuse it.
        var intent = Intent(41) with { IsIntercepted = true };
        var clipboard = new FakeClipboard(41);
        var input = new FakeInput();

        var result = await Create(clipboard, new FakeTarget(Codex), input)
            .CompleteSequentialAsync(intent, new ClipboardWriteReceipt(41), [@"C:\shots\0.png"], "text");

        Assert.Equal(CodexPasteCompletionStatus.NotApplicable, result.Status);
        Assert.Empty(clipboard.Writes);
        Assert.Null(clipboard.WrittenText);
        Assert.Empty(input.Gestures);
    }

    [Fact]
    public async Task FocusChangeDuringPhysicalRelease_StopsBeforeAnyPasteShortcut()
    {
        var grokBot = new TargetSnapshot(101, 202, 303, "GrokBot", "GrokBot");
        var clipboard = new FakeClipboard(41);
        var target = new FakeTarget(grokBot);
        var input = new FakeInput
        {
            BeforeFinalGuard = () => target.Current = new TargetSnapshot(900, 901, 902, "Other", "Other")
        };
        var intent = new PasteIntentObserved(HotkeyGesture.CtrlV, 101, 303, 41, DateTimeOffset.UtcNow, IsIntercepted: true);

        var result = await Create(clipboard, target, input)
            .CompleteSequentialAsync(intent, new ClipboardWriteReceipt(41), [@"C:\shots\0.png"], "text");

        Assert.Equal(CodexPasteCompletionStatus.TargetLost, result.Status);
        Assert.Equal(new ClipboardWriteReceipt(42), result.CurrentClipboardReceipt);
        Assert.Equal([@"C:\shots\0.png"], clipboard.Writes);
        Assert.Null(clipboard.WrittenText);
        Assert.Empty(input.Gestures);
    }

    [Fact]
    public async Task FocusLossAfterFirstImagePaste_ReturnsCurrentReceiptAndStopsSequence()
    {
        var grokBot = new TargetSnapshot(101, 202, 303, "GrokBot", "GrokBot");
        var clipboard = new FakeClipboard(41);
        var target = new FakeTarget(grokBot) { LoseFocusAfterFirstSameCheck = true };
        var input = new FakeInput();
        var intent = new PasteIntentObserved(HotkeyGesture.CtrlV, 101, 303, 41, DateTimeOffset.UtcNow, IsIntercepted: true);

        var result = await Create(clipboard, target, input)
            .CompleteSequentialAsync(intent, new ClipboardWriteReceipt(41), [@"C:\shots\0.png"], "text");

        Assert.Equal(CodexPasteCompletionStatus.TargetLost, result.Status);
        Assert.Equal(new ClipboardWriteReceipt(42), result.CurrentClipboardReceipt);
        Assert.Equal([HotkeyGesture.CtrlV], input.Gestures);
        Assert.Equal([@"C:\shots\0.png"], clipboard.Writes);
        Assert.Null(clipboard.WrittenText);
    }

    [Fact]
    public async Task ClipboardChangeAfterFirstImagePaste_StopsBeforeSecondImageAndText()
    {
        var grokBot = new TargetSnapshot(101, 202, 303, "GrokBot", "GrokBot");
        var clipboard = new FakeClipboard(41);
        var input = new FakeInput { AfterDispatch = clipboard.ExternalWrite };
        var intent = new PasteIntentObserved(HotkeyGesture.CtrlV, 101, 303, 41, DateTimeOffset.UtcNow, IsIntercepted: true);

        var result = await Create(clipboard, new FakeTarget(grokBot), input)
            .CompleteSequentialAsync(intent, new ClipboardWriteReceipt(41), [@"C:\shots\0.png", @"C:\shots\1.png"], "text");

        Assert.Equal(CodexPasteCompletionStatus.ClipboardChanged, result.Status);
        Assert.Equal(new ClipboardWriteReceipt(42), result.CurrentClipboardReceipt);
        Assert.Equal([@"C:\shots\0.png"], clipboard.Writes);
        Assert.Single(input.Gestures);
        Assert.Null(clipboard.WrittenText);
    }

    [Fact]
    public async Task CancellationAfterFirstImagePaste_ReturnsCurrentReceiptWithoutContinuing()
    {
        var grokBot = new TargetSnapshot(101, 202, 303, "GrokBot", "GrokBot");
        var clipboard = new FakeClipboard(41);
        using var cancellation = new CancellationTokenSource();
        var input = new FakeInput { AfterDispatch = cancellation.Cancel };
        var intent = new PasteIntentObserved(HotkeyGesture.CtrlV, 101, 303, 41, DateTimeOffset.UtcNow, IsIntercepted: true);
        var service = new CodexDesktopPasteCompletionService(
            clipboard,
            new FakeTarget(grokBot),
            input,
            TimeSpan.FromSeconds(1),
            TimeSpan.FromSeconds(1),
            TimeSpan.FromSeconds(1));

        var result = await service.CompleteSequentialAsync(
            intent,
            new ClipboardWriteReceipt(41),
            [@"C:\shots\0.png", @"C:\shots\1.png"],
            "text",
            cancellation.Token);

        Assert.Equal(CodexPasteCompletionStatus.Cancelled, result.Status);
        Assert.Equal(new ClipboardWriteReceipt(42), result.CurrentClipboardReceipt);
        Assert.Equal([@"C:\shots\0.png"], clipboard.Writes);
        Assert.Single(input.Gestures);
        Assert.Null(clipboard.WrittenText);
    }

    [Fact]
    public async Task InterceptedIntent_IsNotAlsoHandledByCodexCompletion()
    {
        var clipboard = new FakeClipboard(41);
        var input = new FakeInput();
        var intent = Intent(41) with { IsIntercepted = true };

        var result = await Create(clipboard, new FakeTarget(Codex), input)
            .CompleteAsync(intent, new ClipboardWriteReceipt(41), "text");

        Assert.Equal(CodexPasteCompletionStatus.NotApplicable, result.Status);
        Assert.Null(clipboard.WrittenText);
        Assert.Empty(input.Gestures);
    }

    [Theory]
    [InlineData("Code", 101u, 202L)]
    [InlineData("ChatGPT", 999u, 202L)]
    [InlineData("ChatGPT", 101u, 999L)]
    public async Task UnknownOrMismatchedTarget_IsNotApplicableAndDoesNotInject(string process, uint processId, long window)
    {
        var clipboard = new FakeClipboard(41);
        var input = new FakeInput();
        var target = new FakeTarget(new TargetSnapshot((nint)window, 202, processId, process, process));
        var result = await Create(clipboard, target, input).CompleteAsync(Intent(41), new ClipboardWriteReceipt(41), "text");

        Assert.Equal(CodexPasteCompletionStatus.NotApplicable, result.Status);
        Assert.Null(clipboard.WrittenText);
        Assert.Empty(input.Gestures);
    }

    [Fact]
    public async Task StaleIntentSequence_DoesNotWriteOrInject()
    {
        var clipboard = new FakeClipboard(42);
        var input = new FakeInput();
        var result = await Create(clipboard, new FakeTarget(Codex), input)
            .CompleteAsync(Intent(41), new ClipboardWriteReceipt(42), "text");

        Assert.Equal(CodexPasteCompletionStatus.StaleIntent, result.Status);
        Assert.Null(clipboard.WrittenText);
        Assert.Empty(input.Gestures);
    }

    [Fact]
    public async Task FocusChangeDuringSettlement_DoesNotWriteOrInject()
    {
        var clipboard = new FakeClipboard(41);
        var target = new FakeTarget(Codex) { Same = false };
        var input = new FakeInput();
        var result = await Create(clipboard, target, input)
            .CompleteAsync(Intent(41), new ClipboardWriteReceipt(41), "text");

        Assert.Equal(CodexPasteCompletionStatus.TargetLost, result.Status);
        Assert.Null(clipboard.WrittenText);
        Assert.Empty(input.Gestures);
    }

    [Fact]
    public async Task ClipboardChangeDuringSettlement_DoesNotWriteOrInject()
    {
        var clipboard = new FakeClipboard(42);
        var input = new FakeInput();
        var result = await Create(clipboard, new FakeTarget(Codex), input)
            .CompleteAsync(Intent(41), new ClipboardWriteReceipt(41), "text");

        Assert.Equal(CodexPasteCompletionStatus.ClipboardChanged, result.Status);
        Assert.Null(clipboard.WrittenText);
        Assert.Empty(input.Gestures);
    }

    [Fact]
    public async Task FocusLossAfterTextWrite_ReturnsReceiptButDoesNotInject()
    {
        var clipboard = new FakeClipboard(41);
        var target = new FakeTarget(Codex) { LoseFocusAfterFirstSameCheck = true };
        var input = new FakeInput();
        var result = await Create(clipboard, target, input)
            .CompleteAsync(Intent(41), new ClipboardWriteReceipt(41), "text");

        Assert.Equal(CodexPasteCompletionStatus.TargetLost, result.Status);
        Assert.Equal(new ClipboardWriteReceipt(42), result.TextClipboardReceipt);
        Assert.Empty(input.Gestures);
    }

    [Fact]
    public async Task GuardedClipboardWriteFailure_IsReportedAndDoesNotInject()
    {
        var clipboard = new FakeClipboard(41) { FailWrite = true };
        var input = new FakeInput();
        var result = await Create(clipboard, new FakeTarget(Codex), input)
            .CompleteAsync(Intent(41), new ClipboardWriteReceipt(41), "text");

        Assert.Equal(CodexPasteCompletionStatus.ClipboardChanged, result.Status);
        Assert.Empty(input.Gestures);
    }

    [Fact]
    public async Task ClipboardChangeAfterTextWrite_ReturnsReceiptButDoesNotInject()
    {
        var clipboard = new FakeClipboard(41) { ChangeAfterWrite = true };
        var input = new FakeInput();
        var result = await Create(clipboard, new FakeTarget(Codex), input)
            .CompleteAsync(Intent(41), new ClipboardWriteReceipt(41), "text");

        Assert.Equal(CodexPasteCompletionStatus.ClipboardChanged, result.Status);
        Assert.Equal(new ClipboardWriteReceipt(42), result.TextClipboardReceipt);
        Assert.Empty(input.Gestures);
    }

    [Fact]
    public async Task FocusChangeDuringPhysicalReleaseWait_PreventsDispatch()
    {
        var clipboard = new FakeClipboard(41);
        var target = new FakeTarget(Codex);
        var input = new FakeInput
        {
            BeforeFinalGuard = () => target.Current = new TargetSnapshot(900, 901, 902, "Other", "Other")
        };
        var result = await Create(clipboard, target, input)
            .CompleteAsync(Intent(41), new ClipboardWriteReceipt(41), "text");

        Assert.Equal(CodexPasteCompletionStatus.TargetLost, result.Status);
        Assert.Equal(new ClipboardWriteReceipt(42), result.TextClipboardReceipt);
        Assert.Empty(input.Gestures);
    }

    [Fact]
    public async Task ClipboardChangeDuringPhysicalReleaseWait_PreventsDispatch()
    {
        var clipboard = new FakeClipboard(41);
        var input = new FakeInput { BeforeFinalGuard = clipboard.ExternalWrite };
        var result = await Create(clipboard, new FakeTarget(Codex), input)
            .CompleteAsync(Intent(41), new ClipboardWriteReceipt(41), "text");

        Assert.Equal(CodexPasteCompletionStatus.ClipboardChanged, result.Status);
        Assert.Equal(new ClipboardWriteReceipt(42), result.TextClipboardReceipt);
        Assert.Empty(input.Gestures);
    }

    [Fact]
    public async Task AltVAndEmptyPrompt_DoNotInject()
    {
        var clipboard = new FakeClipboard(41);
        var input = new FakeInput();
        var service = Create(clipboard, new FakeTarget(Codex), input);

        var alt = await service.CompleteAsync(Intent(41) with { Gesture = HotkeyGesture.AltV }, new ClipboardWriteReceipt(41), "text");
        var empty = await service.CompleteAsync(Intent(41), new ClipboardWriteReceipt(41), string.Empty);

        Assert.Equal(CodexPasteCompletionStatus.NotApplicable, alt.Status);
        Assert.Equal(CodexPasteCompletionStatus.NothingToDispatch, empty.Status);
        Assert.Empty(input.Gestures);
    }

    private static CodexDesktopPasteCompletionService Create(FakeClipboard clipboard, FakeTarget target, FakeInput input) =>
        new(clipboard, target, input, TimeSpan.Zero, TimeSpan.Zero, TimeSpan.Zero);

    private static PasteIntentObserved Intent(uint sequence) =>
        new(HotkeyGesture.CtrlV, Codex.WindowHandle, Codex.ProcessId, sequence, DateTimeOffset.UtcNow);

    private sealed class FakeClipboard(uint sequence) : IClipboardService
    {
        private uint currentSequence = sequence;
        public List<string> Writes { get; } = [];
        public string? WrittenText { get; private set; }
        public bool FailWrite { get; set; }
        public bool ChangeAfterWrite { get; set; }
        public Task<ClipboardSnapshot> CaptureAsync(CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<ClipboardWriteReceipt> SetPackageGuardedAsync(IReadOnlyList<string> pngPaths, string text, uint expectedSequenceNumber, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<ClipboardWriteReceipt> SetPngOnlyGuardedAsync(string pngPath, uint expectedSequenceNumber, CancellationToken cancellationToken)
        {
            if (FailWrite || expectedSequenceNumber != currentSequence) throw new ClipboardChangedException();
            Writes.Add(pngPath);
            var receipt = new ClipboardWriteReceipt(++currentSequence);
            if (ChangeAfterWrite) currentSequence++;
            return Task.FromResult(receipt);
        }
        public Task<ClipboardWriteReceipt> SetPngGuardedAsync(string pngPath, uint expectedSequenceNumber, CancellationToken cancellationToken)
        {
            if (FailWrite || expectedSequenceNumber != currentSequence) throw new ClipboardChangedException();
            Writes.Add(pngPath);
            var receipt = new ClipboardWriteReceipt(++currentSequence);
            if (ChangeAfterWrite) currentSequence++;
            return Task.FromResult(receipt);
        }
        public Task<ClipboardWriteReceipt> SetTextGuardedAsync(string text, uint expectedSequenceNumber, CancellationToken cancellationToken)
        {
            if (FailWrite || expectedSequenceNumber != currentSequence) throw new ClipboardChangedException();
            WrittenText = text;
            Writes.Add("TEXT");
            var receipt = new ClipboardWriteReceipt(++currentSequence);
            if (ChangeAfterWrite) currentSequence++;
            return Task.FromResult(receipt);
        }
        public Task<bool> IsCurrentAsync(ClipboardWriteReceipt receipt, CancellationToken cancellationToken) => Task.FromResult(receipt.SequenceNumber == currentSequence);
        public Task<bool> RestoreIfCurrentAsync(ClipboardSnapshot snapshot, ClipboardWriteReceipt receipt, CancellationToken cancellationToken) => throw new NotSupportedException();
        public void ExternalWrite() => currentSequence++;
    }

    private sealed class FakeTarget(TargetSnapshot initial) : IForegroundTargetService
    {
        private int sameChecks;
        public TargetSnapshot Current { get; set; } = initial;
        public bool Same { get; set; } = true;
        public bool LoseFocusAfterFirstSameCheck { get; set; }
        public TargetSnapshot Capture() => Current;
        public bool IsSame(TargetSnapshot expected)
        {
            sameChecks++;
            if (!Same) return false;
            if (LoseFocusAfterFirstSameCheck && sameChecks > 1) return false;
            return expected == Current;
        }
        public bool Matches(TargetSnapshot target, TargetProfile profile) => profile.AllowedProcessNames.Contains(target.ProcessName);
    }

    private sealed class FakeInput : IGuardedInputInjector
    {
        public List<HotkeyGesture> Gestures { get; } = [];
        public Action? BeforeFinalGuard { get; set; }
        public Action? AfterDispatch { get; set; }
        public Task SendAsync(HotkeyGesture gesture, CancellationToken cancellationToken)
        {
            Gestures.Add(gesture);
            return Task.CompletedTask;
        }

        public async Task<bool> SendGuardedAsync(HotkeyGesture gesture, Func<CancellationToken, ValueTask<bool>> finalGuard, CancellationToken cancellationToken)
        {
            BeforeFinalGuard?.Invoke();
            if (!await finalGuard(cancellationToken)) return false;
            Gestures.Add(gesture);
            AfterDispatch?.Invoke();
            return true;
        }
    }
}
