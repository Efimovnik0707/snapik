using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;

namespace SnapBrief.App;

public partial class OverlayEditorWindow
{
    // A caption is typed on the capture itself, in a text box standing exactly where the letters
    // will be drawn and in the size they will be drawn in. It used to be typed inside the pill of a
    // comment, which closed on the first click anywhere and never came back.
    private readonly TextBox _textEditor = new();
    private AnnotationItem? _editingText;
    private string _editingTextBefore = string.Empty;
    private bool _editingTextIsNew;
    private int _editingUndoDepth;
    private bool _closingTextEdit;

    internal bool IsEditingText => _editingText is not null;

    private void InitializeTextEditor()
    {
        _textEditor.Background = Brushes.Transparent;
        _textEditor.BorderThickness = new Thickness(0);
        _textEditor.Padding = new Thickness(0);
        _textEditor.CaretBrush = Brushes.White;
        _textEditor.SelectionBrush = new SolidColorBrush(Color.FromRgb(47, 140, 255));
        _textEditor.AcceptsReturn = true;
        _textEditor.TextWrapping = TextWrapping.NoWrap;
        _textEditor.FontFamily = new FontFamily(TextMarkMetrics.FamilyName);
        _textEditor.MinWidth = 24;
        _textEditor.Visibility = Visibility.Collapsed;
        _textEditor.TextChanged += OnTextEditorChanged;
        _textEditor.PreviewKeyDown += OnTextEditorKeyDown;
        _textEditor.LostKeyboardFocus += (_, _) =>
            Dispatcher.BeginInvoke(() => { if (_editingText is not null && !_textEditor.IsKeyboardFocusWithin) CommitTextEdit(); }, DispatcherPriority.Input);
        TextLayer.Children.Add(_textEditor);
    }

    // The word the caption starts with is selected whole: typing replaces it, a click inside it does
    // not. That is how a caption is placed in Paint and in the markup of macOS.
    internal void BeginTextEdit(AnnotationItem annotation, bool selectAll, bool isNew)
    {
        if (_capture is null || annotation.Kind != EditorTool.Text) return;
        if (_editingText is not null && !ReferenceEquals(_editingText, annotation)) CommitTextEdit();
        _editingText = annotation;
        _editingTextBefore = annotation.Text;
        _editingTextIsNew = isNew;
        _editingUndoDepth = _undo.Count;
        Surface.EditingTextId = annotation.Id;
        Surface.SelectAnnotation(annotation.Id);
        _settingUp = true;
        _textEditor.Text = annotation.Text;
        _settingUp = false;
        _textEditor.Visibility = Visibility.Visible;
        ResizeTextEditor();
        // The selection is set here and not in the callback below: a window that is being driven
        // without a pointer has no focus to wait for, and the selection is what the checks read.
        if (selectAll) _textEditor.SelectAll();
        else _textEditor.CaretIndex = _textEditor.Text.Length;
        Surface.InvalidateVisual();
        Dispatcher.BeginInvoke(() => { if (_editingText is not null) _textEditor.Focus(); }, DispatcherPriority.Input);
    }

    // Where the text box stands and how big its letters are: the capture is shown scaled, so both
    // follow the crop rectangle. Called whenever the text, the size or the layout changes.
    private void ResizeTextEditor()
    {
        if (_editingText is not { } annotation || _capture is null || _cropRect.Width <= 0) return;
        var scale = _cropRect.Width / _capture.Image.PixelWidth;
        _textEditor.FontSize = Math.Max(1, TextMarkMetrics.Clamp(annotation.FontSize) * scale);
        _textEditor.Foreground = new SolidColorBrush(annotation.Color);
        Canvas.SetLeft(_textEditor, _cropRect.Left + annotation.Points[0].X * scale);
        Canvas.SetTop(_textEditor, _cropRect.Top + annotation.Points[0].Y * scale);
    }

    private void OnTextEditorChanged(object sender, TextChangedEventArgs e)
    {
        if (_settingUp || _editingText is not { } annotation) return;
        annotation.Text = _textEditor.Text;
        TextMarkMetrics.Fit(annotation);
        Surface.InvalidateVisual();
    }

    private void OnTextEditorKeyDown(object sender, KeyEventArgs e)
    {
        // Enter finishes the caption, Shift+Enter breaks the line inside it, Escape gives it up.
        if (e.Key == Key.Enter && Keyboard.Modifiers == ModifierKeys.None) { e.Handled = true; CommitTextEdit(); }
        else if (e.Key == Key.Escape) { e.Handled = true; CancelTextEdit(); }
    }

    internal void CommitTextEdit()
    {
        if (_editingText is not { } annotation || _closingTextEdit) return;
        _closingTextEdit = true;
        try
        {
            CloseTextEditor();
            // A caption with nothing in it is not a caption: leaving it would drop an invisible mark
            // on the capture, and there would be no way to find it again.
            if (string.IsNullOrWhiteSpace(annotation.Text)) DropTextMark(annotation);
            else if (_capture is not null) { _lastSnapshot = SnapshotState(); RefreshLabels(); }
            Surface.Focus();
        }
        finally { _closingTextEdit = false; }
    }

    internal void CancelTextEdit()
    {
        if (_editingText is not { } annotation || _closingTextEdit) return;
        _closingTextEdit = true;
        try
        {
            CloseTextEditor();
            if (_editingTextIsNew || string.IsNullOrWhiteSpace(_editingTextBefore)) DropTextMark(annotation);
            else
            {
                annotation.Text = _editingTextBefore;
                TextMarkMetrics.Fit(annotation);
                if (_capture is not null) _lastSnapshot = SnapshotState();
                RefreshLabels();
            }
            Surface.Focus();
        }
        finally { _closingTextEdit = false; }
    }

    // A press somewhere else finishes the caption, the way clicking away from it does everywhere.
    internal bool CommitTextEditIfOutside(DependencyObject? source)
    {
        if (_editingText is null || IsInside(source, _textEditor)) return false;
        CommitTextEdit();
        return true;
    }

    private void CloseTextEditor()
    {
        _editingText = null;
        Surface.EditingTextId = null;
        _textEditor.Visibility = Visibility.Collapsed;
        Surface.InvalidateVisual();
    }

    // A caption that was given up: it leaves the capture, and a caption that was only just placed
    // takes the history entry of its own placement with it, so one Escape leaves nothing behind.
    private void DropTextMark(AnnotationItem annotation)
    {
        if (_capture is null) return;
        if (ReferenceEquals(Surface.SelectedAnnotation, annotation)) Surface.SelectAnnotation(null);
        _capture.Annotations.Remove(annotation);
        if (_editingTextIsNew && _undo.Count > 0 && _undo.Count == _editingUndoDepth) _undo.Pop();
        _lastSnapshot = SnapshotState();
        RefreshLabels();
        SyncAppearance();
    }
}
