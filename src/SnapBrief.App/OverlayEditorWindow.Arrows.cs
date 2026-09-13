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

        // The thickness is not here any more: it belongs to every stroke, not to the arrow, and it
        // has its own button on the panel. This menu is about the style of the arrow alone.
        return menu;
    }

    private void OnArrowOptionsClick(object sender, RoutedEventArgs e) => OpenToolMenu(BuildArrowMenu((UIElement)sender));
}
