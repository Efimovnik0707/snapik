using System;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using System.Threading;
using System.Threading.Tasks;

namespace Snapik.App;

/// <summary>
/// Putting the icon on the taskbar, which Windows has no single way of doing. There are three paths
/// and the build number chooses between them: from 26100.7705 the WinRT <c>TaskbarManager</c> asks
/// the user with a dialog of its own; below 26052 the undocumented shell interface
/// <c>IPinnedList3</c> still works; in between, and whenever anything at all refuses, the step shows
/// the three lines of the manual way instead. Nothing here throws at the caller and nothing here
/// promises: the result is read back from the system, never from the return code of the call.
/// </summary>
internal static class TaskbarPinService
{
    /// <summary>
    /// The identity of the application, the one string this is written in. The shortcuts of the
    /// installer carry the same value in <c>System.AppUserModel.ID</c>; without that, the pinned
    /// icon and the running window are two different applications to the taskbar.
    /// </summary>
    internal const string AppUserModelId = "YesWorkflow.Snapik";

    /// <summary>Set this to "off" to walk the branch where pinning fails, without breaking anything.</summary>
    private const string OverrideVariable = "SNAPIK_TASKBAR_PIN";

    internal enum PinResult
    {
        /// <summary>The icon was already on the taskbar before the button was pressed.</summary>
        AlreadyPinned,
        /// <summary>The icon is on the taskbar because of this call.</summary>
        Pinned,
        /// <summary>Nothing was pinned, whatever the reason: the step shows the manual way.</summary>
        Unavailable
    }

    /// <summary>
    /// Names the process to the shell before any window of it exists. Called once at startup: after
    /// a window is created the identity is already taken and the call changes nothing.
    /// </summary>
    internal static void NameThisProcess(Action<string>? trace = null)
    {
        try { SetCurrentProcessExplicitAppUserModelID(AppUserModelId); }
        catch (Exception ex) { trace?.Invoke($"Taskbar identity: {ex}"); }
    }

    /// <summary>
    /// Whether the button is worth showing at all. A policy that forbids pinning, a build between the
    /// two paths, a smoke run or a demo: the step goes straight to the three lines, and the user is
    /// never offered a button that cannot work.
    /// </summary>
    internal static bool CanTry() => !TurnedOff() && !BlockedByPolicy() && (SupportsTaskbarManager() || SupportsPinnedList());

    /// <summary>
    /// Whether the icon is on the taskbar already, read from the folder the shell keeps it in. A
    /// smoke run, a demo and the override answer "not pinned" without looking: the probe has to see
    /// the same step on every machine, pinned icon or not.
    /// </summary>
    internal static bool IsPinned() => !TurnedOff() && PinnedShortcuts().Any(IsOurShortcut);

    /// <summary>
    /// Tries once, and answers with what the system says afterwards rather than with an HRESULT: on
    /// 24H2 the old interface returns S_OK and pins nothing.
    /// </summary>
    internal static async Task<PinResult> TryPinAsync(Action<string>? trace = null)
    {
        try
        {
            if (TurnedOff() || BlockedByPolicy()) return PinResult.Unavailable;
            if (IsPinned()) return PinResult.AlreadyPinned;
            if (SupportsTaskbarManager() && OperatingSystem.IsWindowsVersionAtLeast(10, 0, 26100))
                return await RequestThroughTaskbarManagerAsync(trace).ConfigureAwait(true);
            if (SupportsPinnedList()) return await PinThroughPinnedListAsync(trace).ConfigureAwait(true);
            return PinResult.Unavailable;
        }
        catch (Exception ex)
        {
            trace?.Invoke($"Taskbar pin: {ex}");
            return PinResult.Unavailable;
        }
    }

    // A smoke run and a demo must not touch COM or WinRT: the build agent would end up pinning icons.
    private static bool TurnedOff()
    {
        if (string.Equals(Environment.GetEnvironmentVariable(OverrideVariable), "off", StringComparison.OrdinalIgnoreCase)) return true;
        var arguments = Environment.GetCommandLineArgs();
        return arguments.Any(argument =>
            argument.Equals("--smoke-test", StringComparison.OrdinalIgnoreCase) ||
            argument.Equals("--demo", StringComparison.OrdinalIgnoreCase));
    }

    // The policy of a managed machine, in either hive: pinning is simply not allowed there.
    private static bool BlockedByPolicy()
    {
        foreach (var root in new[] { Microsoft.Win32.Registry.CurrentUser, Microsoft.Win32.Registry.LocalMachine })
        {
            try
            {
                using var key = root.OpenSubKey(@"Software\Policies\Microsoft\Windows\Explorer");
                if (key?.GetValue("NoPinningToTaskbar") is int forbidden && forbidden != 0) return true;
            }
            catch (Exception) { }
        }
        return false;
    }

    // KB5074105 (26100.7705 and 26200.7705) is where an application without a package of its own is
    // allowed to ask; the update also removed the token the API used to need.
    private static bool SupportsTaskbarManager() =>
        OperatingSystem.IsWindowsVersionAtLeast(10, 0, 26100) && Revision() >= 7705;

    // Every build from 26052 on returns success and pins nothing, so the old interface is only tried
    // below it: Windows 10 22H2 and Windows 11 up to 23H2.
    private static bool SupportsPinnedList() => Environment.OSVersion.Version.Build < 26052;

    // The fourth number of the version, which Environment.OSVersion leaves at zero on Windows.
    private static int Revision()
    {
        try
        {
            using var key = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion");
            return key?.GetValue("UBR") is int revision ? revision : 0;
        }
        catch (Exception) { return 0; }
    }

    [SupportedOSPlatform("windows10.0.26100.0")]
    private static async Task<PinResult> RequestThroughTaskbarManagerAsync(Action<string>? trace)
    {
        global::Windows.UI.Shell.TaskbarManager manager;
        try { manager = global::Windows.UI.Shell.TaskbarManager.GetDefault(); }
        catch (Exception ex)
        {
            trace?.Invoke($"Taskbar manager: {ex}");
            return PinResult.Unavailable;
        }
        if (!manager.IsSupported || !manager.IsPinningAllowed) return PinResult.Unavailable;
        if (await manager.IsCurrentAppPinnedAsync()) return PinResult.AlreadyPinned;
        // The shortcut of the Start menu is what carries the identity of the application, and the
        // shell needs a moment to see a freshly installed one; asking before it does is refused.
        await WaitForStartMenuShortcutAsync().ConfigureAwait(true);
        // The system shows its own "pin?" dialog here, and that cannot be gone around.
        var requested = await manager.RequestPinCurrentAppAsync();
        if (!requested) return PinResult.Unavailable;
        return await manager.IsCurrentAppPinnedAsync() || IsPinned() ? PinResult.Pinned : PinResult.Unavailable;
    }

    // The old way: the pin list of the taskband, asked for the shortcut of the Start menu. It lives on
    // a thread of its own, because shell COM is free to hang, and the wizard is not.
    private static async Task<PinResult> PinThroughPinnedListAsync(Action<string>? trace)
    {
        var shortcut = StartMenuShortcut();
        if (shortcut is null) return PinResult.Unavailable;
        var before = PinnedShortcuts().Count;
        var worker = new Thread(() =>
        {
            var pidl = IntPtr.Zero;
            object? list = null;
            try
            {
                pidl = ILCreateFromPathW(shortcut);
                if (pidl == IntPtr.Zero) return;
                var type = Type.GetTypeFromCLSID(TaskbandPin);
                if (type is null) return;
                list = Activator.CreateInstance(type);
                // 4 is the caller Explorer names itself with; the interface takes "unpin" first.
                ((IPinnedList3)list!).Modify(IntPtr.Zero, pidl, 4);
            }
            catch (Exception ex) { trace?.Invoke($"Taskbar pin list: {ex}"); }
            finally
            {
                if (list is not null) Marshal.ReleaseComObject(list);
                if (pidl != IntPtr.Zero) ILFree(pidl);
            }
        });
        worker.SetApartmentState(ApartmentState.STA);
        worker.IsBackground = true;
        worker.Start();
        await Task.Run(() => worker.Join(TimeSpan.FromSeconds(3))).ConfigureAwait(true);
        // Explorer writes the shortcut after the call returns, so the answer is polled for.
        for (var attempt = 0; attempt < 15; attempt++)
        {
            if (IsPinned()) return PinResult.Pinned;
            if (PinnedShortcuts().Count > before) return PinResult.Pinned;
            await Task.Delay(200).ConfigureAwait(true);
        }
        return PinResult.Unavailable;
    }

    private static async Task WaitForStartMenuShortcutAsync()
    {
        for (var attempt = 0; attempt < 15 && StartMenuShortcut() is null; attempt++)
            await Task.Delay(200).ConfigureAwait(true);
    }

    // The shortcut the installer puts into the Start menu; a build run from its own folder has none,
    // and then there is nothing to pin by name.
    private static string? StartMenuShortcut()
    {
        try
        {
            var name = ShortcutName();
            foreach (var folder in new[] { Environment.SpecialFolder.Programs, Environment.SpecialFolder.CommonPrograms })
            {
                var path = Path.Combine(Environment.GetFolderPath(folder), name);
                if (File.Exists(path)) return path;
            }
        }
        catch (Exception) { }
        return null;
    }

    // Where the shell keeps what is pinned. The folder is the only honest answer: the registry value
    // beside it is written lazily and is undocumented.
    private static System.Collections.Generic.IReadOnlyList<string> PinnedShortcuts()
    {
        try
        {
            var folder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                "Microsoft", "Internet Explorer", "Quick Launch", "User Pinned", "TaskBar");
            return Directory.Exists(folder) ? Directory.GetFiles(folder, "*.lnk") : [];
        }
        catch (Exception) { return []; }
    }

    private static bool IsOurShortcut(string path) =>
        string.Equals(Path.GetFileName(path), ShortcutName(), StringComparison.OrdinalIgnoreCase);

    private static string ShortcutName() =>
        $"{Path.GetFileNameWithoutExtension(Environment.ProcessPath) ?? "Snapik"}.lnk";

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern void SetCurrentProcessExplicitAppUserModelID([MarshalAs(UnmanagedType.LPWStr)] string appId);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr ILCreateFromPathW([MarshalAs(UnmanagedType.LPWStr)] string path);

    [DllImport("shell32.dll")]
    private static extern void ILFree(IntPtr pidl);

    private static readonly Guid TaskbandPin = new("90AA3A4E-1CBA-4233-B8BB-535773D48449");

    // The slots before Modify are inherited and are never called here; they are written out because
    // the interface is reached through its vtable, and a missing slot would call the wrong method.
    [ComImport, Guid("0DD79AE2-D156-45D4-9EEB-3B549769E940"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IPinnedList3
    {
        [PreserveSig] int EnumObjects(out IntPtr objects);
        [PreserveSig] int GetPinnableInfo(IntPtr pidl, uint first, uint second, IntPtr third, IntPtr fourth);
        [PreserveSig] int IsPinnable(IntPtr dataObject, int flag);
        [PreserveSig] int Resolve(IntPtr window, uint flags, IntPtr pidl, out IntPtr resolved);
        [PreserveSig] int LegacyModify(IntPtr from, IntPtr to);
        [PreserveSig] int GetChangeCount(out int count);
        [PreserveSig] int IsPinned(IntPtr pidl);
        [PreserveSig] int GetPinnedItem(IntPtr pidl, out IntPtr pinned);
        [PreserveSig] int GetAppIDForPinnedItem(IntPtr pidl, IntPtr appId);
        [PreserveSig] int ItemChangeNotify(IntPtr from, IntPtr to);
        [PreserveSig] int UpdateForRemovedItemsAsNecessary();
        [PreserveSig] int PinShellLink(ushort flags, IntPtr link);
        [PreserveSig] int GetPinnedItemForAppID(ushort appId, out IntPtr pidl);
        [PreserveSig] int Modify(IntPtr unpin, IntPtr pin, int caller);
    }
}
