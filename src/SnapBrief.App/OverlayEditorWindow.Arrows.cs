using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using SnapBrief.App.Imaging;

namespace SnapBrief.App;

public partial class OverlayEditorWindow
{
    private ContextMenu BuildArrowMenu(UIElement target)
    {
        var menu = ToolMenu(target);
        var selected = Surface.SelectedAnnotation;
        var current = selected?.Kind == EditorTool.Arrow ? selected.ArrowStyle : Surface.ActiveArrowStyle;
        // "bold" is still drawn for arrows that carry it, but it is not offered any more: it only
        // doubles the thickness, and the thickness is on the slider below.
        foreach (var (style, caption) in new[] { ("straight", "Прямая стрелка"), ("curved", "Изогнутая стрелка"), ("wide", "Широкая стрелка") })
        {
            var drawing = new DrawingGroup();
            using (var dc = drawing.Open()) ArrowDrawing.Draw(dc, new Point(4, 24), new Point(70, 8), Brushes.White, 2, style);
            var pick = style;
            menu.Items.Add(MenuRow(
                new Image { Source = new DrawingImage(drawing), Width = 64, Height = 28 },
                UiLanguage.Text(caption), current == style, () =>
                {
                    if (Surface.SelectedAnnotation is not { Kind: EditorTool.Arrow }) SelectToolMode(EditorTool.Arrow);
                    ApplyAppearance(null, null, arrowStyle: pick);
                }));
        }

        // The same edit as the slider in the popover, not a second state: one ApplyAppearance call.
        var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(10, 4, 10, 2) };
        row.Children.Add(new TextBlock
        {
            Text = UiLanguage.Text("Толщина"), Foreground = Brushes.White,
            VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 12, 0)
        });
        var slider = new Slider
        {
            Width = 120, Minimum = 1, Maximum = 16, TickFrequency = 1, IsSnapToTickEnabled = true, IsMoveToPointEnabled = true,
            Style = (Style)FindResource("StrokeSliderStyle"), VerticalAlignment = VerticalAlignment.Center,
            Value = Math.Clamp(selected?.Thickness ?? _activeThickness, 1, 16)
        };
        System.Windows.Automation.AutomationProperties.SetName(slider, UiLanguage.Text("Толщина линии"));
        slider.ValueChanged += (_, e) => ApplyAppearance(null, Math.Round(e.NewValue));
        row.Children.Add(slider);
        menu.Items.Add(new Separator());
        menu.Items.Add(new MenuItem { Header = row, StaysOpenOnClick = true, Foreground = Brushes.White, Padding = new Thickness(0) });
        return menu;
    }

    private void OnArrowOptionsClick(object sender, RoutedEventArgs e) => OpenToolMenu(BuildArrowMenu((UIElement)sender));
}
