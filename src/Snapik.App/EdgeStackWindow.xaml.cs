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
using Snapik.Core.Exporting;
using Snapik.Windows;
using WinForms = System.Windows.Forms;

namespace Snapik.App;

public partial class EdgeStackWindow : Window
{
    private readonly LaunchOptions _options;
    private readonly SessionWorkspace _workspace;
    private readonly WindowsClipboardService _clipboard = new();
    private readonly IPasteCoordinator _pasteCoordinator;
    private readonly ICodexDesktopPasteCompletionService _codexPasteCompletion;
    private readonly DispatcherTimer _saveTimer;
    private readonly DispatcherTimer _toastTimer;
    // The bar of the strip is an overlay: it shows itself while the list moves and goes out a second
    // after it stops. This is that second, and the bar it fades is found once, in the template.
    private readonly DispatcherTimer _scrollBarTimer;
    private System.Windows.Controls.Primitives.ScrollBar? _stripScrollBar;
    private ScrollViewer? _stripScrollViewer;
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
    private static readonly TimeSpan ScrollBarLifetime = TimeSpan.FromSeconds(1);
    private static readonly TimeSpan ToastFade = TimeSpan.FromMilliseconds(150);
    private Action? _toastAction;
    private int _toastGeneration;
    private Point _dragStart;
    private double _resizeRightEdge;
    private double _resizeTop;
    private Rect _resizeWorkArea;
    // The whole geometry of the strip as it was when the drag began, and the pointer with it: every
    // size under the drag is counted from these, never from the size of the moment.
    private double _resizeStartWidth;
    private double _resizeStartListHeight;
    private double _resizeStartChrome;
    private double _resizeStartMinHeight;
    private Point _resizeStartPointer;
    // The strip as it was before it collapsed, so the capsule gives back the same window.
    private bool _softLimitWarned;
    private bool _capsuleMode;
    private double _expandedWidth;
    private double _expandedLeft;
    private double _expandedTop;
    private double _expandedMinHeight;
    private CaptureItem? _draggedCapture;
    private readonly Stack<(CaptureItem Capture, int Index)> _removed = [];
    private TargetProfile? _selectedProfile;

    public EdgeStackWindow(LaunchOptions options)
    {
        _options = options;
        var dataRoot = options.DataDirectory;
        if (options.Demo && string.IsNullOrWhiteSpace(dataRoot)) dataRoot = Path.Combine(Path.GetTempPath(), "Snapik", $"demo-{Environment.ProcessId}");
        _workspace = new SessionWorkspace(dataRoot);
        _settingsPath = Path.Combine(options.DataDirectory ?? AppDataPaths.LocalRoot, "settings.json");
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
        _scrollBarTimer = new DispatcherTimer { Interval = ScrollBarLifetime };
        _scrollBarTimer.Tick += OnScrollBarTimerTick;
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
            var intercept = !foreground.Matches(target, Snapik.Windows.TargetProfiles.CodexDesktop);
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
            Text = "Snapik",
            Icon = System.Drawing.Icon.ExtractAssociatedIcon(Environment.ProcessPath!) ?? System.Drawing.SystemIcons.Application,
            Visible = true,
            ContextMenuStrip = new WinForms.ContextMenuStrip()
        };
        _trayIcon.ContextMenuStrip.Items.Add("Показать ленту", null, (_, _) => Dispatcher.Invoke(ShowStackWithoutActivation));
        // BeginInvoke, not Invoke, for both of the items that open a dialog: a modal loop started
        // from inside the click handler of the menu runs while that menu is still on screen, and the
        // dialog then may never get the activation its keyboard needs. Posting it lets the menu close
        // first. Without activation the settings window is worse off than the slides: the hotkey
        // field would record nothing at all.
        _trayIcon.ContextMenuStrip.Items.Add("Настройки", null, (_, _) => Dispatcher.BeginInvoke(() => { ShowStackWithoutActivation(); OpenSettings(); }));
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
    public IReadOnlyList<TargetProfile> TargetProfiles { get; } = Snapik.Windows.TargetProfiles.All;
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
            PlaceStripInitially();
            // Every run ends with the strip on the screen, empty and compact and without taking the
            // focus: the strip is a window on the taskbar now, and the line under the icon has to be
            // there from the first second rather than from the first capture. Here and not earlier:
            // the wizard is modal and has already closed by this point (with Topmost the strip would
            // otherwise stand over it), and the session is restored in between, so a strip shown
            // before that would flash empty and be placed twice.
            ShowStackWithoutActivation();
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
        // Every way the list moves ends in this event: the wheel, the grip, the track and the keys.
        CaptureList.AddHandler(ScrollViewer.ScrollChangedEvent, new ScrollChangedEventHandler(OnStripScrolled));
    }

    // The bar of the strip lives while the list moves: it comes up on the first pixel of scrolling
    // and goes out a second after the last one. The pointer over the field of the bar holds it
    // there, and the width of six is a trigger in the template — a setter and an animation on one
    // property would fight, and the animation would win for good.
    private void OnStripScrolled(object sender, ScrollChangedEventArgs e)
    {
        if (e.VerticalChange == 0) return;
        FadeStripScrollBar(1, 90);
        _scrollBarTimer.Stop();
        _scrollBarTimer.Start();
    }

    private void OnScrollBarTimerTick(object? sender, EventArgs e)
    {
        _scrollBarTimer.Stop();
        FadeStripScrollBar(0, 160);
    }

    private void OnBarFieldEnter(object sender, MouseEventArgs e)
    {
        _scrollBarTimer.Stop();
        FadeStripScrollBar(1, 90);
    }

    private void OnBarFieldLeave(object sender, MouseEventArgs e)
    {
        _scrollBarTimer.Stop();
        _scrollBarTimer.Start();
    }

    private void FadeStripScrollBar(double to, int milliseconds)
    {
        if (StripScrollBar() is not { } bar) return;
        bar.BeginAnimation(OpacityProperty, new DoubleAnimation(to, TimeSpan.FromMilliseconds(milliseconds)));
    }

    // The viewer is the whole template of the list — the ListBox is retemplated into a bare
    // ScrollViewer — so it is its only visual child, and it outlives every capture the strip holds:
    // looked up once and kept, like the bar inside it.
    private ScrollViewer? StripScrollViewer()
    {
        if (_stripScrollViewer is not null) return _stripScrollViewer;
        if (CaptureList is null || VisualTreeHelper.GetChildrenCount(CaptureList) == 0) return null;
        return _stripScrollViewer = VisualTreeHelper.GetChild(CaptureList, 0) as ScrollViewer;
    }

    // The bar is part of the template of the viewer, which is part of the template of the list, so
    // it is looked up once and kept: the two templates outlive every capture the strip holds.
    private System.Windows.Controls.Primitives.ScrollBar? StripScrollBar()
    {
        if (_stripScrollBar is not null) return _stripScrollBar;
        if (StripScrollViewer() is not { } viewer) return null;
        _stripScrollBar = viewer.Template.FindName("PART_VerticalScrollBar", viewer) as System.Windows.Controls.Primitives.ScrollBar;
        return _stripScrollBar;
    }

    // The bottom of the strip, not the last card: the container of a card is 30 px tall — the
    // overhang of 48 belongs to the panel — so ScrollIntoView would stop having shown 30 px of the
    // 78 the card is drawn with. Called after the layout pass that added the card, and separately
    // from the deferred call below so the probe of the strip can take the same path in one go.
    private void ScrollStripToEndCore()
    {
        if (CaptureList is null || CaptureList.Visibility != Visibility.Visible) return;
        CaptureList.UpdateLayout();
        StripScrollViewer()?.ScrollToEnd();
    }

    // At Loaded priority: a capture is added and the strip is shown before the list has been given
    // its new height, and a scroll asked for at that moment has nothing to scroll yet.
    private void ScrollStripToEnd() => Dispatcher.InvokeAsync(ScrollStripToEndCore, DispatcherPriority.Loaded);

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
        else if (e.Id == "fullscreen-save") await CaptureFullscreenAsync();
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
                // that are still waiting rebuild the clipboard and cancel that watch. A completion
                // that never wrote to the clipboard needs no republish at all: see NeedsRepublish.
                var needsRepublish = completion.NeedsRepublish(
                    await _clipboard.IsCurrentAsync(receiptAtIntent, CancellationToken.None));
                await RepublishPackageForReuseAsync(publishedAtIntent, needsRepublish);
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

    private async Task RepublishPackageForReuseAsync(PublishedPackage publishedAtIntent, bool needsRepublish = true)
    {
        if (_ownedClipboardReceipt is not { } current)
        {
            SetStatus(UiLanguage.Text("Пакет вытеснен другим приложением. Сессия сохранена."), true);
            return;
        }
        try
        {
            // The package is already on the clipboard and this completion never moved it: the write
            // is skipped, and the toast and the echo watch below happen exactly as after a real
            // republish. Writing it again would take it away from the receiver that is reading it
            // right now, which is the whole reason for the check.
            var republished = needsRepublish
                ? await _clipboard.SetPackageGuardedAsync(publishedAtIntent.Paths, publishedAtIntent.Prompt, current.SequenceNumber, CancellationToken.None)
                : current;
            _ownedClipboardReceipt = republished;
            SetPublished(publishedAtIntent);
            StartupTrace.Write(_options, $"PasteIntent {(needsRepublish ? "republished" : "kept")} package: seq={republished.SequenceNumber}, images={publishedAtIntent.Paths.Length}");
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
                NoteStripGrowth();
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

    // The strip holds twenty-six captures, sent ones included: they take the same disk and the same
    // memory, and the letters of the strip stay inside A..Z. Every way of adding a capture goes
    // through here, and the number of the toast comes from the constant, never from the sentence.
    private bool StripIsFull(int adding = 1)
    {
        if (Captures.Count + adding <= SentCaptureRules.MaxStripCaptures) return false;
        ShowToast(string.Format(UiLanguage.Text("В ленте максимум {0} снимков. Отправьте или удалите лишние"), SentCaptureRules.MaxStripCaptures));
        return true;
    }

    // The soft limit, said once. Twenty-six captures fit the strip, but a chat usually takes about
    // twenty images in one paste, so the strip warns when it goes past that number and says nothing
    // more until it has come back down to it. Every way of adding a capture calls this after adding.
    private void NoteStripGrowth()
    {
        if (Captures.Count <= SentCaptureRules.SoftStripWarning) { _softLimitWarned = false; return; }
        if (_softLimitWarned) return;
        _softLimitWarned = true;
        ShowToast(string.Format(UiLanguage.Text("Чаты обычно принимают до {0} картинок за раз"), SentCaptureRules.SoftStripWarning));
    }

    private async void OnRemoveCaptureClick(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: CaptureItem capture }) return;
        await RemoveCapture(capture);
        e.Handled = true;
    }

    // The removal apart from the button that asks for it: the card has one, and the context menu of
    // the same card gets one too.
    private async Task RemoveCapture(CaptureItem capture)
    {
        await _pasteIntentTransition;
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
        // A capture taken while the strip is collapsed must not unfold it: the capsule stays where it
        // is and only its counter grows. It is already standing where it belongs, so there is
        // nothing to place — the placement of the strip would give the window the width and the
        // height of the strip back.
        if (!_capsuleMode) EnsureStripPlaced();
        // Show() does not bring a minimised window back, and WindowState = Normal would activate it
        // and take the focus away from the application the user is about to paste into.
        // SW_SHOWNOACTIVATE restores the window and leaves the focus where it was.
        if (WindowState == WindowState.Minimized)
            _ = ShowWindow(new WindowInteropHelper(this).EnsureHandle(), SwShowNoActivate);
        Show();
        _ = SetWindowPos(new WindowInteropHelper(this).Handle, IntPtr.Zero, 0, 0, 0, 0, 0x0053);
        UiLanguage.Apply(this);
        AnimateStackIn();
        // Every showing of the strip ends at its last capture: this is the one path all of them go
        // through — a capture, the whole screen, a paste, the tray, the start and the way back from
        // the editor. Renumber and UpdateEmptyState are deliberately left alone: they also run on a
        // removal, a reorder and a capture marked as sent, where the bottom is the wrong place.
        ScrollStripToEnd();
    }

    public void RevealStack() => ShowStackWithoutActivation();

    // The fourth button of the header minimises the strip the way every window is minimised: it
    // keeps its button on the taskbar and the line under the icon, and a click on that button brings
    // it back. Hiding to the tray took the line with it, and the strip was gone from the taskbar
    // while the application was still running.
    private void OnHideClick(object sender, RoutedEventArgs e)
    {
        HideToastNow();
        WindowState = WindowState.Minimized;
    }

    // The strip collapsed into the capsule, and back. It is a mode of this window: the hotkeys, the
    // topmost, the tray icon and the drag of the header all hang on this window and on its handle.
    // The mode lives in memory only and is never written to the settings file: a strip that opens
    // collapsed would look like a strip that failed to open.
    private void OnCollapseToCapsuleClick(object sender, RoutedEventArgs e) => CollapseToCapsule();

    private void OnCapsuleClick(object sender, MouseButtonEventArgs e) => ExpandFromCapsule();

    private void CollapseToCapsule()
    {
        if (_capsuleMode) return;
        _capsuleMode = true;
        _expandedWidth = Width;
        // The height of the list is not remembered on purpose: it follows the content, and the strip
        // may have been given captures while it stood as a capsule.
        // The left edge is remembered with the rest of the rectangle: without it the strip came back
        // to the edge of the monitor whatever corner the user had dragged it to.
        _expandedLeft = Left;
        _expandedTop = Top;
        _expandedMinHeight = MinHeight;
        HideToastNow();
        Shell.Visibility = Visibility.Collapsed;
        WidthGrip.Visibility = Visibility.Collapsed;
        CornerGrip.Visibility = Visibility.Collapsed;
        Capsule.Visibility = Visibility.Visible;
        // Both sides by the content now, and no floor under the height: the minimum of the strip is
        // three times the capsule.
        MinHeight = 0;
        Width = double.NaN;
        SizeToContent = SizeToContent.WidthAndHeight;
        PositionCapsuleAtStrip();
    }

    private void ExpandFromCapsule()
    {
        if (!_capsuleMode) return;
        _capsuleMode = false;
        Capsule.Visibility = Visibility.Collapsed;
        Shell.Visibility = Visibility.Visible;
        WidthGrip.Visibility = Visibility.Visible;
        // The list, the hint and the corner grip belong to the state of the strip, not to the mode:
        // an empty strip unfolds back into an empty strip, without a grip that has nothing to pull.
        // The order below is fixed: the height of the list is settled before the window is placed,
        // or ActualHeight is measured from the list the strip had before the capsule; and
        // SizeToContent goes off before Width is assigned, or WPF runs a pass of its own in between
        // and moves the window. The height is settled by UpdateEmptyState through ApplyListHeight,
        // and by nothing else: captures taken while the strip was a capsule count as well, and the
        // ceiling belongs to the settings, not to the height the list happened to have back then.
        UpdateEmptyState();
        SizeToContent = SizeToContent.Manual;
        MinHeight = _expandedMinHeight;
        Width = _expandedWidth;
        UpdateLayout();
        // The working area is the one of the monitor the capsule stands on, and it is a frame to
        // clamp against, not a place to move to: a strip dragged away from the edge comes back where
        // it was left.
        PlaceWindow(Controls.StripResizeGeometry.RestoreRect(
            new Rect(_expandedLeft, _expandedTop, Width, ActualHeight), StackWorkArea()));
        SizeToContent = SizeToContent.Height;
    }

    // The capsule keeps the corner of the strip it came from: the same right edge, because both
    // windows carry the same 20 px field under their shadow, and a Top that is not touched at all.
    private void PositionCapsuleAtStrip()
    {
        UpdateLayout();
        Left = Controls.StripResizeGeometry.CapsuleLeft(_expandedLeft, _expandedWidth, ActualWidth);
    }

    // The window moved and sized in one call: assignments of Left, Top and Width are three layout
    // passes, and the strip is seen travelling through all of them.
    private void PlaceWindow(Rect target)
    {
        var dpi = VisualTreeHelper.GetDpi(this);
        _ = SetWindowPos(new WindowInteropHelper(this).Handle, IntPtr.Zero,
            (int)Math.Round(target.X * dpi.DpiScaleX), (int)Math.Round(target.Y * dpi.DpiScaleY),
            (int)Math.Round(target.Width * dpi.DpiScaleX), (int)Math.Round(target.Height * dpi.DpiScaleY),
            0x0014);   // SWP_NOZORDER | SWP_NOACTIVATE
    }

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

    // The height of the list is the height of what it holds until the corner grip is dragged, and the
    // height that was dragged after that; the stored number is the ceiling in the first case and the
    // height itself in the second. It is written here and nowhere else: every path that changes the
    // strip goes through Renumber and UpdateEmptyState, so a capture added, removed, restored or
    // reordered brings the window with it.
    private void ApplyListHeight()
    {
        if (CaptureList is null) return;
        var stored = Controls.StripResizeGeometry.ClampListHeight(
            _settings.StackHeight, StackWorkArea().Height, StackChromeHeight());
        CaptureList.Height = Controls.StripResizeGeometry.ListHeight(Captures.Count, stored, _settings.StackHeightManual);
    }

    // The first placement of the strip: the edge of the monitor, the width from the settings and the
    // middle of the working area. It happens once, from Loaded; every showing after that is
    // EnsureStripPlaced, which leaves the strip where the user dragged it.
    private void PlaceStripInitially()
    {
        var work = StackWorkArea();
        // The width the user dragged the strip to. The only ceiling is the working area of this
        // monitor: a width dragged out on a large screen is pulled back in when the strip opens on
        // a small one, and a settings file written by hand cannot produce a strip nobody can use.
        Width = Controls.StripResizeGeometry.ClampWidth(_settings.StackWidth, work.Width);
        // The height belongs to the list and to what it holds; the stored number is its ceiling.
        ApplyListHeight();
        // The height above was just assigned and ActualHeight still holds the one before it; the
        // placement below is built on the height the window is about to have.
        UpdateLayout();
        Left = work.Right - Width - Controls.StripResizeGeometry.EdgeGap;
        var height = Math.Max(ActualHeight, 160);
        var centred = Math.Max(work.Top + 24, work.Top + (work.Height - height) / 2);
        Top = Math.Max(work.Top, Math.Min(centred, work.Bottom - height));
    }

    // A showing of a strip that has already been placed: the height for what it holds, and the
    // rectangle it stands in only if that rectangle has left the screen. A strip dragged away from
    // the edge used to jump back to it after every capture.
    private void EnsureStripPlaced()
    {
        ApplyListHeight();
        UpdateLayout();
        var target = Controls.StripResizeGeometry.RestoreRect(
            new Rect(Left, Top, Width, ActualHeight), StackWorkArea());
        Left = target.X;
        Top = target.Y;
    }

    // Where the pointer is, in the units the window is placed in. The delta of a Thumb cannot be used
    // for this: it is measured against the grip itself, the grip travels with the window it resizes,
    // and once a clamp stops the window the two drift apart by everything the pointer spent past it.
    private Point PointerInWindowUnits()
    {
        var position = WinForms.Cursor.Position;
        var dpi = VisualTreeHelper.GetDpi(this);
        var scaleX = dpi.DpiScaleX > 0 ? dpi.DpiScaleX : 1;
        var scaleY = dpi.DpiScaleY > 0 ? dpi.DpiScaleY : 1;
        return new Point(position.X / scaleX, position.Y / scaleY);
    }

    // The whole geometry of the strip, taken once at the start of the drag. The right edge is among
    // it for a reason of its own: reading it from Left + Width on every delta would accumulate the
    // rounding of each step and let the strip drift off the screen edge.
    private void BeginResize()
    {
        _resizeRightEdge = Left + Width;
        _resizeTop = Top;
        _resizeStartWidth = Width;
        _resizeStartListHeight = CaptureList.Height;
        _resizeStartChrome = StackChromeHeight();
        _resizeStartPointer = PointerInWindowUnits();
        // The monitor is asked once: the working area cannot change under a drag, and reading it
        // costs a P/Invoke and a DPI lookup on every movement of the mouse.
        _resizeWorkArea = StackWorkArea();
    }

    private void OnWidthDragStarted(object sender, System.Windows.Controls.Primitives.DragStartedEventArgs e) => BeginResize();

    private void OnWidthDragDelta(object sender, System.Windows.Controls.Primitives.DragDeltaEventArgs e)
    {
        var (left, width) = Controls.StripResizeGeometry.WidthFromStart(
            _resizeRightEdge, _resizeStartWidth, PointerInWindowUnits().X - _resizeStartPointer.X, _resizeWorkArea.Left);
        Left = left;
        Width = width;
    }

    private void OnWidthDragCompleted(object sender, System.Windows.Controls.Primitives.DragCompletedEventArgs e) =>
        MutateSettings(stored => stored with { StackWidth = Width });

    // The corner takes both sides at once. The top edge is held where the drag found it, so the strip
    // keeps its place at the screen edge and grows downwards instead of walking around under the
    // pointer. SizeToContent goes off for the length of the drag: while it is on, the window works out
    // a height of its own on the next layout pass, a pass that lands between the assignments below and
    // moves the window a second time inside one movement of the mouse.
    private void OnCornerDragStarted(object sender, System.Windows.Controls.Primitives.DragStartedEventArgs e)
    {
        BeginResize();
        _resizeStartMinHeight = MinHeight;
        Height = ActualHeight;
        MinHeight = 0;
        SizeToContent = SizeToContent.Manual;
    }

    private void OnCornerDragDelta(object sender, System.Windows.Controls.Primitives.DragDeltaEventArgs e)
    {
        var pointer = PointerInWindowUnits();
        var (left, width) = Controls.StripResizeGeometry.WidthFromStart(
            _resizeRightEdge, _resizeStartWidth, pointer.X - _resizeStartPointer.X, _resizeWorkArea.Left);
        // The chrome is the one measured at the start of the drag as well: measuring it again here
        // reads the layout pass before this one, which under a fast drag is a height the window has
        // already left behind.
        var listHeight = Controls.StripResizeGeometry.ListHeightFromStart(
            _resizeStartListHeight, pointer.Y - _resizeStartPointer.Y, _resizeStartChrome, _resizeTop, _resizeWorkArea.Bottom);
        // One block, in one order every time: the top first so the strip cannot be seen to jump, the
        // height last so the window is never taller than what it is about to be moved to.
        CaptureList.Height = listHeight;
        Top = _resizeTop;
        Left = left;
        Width = width;
        Height = _resizeStartChrome + listHeight;
    }

    // A double click on the grip is the standard "size to content" gesture, and it gives the strip
    // back to what it holds. Preview, not the ordinary event: a Thumb captures the mouse in its own
    // MouseLeftButtonDown and MouseDoubleClick never arrives. It is the way the header skips a double
    // click as well, see OnShellMouseDown.
    private void OnCornerGripPress(object sender, MouseButtonEventArgs e)
    {
        if (e.ClickCount != 2) return;
        e.Handled = true;
        MutateSettings(stored => stored with { StackHeightManual = false });
        ApplyListHeight();
    }

    private void OnCornerDragCompleted(object sender, System.Windows.Controls.Primitives.DragCompletedEventArgs e)
    {
        SizeToContent = SizeToContent.Height;
        MinHeight = _resizeStartMinHeight;
        MutateSettings(stored => stored with { StackWidth = Width, StackHeight = CaptureList.Height, StackHeightManual = true });
        // The strip stays where it was let go: the height that was dragged is the height of the list
        // from now on, empty space under the last card included. The call below no longer settles it
        // on anything — it writes back the same number and applies the clamps of the monitor to it.
        ApplyListHeight();
    }

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
            try
            {
                var capture = await _workspace.AddImageAsync(SessionWorkspace.LoadBitmap(path));
                // The name of the file is what tells one import from another, on the chip of the card
                // and in prompt.md; a capture of a region has nothing to put there and leaves it empty.
                capture.Kind = Snapik.Core.Models.CaptureKind.Import;
                capture.Title = Path.GetFileName(path);
                Captures.Add(capture);
                imported++;
            }
            catch (Exception ex) { failures.Add($"{Path.GetFileName(path)}: {ex.Message}"); }
        }
        Renumber(); NoteStripGrowth(); InvalidatePrepared();
        // The chip of a card is written in the markup, so a card born after the strip was translated
        // carries Russian until the next showing of the window: the new ones are translated here.
        UiLanguage.Apply(this);
        var saved = await SaveAsync();
        // The clipboard package follows the stack even when the session file could not be written:
        // a receipt left pointing at the previous package makes the next Ctrl+V rotate the session.
        // Nothing was added means nothing changed, so the published package stays as it is.
        if (imported > 0) await RefreshOwnedClipboardAsync();
        // A failed import must survive the next status update, a successful one has to stay readable for a few seconds.
        if (failures.Count > 0) SetStatus($"{UiLanguage.Text("Не удалось добавить")}: {string.Join("; ", failures)}", true);
        else if (truncated) ShowToast(string.Format(UiLanguage.Text("В ленте максимум {0} снимков. Отправьте или удалите лишние"), SentCaptureRules.MaxStripCaptures));
        else if (saved) ShowToast(string.Format(UiLanguage.Text("Добавлено снимков: {0}"), imported));
        // The import adds to the end of a strip that is already on screen, so it never passes
        // through ShowStackWithoutActivation and asks for the bottom itself.
        if (imported > 0) ScrollStripToEnd();
    }

    private async Task ImportClipboardAsync()
    {
        await _pasteIntentTransition;
        if (StripIsFull()) return;
        if (!Clipboard.ContainsImage() || Clipboard.GetImage() is not { } image) { SetStatus(UiLanguage.Text("В буфере нет изображения."), true); return; }
        image.Freeze();
        Captures.Add(await _workspace.AddImageAsync(image));
        Renumber(); NoteStripGrowth(); InvalidatePrepared();
        var saved = await SaveAsync();
        await RefreshOwnedClipboardAsync();
        if (saved) ShowToast(UiLanguage.Text("Изображение добавлено."));
        ScrollStripToEnd();
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
            if (_hotkeys is null) return UiLanguage.Text("Регистрация клавиш недоступна. Перезапустите Snapik.", language);
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

    // Only the fields the wizard owns, on top of the file as it is now; a file that could not be
    // read is replaced whole, because there is nothing in it to merge into. The appearance step is
    // among them: a theme picked in the wizard used to live until the next start and no longer.
    private bool WriteOnboarding(HotkeySettings candidate, bool merge)
    {
        if (merge) return MutateSettings(stored => MergeOnboarding(stored, candidate));
        try { candidate.Save(_settingsPath); _settings = candidate; return true; }
        catch (Exception ex)
        {
            SetStatus($"{UiLanguage.Text("Не удалось сохранить настройки", candidate.Language)}: {ex.Message}", true);
            return false;
        }
    }

    /// <summary>
    /// The five fields the wizard owns, put on top of the file as it is now. It is a rule of its own
    /// so that the smoke can read it without a strip window: the list of fields is the whole bug.
    /// </summary>
    internal static HotkeySettings MergeOnboarding(HotkeySettings stored, HotkeySettings candidate) => stored with
    {
        CaptureId = candidate.CaptureId, Language = candidate.Language,
        Theme = candidate.Theme, AccentId = candidate.AccentId,
        OnboardingVersion = candidate.OnboardingVersion
    };

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
                        if (_hotkeys is null) return UiLanguage.Text("Регистрация клавиш недоступна. Перезапустите Snapik.");
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
                            Theme = candidate.Theme, AccentId = candidate.AccentId,
                            // The appearance tab offers the palette of the editor as well, so this
                            // field belongs to the dialog too; the colours of the own palette stay
                            // with the editor, the only place they are picked.
                            AnnotationPalette = candidate.AnnotationPalette
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
            // "Go through the tour again" is a link of the settings, and the wizard has to outlive
            // the window that offered it: the dialog only says it was asked for. Inside the try, so
            // the shortcuts are registered once, in the finally below, after both windows are gone.
            if (dialog.OnboardingRequested) ShowOnboarding();
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
        var pending = PendingCaptures.Count;
        CountText.Text = pending.ToString();
        // The capsule shows the same number as the header: what is still waiting to be pasted.
        CapsuleCount.Text = CountText.Text;
        PasteButton.IsEnabled = pending > 0;
        UpdateEmptyState();
    }

    // An empty strip shows a hint instead of an empty list, and it is the window that shrinks: the
    // list carries its height outright (ApplyListHeight), so hiding it takes those pixels out of the
    // layout and the first capture brings them back. The corner grip is hidden with the list, there
    // being nothing to stretch, and it stays hidden in the capsule, where the mode owns it.
    private void UpdateEmptyState()
    {
        if (CaptureList is null) return;
        ApplyListHeight();
        var empty = Captures.Count == 0;
        CaptureList.Visibility = empty ? Visibility.Collapsed : Visibility.Visible;
        EmptyHint.Visibility = empty ? Visibility.Visible : Visibility.Collapsed;
        CornerGrip.Visibility = empty || _capsuleMode ? Visibility.Collapsed : Visibility.Visible;
        // The shortcut may be switched off, and then there is nothing to name: the hint says what is
        // left, the button of the strip.
        EmptyHintText.Text = _settings.CaptureEnabled
            ? string.Format(UiLanguage.Text("Нажми {0} или «Новый снимок»"), HotkeySettings.Find(_settings.CaptureId).Label)
            : UiLanguage.Text("Нажми «Новый снимок»");
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
                Color = OverlayEditorWindow.DefaultAnnotationColor, Thickness = 4,
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

    // The strip is dragged by any free spot of the panel, not by the header alone: the paddings, the
    // gaps between the cards and the header itself, which is transparent and therefore hit-tested
    // whole. Everything that wants a press of its own takes it before this: the buttons, the cards,
    // the two grips and the scrollbar. A double click is let through, it is not the start of a drag.
    private void OnShellMouseDown(object sender, MouseButtonEventArgs e)
    {
        if (e.LeftButton != MouseButtonState.Pressed || e.ClickCount > 1) return;
        DragMove();
    }

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
            _busy = false;
            if (stackHidden) ShowStackWithoutActivation();
        }
        if (requestNext) await CaptureLoopAsync();
    }

    // The right button takes nothing away from the two drags: the cards are dragged on
    // PreviewMouseLeftButtonDown, the window on the left button of the panel. The menu is built here
    // rather than in the markup, the way the menu of "•••" is: a ContextMenu is no part of the visual
    // tree, and the language pass over the window would never reach it.
    private void OnCaptureListRightClick(object sender, MouseButtonEventArgs e)
    {
        if (FindAncestor<ContentPresenter>((DependencyObject)e.OriginalSource)?.Content is not CaptureItem capture) return;
        var menu = new ContextMenu();
        menu.Items.Add(MenuItem("Копировать снимок", async () => await CopySingleCaptureAsync(capture, capture.DisplayLabel)));
        menu.Items.Add(MenuItem("Сохранить снимок…", async () => await SaveSingleCaptureAsAsync(capture)));
        menu.Items.Add(new Separator());
        menu.Items.Add(MenuItem("Удалить", async () => await RemoveCapture(capture)));
        menu.PlacementTarget = CaptureList;
        UiLanguage.Apply(menu);
        menu.IsOpen = true;
        e.Handled = true;
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
        Renumber(); NoteStripGrowth(); InvalidatePrepared(); if (await SaveAsync()) ShowToast(UiLanguage.Text("Снимок восстановлен.")); await RefreshOwnedClipboardAsync();
    }

    private static T? FindAncestor<T>(DependencyObject? current) where T : DependencyObject
    {
        while (current is not null) { if (current is T target) return target; current = VisualTreeHelper.GetParent(current); }
        return null;
    }

    // The way down, for the parts of a card: the template of an item has a namescope of its own, so
    // the card of a container is reached by walking its visual children and not by FindName.
    private static T? FindDescendant<T>(DependencyObject? current, string name) where T : FrameworkElement
    {
        if (current is null) return null;
        if (current is T match && match.Name == name) return match;
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(current); i++)
            if (FindDescendant<T>(VisualTreeHelper.GetChild(current, i), name) is { } found) return found;
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

    // The strip itself, not a copy of its markup: the height of the list, the template of the list
    // and the bar over the cards are the work of this file, and a window built by XamlReader.Parse
    // runs none of it. Five cards fit under the ceiling of 372, so the list is 220 tall and has
    // nothing to scroll, and the last card is whole — that is what the overhang of 48 handed to the
    // items panel is for. Twelve cards run into the ceiling, and the bar that appears has to be the
    // bar of three pixels: the minimum of 17 the default theme gives every ScrollBar is what laid
    // nine pixels of the thumb over the cards and read as a second, dimmer bar.
    internal static void RunStripGrowthProbe()
    {
        // A strip of its own is the only window of the probe, and the application ends with the last
        // window by default: the checks that come after this one would never run.
        var application = Application.Current;
        var shutdown = application?.ShutdownMode ?? ShutdownMode.OnLastWindowClose;
        if (application is not null) application.ShutdownMode = ShutdownMode.OnExplicitShutdown;
        var language = UiLanguage.Current;
        try
        {
            ProbeStrip(5, (window, viewer) =>
            {
                if (Math.Abs(window.CaptureList.Height - 220) > 0.5)
                    throw new InvalidOperationException($"Five cards under a ceiling of 372 make a list of 220, not {window.CaptureList.Height}.");
                if (viewer.ScrollableHeight > 0)
                    throw new InvalidOperationException($"A list that fits must not scroll: {viewer.ScrollableHeight} px of it are out of sight.");
                TheLastCardIsWhole(window, viewer);
            });
            ProbeStrip(12, (window, viewer) =>
            {
                if (Math.Abs(window.CaptureList.Height - Controls.StripResizeGeometry.DefaultListHeight) > 0.5)
                    throw new InvalidOperationException($"Twelve cards stop at the ceiling of 372, not at {window.CaptureList.Height}.");
                if (viewer.ScrollableHeight <= 0)
                    throw new InvalidOperationException("Twelve cards do not fit into 372 and the list has to scroll.");
                var bar = window.StripScrollBar() ?? throw new InvalidOperationException("The template of the list must keep a PART_VerticalScrollBar.");
                if (bar.Visibility != Visibility.Visible || bar.ActualWidth > 6)
                    throw new InvalidOperationException($"The bar of an overflowing strip is {bar.ActualWidth} px wide and {bar.Visibility}.");
                // The path of the showing, taken by hand: the probe shows no window, and the
                // deferred half of ScrollStripToEnd waits for a dispatcher nobody pumps here.
                // The offset lands on the layout pass after the scroll, hence the second one.
                window.ScrollStripToEndCore();
                window.CaptureList.UpdateLayout();
                if (Math.Abs(viewer.VerticalOffset - viewer.ScrollableHeight) > 0.5)
                    throw new InvalidOperationException($"A strip that was shown stands at {viewer.VerticalOffset} of {viewer.ScrollableHeight}: the capture it just took is above the fold.");
                TheLastCardIsWhole(window, viewer);
            });
            // The card that the pointer unfolds, unfolded by hand: the animation of the template is
            // the only thing left out, and what it animates is this margin. The list keeps the
            // height it was given, the 48 the card took go into the extent of the scroll, and the
            // card itself does not move — the cards below it do.
            ProbeStrip(5, (window, viewer) =>
            {
                var presenter = (ScrollContentPresenter)viewer.Template.FindName("PART_ScrollContentPresenter", viewer);
                var third = (ListBoxItem)window.CaptureList.ItemContainerGenerator.ContainerFromIndex(2);
                var topBefore = third.TranslatePoint(new Point(0, 0), presenter).Y;
                var card = FindDescendant<Border>(third, "ThumbCard")
                    ?? throw new InvalidOperationException("The template of a card must keep a border named ThumbCard.");
                card.Margin = new Thickness(0);
                window.CaptureList.UpdateLayout();
                if (Math.Abs(window.CaptureList.Height - 220) > 0.5)
                    throw new InvalidOperationException($"An unfolded card left the list at {window.CaptureList.Height} instead of the 220 five cards are given.");
                if (Math.Abs(viewer.ScrollableHeight - Controls.StripResizeGeometry.CardOverlap) > 0.5)
                    throw new InvalidOperationException($"An unfolded card adds 48 px to the extent, not {viewer.ScrollableHeight}.");
                if (Math.Abs(third.TranslatePoint(new Point(0, 0), presenter).Y - topBefore) > 0.5)
                    throw new InvalidOperationException("An unfolded card must stay where it was: the cards below it are the ones that move.");
            });
        }
        finally
        {
            if (application is not null) application.ShutdownMode = shutdown;
            UiLanguage.Current = language;
        }
    }

    // The bottom of the last card against the bottom of the field the cards stand in. It is the
    // same question in both cases — a list that fits and a list scrolled to its end — and the
    // overhang of 48 given to the items panel is what makes the answer yes.
    private static void TheLastCardIsWhole(EdgeStackWindow window, ScrollViewer viewer)
    {
        var presenter = (ScrollContentPresenter)viewer.Template.FindName("PART_ScrollContentPresenter", viewer);
        var last = (ListBoxItem)window.CaptureList.ItemContainerGenerator.ContainerFromIndex(window.Captures.Count - 1);
        var cardBottom = last.TranslatePoint(new Point(0, 0), presenter).Y + Controls.StripResizeGeometry.CardHeight;
        if (cardBottom > presenter.ActualHeight + 0.5)
            throw new InvalidOperationException($"The last card ends at {cardBottom} and the list at {presenter.ActualHeight}: the bottom of it is cut off.");
    }

    // A strip of its own for every case: a list refilled in place keeps the extent of the list it
    // held before, and the probe would be measuring the state it has already left.
    private static void ProbeStrip(int count, Action<EdgeStackWindow, ScrollViewer> checks)
    {
        var root = Path.Combine(Path.GetTempPath(), "Snapik", $"strip-probe-{Guid.NewGuid():N}");
        var window = new EdgeStackWindow(new LaunchOptions(false, true, root));
        try
        {
            for (var i = 0; i < count; i++)
                window.Captures.Add(new CaptureItem { Image = SessionWorkspace.CreateDemoBitmap(i, 320, 200), SourcePath = $"strip-probe-{i}.png" });
            // The path every capture takes: the renumbering carries the empty state, and that one
            // carries the height of the list.
            window.Renumber();
            // The list is laid out the way the shell lays it out — the window without the field under
            // the shadow and without the padding of the panel, 184 px at a window of 244. The window
            // itself has no handle here and would measure to nothing.
            var width = window.Width - 2 * Controls.StripResizeGeometry.ShadowMargin - 2 * Controls.StripResizeGeometry.ShellPadding;
            window.CaptureList.Measure(new Size(width, window.CaptureList.Height));
            window.CaptureList.Arrange(new Rect(0, 0, width, window.CaptureList.Height));
            window.CaptureList.UpdateLayout();
            checks(window, (ScrollViewer)VisualTreeHelper.GetChild(window.CaptureList, 0));
        }
        finally
        {
            window._allowClose = true;
            window.Close();
            if (Directory.Exists(root)) Directory.Delete(root, true);
        }
    }

    // Raise the strip without activating it; whether it stays above other applications is the StackTopmost setting.
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWindowPos(IntPtr window, IntPtr after, int x, int y, int width, int height, uint flags);

    private const int SwShowNoActivate = 4;

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ShowWindow(IntPtr window, int command);

    [DllImport("dwmapi.dll")]
    private static extern int DwmFlush();
}
