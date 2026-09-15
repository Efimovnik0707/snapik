using System;

namespace Snapik.App;

/// <summary>
/// What the two save dialogs are named and filtered with. Both rules are pure so they can be
/// tested without a window: the file dialog of a single capture and the package folder picker.
/// </summary>
internal static class SaveNaming
{
    /// <summary>How many names with a suffix are tried before the save gives up on the folder.</summary>
    internal const int NameAttempts = 100;

    /// <summary>
    /// A name nothing is saved under yet: the one that was asked for, or the same name with "-2",
    /// "-3" … after it. Null means every attempt is taken and the user has to pick another folder.
    /// The check is done once, before the first file is copied, so a package never lands half
    /// written next to files of another one.
    /// </summary>
    internal static string? FreeName(string baseName, Func<string, bool> taken)
    {
        if (!taken(baseName)) return baseName;
        for (var attempt = 2; attempt <= NameAttempts; attempt++)
        {
            var candidate = $"{baseName}-{attempt}";
            if (!taken(candidate)) return candidate;
        }

        return null;
    }

    /// <summary>
    /// The filter of the "save the capture" dialog. Its first line is "all supported", so saving
    /// does not start with a choice of format, and the patterns in it are ordered by the preferred
    /// format: the dialog appends the extension of the first one.
    /// </summary>
    internal static string ImageFilter(string saveFormat, string allSupportedCaption)
    {
        var supported = saveFormat == "jpeg" ? "*.jpg;*.jpeg;*.png" : "*.png;*.jpg;*.jpeg";
        return $"{allSupportedCaption} ({supported})|{supported}|PNG (*.png)|*.png|JPEG (*.jpg;*.jpeg)|*.jpg;*.jpeg";
    }
}
