using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;

namespace Snapik.App.Controls;

/// <summary>
/// The look of the application in one control: the gallery of themes, the row of accents and a line
/// showing what a mark will look like. It is shown twice, on step four of the wizard and in the
/// appearance tab of the settings, and both show the same thing because it is the same control.
///
/// The preview is live and free: clicking a card applies the theme to the whole application at once
/// and saves nothing. Whoever owns the control takes the values when it saves, and puts the previous
/// pair back if the user walks away.
/// </summary>
public partial class AppearancePicker : UserControl
{
    private string _language = UiLanguage.Current;
    private string _theme = ThemeService.DefaultTheme;
    private string _accent = ThemeService.DefaultAccent;
    private string _palette = "standard";
    private bool _building;

    /// <summary>The names of the themes, in the order the gallery shows them.</summary>
    private static readonly Dictionary<string, string> ThemeNames = new()
    {
        ["dark"] = "Тёмная", ["glass"] = "Стекло",
        // The dawn theme is the light one: the card says both words, so nobody looks for a "Light"
        // card that is not there any more.
        ["night"] = "Ночь", ["sunset"] = "Закат", ["sea"] = "Море", ["dawn"] = "Светлая · Рассвет"
    };

    // The identifier of an accent and its name have drifted apart: "teal" is shown as green and
    // "coral" as orange, because the settings file carries the identifier and renaming it would cost
    // a migration for a word.
    private static readonly Dictionary<string, string> AccentNames = new()
    {
        ["blue"] = "синий", ["teal"] = "зелёный", ["violet"] = "фиолетовый", ["coral"] = "оранжевый",
        ["rose"] = "розовый", ["cyan"] = "бирюзовый",
        ["blue-violet"] = "сине-фиолетовый", ["orange-rose"] = "оранжево-розовый",
        ["green-cyan"] = "зелёно-бирюзовый", ["amber-pink"] = "янтарно-розовый",
        ["rose-violet"] = "розово-фиолетовый", ["cyan-blue"] = "бирюзово-синий"
    };

    /// <summary>A card and the gap after it: what one press of a chevron moves the gallery by.</summary>
    private const double CardStep = 142;

    /// <summary>The card the gallery starts at, counted by the control itself.</summary>
    private int _firstCard;

    /// <summary>The sideways wheel of a touchpad; WPF has no event of its own for it.</summary>
    private const int WmMouseHWheel = 0x020E;

    private HwndSource? _source;

    public AppearancePicker()
    {
        InitializeComponent();
        BuildThemeCards();
        BuildAccentRow();
        StandardPalette.IsChecked = true;
        ApplyLanguage(_language);
        // Loaded and Unloaded come in pairs and come again, so the hook is taken once and given back
        // every time the control leaves the tree. The hook is removed before it is added: a second
        // Loaded without an Unloaded between them would leave two hooks and page the gallery twice
        // on one turn of the wheel.
        Loaded += (_, _) =>
        {
            _source ??= PresentationSource.FromVisual(this) as HwndSource;
            _source?.RemoveHook(OnWindowMessage);
            _source?.AddHook(OnWindowMessage);
        };
        Unloaded += (_, _) => { _source?.RemoveHook(OnWindowMessage); _source = null; };
    }

    public event EventHandler? ThemeChanged;
    public event EventHandler? AccentChanged;
    public event EventHandler? PaletteChanged;

    public string SelectedTheme
    {
        get => _theme;
        set
        {
            var theme = ThemeService.NormalizeTheme(value);
            if (theme == _theme) return;
            _theme = theme;
            MarkSelectedCard();
            ThemeChanged?.Invoke(this, EventArgs.Empty);
        }
    }

    public string SelectedAccent
    {
        get => _accent;
        set
        {
            var accent = ThemeService.Normalize(value);
            if (accent == _accent) return;
            _accent = accent;
            MarkSelectedDot();
            AccentChanged?.Invoke(this, EventArgs.Empty);
        }
    }

    /// <summary>Which twelve-colour set the editor offers: standard, pastel or the user's own.</summary>
    public string SelectedPalette
    {
        get => _palette;
        set
        {
            var palette = value is "pastel" or "custom" ? value : "standard";
            if (palette == _palette) return;
            _palette = palette;
            _building = true;
            StandardPalette.IsChecked = palette == "standard";
            PastelPalette.IsChecked = palette == "pastel";
            CustomPalette.IsChecked = palette == "custom";
            _building = false;
            PaletteChanged?.Invoke(this, EventArgs.Empty);
        }
    }

    /// <summary>Whether the row of annotation palettes is part of the control. It is not by default.</summary>
    public bool ShowPaletteRow
    {
        get => PaletteBlock.Visibility == Visibility.Visible;
        set => PaletteBlock.Visibility = value ? Visibility.Visible : Visibility.Collapsed;
    }

    /// <summary>
    /// The captions are built in code, so they are rebuilt whenever the language changes, the way the
    /// hotkey field rebuilds its own.
    /// </summary>
    public void ApplyLanguage(string language)
    {
        _language = language;
        ThemeCaption.Text = Text("Тема · фон и панели");
        AccentCaption.Text = Text("Цвет · рамки, кнопки, номера отметок");
        PaletteCaption.Text = Text("Палитра отметок");
        StandardPalette.Content = Text("Стандартная");
        PastelPalette.Content = Text("Пастель");
        CustomPalette.Content = Text("Своя");
        SampleDone.Text = Text("Готово");
        SampleCaption.Text = Text("так будут выглядеть отметки");
        PreviousTheme.ToolTip = Text("Предыдущая тема");
        NextTheme.ToolTip = Text("Следующая тема");
        foreach (var card in ThemeCards.Children.OfType<Button>())
        {
            if (card.Tag is not string theme) continue;
            var name = Text(ThemeNames[theme]);
            if (NameOf(card) is { } caption) caption.Text = name;
            AutomationProperties.SetName(card, string.Format(Text("Тема: {0}"), name));
        }
        foreach (var dot in AccentRow.Children.OfType<RadioButton>())
            if (dot.Tag is string accent)
                AutomationProperties.SetName(dot, string.Format(Text("Акцент: {0}"), Text(AccentNames[accent])));
    }

    private string Text(string russian) => UiLanguage.Text(russian, _language);

    // Every card is drawn out of the dictionary it stands for, not out of the one in force: the sea
    // card has to show the sea while the application is still dark.
    private void BuildThemeCards()
    {
        foreach (var theme in ThemeService.Themes)
        {
            var palette = ThemeService.LoadTheme(theme);
            var bars = new StackPanel();
            bars.Children.Add(Bar(12, Frozen(palette["DividerBrush"] as Brush)));
            bars.Children.Add(Bar(12, Frozen(palette["DividerBrush"] as Brush)));
            var accentBar = Bar(8, null);
            accentBar.SetResourceReference(Border.BackgroundProperty, "AccentBrush");
            bars.Children.Add(accentBar);
            var strip = new Border
            {
                Width = 40, Margin = new Thickness(6), Padding = new Thickness(4), CornerRadius = new CornerRadius(5),
                HorizontalAlignment = HorizontalAlignment.Right, BorderThickness = new Thickness(1),
                Background = Frozen(palette["SurfaceBrush"] as Brush), BorderBrush = Frozen(palette["SurfaceLineBrush"] as Brush),
                Child = bars
            };
            var preview = new Border
            {
                Height = 64, CornerRadius = new CornerRadius(7), ClipToBounds = true,
                Background = Backdrop(theme), Child = new Grid { Children = { strip } }
            };
            var name = new TextBlock { FontSize = 12, Margin = new Thickness(0, 6, 0, 0), HorizontalAlignment = HorizontalAlignment.Center };
            name.SetResourceReference(TextBlock.ForegroundProperty, "TextBrush");
            var content = new StackPanel();
            content.Children.Add(preview);
            content.Children.Add(name);
            var card = new Button { Style = (Style)FindResource("ThemeCard"), Tag = theme, Content = content };
            card.Click += OnThemePicked;
            ThemeCards.Children.Add(card);
        }
        MarkSelectedCard();
    }

    private void BuildAccentRow()
    {
        var dividerPlaced = false;
        foreach (var accent in ThemeService.Accents)
        {
            // The gradients follow the solid ones, with a hairline between the two halves. Where the
            // line goes is asked of the dictionaries and not of a name: the row was rearranged this
            // round, and a name in a condition here would have been the one place left behind.
            if (!dividerPlaced && ThemeService.IsGradientAccent(accent))
            {
                AccentRow.Children.Add(Divider());
                dividerPlaced = true;
            }
            var dot = new RadioButton
            {
                Style = (Style)FindResource("AccentDot"), Tag = accent, GroupName = "AppearanceAccent",
                Background = Frozen(ThemeService.LoadAccent(accent)["AccentBrush"] as Brush)
            };
            dot.Checked += OnAccentPicked;
            AccentRow.Children.Add(dot);
        }
        MarkSelectedDot();
    }

    // Four pixels on each side, the same as the gap between two dots: twelve dots of 28 with a step
    // of 10 and this line come to 455 px, and the row of the wizard is 520 wide.
    private Border Divider()
    {
        var line = new Border { Width = 1, Height = 22, Margin = new Thickness(4, 0, 4, 0), VerticalAlignment = VerticalAlignment.Center };
        line.SetResourceReference(Border.BackgroundProperty, "DividerBrush");
        return line;
    }

    private static Border Bar(double height, Brush? fill) =>
        new() { Height = height, Margin = new Thickness(0, 0, 0, 3), CornerRadius = new CornerRadius(3), Background = fill };

    // The mock desktop a preview panel sits on: one neutral tone for the dark themes and one for the
    // light ones, and the glass card shows the colours glass is meant to be seen through.
    private static Brush Backdrop(string theme) => theme switch
    {
        "dawn" => Frozen(new SolidColorBrush(Color.FromRgb(0xE8, 0xEC, 0xF2))),
        "glass" => Frozen(new LinearGradientBrush(new GradientStopCollection
        {
            new(Color.FromRgb(0x5B, 0x6B, 0x8C), 0), new(Color.FromRgb(0x8C, 0x6B, 0x7A), 0.5), new(Color.FromRgb(0x4E, 0x7C, 0x8A), 1)
        }, new Point(0, 0), new Point(1, 1))),
        "dark" => Frozen(new SolidColorBrush(Color.FromRgb(0x2A, 0x31, 0x40))),
        _ => Frozen(new SolidColorBrush(Color.FromRgb(0x1E, 0x24, 0x30)))
    };

    // A brush out of a dictionary nothing merged is still a brush the whole gallery shares: it is
    // copied and frozen for the same reason the accent is.
    private static Brush Frozen(Brush? brush)
    {
        var copy = brush?.CloneCurrentValue() ?? Brushes.Transparent;
        copy.Freeze();
        return copy;
    }

    private static TextBlock? NameOf(Button card) =>
        (card.Content as StackPanel)?.Children.OfType<TextBlock>().FirstOrDefault();

    // The frame marks the theme in force wherever its card stands; the gallery itself is not moved
    // for it. It opens at the first card, so the row reads from its beginning and the way on is the
    // obvious one, even when the theme in force is the last of the six.
    private void MarkSelectedCard()
    {
        foreach (var card in ThemeCards.Children.OfType<Button>())
        {
            if (card.Tag as string == _theme) card.SetResourceReference(Border.BorderBrushProperty, "AccentBrush");
            else card.BorderBrush = Brushes.Transparent;
        }
    }

    private void MarkSelectedDot()
    {
        _building = true;
        foreach (var dot in AccentRow.Children.OfType<RadioButton>())
            dot.IsChecked = dot.Tag as string == _accent;
        _building = false;
    }

    /// <summary>How many whole cards the gallery shows at its current width, never fewer than one.</summary>
    private int VisibleCards => Math.Max(1, (int)(Gallery.ViewportWidth / CardStep));

    /// <summary>The furthest card the gallery can start at: past it the strip would show empty space.</summary>
    private int LastPage => Math.Max(0, ThemeCards.Children.Count - VisibleCards);

    // The gallery is moved by the card, and the card is counted here. Asking the scroll viewer where
    // it stands does not work for this: it answers with the offset of the previous layout pass, and
    // it clamps that offset at the end of the strip, so a chevron built on it pages from a number
    // that is not the one on screen and goes silently dead wherever the clamp landed.
    private void PageBy(int cards)
    {
        _firstCard = Math.Clamp(_firstCard + cards, 0, LastPage);
        Gallery.ScrollToHorizontalOffset(_firstCard * CardStep);
        MarkChevrons();
    }

    // An end says so. A chevron with nothing left to show is switched off instead of answering a
    // click with nothing, which is how the gallery came to read as one that does not scroll at all.
    private void MarkChevrons()
    {
        PreviousTheme.IsEnabled = _firstCard > 0;
        NextTheme.IsEnabled = _firstCard < LastPage;
    }

    // The width of the gallery is known only after a layout pass, and the offset it settles on at the
    // end of the strip is the clamped one, which is short of a whole number of cards: the count is put
    // back in step with what is on screen every time the viewer reports a move.
    private void OnGalleryScrolled(object sender, ScrollChangedEventArgs e)
    {
        _firstCard = Gallery.HorizontalOffset >= Gallery.ScrollableWidth
            ? LastPage
            : Math.Clamp((int)Math.Round(Gallery.HorizontalOffset / CardStep), 0, LastPage);
        MarkChevrons();
    }

    // The wheel pages the gallery instead of the window behind it. Handled in the preview phase on
    // purpose: the gallery scrolls horizontally only, so without this the wheel walks up to the
    // scroll viewer of the wizard and scrolls the step.
    private void OnGalleryWheel(object sender, MouseWheelEventArgs e)
    {
        if (e.Delta == 0) return;
        PageBy(e.Delta > 0 ? -1 : 1);
        e.Handled = true;
    }

    // A touchpad sends the sideways swipe as WM_MOUSEHWHEEL, which WPF has no event for, so it is
    // taken off the window the control currently lives in. The control is shown twice, in the wizard
    // and in the settings, and each copy keeps the hook of its own window while it is loaded.
    private IntPtr OnWindowMessage(IntPtr hwnd, int message, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (message != WmMouseHWheel || !Gallery.IsMouseOver) return IntPtr.Zero;
        var delta = (short)((wParam.ToInt64() >> 16) & 0xFFFF);
        if (delta == 0) return IntPtr.Zero;
        // The sign is the other way round from the wheel: a swipe to the right goes forward.
        PageBy(delta > 0 ? 1 : -1);
        handled = true;
        return IntPtr.Zero;
    }

    // The preview is the whole point of the control: the click paints the application, and nothing
    // here writes to the settings file.
    private void OnThemePicked(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string theme }) return;
        SelectedTheme = theme;
        ThemeService.Apply(SelectedTheme, SelectedAccent);
    }

    private void OnAccentPicked(object sender, RoutedEventArgs e)
    {
        if (_building || sender is not RadioButton { Tag: string accent }) return;
        SelectedAccent = accent;
        ThemeService.Apply(SelectedTheme, SelectedAccent);
    }

    private void OnPaletteChecked(object sender, RoutedEventArgs e)
    {
        if (_building || sender is not RadioButton { Tag: string palette }) return;
        SelectedPalette = palette;
    }

    private void OnPreviousTheme(object sender, RoutedEventArgs e) => PageBy(-1);

    private void OnNextTheme(object sender, RoutedEventArgs e) => PageBy(1);

    /// <summary>
    /// The smoke check: the control builds, shows a card per theme and a dot per accent, picks with a
    /// live repaint, and its cards keep showing the theme they stand for while another one is on.
    /// </summary>
    internal static void RunProbe()
    {
        var before = (ThemeService.CurrentTheme, ThemeService.CurrentAccent);
        var picker = new AppearancePicker { Width = 520 };
        picker.ApplyLanguage("en");
        picker.Measure(new Size(520, 400));
        picker.Arrange(new Rect(0, 0, 520, 400));
        picker.UpdateLayout();
        if (picker.ThemeCards.Children.Count != ThemeService.Themes.Count ||
            picker.AccentRow.Children.OfType<RadioButton>().Count() != ThemeService.Accents.Count)
            throw new InvalidOperationException("The appearance picker must show a card per theme and a dot per accent.");
        if (picker.PaletteBlock.Visibility != Visibility.Collapsed)
            throw new InvalidOperationException("The palette row must be off until the owner of the control asks for it.");
        // One hairline in the row, and it stands immediately before the first dot that paints with a
        // gradient. This is what catches a rearranged row and a dictionary with an unexpected brush.
        var row = picker.AccentRow.Children.Cast<UIElement>().ToList();
        var divider = row.FindIndex(item => item is Border);
        if (divider < 0 || divider + 1 >= row.Count || row.Count(item => item is Border) != 1)
            throw new InvalidOperationException("The row of accents must carry exactly one divider, and a dot after it.");
        if (row[divider + 1] is not RadioButton { Tag: string first } || !ThemeService.IsGradientAccent(first) ||
            row.Take(divider).Any(item => item is RadioButton { Tag: string solid } && ThemeService.IsGradientAccent(solid)))
            throw new InvalidOperationException("The divider must stand between the solid accents and the gradients.");
        picker.ShowPaletteRow = true;
        picker.SelectedPalette = "pastel";
        if (picker.PaletteBlock.Visibility != Visibility.Visible || picker.PastelPalette.IsChecked != true)
            throw new InvalidOperationException("The palette row must follow the value it is given.");

        ThemeService.Apply("dark", "blue");
        var sea = picker.ThemeCards.Children.OfType<Button>().First(card => card.Tag as string == "sea");
        if (PreviewPanel(sea) is not LinearGradientBrush card || card.GradientStops[0].Color != Color.FromRgb(0x16, 0x3A, 0x44))
            throw new InvalidOperationException("A card must show the theme it stands for, not the theme in force.");
        var repainted = false;
        picker.ThemeChanged += (_, _) => repainted = true;
        sea.RaiseEvent(new RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent));
        if (!repainted || picker.SelectedTheme != "sea" || ThemeService.CurrentTheme != "sea" ||
            Application.Current.Resources["SurfaceBrush"] is not LinearGradientBrush)
            throw new InvalidOperationException("Clicking a card must repaint the application at once.");

        // Six cards of 132 with a gap of 10 do not fit into the 520 the wizard gives the control,
        // so there is always something to page at this width.
        if (picker.Gallery.ScrollableWidth <= 0 || picker.Gallery.ExtentWidth <= picker.Gallery.ViewportWidth)
            throw new InvalidOperationException("Six cards of 132 must not fit into 520: the gallery has to have something to page.");
        picker.PageBy(-picker.ThemeCards.Children.Count);
        picker.UpdateLayout();
        if (picker._firstCard != 0 || picker.PreviousTheme.IsEnabled || !picker.NextTheme.IsEnabled)
            throw new InvalidOperationException("At the first card the gallery must offer the way on and not the way back.");
        picker.NextTheme.RaiseEvent(new RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent));
        picker.UpdateLayout();
        if (picker._firstCard != 1 || picker.Gallery.HorizontalOffset <= 0 || !picker.PreviousTheme.IsEnabled)
            throw new InvalidOperationException("The chevrons must page the gallery by a card.");
        // The theme in force keeps its frame while the gallery moves under it, and no other card
        // takes one.
        var framed = picker.ThemeCards.Children.OfType<Button>()
            .Where(card => !ReferenceEquals(card.BorderBrush, Brushes.Transparent)).ToList();
        if (framed.Count != 1 || framed[0].Tag as string != picker.SelectedTheme)
            throw new InvalidOperationException("Paging the gallery must leave the frame on the card in force and on no other.");
        // The end of the strip: the chevron says so instead of answering a click with nothing, and a
        // card picked where it stands leaves the gallery where the chevrons have taken it.
        for (var guard = 0; picker.NextTheme.IsEnabled && guard < 20; guard++)
        {
            picker.NextTheme.RaiseEvent(new RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent));
            picker.UpdateLayout();
        }
        var lastPage = picker._firstCard;
        if (lastPage == 0 || picker.NextTheme.IsEnabled || !picker.PreviousTheme.IsEnabled)
            throw new InvalidOperationException("At the last card the chevron on must be switched off and the one back left on.");
        picker.ThemeCards.Children.OfType<Button>().Last().RaiseEvent(new RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent));
        picker.UpdateLayout();
        if (picker._firstCard != lastPage)
            throw new InvalidOperationException("A card chosen where it stands must leave the gallery where it is.");
        picker.PreviousTheme.RaiseEvent(new RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent));
        picker.UpdateLayout();
        if (picker._firstCard != lastPage - 1 || !picker.NextTheme.IsEnabled)
            throw new InvalidOperationException("The gallery must page back from the end.");

        // The gallery opens at the first card whatever the theme in force is: the frame marks the
        // card, it does not pull the strip to it. The wheel and the sideways swipe of a touchpad go
        // through the same paging as the chevrons, so the paging itself is what is checked here.
        picker.SelectedTheme = ThemeService.Themes[0];
        picker.PageBy(-picker.ThemeCards.Children.Count);
        picker.UpdateLayout();
        picker.SelectedTheme = ThemeService.Themes[^1];
        picker.UpdateLayout();
        if (picker._firstCard != 0 || picker.Gallery.HorizontalOffset != 0)
            throw new InvalidOperationException("Choosing a theme must leave the gallery at the card it stands on.");
        var marked = picker.ThemeCards.Children.OfType<Button>()
            .Where(card => !ReferenceEquals(card.BorderBrush, Brushes.Transparent)).ToList();
        if (marked.Count != 1 || marked[0].Tag as string != ThemeService.Themes[^1])
            throw new InvalidOperationException("The frame must stand on the theme in force wherever its card is.");
        picker.PageBy(1);
        picker.UpdateLayout();
        if (picker._firstCard != 1)
            throw new InvalidOperationException("One notch of the wheel must move the gallery by one card.");
        picker.PageBy(picker.ThemeCards.Children.Count);
        picker.UpdateLayout();
        if (picker._firstCard != lastPage || picker.NextTheme.IsEnabled)
            throw new InvalidOperationException("The wheel must stop at the last page, the same as the chevron.");

        picker.ApplyLanguage("ru");
        if (NameOf(sea)?.Text != "Море")
            throw new InvalidOperationException("The names of the themes must follow the language applied to the control.");
        ThemeService.Apply(before.CurrentTheme, before.CurrentAccent);
    }

    private static Brush? PreviewPanel(Button card) =>
        ((((card.Content as StackPanel)?.Children[0] as Border)?.Child as Grid)?.Children[0] as Border)?.Background;
}
