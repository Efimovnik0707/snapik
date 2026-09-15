using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Windows;

namespace Snapik.App;

/// <summary>
/// Swaps the two dictionaries the look of the application is made of: the palette of the theme and
/// the accent. The windows read both through DynamicResource, so replacing a dictionary repaints
/// them without rebuilding anything and without a restart. Neither call saves anything: the owner of
/// the settings writes the pair it wants kept.
/// </summary>
internal static class ThemeService
{
    internal const string DefaultTheme = "dark";
    internal const string DefaultAccent = "blue";
    // Six themes: the flat light one is gone and "dawn" is the light theme now. A settings file that
    // still says "light" is migrated to "dark" on the way in, and anything NormalizeTheme cannot
    // find falls back to the same place.
    internal static IReadOnlyList<string> Themes { get; } = ["dark", "glass", "night", "sunset", "sea", "dawn"];
    // Four solid accents and four gradients; "teal" is called green in the interface and "coral"
    // orange, because the file carries the identifier and renaming it would need a migration.
    internal static IReadOnlyList<string> Accents { get; } =
        ["blue", "teal", "violet", "coral", "blue-violet", "orange-rose", "green-cyan", "amber-pink"];
    private static ResourceDictionary? _theme;
    private static ResourceDictionary? _accent;

    internal static string CurrentTheme { get; private set; } = DefaultTheme;
    internal static string CurrentAccent { get; private set; } = DefaultAccent;

    /// <summary>
    /// The palette of a theme, read without applying it: the cards of the gallery show the theme
    /// they stand for while another one is on screen.
    /// </summary>
    internal static ResourceDictionary LoadTheme(string? themeId) =>
        new() { Source = new Uri($"Themes/Palettes/{FileName(NormalizeTheme(themeId))}.xaml", UriKind.Relative) };

    internal static ResourceDictionary LoadAccent(string? accentId) =>
        new() { Source = new Uri($"Themes/Accents/{FileName(Normalize(accentId))}.xaml", UriKind.Relative) };

    internal static void Apply(string? theme, string? accent)
    {
        if (Application.Current is not { } application) return;
        var merged = application.Resources.MergedDictionaries;
        Swap(merged, LoadTheme(theme), ref _theme, "/Palettes/");
        Swap(merged, LoadAccent(accent), ref _accent, "/Accents/");
        CurrentTheme = NormalizeTheme(theme);
        CurrentAccent = Normalize(accent);
    }

    // The dictionary merged from App.xaml is the one replaced on the first call; every call after
    // that replaces the one this service put there, so the list never grows a second palette.
    private static void Swap(Collection<ResourceDictionary> merged, ResourceDictionary dictionary, ref ResourceDictionary? current, string folder)
    {
        var index = current is not null
            ? merged.IndexOf(current)
            : merged.ToList().FindIndex(entry => entry.Source?.OriginalString.Contains(folder, StringComparison.OrdinalIgnoreCase) == true);
        if (index >= 0) merged[index] = dictionary; else merged.Add(dictionary);
        current = dictionary;
    }

    internal static string NormalizeTheme(string? themeId) =>
        Themes.FirstOrDefault(theme => string.Equals(theme, themeId, StringComparison.OrdinalIgnoreCase)) ?? DefaultTheme;

    internal static string Normalize(string? accentId) =>
        Accents.FirstOrDefault(accent => string.Equals(accent, accentId, StringComparison.OrdinalIgnoreCase)) ?? DefaultAccent;

    // "blue-violet" is one identifier and one file: BlueViolet.xaml.
    private static string FileName(string id) =>
        string.Concat(id.Split('-').Select(part => string.Concat(char.ToUpperInvariant(part[0]), part[1..])));
}
