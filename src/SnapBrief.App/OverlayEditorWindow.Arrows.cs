using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using SnapBrief.App.Imaging;

namespace SnapBrief.App;

public partial class OverlayEditorWindow
{
    private void OnArrowOptionsClick(object sender, RoutedEventArgs e)
    {
        var menu = new ContextMenu { PlacementTarget = (UIElement)sender };
        foreach (var (style, caption) in new[] { ("straight", "Прямая стрелка"), ("curved", "Изогнутая стрелка"), ("bold", "Толстая стрелка"), ("wide", "Широкая стрелка") })
        {
            var drawing = new DrawingGroup();
            using (var dc = drawing.Open()) ArrowDrawing.Draw(dc, new Point(4, 24), new Point(70, 8), Brushes.White, 2, style);
            var header = new StackPanel { Orientation = Orientation.Horizontal };
            header.Children.Add(new Image { Source = new DrawingImage(drawing), Width = 64, Height = 28, Margin = new Thickness(0, 0, 14, 0) });
            header.Children.Add(new TextBlock { Text = UiLanguage.Text(caption), VerticalAlignment = VerticalAlignment.Center });
            var selected = Surface.SelectedAnnotation;
            var item = new MenuItem { Header = header, IsChecked = (selected?.Kind == EditorTool.Arrow ? selected.ArrowStyle : Surface.ActiveArrowStyle) == style };
            item.Click += (_, _) =>
            {
                if (Surface.SelectedAnnotation is { Kind: EditorTool.Arrow } arrow && _capture is not null)
                {
                    _undo.Push(SnapshotState()); _redo.Clear(); arrow.ArrowStyle = style; _lastSnapshot = SnapshotState(); Surface.InvalidateVisual();
                }
                else SelectToolMode(EditorTool.Arrow);
                Surface.ActiveArrowStyle = style;
                SyncAppearance();
            };
            menu.Items.Add(item);
        }
        menu.IsOpen = true;
    }
}
