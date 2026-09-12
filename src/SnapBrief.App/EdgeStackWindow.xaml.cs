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
    private PreparedExport? _prepared;
    private ClipboardWriteReceipt? _ownedClipboardReceipt;
    private string? _ownedClipboardPromptText;
    private string _legacyGlobalNote = string.Empty;
    private bool _loadedOnce;
    private bool _busy;
    private bool _loading;
    private bool _exiting;
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
        _settings = HotkeySettings.Load(_settingsPath);
        UiLanguage.Current = _settings.Language;
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
            if (_sessionResetting || !_pasteIntentTransition.IsCompleted || _clipboardPublicationGate.CurrentCount == 0 ||
                _ownedClipboardReceipt is not { } receipt ||
                intent.ClipboardSequenceNumber != receipt.SequenceNumber ||
                _ownedClipboardPromptText is null || _prepared is null)
            {
                StartupTrace.Write(_options, $"PasteIntent predicate: state not ready (resetting={_sessionResetting}, transitionDone={_pasteIntentTransition.IsCompleted}, gate={_clipboardPublicationGate.CurrentCount}, ownedSeq={receiptSeq}, intentSeq={intent.ClipboardSequenceNumber}, prompt={_ownedClipboardPromptText is not null}, prepared={_prepared is not null}, gesture={intent.Gesture})");
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
        _trayIcon.ContextMenuStrip.Items.Add("Показать стопку", null, (_, _) => Dispatcher.Invoke(ShowStackWithoutActivation));
        _trayIcon.ContextMenuStrip.Items.Add("Настройки", null, (_, _) => Dispatcher.Invoke(() => { ShowStackWithoutActivation(); OpenSettings(); }));
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
        Hide();
        Opacity = 1;
        StartupTrace.Write(_options, "EdgeStack.Loaded entered");
        _loading = true;
        try
        {
            if (_options.Demo)
                await SeedDemoAsync();
            else
            {
                foreach (var capture in await _workspace.LoadCurrentAsync()) Captures.Add(capture);
                _legacyGlobalNote = _workspace.RestoredGlobalNote;
                if (_workspace.RestoredProfileId is { } id) _selectedProfile = TargetProfiles.FirstOrDefault(p => p.Id == id) ?? _selectedProfile;
                RefreshTargetCaption();
            }
            Renumber();
            PositionAtEdge();
            StartupTrace.Write(_options, $"EdgeStack.Loaded completed with {Captures.Count} captures");
        }
        catch (Exception ex) { SetStatus($"{UiLanguage.Text("Не удалось восстановить сессию")}: {ex.Message}", true); StartupTrace.Write(_options, ex.ToString()); }
        finally { _loading = false; }
    }

    private void OnSourceInitialized(object? sender, EventArgs e)
    {
        try
        {
            _hotkeys = new WindowsGlobalHotkeyService(new WindowInteropHelper(this).Handle);
            _ = SetWindowDisplayAffinity(new WindowInteropHelper(this).Handle, 0x00000011);
            _hotkeys.Pressed += OnHotkey;
            _ = RegisterHotkeys();
        }
        catch (Exception ex) { SetStatus($"{UiLanguage.Text("Захват")}: {ex.Message}", true); }
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

    private void OnHotkey(object? sender, GlobalHotkeyPressed e) => Dispatcher.InvokeAsync(async () =>
    {
        if (e.Id == "capture" && !OverlayEditorWindow.TryCommitAndRequestNext()) await CaptureLoopAsync();
        else if (e.Id == "fullscreen-save") await SaveFullscreenAsync();
    });

    private void OnPasteIntentObserved(object? sender, PasteIntentObserved e)
    {
        var receiptAtIntent = _ownedClipboardReceipt;
        var promptAtIntent = _ownedClipboardPromptText;
        StartupTrace.Write(_options, $"PasteIntent observed: gesture={e.Gesture}, intercepted={e.IsIntercepted}, seq={e.ClipboardSequenceNumber}, ownedSeq={receiptAtIntent?.SequenceNumber}, pid={e.ForegroundProcessId}");
        if (receiptAtIntent is null || e.ClipboardSequenceNumber != receiptAtIntent.Value.SequenceNumber)
        {
            _ = LogClipboardDiagnosticsAsync();
            return;
        }
        if (promptAtIntent is null)
        {
            SetStatus(UiLanguage.Text("Не удалось подтвердить содержимое текущего пакета. Сессия сохранена."), true);
            return;
        }

        if (_sessionResetting || !_pasteIntentTransition.IsCompleted || _clipboardPublicationGate.CurrentCount == 0 || _ownedClipboardReceipt != receiptAtIntent) return;
        var pathsAtIntent = _prepared?.GetImagePathsInOrder().ToArray() ?? [];
        // Which captures the package holds is decided here, by id: the strip may be reordered or
        // trimmed before the completion finishes, and then indices would point at other captures.
        var idsAtIntent = _prepared?.Manifest.Images.Select(image => image.CaptureId).ToArray() ?? [];
        // Snapshot in the keyboard hook, but release the hook before any clipboard I/O.
        _pasteIntentTransition = Dispatcher.InvokeAsync(() =>
            CompletePasteIntentAsync(e, receiptAtIntent.Value, promptAtIntent, pathsAtIntent, idsAtIntent)).Task.Unwrap();
    }

    private async Task CompletePasteIntentAsync(PasteIntentObserved e, ClipboardWriteReceipt receiptAtIntent, string promptAtIntent, string[] pathsAtIntent, Guid[] idsAtIntent)
    {
        await _clipboardPublicationGate.WaitAsync();
        try
        {
            var completion = e.IsIntercepted
                ? await _codexPasteCompletion.CompleteSequentialAsync(e, receiptAtIntent, pathsAtIntent, promptAtIntent, CancellationToken.None)
                : await _codexPasteCompletion.CompleteAsync(
                e,
                receiptAtIntent,
                promptAtIntent,
                CancellationToken.None);

            StartupTrace.Write(_options, $"PasteIntent completion: intercepted={e.IsIntercepted}, images={pathsAtIntent.Length}, status={completion.Status}, message={completion.Message}");
            // A newer capture may have replaced the package while completion was waiting.
            // Never rotate that newer session in response to this older paste intent.
            if (_ownedClipboardReceipt != receiptAtIntent) return;

            if (completion.CurrentClipboardReceipt is { } textReceipt)
                _ownedClipboardReceipt = textReceipt;

            if (completion.Status == CodexPasteCompletionStatus.CompletedUnverified)
            {
                // Keep the package on the clipboard until the strip is republished: the pasted
                // captures stay in place and only change their state to sent.
                await RepublishPackageForReuseAsync(pathsAtIntent, promptAtIntent);
                await MarkCapturesSentAsync(idsAtIntent);
                return;
            }

            if (!e.IsIntercepted && completion.Status == CodexPasteCompletionStatus.NotApplicable)
            {
                if (await _clipboard.IsCurrentAsync(receiptAtIntent, CancellationToken.None))
                    await MarkCapturesSentAsync(idsAtIntent);
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

    private async Task RepublishPackageForReuseAsync(string[] pathsAtIntent, string promptAtIntent)
    {
        if (_ownedClipboardReceipt is not { } current || _prepared is null)
        {
            SetStatus(UiLanguage.Text("Пакет вытеснен другим приложением. Сессия сохранена."), true);
            return;
        }
        try
        {
            var republished = await _clipboard.SetPackageGuardedAsync(pathsAtIntent, promptAtIntent, current.SequenceNumber, CancellationToken.None);
            _ownedClipboardReceipt = republished;
            _ownedClipboardPromptText = promptAtIntent;
            StartupTrace.Write(_options, $"PasteIntent republished package: seq={republished.SequenceNumber}, images={pathsAtIntent.Length}");
            var template = UiLanguage.Text("Вставлено: {0} изображений · {1} заметок. Снимки помечены как отправленные");
            ShowToast(string.Format(template, _prepared.Manifest.CaptureCount, _prepared.Manifest.NoteCount));
            StartReceiverEchoWatch(pathsAtIntent, promptAtIntent);
        }
        catch (ClipboardChangedException)
        {
            // Someone else copied in the meantime; leave their clipboard untouched and
            // let the next capture's EnsureCurrentCaptureSessionAsync detect the mismatch.
            CancelReceiverEchoWatch();
            _ownedClipboardReceipt = null;
            _ownedClipboardPromptText = null;
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

    private void StartReceiverEchoWatch(string[] paths, string prompt)
    {
        CancelReceiverEchoWatch();
        // A package without text cannot come back as a text echo from the receiver.
        if (prompt.Length == 0) return;
        var cts = new CancellationTokenSource();
        _receiverEchoWatchCts = cts;
        _ = WatchForReceiverEchoAsync(paths, prompt, cts);
    }

    private async Task WatchForReceiverEchoAsync(string[] paths, string prompt, CancellationTokenSource cts)
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

                if (!ClipboardEchoDetector.IsReceiverEcho(snapshot, prompt))
                {
                    StartupTrace.Write(_options, "PasteIntent package displaced by foreign clipboard write");
                    return;
                }

                await _clipboardPublicationGate.WaitAsync(token);
                try
                {
                    if (token.IsCancellationRequested) return;
                    var republished = await _clipboard.SetPackageGuardedAsync(paths, prompt, snapshot.SequenceNumber, token);
                    StartupTrace.Write(_options, $"PasteIntent re-armed after receiver echo: from seq {current.SequenceNumber} to {republished.SequenceNumber}");
                    _ownedClipboardReceipt = republished;
                    _ownedClipboardPromptText = prompt;
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
        if (_busy) return;
        _busy = true;
        try
        {
            var addNext = true;
            while (addNext)
            {
                HideForCapture();
                var result = await OverlayEditorWindow.CaptureNewAsync(_workspace, PendingCaptures.Count);
                if (result.Capture is null) { addNext = false; continue; }
                Captures.Add(result.Capture);
                Renumber();
                InvalidatePrepared();
                var copied = await SaveAndCopyCommittedPackageAsync();
                CaptureFeedbackSound.Capture(_settings.PlaySounds);
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

    private async void OnRemoveCaptureClick(object sender, RoutedEventArgs e)
    {
        await _pasteIntentTransition;
        if (sender is not Button { Tag: CaptureItem capture }) return;
        var index = Captures.IndexOf(capture);
        Captures.Remove(capture);
        _removed.Push((capture.DeepClone(), index));
        Renumber();
        InvalidatePrepared();
        if (await SaveAsync()) ShowToast(UiLanguage.Text("Снимок удалён"), UiLanguage.Text("Отменить"), () => _ = RestoreRemoved());
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

    private void PositionAtEdge()
    {
        var work = SystemParameters.WorkArea;
        Left = work.Right - Width - 10;
        Top = Math.Max(work.Top + 24, work.Top + (work.Height - Math.Max(ActualHeight, 160)) / 2);
    }

    private async Task<bool> PrepareAsync()
    {
        await _pasteIntentTransition;
        if (Captures.Count == 0) { SetStatus(UiLanguage.Text("Сначала сделайте снимок."), true); return false; }
        try
        {
            SetStatus(UiLanguage.Text("Готовим PNG и текст…"));
            _prepared = await _workspace.PrepareAsync(Captures, string.Empty, SelectedProfile?.Id);
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
                _ownedClipboardPromptText = null;
                SetStatus(string.Empty);
                return true;
            }
            _prepared = await _workspace.PrepareAsync(Captures, pending, string.Empty, SelectedProfile?.Id);
            var current = await _clipboard.CaptureAsync(CancellationToken.None);
            _ownedClipboardReceipt = await _clipboard.SetPackageGuardedAsync(_prepared.GetImagePathsInOrder(), _prepared.Manifest.PromptText, current.SequenceNumber, CancellationToken.None);
            _ownedClipboardPromptText = _prepared.Manifest.PromptText;
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
        var imported = 0;
        var failures = new List<string>();
        foreach (var path in dialog.FileNames)
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
        else if (saved) ShowToast(string.Format(UiLanguage.Text("Добавлено снимков: {0}"), imported));
    }

    private async Task ImportClipboardAsync()
    {
        await _pasteIntentTransition;
        if (!Clipboard.ContainsImage() || Clipboard.GetImage() is not { } image) { SetStatus(UiLanguage.Text("В буфере нет изображения."), true); return; }
        image.Freeze();
        Captures.Add(await _workspace.AddImageAsync(image));
        Renumber(); InvalidatePrepared();
        var saved = await SaveAsync();
        await RefreshOwnedClipboardAsync();
        if (saved) ShowToast(UiLanguage.Text("Изображение добавлено."));
    }

    private async Task CopyPackageAsync()
    {
        await _pasteIntentTransition;
        CancelReceiverEchoWatch();
        await _clipboardPublicationGate.WaitAsync();
        try
        {
        if (_prepared is null && !await PrepareAsync()) return;
        if (_prepared is null) return;
        var current = await _clipboard.CaptureAsync(CancellationToken.None);
        _ownedClipboardReceipt = await _clipboard.SetPackageGuardedAsync(_prepared.GetImagePathsInOrder(), _prepared.Manifest.PromptText, current.SequenceNumber, CancellationToken.None);
        _ownedClipboardPromptText = _prepared.Manifest.PromptText;
            NotifyCopied();
        SetStatus(UiLanguage.Text("PNG и текст скопированы. Если получатель выберет один формат, используйте кнопку вставки."));
        }
        finally { _clipboardPublicationGate.Release(); }
    }

    private async Task SavePackageAsAsync()
    {
        await _pasteIntentTransition;
        if (_prepared is null && !await PrepareAsync()) return;
        if (_prepared is null) return;
        using var dialog = new WinForms.FolderBrowserDialog { Description = "Папка для пакета SnapBrief", UseDescriptionForTitle = true };
        WinForms.DialogResult picked;
        using (SuspendTopmost()) picked = dialog.ShowDialog();
        if (picked != WinForms.DialogResult.OK) return;
        var destination = Path.Combine(dialog.SelectedPath, $"SnapBrief-{DateTime.Now:yyyyMMdd-HHmmss}");
        Directory.CreateDirectory(destination);
        foreach (var path in Directory.EnumerateFiles(_prepared.RootDirectory)) File.Copy(path, Path.Combine(destination, Path.GetFileName(path)));
        ShowToast(UiLanguage.Text("Пакет сохранён."));
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
                        if (_hotkeys is null) return "Регистрация клавиш недоступна. Перезапустите SnapBrief.";
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
                            PlaySounds = candidate.PlaySounds, ClearStackAfterPaste = candidate.ClearStackAfterPaste,
                            SaveFormat = candidate.SaveFormat, JpegQuality = candidate.JpegQuality,
                            SaveDirectory = candidate.SaveDirectory, Language = candidate.Language
                        });
                        if (!merged) return UiLanguage.Text("Не удалось сохранить настройки");
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
                            return "Эта клавиша уже занята. Освободите её в другом приложении или выберите другую.";
                        return ex is Win32Exception ? "Не удалось назначить сочетание. Возможно, оно уже занято — нажмите другое." : $"Не удалось сохранить настройки: {ex.Message}";
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

    // Clearing the strip archives the current session on disk and opens an empty one; the panel
    // itself stays visible, and there is no undo in this version (the files remain in the session).
    private async Task<bool> ClearStackAsync()
    {
        if (_sessionResetting) return false;
        _sessionResetting = true;
        CancelReceiverEchoWatch();
        _saveTimer.Stop();
        await _workspaceMutationGate.WaitAsync();
        try
        {
            await _workspace.StartNewSessionAsync(Captures, _legacyGlobalNote, SelectedProfile?.Id);
            _loading = true;
            Captures.Clear();
            _legacyGlobalNote = string.Empty;
            _removed.Clear();
            _prepared = null;
            _ownedClipboardReceipt = null;
            _ownedClipboardPromptText = null;
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

    private async Task ClearStackFromUserAsync()
    {
        await _pasteIntentTransition;
        await ClearStackAsync();
    }

    private async void OnClearStackClick(object sender, RoutedEventArgs e) => await ClearStackFromUserAsync();

    // A completed paste keeps the captures in the strip and only marks the ones that were in the
    // package; the clipboard is then rebuilt from what is left, so the next Ctrl+V cannot repeat them.
    private async Task MarkCapturesSentAsync(Guid[] idsAtIntent)
    {
        if (_settings.ClearStackAfterPaste) { await ClearStackAsync(); return; }
        var ids = idsAtIntent.ToHashSet();
        var marked = false;
        foreach (var capture in Captures)
            if (ids.Contains(capture.Id) && !capture.IsSent) { capture.IsSent = true; marked = true; }
        if (!marked) return;
        Renumber();
        InvalidatePrepared();
        CancelReceiverEchoWatch();
        await SaveCoreAsync();
        await RefreshOwnedClipboardCoreAsync();
    }

    private async Task RefreshOwnedClipboardAsync()
    {
        await _pasteIntentTransition;
        CancelReceiverEchoWatch();
        await _clipboardPublicationGate.WaitAsync();
        try { await RefreshOwnedClipboardCoreAsync(); }
        finally { _clipboardPublicationGate.Release(); }
    }

    private async Task RefreshOwnedClipboardCoreAsync()
    {
        if (_ownedClipboardReceipt is not { } receipt) return;
        try
        {
            if (!await _clipboard.IsCurrentAsync(receipt, CancellationToken.None))
            {
                _ownedClipboardReceipt = null;
                _ownedClipboardPromptText = null;
                return;
            }
            var pending = PendingCaptures;
            if (pending.Count == 0)
            {
                _ownedClipboardReceipt = await _clipboard.SetTextGuardedAsync(string.Empty, receipt.SequenceNumber, CancellationToken.None);
                _ownedClipboardPromptText = null;
                _prepared = null;
                return;
            }
            _prepared = await _workspace.PrepareAsync(Captures, pending, string.Empty, SelectedProfile?.Id);
            _ownedClipboardReceipt = await _clipboard.SetPackageGuardedAsync(_prepared.GetImagePathsInOrder(), _prepared.Manifest.PromptText, receipt.SequenceNumber, CancellationToken.None);
            _ownedClipboardPromptText = _prepared.Manifest.PromptText;
            NotifyCopied();
        }
        catch (ClipboardChangedException)
        {
            _ownedClipboardReceipt = null;
            _ownedClipboardPromptText = null;
        }
        catch (Exception ex)
        {
            // The receipt no longer describes anything we can trust, and this method cannot tell
            // whether the session itself was written: the message promises only what is known.
            _ownedClipboardReceipt = null;
            _ownedClipboardPromptText = null;
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
        if (!await SaveAsync()) { _exiting = false; ShowStackWithoutActivation(); return; }
        if (_exiting) { _allowClose = true; Close(); }
        else Hide();
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
