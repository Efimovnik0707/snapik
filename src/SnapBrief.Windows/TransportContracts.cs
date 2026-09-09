namespace SnapBrief.Windows;

public sealed record PreparedPastePackage(
    Guid ExportId,
    IReadOnlyList<string> ImagePaths,
    string PromptText);

[Flags]
public enum HotkeyModifiers : uint
{
    None = 0,
    Alt = 0x0001,
    Control = 0x0002,
    Shift = 0x0004,
    Windows = 0x0008,
    NoRepeat = 0x4000,
}

public readonly record struct HotkeyGesture(HotkeyModifiers Modifiers, ushort VirtualKey)
{
    public const ushort EnterVirtualKey = 0x0D;

    public static HotkeyGesture CtrlV => new(HotkeyModifiers.Control, 0x56);
    public static HotkeyGesture CtrlShiftV => new(HotkeyModifiers.Control | HotkeyModifiers.Shift, 0x56);
    public static HotkeyGesture AltV => new(HotkeyModifiers.Alt, 0x56);

    public bool ContainsEnter => VirtualKey == EnterVirtualKey;
}

public enum PasteTransport
{
    SingleClipboardPackage,
    StagedSequence,
}

public enum ProfileVerification
{
    Unverified,
    Experimental,
    Verified,
}

public sealed record TargetProfile(
    string Id,
    string DisplayName,
    PasteTransport Transport,
    HotkeyGesture ImagePasteGesture,
    HotkeyGesture TextPasteGesture,
    IReadOnlySet<string> AllowedProcessNames,
    TimeSpan AcceptanceTimeout,
    TimeSpan UnobservableSettlementDelay,
    ProfileVerification Verification,
    string? VerifiedVersion = null,
    bool RestoreClipboardWhenSafe = false)
{
    public void Validate()
    {
        if (string.IsNullOrWhiteSpace(Id) || string.IsNullOrWhiteSpace(DisplayName))
            throw new ArgumentException("A target profile needs an id and display name.");
        if (ImagePasteGesture.ContainsEnter || TextPasteGesture.ContainsEnter)
            throw new ArgumentException("Paste profiles must never contain Enter.");
        if (Transport == PasteTransport.SingleClipboardPackage && ImagePasteGesture != TextPasteGesture)
            throw new ArgumentException("A single clipboard package must use one shared paste gesture.");
        if (AllowedProcessNames.Count == 0)
            throw new ArgumentException("A target profile needs at least one allowed process name.");
        if (AcceptanceTimeout <= TimeSpan.Zero || UnobservableSettlementDelay < TimeSpan.Zero)
            throw new ArgumentOutOfRangeException(nameof(AcceptanceTimeout));
    }
}

public static class TargetProfiles
{
    private static readonly TimeSpan DefaultTimeout = TimeSpan.FromSeconds(8);
    private static readonly TimeSpan DefaultDelay = TimeSpan.FromMilliseconds(900);

    public static TargetProfile ClaudeCodeWindowsTerminal { get; } = new(
        "claude-code-windows-terminal",
        "Claude Code · Windows Terminal (не проверено)",
        PasteTransport.StagedSequence,
        HotkeyGesture.AltV,
        HotkeyGesture.CtrlShiftV,
        Processes("WindowsTerminal"),
        DefaultTimeout,
        DefaultDelay,
        ProfileVerification.Unverified);

    public static TargetProfile ClaudeDesktopCode { get; } = new(
        "claude-desktop-code",
        "Claude Desktop · Code (не проверено)",
        PasteTransport.StagedSequence,
        HotkeyGesture.CtrlV,
        HotkeyGesture.CtrlV,
        Processes("Claude"),
        DefaultTimeout,
        DefaultDelay,
        ProfileVerification.Unverified);

    public static TargetProfile ClaudeCodeVisualStudioCode { get; } = new(
        "claude-code-vscode",
        "Claude Code · Visual Studio Code (не проверено)",
        PasteTransport.StagedSequence,
        HotkeyGesture.AltV,
        HotkeyGesture.CtrlV,
        Processes("Code"),
        DefaultTimeout,
        DefaultDelay,
        ProfileVerification.Unverified);

    public static TargetProfile CodexDesktop { get; } = new(
        "codex-desktop",
        "Codex Desktop (не проверено)",
        PasteTransport.StagedSequence,
        HotkeyGesture.CtrlV,
        HotkeyGesture.CtrlV,
        Processes("ChatGPT"),
        DefaultTimeout,
        DefaultDelay,
        ProfileVerification.Unverified);

    public static TargetProfile CodexTerminal { get; } = new(
        "codex-terminal",
        "Codex CLI · Windows Terminal (не проверено)",
        PasteTransport.StagedSequence,
        HotkeyGesture.CtrlV,
        HotkeyGesture.CtrlShiftV,
        Processes("WindowsTerminal"),
        DefaultTimeout,
        DefaultDelay,
        ProfileVerification.Unverified);

    public static TargetProfile CodexVisualStudioCode { get; } = new(
        "codex-vscode",
        "Codex CLI · Visual Studio Code (не проверено)",
        PasteTransport.StagedSequence,
        HotkeyGesture.CtrlV,
        HotkeyGesture.CtrlV,
        Processes("Code"),
        DefaultTimeout,
        DefaultDelay,
        ProfileVerification.Unverified);

    public static IReadOnlyList<TargetProfile> All { get; } =
        [ClaudeCodeWindowsTerminal, ClaudeCodeVisualStudioCode, ClaudeDesktopCode, CodexDesktop, CodexTerminal, CodexVisualStudioCode];

    private static IReadOnlySet<string> Processes(params string[] names) =>
        new HashSet<string>(names, StringComparer.OrdinalIgnoreCase);
}

public readonly record struct ClipboardWriteReceipt(uint SequenceNumber);

public sealed record ClipboardSnapshot(uint SequenceNumber, IReadOnlyDictionary<string, object> Data, bool IsComplete);

public sealed class ClipboardChangedException : InvalidOperationException
{
    public ClipboardChangedException() : base("The clipboard changed before SnapBrief could publish the next stage.") { }
}

public interface IClipboardService
{
    Task<ClipboardSnapshot> CaptureAsync(CancellationToken cancellationToken);
    Task<ClipboardWriteReceipt> SetPackageGuardedAsync(
        IReadOnlyList<string> pngPaths,
        string text,
        uint expectedSequenceNumber,
        CancellationToken cancellationToken);
    Task<ClipboardWriteReceipt> SetPngOnlyGuardedAsync(
        string pngPath,
        uint expectedSequenceNumber,
        CancellationToken cancellationToken);
    Task<ClipboardWriteReceipt> SetPngGuardedAsync(string pngPath, uint expectedSequenceNumber, CancellationToken cancellationToken);
    Task<ClipboardWriteReceipt> SetTextGuardedAsync(string text, uint expectedSequenceNumber, CancellationToken cancellationToken);
    Task<bool> IsCurrentAsync(ClipboardWriteReceipt receipt, CancellationToken cancellationToken);
    Task<bool> RestoreIfCurrentAsync(
        ClipboardSnapshot snapshot,
        ClipboardWriteReceipt receipt,
        CancellationToken cancellationToken);
}

public sealed record TargetSnapshot(nint WindowHandle, nint FocusedControlHandle, uint ProcessId, string ProcessName, string WindowTitle)
{
    public bool IsUsable => WindowHandle != 0 && ProcessId != 0;
}

public interface IForegroundTargetService
{
    TargetSnapshot Capture();
    bool IsSame(TargetSnapshot expected);
    bool Matches(TargetSnapshot target, TargetProfile profile);
}

public interface IInputInjector
{
    Task SendAsync(HotkeyGesture gesture, CancellationToken cancellationToken);
}

public interface IGuardedInputInjector : IInputInjector
{
    Task<bool> SendGuardedAsync(
        HotkeyGesture gesture,
        Func<CancellationToken, ValueTask<bool>> finalGuard,
        CancellationToken cancellationToken);
}

public interface IPhysicalKeyState
{
    bool IsDown(ushort virtualKey);
}

public sealed class PhysicalKeysStillHeldException : InvalidOperationException
{
    public PhysicalKeysStillHeldException() : base("Paste shortcut keys or trigger modifiers are still physically held.") { }
}

public enum AcceptanceOutcome
{
    Accepted,
    NotObservable,
    TimedOut,
    TargetLost,
}

public interface IPasteAcceptanceObserver
{
    Task<PackageAcceptanceOutcome> WaitForPackageAsync(
        TargetSnapshot target,
        TargetProfile profile,
        CancellationToken cancellationToken);
    Task<AcceptanceOutcome> WaitForImageAsync(
        TargetSnapshot target,
        int imageIndex,
        TargetProfile profile,
        CancellationToken cancellationToken);
    Task<AcceptanceOutcome> WaitForTextAsync(
        TargetSnapshot target,
        TargetProfile profile,
        CancellationToken cancellationToken);
}

public sealed record PackageAcceptanceOutcome(
    AcceptanceOutcome Images,
    AcceptanceOutcome Text);

public enum PastePhase
{
    Validating,
    PreparingClipboard,
    SendingImage,
    WaitingForImage,
    SendingText,
    WaitingForText,
    Completed,
    Stopped,
}

public sealed record PasteProgress(
    PastePhase Phase,
    int ImagesDispatched,
    int ImagesConfirmed,
    int TotalImages,
    bool TextDispatched,
    bool TextConfirmed,
    string Message);

public enum PasteStatus
{
    CompletedVerified,
    CompletedUnverified,
    InvalidPackage,
    TargetMismatch,
    TargetChanged,
    ClipboardChanged,
    AcceptanceTimedOut,
    Cancelled,
    Failed,
}

public sealed record PasteResumeToken(Guid ExportId, int ConfirmedImageCount, bool TextConfirmed);

public sealed record PasteResult(
    PasteStatus Status,
    int ImagesDispatched,
    int ImagesConfirmed,
    bool TextDispatched,
    bool TextConfirmed,
    PasteResumeToken? SafeResumeToken,
    string Message,
    Exception? Error = null)
{
    public bool DeliveryWasObserved => Status == PasteStatus.CompletedVerified;
}

public interface IPasteCoordinator
{
    Task<PasteResult> PasteAsync(
        PreparedPastePackage package,
        TargetProfile profile,
        PasteResumeToken? resumeToken = null,
        IProgress<PasteProgress>? progress = null,
        CancellationToken cancellationToken = default);
}

public sealed record GlobalHotkeyPressed(string Id);

public interface IGlobalHotkeyService : IDisposable
{
    event EventHandler<GlobalHotkeyPressed>? Pressed;
    void Register(string id, HotkeyGesture gesture);
    void Unregister(string id);
}

public sealed record PasteIntentObserved(
    HotkeyGesture Gesture,
    nint ForegroundWindowHandle,
    uint ForegroundProcessId,
    uint ClipboardSequenceNumber,
    DateTimeOffset ObservedAtUtc,
    bool IsIntercepted = false);

public interface IPasteIntentObserver : IDisposable
{
    event EventHandler<PasteIntentObserved>? PasteIntentObserved;
    void Start();
    void Stop();
}

public enum CodexPasteCompletionStatus
{
    CompletedUnverified,
    NotApplicable,
    NothingToDispatch,
    StaleIntent,
    TargetLost,
    ClipboardChanged,
    Cancelled,
    Failed,
}

public sealed record CodexPasteCompletionResult(
    CodexPasteCompletionStatus Status,
    string Message,
    ClipboardWriteReceipt? TextClipboardReceipt = null,
    Exception? Error = null)
{
    public ClipboardWriteReceipt? CurrentClipboardReceipt => TextClipboardReceipt;
    public bool TextWasDispatched => Status == CodexPasteCompletionStatus.CompletedUnverified;
}

public interface ICodexDesktopPasteCompletionService
{
    Task<CodexPasteCompletionResult> CompleteAsync(
        PasteIntentObserved intent,
        ClipboardWriteReceipt ownedPackageReceipt,
        string immutablePromptText,
        CancellationToken cancellationToken = default);
    Task<CodexPasteCompletionResult> CompleteSequentialAsync(
        PasteIntentObserved intent,
        ClipboardWriteReceipt ownedPackageReceipt,
        IReadOnlyList<string> immutableImagePaths,
        string immutablePromptText,
        CancellationToken cancellationToken = default);
    Task<CodexPasteCompletionResult> CompleteClaudeAsync(
        PasteIntentObserved intent,
        ClipboardWriteReceipt ownedPackageReceipt,
        IReadOnlyList<string> immutableImagePaths,
        string immutablePromptText,
        CancellationToken cancellationToken = default);
}
