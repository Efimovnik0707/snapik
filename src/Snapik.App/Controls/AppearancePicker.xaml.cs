using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
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

    public AppearancePicker()
    {
        InitializeComponent();
        BuildThemeCards();
        BuildAccentRow();
        StandardPalette.IsChecked = true;
        ApplyLanguage(_language);
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
        foreach (var accent in ThemeService.Accents)
        {
            // The four gradients follow the four solid ones, with a hairline between the two halves.
            if (accent == "blue-violet")
                AccentRow.Children.Add(Divider());
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

    private Border Divider()
    {
        var line = new Border { Width = 1, Height = 22, Margin = new Thickness(4, 0, 14, 0), VerticalAlignment = VerticalAlignment.Center };
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

    private void MarkSelectedCard()
    {
        foreach (var card in ThemeCards.Children.OfType<Button>())
        {
            if (card.Tag as string == _theme) card.SetResourceReference(Border.BorderBrushProperty, "AccentBrush");
            else card.BorderBrush = Brushes.Transparent;
        }
        BringSelectedCardIntoView();
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

    // A card already on screen is left where it is: choosing a theme must not pull the gallery back
    // from where the chevrons have taken it.
    private void BringSelectedCardIntoView()
    {
        var index = ThemeService.Themes.ToList().IndexOf(_theme);
        if (index < 0 || Gallery is null) return;
        if (index < _firstCard) PageBy(index - _firstCard);
        else if (index >= _firstCard + VisibleCards) PageBy(index - VisibleCards + 1 - _firstCard);
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

        picker.ApplyLanguage("ru");
        if (NameOf(sea)?.Text != "Море")
            throw new InvalidOperationException("The names of the themes must follow the language applied to the control.");
        ThemeService.Apply(before.CurrentTheme, before.CurrentAccent);
    }

    private static Brush? PreviewPanel(Button card) =>
        ((((card.Content as StackPanel)?.Children[0] as Border)?.Child as Grid)?.Children[0] as Border)?.Background;
}
