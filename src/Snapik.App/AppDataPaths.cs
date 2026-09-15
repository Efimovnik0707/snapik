using System;
using System.IO;

namespace Snapik.App;

/// The one place that knows the default data folder of the application: settings, sessions and the
/// startup log all live under it. A run with <c>--data-dir</c> owns its own directory and never
/// comes here.
internal static class AppDataPaths
{
    private const string FolderName = "Snapik";

    // legacy: up to version 1.4.0 the application was named SnapBrief and kept exactly the same
    // folder under that name. An update has to carry it over, or the user starts with empty
    // settings and no sessions.
    private const string LegacyFolderName = "SnapBrief";

    private static string LocalAppData => Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);

    internal static string LocalRoot => Path.Combine(LocalAppData, FolderName);

    internal static string LegacyLocalRoot => Path.Combine(LocalAppData, LegacyFolderName);

    /// Called once at startup, before anything reads or creates the folder.
    internal static void CarryOverLegacyData() => CarryOverLegacyData(LegacyLocalRoot, LocalRoot);

    internal static void CarryOverLegacyData(string legacyRoot, string root)
    {
        try
        {
            if (Directory.Exists(root) || !Directory.Exists(legacyRoot)) return;
            try
            {
                // Same volume: a rename, and the old folder is gone afterwards.
                Directory.Move(legacyRoot, root);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                // Could not be moved: copy instead and leave the old folder where it is.
                CopyDirectory(legacyRoot, root);
            }
        }
        catch
        {
            // Data of the older name is a convenience, never a reason not to start.
        }
    }

    private static void CopyDirectory(string source, string destination)
    {
        Directory.CreateDirectory(destination);
        foreach (var file in Directory.GetFiles(source))
            File.Copy(file, Path.Combine(destination, Path.GetFileName(file)), overwrite: true);
        foreach (var directory in Directory.GetDirectories(source))
            CopyDirectory(directory, Path.Combine(destination, Path.GetFileName(directory)));
    }
}
