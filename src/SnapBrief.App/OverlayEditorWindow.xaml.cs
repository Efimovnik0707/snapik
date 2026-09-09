using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using SnapBrief.Core.Exporting;
using SnapBrief.Core.Editing;
using WinForms = System.Windows.Forms;

namespace SnapBrief.App;

public sealed record OverlayEditResult(CaptureItem? Capture, bool AddNext, bool Cancelled);

public partial class OverlayEditorWindow : Window
{
    private static OverlayEditorWindow? _active;

    private readonly SessionWorkspace _workspace;
    private readonly DesktopFrame _frame;
    private readonly int _captureIndex;
    private readonly bool _isNew;
    private readonly Stack<OverlaySnapshot> _undo = [];
    private readonly Stack<OverlaySnapshot> _redo = [];
    private readonly Dictionary<Guid, TextBlock> _chipLabels = [];
    private readonly HashSet<Guid> _visibleChipIds = [];
    private readonly HashSet<string> _createdSourcePaths = new(StringComparer.OrdinalIgnoreCase);
    private readonly RectangleGeometry _shadeOuter = new();
    private readonly RectangleGeometry _shadeHole = new();
    private bool _closed;
    private Point? _selectionStart;
    private Rect _cropRect;
    private CaptureItem? _capture;
    private OverlaySnapshot? _lastSnapshot;
    private Color _activeColor = Color.FromRgb(47, 140, 255);
    private double _activeThickness = 4;
    private bool _settingUp;
    private bool _busyCrop;

    private OverlayEditorWindow(SessionWorkspace workspace, DesktopFrame frame, int captureIndex, CaptureItem? existing)
    {
        _workspace = workspace;
        _frame = frame;
        _captureIndex = captureIndex;
        _capture = existing?.DeepClone();
        _isNew = existing is null;
        InitializeComponent();
        InitializeCaptureHandles();
        DesktopImage.Source = frame.Image;
        var shadeGeometry = new GeometryGroup { FillRule = FillRule.EvenOdd };
        shadeGeometry.Children.Add(_shadeOuter);
        shadeGeometry.Children.Add(_shadeHole);
        Shade.Data = shadeGeometry;
        SourceInitialized += OnSourceInitialized;
        Loaded += OnLoaded;
        Closing += OnClosing;
    }

    public OverlayEditResult Result { get; private set; } = new(null, false, true);

    public static async Task<OverlayEditResult> CaptureNewAsync(SessionWorkspace workspace, int captureIndex)
    {
        await Task.Delay(120);
        var frame = CaptureOverlay.CaptureDesktopFrame(workspace.Preferences.CaptureCursor);
        var window = new OverlayEditorWindow(workspace, frame, captureIndex, null);
        _active = window;
        try { window.ShowDialog(); return window.Result; }
        finally { if (ReferenceEquals(_active, window)) _active = null; }
    }

    public static async Task<OverlayEditResult> EditExistingAsync(SessionWorkspace workspace, CaptureItem capture, int captureIndex)
    {
        await Task.Delay(120);
        var frame = CaptureOverlay.CaptureDesktopFrame(workspace.Preferences.CaptureCursor);
        var window = new OverlayEditorWindow(workspace, frame, captureIndex, capture);
        _active = window;
        try { window.ShowDialog(); return window.Result; }
        finally { if (ReferenceEquals(_active, window)) _active = null; }
    }

    public static bool TryCommitAndRequestNext()
    {
        var active = _active;
        if (active?._capture is null || active._busyCrop || active._captureResizeCorner >= 0 || active.Surface.IsMouseCaptured) return false;
        active.Dispatcher.BeginInvoke(() => active.Complete(true), DispatcherPriority.Input);
        return true;
    }

    internal static CaptureItem RunNoteAffordanceProbe(CaptureItem source)
    {
        var capture = source.DeepClone();
        capture.Annotations.Clear();
        var annotation = new AnnotationItem
        {
            Kind = EditorTool.Arrow,
            Points = [new Point(source.Image.PixelWidth * .2, source.Image.PixelHeight * .2), new Point(source.Image.PixelWidth * .55, source.Image.PixelHeight * .48)],
            Color = Color.FromRgb(47, 140, 255),
            Thickness = 4
        };
        capture.Annotations.Add(annotation);
        var workspace = new SessionWorkspace(Path.Combine(Path.GetTempPath(), "SnapBrief", $"note-probe-{Guid.NewGuid():N}"));
        var frame = new DesktopFrame(capture.Image, 0, 0, capture.Image.PixelWidth, capture.Image.PixelHeight);
        var window = new OverlayEditorWindow(workspace, frame, 0, capture) { Width = 1280, Height = 720 };
        window.Measure(new Size(1280, 720));
        window.Arrange(new Rect(0, 0, 1280, 720));
        window._cropRect = new Rect(120, 90, 900, 506);
        window.SetupEditor();
        var workingAnnotation = window._capture!.Annotations[0];
        window.Surface.SelectAnnotation(workingAnnotation.Id);
        window.UpdateContextNoteAffordance(workingAnnotation);
        window.Root.UpdateLayout();
        if (window.ContextNoteButton.Visibility != Visibility.Visible || !window.ContextNoteButton.IsHitTestVisible ||
            !double.IsFinite(Canvas.GetLeft(window.ContextNoteButton)) || !double.IsFinite(Canvas.GetTop(window.ContextNoteButton)))
            throw new InvalidOperationException("The contextual note affordance is not laid out as a visible hit target.");

        window.ContextNoteButton.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        var note = window.ChipLayer.Children.OfType<Border>()
            .Select(border => border.Child).OfType<Grid>()
            .SelectMany(grid => grid.Children.OfType<TextBox>()).Single();
        note.Text = "Контекстная заметка";
        if (workingAnnotation.Note != note.Text || window.ChipLayer.Children.Count != 1)
            throw new InvalidOperationException("The contextual note command did not bind the editor to its annotation.");
        _ = window.Surface.RenderAnnotated();
        var oldColor = workingAnnotation.Color;
        var oldThickness = workingAnnotation.Thickness;
        window._appearanceBefore = window.SnapshotState();
        window.ApplyAppearance(Colors.Red, 14);
        window.ApplyAppearance(null, 2);
        if (workingAnnotation.Color != Colors.Red || workingAnnotation.Thickness != 2)
            throw new InvalidOperationException("Appearance changes must update the selected annotation in both slider directions.");
        window.OnAppearanceClosed(window, EventArgs.Empty);
        window.OnUndoClick(window, new RoutedEventArgs());
        var restoredAnnotation = window._capture.Annotations.Single(a => a.Id == workingAnnotation.Id);
        if (restoredAnnotation.Color != oldColor || restoredAnnotation.Thickness != oldThickness)
            throw new InvalidOperationException("One undo must restore the appearance from before the property edit.");
        var result = window._capture.DeepClone();
        var textAnnotation = new AnnotationItem { Kind = EditorTool.Text, Points = [new Point(100, 100), new Point(220, 160)] };
        window._capture.Annotations.Add(textAnnotation);
        window.OnAnnotationCreated(window, textAnnotation);
        var textChip = window.ChipLayer.Children.OfType<Border>().Single(b => b.Tag is Guid id && id == textAnnotation.Id);
        var textInput = ((Grid)textChip.Child).Children.OfType<TextBox>().Single();
        textInput.Text = "Проверка текста";
        if (textAnnotation.Text != textInput.Text || !string.IsNullOrEmpty(textAnnotation.Note))
            throw new InvalidOperationException("Text tool input must update rendered text, not an annotation note.");
        return result;
    }

    private void OnSourceInitialized(object? sender, EventArgs e)
    {
        var handle = new WindowInteropHelper(this).Handle;
        SetWindowPos(handle, new IntPtr(-1), _frame.Left, _frame.Top, _frame.PixelWidth, _frame.PixelHeight, 0x0010 | 0x0040);
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        UpdateShade();
        UiLanguage.Apply(this, _workspace.Preferences.Language);
        Activate();
        Focus();
        if (_capture is null) { RestoreLastRegion(); return; }
        var maxWidth = ActualWidth * .72;
        var maxHeight = ActualHeight * .72;
        var scale = Math.Min(maxWidth / _capture.Image.PixelWidth, maxHeight / _capture.Image.PixelHeight);
        var width = _capture.Image.PixelWidth * scale;
        var height = _capture.Image.PixelHeight * scale;
        _cropRect = new Rect((ActualWidth - width) / 2, (ActualHeight - height) / 2, width, height);
        SetupEditor();
    }

    private void OnWindowMouseDown(object sender, MouseButtonEventArgs e)
    {
        if (_busyCrop || _closed || _capture is not null) return;
        if (!_isNew || _capture is not null || e.OriginalSource is not Image) return;
        _selectionStart = e.GetPosition(this);
        _cropRect = new Rect(_selectionStart.Value, _selectionStart.Value);
        CaptureMouse();
        UpdateCropVisual();
    }

    private void OnWindowMouseMove(object sender, MouseEventArgs e)
    {
        if (_selectionStart is null || e.LeftButton != MouseButtonState.Pressed) return;
        var point = e.GetPosition(this);
        _cropRect = Normalize(_selectionStart.Value, point);
        UpdateCropVisual();
    }

    private async void OnWindowMouseUp(object sender, MouseButtonEventArgs e)
    {
        if (_selectionStart is null)
        {
            if (_capture is not null && e.OriginalSource is Image && !_busyCrop && !_cropRect.Contains(e.GetPosition(this)))
            {
                e.Handled = true;
                Complete(false);
            }
            return;
        }
        _cropRect = Normalize(_selectionStart.Value, e.GetPosition(this));
        UpdateCropVisual();
        ReleaseMouseCapture();
        _selectionStart = null;
        if (_cropRect.Width < 12 || _cropRect.Height < 12) { _cropRect = Rect.Empty; UpdateCropVisual(); return; }
        try
        {
            _busyCrop = true;
            var scaleX = _frame.Image.PixelWidth / ActualWidth;
            var scaleY = _frame.Image.PixelHeight / ActualHeight;
            var rect = new Int32Rect(
                Math.Clamp((int)Math.Round(_cropRect.X * scaleX), 0, _frame.Image.PixelWidth - 1),
                Math.Clamp((int)Math.Round(_cropRect.Y * scaleY), 0, _frame.Image.PixelHeight - 1),
                Math.Max(1, (int)Math.Round(_cropRect.Width * scaleX)),
                Math.Max(1, (int)Math.Round(_cropRect.Height * scaleY)));
            if (rect.X + rect.Width > _frame.Image.PixelWidth) rect.Width = _frame.Image.PixelWidth - rect.X;
            if (rect.Y + rect.Height > _frame.Image.PixelHeight) rect.Height = _frame.Image.PixelHeight - rect.Y;
            var crop = new CroppedBitmap(_frame.Image, rect);
            crop.Freeze();
            _capture = await _workspace.AddImageAsync(crop);
            _createdSourcePaths.Add(_capture.SourcePath);
            if (_closed) { DeleteCreatedSourcesExcept(null); return; }
            _capture.DisplayLabel = CaptureLabels.ForIndex(_captureIndex);
            SetupEditor();
        }
        catch (Exception ex)
        {
            Hint.Visibility = Visibility.Visible;
            ((TextBlock)Hint.Child).Text = $"Не удалось сохранить снимок: {ex.Message}";
        }
        finally { _busyCrop = false; }
    }

    private void SetupEditor()
    {
        if (_capture is null) return;
        _settingUp = true;
        CropBorder.Visibility = Visibility.Visible;
        Canvas.SetLeft(CropBorder, _cropRect.Left);
        Canvas.SetTop(CropBorder, _cropRect.Top);
        CropBorder.Width = _cropRect.Width;
        CropBorder.Height = _cropRect.Height;
        Surface.Image = _capture.Image;
        Surface.Annotations = _capture.Annotations;
        Surface.Tool = EditorTool.Rectangle;
        SyncAppearance();
        Surface.ActiveColor = _activeColor;
        Surface.ActiveThickness = _activeThickness;
        Hint.Visibility = Visibility.Collapsed;
        Toolbar.Visibility = Visibility.Visible;
        ShotNoteChip.Visibility = Visibility.Collapsed;
        ShotNoteBox.Text = _capture.Note;
        ShotLabel.Text = $"СНИМОК {_capture.DisplayLabel}";
        UpdateCaptureHandles();
        PositionShotNote();
        foreach (var annotation in _capture.Annotations) annotation.PropertyChanged += OnAnnotationPropertyChanged;
        _lastSnapshot = SnapshotState();
        RefreshLabels();
        RebuildChips();
        UpdateContextNoteAffordance();
        UpdateShade();
        _settingUp = false;
        Dispatcher.BeginInvoke(() => { PositionToolbar(); PositionShotNote(); RepositionChips(); }, DispatcherPriority.Loaded);
    }

    private void UpdateCropVisual()
    {
        if (_cropRect.Width > 0)
        {
            CropBorder.Visibility = Visibility.Visible;
            Canvas.SetLeft(CropBorder, _cropRect.Left);
            Canvas.SetTop(CropBorder, _cropRect.Top);
            CropBorder.Width = _cropRect.Width;
            CropBorder.Height = _cropRect.Height;
        }
        else CropBorder.Visibility = Visibility.Collapsed;
        UpdateCaptureHandles();
        UpdateShade();
    }

    private void UpdateShade()
    {
        _shadeOuter.Rect = new Rect(0, 0, ActualWidth, ActualHeight);
        _shadeHole.Rect = _cropRect.Width > 0 && _cropRect.Height > 0 ? _cropRect : Rect.Empty;
    }

    private void OnToolClick(object sender, RoutedEventArgs e)
    {
        if (sender is not System.Windows.Controls.Primitives.ToggleButton selected || !Enum.TryParse<EditorTool>(selected.Tag?.ToString(), out var tool)) return;
        Surface.SelectAnnotation(null);
        Surface.Tool = tool;
        SyncAppearance();
        foreach (var button in new[] { SelectTool, RectangleTool, ArrowTool, PenTool, HighlightTool, TextTool, ConcealTool, BlurTool, CropTool })
            button.IsChecked = ReferenceEquals(button, selected);
    }

    private void OnColorClick(object sender, RoutedEventArgs e) => OpenAppearance();
    private void OnThicknessClick(object sender, RoutedEventArgs e) => OpenAppearance();

    private void OnMoreToolsClick(object sender, RoutedEventArgs e)
    {
        var menu = new ContextMenu
        {
            PlacementTarget = (UIElement)sender,
            Background = new SolidColorBrush(Color.FromArgb(248, 23, 26, 32)),
            Foreground = Brushes.White,
            BorderBrush = new SolidColorBrush(Color.FromRgb(58, 66, 78)),
            BorderThickness = new Thickness(1),
            Padding = new Thickness(5)
        };
        AddTool("Перо    P", EditorTool.Pen);
        AddTool("Маркер    H", EditorTool.Highlight);
        AddTool("Текст    T", EditorTool.Text);
        AddTool("Скрыть сплошным    X", EditorTool.Conceal);
        menu.IsOpen = true;

        void AddTool(string title, EditorTool tool) { var item = ActionItem(title, () => SelectToolMode(tool)); item.IsChecked = Surface.Tool == tool; menu.Items.Add(item); }
        static MenuItem ActionItem(string title, Action action)
        {
            var item = new MenuItem { Header = title, Foreground = Brushes.White, Background = Brushes.Transparent, Padding = new Thickness(10, 7, 10, 7) };
            item.Click += (_, _) => action();
            return item;
        }
    }

    private void SelectToolMode(EditorTool tool)
    {
        Surface.SelectAnnotation(null);
        Surface.Tool = tool;
        SyncAppearance();
        foreach (var button in new[] { SelectTool, RectangleTool, ArrowTool, PenTool, HighlightTool, TextTool, ConcealTool, BlurTool, CropTool })
            button.IsChecked = string.Equals(button.Tag?.ToString(), tool.ToString(), StringComparison.Ordinal);
        Surface.Focus();
    }

    private void OnAnnotationCreated(object sender, AnnotationItem annotation)
    {
        if (_capture is null) return;
        PushHistory();
        annotation.PropertyChanged += OnAnnotationPropertyChanged;
        RefreshLabels();
        if (annotation.Kind is EditorTool.Rectangle or EditorTool.Text)
        {
            _visibleChipIds.Add(annotation.Id);
            AddChip(annotation, focus: true);
            ContextNoteButton.Visibility = Visibility.Collapsed;
        }
        else UpdateContextNoteAffordance(annotation);
    }

    private void OnSelectionChanged(object sender, AnnotationItem? annotation)
    {
        SyncAppearance();
        if (Mouse.LeftButton == MouseButtonState.Pressed) return;
        RepositionChips();
        UpdateContextNoteAffordance(annotation);
    }

    private void OnAnnotationChanged(object sender, EventArgs e)
    {
        PushHistory();
        RefreshLabels();
        if (_capture is not null && ChipLayer.Children.Count != _capture.Annotations.Count) RebuildChips();
        else RepositionChips();
        UpdateContextNoteAffordance(Surface.SelectedAnnotation);
        SyncAppearance();
    }

    private void OnAnnotationPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(AnnotationItem.IsSelected)) return;
        RefreshLabels();
        if (_capture is not null)
        {
            _redo.Clear();
            _lastSnapshot = SnapshotState();
        }
        Surface.InvalidateVisual();
    }

    private void RebuildChips()
    {
        ChipLayer.Children.Clear();
        _chipLabels.Clear();
        if (_capture is null) return;
        _visibleChipIds.RemoveWhere(id => _capture.Annotations.All(annotation => annotation.Id != id));
        foreach (var annotation in _capture.Annotations.Where(annotation => _visibleChipIds.Contains(annotation.Id))) AddChip(annotation, false);
    }

    private void AddChip(AnnotationItem annotation, bool focus)
    {
        var badge = new TextBlock { Foreground = Brushes.White, FontSize = 11, FontWeight = FontWeights.Bold, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        _chipLabels[annotation.Id] = badge;
        var badgeHost = new Border { Width = 25, Height = 25, CornerRadius = new CornerRadius(13), Background = new SolidColorBrush(Color.FromRgb(47, 140, 255)), Child = badge, VerticalAlignment = VerticalAlignment.Center };
        var note = new TextBox
        {
            MinHeight = 32, MaxHeight = 78, Text = annotation.Kind == EditorTool.Text ? annotation.Text : annotation.Note, AcceptsReturn = true, TextWrapping = TextWrapping.Wrap,
            Background = Brushes.Transparent, Foreground = Brushes.White, BorderThickness = new Thickness(0), CaretBrush = Brushes.White,
            SelectionBrush = new SolidColorBrush(Color.FromRgb(47, 140, 255)), Padding = new Thickness(7, 5, 7, 5), Tag = annotation
        };
        note.TextChanged += (_, _) => { if (!_settingUp) { if (annotation.Kind == EditorTool.Text) annotation.Text = note.Text; else annotation.Note = note.Text; RefreshLabels(); } };
        note.GotKeyboardFocus += (_, _) => Surface.SelectAnnotation(annotation.Id);
        var closePath = new System.Windows.Shapes.Path
        {
            Stroke = new SolidColorBrush(Color.FromRgb(217, 222, 232)), StrokeThickness = 1.5,
            StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round,
            Data = Geometry.Parse("M1,1 L9,9 M9,1 L1,9")
        };
        var close = new Button
        {
            Width = 27, Height = 27, Padding = new Thickness(7), Background = Brushes.Transparent,
            BorderThickness = new Thickness(0), Content = closePath, ToolTip = annotation.Kind == EditorTool.Text ? "Закрыть ввод текста" : "Удалить комментарий", Tag = annotation
        };
        close.Click += OnDeleteAnnotationNoteClick;
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(31) });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(29) });
        grid.Children.Add(badgeHost);
        Grid.SetColumn(note, 1); grid.Children.Add(note);
        Grid.SetColumn(close, 2); grid.Children.Add(close);
        var border = new Border
        {
            Tag = annotation.Id, Width = 226, MinHeight = 40, Padding = new Thickness(6), CornerRadius = new CornerRadius(13),
            Background = new SolidColorBrush(Color.FromArgb(244, 23, 26, 32)), Child = grid,
            Effect = new System.Windows.Media.Effects.DropShadowEffect { Color = Colors.Black, BlurRadius = 14, ShadowDepth = 4, Opacity = .42 }
        };
        ChipLayer.Children.Add(border);
        PositionChip(border, annotation);
        RefreshLabels();
        PositionToolbar();
        if (focus) Dispatcher.BeginInvoke(() => { note.Focus(); note.SelectAll(); }, DispatcherPriority.Input);
    }

    private void RefreshLabels()
    {
        if (_capture is null) return;
        var labels = CaptureLabels.ForNotedAnnotations(_capture.DisplayLabel, _capture.ToCore()).ToDictionary(x => x.Annotation.Id, x => x.DisplayLabel);
        foreach (var annotation in _capture.Annotations)
        {
            annotation.Label = labels.GetValueOrDefault(annotation.Id) ?? string.Empty;
            if (_chipLabels.TryGetValue(annotation.Id, out var text))
            {
                var noteIndex = _capture.Annotations.TakeWhile(item => item.Id != annotation.Id).Count(item => !string.IsNullOrWhiteSpace(item.Note)) + 1;
                text.Text = string.IsNullOrEmpty(annotation.Label) ? $"{_capture.DisplayLabel}{noteIndex}" : annotation.Label;
            }
        }
        Surface.InvalidateVisual();
    }

    private void RepositionChips()
    {
        if (_capture is null) return;
        foreach (Border border in ChipLayer.Children)
            if (border.Tag is Guid id && _capture.Annotations.FirstOrDefault(a => a.Id == id) is { } annotation) PositionChip(border, annotation);
    }

    private void PositionChip(Border chip, AnnotationItem annotation)
    {
        var bounds = Surface.GetDisplayBounds(annotation);
        var work = GetCropMonitorWorkArea();
        var x = _cropRect.Left + bounds.Left;
        var y = _cropRect.Top + bounds.Bottom + 8;
        if (y + 86 > work.Bottom) y = _cropRect.Top + bounds.Top - 50;
        x = Math.Clamp(x, work.Left + 8, Math.Max(work.Left + 8, work.Right - 230));
        y = Math.Clamp(y, work.Top + 8, Math.Max(work.Top + 8, work.Bottom - 88));
        Canvas.SetLeft(chip, x);
        Canvas.SetTop(chip, y);
    }

    private void PositionShotNote()
    {
        var work = GetCropMonitorWorkArea();
        var left = Math.Clamp(_cropRect.Right - 250, work.Left + 8, Math.Max(work.Left + 8, work.Right - 258));
        var top = Math.Clamp(_cropRect.Top, work.Top + 8, Math.Max(work.Top + 8, work.Bottom - 132));
        ShotNoteChip.HorizontalAlignment = HorizontalAlignment.Left;
        ShotNoteChip.Margin = new Thickness(left, top, 0, 0);
    }

    private void PositionToolbar()
    {
        Toolbar.UpdateLayout();
        var work = GetCropMonitorWorkArea();
        var width = Math.Max(Toolbar.ActualWidth, 380);
        var height = Math.Max(Toolbar.ActualHeight, 50);
        var placement = PlaceToolbar(_cropRect, work, new Size(width, height), VisibleNoteRects().ToArray());
        Toolbar.Margin = new Thickness(placement.Left, placement.Top, 0, 0);

        IEnumerable<Rect> VisibleNoteRects()
        {
            foreach (Border chip in ChipLayer.Children)
            {
                var x = Canvas.GetLeft(chip); var y = Canvas.GetTop(chip);
                if (!double.IsNaN(x) && !double.IsNaN(y)) yield return new Rect(x, y, Math.Max(chip.ActualWidth, chip.Width), Math.Max(chip.ActualHeight, 40));
            }
            if (ShotNoteChip.Visibility == Visibility.Visible)
                yield return new Rect(ShotNoteChip.Margin.Left, ShotNoteChip.Margin.Top, ShotNoteChip.Width, Math.Max(ShotNoteChip.ActualHeight, 60));
        }
    }

    private void OnCommentClick(object sender, RoutedEventArgs e)
    {
        if (_capture is null) return;
        if (Surface.SelectedAnnotation is { } annotation)
        {
            _visibleChipIds.Add(annotation.Id);
            if (ChipLayer.Children.OfType<Border>().FirstOrDefault(border => border.Tag is Guid id && id == annotation.Id) is null)
                AddChip(annotation, focus: true);
            else if (ChipLayer.Children.OfType<Border>().First(border => border.Tag is Guid id && id == annotation.Id).Child is Grid grid)
                grid.Children.OfType<TextBox>().FirstOrDefault()?.Focus();
            ContextNoteButton.Visibility = Visibility.Collapsed;
            return;
        }
        ShotNoteChip.Visibility = Visibility.Visible;
        PositionShotNote();
        PositionToolbar();
        ShotNoteBox.Focus();
        ContextNoteButton.Visibility = Visibility.Collapsed;
    }

    private void UpdateContextNoteAffordance(AnnotationItem? annotation = null)
    {
        if (_capture is null) { ContextNoteButton.Visibility = Visibility.Collapsed; return; }
        annotation ??= Surface.SelectedAnnotation;
        if (annotation is not null && _visibleChipIds.Contains(annotation.Id))
        {
            ContextNoteButton.Visibility = Visibility.Collapsed;
            return;
        }

        var work = GetCropMonitorWorkArea();
        double x;
        double y;
        if (annotation is not null)
        {
            var bounds = Surface.GetDisplayBounds(annotation);
            x = _cropRect.Left + bounds.Right + 8;
            y = _cropRect.Top + bounds.Top - 4;
            if (x + 36 > work.Right) x = _cropRect.Left + bounds.Left - 40;
        }
        else
        {
            x = _cropRect.Right - 40;
            y = _cropRect.Top + 8;
        }
        x = Math.Clamp(x, work.Left + 8, Math.Max(work.Left + 8, work.Right - 40));
        y = Math.Clamp(y, work.Top + 8, Math.Max(work.Top + 8, work.Bottom - 40));
        Canvas.SetLeft(ContextNoteButton, x);
        Canvas.SetTop(ContextNoteButton, y);
        ContextNoteButton.Visibility = Visibility.Visible;
    }

    private void OnDeleteAnnotationNoteClick(object sender, RoutedEventArgs e)
    {
        if (_capture is null || sender is not Button { Tag: AnnotationItem annotation }) return;
        if (!string.IsNullOrEmpty(annotation.Note)) _undo.Push(SnapshotState());
        _redo.Clear();
        if (annotation.Kind != EditorTool.Text) annotation.Note = string.Empty;
        _lastSnapshot = SnapshotState();
        _visibleChipIds.Remove(annotation.Id);
        if (ChipLayer.Children.OfType<Border>().FirstOrDefault(border => border.Tag is Guid id && id == annotation.Id) is { } chip)
            ChipLayer.Children.Remove(chip);
        RefreshLabels();
        PositionToolbar();
        UpdateContextNoteAffordance(annotation);
        e.Handled = true;
    }

    private void OnCloseShotNoteClick(object sender, RoutedEventArgs e)
    {
        if (_capture is null) return;
        if (!string.IsNullOrEmpty(_capture.Note)) _undo.Push(SnapshotState());
        _redo.Clear();
        _settingUp = true;
        ShotNoteBox.Clear();
        _capture.Note = string.Empty;
        _settingUp = false;
        _lastSnapshot = SnapshotState();
        ShotNoteChip.Visibility = Visibility.Collapsed;
        PositionToolbar();
        UpdateContextNoteAffordance();
        Surface.Focus();
        e.Handled = true;
    }

    private Rect GetCropMonitorWorkArea()
    {
        var scaleToPixelX = _frame.PixelWidth / Math.Max(1, ActualWidth);
        var scaleToPixelY = _frame.PixelHeight / Math.Max(1, ActualHeight);
        var centerPixel = new System.Drawing.Point(
            _frame.Left + (int)Math.Round((_cropRect.Left + _cropRect.Width / 2) * scaleToPixelX),
            _frame.Top + (int)Math.Round((_cropRect.Top + _cropRect.Height / 2) * scaleToPixelY));
        var area = WinForms.Screen.FromPoint(centerPixel).WorkingArea;
        return new Rect(
            (area.Left - _frame.Left) / scaleToPixelX,
            (area.Top - _frame.Top) / scaleToPixelY,
            area.Width / scaleToPixelX,
            area.Height / scaleToPixelY);
    }

    private void OnShotNoteChanged(object sender, TextChangedEventArgs e)
    {
        if (_settingUp || _capture is null) return;
        _capture.Note = ShotNoteBox.Text;
        _redo.Clear();
        _lastSnapshot = SnapshotState();
        SyncAppearance();
    }

    private void PushHistory()
    {
        if (_capture is null || _lastSnapshot is null) return;
        _undo.Push(_lastSnapshot);
        _redo.Clear();
        _lastSnapshot = SnapshotState();
        SyncAppearance();
    }

    private void OnUndoClick(object sender, RoutedEventArgs e)
    {
        if (_busyCrop || _captureResizeCorner >= 0 || _capture is null || _undo.Count == 0) return;
        _redo.Push(SnapshotState());
        RestoreState(_undo.Pop());
    }

    private void OnRedoClick(object sender, RoutedEventArgs e)
    {
        if (_busyCrop || _captureResizeCorner >= 0 || _capture is null || _redo.Count == 0) return;
        _undo.Push(SnapshotState());
        RestoreState(_redo.Pop());
    }

    private OverlaySnapshot SnapshotState() => new(_capture!.Snapshot(), _cropRect, new HashSet<Guid>(_visibleChipIds), ShotNoteChip.Visibility == Visibility.Visible);

    private void RestoreState(OverlaySnapshot state)
    {
        if (_capture is null) return;
        _capture.Restore(state.Capture);
        _cropRect = state.CropRect;
        _visibleChipIds.Clear();
        _visibleChipIds.UnionWith(state.VisibleChipIds);
        foreach (var annotation in _capture.Annotations) annotation.PropertyChanged += OnAnnotationPropertyChanged;
        Surface.Image = _capture.Image;
        Surface.Annotations = _capture.Annotations;
        _settingUp = true;
        ShotNoteBox.Text = _capture.Note;
        ShotNoteChip.Visibility = state.ShotNoteVisible ? Visibility.Visible : Visibility.Collapsed;
        _settingUp = false;
        _lastSnapshot = SnapshotState();
        UpdateCropVisual();
        RebuildChips();
        UpdateContextNoteAffordance(Surface.SelectedAnnotation);
        SyncAppearance();
        PositionToolbar();
        PositionShotNote();
        Surface.InvalidateVisual();
    }

    private async void OnCropRequested(Rect pixelBounds)
    {
        if (_capture is null || _busyCrop || _captureResizeCorner >= 0 || Surface.IsMouseCaptured) return;
        var width = _capture.Image.PixelWidth;
        var height = _capture.Image.PixelHeight;
        var left = Math.Clamp((int)Math.Floor(pixelBounds.Left), 0, width - 1);
        var top = Math.Clamp((int)Math.Floor(pixelBounds.Top), 0, height - 1);
        var right = Math.Clamp((int)Math.Ceiling(pixelBounds.Right), left + 1, width);
        var bottom = Math.Clamp((int)Math.Ceiling(pixelBounds.Bottom), top + 1, height);
        if (right - left < 8 || bottom - top < 8) return;

        _busyCrop = true;
        try
        {
            var before = SnapshotState();
            var pixelRect = new Int32Rect(left, top, right - left, bottom - top);
            var bitmap = new CroppedBitmap(_capture.Image, pixelRect);
            bitmap.Freeze();
            var relativePath = await _workspace.SaveDerivedImageAsync(bitmap);
            _createdSourcePaths.Add(relativePath);
            var normalized = new NormalizedRect((double)left / width, (double)top / height, (double)pixelRect.Width / width, (double)pixelRect.Height / height);
            var result = CaptureCropper.Crop(_capture.ToCore(), normalized, relativePath, pixelRect.Width, pixelRect.Height);
            var cropped = CaptureItem.FromCore(result.CroppedCapture, bitmap);
            cropped.DisplayLabel = _capture.DisplayLabel;
            cropped.IsSelected = _capture.IsSelected;

            var oldRect = _cropRect;
            _cropRect = new Rect(
                oldRect.Left + oldRect.Width * left / width,
                oldRect.Top + oldRect.Height * top / height,
                oldRect.Width * pixelRect.Width / width,
                oldRect.Height * pixelRect.Height / height);
            _capture = cropped;
            _undo.Push(before);
            _redo.Clear();
            SetupEditor();
            Surface.Tool = EditorTool.Select;
            SelectTool.IsChecked = true;
            CropTool.IsChecked = false;
        }
        catch (Exception ex)
        {
            Hint.Visibility = Visibility.Visible;
            ((TextBlock)Hint.Child).Text = $"Не удалось обрезать снимок: {ex.Message}";
        }
        finally { _busyCrop = false; }
    }

    private void OnDoneClick(object sender, RoutedEventArgs e) => Complete(false);
    private void OnAddNextClick(object sender, RoutedEventArgs e) => Complete(true);

    private void Complete(bool addNext)
    {
        if (_capture is null || _busyCrop || _captureResizeCorner >= 0 || Surface.IsMouseCaptured) return;
        RememberCurrentRegion();
        _capture.Note = ShotNoteBox.Text;
        DeleteCreatedSourcesExcept(_capture.SourcePath);
        Result = new OverlayEditResult(_capture, addNext, false);
        DialogResult = true;
    }

    private void OnWindowKeyDown(object sender, KeyEventArgs e)
    {
        if (Keyboard.Modifiers == ModifierKeys.Control && e.Key == Key.S) { e.Handled = true; OnSaveImageClick(this, e); return; }
        if (Keyboard.FocusedElement is TextBox)
        {
            if (e.Key == Key.Escape) { Surface.Focus(); e.Handled = true; }
            return;
        }
        if (e.Key == Key.Escape)
        {
            CancelEdit();
            Result = new OverlayEditResult(_isNew ? null : _capture, false, true);
            DialogResult = false;
        }
        else if (Keyboard.Modifiers == ModifierKeys.Control && e.Key == Key.S) { e.Handled = true; OnSaveImageClick(this, e); }
        else if (Keyboard.Modifiers == ModifierKeys.Control && e.Key == Key.Z) { OnUndoClick(this, e); e.Handled = true; }
        else if (Keyboard.Modifiers == ModifierKeys.Control && e.Key == Key.Y) { OnRedoClick(this, e); e.Handled = true; }
        else if (Keyboard.Modifiers == ModifierKeys.Control && e.Key == Key.C && _capture is not null) { e.Handled = true; Complete(false); }
        else if (Keyboard.Modifiers == ModifierKeys.None)
        {
            var tool = e.Key switch
            {
                Key.V => EditorTool.Select,
                Key.R => EditorTool.Rectangle,
                Key.A => EditorTool.Arrow,
                Key.B => EditorTool.Blur,
                Key.C => EditorTool.Crop,
                Key.P => EditorTool.Pen,
                Key.H => EditorTool.Highlight,
                Key.T => EditorTool.Text,
                Key.X => EditorTool.Conceal,
                _ => (EditorTool?)null
            };
            if (tool is not null) { SelectToolMode(tool.Value); e.Handled = true; }
        }
    }

    private static Rect Normalize(Point a, Point b) => new(new Point(Math.Min(a.X, b.X), Math.Min(a.Y, b.Y)), new Point(Math.Max(a.X, b.X), Math.Max(a.Y, b.Y)));

    private void OnClosing(object? sender, CancelEventArgs e)
    {
        _closed = true;
        if (Result.Cancelled) CancelEdit();
    }

    private void CancelEdit()
    {
        if (_capture is null) return;
        DeleteCreatedSourcesExcept(null);
    }

    private void DeleteCreatedSourcesExcept(string? keepRelativePath)
    {
        var root = Path.GetFullPath(_workspace.SessionDirectory) + Path.DirectorySeparatorChar;
        foreach (var relativePath in _createdSourcePaths)
        {
            if (string.Equals(relativePath, keepRelativePath, StringComparison.OrdinalIgnoreCase)) continue;
            var source = Path.GetFullPath(Path.Combine(_workspace.SessionDirectory, relativePath));
            if (source.StartsWith(root, StringComparison.OrdinalIgnoreCase) && File.Exists(source)) File.Delete(source);
        }
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetWindowPos(IntPtr hwnd, IntPtr insertAfter, int x, int y, int cx, int cy, uint flags);

    private sealed record OverlaySnapshot(CaptureSnapshot Capture, Rect CropRect, IReadOnlySet<Guid> VisibleChipIds, bool ShotNoteVisible);
}










