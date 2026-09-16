using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace Snapik.App;

/// <summary>
/// The pinned icon an installation over SnapBrief 1.4.0 leaves behind. The taskbar keeps the order
/// of its buttons as a list of PIDLs, and a PIDL points at a file by its path, so the shortcut is
/// aimed at the new executable where it lies instead of being renamed: the button then starts
/// Snapik, and the pin itself survives. The price is its caption, which stays "SnapBrief" until the
/// user pins the application again by hand; losing the pin would be the worse of the two.
/// </summary>
internal static class TaskbarPinLegacy
{
    /// <summary>The name the pinned shortcut of SnapBrief 1.4.0 carries.</summary>
    internal const string LegacyShortcutName = "SnapBrief.lnk";

    /// <summary>
    /// The identity of the application, and the only place it is written out. The shortcuts of the
    /// installer carry the same value; <c>TaskbarPinService.AppUserModelId</c> is this constant
    /// under its own name. It lives here and not there because this file is read by the tests, and
    /// the service beside it cannot be.
    /// </summary>
    internal const string AppUserModelId = "YesWorkflow.Snapik";

    /// <summary>
    /// The pinned shortcut to carry over, or null when there is nothing to do. There is nothing to
    /// do when the old pin is not there, and there is nothing to do when our own pin is there
    /// beside it either: aiming the old one at the same application would leave two buttons opening
    /// it, and the second cannot be removed by any program. That case is the one the wizard has a
    /// line of text for.
    /// </summary>
    internal static string? ChooseLegacyPin(IReadOnlyList<string> pinned, string currentName, string legacyName)
    {
        string? legacy = null;
        foreach (var path in pinned)
        {
            var name = Path.GetFileName(path);
            if (string.Equals(name, currentName, StringComparison.OrdinalIgnoreCase)) return null;
            if (string.Equals(name, legacyName, StringComparison.OrdinalIgnoreCase)) legacy = path;
        }
        return legacy;
    }

    /// <summary>
    /// Whether a pinned shortcut is ours. By its name, as before, and now also by what it holds: a
    /// carried-over pin keeps the name of the old application and opens this one, and a pin that
    /// carries our identity is ours whatever it is called.
    /// </summary>
    internal static bool IsOurs(string fileName, string? target, string? appId, string? processPath)
    {
        var ourName = $"{Path.GetFileNameWithoutExtension(processPath) ?? "Snapik"}.lnk";
        if (string.Equals(fileName, ourName, StringComparison.OrdinalIgnoreCase)) return true;
        if (!string.IsNullOrEmpty(processPath) && !string.IsNullOrEmpty(target) &&
            string.Equals(target, processPath, StringComparison.OrdinalIgnoreCase)) return true;
        return string.Equals(appId, AppUserModelId, StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>What a shortcut opens and under which identity; both are null when it cannot be read.</summary>
    internal static (string? Target, string? AppId) ReadShortcut(string path)
    {
        try
        {
            var link = (IShellLink)new ShellLink();
            ((IPersistFile)link).Load(path, StgmRead);
            var target = new StringBuilder(260);
            link.GetPath(target, target.Capacity, IntPtr.Zero, 0);
            return (target.Length > 0 ? target.ToString() : null, ReadAppId((IPropertyStore)link));
        }
        // A shortcut Explorer holds open, or one that is not a shortcut at all, is simply not read.
        catch (Exception) { return (null, null); }
    }

    /// <summary>
    /// Aims an existing shortcut at this application without renaming it, and tells the shell that
    /// the file changed. Whether the taskbar shows it at once is the shell's own business: the icon
    /// and the caption of a pinned button are cached, and sometimes only a new session refreshes them.
    /// </summary>
    internal static bool Retarget(string path, string exePath, string appId) => Aim(path, exePath, appId, existing: true);

    /// <summary>
    /// Writes a shortcut where there is none. The carry-over itself never creates one — the pin it
    /// works on is the one already on the taskbar — but the smoke run needs a shortcut of its own to
    /// carry over, and building it here is what makes that check a check of this code.
    /// </summary>
    internal static bool WriteShortcut(string path, string exePath, string appId) => Aim(path, exePath, appId, existing: false);

    private static bool Aim(string path, string exePath, string appId, bool existing)
    {
        try
        {
            var link = (IShellLink)new ShellLink();
            var file = (IPersistFile)link;
            if (existing) file.Load(path, StgmReadWrite);
            link.SetPath(exePath);
            link.SetIconLocation(exePath, 0);
            link.SetWorkingDirectory(Path.GetDirectoryName(exePath) ?? string.Empty);
            WriteAppId((IPropertyStore)link, appId);
            file.Save(path, true);
            SHChangeNotify(ShcneUpdateItem, ShcnfPath | ShcnfFlush, path, IntPtr.Zero);
            return true;
        }
        catch (Exception) { return false; }
    }

    /// <summary>
    /// The one step of the start: if the old pin is there and ours is not, the old one is aimed at
    /// this application. Everything here is best effort — a pin that cannot be carried over leaves
    /// the wizard to say so in words.
    /// </summary>
    internal static void CarryOverPin()
    {
        try
        {
            var exePath = Environment.ProcessPath;
            if (string.IsNullOrEmpty(exePath)) return;
            var currentName = $"{Path.GetFileNameWithoutExtension(exePath)}.lnk";
            if (ChooseLegacyPin(PinnedShortcuts(), currentName, LegacyShortcutName) is not { } legacy) return;
            Retarget(legacy, exePath, AppUserModelId);
        }
        catch (Exception) { }
    }

    // The same folder TaskbarPinService reads: what the shell keeps pinned, as files.
    private static IReadOnlyList<string> PinnedShortcuts()
    {
        try
        {
            var folder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                "Microsoft", "Internet Explorer", "Quick Launch", "User Pinned", "TaskBar");
            return Directory.Exists(folder) ? Directory.GetFiles(folder, "*.lnk") : [];
        }
        catch (Exception) { return []; }
    }

    private static string? ReadAppId(IPropertyStore store)
    {
        var key = AppUserModelIdKey;
        store.GetValue(ref key, out var value);
        try { return value.ValueType == VtLpwstr ? Marshal.PtrToStringUni(value.Value) : null; }
        finally { PropVariantClear(ref value); }
    }

    private static void WriteAppId(IPropertyStore store, string appId)
    {
        var key = AppUserModelIdKey;
        var value = new PropVariant { ValueType = VtLpwstr, Value = Marshal.StringToCoTaskMemUni(appId) };
        try
        {
            store.SetValue(ref key, ref value);
            store.Commit();
        }
        finally { PropVariantClear(ref value); }
    }

    private const uint StgmRead = 0x00000000;
    private const uint StgmReadWrite = 0x00000002;
    private const ushort VtLpwstr = 31;
    private const uint ShcneUpdateItem = 0x00002000;
    private const uint ShcnfPath = 0x0001;
    private const uint ShcnfFlush = 0x1000;

    // System.AppUserModel.ID, the identity a pinned shortcut and the running window have to share.
    private static readonly PropertyKey AppUserModelIdKey =
        new() { FormatId = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), PropertyId = 5 };

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern void SHChangeNotify(uint eventId, uint flags,
        [MarshalAs(UnmanagedType.LPWStr)] string item, IntPtr second);

    [DllImport("ole32.dll")]
    private static extern int PropVariantClear(ref PropVariant value);

    [StructLayout(LayoutKind.Sequential)]
    private struct PropertyKey
    {
        public Guid FormatId;
        public uint PropertyId;
    }

    // PROPVARIANT: the kind of the value, then six bytes the header pads with, then the value
    // itself. The offsets are written out rather than left to the packing rules, because the union
    // starts at eight on both architectures while a sequential layout would move it on one of them.
    [StructLayout(LayoutKind.Explicit, Size = 24)]
    private struct PropVariant
    {
        [FieldOffset(0)] public ushort ValueType;
        [FieldOffset(8)] public IntPtr Value;
    }

    [ComImport, Guid("00021401-0000-0000-C000-000000000046")]
    private class ShellLink { }

    // The slots are written out in full and in order: the interface is reached through its vtable,
    // and a missing one would call the wrong method.
    [ComImport, Guid("000214F9-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IShellLink
    {
        void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder file, int length, IntPtr findData, uint flags);
        void GetIDList(out IntPtr list);
        void SetIDList(IntPtr list);
        void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder name, int length);
        void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string name);
        void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder directory, int length);
        void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string directory);
        void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder arguments, int length);
        void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string arguments);
        void GetHotkey(out short hotkey);
        void SetHotkey(short hotkey);
        void GetShowCmd(out int show);
        void SetShowCmd(int show);
        void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder icon, int length, out int index);
        void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string icon, int index);
        void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string path, uint reserved);
        void Resolve(IntPtr window, uint flags);
        void SetPath([MarshalAs(UnmanagedType.LPWStr)] string path);
    }

    [ComImport, Guid("0000010B-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IPersistFile
    {
        void GetClassID(out Guid classId);
        [PreserveSig] int IsDirty();
        void Load([MarshalAs(UnmanagedType.LPWStr)] string fileName, uint mode);
        void Save([MarshalAs(UnmanagedType.LPWStr)] string? fileName, [MarshalAs(UnmanagedType.Bool)] bool remember);
        void SaveCompleted([MarshalAs(UnmanagedType.LPWStr)] string fileName);
        void GetCurFile([MarshalAs(UnmanagedType.LPWStr)] out string fileName);
    }

    [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IPropertyStore
    {
        void GetCount(out uint count);
        void GetAt(uint index, out PropertyKey key);
        void GetValue(ref PropertyKey key, out PropVariant value);
        void SetValue(ref PropertyKey key, ref PropVariant value);
        void Commit();
    }
}
