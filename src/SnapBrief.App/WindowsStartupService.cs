using System;
using System.IO;
using Microsoft.Win32;

namespace SnapBrief.App;

internal static class WindowsStartupService
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "SnapBrief";

    private static string LaunchCommand => $"\"{Path.GetFullPath(Environment.ProcessPath ?? throw new InvalidOperationException("Не найден путь приложения."))}\"";

    internal static bool IsEnabled()
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunKey);
        return string.Equals(key?.GetValue(ValueName) as string, LaunchCommand, StringComparison.OrdinalIgnoreCase);
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
