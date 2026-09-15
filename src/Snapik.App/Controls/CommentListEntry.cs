using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

namespace Snapik.App.Controls;

/// <summary>
/// One row of the comments panel: the number of the note, its text and what it is attached to.
/// A border and not a button on purpose, because a click here must select the mark on the capture
/// without taking the focus away from it.
/// </summary>
public sealed class CommentListEntry : Border
{
    private readonly TextBlock _badge = new()
    {
        Foreground = Brushes.White, FontSize = 11, FontWeight = FontWeights.Bold,
        HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center
    };
    private readonly TextBlock _text = new()
    {
        FontSize = 12, TextWrapping = TextWrapping.Wrap, VerticalAlignment = VerticalAlignment.Center
    };
    private readonly TextBlock _relation = new()
    {
        FontSize = 11, Margin = new Thickness(0, 3, 0, 0), Visibility = Visibility.Collapsed
    };
    private bool _current;

    public CommentListEntry(Guid annotationId)
    {
        AnnotationId = annotationId;
        // The row is painted by the theme, and by resource and not by colour: the theme may change
        // while the panel is open, and the text of a row would keep the tone of the old one.
        _text.SetResourceReference(TextBlock.ForegroundProperty, "TextBrush");
        _relation.SetResourceReference(TextBlock.ForegroundProperty, "TextMutedBrush");
        Padding = new Thickness(7, 6, 7, 6);
        Margin = new Thickness(0, 0, 0, 4);
        CornerRadius = new CornerRadius(9);
        Background = Brushes.Transparent;
        Cursor = Cursors.Hand;
        var badgeHost = new Border
        {
            Width = 25, Height = 25, CornerRadius = new CornerRadius(13), Background = AccentPalette.Brush,
            Child = _badge, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, 0, 8, 0)
        };
        var lines = new StackPanel();
        lines.Children.Add(_text);
        lines.Children.Add(_relation);
        var row = new DockPanel();
        DockPanel.SetDock(badgeHost, Dock.Left);
        row.Children.Add(badgeHost);
        row.Children.Add(lines);
        Child = row;
        MouseEnter += (_, _) => { if (!_current) SetResourceReference(BackgroundProperty, "HoverBrush"); };
        MouseLeave += (_, _) => { if (!_current) Background = Brushes.Transparent; };
        MouseLeftButtonUp += (_, e) => { Activated?.Invoke(this, EventArgs.Empty); e.Handled = true; };
    }

    public Guid AnnotationId { get; }

    /// <summary>The number of the note, or "+" while it has no text and claims no number yet.</summary>
    public string Label { get => _badge.Text; set => _badge.Text = value; }

    public string Text { get => _text.Text; set => _text.Text = value; }

    public string Relation
    {
        set
        {
            _relation.Text = value;
            _relation.Visibility = string.IsNullOrEmpty(value) ? Visibility.Collapsed : Visibility.Visible;
        }
    }

    public bool IsCurrent
    {
        get => _current;
        // The row of the note the hand is on takes the accent thinned down, as a resource and not as
        // a colour: the accent can change while the panel is open, and the row has to follow it.
        set
        {
            _current = value;
            if (value) SetResourceReference(BackgroundProperty, "AccentSoftBrush");
            else Background = Brushes.Transparent;
        }
    }

    public event EventHandler? Activated;
}
