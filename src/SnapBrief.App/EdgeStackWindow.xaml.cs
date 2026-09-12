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
    private readonly DispatcherTimer _statusTimer;
    private readonly string _settingsPath;
    private readonly WinForms.NotifyIcon _trayIcon;
    private readonly IPasteIntentObserver _pasteIntentObserver;
    private readonly SemaphoreSlim _workspaceMutationGate = new(1, 1);
    private readonly SemaphoreSlim _clipboardPublicationGate = new(1, 1);
    private HotkeySettings _settings;
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
    private bool _pasteObservedForCurrentPackage;
    private CancellationTokenSource? _receiverEchoWatchCts;
    private Task _pasteIntentTransition = Task.CompletedTask;
    // Some paste receivers (e.g. a terminal hosting Claude Code) write their own
    // rendering of the pasted text back to the clipboard right after the paste. This
    // window bounds how long we keep watching for and re-arming through such an echo.
    private static readonly TimeSpan ReceiverEchoWatchWindow = TimeSpan.FromSeconds(6);
    private static readonly TimeSpan ReceiverEchoPollInterval = TimeSpan.FromMilliseconds(200);
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
        _statusTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(4) };
        _statusTimer.Tick += OnStatusTimerTick;
        _pasteIntentObserver = new WindowsPasteIntentObserver(intent =>
        {
            var receiptSeq = _ownedClipboardReceipt?.SequenceNumber;
            if (_sessionResetting || !_pasteIntentTransition.IsCompleted || _clipboardPublicationGate.CurrentCount == 0 ||
                _ownedClipboardReceipt is not { } receipt ||
                intent.ClipboardSequenceNumber != receipt.SequenceNumber ||
                string.IsNullOrEmpty(_ownedClipboardPromptText) || _prepared is null)
            {
                StartupTrace.Write(_options, $"PasteIntent predicate: state not ready (resetting={_sessionResetting}, transitionDone={_pasteIntentTransition.IsCompleted}, gate={_clipboardPublicationGate.CurrentCount}, ownedSeq={receiptSeq}, intentSeq={intent.ClipboardSequenceNumber}, prompt={!string.IsNullOrEmpty(_ownedClipboardPromptText)}, prepared={_prepared is not null}, gesture={intent.Gesture})");
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
                SetStatus($"Не удалось изменить автозапуск: {ex.Message}", true);
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
        catch (Exception ex) { SetStatus($"Не удалось восстановить сессию: {ex.Message}", true); StartupTrace.Write(_options, ex.ToString()); }
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
        catch (Exception ex) { SetStatus($"Захват: {ex.Message}", true); }
        try
        {
            _pasteIntentObserver.PasteIntentObserved += OnPasteIntentObserved;
            _pasteIntentObserver.Start();
        }
        catch (Exception ex) { SetStatus($"Отслеживание вставки недоступно: {ex.Message}", true); }
    }

    private bool RegisterHotkeys()
    {
        var conflicts = new List<string>();
        if (_settings.CaptureEnabled) try { _hotkeys?.Register("capture", _settings.CaptureGesture); } catch { conflicts.Add("захват"); }
        if (_settings.FullscreenSaveEnabled) try { _hotkeys?.Register("fullscreen-save", _settings.FullscreenSaveGesture); } catch { conflicts.Add("сохранение экрана"); }
        if (conflicts.Count > 0) SetStatus($"Сочетание занято: {string.Join(", ", conflicts)}", true);
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
            SetStatus("Не удалось подтвердить содержимое текущего пакета. Сессия сохранена.", true);
            return;
        }

        if (_sessionResetting || !_pasteIntentTransition.IsCompleted || _clipboardPublicationGate.CurrentCount == 0 || _ownedClipboardReceipt != receiptAtIntent) return;
        var pathsAtIntent = _prepared?.GetImagePathsInOrder().ToArray() ?? [];
        // Snapshot in the keyboard hook, but release the hook before any clipboard I/O.
        _pasteIntentTransition = Dispatcher.InvokeAsync(() =>
            CompletePasteIntentAsync(e, receiptAtIntent.Value, promptAtIntent, pathsAtIntent)).Task.Unwrap();
    }

    private async Task CompletePasteIntentAsync(PasteIntentObserved e, ClipboardWriteReceipt receiptAtIntent, string promptAtIntent, string[] pathsAtIntent)
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
                // Keep the package on the clipboard so the same stack can be pasted into
                // several applications in a row; session rotation moves to the next capture.
                await RepublishPackageForReuseAsync(pathsAtIntent, promptAtIntent);
                return;
            }

            if (!e.IsIntercepted && completion.Status == CodexPasteCompletionStatus.NotApplicable)
            {
                if (await _clipboard.IsCurrentAsync(receiptAtIntent, CancellationToken.None))
                    await StartNewSessionAsync();
                return;
            }

            SetStatus($"{UiLanguage.Text("Снимки сохранены, но вставка не завершена")}: {completion.Message}", true);
        }
        catch (Exception ex)
        {
            StartupTrace.Write(_options, $"PasteIntent completion failed: {ex}");
            SetStatus($"Вставка замечена, но новая сессия не создана: {ex.Message}", true);
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
            _pasteObservedForCurrentPackage = true;
            StartupTrace.Write(_options, $"PasteIntent republished package: seq={republished.SequenceNumber}, images={pathsAtIntent.Length}");
            var template = UiLanguage.Text("Вставлено: {0} изображений · {1} заметок. Пакет остаётся в буфере, следующий снимок начнёт новую стопку");
            SetStatus(string.Format(template, _prepared.Manifest.CaptureCount, _prepared.Manifest.NoteCount));
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
            if (!await EnsureCurrentCaptureSessionAsync()) return;
            var addNext = true;
            while (addNext)
            {
                HideForCapture();
                var result = await OverlayEditorWindow.CaptureNewAsync(_workspace, Captures.Count);
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
        catch (Exception ex) { SetStatus($"Захват не завершён: {ex.Message}", true); }
        finally
        {
            _busy = false;
            ShowStackWithoutActivation();
        }
    }

    private async Task<bool> EnsureCurrentCaptureSessionAsync()
    {
        if (_pasteObservedForCurrentPackage)
        {
            // A reusable package sat in the clipboard after a completed paste; rotation
            // was deferred to this next capture. The old session is preserved on disk.
            _pasteObservedForCurrentPackage = false;
            _ownedClipboardReceipt = null;
            _ownedClipboardPromptText = null;
            return await StartNewSessionAsync();
        }

        if (Captures.Count == 0) return true;

        try
        {
            if (_ownedClipboardReceipt is { } receipt &&
                await _clipboard.IsCurrentAsync(receipt, CancellationToken.None))
                return true;

            // The previous batch was pasted, replaced, or restored after restart.
            // Preserve it on disk and start the next capture in a fresh session;
            // leave the user's current clipboard untouched until that capture commits.
            _ownedClipboardReceipt = null;
            _ownedClipboardPromptText = null;
            return await StartNewSessionAsync();
        }
        catch (Exception ex)
        {
            SetStatus($"Не удалось проверить буфер перед новым снимком: {ex.Message}", true);
            return false;
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
        if (await SaveAsync()) SetStatus("Снимок удалён");
        await RefreshOwnedClipboardAsync();
        UndoRemoveButton.Visibility = Visibility.Visible;
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
        if (Captures.Count == 0) { SetStatus("Сначала сделайте снимок.", true); return false; }
        try
        {
            SetStatus("Готовим PNG и текст…");
            _prepared = await _workspace.PrepareAsync(Captures, string.Empty, SelectedProfile?.Id);
            PasteButton.IsEnabled = true;
            SetStatus($"Готово: {_prepared.Manifest.CaptureCount} изображений · {_prepared.Manifest.NoteCount} заметок");
            return true;
        }
        catch (Exception ex) { SetStatus($"Не удалось подготовить: {ex.Message}", true); return false; }
    }

    private async Task<bool> SaveAndCopyCommittedPackageAsync()
    {
        await _pasteIntentTransition;
        CancelReceiverEchoWatch();
        await _clipboardPublicationGate.WaitAsync();
        try
        {
            _prepared = await _workspace.PrepareAsync(Captures, string.Empty, SelectedProfile?.Id);
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
            SetStatus($"Снимок сохранён, но буфер не обновлён: {ex.Message}. Повторите копирование через меню.", true);
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
        catch (Exception ex) { SetStatus($"Вставка остановлена: {ex.Message}", true); }
        finally
        {
            _busy = false;
            if (hideStack) ShowStackWithoutActivation();
        }
    }

    private void OnMoreClick(object sender, RoutedEventArgs e)
    {
        var menu = new ContextMenu();
        menu.Items.Add(MenuItem("Импортировать файл…", async () => await ImportFileAsync()));
        menu.Items.Add(MenuItem("Вставить изображение из буфера", async () => await ImportClipboardAsync()));
        if (_removed.Count > 0) menu.Items.Add(MenuItem("Вернуть удалённый снимок", RestoreRemoved));
        menu.Items.Add(MenuItem("Новая сессия", StartNewSessionFromUserAsync));
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
            catch (Exception ex) { SetStatus($"Не удалось выполнить действие: {ex.Message}", true); }
        };
        return item;
    }

    private async Task ImportFileAsync()
    {
        await _pasteIntentTransition;
        var filter = $"{UiLanguage.Text("Изображения")}|*.png;*.jpg;*.jpeg;*.webp;*.bmp;*.gif;*.tif;*.tiff|{UiLanguage.Text("Все файлы")}|*.*";
        var dialog = new OpenFileDialog { Filter = filter, Multiselect = true };
        if (dialog.ShowDialog(this) != true) return;
        var imported = 0;
        var failures = new List<string>();
        foreach (var path in dialog.FileNames)
        {
            try { Captures.Add(await _workspace.AddImageAsync(SessionWorkspace.LoadBitmap(path))); imported++; }
            catch (Exception ex) { failures.Add($"{Path.GetFileName(path)}: {ex.Message}"); }
        }
        Renumber(); InvalidatePrepared();
        var saved = await SaveAsync();
        // A failed import must survive the next status update, a successful one has to stay readable for a few seconds.
        if (failures.Count > 0) SetStatus($"{UiLanguage.Text("Не удалось добавить")}: {string.Join("; ", failures)}", true);
        else if (saved) ShowTransientStatus(string.Format(UiLanguage.Text("Добавлено снимков: {0}"), imported));
        if (saved) await RefreshOwnedClipboardAsync();
    }

    private async Task ImportClipboardAsync()
    {
        await _pasteIntentTransition;
        if (!Clipboard.ContainsImage() || Clipboard.GetImage() is not { } image) { SetStatus(UiLanguage.Text("В буфере нет изображения."), true); return; }
        image.Freeze();
        Captures.Add(await _workspace.AddImageAsync(image));
        Renumber(); InvalidatePrepared();
        if (!await SaveAsync()) return;
        ShowTransientStatus(UiLanguage.Text("Изображение добавлено."));
        await RefreshOwnedClipboardAsync();
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
        SetStatus("PNG и текст скопированы. Если получатель выберет один формат, используйте кнопку вставки.");
        }
        finally { _clipboardPublicationGate.Release(); }
    }

    private async Task SavePackageAsAsync()
    {
        await _pasteIntentTransition;
        if (_prepared is null && !await PrepareAsync()) return;
        if (_prepared is null) return;
        using var dialog = new WinForms.FolderBrowserDialog { Description = "Папка для пакета SnapBrief", UseDescriptionForTitle = true };
        if (dialog.ShowDialog() != WinForms.DialogResult.OK) return;
        var destination = Path.Combine(dialog.SelectedPath, $"SnapBrief-{DateTime.Now:yyyyMMdd-HHmmss}");
        Directory.CreateDirectory(destination);
        foreach (var path in Directory.EnumerateFiles(_prepared.RootDirectory)) File.Copy(path, Path.Combine(destination, Path.GetFileName(path)));
        SetStatus("Пакет сохранён.");
    }

    private void OpenSettings()
    {
        _hotkeys?.Unregister("capture");
        _hotkeys?.Unregister("fullscreen-save");
        try
        {
            var dialog = new HotkeySettingsWindow(_settings, showPasteSettings: false)
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
                        candidate.Save(_settingsPath);
                        _settings = candidate;
                        UiLanguage.Current = candidate.Language;
                        UiLanguage.Apply(this, candidate.Language);
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
            if (dialog.ShowDialog() == true) SetStatus(string.Empty);
        }
        finally
        {
            _hotkeys?.Unregister("capture");
        _hotkeys?.Unregister("fullscreen-save");
            _ = RegisterHotkeys();
        }
    }

    private void Renumber()
    {
        for (var i = 0; i < Captures.Count; i++) Captures[i].DisplayLabel = CaptureLabels.ForIndex(i);
        CaptureList?.Items.Refresh();
        CountText.Text = Captures.Count.ToString();
        PasteButton.IsEnabled = Captures.Count > 0;
    }

    private void InvalidatePrepared() { _prepared = null; }
    private void QueueSave() { _saveTimer.Stop(); _saveTimer.Start(); }
    private async void OnSaveTimerTick(object? sender, EventArgs e) { _saveTimer.Stop(); if (await SaveAsync()) await RefreshOwnedClipboardAsync(); }

    private async Task<bool> SaveAsync()
    {
        await _pasteIntentTransition;
        await _workspaceMutationGate.WaitAsync();
        try { await _workspace.SaveAsync(Captures, _legacyGlobalNote, SelectedProfile?.Id); return true; }
        catch (Exception ex) { SetStatus($"Не удалось сохранить: {ex.Message}", true); return false; }
        finally { _workspaceMutationGate.Release(); }
    }

    private async Task<bool> StartNewSessionAsync()
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
            HideStack();
            _legacyGlobalNote = string.Empty;
            _removed.Clear();
            _prepared = null;
            _ownedClipboardReceipt = null;
            _ownedClipboardPromptText = null;
            Renumber();
            SetStatus(string.Empty);
            return true;
        }
        catch (Exception ex)
        {
            SetStatus($"Не удалось начать новую сессию: {ex.Message}", true);
            return false;
        }
        finally
        {
            _workspaceMutationGate.Release();
            _loading = false;
            _sessionResetting = false;
        }
    }

    private async Task StartNewSessionFromUserAsync()
    {
        await _pasteIntentTransition;
        await StartNewSessionAsync();
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
            if (Captures.Count == 0)
            {
                _ownedClipboardReceipt = await _clipboard.SetTextGuardedAsync(string.Empty, receipt.SequenceNumber, CancellationToken.None);
                _ownedClipboardPromptText = null;
                _prepared = null;
                return;
            }
            _prepared = await _workspace.PrepareAsync(Captures, string.Empty, SelectedProfile?.Id);
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
            SetStatus($"Сессия сохранена, но буфер не обновлён: {ex.Message}", true);
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
        _statusTimer.Stop();
        if (error) StartupTrace.Write(_options, text);
        StatusText.Text = text;
        StatusText.Visibility = error ? Visibility.Visible : Visibility.Collapsed;
        StatusText.Foreground = new SolidColorBrush(Color.FromRgb(255, 155, 149));
    }

    // Plain SetStatus keeps non-error text hidden; this one shows a confirmation for a few seconds.
    private void ShowTransientStatus(string text)
    {
        if (!Dispatcher.CheckAccess()) { Dispatcher.Invoke(() => ShowTransientStatus(text)); return; }
        _statusTimer.Stop();
        StatusText.Text = text;
        StatusText.Foreground = new SolidColorBrush(Color.FromRgb(174, 184, 199));
        StatusText.Visibility = Visibility.Visible;
        _statusTimer.Start();
    }

    private void OnStatusTimerTick(object? sender, EventArgs e)
    {
        _statusTimer.Stop();
        StatusText.Text = string.Empty;
        StatusText.Visibility = Visibility.Collapsed;
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
        Renumber(); InvalidatePrepared(); if (await SaveAsync()) SetStatus("Порядок снимков изменён."); await RefreshOwnedClipboardAsync();
    }

    private async Task RestoreRemoved()
    {
        await _pasteIntentTransition;
        if (_removed.Count == 0) return;
        var removed = _removed.Pop();
        Captures.Insert(Math.Clamp(removed.Index, 0, Captures.Count), removed.Capture);
        Renumber(); InvalidatePrepared(); if (await SaveAsync()) SetStatus("Снимок восстановлен."); await RefreshOwnedClipboardAsync();
        UndoRemoveButton.Visibility = _removed.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    private async void OnRestoreRemovedClick(object sender, RoutedEventArgs e) => await RestoreRemoved();

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
        if (!await SaveAsync()) { _exiting = false; ShowStackWithoutActivation(); return; }
        if (_exiting) { _allowClose = true; Close(); }
        else Hide();
    }

    // Raise a normal window once without activation; never pin it above other applications.
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWindowPos(IntPtr window, IntPtr after, int x, int y, int width, int height, uint flags);

    [DllImport("dwmapi.dll")]
    private static extern int DwmFlush();

    [DllImport("user32.dll")]
    private static extern bool SetWindowDisplayAffinity(IntPtr hwnd, uint affinity);
}
