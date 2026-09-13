namespace SnapBrief.App;

/// <summary>
/// What a stored shortcut id is allowed to say. An id is either the name of a preset or
/// "custom:{modifiers}:{virtualKey}", and the rules live apart from the settings window so that
/// they can be read, and tested, without a window behind them.
/// </summary>
internal static class HotkeyRules
{
    /// <summary>
    /// The two keys that are a shortcut on their own: Print Screen and Pause. Everything else needs
    /// Ctrl, Alt, Shift or Win, because a shortcut is registered globally: a key pressed alone is
    /// taken away from every other application on the machine, and a bare arrow leaves nothing to
    /// move a cursor with.
    /// </summary>
    internal static bool IsShortcutOnItsOwn(ushort virtualKey) => virtualKey is 0x2C or 0x13;

    /// <summary>
    /// Reads a custom id from the settings file. False means the file holds something that must not
    /// be registered: a malformed id, a key outside the range, a modifier bit nothing maps to, or a
    /// key pressed alone that is not one of the two above. The caller answers with the default
    /// shortcut, and that is how a bare arrow recorded by an older build is undone, without the
    /// read having to write anything back.
    /// </summary>
    internal static bool TryParseCustom(string id, out uint modifiers, out ushort virtualKey)
    {
        modifiers = 0;
        virtualKey = 0;
        var parts = id.Split(':');
        if (parts.Length != 3 || parts[0] != "custom") return false;
        if (!uint.TryParse(parts[1], out var storedModifiers) || (storedModifiers & ~15u) != 0) return false;
        if (!uint.TryParse(parts[2], out var storedKey) || storedKey is 0 or >= 255) return false;
        if (storedModifiers == 0 && !IsShortcutOnItsOwn((ushort)storedKey)) return false;
        modifiers = storedModifiers;
        virtualKey = (ushort)storedKey;
        return true;
    }
}
