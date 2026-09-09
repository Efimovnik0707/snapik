using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Windows.Threading;

namespace SnapBrief.Windows;

public sealed partial class WindowsPasteIntentObserver : IPasteIntentObserver
{
    private const int LowLevelKeyboardHook = 13;
    private const int KeyDownMessage = 0x0100;
    private const int KeyUpMessage = 0x0101;
    private const int SystemKeyDownMessage = 0x0104;
    private const int SystemKeyUpMessage = 0x0105;
    private const uint InjectedFlag = 0x10;

    private readonly Dispatcher dispatcher;
    private readonly PasteIntentKeyState keyState = new();
    private readonly HookProcedure hookProcedure;
    private nint hookHandle;
    private bool disposed;

    public WindowsPasteIntentObserver()
    {
        dispatcher = Dispatcher.FromThread(Thread.CurrentThread)
            ?? throw new InvalidOperationException("Create the paste-intent observer on a WPF dispatcher thread.");
        hookProcedure = OnKeyboardHook;
    }

    public event EventHandler<PasteIntentObserved>? PasteIntentObserved;

    public void Start()
    {
        VerifyAccess();
        ObjectDisposedException.ThrowIf(disposed, this);
        if (hookHandle != 0) return;

        hookHandle = SetWindowsHookEx(LowLevelKeyboardHook, hookProcedure, GetModuleHandle(null), 0);
        if (hookHandle == 0)
            throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not install the passive paste-intent keyboard hook.");
    }

    public void Stop()
    {
        VerifyAccess();
        if (hookHandle == 0) return;
        var handle = hookHandle;
        hookHandle = 0;
        keyState.Reset();
        if (!UnhookWindowsHookEx(handle))
            throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not remove the passive paste-intent keyboard hook.");
    }

    private nint OnKeyboardHook(int code, nint message, nint data)
    {
        try
        {
            if (code >= 0 && TryClassifyMessage(message, out var isKeyDown))
            {
                var input = Marshal.PtrToStructure<LowLevelKeyboardInput>(data);
                var gesture = keyState.Observe(input.VirtualKey, isKeyDown, (input.Flags & InjectedFlag) != 0);
                if (gesture is { } observed)
                {
                    var foregroundWindow = GetForegroundWindow();
                    _ = GetWindowThreadProcessId(foregroundWindow, out var foregroundProcessId);
                    if (foregroundWindow != 0 && foregroundProcessId != 0 && foregroundProcessId != (uint)Environment.ProcessId)
                    {
                        PasteIntentObserved?.Invoke(this, new PasteIntentObserved(
                            observed,
                            foregroundWindow,
                            foregroundProcessId,
                            GetClipboardSequenceNumber(),
                            DateTimeOffset.UtcNow));
                    }
                }
            }
        }
        catch
        {
            // Exceptions must never escape a native hook callback or interfere with input.
        }

        return CallNextHookEx(hookHandle, code, message, data);
    }

    private static bool TryClassifyMessage(nint message, out bool isKeyDown)
    {
        var value = message.ToInt32();
        isKeyDown = value is KeyDownMessage or SystemKeyDownMessage;
        return isKeyDown || value is KeyUpMessage or SystemKeyUpMessage;
    }

    private void VerifyAccess()
    {
        if (!dispatcher.CheckAccess())
            throw new InvalidOperationException("Start, stop, and dispose the paste-intent observer on its WPF dispatcher thread.");
    }

    public void Dispose()
    {
        VerifyAccess();
        if (disposed) return;
        Stop();
        disposed = true;
    }

    private delegate nint HookProcedure(int code, nint message, nint data);

    [StructLayout(LayoutKind.Sequential)]
    private readonly struct LowLevelKeyboardInput
    {
        public readonly uint VirtualKey;
        public readonly uint ScanCode;
        public readonly uint Flags;
        public readonly uint Time;
        public readonly nuint ExtraInfo;
    }

    [LibraryImport("user32.dll", EntryPoint = "SetWindowsHookExW", SetLastError = true)]
    private static partial nint SetWindowsHookEx(int hookId, HookProcedure callback, nint moduleHandle, uint threadId);

    [LibraryImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool UnhookWindowsHookEx(nint hookHandle);

    [LibraryImport("user32.dll")]
    private static partial nint CallNextHookEx(nint hookHandle, int code, nint message, nint data);

    [LibraryImport("user32.dll")]
    private static partial nint GetForegroundWindow();

    [LibraryImport("user32.dll")]
    private static partial uint GetWindowThreadProcessId(nint windowHandle, out uint processId);

    [LibraryImport("user32.dll")]
    private static partial uint GetClipboardSequenceNumber();

    [LibraryImport("kernel32.dll", EntryPoint = "GetModuleHandleW", StringMarshalling = StringMarshalling.Utf16)]
    private static partial nint GetModuleHandle(string? moduleName);
}

internal sealed class PasteIntentKeyState
{
    internal const uint V = 0x56;
    internal const uint Control = 0x11;
    internal const uint LeftControl = 0xA2;
    internal const uint RightControl = 0xA3;
    internal const uint Alt = 0x12;
    internal const uint LeftAlt = 0xA4;
    internal const uint RightAlt = 0xA5;
    internal const uint Shift = 0x10;
    internal const uint LeftShift = 0xA0;
    internal const uint RightShift = 0xA1;
    internal const uint LeftWindows = 0x5B;
    internal const uint RightWindows = 0x5C;

    private readonly HashSet<uint> controlKeysDown = [];
    private readonly HashSet<uint> altKeysDown = [];
    private readonly HashSet<uint> otherModifierKeysDown = [];
    private bool vDown;

    public HotkeyGesture? Observe(uint virtualKey, bool isKeyDown, bool isInjected)
    {
        if (isInjected) return null;

        if (IsControl(virtualKey))
        {
            SetKey(controlKeysDown, virtualKey, isKeyDown);
            return null;
        }

        if (IsAlt(virtualKey))
        {
            SetKey(altKeysDown, virtualKey, isKeyDown);
            return null;
        }

        if (IsOtherModifier(virtualKey))
        {
            SetKey(otherModifierKeysDown, virtualKey, isKeyDown);
            return null;
        }

        if (virtualKey != V) return null;
        if (!isKeyDown)
        {
            vDown = false;
            return null;
        }

        if (vDown) return null;
        vDown = true;
        var controlDown = controlKeysDown.Count > 0;
        var altDown = altKeysDown.Count > 0;
        if (controlDown == altDown || otherModifierKeysDown.Count > 0) return null;
        return controlDown ? HotkeyGesture.CtrlV : HotkeyGesture.AltV;
    }

    public void Reset()
    {
        controlKeysDown.Clear();
        altKeysDown.Clear();
        otherModifierKeysDown.Clear();
        vDown = false;
    }

    private static bool IsControl(uint key) => key is Control or LeftControl or RightControl;
    private static bool IsAlt(uint key) => key is Alt or LeftAlt or RightAlt;
    private static bool IsOtherModifier(uint key) => key is Shift or LeftShift or RightShift or LeftWindows or RightWindows;

    private static void SetKey(HashSet<uint> keys, uint key, bool isDown)
    {
        if (isDown) keys.Add(key);
        else keys.Remove(key);
    }
}
