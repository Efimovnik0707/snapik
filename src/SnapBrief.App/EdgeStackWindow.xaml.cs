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
    private Task _pasteIntentTransition = Task.CompletedTask;
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
        _pasteIntentObserver = new WindowsPasteIntentObserver(intent =>
        {
            if (_sessionResetting || !_pasteIntentTransition.IsCompleted || _clipboardPublicationGate.CurrentCount == 0 ||
                _ownedClipboardReceipt is not { } receipt ||
                intent.ClipboardSequenceNumber != receipt.SequenceNumber ||
                string.IsNullOrEmpty(_ownedClipboardPromptText) || _prepared is null) return false;
            if (intent.Gesture != HotkeyGesture.CtrlV && intent.Gesture != HotkeyGesture.AltV) return false;
            var target = foreground.Capture();
            if (!target.IsUsable || target.WindowHandle != intent.ForegroundWindowHandle ||
                target.ProcessId != intent.ForegroundProcessId) return false;
            // Codex Desktop keeps the untouched CompleteAsync path: its physical Ctrl+V paste
            // already works against the composite package, so it must not be intercepted here.
            return !foreground.Matches(target, SnapBrief.Windows.TargetProfiles.CodexDesktop);
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
        if (receiptAtIntent is null || e.ClipboardSequenceNumber != receiptAtIntent.Value.SequenceNumber) return;
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

            // A newer capture may have replaced the package while completion was waiting.
            // Never rotate that newer session in response to this older paste intent.
            if (_ownedClipboardReceipt != receiptAtIntent) return;

            if (completion.CurrentClipboardReceipt is { } textReceipt)
                _ownedClipboardReceipt = textReceipt;

            if (completion.Status == CodexPasteCompletionStatus.CompletedUnverified)
            {
                await StartNewSessionAsync();
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
            SetStatus($"Вставка замечена, но новая сессия не создана: {ex.Message}", true);
        }
        finally { _clipboardPublicationGate.Release(); }
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
        var dialog = new OpenFileDialog { Filter = "Изображения|*.png;*.jpg;*.jpeg", Multiselect = true };
        if (dialog.ShowDialog(this) != true) return;
        var imported = 0;
        foreach (var path in dialog.FileNames)
        {
            try { Captures.Add(await _workspace.AddImageAsync(SessionWorkspace.LoadBitmap(path))); imported++; }
            catch (Exception ex) { SetStatus($"{Path.GetFileName(path)}: {ex.Message}", true); }
        }
        Renumber(); InvalidatePrepared(); await SaveAsync(); SetStatus($"Добавлено: {imported}");
    }

    private async Task ImportClipboardAsync()
    {
        await _pasteIntentTransition;
        if (!Clipboard.ContainsImage() || Clipboard.GetImage() is not { } image) { SetStatus("В буфере нет изображения.", true); return; }
        image.Freeze();
        Captures.Add(await _workspace.AddImageAsync(image));
        Renumber(); InvalidatePrepared(); await SaveAsync(); SetStatus("Изображение добавлено.");
    }

    private async Task CopyPackageAsync()
    {
        await _pasteIntentTransition;
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
        if (error) StartupTrace.Write(_options, text);
        StatusText.Text = text;
        StatusText.Visibility = error ? Visibility.Visible : Visibility.Collapsed;
        StatusText.Foreground = new SolidColorBrush(Color.FromRgb(255, 155, 149));
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
        if (_allowClose) {  _hotkeys?.Dispose(); _pasteIntentObserver.Dispose(); _clipboard.Dispose(); _trayIcon.Visible = false; _trayIcon.Dispose(); return; }
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
