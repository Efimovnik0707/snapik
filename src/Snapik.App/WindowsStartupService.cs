using System;
using System.IO;
using Microsoft.Win32;

namespace Snapik.App;

internal static class WindowsStartupService
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "Snapik";

    // legacy: up to version 1.4.0 the application wrote its autostart under the name SnapBrief.
    private const string LegacyValueName = "SnapBrief";

    private static string LaunchCommand => $"\"{Path.GetFullPath(Environment.ProcessPath ?? throw new InvalidOperationException("Не найден путь приложения."))}\"";

    internal static bool IsEnabled()
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunKey);
        return string.Equals(key?.GetValue(ValueName) as string, LaunchCommand, StringComparison.OrdinalIgnoreCase);
    }

    /// Called once at startup: an installation over SnapBrief 1.4.0 leaves the autostart of the
    /// old name behind, pointing at an executable that is gone. The entry is dropped, and because
    /// its presence is what "autostart is on" means here, the new one takes its place.
    internal static void CarryOverLegacyValue()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey, writable: true);
            if (key is null) return;
            if (key.GetValue(LegacyValueName) is not string legacy || string.IsNullOrWhiteSpace(legacy)) return;
            key.DeleteValue(LegacyValueName, throwOnMissingValue: false);
            if (key.GetValue(ValueName) is null) key.SetValue(ValueName, LaunchCommand, RegistryValueKind.String);
        }
        catch
        {
            // Autostart of the older name is a convenience, never a reason not to start.
        }
    }

    internal static void SetEnabled(bool enabled)
    {
        using var key = Registry.CurrentUser.CreateSubKey(RunKey, writable: true)
            ?? throw new IOException("Не удалось открыть настройки автозапуска Windows.");
        if (enabled) key.SetValue(ValueName, LaunchCommand, RegistryValueKind.String);
        else if (string.Equals(key.GetValue(ValueName) as string, LaunchCommand, StringComparison.OrdinalIgnoreCase))
            key.DeleteValue(ValueName, throwOnMissingValue: false);
    }
}
