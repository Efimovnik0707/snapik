using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace SnapBrief.Windows;

public sealed class WindowsForegroundTargetService : IForegroundTargetService
{
    public TargetSnapshot Capture()
    {
        var handle = GetForegroundWindow();
        if (handle == 0) return new(0, 0, 0, string.Empty, string.Empty);
        var threadId = GetWindowThreadProcessId(handle, out var processId);
        string processName;
        try { processName = Process.GetProcessById((int)processId).ProcessName; }
        catch { processName = string.Empty; }

        var length = GetWindowTextLength(handle);
        var title = new StringBuilder(Math.Max(length + 1, 1));
        _ = GetWindowText(handle, title, title.Capacity);
        var info = GuiThreadInfo.Create();
        var focusedHandle = GetGUIThreadInfo(threadId, ref info) ? info.FocusedWindow : 0;
        return new(handle, focusedHandle, processId, processName, title.ToString());
    }

    public bool IsSame(TargetSnapshot expected)
    {
        var current = Capture();
        return current.WindowHandle == expected.WindowHandle
            && current.FocusedControlHandle == expected.FocusedControlHandle
            && current.ProcessId == expected.ProcessId;
    }

    public bool Matches(TargetSnapshot target, TargetProfile profile) =>
        profile.AllowedProcessNames.Contains(target.ProcessName);

    [DllImport("user32.dll")]
    private static extern nint GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(nint hWnd, out uint processId);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetGUIThreadInfo(uint threadId, ref GuiThreadInfo info);

    [DllImport("user32.dll", EntryPoint = "GetWindowTextLengthW")]
    private static extern int GetWindowTextLength(nint hWnd);

    [DllImport("user32.dll", EntryPoint = "GetWindowTextW", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(nint hWnd, StringBuilder text, int maxCount);

    [StructLayout(LayoutKind.Sequential)]
    private struct GuiThreadInfo
    {
        public int Size;
        public uint Flags;
        public nint ActiveWindow;
        public nint FocusedWindow;
        public nint CaptureWindow;
        public nint MenuOwnerWindow;
        public nint MoveSizeWindow;
        public nint CaretWindow;
        public System.Drawing.Rectangle CaretRectangle;

        public static GuiThreadInfo Create() => new() { Size = Marshal.SizeOf<GuiThreadInfo>() };
    }
}
