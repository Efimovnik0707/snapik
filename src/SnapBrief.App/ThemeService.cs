using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;

namespace SnapBrief.App;

/// <summary>
/// Swaps the accent dictionary in the application resources. The windows read the accent through
/// DynamicResource, so replacing the dictionary repaints them without rebuilding anything. Only the
/// dark theme exists in this phase; the parameter is kept so the call sites already pass it.
/// </summary>
internal static class ThemeService
{
    internal const string DefaultTheme = "dark";
    internal const string DefaultAccent = "blue";
    // Placeholder accents until the palettes from the designer arrive.
    internal static IReadOnlyList<string> Accents { get; } = ["blue", "teal", "violet", "coral"];
    private static ResourceDictionary? _accent;

    internal static string CurrentTheme { get; private set; } = DefaultTheme;
    internal static string CurrentAccent { get; private set; } = DefaultAccent;

    internal static ResourceDictionary Load(string? accentId) =>
        new() { Source = new Uri($"Themes/Accents/{FileName(accentId)}.xaml", UriKind.Relative) };

    internal static void Apply(string? theme, string? accentId)
    {
        if (Application.Current is not { } application) return;
        var dictionary = Load(accentId);
        var merged = application.Resources.MergedDictionaries;
        // The dictionary merged from App.xaml is the one replaced on the first call.
        var index = _accent is not null
            ? merged.IndexOf(_accent)
            : merged.ToList().FindIndex(entry => entry.Source?.OriginalString.Contains("/Accents/", StringComparison.OrdinalIgnoreCase) == true);
        if (index >= 0) merged[index] = dictionary; else merged.Add(dictionary);
        _accent = dictionary;
        // Phase 1 has one theme: anything stored in the settings resolves to "dark".
        CurrentTheme = DefaultTheme;
        CurrentAccent = Normalize(accentId);
    }

    internal static string Normalize(string? accentId) =>
        Accents.FirstOrDefault(accent => string.Equals(accent, accentId, StringComparison.OrdinalIgnoreCase)) ?? DefaultAccent;

    private static string FileName(string? accentId)
    {
        var accent = Normalize(accentId);
        return string.Concat(char.ToUpperInvariant(accent[0]), accent[1..]);
    }
}
