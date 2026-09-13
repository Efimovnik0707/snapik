using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using Microsoft.Win32;
using SnapBrief.Core.Exporting;
using SnapBrief.Windows;
using WinForms = System.Windows.Forms;

namespace SnapBrief.App;

public partial class EdgeStackWindow : Window
{
    private readonly LaunchOptions _options;
    private readonly SessionWorkspace _workspace;
    private readonly WindowsClipboardService _clipboard = new();
    private readonly IPasteCoordinator _pasteCoordinator;
    private readonly ICodexDesktopPasteCompletionService _codexPasteCompletion;
    private readonly DispatcherTimer _saveTimer;
    private readonly DispatcherTimer _toastTimer;
    private readonly string _settingsPath;
    private readonly WinForms.NotifyIcon _trayIcon;
    private readonly IPasteIntentObserver _pasteIntentObserver;
    private readonly SemaphoreSlim _workspaceMutationGate = new(1, 1);
    private readonly SemaphoreSlim _clipboardPublicationGate = new(1, 1);
    private HotkeySettings _settings;
    private int _topmostSuspensions;
    private WindowsGlobalHotkeyService? _hotkeys;
    private bool _hotkeysStarting;
    private PreparedExport? _preparedExport;
    private PublishedPackage? _published;
    private ClipboardWriteReceipt? _ownedClipboardReceipt;
    private string _legacyGlobalNote = string.Empty;
    private bool _loadedOnce;
    private bool _busy;
    private bool _loading;
    private bool _exiting;
    // The question on the way out is on screen (or the session is being deleted): a second "Exit"
    // from the tray must not start a second one.
    private bool _leaving;
    private bool _allowClose;
    private bool _sessionResetting;
    private CancellationTokenSource? _receiverEchoWatchCts;
    private Task _pasteIntentTransition = Task.CompletedTask;
    // Some paste receivers (e.g. a terminal hosting Claude Code) write their own
    // rendering of the pasted text back to the clipboard right after the paste. This
    // window bounds how long we keep watching for and re-arming through such an echo.
    private static readonly TimeSpan ReceiverEchoWatchWindow = TimeSpan.FromSeconds(6);
    private static readonly TimeSpan ReceiverEchoPollInterval = TimeSpan.FromMilliseconds(200);
    private static readonly TimeSpan ToastLifetime = TimeSpan.FromSeconds(5);
    private static readonly TimeSpan ToastFade = TimeSpan.FromMilliseconds(150);
    private Action? _toastAction;
    private int _toastGeneration;
    private Point _dragStart;
    private double _resizeRightEdge;
    private double _resizeTop;
    private Rect _resizeWorkArea;
    private CaptureItem? _draggedCapture;
    private readonly Stack<(CaptureItem Capture, int Index)> _removed = [];
    private TargetProfile? _selectedProfile;

    public EdgeStackWindow(LaunchOptions options)
    {
        _options = options;
        var dataRoot = options.DataDirectory;
        if (options.Demo && string.IsNullOrWhiteSpace(dataRoot)) dataRoot = Path.Combine(Path.GetTempPath(), "SnapBrief", $"demo-{Environment.ProcessId}");
        _workspace = new SessionWorkspace(dataRoot);
        _settingsPath = Path.Combine(options.DataDirectory ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SnapBrief"), "settings.json");
        // The one read of the settings that may also write: a file from an older build is brought
        // up to date here, once, and every other read in the application stays a read.
        _settings = HotkeySettings.LoadAndMigrate(_settingsPath);
        UiLanguage.Current = _settings.Language;
        // Before any window content is built: the accent is read through DynamicResource.
        ThemeService.Apply(_settings.Theme, _settings.AccentId);
        var foreground = new WindowsForegroundTargetService();
        var input = new WindowsInputInjector();
        _pasteCoordinator = new PasteCoordinator(_clipboard, foreground, input, new UnobservableAcceptanceObserver(foreground));
        _codexPasteCompletion = new CodexDesktopPasteCompletionService(_clipboard, foreground, input);
        _saveTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(500) };
        _saveTimer.Tick += OnSaveTimerTick;
        _toastTimer = new DispatcherTimer { Interval = ToastLifetime };
        _toastTimer.Tick += OnToastTimerTick;
        _pasteIntentObserver = new WindowsPasteIntentObserver(intent =>
        {
            var receiptSeq = _ownedClipboardReceipt?.SequenceNumber;
            // What the clipboard holds is the published package, not the prepared export: the export
            // is rebuilt (or dropped) as soon as the strip changes, while the package the user is
            // about to paste stays on the clipboard until something replaces it.
            if (_sessionResetting || !_pasteIntentTransition.IsCompleted || _clipboardPublicationGate.CurrentCount == 0 ||
                !PublishedPackage.IsOwnPaste(_published, receiptSeq, intent.ClipboardSequenceNumber))
            {
                StartupTrace.Write(_options, $"PasteIntent predicate: state not ready (resetting={_sessionResetting}, transitionDone={_pasteIntentTransition.IsCompleted}, gate={_clipboardPublicationGate.CurrentCount}, ownedSeq={receiptSeq}, intentSeq={intent.ClipboardSequenceNumber}, published={_published is not null}, gesture={intent.Gesture})");
                return false;
            }
            if (intent.Gesture != HotkeyGesture.CtrlV && intent.Gesture != HotkeyGesture.AltV)
            {
                StartupTrace.Write(_options, $"PasteIntent predicate: gesture {intent.Gesture} not intercepted");
                return false;
            }
            var target = foreground.Capture();
            if (!target.IsUsable || target.WindowHandle != intent.ForegroundWindowHandle ||
                target.ProcessId != intent.ForegroundProcessId)
            {
                StartupTrace.Write(_options, $"PasteIntent predicate: target mismatch (usable={target.IsUsable}, process={target.ProcessName}, hwnd={target.WindowHandle} vs {intent.ForegroundWindowHandle}, pid={target.ProcessId} vs {intent.ForegroundProcessId})");
                return false;
            }
            // Codex Desktop keeps the untouched CompleteAsync path: its physical Ctrl+V paste
            // already works against the composite package, so it must not be intercepted here.
            var intercept = !foreground.Matches(target, SnapBrief.Windows.TargetProfiles.CodexDesktop);
            StartupTrace.Write(_options, $"PasteIntent predicate: intercept={intercept}, gesture={intent.Gesture}, process={target.ProcessName}, title={target.WindowTitle}, seq={intent.ClipboardSequenceNumber}");
            return intercept;
        });

        InitializeComponent();
        DataContext = this;
        Opacity = 0;
        _selectedProfile = TargetProfiles.ElementAtOrDefault(3) ?? TargetProfiles.FirstOrDefault();
        RefreshTargetCaption();
        _trayIcon = new WinForms.NotifyIcon
        {
            Text = "SnapBrief",
            Icon = System.Drawing.Icon.ExtractAssociatedIcon(Environment.ProcessPath!) ?? System.Drawing.SystemIcons.Application,
            Visible = true,
            ContextMenuStrip = new WinForms.ContextMenuStrip()
        };
        _trayIcon.ContextMenuStrip.Items.Add("Показать ленту", null, (_, _) => Dispatcher.Invoke(ShowStackWithoutActivation));
        _trayIcon.ContextMenuStrip.Items.Add("Настройки", null, (_, _) => Dispatcher.Invoke(() => { ShowStackWithoutActivation(); OpenSettings(); }));
        // BeginInvoke, not Invoke: the slides open modally, and a modal loop started from inside the
        // click handler of the menu runs while that menu is still on screen. The dialog then may
        // never get the activation its arrow keys need. Posting it lets the menu close first.
        _trayIcon.ContextMenuStrip.Items.Add("Как пользоваться", null, (_, _) => Dispatcher.BeginInvoke(() => ShowOnboarding(howToOnly: true)));
        _trayIcon.ContextMenuStrip.Items.Add("Новый снимок", null, (_, _) => Dispatcher.InvokeAsync(CaptureLoopAsync));
        _trayIcon.ContextMenuStrip.Items.Add(new WinForms.ToolStripSeparator());
        _trayIcon.ContextMenuStrip.Items.Add("Выйти", null, (_, _) => Dispatcher.Invoke(() => { _exiting = true; Close(); }));
        var startupItem = new WinForms.ToolStripMenuItem("Запускать с Windows");
        _trayIcon.ContextMenuStrip.Items.Add(startupItem);
        _trayIcon.ContextMenuStrip.Opening += (_, _) =>
        {
            foreach (WinForms.ToolStripItem item in _trayIcon.ContextMenuStrip.Items) item.Text = UiLanguage.Text(item.Text ?? string.Empty);
            try { startupItem.Checked = WindowsStartupService.IsEnabled(); startupItem.Enabled = true; }
            catch (Exception ex) { startupItem.Enabled = false; StartupTrace.Write(_options, $"Startup settings: {ex}"); }
        };
        startupItem.Click += (_, _) => Dispatcher.Invoke(() =>
        {
            try
            {
                WindowsStartupService.SetEnabled(!WindowsStartupService.IsEnabled());
                startupItem.Checked = WindowsStartupService.IsEnabled();
            }
            catch (Exception ex)
            {
                ShowStackWithoutActivation();
                SetStatus($"{UiLanguage.Text("Не удалось изменить автозапуск")}: {ex.Message}", true);
            }
        });
        _trayIcon.DoubleClick += (_, _) => Dispatcher.Invoke(ShowStackWithoutActivation);
        Loaded += OnLoaded;
        SourceInitialized += OnSourceInitialized;
        Closing += OnClosing;
    }

    public ObservableCollection<CaptureItem> Captures { get; } = [];
    public IReadOnlyList<TargetProfile> TargetProfiles { get; } = SnapBrief.Windows.TargetProfiles.All;
    private TargetProfile? SelectedProfile => _selectedProfile;

    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        if (_loadedOnce) return;
        _loadedOnce = true;
        Topmost = _settings.StackTopmost;
        UiSoundService.Preload();
        Hide();
        Opacity = 1;
        StartupTrace.Write(_options, "EdgeStack.Loaded entered");
        // Loaded may arrive before SourceInitialized (SizeToContent), and the wizard below registers
        // the shortcut through the hotkey service.
        try { EnsureHotkeys(); }
        catch (Exception ex) { StartupTrace.Write(_options, $"Hotkeys in Loaded: {ex}"); }
        // Before the session is restored: on the very first run there is nothing to restore, and the
        // wizard writes the language and the shortcut the rest of the startup reads.
        if (OnboardingWindow.ShouldShowOnboarding(File.Exists(_settingsPath), _settings, _options.Demo || _options.SmokeTest))
            ShowOnboarding();
        _loading = true;
        try
        {
            if (_options.Demo)
                await SeedDemoAsync();
            else
            {
                // A session lives for one run: the strip starts empty, and whatever the previous run
                // left on disk (including a run that was killed) goes before this one writes anything.
                await _workspace.PurgePreviousSessionsAsync(message => StartupTrace.Write(_options, message));
            }
            Renumber();
            PositionAtEdge();
            StartupTrace.Write(_options, $"EdgeStack.Loaded completed with {Captures.Count} captures");
        }
        catch (Exception ex) { SetStatus($"{UiLanguage.Text("Не удалось восстановить сессию")}: {ex.Message}", true); StartupTrace.Write(_options, ex.ToString()); }
        finally { _loading = false; }
    }

    // With SizeToContent WPF runs the first layout pass, and raises Loaded, before it raises
    // SourceInitialized. The wizard opens from Loaded and needs the hotkey service, so the service
    // is created by whichever of the two events comes first; the handle already exists in both.
    private void EnsureHotkeys()
    {
        // EnsureHandle() raises SourceInitialized on the spot, and that handler comes back here while
        // the service is still being built: without the flag the window would end up with two
        // services on one hwnd, and the second registration of the same shortcut reports it as taken.
        if (_hotkeys is not null || _hotkeysStarting) return;
        _hotkeysStarting = true;
        try
        {
            var handle = new WindowInteropHelper(this).EnsureHandle();
            _hotkeys = new WindowsGlobalHotkeyService(handle);
            _ = SetWindowDisplayAffinity(handle, 0x00000011);
            _hotkeys.Pressed += OnHotkey;
            _ = RegisterHotkeys();
            StartupTrace.Write(_options, $"Hotkeys ready: hwnd={handle}");
        }
        finally { _hotkeysStarting = false; }
    }

    private void OnSourceInitialized(object? sender, EventArgs e)
    {
        try { EnsureHotkeys(); }
        catch (Exception ex)
        {
            StartupTrace.Write(_options, $"Hotkeys: {ex}");
            SetStatus($"{UiLanguage.Text("Захват")}: {ex.Message}", true);
        }
        try
        {
            _pasteIntentObserver.PasteIntentObserved += OnPasteIntentObserved;
            _pasteIntentObserver.Start();
        }
        catch (Exception ex) { SetStatus($"{UiLanguage.Text("Отслеживание вставки недоступно")}: {ex.Message}", true); }
    }

    private bool RegisterHotkeys()
    {
        var conflicts = new List<string>();
        if (_settings.CaptureEnabled) try { _hotkeys?.Register("capture", _settings.CaptureGesture); } catch { conflicts.Add(UiLanguage.Text("захват")); }
        if (_settings.FullscreenSaveEnabled) try { _hotkeys?.Register("fullscreen-save", _settings.FullscreenSaveGesture); } catch { conflicts.Add(UiLanguage.Text("сохранение экрана")); }
        if (conflicts.Count > 0) SetStatus($"{UiLanguage.Text("Сочетание занято")}: {string.Join(", ", conflicts)}", true);
        return conflicts.Count == 0;
    }

    // A shortcut is delivered through the dispatcher, and the dispatcher runs inside the modal loop
    // of a dialog as well, so a capture can start while the wizard or the settings are waiting for
    // an answer. It must not: see CaptureIsBlockedByADialog.
    private void OnHotkey(object? sender, GlobalHotkeyPressed e) => Dispatcher.InvokeAsync(async () =>
    {
        if (CaptureIsBlockedByADialog($"hotkey {e.Id}")) return;
        if (e.Id == "capture" && !OverlayEditorWindow.TryCommitAndRequestNext()) await CaptureLoopAsync();
        else if (e.Id == "fullscreen-save") await SaveFullscreenAsync();
    });

    // Every modal window the application opens goes through SuspendTopmost, so the number of
    // suspensions is the number of dialogs waiting for an answer.
    private bool ADialogIsOnScreen => _topmostSuspensions > 0;

    // True when the capture is refused, with the reason in the log. A capture hides every window of
    // the application, and a dialog hidden that way never comes back: the strip returns alone, while
    // the modal loop of the dialog goes on running behind nothing at all. That is how the wizard
    // disappeared when a shortcut fired a capture on its slides. Hiding the dialog and bringing it
    // back would be worse: a topmost wizard would return on top of the editor of the new capture and
    // block it. So a capture asked for over a dialog simply does not happen.
    private bool CaptureIsBlockedByADialog(string source)
    {
        if (!ADialogIsOnScreen) return false;
        StartupTrace.Write(_options, $"Capture refused ({source}): a dialog of the application is on screen.");
        return true;
    }

    private void OnPasteIntentObserved(object? sender, PasteIntentObserved e)
    {
        var receiptAtIntent = _ownedClipboardReceipt;
        // The files, the text and the captures come from the package that was published, so the
        // completion works on what is on the clipboard even when the prepared export has moved on.
        // Which captures the package holds is decided by id: the strip may be reordered or trimmed
        // before the completion finishes, and then indices would point at other captures. A capture
        // edited between this intent and the completion keeps its id, so it is marked as sent
        // together with the rest of the package it left in.
        var publishedAtIntent = _published;
        StartupTrace.Write(_options, $"PasteIntent observed: gesture={e.Gesture}, intercepted={e.IsIntercepted}, seq={e.ClipboardSequenceNumber}, ownedSeq={receiptAtIntent?.SequenceNumber}, pid={e.ForegroundProcessId}");
        if (receiptAtIntent is null || e.ClipboardSequenceNumber != receiptAtIntent.Value.SequenceNumber)
        {
            _ = LogClipboardDiagnosticsAsync();
            return;
        }
        if (publishedAtIntent is null)
        {
            SetStatus(UiLanguage.Text("Не удалось подтвердить содержимое текущего пакета. Сессия сохранена."), true);
            return;
        }

        if (_sessionResetting || !_pasteIntentTransition.IsCompleted || _clipboardPublicationGate.CurrentCount == 0 || _ownedClipboardReceipt != receiptAtIntent) return;
        // Snapshot in the keyboard hook, but release the hook before any clipboard I/O.
        _pasteIntentTransition = Dispatcher.InvokeAsync(() =>
            CompletePasteIntentAsync(e, receiptAtIntent.Value, publishedAtIntent)).Task.Unwrap();
    }

    private async Task CompletePasteIntentAsync(PasteIntentObserved e, ClipboardWriteReceipt receiptAtIntent, PublishedPackage publishedAtIntent)
    {
        await _clipboardPublicationGate.WaitAsync();
        try
        {
            var completion = e.IsIntercepted
                ? await _codexPasteCompletion.CompleteSequentialAsync(e, receiptAtIntent, publishedAtIntent.Paths, publishedAtIntent.Prompt, CancellationToken.None)
                : await _codexPasteCompletion.CompleteAsync(
                e,
                receiptAtIntent,
                publishedAtIntent.Prompt,
                CancellationToken.None);

            StartupTrace.Write(_options, $"PasteIntent completion: intercepted={e.IsIntercepted}, images={publishedAtIntent.Paths.Length}, status={completion.Status}, message={completion.Message}");
            // A newer capture may have replaced the package while completion was waiting.
            // Never rotate that newer session in response to this older paste intent.
            if (_ownedClipboardReceipt != receiptAtIntent) return;

            if (completion.CurrentClipboardReceipt is { } textReceipt)
            {
                // That receipt is the write of the prompt text: the package is no longer on the
                // clipboard. Only the completed branch below puts it back, so every other outcome
                // leaves nothing of ours published and the paste intent must stop recognizing it.
                _ownedClipboardReceipt = textReceipt;
                if (completion.Status != CodexPasteCompletionStatus.CompletedUnverified) SetPublished(null);
            }

            if (completion.Status == CodexPasteCompletionStatus.CompletedUnverified)
            {
                // The pasted package stays on the clipboard so the same set can go into another
                // application right away; the captures stay in the strip and only turn sent. The
                // republish arms the echo watch first, and marking runs after it: only captures
                // that are still waiting rebuild the clipboard and cancel that watch.
                await RepublishPackageForReuseAsync(publishedAtIntent);
                await MarkCapturesSentAsync(publishedAtIntent.CaptureIds);
                return;
            }

            if (!e.IsIntercepted && completion.Status == CodexPasteCompletionStatus.NotApplicable)
            {
                if (await _clipboard.IsCurrentAsync(receiptAtIntent, CancellationToken.None))
                    await MarkCapturesSentAsync(publishedAtIntent.CaptureIds);
                return;
            }

            SetStatus($"{UiLanguage.Text("Снимки сохранены, но вставка не завершена")}: {completion.Message}", true);
        }
        catch (Exception ex)
        {
            StartupTrace.Write(_options, $"PasteIntent completion failed: {ex}");
            SetStatus($"{UiLanguage.Text("Вставка замечена, но лента не обновлена")}: {ex.Message}", true);
        }
        finally { _clipboardPublicationGate.Release(); }
    }

    // Runs inside the same critical section as the completion above (the gate is
    // released by CompletePasteIntentAsync's finally), so the republish and the
    // guard it depends on stay atomic with respect to other clipboard publishers.
    [DllImport("user32.dll")] private static extern nint GetClipboardOwner();
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(nint hWnd, out uint processId);

    /// <summary>Diagnostics only: who owns the clipboard and what it holds when a paste intent misses our package.</summary>
    private async Task LogClipboardDiagnosticsAsync()
    {
        try
        {
            var owner = GetClipboardOwner();
            var ownerName = "none";
            if (owner != 0)
            {
                GetWindowThreadProcessId(owner, out var ownerPid);
                try { ownerName = $"{System.Diagnostics.Process.GetProcessById((int)ownerPid).ProcessName}({ownerPid})"; }
                catch { ownerName = $"pid {ownerPid}"; }
            }
            var snapshot = await _clipboard.CaptureAsync(CancellationToken.None);
            var formats = string.Join(",", snapshot.Data.Keys);
            var text = snapshot.Data.TryGetValue(DataFormats.UnicodeText, out var t) ? t?.ToString() : null;
            text ??= snapshot.Data.TryGetValue(DataFormats.Text, out var t2) ? t2?.ToString() : null;
            var preview = text is null ? "<no text>" : text.Length > 120 ? text[..120] : text;
            var safePreview = preview.Replace('\r', ' ').Replace('\n', '|');
            StartupTrace.Write(_options, $"Clipboard diagnostics: seq={snapshot.SequenceNumber}, owner={ownerName}, formats=[{formats}], text={safePreview}");
        }
        catch (Exception ex)
        {
            StartupTrace.Write(_options, $"Clipboard diagnostics failed: {ex.Message}");
        }
    }

    private async Task RepublishPackageForReuseAsync(PublishedPackage publishedAtIntent)
    {
        if (_ownedClipboardReceipt is not { } current)
        {
            SetStatus(UiLanguage.Text("Пакет вытеснен другим приложением. Сессия сохранена."), true);
            return;
        }
        try
        {
            var republished = await _clipboard.SetPackageGuardedAsync(publishedAtIntent.Paths, publishedAtIntent.Prompt, current.SequenceNumber, CancellationToken.None);
            _ownedClipboardReceipt = republished;
            SetPublished(publishedAtIntent);
            StartupTrace.Write(_options, $"PasteIntent republished package: seq={republished.SequenceNumber}, images={publishedAtIntent.Paths.Length}");
            var template = UiLanguage.Text("Вставлено: {0} изображений · {1} заметок. Снимки помечены как отправленные");
            ShowToast(string.Format(template, publishedAtIntent.Paths.Length, publishedAtIntent.NoteCount));
            StartReceiverEchoWatch(publishedAtIntent);
        }
        catch (ClipboardChangedException)
        {
            // Someone else copied in the meantime; leave their clipboard untouched. The next capture
            // rebuilds the package in SaveAndCopyCommittedPackageAsync from the captures that are
            // still waiting, and nothing of ours is on the clipboard until then.
            CancelReceiverEchoWatch();
            _ownedClipboardReceipt = null;
            SetPublished(null);
            SetStatus(UiLanguage.Text("Пакет вытеснен другим приложением. Сессия сохранена."), true);
        }
    }

    // Some receivers (a terminal hosting Claude Code, for example) write their own text
    // rendering of a just-completed paste back onto the clipboard a moment later. That
    // overwrites our sequence number and makes the next Ctrl+V/Alt+V miss the interception
    // predicate, even though our package is still the one the user intends to paste. This
    // watcher polls the clipboard for a short window after every republish and, if the
    // change looks like that echo rather than a real foreign copy, republishes the same
    // package so the predicate keeps recognizing it.
    private void CancelReceiverEchoWatch()
    {
        var cts = _receiverEchoWatchCts;
        _receiverEchoWatchCts = null;
        if (cts is null) return;
        cts.Cancel();
        cts.Dispose();
    }

    private void StartReceiverEchoWatch(PublishedPackage published)
    {
        CancelReceiverEchoWatch();
        // A package without text cannot come back as a text echo from the receiver.
        if (published.Prompt.Length == 0) return;
        var cts = new CancellationTokenSource();
        _receiverEchoWatchCts = cts;
        _ = WatchForReceiverEchoAsync(published, cts);
    }

    private async Task WatchForReceiverEchoAsync(PublishedPackage published, CancellationTokenSource cts)
    {
        var token = cts.Token;
        try
        {
            var deadline = DateTimeOffset.UtcNow + ReceiverEchoWatchWindow;
            while (!token.IsCancellationRequested && DateTimeOffset.UtcNow < deadline)
            {
                try { await Task.Delay(ReceiverEchoPollInterval, token); }
                catch (OperationCanceledException) { return; }

                if (_ownedClipboardReceipt is not { } current) return;

                ClipboardSnapshot snapshot;
                try { snapshot = await _clipboard.CaptureAsync(token); }
                catch (OperationCanceledException) { return; }
                catch (Exception ex) { StartupTrace.Write(_options, $"Receiver echo watch: capture failed: {ex.Message}"); continue; }

                if (snapshot.SequenceNumber == current.SequenceNumber) continue;

                if (!ClipboardEchoDetector.IsReceiverEcho(snapshot, published.Prompt))
                {
                    StartupTrace.Write(_options, "PasteIntent package displaced by foreign clipboard write");
                    return;
                }

                await _clipboardPublicationGate.WaitAsync(token);
                try
                {
                    if (token.IsCancellationRequested) return;
                    var republished = await _clipboard.SetPackageGuardedAsync(published.Paths, published.Prompt, snapshot.SequenceNumber, token);
                    StartupTrace.Write(_options, $"PasteIntent re-armed after receiver echo: from seq {current.SequenceNumber} to {republished.SequenceNumber}");
                    _ownedClipboardReceipt = republished;
                    SetPublished(published);
                }
                catch (OperationCanceledException) { return; }
                catch (ClipboardChangedException)
                {
                    StartupTrace.Write(_options, "PasteIntent package displaced by foreign clipboard write");
                    return;
                }
                finally { _clipboardPublicationGate.Release(); }

                deadline = DateTimeOffset.UtcNow + ReceiverEchoWatchWindow;
            }
        }
        finally { if (ReferenceEquals(_receiverEchoWatchCts, cts)) _receiverEchoWatchCts = null; }
    }

    private async void OnCaptureClick(object sender, RoutedEventArgs e) => await CaptureLoopAsync();

    private async Task CaptureLoopAsync()
    {
        await _pasteIntentTransition;
        // Checked again after the wait, and for the tray item and the button of the strip as well:
        // a dialog may have opened while this was waiting.
        if (CaptureIsBlockedByADialog("capture loop")) return;
        if (_busy) return;
        _busy = true;
        try
        {
            var addNext = true;
            while (addNext)
            {
                // Checked before anything is hidden: an eleventh press must not open the editor over
                // a capture that has nowhere to go.
                if (StripIsFull()) { addNext = false; continue; }
                HideForCapture();
                var result = await OverlayEditorWindow.CaptureNewAsync(_workspace, PendingCaptures.Count);
                if (result.Capture is null) { addNext = false; continue; }
                Captures.Add(result.Capture);
                Renumber();
                InvalidatePrepared();
                // The shutter belongs to the moment of the capture, so it plays before the package
                // travels to the clipboard and not after that wait.
                UiSoundService.Capture(_settings);
                var copied = await SaveAndCopyCommittedPackageAsync();
                await AutoSaveCaptureAsync(result.Capture);
                addNext = copied && result.AddNext;
            }
        }
        catch (Exception ex) { SetStatus($"{UiLanguage.Text("Захват не завершён")}: {ex.Message}", true); }
        finally
        {
            _busy = false;
            ShowStackWithoutActivation();
        }
    }

    // The strip holds ten captures, sent ones included: they take the same disk and the same memory,
    // and the letters of the strip stay inside A..J. Every way of adding a capture goes through here.
    private bool StripIsFull(int adding = 1)
    {
        if (Captures.Count + adding <= SentCaptureRules.MaxStripCaptures) return false;
        ShowToast(UiLanguage.Text("В ленте максимум 10 снимков. Отправьте или удалите лишние"));
        return true;
    }

    private async void OnRemoveCaptureClick(object sender, RoutedEventArgs e)
    {
        await _pasteIntentTransition;
        if (sender is not Button { Tag: CaptureItem capture }) return;
        var index = Captures.IndexOf(capture);
        Captures.Remove(capture);
        _removed.Push((capture.DeepClone(), index));
        Renumber();
        InvalidatePrepared();
        // Undo works from the copy held in memory, so the offer stands even when the session file
        // could not be written; that failure stays on the status line under the toast.
        await SaveAsync();
        ShowToast(UiLanguage.Text("Снимок удалён"), UiLanguage.Text("Отменить"), () => _ = RestoreRemoved());
        await RefreshOwnedClipboardAsync();
        e.Handled = true;
    }

    private void HideForCapture()
    {
        foreach (Window window in Application.Current.Windows)
            if (window.IsVisible && window is not OverlayEditorWindow) window.Hide();
        Dispatcher.Invoke(() => { }, DispatcherPriority.Render);
        _ = DwmFlush();
    }

    private void ShowStackWithoutActivation()
    {
        Renumber();
        PositionAtEdge();
        Show();
        _ = SetWindowPos(new WindowInteropHelper(this).Handle, IntPtr.Zero, 0, 0, 0, 0, 0x0053);
        UiLanguage.Apply(this);
        AnimateStackIn();


    }

    public void RevealStack() => ShowStackWithoutActivation();

    private void HideStack()
    {
        HideToastNow();
        Hide();
    }

    private void OnHideClick(object sender, RoutedEventArgs e) => HideStack();

    private void AnimateStackIn()
    {
        if (!SystemParameters.ClientAreaAnimation) { Opacity = 1; return; }
        Opacity = 0;
        var animation = new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(180)) { EasingFunction = new ExponentialEase { EasingMode = EasingMode.EaseOut, Exponent = 5 } };
        BeginAnimation(OpacityProperty, animation);
    }

    // The working area of the monitor the strip is on, in the units Left and Top are written in;
    // before the window has a handle there is nothing to ask about and the primary screen is used.
    private Rect StackWorkArea()
    {
        var handle = new WindowInteropHelper(this).Handle;
        if (handle == 0) return SystemParameters.WorkArea;
        var area = WinForms.Screen.FromHandle(handle).WorkingArea;
        var dpi = VisualTreeHelper.GetDpi(this);
        return Controls.StripResizeGeometry.ToDeviceIndependent(
            new Rect(area.Left, area.Top, area.Width, area.Height), dpi.DpiScaleX, dpi.DpiScaleY);
    }

    // Everything of the window that is not the list: the header, the capture button, the toast and
    // the paddings. Before the first layout pass there is nothing to measure, and the estimate of
    // StripResizeGeometry stands in; it is what keeps the bottom of the window on the screen.
    private double StackChromeHeight()
    {
        var measured = ActualHeight - CaptureList.ActualHeight;
        return double.IsFinite(measured) && measured > 0 ? measured : Controls.StripResizeGeometry.EstimatedChromeHeight;
    }

    private void PositionAtEdge()
    {
        var work = StackWorkArea();
        // The width the user dragged the strip to. The only ceiling is the working area of this
        // monitor: a width dragged out on a large screen is pulled back in when the strip opens on
        // a small one, and a settings file written by hand cannot produce a strip nobody can use.
        Width = Controls.StripResizeGeometry.ClampWidth(_settings.StackWidth, work.Width);
        // The height is remembered the same way, and it is the height of the list: the window is on
        // SizeToContent and follows it. The clamp takes the chrome into account, so a height stored
        // on a tall monitor cannot open a window whose lower half is below the screen.
        CaptureList.Height = Controls.StripResizeGeometry.ClampListHeight(_settings.StackHeight, work.Height, StackChromeHeight());
        // The height above was just assigned and ActualHeight still holds the one before it; the
        // placement below is built on the height the window is about to have.
        UpdateLayout();
        Left = work.Right - Width - Controls.StripResizeGeometry.EdgeGap;
        var height = Math.Max(ActualHeight, 160);
        var centred = Math.Max(work.Top + 24, work.Top + (work.Height - height) / 2);
        Top = Math.Max(work.Top, Math.Min(centred, work.Bottom - height));
    }

    // The right edge is taken once, at the start of the drag: reading it from Left + Width on every
    // delta would accumulate the rounding of each step and let the strip drift off the screen edge.
    private void OnWidthDragStarted(object sender, System.Windows.Controls.Primitives.DragStartedEventArgs e) =>
        _resizeRightEdge = Left + Width;

    private void OnWidthDragDelta(object sender, System.Windows.Controls.Primitives.DragDeltaEventArgs e)
    {
        var (left, width) = Controls.StripResizeGeometry.Resize(_resizeRightEdge, Width, e.HorizontalChange, StackWorkArea().Left);
        Width = width;
        Left = left;
    }

    private void OnWidthDragCompleted(object sender, System.Windows.Controls.Primitives.DragCompletedEventArgs e) =>
        MutateSettings(stored => stored with { StackWidth = Width });

    // The corner takes both sides at once. The right edge and the top edge are taken once, for the
    // same reason the width drag takes the right one: the strip keeps its place at the screen edge
    // and grows downwards instead of walking around while the pointer moves.
    private void OnCornerDragStarted(object sender, System.Windows.Controls.Primitives.DragStartedEventArgs e)
    {
        _resizeRightEdge = Left + Width;
        _resizeTop = Top;
        // The monitor is asked once: the working area cannot change under a drag, and reading it
        // costs a P/Invoke and a DPI lookup on every movement of the mouse.
        _resizeWorkArea = StackWorkArea();
    }

    private void OnCornerDragDelta(object sender, System.Windows.Controls.Primitives.DragDeltaEventArgs e)
    {
        var (left, width) = Controls.StripResizeGeometry.Resize(_resizeRightEdge, Width, e.HorizontalChange, _resizeWorkArea.Left);
        Width = width;
        Left = left;
        // The delta of a Thumb is measured from where the grip was when the drag began, so it is an
        // increment only while the grip travels with what it resizes. The bottom of the window
        // follows the height of the list, the grip sits on that bottom, and both stay true only
        // because the list carries a height rather than a maximum.
        CaptureList.Height = Controls.StripResizeGeometry.ResizeListHeight(
            CaptureList.Height, e.VerticalChange, StackChromeHeight(), _resizeTop, _resizeWorkArea.Bottom);
        Top = _resizeTop;
    }

    private void OnCornerDragCompleted(object sender, System.Windows.Controls.Primitives.DragCompletedEventArgs e) =>
        MutateSettings(stored => stored with { StackWidth = Width, StackHeight = CaptureList.Height });

    private async Task<bool> PrepareAsync()
    {
        await _pasteIntentTransition;
        // The paste button sends what is still waiting, so an empty strip and a strip of sent
        // captures are both "nothing to prepare", but they need different advice.
        var pending = PendingCaptures;
        if (pending.Count == 0)
        {
            SetStatus(UiLanguage.Text(Captures.Count == 0 ? "Сначала сделайте снимок." : "Все снимки уже отправлены. Сделайте новый снимок."), true);
            return false;
        }
        try
        {
            SetStatus(UiLanguage.Text("Готовим PNG и текст…"));
            _prepared = await _workspace.PrepareAsync(Captures, pending, string.Empty, SelectedProfile?.Id);
            PasteButton.IsEnabled = true;
            ShowToast(string.Format(UiLanguage.Text("Готово: {0} изображений · {1} заметок"), _prepared.Manifest.CaptureCount, _prepared.Manifest.NoteCount));
            return true;
        }
        catch (Exception ex) { SetStatus($"{UiLanguage.Text("Не удалось подготовить")}: {ex.Message}", true); return false; }
    }

    private async Task<bool> SaveAndCopyCommittedPackageAsync()
    {
        await _pasteIntentTransition;
        CancelReceiverEchoWatch();
        await _clipboardPublicationGate.WaitAsync();
        try
        {
            var pending = PendingCaptures;
            if (pending.Count == 0)
            {
                // Everything in the strip was already pasted: leave the user's clipboard alone
                // instead of publishing a package that repeats what the receiver already has.
                await SaveCoreAsync();
                _prepared = null;
                _ownedClipboardReceipt = null;
                SetPublished(null);
                SetStatus(string.Empty);
                return true;
            }
            _prepared = await _workspace.PrepareAsync(Captures, pending, string.Empty, SelectedProfile?.Id);
            var current = await _clipboard.CaptureAsync(CancellationToken.None);
            _ownedClipboardReceipt = await _clipboard.SetPackageGuardedAsync(_prepared.GetImagePathsInOrder(), _prepared.Manifest.PromptText, current.SequenceNumber, CancellationToken.None);
            SetPublished(Published(_prepared));
            NotifyCopied();
            SetStatus(string.Empty);
            return true;
        }
        catch (Exception ex)
        {
            await SaveAsync();
            SetStatus($"{UiLanguage.Text("Снимок сохранён, но буфер не обновлён")}: {ex.Message}. {UiLanguage.Text("Повторите копирование через меню.")}", true);
            return false;
        }
        finally { _clipboardPublicationGate.Release(); }
    }

    private async void OnPasteClick(object sender, RoutedEventArgs e) => await PasteAsync(true);

    private async Task PasteAsync(bool hideStack)
    {
        await _pasteIntentTransition;
        if (_busy) return;
        _busy = true;
        try
        {
            if (_prepared is null && !await PrepareAsync()) return;
            if (_prepared is null || SelectedProfile is null) return;
            if (hideStack)
            {
                Hide();
                Dispatcher.Invoke(() => { }, DispatcherPriority.Render);
                _ = DwmFlush();
                await Task.Delay(180);
            }
            var package = new PreparedPastePackage(_prepared.Manifest.ExportId, _prepared.GetImagePathsInOrder(), _prepared.Manifest.PromptText);
            var progress = new Progress<PasteProgress>(p => SetStatus(p.Message));
            var result = await _pasteCoordinator.PasteAsync(package, SelectedProfile, progress: progress);
            SetStatus(result.Message, result.Status is not (PasteStatus.CompletedVerified or PasteStatus.CompletedUnverified));
        }
        catch (Exception ex) { SetStatus($"{UiLanguage.Text("Вставка остановлена")}: {ex.Message}", true); }
        finally
        {
            _busy = false;
            if (hideStack) ShowStackWithoutActivation();
        }
    }

    private void OnMoreClick(object sender, RoutedEventArgs e)
    {
        var menu = new ContextMenu();
        var topmostItem = new MenuItem { Header = "Поверх других окон", IsCheckable = true, IsChecked = _settings.StackTopmost };
        topmostItem.Click += (_, _) => ToggleTopmost(topmostItem);
        menu.Items.Add(topmostItem);
        menu.Items.Add(new Separator());
        menu.Items.Add(MenuItem("Импортировать файл…", async () => await ImportFileAsync()));
        menu.Items.Add(MenuItem("Вставить изображение из буфера", async () => await ImportClipboardAsync()));
        if (_removed.Count > 0) menu.Items.Add(MenuItem("Вернуть удалённый снимок", RestoreRemoved));
        menu.Items.Add(MenuItem("Очистить ленту", ClearStackFromUserAsync));
        menu.Items.Add(new Separator());
        menu.Items.Add(MenuItem("Копировать пакет", async () => await CopyPackageAsync()));
        menu.Items.Add(MenuItem("Сохранить пакет…", async () => await SavePackageAsAsync()));
        menu.Items.Add(MenuItem("Настройки", OpenSettings));
        menu.Items.Add(new Separator());
        menu.Items.Add(MenuItem("Выйти", () => { _exiting = true; Close(); }));
        menu.PlacementTarget = (UIElement)sender;
        UiLanguage.Apply(menu);
        menu.IsOpen = true;
    }

    // The editor writes annotation defaults into the same file, so a change made from the strip is
    // applied on top of what is on disk right now, not on top of the snapshot taken at startup.
    private bool MutateSettings(Func<HotkeySettings, HotkeySettings> change)
    {
        try
        {
            if (!HotkeySettings.TryLoad(_settingsPath, out var stored))
                throw new InvalidOperationException(UiLanguage.Text("Файл настроек не читается."));
            var updated = change(stored);
            updated.Save(_settingsPath);
            _settings = updated;
            return true;
        }
        catch (Exception ex)
        {
            SetStatus($"{UiLanguage.Text("Не удалось сохранить настройки")}: {ex.Message}", true);
            return false;
        }
    }

    // An unreadable settings file must not freeze the panel: the click still applies to this session,
    // with the save error on screen. A write that failed for any other reason changes nothing, so the
    // checkmark that WPF has already flipped goes back to the state the panel is really in.
    private void ToggleTopmost(MenuItem item)
    {
        var desired = !_settings.StackTopmost;
        if (!MutateSettings(settings => settings with { StackTopmost = desired }) &&
            !HotkeySettings.TryLoad(_settingsPath, out _))
            _settings = _settings with { StackTopmost = desired };
        item.IsChecked = _settings.StackTopmost;
        ApplyTopmost();
    }

    // Modal dialogs owned by the strip would otherwise open behind a topmost strip. Suspensions nest
    // (a dialog opened over another one), so the strip returns on top only when the last one ends.
    private IDisposable SuspendTopmost()
    {
        _topmostSuspensions++;
        Topmost = false;
        return new TopmostSuspension(this);
    }

    private void ApplyTopmost() => Topmost = _topmostSuspensions == 0 && _settings.StackTopmost;

    private sealed class TopmostSuspension(EdgeStackWindow owner) : IDisposable
    {
        private bool _released;
        public void Dispose()
        {
            if (_released) return;
            _released = true;
            if (--owner._topmostSuspensions == 0) owner.ApplyTopmost();
        }
    }

    private void OnTargetClick(object sender, RoutedEventArgs e)
    {
        var menu = new ContextMenu { PlacementTarget = TargetButton };
        foreach (var profile in TargetProfiles)
        {
            var item = new MenuItem { Header = profile.DisplayName, IsCheckable = true, IsChecked = profile.Id == SelectedProfile?.Id, ToolTip = ProfileDetail(profile) };
            item.Click += (_, _) => SelectProfile(profile);
            menu.Items.Add(item);
        }
        UiLanguage.Apply(menu);
        menu.IsOpen = true;
    }

    private void SelectProfile(TargetProfile profile)
    {
        _selectedProfile = profile;
        RefreshTargetCaption();
        if (!_loading) { InvalidatePrepared(); QueueSave(); }
    }

    private void RefreshTargetCaption()
    {
        if (TargetCaption is null || TargetButton is null || SelectedProfile is null) return;
        TargetCaption.Text = SelectedProfile.DisplayName.Contains("Claude", StringComparison.OrdinalIgnoreCase) ? "Claude Code" : "Codex";
        TargetButton.ToolTip = ProfileDetail(SelectedProfile);
    }

    private static string ProfileDetail(TargetProfile profile) => $"{profile.DisplayName}\nПрофиль вставки: {profile.Verification switch { ProfileVerification.Verified => "проверен", ProfileVerification.Experimental => "экспериментальный", _ => "не проверен" }}";

    private MenuItem MenuItem(string text, Action action)
    {
        var item = new MenuItem { Header = text };
        item.Click += (_, _) => action();
        return item;
    }

    private MenuItem MenuItem(string text, Func<Task> action)
    {
        var item = new MenuItem { Header = text };
        item.Click += async (_, _) =>
        {
            try { await action(); }
            catch (Exception ex) { SetStatus($"{UiLanguage.Text("Не удалось выполнить действие")}: {ex.Message}", true); }
        };
        return item;
    }

    private async Task ImportFileAsync()
    {
        await _pasteIntentTransition;
        var filter = $"{UiLanguage.Text("Изображения")}|*.png;*.jpg;*.jpeg;*.webp;*.bmp;*.gif;*.tif;*.tiff|{UiLanguage.Text("Все файлы")}|*.*";
        var dialog = new OpenFileDialog { Filter = filter, Multiselect = true };
        bool? picked;
        using (SuspendTopmost()) picked = dialog.ShowDialog(this);
        if (picked != true) return;
        if (StripIsFull()) return;
        // A multiple selection larger than the free places takes the first of them, and the toast
        // about the limit replaces the one about the captures that were added.
        var free = SentCaptureRules.MaxStripCaptures - Captures.Count;
        var chosen = dialog.FileNames;
        var truncated = chosen.Length > free;
        var imported = 0;
        var failures = new List<string>();
        foreach (var path in chosen.Take(free))
        {
            try { Captures.Add(await _workspace.AddImageAsync(SessionWorkspace.LoadBitmap(path))); imported++; }
            catch (Exception ex) { failures.Add($"{Path.GetFileName(path)}: {ex.Message}"); }
        }
        Renumber(); InvalidatePrepared();
        var saved = await SaveAsync();
        // The clipboard package follows the stack even when the session file could not be written:
        // a receipt left pointing at the previous package makes the next Ctrl+V rotate the session.
        // Nothing was added means nothing changed, so the published package stays as it is.
        if (imported > 0) await RefreshOwnedClipboardAsync();
        // A failed import must survive the next status update, a successful one has to stay readable for a few seconds.
        if (failures.Count > 0) SetStatus($"{UiLanguage.Text("Не удалось добавить")}: {string.Join("; ", failures)}", true);
        else if (truncated) ShowToast(UiLanguage.Text("В ленте максимум 10 снимков. Отправьте или удалите лишние"));
        else if (saved) ShowToast(string.Format(UiLanguage.Text("Добавлено снимков: {0}"), imported));
    }

    private async Task ImportClipboardAsync()
    {
        await _pasteIntentTransition;
        if (StripIsFull()) return;
        if (!Clipboard.ContainsImage() || Clipboard.GetImage() is not { } image) { SetStatus(UiLanguage.Text("В буфере нет изображения."), true); return; }
        image.Freeze();
        Captures.Add(await _workspace.AddImageAsync(image));
        Renumber(); InvalidatePrepared();
        var saved = await SaveAsync();
        await RefreshOwnedClipboardAsync();
        if (saved) ShowToast(UiLanguage.Text("Изображение добавлено."));
    }

    // Copying and saving by hand are about the strip as a whole: they take every capture, sent ones
    // included, into a package of their own. Copying also becomes the current package, because an
    // intercepted Ctrl+V pastes `_prepared`, and that must be what the user just put on the clipboard.
    private async Task CopyPackageAsync()
    {
        await _pasteIntentTransition;
        if (Captures.Count == 0) { SetStatus(UiLanguage.Text("Сначала сделайте снимок."), true); return; }
        CancelReceiverEchoWatch();
        await _clipboardPublicationGate.WaitAsync();
        try
        {
            var package = await _workspace.PrepareAsync(Captures, Captures, string.Empty, SelectedProfile?.Id);
            var current = await _clipboard.CaptureAsync(CancellationToken.None);
            _ownedClipboardReceipt = await _clipboard.SetPackageGuardedAsync(package.GetImagePathsInOrder(), package.Manifest.PromptText, current.SequenceNumber, CancellationToken.None);
            SetPublished(Published(package));
            // The next capture rebuilds the package from the captures that are still waiting anyway.
            _prepared = package;
            UiSoundService.Copied(_settings);
            NotifyCopied();
            // The advice about the paste button only makes sense while that button is enabled, and it
            // is enabled by the captures that are still waiting.
            SetStatus(UiLanguage.Text(PendingCaptures.Count > 0
                ? "PNG и текст скопированы. Если получатель выберет один формат, используйте кнопку вставки."
                : "PNG и текст скопированы."));
        }
        finally { _clipboardPublicationGate.Release(); }
    }

    private async Task SavePackageAsAsync()
    {
        await _pasteIntentTransition;
        if (Captures.Count == 0) { SetStatus(UiLanguage.Text("Сначала сделайте снимок."), true); return; }
        var now = DateTime.Now;
        var dialog = new SavePackageWindow(_settings, now) { Owner = this };
        bool? picked;
        using (SuspendTopmost()) picked = dialog.ShowDialog();
        if (picked != true || dialog.Result is not { } choice) return;
        // The folder and the subfolder switch are remembered, so saving into the same place a second
        // time is one click; a settings file that cannot be written leaves its own error on screen
        // and must not stop the package from being saved.
        MutateSettings(stored => stored with { PackageSaveDirectory = choice.Directory, PackageCreateSubfolder = choice.CreateSubfolder });
        var package = await _workspace.PrepareAsync(Captures, Captures, string.Empty, SelectedProfile?.Id);
        var promptFileName = package.Manifest.PromptFileName;
        try
        {
            // Only what the user opened the folder for: the images and the text. manifest.json
            // describes the package for the application itself and stays in the working directory.
            var sources = Directory.EnumerateFiles(package.RootDirectory)
                .Where(path => Path.GetFileName(path).EndsWith(".png", StringComparison.OrdinalIgnoreCase) ||
                               (promptFileName.Length > 0 && Path.GetFileName(path) == promptFileName))
                .ToArray();
            // Without a subfolder the files share the folder with whatever is already there, so the
            // date of the package goes into every name; with one, the folder name already carries it.
            // Either way the whole set of destinations is checked before the first copy: a package
            // saved twice into the same place becomes "…-2" as a whole, never half of one and half
            // of another, and the user never sees a raw .NET message about an existing file.
            string destination, prefix;
            if (choice.CreateSubfolder)
            {
                var folder = SaveNaming.FreeName(choice.FolderName,
                    candidate => sources.Any(path => File.Exists(Path.Combine(choice.Directory, candidate, Path.GetFileName(path)))));
                if (folder is null) { SetStatus(UiLanguage.Text("В этой папке нет свободного имени для пакета. Выберите другую папку."), true); return; }
                destination = Path.Combine(choice.Directory, folder);
                prefix = string.Empty;
            }
            else
            {
                var stamp = SaveNaming.FreeName($"{now:yyyyMMdd-HHmmss}",
                    candidate => sources.Any(path => File.Exists(Path.Combine(choice.Directory, $"{candidate}-{Path.GetFileName(path)}"))));
                if (stamp is null) { SetStatus(UiLanguage.Text("В этой папке нет свободного имени для пакета. Выберите другую папку."), true); return; }
                destination = choice.Directory;
                prefix = $"{stamp}-";
            }
            Directory.CreateDirectory(destination);
            foreach (var path in sources)
                File.Copy(path, Path.Combine(destination, prefix + Path.GetFileName(path)), overwrite: false);
            ShowToast(UiLanguage.Text("Пакет сохранён."));
        }
        catch (Exception ex) { SetStatus($"{UiLanguage.Text("Не удалось сохранить пакет")}: {ex.Message}", true); }
    }

    // The wizard of the first run, and the tray item that opens it again. Its shortcut field goes
    // through the same registration as the settings dialog, so a taken shortcut is reported inside
    // the wizard and the user cannot leave that step with it.
    private void ShowOnboarding(bool howToOnly = false)
    {
        StartupTrace.Write(_options, $"Onboarding opens: hotkeys={_hotkeys is not null}, howToOnly={howToOnly}");
        // The how-to slides opened from the tray have no shortcut field, so the registered
        // shortcuts stay as they are for the whole time the slides are on screen.
        if (howToOnly)
        {
            var readableHowTo = HotkeySettings.TryLoad(_settingsPath, out var currentHowTo);
            if (!readableHowTo) currentHowTo = HotkeySettings.Default;
            var slides = new OnboardingWindow(currentHowTo, howToOnly: true, settingsFileExists: File.Exists(_settingsPath))
            {
                Trace = message => StartupTrace.Write(_options, message)
            };
            using (SuspendTopmost()) slides.ShowDialog();
            return;
        }
        _hotkeys?.Unregister("capture");
        _hotkeys?.Unregister("fullscreen-save");
        try
        {
            // A file that exists but does not parse used to swallow the wizard, and the first run
            // ended with a hidden strip and a line of status nobody was there to read. The wizard
            // opens on the defaults instead, and everything it collects is written over that file
            // as a whole: merging into it would fail on the very read that failed here.
            var readable = HotkeySettings.TryLoad(_settingsPath, out var current);
            if (!readable) current = HotkeySettings.Default;
            // A file that is there carries a language the user has chosen once, and the wizard opens
            // in it; the locale is only for a machine that has no file at all.
            var wizard = new OnboardingWindow(current, settingsFileExists: readable && File.Exists(_settingsPath))
            {
                TryApply = candidate => ApplyOnboarding(candidate, readable),
                MarkPassed = () => CompleteOnboarding(readable),
                Trace = message => StartupTrace.Write(_options, message)
            };
            using (SuspendTopmost()) wizard.ShowDialog();
            if (!readable) SetStatus(UiLanguage.Text("Файл настроек не читался, настройки созданы заново"), true);
        }
        finally
        {
            _hotkeys?.Unregister("capture");
            _hotkeys?.Unregister("fullscreen-save");
            _ = RegisterHotkeys();
        }
    }

    // Every message goes back in the language of the wizard, not in the one the strip is showing:
    // the candidate carries the language its first step has just chosen.
    private string? ApplyOnboarding(HotkeySettings candidate, bool merge)
    {
        var language = candidate.Language;
        try
        {
            if (_hotkeys is null) return UiLanguage.Text("Регистрация клавиш недоступна. Перезапустите SnapBrief.", language);
            _hotkeys.Unregister("capture");
            if (candidate.CaptureEnabled) _hotkeys.Register("capture", candidate.CaptureGesture);
            if (!WriteOnboarding(candidate, merge)) return UiLanguage.Text("Не удалось сохранить настройки", language);
            UiLanguage.Current = _settings.Language;
            UiLanguage.Apply(this, _settings.Language);
            return null;
        }
        catch (Exception ex)
        {
            _hotkeys?.Unregister("capture");
            StartupTrace.Write(_options, $"Onboarding ({HotkeySettings.Find(candidate.CaptureId).Label}): {ex}");
            if (ex is Win32Exception { NativeErrorCode: 1409 })
                return UiLanguage.Text("Эта клавиша уже занята. Освободите её в другом приложении или выберите другую.", language);
            return ex is Win32Exception
                ? UiLanguage.Text("Не удалось назначить сочетание. Возможно, оно уже занято — нажмите другое.", language)
                : $"{UiLanguage.Text("Не удалось сохранить настройки", language)}: {ex.Message}";
        }
    }

    // Only the three fields the wizard owns, on top of the file as it is now; a file that could not
    // be read is replaced whole, because there is nothing in it to merge into.
    private bool WriteOnboarding(HotkeySettings candidate, bool merge)
    {
        if (merge)
            return MutateSettings(stored => stored with
            {
                CaptureId = candidate.CaptureId, Language = candidate.Language,
                OnboardingVersion = candidate.OnboardingVersion
            });
        try { candidate.Save(_settingsPath); _settings = candidate; return true; }
        catch (Exception ex)
        {
            SetStatus($"{UiLanguage.Text("Не удалось сохранить настройки", candidate.Language)}: {ex.Message}", true);
            return false;
        }
    }

    // The wizard counts as passed the moment its window is gone, however it was closed, and the
    // version is written on its own: a shortcut that stayed in conflict keeps the user on its step,
    // but must not bring the whole wizard back on every start. The tray opens it again at any time.
    private void CompleteOnboarding(bool merge)
    {
        if (_settings.OnboardingVersion >= OnboardingWindow.CurrentVersion) return;
        if (merge) MutateSettings(stored => stored with { OnboardingVersion = OnboardingWindow.CurrentVersion });
        else WriteOnboarding(_settings with { OnboardingVersion = OnboardingWindow.CurrentVersion }, merge: false);
    }

    private void OpenSettings()
    {
        _hotkeys?.Unregister("capture");
        _hotkeys?.Unregister("fullscreen-save");
        try
        {
            // The editor may have written annotation defaults since this window loaded its snapshot,
            // so the dialog edits the file as it is now and saves its own fields on top of that. A file
            // that exists but cannot be read is never opened as defaults: saving would wipe it.
            if (!HotkeySettings.TryLoad(_settingsPath, out var current))
            {
                SetStatus(UiLanguage.Text("Файл настроек не читается."), true);
                return;
            }
            var dialog = new HotkeySettingsWindow(current, showPasteSettings: false)
            {
                Owner = this,
                TryApply = candidate =>
                {
                    try
                    {
                        if (_hotkeys is null) return UiLanguage.Text("Регистрация клавиш недоступна. Перезапустите SnapBrief.");
                        _hotkeys.Unregister("capture");
                        _hotkeys.Unregister("fullscreen-save");
                        if (candidate.CaptureEnabled) _hotkeys.Register("capture", candidate.CaptureGesture);
                        if (candidate.FullscreenSaveEnabled) _hotkeys.Register("fullscreen-save", candidate.FullscreenSaveGesture);
                        // Only the fields this dialog owns are written, on top of the file as it is now:
                        // the editor may have saved its annotation defaults while the dialog was open.
                        var merged = MutateSettings(stored => stored with
                        {
                            CaptureId = candidate.CaptureId, FullscreenSaveId = candidate.FullscreenSaveId,
                            CaptureEnabled = candidate.CaptureEnabled, FullscreenSaveEnabled = candidate.FullscreenSaveEnabled,
                            ShowNotifications = candidate.ShowNotifications, RememberRegion = candidate.RememberRegion,
                            CaptureCursor = candidate.CaptureCursor, AutoSaveCaptures = candidate.AutoSaveCaptures,
                            PlaySounds = candidate.PlaySounds, SoundVolume = candidate.SoundVolume,
                            ClearStackAfterPaste = candidate.ClearStackAfterPaste,
                            SaveFormat = candidate.SaveFormat, JpegQuality = candidate.JpegQuality,
                            SaveDirectory = candidate.SaveDirectory, Language = candidate.Language,
                            AccentId = candidate.AccentId
                        });
                        if (!merged) return UiLanguage.Text("Не удалось сохранить настройки");
                        ThemeService.Apply(_settings.Theme, _settings.AccentId);
                        UiLanguage.Current = _settings.Language;
                        UiLanguage.Apply(this, _settings.Language);
                        return null;
                    }
                    catch (Exception ex)
                    {
                        _hotkeys?.Unregister("capture");
        _hotkeys?.Unregister("fullscreen-save");
                        StartupTrace.Write(_options, $"Hotkey settings ({HotkeySettings.Find(candidate.CaptureId).Label}): {ex}");
                        if (ex is Win32Exception { NativeErrorCode: 1409 })
                            return UiLanguage.Text("Эта клавиша уже занята. Освободите её в другом приложении или выберите другую.");
                        return ex is Win32Exception
                            ? UiLanguage.Text("Не удалось назначить сочетание. Возможно, оно уже занято — нажмите другое.")
                            : $"{UiLanguage.Text("Не удалось сохранить настройки")}: {ex.Message}";
                    }
                }
            };
            bool? saved;
            using (SuspendTopmost()) saved = dialog.ShowDialog();
            if (saved == true) SetStatus(string.Empty);
        }
        finally
        {
            _hotkeys?.Unregister("capture");
        _hotkeys?.Unregister("fullscreen-save");
            _ = RegisterHotkeys();
        }
    }

    // Letters go to the captures that are still waiting, so the badge in the strip matches the
    // letter the same capture gets in prompt.md; a sent capture keeps the letter it left with.
    private void Renumber()
    {
        var labels = SentCaptureRules.StripLabels([.. Captures.Select(capture => capture.IsSent)]);
        for (var i = 0; i < Captures.Count; i++) if (labels[i] is { } label) Captures[i].DisplayLabel = label;
        CaptureList?.Items.Refresh();
        var pending = PendingCaptures.Count;
        CountText.Text = pending.ToString();
        PasteButton.IsEnabled = pending > 0;
    }

    private IReadOnlyList<CaptureItem> PendingCaptures => SentCaptureRules.ForPackage(Captures, capture => capture.IsSent);

    private void InvalidatePrepared() { _prepared = null; }

    private static PublishedPackage Published(PreparedExport export) => new(
        [.. export.GetImagePathsInOrder()],
        export.Manifest.PromptText,
        [.. export.Manifest.Images.Select(image => image.CaptureId)],
        export.RootDirectory,
        export.Manifest.NoteCount);

    // The export directory of the published package is pinned in the workspace: its PNGs are the ones
    // on the clipboard, so the revisions written by a manual "Copy package" must not trim it away.
    private void SetPublished(PublishedPackage? published)
    {
        _published = published;
        PinExportDirectories();
    }

    // The prepared export is what an intercepted Ctrl+V pastes and the published one is what is on
    // the clipboard; the two diverge, and a revision either of them points at must survive the trim.
    // Going through a property keeps the pin in step with every assignment of `_prepared`.
    private PreparedExport? _prepared
    {
        get => _preparedExport;
        set { _preparedExport = value; PinExportDirectories(); }
    }

    private void PinExportDirectories() =>
        _workspace.PinnedExportDirectories = [.. new[] { _published?.ExportDirectory, _preparedExport?.RootDirectory }.OfType<string>()];

    private void QueueSave() { _saveTimer.Stop(); _saveTimer.Start(); }
    // The clipboard follows the strip even when the session file could not be written: an old receipt
    // would make the next Ctrl+V paste a package that no longer matches what the strip holds.
    private async void OnSaveTimerTick(object? sender, EventArgs e) { _saveTimer.Stop(); await SaveAsync(); await RefreshOwnedClipboardAsync(); }

    private async Task<bool> SaveAsync()
    {
        await _pasteIntentTransition;
        return await SaveCoreAsync();
    }

    // The paste completion runs as _pasteIntentTransition itself and must not await it.
    private async Task<bool> SaveCoreAsync()
    {
        await _workspaceMutationGate.WaitAsync();
        try { await _workspace.SaveAsync(Captures, _legacyGlobalNote, SelectedProfile?.Id); return true; }
        catch (Exception ex) { SetStatus($"{UiLanguage.Text("Не удалось сохранить")}: {ex.Message}", true); return false; }
        finally { _workspaceMutationGate.Release(); }
    }

    // Clearing the strip deletes the directory of the current session and opens an empty one; the
    // panel itself stays visible, and there is no undo: the captures are gone from the disk, which
    // is why the question comes first.
    private async Task<bool> ClearStackAsync(bool clipboardGateHeld = false)
    {
        // Clearing gives the clipboard back, so it belongs in the same critical section as every
        // other publication. The gate is taken here in the same order as everywhere else (before the
        // workspace one); the ClearStackAfterPaste path runs inside CompletePasteIntentAsync, which
        // holds it already.
        if (clipboardGateHeld) return await ClearStackCoreAsync();
        await _clipboardPublicationGate.WaitAsync();
        try { return await ClearStackCoreAsync(); }
        finally { _clipboardPublicationGate.Release(); }
    }

    private async Task<bool> ClearStackCoreAsync()
    {
        if (_sessionResetting) return false;
        _sessionResetting = true;
        CancelReceiverEchoWatch();
        _saveTimer.Stop();
        await _workspaceMutationGate.WaitAsync();
        try
        {
            // The clipboard goes back first: the published package is a list of paths into the
            // session directory, and those files are about to be deleted.
            await ReleaseOwnedClipboardCoreAsync();
            await _workspace.DiscardCurrentSessionAsync(message => StartupTrace.Write(_options, message));
            _loading = true;
            Captures.Clear();
            _legacyGlobalNote = string.Empty;
            _removed.Clear();
            // An undo toast still on screen would offer to restore into a session that no longer
            // holds the capture it points at.
            HideToastNow();
            _prepared = null;
            Renumber();
            SetStatus(string.Empty);
            ShowToast(UiLanguage.Text("Лента очищена"));
            return true;
        }
        catch (Exception ex)
        {
            SetStatus($"{UiLanguage.Text("Не удалось очистить ленту")}: {ex.Message}", true);
            return false;
        }
        finally
        {
            _workspaceMutationGate.Release();
            _loading = false;
            _sessionResetting = false;
        }
    }

    // The package lives on the clipboard until the next capture or until the strip is cleared, so
    // clearing gives the clipboard back — but only while it still holds our own write; a package
    // another application has already replaced is not ours to erase.
    private async Task ReleaseOwnedClipboardCoreAsync()
    {
        if (_ownedClipboardReceipt is { } receipt)
        {
            try
            {
                if (await _clipboard.IsCurrentAsync(receipt, CancellationToken.None))
                    await _clipboard.SetTextGuardedAsync(string.Empty, receipt.SequenceNumber, CancellationToken.None);
            }
            catch (ClipboardChangedException) { }
            catch (Exception ex) { StartupTrace.Write(_options, $"Clear strip: the clipboard was not released: {ex.Message}"); }
        }
        _ownedClipboardReceipt = null;
        SetPublished(null);
    }

    private async Task ClearStackFromUserAsync()
    {
        await _pasteIntentTransition;
        if (!ConfirmSessionDiscard()) return;
        await ClearStackAsync();
    }

    // Clearing the strip and leaving the application delete the captures from the disk, so both ask
    // first. An empty strip has nothing to lose and never asks, and the question carries the box
    // that turns it off; the automatic "clear after pasting" is not a user decision and stays silent.
    private bool ConfirmSessionDiscard()
    {
        if (Captures.Count == 0 || !_settings.ConfirmSessionDiscard) return true;
        var dialog = new DiscardSessionWindow(_settings) { Owner = this };
        bool? confirmed;
        using (SuspendTopmost()) confirmed = dialog.ShowDialog();
        if (confirmed != true) return false;
        // A settings file that cannot be written leaves its own error on screen and must not stop
        // the deletion the user has just confirmed.
        if (dialog.DoNotAskAgain) MutateSettings(stored => stored with { ConfirmSessionDiscard = false });
        return true;
    }

    private async void OnClearStackClick(object sender, RoutedEventArgs e) => await ClearStackFromUserAsync();

    // A completed paste keeps the captures in the strip and only marks the ones that were in the
    // package. Captures that are still waiting rebuild the clipboard, so the next Ctrl+V cannot
    // repeat what was already sent; when nothing is left waiting the just-pasted package stays on
    // the clipboard, and repeating Ctrl+V pastes the same set into another application.
    private async Task MarkCapturesSentAsync(Guid[] idsAtIntent)
    {
        if (_settings.ClearStackAfterPaste) { await ClearStackAsync(clipboardGateHeld: true); return; }
        var ids = idsAtIntent.ToHashSet();
        var marked = false;
        foreach (var capture in Captures)
            if (ids.Contains(capture.Id) && !capture.IsSent) { capture.IsSent = true; marked = true; }
        if (!marked) return;
        Renumber();
        await SaveCoreAsync();
        if (PendingCaptures.Count == 0) return;
        InvalidatePrepared();
        CancelReceiverEchoWatch();
        // The strip published this package itself a moment ago; a balloon about copying would
        // describe a paste the user has just made by hand.
        await RefreshOwnedClipboardCoreAsync(notifyCopied: false);
    }

    private async Task RefreshOwnedClipboardAsync()
    {
        await _pasteIntentTransition;
        CancelReceiverEchoWatch();
        await _clipboardPublicationGate.WaitAsync();
        try { await RefreshOwnedClipboardCoreAsync(); }
        finally { _clipboardPublicationGate.Release(); }
    }

    private async Task RefreshOwnedClipboardCoreAsync(bool notifyCopied = true)
    {
        // A session being reset is about to give the clipboard back; republishing into it would
        // leave a package pointing at captures the reset has already taken away.
        if (_sessionResetting || _ownedClipboardReceipt is not { } receipt) return;
        try
        {
            if (!await _clipboard.IsCurrentAsync(receipt, CancellationToken.None))
            {
                _ownedClipboardReceipt = null;
                SetPublished(null);
                return;
            }
            var pending = PendingCaptures;
            if (pending.Count == 0)
            {
                // A strip that holds only sent captures keeps the package that was pasted from it:
                // the clipboard, the published package and the receipt all still describe it, so the
                // same set can be pasted again elsewhere; the prepared export may already be gone,
                // and that is exactly why the two are tracked apart. Only a strip that is really
                // empty gives the clipboard back.
                if (Captures.Count > 0) return;
                _ownedClipboardReceipt = await _clipboard.SetTextGuardedAsync(string.Empty, receipt.SequenceNumber, CancellationToken.None);
                SetPublished(null);
                _prepared = null;
                return;
            }
            _prepared = await _workspace.PrepareAsync(Captures, pending, string.Empty, SelectedProfile?.Id);
            _ownedClipboardReceipt = await _clipboard.SetPackageGuardedAsync(_prepared.GetImagePathsInOrder(), _prepared.Manifest.PromptText, receipt.SequenceNumber, CancellationToken.None);
            SetPublished(Published(_prepared));
            if (notifyCopied) NotifyCopied();
        }
        catch (ClipboardChangedException)
        {
            _ownedClipboardReceipt = null;
            SetPublished(null);
        }
        catch (Exception ex)
        {
            // The receipt no longer describes anything we can trust, and this method cannot tell
            // whether the session itself was written: the message promises only what is known.
            _ownedClipboardReceipt = null;
            SetPublished(null);
            SetStatus($"{UiLanguage.Text("Буфер не обновлён")}: {ex.Message}", true);
        }
    }

    private async Task SeedDemoAsync()
    {
        for (var i = 0; i < 3; i++)
        {
            var capture = await _workspace.AddImageAsync(SessionWorkspace.CreateDemoBitmap(i));
            capture.DisplayLabel = CaptureLabels.ForIndex(i);
            capture.Note = i == 2 ? "Текст обрезается" : string.Empty;
            if (i < 2) capture.Annotations.Add(new AnnotationItem
            {
                Kind = i == 0 ? EditorTool.Rectangle : EditorTool.Arrow,
                Points = [new Point(650, 360), new Point(980, 520)],
                Color = Color.FromRgb(47, 140, 255), Thickness = 4,
                Note = i == 0 ? "Увеличить кнопку" : "Перенести пункт выше"
            });
            Captures.Add(capture);
        }
        _legacyGlobalNote = "Сохранить цвета";
        await SaveAsync();
    }

    private void SetStatus(string text, bool error = false)
    {
        if (!Dispatcher.CheckAccess()) { Dispatcher.Invoke(() => SetStatus(text, error)); return; }
        if (error) StartupTrace.Write(_options, text);
        StatusText.Text = text;
        StatusText.Visibility = error ? Visibility.Visible : Visibility.Collapsed;
        StatusText.Foreground = new SolidColorBrush(Color.FromRgb(255, 155, 149));
    }

    // Plain SetStatus keeps non-error text hidden; a toast shows a confirmation for a few seconds and
    // can carry one action. Only one toast lives at a time: a new one replaces whatever is on screen.
    private void ShowToast(string text, string? actionText = null, Action? action = null)
    {
        if (!Dispatcher.CheckAccess()) { Dispatcher.Invoke(() => ShowToast(text, actionText, action)); return; }
        _toastTimer.Stop();
        _toastGeneration++;
        _toastAction = action;
        ToastText.Text = text;
        ToastAction.Content = actionText ?? string.Empty;
        ToastAction.Visibility = actionText is null || action is null ? Visibility.Collapsed : Visibility.Visible;
        Toast.Visibility = Visibility.Visible;
        Toast.BeginAnimation(OpacityProperty, null);
        if (SystemParameters.ClientAreaAnimation) Toast.BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, ToastFade));
        else Toast.Opacity = 1;
        _toastTimer.Start();
    }

    private void OnToastTimerTick(object? sender, EventArgs e)
    {
        _toastTimer.Stop();
        var generation = _toastGeneration;
        if (!SystemParameters.ClientAreaAnimation) { HideToast(generation); return; }
        var fade = new DoubleAnimation(Toast.Opacity, 0, ToastFade);
        fade.Completed += (_, _) => HideToast(generation);
        Toast.BeginAnimation(OpacityProperty, fade);
    }

    // A toast shown while the previous one was fading out keeps its own generation, so the late
    // fade-out of the older toast must not hide the newer message.
    private void HideToast(int generation)
    {
        if (generation != _toastGeneration) return;
        Toast.BeginAnimation(OpacityProperty, null);
        Toast.Opacity = 0;
        Toast.Visibility = Visibility.Collapsed;
        _toastAction = null;
    }

    // A toast that outlives the panel it belongs to would greet the next show with stale text,
    // so hiding the panel takes the toast with it instead of waiting for the timer.
    private void HideToastNow()
    {
        _toastTimer.Stop();
        _toastGeneration++;
        HideToast(_toastGeneration);
    }

    private void OnToastActionClick(object sender, RoutedEventArgs e)
    {
        var action = _toastAction;
        HideToastNow();
        action?.Invoke();
    }

    private void OnHeaderMouseDown(object sender, MouseButtonEventArgs e) { if (e.LeftButton == MouseButtonState.Pressed) DragMove(); }

    private void OnCaptureThumbMouseEnter(object sender, MouseEventArgs e) => UiSoundService.Tick(_settings);

    private void OnCaptureListMouseWheel(object sender, MouseWheelEventArgs e) => UiSoundService.Tick(_settings);

    // A click on a card goes straight to the editor: the capture opens with every annotation it
    // already carries, and the strip stays hidden while the full-screen editor is up.
    private async void OnOpenCaptureClick(object sender, RoutedEventArgs e)
    {
        await _pasteIntentTransition;
        if (_busy || sender is not Button { Tag: CaptureItem capture }) return;

        _busy = true;
        capture.IsSelected = true;
        CaptureList.Items.Refresh();
        var stackHidden = false;
        var requestNext = false;
        try
        {
            HideForCapture();
            stackHidden = true;
            var index = Captures.IndexOf(capture);
            if (index < 0) return;
            // The editor labels the capture by its place among the captures that were not sent yet.
            var labelIndex = Captures.Take(index).Count(other => !other.IsSent);
            var result = await OverlayEditorWindow.EditExistingAsync(_workspace, capture, labelIndex);
            if (!result.Cancelled && result.Capture is not null)
            {
                // An edited capture no longer matches what the receiver got, so it returns to the package
                // even though the editor works on a copy that carries the sent flag over.
                result.Capture.IsSent = false;
                Captures[index] = result.Capture;
                Renumber();
                InvalidatePrepared();
                requestNext = await SaveAndCopyCommittedPackageAsync() && result.AddNext;
            }
        }
        catch (Exception ex) { SetStatus($"Не удалось открыть снимок: {ex.Message}", true); }
        finally
        {
            capture.IsSelected = false;
            CaptureList.Items.Refresh();
            _busy = false;
            if (stackHidden) ShowStackWithoutActivation();
        }
        if (requestNext) await CaptureLoopAsync();
    }

    private void OnCaptureListMouseDown(object sender, MouseButtonEventArgs e)
    {
        _dragStart = e.GetPosition(CaptureList);
        _draggedCapture = FindAncestor<ContentPresenter>((DependencyObject)e.OriginalSource)?.Content as CaptureItem;
    }

    private void OnCaptureListMouseMove(object sender, MouseEventArgs e)
    {
        if (e.LeftButton != MouseButtonState.Pressed || _draggedCapture is null) return;
        var point = e.GetPosition(CaptureList);
        if (Math.Abs(point.Y - _dragStart.Y) < SystemParameters.MinimumVerticalDragDistance) return;
        DragDrop.DoDragDrop(CaptureList, _draggedCapture, DragDropEffects.Move);
    }

    private async void OnCaptureListDrop(object sender, DragEventArgs e)
    {
        await _pasteIntentTransition;
        if (!e.Data.GetDataPresent(typeof(CaptureItem))) return;
        var source = (CaptureItem)e.Data.GetData(typeof(CaptureItem));
        var target = FindAncestor<ContentPresenter>((DependencyObject)e.OriginalSource)?.Content as CaptureItem;
        if (target is null || ReferenceEquals(source, target)) return;
        Captures.Move(Captures.IndexOf(source), Captures.IndexOf(target));
        Renumber(); InvalidatePrepared(); if (await SaveAsync()) ShowToast(UiLanguage.Text("Порядок снимков изменён.")); await RefreshOwnedClipboardAsync();
    }

    private async Task RestoreRemoved()
    {
        await _pasteIntentTransition;
        if (_removed.Count == 0) return;
        // The capture stays on the stack of removed ones: after another capture leaves the strip
        // there is room again, and "Restore" still has something to bring back.
        if (StripIsFull()) return;
        var removed = _removed.Pop();
        Captures.Insert(Math.Clamp(removed.Index, 0, Captures.Count), removed.Capture);
        Renumber(); InvalidatePrepared(); if (await SaveAsync()) ShowToast(UiLanguage.Text("Снимок восстановлен.")); await RefreshOwnedClipboardAsync();
    }

    private static T? FindAncestor<T>(DependencyObject? current) where T : DependencyObject
    {
        while (current is not null) { if (current is T target) return target; current = VisualTreeHelper.GetParent(current); }
        return null;
    }

    private async void OnClosing(object? sender, CancelEventArgs e)
    {
        if (_allowClose) { CancelReceiverEchoWatch(); _hotkeys?.Dispose(); _pasteIntentObserver.Dispose(); _clipboard.Dispose(); _trayIcon.Visible = false; _trayIcon.Dispose(); return; }
        e.Cancel = true;
        _saveTimer.Stop();
        HideToastNow();
        if (_exiting)
        {
            // The tray menu is a window of its own and its clicks arrive even while the question
            // below runs its own message loop: without this a second "Exit" would put a second
            // dialog on screen and run the deletion and the close twice.
            if (_leaving) return;
            _leaving = true;
            try
            {
                // Leaving takes the captures of the session with it, so the question comes before
                // anything is written or deleted, and a cancelled exit leaves the strip as it was.
                if (!ConfirmSessionDiscard()) { _exiting = false; ShowStackWithoutActivation(); return; }
                // SaveAsync is deliberately not called here: it would write session.json back into the
                // directory that is about to go.
                await DiscardSessionOnExitAsync();
            }
            finally { _leaving = false; }
            _allowClose = true;
            Close();
            return;
        }
        // Hiding to the tray is not the end of the session: the strip keeps its captures, and a
        // shutdown of the system leaves them to the next start to clean up.
        if (!await SaveAsync()) { ShowStackWithoutActivation(); return; }
        Hide();
    }

    // The same deletion as "Clear the strip", under the same two gates and in the same order: the
    // tray menu is served even inside the modal editor and inside an export that is still running,
    // and a directory deleted from under one of them comes back as a half-written session whose
    // paths are already on the clipboard.
    private async Task DiscardSessionOnExitAsync()
    {
        // A capture or the editor is still on screen: whatever it writes would land in the
        // directory right after it was deleted, so the deletion is left to the purge of the next
        // start, which takes the whole root anyway.
        if (_busy)
        {
            StartupTrace.Write(_options, "Exit: the session was left to the next start, an operation was still running.");
            return;
        }
        await _clipboardPublicationGate.WaitAsync();
        try
        {
            await _workspaceMutationGate.WaitAsync();
            try
            {
                // Nothing may publish or rebuild the clipboard from here on: the strip is going.
                _sessionResetting = true;
                _saveTimer.Stop();
                CancelReceiverEchoWatch();
                // The package on the clipboard is a list of paths into the session directory: the
                // clipboard is given back first, so a paste made after the exit is honestly empty
                // instead of pointing at files that are no longer there.
                await ReleaseOwnedClipboardCoreAsync();
                await _workspace.DiscardCurrentSessionAsync(message => StartupTrace.Write(_options, message));
            }
            finally { _workspaceMutationGate.Release(); }
        }
        // Nothing can be shown to the user at this point, and the next start purges the root anyway.
        catch (Exception ex) { StartupTrace.Write(_options, $"Exit: the session was not discarded: {ex}"); }
        finally { _clipboardPublicationGate.Release(); }
    }

    // Raise the strip without activating it; whether it stays above other applications is the StackTopmost setting.
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWindowPos(IntPtr window, IntPtr after, int x, int y, int width, int height, uint flags);

    [DllImport("dwmapi.dll")]
    private static extern int DwmFlush();

    [DllImport("user32.dll")]
    private static extern bool SetWindowDisplayAffinity(IntPtr hwnd, uint affinity);
}
