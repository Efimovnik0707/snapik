using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

namespace SnapBrief.App;

// The captures of a session are deleted from the disk when the strip is cleared and when the
// application exits, and the only way to keep them is "Save package…". That is worth one question,
// and the question carries its own way to turn itself off.
public partial class DiscardSessionWindow : Window
{
    public DiscardSessionWindow(HotkeySettings settings)
    {
        InitializeComponent();
        Loaded += (_, _) => ApplyLanguage(settings.Language);
    }

    /// <summary>Whether the user asked not to be questioned again; read only after "Delete".</summary>
    public bool DoNotAskAgain => DoNotAskBox.IsChecked == true;

    internal void ApplyLanguage(string language) => UiLanguage.Apply(this, language);

    private void OnHeaderDrag(object sender, MouseButtonEventArgs e) { if (e.LeftButton == MouseButtonState.Pressed) DragMove(); }

    private void OnDiscard(object sender, RoutedEventArgs e) => DialogResult = true;

    // Smoke probe: the window is built, laid out and translated both ways, so a broken template or a
    // string without an English pair fails the run.
    internal static void RunDiscardProbe(HotkeySettings settings)
    {
        var window = new DiscardSessionWindow(settings);
        try
        {
            window.Measure(new Size(430, 260));
            window.Arrange(new Rect(0, 0, 430, 260));
            if (window.DoNotAskAgain)
                throw new InvalidOperationException("The discard dialog must open with the question still on.");
            window.DoNotAskBox.IsChecked = true;
            if (!window.DoNotAskAgain)
                throw new InvalidOperationException("The checkbox of the discard dialog must be readable by its caller.");
            window.ApplyLanguage("en");
            var cyrillic = new System.Text.RegularExpressions.Regex("[А-Яа-яЁё]");
            foreach (var text in WindowStrings(window))
                if (cyrillic.IsMatch(text))
                    throw new InvalidOperationException($"The English discard dialog still shows Russian text: \"{text}\".");
            window.ApplyLanguage("ru");
        }
        finally { window.Close(); }
    }

    private static IEnumerable<string> WindowStrings(DiscardSessionWindow window)
    {
        var visited = new HashSet<DependencyObject>();
        var found = new List<string>();
        void Walk(DependencyObject item)
        {
            if (!visited.Add(item)) return;
            if (item is FrameworkElement { ToolTip: string tip }) found.Add(tip);
            if (item is ContentControl { Content: string caption }) found.Add(caption);
            if (item is TextBlock text) found.Add(text.Text);
            foreach (var child in LogicalTreeHelper.GetChildren(item)) if (child is DependencyObject dependency) Walk(dependency);
            if (item is Visual)
                for (var i = 0; i < VisualTreeHelper.GetChildrenCount(item); i++) Walk(VisualTreeHelper.GetChild(item, i));
        }
        Walk(window);
        return found;
    }
}
