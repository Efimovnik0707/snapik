using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Windows.Interop;

namespace Snapik.Windows;

public sealed partial class WindowsGlobalHotkeyService : IGlobalHotkeyService
{
    private const int HotkeyMessage = 0x0312;
    private readonly nint windowHandle;
    private readonly HwndSource source;
    private readonly Dictionary<string, int> idsByName = new(StringComparer.Ordinal);
    private readonly Dictionary<int, string> namesById = [];
    private int nextId = 0x4000;
    private bool disposed;

    public WindowsGlobalHotkeyService(nint messageWindowHandle)
    {
        if (messageWindowHandle == 0) throw new ArgumentException("A created WPF window handle is required.", nameof(messageWindowHandle));
        windowHandle = messageWindowHandle;
        source = HwndSource.FromHwnd(windowHandle) ?? throw new InvalidOperationException("The handle does not belong to a WPF HwndSource.");
        source.AddHook(WindowProcedure);
    }

    public event EventHandler<GlobalHotkeyPressed>? Pressed;

    public void Register(string id, HotkeyGesture gesture)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        if (string.IsNullOrWhiteSpace(id)) throw new ArgumentException("A hotkey id is required.", nameof(id));
        if (idsByName.ContainsKey(id)) throw new InvalidOperationException($"Hotkey '{id}' is already registered.");
        var nativeId = checked(nextId++);
        if (!RegisterHotKey(windowHandle, nativeId, (uint)gesture.Modifiers, gesture.VirtualKey))
            throw new Win32Exception(Marshal.GetLastWin32Error(), $"Could not register global hotkey '{id}'.");
        idsByName.Add(id, nativeId);
        namesById.Add(nativeId, id);
    }

    public void Unregister(string id)
    {
        if (!idsByName.Remove(id, out var nativeId)) return;
        namesById.Remove(nativeId);
        _ = UnregisterHotKey(windowHandle, nativeId);
    }

    private nint WindowProcedure(nint hwnd, int message, nint wParam, nint lParam, ref bool handled)
    {
        if (message == HotkeyMessage && namesById.TryGetValue(wParam.ToInt32(), out var id))
        {
            handled = true;
            Pressed?.Invoke(this, new GlobalHotkeyPressed(id));
        }
        return 0;
    }

    public void Dispose()
    {
        if (disposed) return;
        disposed = true;
        foreach (var nativeId in namesById.Keys.ToArray()) _ = UnregisterHotKey(windowHandle, nativeId);
        idsByName.Clear();
        namesById.Clear();
        source.RemoveHook(WindowProcedure);
    }

    [LibraryImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool RegisterHotKey(nint hWnd, int id, uint modifiers, uint virtualKey);

    [LibraryImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool UnregisterHotKey(nint hWnd, int id);
}
