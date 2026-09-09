using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Collections.Specialized;
using System.ComponentModel;
using System.IO;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Microsoft.Win32;
using SnapBrief.Core.Exporting;
using SnapBrief.Windows;
using WinForms = System.Windows.Forms;

namespace SnapBrief.App;

public partial class MainWindow : Window, INotifyPropertyChanged
{
    private readonly LaunchOptions _options;
    private readonly SessionWorkspace _workspace;
    private readonly DispatcherTimer _saveTimer;
    private readonly Stack<WorkspaceSnapshot> _undo = [];
    private readonly Stack<WorkspaceSnapshot> _redo = [];
    private readonly WindowsClipboardService _clipboard = new();
    private readonly IPasteCoordinator _pasteCoordinator;
    private readonly string _settingsPath;
    private HotkeySettings _settings;
    private CaptureItem? _activeCapture;
    private EditorTool _currentTool = EditorTool.Select;
    private PreparedExport? _prepared;
    private WorkspaceSnapshot? _currentSnapshot;
    private Point _filmstripDragStart;
    private CaptureItem? _draggedCapture;
    private WindowsGlobalHotkeyService? _hotkeys;
    private bool _restoring;
    private bool _closingAfterSave;
    private bool _captureOpen;
    private bool _preparing;
    private bool _pasting;
    private bool _stickyStatus;
    private bool _explicitExit;
    private readonly WinForms.NotifyIcon? _trayIcon;
    private readonly bool _secondary;

    public MainWindow(LaunchOptions options, bool secondary = false)
    {
        _options = options;
        _secondary = secondary;
        var dataRoot = options.DataDirectory;
        if (options.Demo && string.IsNullOrWhiteSpace(dataRoot))
            dataRoot = Path.Combine(Path.GetTempPath(), "SnapBrief", $"demo-{Environment.ProcessId}");
        _workspace = new SessionWorkspace(dataRoot);
        _settingsPath = Path.Combine(options.DataDirectory ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SnapBrief"), "settings.json");
        _settings = HotkeySettings.Load(_settingsPath);
        var foreground = new WindowsForegroundTargetService();
        _pasteCoordinator = new PasteCoordinator(_clipboard, foreground, new WindowsInputInjector(), new UnobservableAcceptanceObserver(foreground));
        _saveTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(500) };
        _saveTimer.Tick += OnSaveTimerTick;

        InitializeComponent();
        DataContext = this;
        if (!secondary)
        {
            _trayIcon = new WinForms.NotifyIcon
            {
                Text = "SnapBrief",
                Icon = System.Drawing.SystemIcons.Application,
                Visible = true,
                ContextMenuStrip = new WinForms.ContextMenuStrip()
            };
            _trayIcon.ContextMenuStrip.Items.Add("Открыть", null, (_, _) => Dispatcher.Invoke(ShowFromTray));
            _trayIcon.ContextMenuStrip.Items.Add("Сделать снимок", null, (_, _) => Dispatcher.InvokeAsync(CaptureAsync));
            _trayIcon.ContextMenuStrip.Items.Add(new WinForms.ToolStripSeparator());
            _trayIcon.ContextMenuStrip.Items.Add("Выйти", null, (_, _) => Dispatcher.Invoke(() => { _explicitExit = true; Close(); }));
            _trayIcon.DoubleClick += (_, _) => Dispatcher.Invoke(ShowFromTray);
        }
        Loaded += OnLoaded;
        SourceInitialized += OnSourceInitialized;
        Closing += OnClosing;
    }

    public ObservableCollection<CaptureItem> Captures { get; } = [];
    public IReadOnlyList<TargetProfile> TargetProfiles { get; } = SnapBrief.Windows.TargetProfiles.All;

    public CaptureItem? ActiveCapture
    {
        get => _activeCapture;
        set
        {
            if (ReferenceEquals(_activeCapture, value)) return;
            if (_activeCapture is not null) _activeCapture.IsSelected = false;
            _activeCapture = value;
            if (_activeCapture is not null) _activeCapture.IsSelected = true;
            OnPropertyChanged();
            RefreshInterface();
        }
    }

    public EditorTool CurrentTool
    {
        get => _currentTool;
        set { if (_currentTool == value) return; _currentTool = value; OnPropertyChanged(); }
    }

    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        StartupTrace.Write(_options, "MainWindow.Loaded entered");
        try
        {
            if (_options.Demo)
                await SeedDemoAsync();
            else
            {
                foreach (var capture in await _workspace.LoadCurrentAsync()) AddCaptureToUi(capture);
                OverallNoteBox.Text = _workspace.RestoredGlobalNote;
                if (_workspace.RestoredProfileId is { } profileId)
                    TargetProfileBox.SelectedItem = TargetProfiles.FirstOrDefault(p => p.Id == profileId) ?? TargetProfileBox.SelectedItem;
            }
            ActiveCapture = Captures.FirstOrDefault();
            _currentSnapshot = TakeSnapshot();
            RefreshInterface();
            StartupTrace.Write(_options, "MainWindow.Loaded completed");
        }
        catch (Exception ex) { StartupTrace.Write(_options, $"MainWindow.Loaded failed: {ex}"); SetStatus($"Не удалось восстановить сессию: {ex.Message}", true); }
    }

    private void OnSourceInitialized(object? sender, EventArgs e)
    {
        if (_secondary) return;
        try
        {
            _hotkeys = new WindowsGlobalHotkeyService(new WindowInteropHelper(this).Handle);
            _hotkeys.Pressed += OnGlobalHotkey;
            var conflicts = new List<string>();
            try { _hotkeys.Register("capture", _settings.CaptureGesture); }
            catch { conflicts.Add("захват"); }
            try { _hotkeys.Register("paste", _settings.PasteGesture); }
            catch { conflicts.Add("вставка"); }
            if (conflicts.Count > 0) SetStatus($"Не удалось зарегистрировать: {string.Join(", ", conflicts)}. Выберите другое сочетание в настройках.", true);
        }
        catch (Exception ex) { SetStatus($"Горячие клавиши заняты: {ex.Message}", true); }
    }

    private void OnSettingsClick(object sender, RoutedEventArgs e)
    {
        var dialog = new HotkeySettingsWindow(_settings) { Owner = this };
        if (dialog.ShowDialog() != true || dialog.Result is null) return;
        _settings = dialog.Result;
        _settings.Save(_settingsPath);
        try
        {
            _hotkeys?.Unregister("capture");
            _hotkeys?.Unregister("paste");
            var conflicts = new List<string>();
            try { _hotkeys?.Register("capture", _settings.CaptureGesture); } catch { conflicts.Add("захват"); }
            try { _hotkeys?.Register("paste", _settings.PasteGesture); } catch { conflicts.Add("вставка"); }
            SetStatus(conflicts.Count == 0 ? "Горячие клавиши обновлены." : $"Сочетание занято: {string.Join(", ", conflicts)}. Остальные сочетания продолжают работать.", conflicts.Count > 0);
        }
        catch (Exception ex) { SetStatus($"Не удалось применить горячие клавиши: {ex.Message}", true); }
    }

    private void OnGlobalHotkey(object? sender, GlobalHotkeyPressed e)
    {
        Dispatcher.InvokeAsync(async () =>
        {
            if (e.Id == "capture") await CaptureAsync();
            else if (e.Id == "paste") await PastePreparedAsync(hideWindow: false);
        });
    }

    private async void OnCaptureClick(object sender, RoutedEventArgs e) => await CaptureAsync();

    private async Task CaptureAsync()
    {
        if (_captureOpen || _preparing || _pasting) return;
        _captureOpen = true;
        try
        {
            SetStatus("Выберите область; Esc отменяет захват.");
            var bitmap = await CaptureOverlay.CaptureAsync(this);
            if (bitmap is null) { SetStatus("Захват отменён. Сессия не изменена."); return; }
            var capture = await _workspace.AddImageAsync(bitmap);
            AddCaptureToUi(capture);
            ActiveCapture = capture;
            RecordMutation();
            CaptureNoteBox.Focus();
            SetStatus("Снимок добавлен. Можно отметить область или написать комментарий.");
        }
        catch (Exception ex) { SetStatus($"Не удалось сделать снимок: {ex.Message}", true); }
        finally { _captureOpen = false; }
    }

    private async void OnImportFileClick(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog { Filter = "Изображения|*.png;*.jpg;*.jpeg|PNG|*.png|JPEG|*.jpg;*.jpeg", Multiselect = true };
        if (dialog.ShowDialog(this) != true) return;
        var imported = 0;
        foreach (var file in dialog.FileNames)
        {
            try
            {
                var capture = await _workspace.AddImageAsync(SessionWorkspace.LoadBitmap(file));
                AddCaptureToUi(capture);
                ActiveCapture = capture;
                imported++;
            }
            catch (Exception ex) { SetStatus($"Не удалось импортировать {Path.GetFileName(file)}: {ex.Message}", true); }
        }
        if (imported > 0) RecordMutation();
        SetStatus($"Импортировано изображений: {imported}.");
    }

    private async void OnImportClipboardClick(object sender, RoutedEventArgs e)
    {
        try
        {
            if (!Clipboard.ContainsImage()) { SetStatus("В буфере обмена нет изображения.", true); return; }
            var image = Clipboard.GetImage();
            if (image is null) { SetStatus("Изображение из буфера не удалось прочитать.", true); return; }
            image.Freeze();
            var capture = await _workspace.AddImageAsync(image);
            AddCaptureToUi(capture);
            ActiveCapture = capture;
            RecordMutation();
            SetStatus("Изображение из буфера добавлено.");
        }
        catch (Exception ex) { SetStatus($"Буфер обмена занят: {ex.Message}", true); }
    }

    private async void OnFileDrop(object sender, DragEventArgs e)
    {
        try
        {
            if (!e.Data.GetDataPresent(DataFormats.FileDrop)) return;
            var files = ((string[])e.Data.GetData(DataFormats.FileDrop)).Where(IsImageFile).ToArray();
            var imported = 0;
            foreach (var file in files)
            {
                try
                {
                    var capture = await _workspace.AddImageAsync(SessionWorkspace.LoadBitmap(file));
                    AddCaptureToUi(capture);
                    ActiveCapture = capture;
                    imported++;
                }
                catch (Exception ex) { SetStatus($"Не удалось импортировать {Path.GetFileName(file)}: {ex.Message}", true); }
            }
            if (imported > 0) { RecordMutation(); SetStatus($"Добавлено файлов: {imported}."); }
        }
        catch (Exception ex) { SetStatus($"Не удалось обработать перетаскивание: {ex.Message}", true); }
    }

    private void OnToolClick(object sender, RoutedEventArgs e)
    {
        if (sender is not System.Windows.Controls.Primitives.ToggleButton selected || !Enum.TryParse<EditorTool>(selected.Tag?.ToString(), out var tool)) return;
        CurrentTool = tool;
        foreach (var button in new[] { SelectTool, ArrowTool, RectangleTool, PenTool, HighlightTool, TextTool, ConcealTool })
            button.IsChecked = ReferenceEquals(button, selected);
        EditorCanvas.Cursor = tool == EditorTool.Select ? Cursors.Arrow : Cursors.Cross;
    }

    private void OnAnnotationCreated(object sender, AnnotationItem annotation)
    {
        SubscribeAnnotation(annotation);
        RefreshLabels();
        RecordMutation();
        Dispatcher.BeginInvoke(() => FocusAnnotationNote(annotation), DispatcherPriority.Input);
    }

    private void OnCanvasSelectionChanged(object sender, AnnotationItem? annotation)
    {
        if (annotation is not null) Dispatcher.BeginInvoke(() => FocusAnnotationNote(annotation), DispatcherPriority.Input);
    }

    private void OnAnnotationChanged(object sender, EventArgs e)
    {
        RefreshLabels();
        RecordMutation();
    }

    private void OnAnnotationNoteFocus(object sender, KeyboardFocusChangedEventArgs e)
    {
        if (sender is TextBox { Tag: AnnotationItem item }) EditorCanvas.SelectAnnotation(item.Id);
    }

    private void OnNoteTextChanged(object sender, TextChangedEventArgs e)
    {
        if (_restoring) return;
        RefreshLabels();
        _currentSnapshot = TakeSnapshot();
        QueueSave();
    }

    private void OnAnnotationPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (_restoring || e.PropertyName == nameof(AnnotationItem.IsSelected)) return;
        RefreshLabels();
        _currentSnapshot = TakeSnapshot();
        QueueSave();
        EditorCanvas.InvalidateVisual();
    }

    private void OnCaptureSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (Filmstrip.SelectedItem is CaptureItem capture) ActiveCapture = capture;
    }

    private void OnDeleteCaptureClick(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: CaptureItem capture }) return;
        var index = Captures.IndexOf(capture);
        Captures.Remove(capture);
        ActiveCapture = Captures.Count == 0 ? null : Captures[Math.Clamp(index, 0, Captures.Count - 1)];
        RecordMutation();
        e.Handled = true;
        SetStatus("Снимок удалён. Ctrl+Z восстановит его.");
    }

    private void OnFilmstripMouseDown(object sender, MouseButtonEventArgs e)
    {
        _filmstripDragStart = e.GetPosition(Filmstrip);
        _draggedCapture = FindAncestor<ListBoxItem>((DependencyObject)e.OriginalSource)?.DataContext as CaptureItem;
    }

    private void OnFilmstripMouseMove(object sender, MouseEventArgs e)
    {
        if (e.LeftButton != MouseButtonState.Pressed || _draggedCapture is null) return;
        var point = e.GetPosition(Filmstrip);
        if (Math.Abs(point.X - _filmstripDragStart.X) < SystemParameters.MinimumHorizontalDragDistance) return;
        DragDrop.DoDragDrop(Filmstrip, _draggedCapture, DragDropEffects.Move);
    }

    private void OnFilmstripDrop(object sender, DragEventArgs e)
    {
        if (!e.Data.GetDataPresent(typeof(CaptureItem))) return;
        var source = (CaptureItem)e.Data.GetData(typeof(CaptureItem));
        var target = FindAncestor<ListBoxItem>((DependencyObject)e.OriginalSource)?.DataContext as CaptureItem;
        if (target is null || ReferenceEquals(source, target)) return;
        var destination = Captures.IndexOf(target);
        Captures.Move(Captures.IndexOf(source), destination);
        ActiveCapture = source;
        RecordMutation();
        SetStatus("Порядок снимков изменён; метки обновлены.");
    }

    private void OnUndoClick(object sender, RoutedEventArgs e) => Undo();
    private void OnRedoClick(object sender, RoutedEventArgs e) => Redo();

    private void Undo()
    {
        if (_undo.Count == 0) { SetStatus("Больше нечего отменять."); return; }
        if (_currentSnapshot is not null) _redo.Push(_currentSnapshot);
        RestoreSnapshot(_undo.Pop());
        SetStatus("Последнее действие отменено.");
    }

    private void Redo()
    {
        if (_redo.Count == 0) { SetStatus("Больше нечего повторять."); return; }
        if (_currentSnapshot is not null) _undo.Push(_currentSnapshot);
        RestoreSnapshot(_redo.Pop());
        SetStatus("Действие повторено.");
    }

    private async void OnPrepareClick(object sender, RoutedEventArgs e) => await PrepareAsync();

    private async Task<bool> PrepareAsync()
    {
        if (Captures.Count == 0 || _preparing || _pasting) return false;
        _preparing = true;
        try
        {
            PrepareButton.IsEnabled = false;
            SetStatus("Готовим отдельные PNG и текст задания…");
            _prepared = await _workspace.PrepareAsync(Captures, OverallNoteBox.Text, SelectedProfile?.Id);
            PasteButton.IsEnabled = true;
            CopyButton.IsEnabled = true;
            StatusDot.Fill = new SolidColorBrush(Color.FromRgb(49, 92, 245));
            SetStatus($"Пакет подготовлен: {_prepared.Manifest.CaptureCount} изображений, {_prepared.Manifest.NoteCount} заметок. Запрос не отправлен.");
            return true;
        }
        catch (Exception ex) { SetStatus($"Не удалось подготовить пакет: {ex.Message}", true); return false; }
        finally { _preparing = false; PrepareButton.IsEnabled = Captures.Count > 0; }
    }

    private async void OnCopyPackageClick(object sender, RoutedEventArgs e)
    {
        if (_prepared is null && !await PrepareAsync()) return;
        if (_prepared is null) return;
        try
        {
            var before = await _clipboard.CaptureAsync(CancellationToken.None);
            await _clipboard.SetPackageGuardedAsync(_prepared.GetImagePathsInOrder(), _prepared.Manifest.PromptText, before.SequenceNumber, CancellationToken.None);
            SetStatus("PNG-файлы и текст помещены в один буферный пакет. Получатель может выбрать только один формат; тогда используйте «Вставить».", sticky: true);
        }
        catch (Exception ex) { SetStatus($"Не удалось скопировать пакет: {ex.Message}", true); }
    }

    private async void OnPasteClick(object sender, RoutedEventArgs e) => await PastePreparedAsync(hideWindow: true);

    private async Task PastePreparedAsync(bool hideWindow)
    {
        if (_pasting || _captureOpen || _preparing) return;
        if (_prepared is null && !await PrepareAsync()) return;
        var profile = SelectedProfile;
        if (_prepared is null || profile is null) return;
        _pasting = true;
        try
        {
            PasteButton.IsEnabled = false;
            if (hideWindow)
            {
                Hide();
                await Task.Delay(300);
            }
            var package = new PreparedPastePackage(_prepared.Manifest.ExportId, _prepared.GetImagePathsInOrder(), _prepared.Manifest.PromptText);
            var progress = new Progress<PasteProgress>(p => SetStatus(p.Message));
            var result = await _pasteCoordinator.PasteAsync(package, profile, progress: progress);
            SetStatus(result.Message, result.Status is not (PasteStatus.CompletedVerified or PasteStatus.CompletedUnverified), sticky: true);
        }
        catch (Exception ex) { SetStatus($"Вставка остановлена: {ex.Message}", true); }
        finally
        {
            if (hideWindow) { Show(); Activate(); }
            PasteButton.IsEnabled = _prepared is not null;
            _pasting = false;
        }
    }

    private async void OnSaveAsClick(object sender, RoutedEventArgs e)
    {
        if (_prepared is null && !await PrepareAsync()) return;
        using var dialog = new WinForms.FolderBrowserDialog { Description = "Выберите папку для пакета SnapBrief", UseDescriptionForTitle = true };
        if (dialog.ShowDialog() != WinForms.DialogResult.OK || _prepared is null) return;
        try
        {
            var destination = Path.Combine(dialog.SelectedPath, $"SnapBrief-{DateTime.Now:yyyyMMdd-HHmmss}");
            Directory.CreateDirectory(destination);
            foreach (var file in Directory.EnumerateFiles(_prepared.RootDirectory)) File.Copy(file, Path.Combine(destination, Path.GetFileName(file)), false);
            SetStatus($"Пакет сохранён: {destination}");
        }
        catch (Exception ex) { SetStatus($"Не удалось сохранить пакет: {ex.Message}", true); }
    }

    private void OnTargetProfileChanged(object sender, SelectionChangedEventArgs e)
    {
        _prepared = null;
        PasteButton.IsEnabled = false;
        CopyButton.IsEnabled = false;
        QueueSave();
    }

    private async void OnSaveTimerTick(object? sender, EventArgs e)
    {
        _saveTimer.Stop();
        try
        {
            await _workspace.SaveAsync(Captures, OverallNoteBox.Text, SelectedProfile?.Id);
            if (!_stickyStatus) SetStatus("Все изменения сохранены.");
        }
        catch (Exception ex) { SetStatus($"Не удалось сохранить сессию: {ex.Message}", true); }
    }

    private async void OnClosing(object? sender, CancelEventArgs e)
    {
        if (_closingAfterSave) { _hotkeys?.Dispose(); _clipboard.Dispose(); if (_trayIcon is not null) { _trayIcon.Visible = false; _trayIcon.Dispose(); } return; }
        e.Cancel = true;
        _saveTimer.Stop();
        try { await _workspace.SaveAsync(Captures, OverallNoteBox.Text, SelectedProfile?.Id); }
        catch (Exception ex) { SetStatus($"Не удалось сохранить перед выходом: {ex.Message}", true); return; }
        if (_explicitExit || _secondary)
        {
            _closingAfterSave = true;
            Close();
        }
        else
        {
            Hide();
            SetStatus("SnapBrief продолжает работать в области уведомлений.");
        }
    }

    private void OnPreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (Keyboard.FocusedElement is TextBox) return;
        if (Keyboard.Modifiers == ModifierKeys.Control && e.Key == Key.Z) { Undo(); e.Handled = true; return; }
        if (Keyboard.Modifiers == ModifierKeys.Control && e.Key == Key.Y) { Redo(); e.Handled = true; return; }
        var tool = e.Key switch { Key.V => EditorTool.Select, Key.A => EditorTool.Arrow, Key.R => EditorTool.Rectangle, Key.P => EditorTool.Pen, Key.H => EditorTool.Highlight, Key.T => EditorTool.Text, Key.B => EditorTool.Conceal, _ => (EditorTool?)null };
        if (tool is null) return;
        var button = new[] { SelectTool, ArrowTool, RectangleTool, PenTool, HighlightTool, TextTool, ConcealTool }.First(b => Equals(b.Tag?.ToString(), tool.Value.ToString()));
        button.RaiseEvent(new RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent));
        e.Handled = true;
    }

    private void AddCaptureToUi(CaptureItem capture)
    {
        capture.PropertyChanged += (_, args) => { if (args.PropertyName == nameof(CaptureItem.Note)) OnNoteTextChanged(this, null!); };
        capture.Annotations.CollectionChanged += OnAnnotationsCollectionChanged;
        foreach (var annotation in capture.Annotations) SubscribeAnnotation(annotation);
        Captures.Add(capture);
        RenumberCaptures();
    }

    private void OnAnnotationsCollectionChanged(object? sender, NotifyCollectionChangedEventArgs e)
    {
        if (e.NewItems is not null) foreach (AnnotationItem item in e.NewItems) SubscribeAnnotation(item);
        RefreshLabels();
    }

    private void SubscribeAnnotation(AnnotationItem annotation)
    {
        annotation.PropertyChanged -= OnAnnotationPropertyChanged;
        annotation.PropertyChanged += OnAnnotationPropertyChanged;
    }

    private void RecordMutation()
    {
        if (_restoring) return;
        if (_currentSnapshot is not null) _undo.Push(_currentSnapshot);
        _redo.Clear();
        RenumberCaptures();
        RefreshLabels();
        _currentSnapshot = TakeSnapshot();
        _prepared = null;
        PasteButton.IsEnabled = false;
        CopyButton.IsEnabled = false;
        QueueSave();
        RefreshInterface();
    }

    private WorkspaceSnapshot TakeSnapshot() => new(Captures.Select(c => c.DeepClone()).ToList(), ActiveCapture?.Id, OverallNoteBox?.Text ?? string.Empty);

    private void RestoreSnapshot(WorkspaceSnapshot snapshot)
    {
        _restoring = true;
        try
        {
            Captures.Clear();
            foreach (var capture in snapshot.Captures.Select(c => c.DeepClone())) AddCaptureToUi(capture);
            OverallNoteBox.Text = snapshot.GlobalNote;
            ActiveCapture = Captures.FirstOrDefault(c => c.Id == snapshot.ActiveCaptureId) ?? Captures.FirstOrDefault();
            _currentSnapshot = TakeSnapshot();
            _prepared = null;
            PasteButton.IsEnabled = false;
        }
        finally { _restoring = false; }
        QueueSave();
        RefreshInterface();
    }

    private void RenumberCaptures()
    {
        for (var i = 0; i < Captures.Count; i++) Captures[i].DisplayLabel = CaptureLabels.ForIndex(i);
        Filmstrip?.Items.Refresh();
    }

    private void RefreshLabels()
    {
        if (ActiveCapture is null) return;
        var core = ActiveCapture.ToCore();
        var labels = CaptureLabels.ForNotedAnnotations(ActiveCapture.DisplayLabel, core).ToDictionary(x => x.Annotation.Id, x => x.DisplayLabel);
        foreach (var annotation in ActiveCapture.Annotations)
            annotation.Label = labels.GetValueOrDefault(annotation.Id, string.Empty);
        NotesList?.Items.Refresh();
        EditorCanvas?.InvalidateVisual();
        AnnotationCount.Text = ActiveCapture.Annotations.Count.ToString();
        RefreshSummary();
    }

    private void RefreshInterface()
    {
        var hasCapture = ActiveCapture is not null;
        EmptyState.Visibility = hasCapture ? Visibility.Collapsed : Visibility.Visible;
        CaptureNoteBox.IsEnabled = hasCapture;
        PrepareButton.IsEnabled = Captures.Count > 0;
        CaptureIdentity.Text = hasCapture ? $"Снимок {ActiveCapture!.DisplayLabel}" : "—";
        AnnotationCount.Text = (ActiveCapture?.Annotations.Count ?? 0).ToString();
        RefreshLabels();
        RefreshSummary();
    }

    private void RefreshSummary()
    {
        var notes = Captures.Sum(c => c.NoteCount) + (string.IsNullOrWhiteSpace(OverallNoteBox?.Text) ? 0 : 1);
        PackageSummary.Text = $"{Captures.Count} {Plural(Captures.Count, "изображение", "изображения", "изображений")} · {notes} {Plural(notes, "заметка", "заметки", "заметок")}";
    }

    private void QueueSave()
    {
        if (_restoring || !IsLoaded) return;
        _prepared = null;
        PasteButton.IsEnabled = false;
        CopyButton.IsEnabled = false;
        _saveTimer.Stop();
        _saveTimer.Start();
        if (!_stickyStatus) SetStatus("Сохраняем изменения…");
    }

    private void SetStatus(string text, bool error = false, bool sticky = false)
    {
        if (!Dispatcher.CheckAccess()) { Dispatcher.Invoke(() => SetStatus(text, error, sticky)); return; }
        StatusText.Text = text;
        StatusDot.Fill = error ? (Brush)FindResource("DangerBrush") : new SolidColorBrush(Color.FromRgb(114, 128, 153));
        _stickyStatus = error || sticky;
    }

    private TargetProfile? SelectedProfile => TargetProfileBox?.SelectedItem as TargetProfile;

    private void ShowFromTray()
    {
        Show();
        WindowState = WindowState.Normal;
        Activate();
    }

    private void FocusAnnotationNote(AnnotationItem item)
    {
        NotesList.UpdateLayout();
        var textBox = FindVisualChild<TextBox>(NotesList, box => ReferenceEquals(box.Tag, item));
        textBox?.Focus();
    }

    private async Task SeedDemoAsync()
    {
        if (Captures.Count > 0) return;
        var notes = new[] { "Увеличить кнопку", "Перенести пункт выше", "Текст обрезается" };
        for (var i = 0; i < 3; i++)
        {
            var capture = await _workspace.AddImageAsync(SessionWorkspace.CreateDemoBitmap(i));
            capture.Note = i == 2 ? notes[i] : string.Empty;
            if (i < 2)
            {
                capture.Annotations.Add(new AnnotationItem
                {
                    Kind = i == 0 ? EditorTool.Arrow : EditorTool.Rectangle,
                    Points = [new Point(770 - i * 40, 470 - i * 20), new Point(1010 - i * 35, 575 - i * 28)],
                    Note = notes[i], Color = Color.FromRgb(49, 92, 245), Thickness = 5
                });
            }
            AddCaptureToUi(capture);
        }
        OverallNoteBox.Text = "Сохранить цвета";
        ActiveCapture = Captures[0];
        await _workspace.SaveAsync(Captures, OverallNoteBox.Text, SelectedProfile?.Id);
        SetStatus("Демонстрационная сессия создана во временной папке.");
    }

    private static bool IsImageFile(string path) => new[] { ".png", ".jpg", ".jpeg" }.Contains(Path.GetExtension(path), StringComparer.OrdinalIgnoreCase);

    private static T? FindAncestor<T>(DependencyObject? current) where T : DependencyObject
    {
        while (current is not null) { if (current is T target) return target; current = VisualTreeHelper.GetParent(current); }
        return null;
    }

    private static T? FindVisualChild<T>(DependencyObject parent, Func<T, bool> predicate) where T : DependencyObject
    {
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(parent); i++)
        {
            var child = VisualTreeHelper.GetChild(parent, i);
            if (child is T match && predicate(match)) return match;
            var nested = FindVisualChild(child, predicate);
            if (nested is not null) return nested;
        }
        return null;
    }

    private static string Plural(int count, string one, string few, string many)
    {
        var n = Math.Abs(count) % 100; var n1 = n % 10;
        if (n is > 10 and < 20) return many;
        if (n1 == 1) return one;
        return n1 is >= 2 and <= 4 ? few : many;
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    private sealed record WorkspaceSnapshot(IReadOnlyList<CaptureItem> Captures, Guid? ActiveCaptureId, string GlobalNote);
}
