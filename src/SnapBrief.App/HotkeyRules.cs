using System.Collections.Generic;
using System.Linq;
using System.Windows.Input;

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

    /// <summary>
    /// The combinations Windows answers before any application does, so recording one would give a
    /// shortcut that never fires: anything held with Win (which covers Win+Shift+S), Ctrl+Alt+Delete,
    /// Alt+Tab, Alt+F4 and Ctrl+Escape.
    ///
    /// Print Screen on its own is deliberately not on this list. Windows 11 hands it to the snipping
    /// tool, but it is also the first shortcut the wizard offers for "save the whole screen", and a
    /// suggestion that the rules refuse would be a suggestion the user cannot accept. It is refused
    /// where it fails, by the registration, and not before.
    ///
    /// The macOS port answers the same question with a list of its own: Cmd+Shift+3, Cmd+Shift+4,
    /// Cmd+Shift+5, Cmd+Tab and Cmd+Space. It is written down here so that the port carries it
    /// alongside this function rather than inventing one.
    /// </summary>
    internal static bool IsSystemReserved(ModifierKeys modifiers, int virtualKey)
    {
        if (modifiers.HasFlag(ModifierKeys.Windows)) return true;
        var control = modifiers.HasFlag(ModifierKeys.Control);
        var alt = modifiers.HasFlag(ModifierKeys.Alt);
        if (control && alt && virtualKey == 0x2E) return true;
        if (alt && virtualKey is 0x09 or 0x73) return true;
        return control && virtualKey == 0x1B;
    }

    /// <summary>
    /// Whether two stored ids stand for the same combination. Compared as the combination they parse
    /// to, not as text: "print-screen" and "custom:0:44" are one shortcut written two ways, and a
    /// window comparing the strings would let both be assigned at once.
    /// </summary>
    internal static bool SameGesture(string? idA, string? idB) =>
        TryParse(idA, out var modifiersA, out var keyA) &&
        TryParse(idB, out var modifiersB, out var keyB) &&
        modifiersA == modifiersB && keyA == keyB;

    /// <summary>
    /// The first combination of the queue that nothing holds and Windows does not answer first, or
    /// null when every one of them is taken. What the "suggest" chip beside an unassigned shortcut
    /// offers, so that the user is never asked to invent one.
    /// </summary>
    internal static string? SuggestFree(IEnumerable<string> taken)
    {
        var held = taken.ToArray();
        return Candidates.FirstOrDefault(candidate =>
            TryParse(candidate, out var modifiers, out var key) &&
            !IsSystemReserved(modifiers, key) &&
            !held.Any(id => SameGesture(id, candidate)));
    }

    /// <summary>The order the chip offers a free combination in.</summary>
    private static readonly string[] Candidates = ["print-screen", "custom:7:83", "ctrl-shift-s", "alt-s"];

    // The presets, spelled out here rather than read from HotkeySettings: this file is compiled into
    // the test project on its own, and the settings record does not come with it. The two lists are
    // the same seven ids; a preset added there has to be added here.
    private static readonly Dictionary<string, (ModifierKeys Modifiers, int Key)> Presets = new()
    {
        ["ctrl-alt-s"] = (ModifierKeys.Control | ModifierKeys.Alt, 0x53),
        ["ctrl-shift-s"] = (ModifierKeys.Control | ModifierKeys.Shift, 0x53),
        ["alt-s"] = (ModifierKeys.Alt, 0x53),
        ["print-screen"] = (ModifierKeys.None, 0x2C),
        ["ctrl-alt-v"] = (ModifierKeys.Control | ModifierKeys.Alt, 0x56),
        ["ctrl-shift-v"] = (ModifierKeys.Control | ModifierKeys.Shift, 0x56),
        ["alt-v"] = (ModifierKeys.Alt, 0x56)
    };

    // The modifier bits of a stored id are the Win32 ones, and ModifierKeys carries the same four in
    // the same places: Alt 1, Control 2, Shift 4, Windows 8.
    private static bool TryParse(string? id, out ModifierKeys modifiers, out int virtualKey)
    {
        modifiers = ModifierKeys.None;
        virtualKey = 0;
        if (id is null) return false;
        if (Presets.TryGetValue(id, out var preset))
        {
            (modifiers, virtualKey) = preset;
            return true;
        }
        if (!TryParseCustom(id, out var storedModifiers, out var storedKey)) return false;
        modifiers = (ModifierKeys)storedModifiers;
        virtualKey = storedKey;
        return true;
    }
}
