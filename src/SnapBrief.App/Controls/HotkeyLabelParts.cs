using System;

namespace SnapBrief.App.Controls;

internal static class HotkeyLabelParts
{
    // HotkeySettings.Find builds the label as "Ctrl + Alt + S", and the field shows one capsule per
    // part. Key names that carry their own spaces ("Print Screen", "Pause / Break") stay one key.
    internal static string[] Split(string? label) =>
        string.IsNullOrWhiteSpace(label)
            ? []
            : label.Split(" + ", StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
}
