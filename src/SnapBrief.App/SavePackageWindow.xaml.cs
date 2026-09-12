using System;
using System.Collections.Generic;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

namespace SnapBrief.App;

/// <summary>Where the package goes and under which name; the folder name is used only with a subfolder.</summary>
public sealed record SavePackageChoice(string Directory, bool CreateSubfolder, string FolderName);

// One window instead of the system folder picker: saving the same package twice into the same
// folder is the common case, so the folder, the name and the subfolder switch are all on screen at
// once and the choice is remembered.
public partial class SavePackageWindow : Window
{
    private string _language;
    public SavePackageChoice? Result { get; private set; }

    public SavePackageWindow(HotkeySettings settings, DateTime now)
    {
        _language = settings.Language;
        InitializeComponent();
        DirectoryBox.Text = settings.PackageDirectory();
        SubfolderBox.IsChecked = settings.PackageCreateSubfolder;
        NameBox.Text = $"SnapBrief-{now:yyyyMMdd-HHmmss}";
        SubfolderBox.Checked += (_, _) => UpdateNameState();
        SubfolderBox.Unchecked += (_, _) => UpdateNameState();
        UpdateNameState();
        Loaded += (_, _) => ApplyLanguage(settings.Language);
    }

    internal void ApplyLanguage(string language)
    {
        _language = language;
        UiLanguage.Apply(this, language);
    }

    // Without a subfolder the files go straight into the chosen folder under a date prefix, so the
    // name of a folder that is not created has nothing to describe.
    private void UpdateNameState() => NameLabel.IsEnabled = NameBox.IsEnabled = SubfolderBox.IsChecked == true;

    private void OnHeaderDrag(object sender, MouseButtonEventArgs e) { if (e.LeftButton == MouseButtonState.Pressed) DragMove(); }

    private void OnClose(object sender, RoutedEventArgs e) => Close();

    private void OnBrowseDirectory(object sender, RoutedEventArgs e)
    {
        var dialog = new Microsoft.Win32.OpenFolderDialog
        {
            InitialDirectory = System.IO.Directory.Exists(DirectoryBox.Text) ? DirectoryBox.Text : Environment.GetFolderPath(Environment.SpecialFolder.MyPictures)
        };
        if (dialog.ShowDialog(this) == true) DirectoryBox.Text = dialog.FolderName;
    }

    private void OnSave(object sender, RoutedEventArgs e)
    {
        try
        {
            var directory = DirectoryBox.Text.Trim();
            if (directory.Length == 0)
                throw new InvalidOperationException(UiLanguage.Text("Укажите папку сохранения.", _language));
            // A relative path would be resolved against the working directory of the process, and
            // the package would land somewhere the user never named.
            if (!Path.IsPathFullyQualified(directory))
                throw new InvalidOperationException(UiLanguage.Text(@"Укажите полный путь к папке, например C:\Users\Public\Pictures.", _language));
            var createSubfolder = SubfolderBox.IsChecked == true;
            var name = NameBox.Text.Trim();
            if (createSubfolder && name.Length == 0)
                throw new InvalidOperationException(UiLanguage.Text("Укажите имя папки.", _language));
            if (createSubfolder && name.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0)
                throw new InvalidOperationException(UiLanguage.Text("В имени папки есть недопустимые символы.", _language));
            Result = new SavePackageChoice(Path.GetFullPath(directory), createSubfolder, name);
            DialogResult = true;
        }
        catch (Exception ex)
        {
            // The lines thrown above are already in the language of the window; anything else is a
            // .NET message about a path, and the user is told what to do with it instead.
            ErrorText.Text = ex is InvalidOperationException
                ? ex.Message
                : UiLanguage.Text("Этот путь не подходит. Выберите папку кнопкой обзора.", _language);
            ErrorText.Visibility = Visibility.Visible;
            Result = null;
        }
    }

    // Smoke probe: the window is built, laid out and translated both ways, so a broken template or a
    // string without an English pair fails the run.
    internal static void RunSavePackageProbe(HotkeySettings settings)
    {
        var window = new SavePackageWindow(settings, new DateTime(2026, 9, 12, 17, 18, 27));
        try
        {
            window.Measure(new Size(470, 460));
            window.Arrange(new Rect(0, 0, 470, 460));
            if (window.NameBox.Text != "SnapBrief-20260912-171827")
                throw new InvalidOperationException("The folder name must be offered as SnapBrief with the date and the time.");
            window.SubfolderBox.IsChecked = false;
            if (window.NameBox.IsEnabled || window.NameLabel.IsEnabled)
                throw new InvalidOperationException("The folder name must be disabled while no subfolder is created.");
            window.SubfolderBox.IsChecked = true;
            if (!window.NameBox.IsEnabled)
                throw new InvalidOperationException("The folder name must come back with the subfolder.");
            window.ApplyLanguage("en");
            var cyrillic = new System.Text.RegularExpressions.Regex("[А-Яа-яЁё]");
            foreach (var text in WindowStrings(window))
                if (cyrillic.IsMatch(text))
                    throw new InvalidOperationException($"The English save package window still shows Russian text: \"{text}\".");
            window.ApplyLanguage("ru");
        }
        finally { window.Close(); }
    }

    private static IEnumerable<string> WindowStrings(SavePackageWindow window)
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
