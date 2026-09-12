using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Markup;
using System.Windows.Threading;
using SnapBrief.App.Controls;
using WinForms = System.Windows.Forms;

namespace SnapBrief.App;

public partial class CapturePreviewWindow : Window
{
    private readonly CaptureItem _capture;
    private readonly Func<Task> _persist;
    private readonly TaskCompletionSource<bool> _completion = new(TaskCreationOptions.RunContinuationsAsynchronously);
    private readonly DispatcherTimer _saveTimer = new() { Interval = TimeSpan.FromMilliseconds(360) };
    private Task _persistChain = Task.CompletedTask;
    private bool _fitToWindow = true;
    private bool _canAutoClose;
    private bool _closing;
    private bool _closed;
    private double _zoom = 1;

    public CapturePreviewWindow(CaptureItem capture, Func<Task> persist)
    {
        _capture = capture;
        _persist = persist;
        InitializeComponent();
        DataContext = this;
        _saveTimer.Tick += OnSaveTimerTick;
        Loaded += OnLoaded;
        SourceInitialized += OnSourceInitialized;
        Deactivated += OnDeactivated;
        Closed += OnClosed;
        PreviewKeyDown += OnPreviewKeyDown;
        SizeChanged += OnWindowSizeChanged;
    }

    public ObservableCollection<CommentEntry> Comments { get; } = [];

    public Task<bool> ShowForAsync(Window owner)
    {
        Owner = owner;
        Show();
        Activate();
        return _completion.Task;
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        CaptureLabel.Text = _capture.DisplayLabel;
        ImageSizeText.Text = $"{_capture.Image.PixelWidth} × {_capture.Image.PixelHeight}";
        PreviewImage.Source = RenderPreview();
        PreviewImage.Width = _capture.Image.PixelWidth;
        PreviewImage.Height = _capture.Image.PixelHeight;
        RebuildComments();
        UiLanguage.Apply(this);
        Dispatcher.BeginInvoke(() =>
        {
            UpdateFitZoom();
            Activate();
            Focus();
            _canAutoClose = true;
        }, DispatcherPriority.ApplicationIdle);
    }

    private ImageSource RenderPreview()
    {
        var annotations = new ObservableCollection<AnnotationItem>(_capture.Annotations.Select(item => item.Clone()));
        var labels = SnapBrief.Core.Exporting.CaptureLabels.ForNotedAnnotations(_capture.DisplayLabel, _capture.ToCore())
            .ToDictionary(item => item.Annotation.Id, item => item.DisplayLabel);
        foreach (var annotation in annotations) annotation.Label = labels.GetValueOrDefault(annotation.Id) ?? string.Empty;
        var canvas = new AnnotationCanvas { Image = _capture.Image, Annotations = annotations, ImagePadding = 0 };
        return canvas.RenderAnnotated();
    }

    private void OnSourceInitialized(object? sender, EventArgs e)
    {
        var ownerHandle = Owner is null ? IntPtr.Zero : new WindowInteropHelper(Owner).Handle;
        var area = WinForms.Screen.FromHandle(ownerHandle).WorkingArea;
        var dpi = VisualTreeHelper.GetDpi(this);
        var bounds = CalculatePreviewBounds(new Rect(area.Left, area.Top, area.Width, area.Height), dpi.DpiScaleX, dpi.DpiScaleY, out var minimumDipSize);
        MinWidth = minimumDipSize.Width;
        MinHeight = minimumDipSize.Height;
        _ = SetWindowPos(new WindowInteropHelper(this).Handle, IntPtr.Zero,
            (int)Math.Round(bounds.Left), (int)Math.Round(bounds.Top), (int)Math.Round(bounds.Width), (int)Math.Round(bounds.Height), 0x0004 | 0x0010);
    }

    internal static Rect CalculatePreviewBounds(Rect workAreaPixels, double dpiScaleX, double dpiScaleY, out Size minimumDipSize)
    {
        dpiScaleX = Math.Max(.1, dpiScaleX);
        dpiScaleY = Math.Max(.1, dpiScaleY);
        var availableWidth = Math.Max(1, (workAreaPixels.Width - 32) / dpiScaleX);
        var availableHeight = Math.Max(1, (workAreaPixels.Height - 32) / dpiScaleY);
        minimumDipSize = new Size(Math.Min(720, availableWidth), Math.Min(500, availableHeight));
        var width = Math.Min(1100, availableWidth) * dpiScaleX;
        var height = Math.Min(760, availableHeight) * dpiScaleY;
        return new Rect(
            workAreaPixels.Left + (workAreaPixels.Width - width) / 2,
            workAreaPixels.Top + (workAreaPixels.Height - height) / 2,
            width,
            height);
    }

    private void RebuildComments()
    {
        Comments.Clear();
        if (!string.IsNullOrWhiteSpace(_capture.Note))
            Comments.Add(CommentEntry.ForCapture(_capture, UiLanguage.Text("Комментарий к снимку"), QueuePersist));

        foreach (var annotation in _capture.Annotations.Where(item => item.Kind == EditorTool.Comment || !string.IsNullOrWhiteSpace(item.Note)))
        {
            var relation = annotation.ParentAnnotationId is { } parentId
                ? UiLanguage.Text("К отметке") + " " + AnnotationName(parentId)
                : UiLanguage.Text("К снимку") + " " + _capture.DisplayLabel;
            Comments.Add(CommentEntry.ForAnnotation(annotation, "+", relation, QueuePersist));
        }

        RefreshCommentLabels();
        EmptyCommentsText.Visibility = Comments.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    private void RefreshCommentLabels()
    {
        var labels = SnapBrief.Core.Exporting.CaptureLabels.ForNotedAnnotations(_capture.DisplayLabel, _capture.ToCore())
            .ToDictionary(item => item.Annotation.Id, item => item.DisplayLabel);
        foreach (var entry in Comments)
            entry.Label = entry.Annotation is null ? _capture.DisplayLabel : labels.GetValueOrDefault(entry.Annotation.Id) ?? "+";
    }

    private string AnnotationName(Guid id)
    {
        var annotation = _capture.Annotations.FirstOrDefault(item => item.Id == id);
        if (annotation is null) return "";
        if (!string.IsNullOrWhiteSpace(annotation.Label)) return annotation.Label;
        var index = _capture.Annotations.Where(item => item.Kind != EditorTool.Comment).TakeWhile(item => item.Id != id).Count() + 1;
        return $"{_capture.DisplayLabel}·{index}";
    }

    private void OnAddCommentClick(object sender, RoutedEventArgs e)
    {
        var center = new Point(_capture.Image.PixelWidth / 2d, _capture.Image.PixelHeight / 2d);
        var comment = new AnnotationItem
        {
            Kind = EditorTool.Comment,
            Points = [center, new Point(center.X + 8, center.Y + 8)],
            Note = string.Empty
        };
        _capture.Annotations.Add(comment);
        RebuildComments();
        QueuePersist();
        Dispatcher.BeginInvoke(() =>
        {
            if (Comments.LastOrDefault() is not { } last) return;
            CommentList.ScrollIntoView(last);
            CommentList.UpdateLayout();
            if (CommentList.ItemContainerGenerator.ContainerFromItem(last) is not DependencyObject container) return;
            if (FindVisualChild<TextBox>(container) is { } editor) { editor.Focus(); editor.CaretIndex = editor.Text.Length; }
        }, DispatcherPriority.Input);
    }

    private void OnDeleteCommentClick(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: CommentEntry entry }) return;
        DeleteComment(entry);
        e.Handled = true;
    }

    private void DeleteComment(CommentEntry entry)
    {
        if (entry.Annotation is { Kind: EditorTool.Comment } comment) _capture.Annotations.Remove(comment);
        else if (entry.Annotation is { } annotation) annotation.Note = string.Empty;
        else _capture.Note = string.Empty;
        RebuildComments();
        PreviewImage.Source = RenderPreview();
        QueuePersist();
    }

    private void QueuePersist()
    {
        RefreshCommentLabels();
        _saveTimer.Stop();
        _saveTimer.Start();
    }

    private void OnSaveTimerTick(object? sender, EventArgs e)
    {
        _saveTimer.Stop();
        PreviewImage.Source = RenderPreview();
        _persistChain = PersistAfterAsync(_persistChain);
    }

    private async Task PersistAfterAsync(Task previous)
    {
        try { await previous; }
        catch { }
        await _persist();
    }

    private async Task FlushEditsAsync()
    {
        var pending = _saveTimer.IsEnabled;
        _saveTimer.Stop();
        try { await _persistChain; }
        catch { }
        if (pending) await _persist();
    }

    private void OnZoomOutClick(object sender, RoutedEventArgs e) => SetZoom(_zoom / 1.2);
    private void OnZoomInClick(object sender, RoutedEventArgs e) => SetZoom(_zoom * 1.2);
    private void OnActualSizeClick(object sender, RoutedEventArgs e) => SetZoom(1);

    private void OnFitClick(object sender, RoutedEventArgs e)
    {
        _fitToWindow = true;
        UpdateFitZoom();
    }

    private void SetZoom(double value)
    {
        _fitToWindow = false;
        _zoom = Math.Clamp(value, .1, 4);
        ApplyZoom();
    }

    private void UpdateFitZoom()
    {
        if (!_fitToWindow || _capture.Image.PixelWidth <= 0 || _capture.Image.PixelHeight <= 0) return;
        var width = ImageScroller.ViewportWidth;
        var height = ImageScroller.ViewportHeight;
        if (!double.IsFinite(width) || !double.IsFinite(height) || width <= 8 || height <= 8) return;
        _zoom = Math.Clamp(Math.Min((width - 8) / _capture.Image.PixelWidth, (height - 8) / _capture.Image.PixelHeight), .05, 4);
        ApplyZoom();
    }

    private void ApplyZoom()
    {
        ImageScale.ScaleX = ImageScale.ScaleY = _zoom;
        ZoomText.Text = $"{_zoom:P0}";
        FitButton.BorderBrush = _fitToWindow ? new SolidColorBrush(Color.FromRgb(122, 184, 255)) : new SolidColorBrush(Color.FromRgb(58, 68, 81));
    }

    private void OnImageViewportSizeChanged(object sender, SizeChangedEventArgs e) => UpdateFitZoom();
    private void OnWindowSizeChanged(object sender, SizeChangedEventArgs e) => WindowShell.CornerRadius = WindowState == WindowState.Maximized ? new CornerRadius(0) : new CornerRadius(12);

    private void OnImageMouseWheel(object sender, MouseWheelEventArgs e)
    {
        if ((Keyboard.Modifiers & ModifierKeys.Control) == 0) return;
        SetZoom(e.Delta > 0 ? _zoom * 1.12 : _zoom / 1.12);
        e.Handled = true;
    }

    private void OnFullscreenClick(object sender, RoutedEventArgs e)
    {
        WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;
        FullscreenButton.ToolTip = UiLanguage.Text(WindowState == WindowState.Maximized ? "Вернуть размер" : "На весь экран");
        Dispatcher.BeginInvoke(UpdateFitZoom, DispatcherPriority.Loaded);
    }

    private void OnPreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Escape) { ClosePreview(); e.Handled = true; return; }
        if (e.Key == Key.F11) { OnFullscreenClick(this, new RoutedEventArgs()); e.Handled = true; return; }
        if ((Keyboard.Modifiers & ModifierKeys.Control) == 0) return;
        if (e.Key is Key.D0 or Key.NumPad0) { OnFitClick(this, new RoutedEventArgs()); e.Handled = true; }
        else if (e.Key is Key.D1 or Key.NumPad1) { OnActualSizeClick(this, new RoutedEventArgs()); e.Handled = true; }
        else if (e.Key is Key.Add or Key.OemPlus) { OnZoomInClick(this, new RoutedEventArgs()); e.Handled = true; }
        else if (e.Key is Key.Subtract or Key.OemMinus) { OnZoomOutClick(this, new RoutedEventArgs()); e.Handled = true; }
    }

    private void OnMarkupClick(object sender, RoutedEventArgs e)
    {
        MarkupRequested = true;
        ClosePreview();
    }

    private void OnCloseClick(object sender, RoutedEventArgs e) => ClosePreview();

    private void OnDeactivated(object? sender, EventArgs e)
    {
        if (_canAutoClose && !_closing && !_closed) ClosePreview();
    }

    private void ClosePreview()
    {
        if (_closing || _closed) return;
        _closing = true;
        Close();
    }

    private async void OnClosed(object? sender, EventArgs e)
    {
        if (_closed) return;
        _closed = true;
        try
        {
            await FlushEditsAsync();
            _completion.TrySetResult(MarkupRequested);
        }
        catch (Exception ex) { _completion.TrySetException(ex); }
    }

    private bool MarkupRequested { get; set; }

    internal static CapturePreviewWindow RunPreviewProbe(CaptureItem source)
    {
        var capture = new CaptureItem
        {
            Id = source.Id,
            Image = source.Image,
            SourcePath = source.SourcePath,
            DisplayLabel = source.DisplayLabel
        };
        var marked = new AnnotationItem
        {
            Kind = EditorTool.Rectangle,
            Points = [new Point(10, 10), new Point(80, 80)],
            Note = "Первый"
        };
        var blank = new AnnotationItem
        {
            Kind = EditorTool.Comment,
            Points = [new Point(40, 40), new Point(48, 48)]
        };
        capture.Annotations.Add(marked);
        capture.Annotations.Add(blank);

        var window = new CapturePreviewWindow(capture, () => Task.CompletedTask);
        window.RebuildComments();
        var blankEntry = window.Comments.Single(item => item.Annotation?.Id == blank.Id);
        if (blankEntry.Label != "+") throw new InvalidOperationException("An empty preview comment must not claim an export label.");
        blankEntry.Text = "Второй";
        var expectedSecond = SnapBrief.Core.Exporting.CaptureLabels.ForNotedAnnotations(capture.DisplayLabel, capture.ToCore()).Last().DisplayLabel;
        if (blankEntry.Label != expectedSecond) throw new InvalidOperationException("Preview and export comment labels must match.");

        var markedEntry = window.Comments.Single(item => item.Annotation?.Id == marked.Id);
        window.DeleteComment(markedEntry);
        var expectedFirst = SnapBrief.Core.Exporting.CaptureLabels.ForNotedAnnotations(capture.DisplayLabel, capture.ToCore()).Single().DisplayLabel;
        if (window.Comments.Single().Label != expectedFirst) throw new InvalidOperationException("Comment labels must close the gap after deletion.");

        for (var i = 0; i < 299; i++)
            capture.Annotations.Add(new AnnotationItem
            {
                Kind = EditorTool.Comment,
                Points = [new Point(50, 50), new Point(58, 58)],
                Note = $"Комментарий {i + 2}"
            });
        window.RebuildComments();
        if (window.Comments.Count != 300) throw new InvalidOperationException("The preview comment list truncated a large capture.");

        var workArea = new Rect(-1920, 0, 1920, 1080);
        var bounds = CalculatePreviewBounds(workArea, 1.5, 1.5, out _);
        if (bounds.Left < workArea.Left || bounds.Top < workArea.Top || bounds.Right > workArea.Right || bounds.Bottom > workArea.Bottom)
            throw new InvalidOperationException("Preview bounds escaped the stack monitor working area.");
        window._saveTimer.Stop();
        return window;
    }

    private static T? FindVisualChild<T>(DependencyObject parent) where T : DependencyObject
    {
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(parent); i++)
        {
            var child = VisualTreeHelper.GetChild(parent, i);
            if (child is T match) return match;
            if (FindVisualChild<T>(child) is { } descendant) return descendant;
        }
        return null;
    }

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWindowPos(IntPtr hwnd, IntPtr insertAfter, int x, int y, int width, int height, uint flags);

    public sealed class CommentEntry : INotifyPropertyChanged
    {
        private readonly CaptureItem? _capture;
        private readonly Action _changed;

        private CommentEntry(CaptureItem? capture, AnnotationItem? annotation, string label, string relation, Action changed)
        {
            _capture = capture;
            Annotation = annotation;
            Label = label;
            Relation = relation;
            _changed = changed;
        }

        public AnnotationItem? Annotation { get; }
        private string _label = string.Empty;
        public string Label
        {
            get => _label;
            set { if (_label == value) return; _label = value; PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(Label))); }
        }
        public string Relation { get; }
        public string Text
        {
            get => Annotation?.Note ?? _capture?.Note ?? string.Empty;
            set
            {
                if (Text == value) return;
                if (Annotation is not null) Annotation.Note = value;
                else if (_capture is not null) _capture.Note = value;
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(Text)));
                _changed();
            }
        }

        public static CommentEntry ForCapture(CaptureItem capture, string relation, Action changed) => new(capture, null, capture.DisplayLabel, relation, changed);
        public static CommentEntry ForAnnotation(AnnotationItem annotation, string label, string relation, Action changed) => new(null, annotation, label, relation, changed);

        public event PropertyChangedEventHandler? PropertyChanged;
    }
}

[MarkupExtensionReturnType(typeof(string))]
public sealed class UiTextExtension(string key) : MarkupExtension
{
    public override object ProvideValue(IServiceProvider serviceProvider) => UiLanguage.Text(key);
}
