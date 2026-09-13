using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;
using System.Windows.Threading;
using SnapBrief.Core.Models;

namespace SnapBrief.App;

public partial class OverlayEditorWindow
{
    // The chevron half of a split button and its menu: the same dark chrome for the shapes of a
    // region and for the styles of an arrow. The menu is built apart from being opened, so a smoke
    // run can read what it offers without a popup on screen.
    private ContextMenu ToolMenu(UIElement target) => new()
    {
        PlacementTarget = target,
        Placement = System.Windows.Controls.Primitives.PlacementMode.Bottom,
        Background = new SolidColorBrush(Color.FromArgb(248, 23, 26, 32)),
        Foreground = Brushes.White,
        BorderBrush = new SolidColorBrush(Color.FromRgb(58, 66, 78)),
        BorderThickness = new Thickness(1),
        Padding = new Thickness(5)
    };

    private static MenuItem MenuRow(UIElement icon, string caption, bool isChecked, Action action)
    {
        var header = new StackPanel { Orientation = Orientation.Horizontal };
        icon.SetValue(FrameworkElement.MarginProperty, new Thickness(0, 0, 14, 0));
        header.Children.Add(icon);
        header.Children.Add(new TextBlock { Text = caption, VerticalAlignment = VerticalAlignment.Center });
        var item = new MenuItem { Header = header, IsChecked = isChecked, Foreground = Brushes.White, Padding = new Thickness(10, 7, 10, 7) };
        item.Click += (_, _) => action();
        return item;
    }

    // The whole menu is one edit: it takes the state before opening and pushes at most one history
    // entry when it closes, exactly like the colour popover.
    private void OpenToolMenu(ContextMenu menu)
    {
        if (_capture is not null) { _appearanceBefore = SnapshotState(); _appearanceChanged = false; }
        menu.Closed += (_, _) => { CommitAppearanceEdit(); Surface.Focus(); };
        menu.IsOpen = true;
    }

    private ContextMenu BuildShapeMenu(UIElement target)
    {
        var menu = ToolMenu(target);
        var selected = Surface.SelectedAnnotation;
        var current = selected is { Kind: EditorTool.Rectangle or EditorTool.Blur } ? selected.Shape : Surface.ActiveShape;
        Add(AnnotationShape.Rectangle, "Прямоугольник", new Rectangle { Width = 24, Height = 16, Stroke = Brushes.White, StrokeThickness = 1.4 });
        Add(AnnotationShape.Rounded, "Скруглённый прямоугольник", new Rectangle { Width = 24, Height = 16, RadiusX = 5, RadiusY = 5, Stroke = Brushes.White, StrokeThickness = 1.4 });
        Add(AnnotationShape.Ellipse, "Овал", new Ellipse { Width = 24, Height = 16, Stroke = Brushes.White, StrokeThickness = 1.4 });
        return menu;

        void Add(AnnotationShape shape, string caption, UIElement icon) =>
            menu.Items.Add(MenuRow(icon, UiLanguage.Text(caption), current == shape, () =>
            {
                // The shape belongs to the region and to the blur alike: a selected blur takes it
                // without the tool switching out from under the hand.
                if (Surface.SelectedAnnotation is not { Kind: EditorTool.Rectangle or EditorTool.Blur }) SelectToolMode(EditorTool.Rectangle);
                ApplyAppearance(null, null, shape: shape);
            }));
    }

    private void OnShapeMenuClick(object sender, RoutedEventArgs e) => OpenToolMenu(BuildShapeMenu((UIElement)sender));

    // A long press on the tool itself opens the same menu, for the hand that never finds the chevron.
    private void AttachLongPress(ButtonBase button, Func<ContextMenu> build)
    {
        var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(400) };
        timer.Tick += (_, _) =>
        {
            timer.Stop();
            if (Mouse.LeftButton == MouseButtonState.Pressed && button.IsMouseOver) OpenToolMenu(build());
        };
        button.PreviewMouseLeftButtonDown += (_, _) => timer.Start();
        button.PreviewMouseLeftButtonUp += (_, _) => timer.Stop();
        button.MouseLeave += (_, _) => timer.Stop();
    }
}
