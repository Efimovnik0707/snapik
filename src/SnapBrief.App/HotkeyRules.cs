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
    /// Ctrl, Alt, Shift and Win, in every form Windows names them: they are what a shortcut is held
    /// together with, never what it ends with. Releasing one of them while another is still down
    /// used to write it in as the key of the shortcut, and "Ctrl + LeftShift" then answered every
    /// Ctrl+Shift on the machine.
    /// </summary>
    internal static bool IsModifierKey(ushort virtualKey) =>
        virtualKey is 0x10 or 0x11 or 0x12 or 0x5B or 0x5C or (>= 0xA0 and <= 0xA5);

    /// <summary>
    /// Reads a custom id from the settings file. False means the file holds something that must not
    /// be registered: a malformed id, a key outside the range, a modifier bit nothing maps to, a
    /// modifier standing where the key of the shortcut belongs, or a key pressed alone that is not
    /// one of the two above. The caller answers with the default
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
        if (IsModifierKey((ushort)storedKey)) return false;
        if (storedModifiers == 0 && !IsShortcutOnItsOwn((ushort)storedKey)) return false;
        modifiers = storedModifiers;
        virtualKey = (ushort)storedKey;
        return true;
    }
}
