using System.ComponentModel;
using System.Runtime.InteropServices;

namespace Snapik.Windows;

public sealed partial class WindowsInputInjector : IGuardedInputInjector
{
    private const uint InputKeyboard = 1;
    private const uint KeyUp = 0x0002;
    private const ushort VkMenu = 0x12;
    private const ushort VkControl = 0x11;
    private const ushort VkShift = 0x10;
    private const ushort VkLWin = 0x5B;
    private const ushort VkRWin = 0x5C;
    private readonly IPhysicalKeyState physicalKeys;
    private readonly TimeSpan releaseTimeout;
    internal static int NativeInputSize => Marshal.SizeOf<Input>();

    public WindowsInputInjector(IPhysicalKeyState? physicalKeys = null, TimeSpan? releaseTimeout = null)
    {
        this.physicalKeys = physicalKeys ?? new WindowsPhysicalKeyState();
        this.releaseTimeout = releaseTimeout ?? TimeSpan.FromMilliseconds(750);
        if (this.releaseTimeout <= TimeSpan.Zero) throw new ArgumentOutOfRangeException(nameof(releaseTimeout));
    }

    public async Task SendAsync(HotkeyGesture gesture, CancellationToken cancellationToken) =>
        _ = await SendCoreAsync(gesture, null, cancellationToken);

    public Task<bool> SendGuardedAsync(
        HotkeyGesture gesture,
        Func<CancellationToken, ValueTask<bool>> finalGuard,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(finalGuard);
        return SendCoreAsync(gesture, finalGuard, cancellationToken);
    }

    private async Task<bool> SendCoreAsync(
        HotkeyGesture gesture,
        Func<CancellationToken, ValueTask<bool>>? finalGuard,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (gesture.ContainsEnter) throw new InvalidOperationException("Snapik never injects Enter.");
        await WaitForPhysicalReleaseAsync(gesture.VirtualKey, cancellationToken);
        if (finalGuard is not null && !await finalGuard(cancellationToken)) return false;

        var modifiers = GetModifierKeys(gesture.Modifiers).ToArray();
        var inputs = new List<Input>(modifiers.Length * 2 + 2);
        inputs.AddRange(modifiers.Select(KeyDown));
        inputs.Add(KeyDown(gesture.VirtualKey));
        inputs.Add(KeyUpInput(gesture.VirtualKey));
        inputs.AddRange(modifiers.Reverse().Select(KeyUpInput));

        var sent = SendInput((uint)inputs.Count, CollectionsMarshal.AsSpan(inputs), NativeInputSize);
        if (sent != inputs.Count)
            throw new Win32Exception(Marshal.GetLastWin32Error(), "Windows rejected part of the paste shortcut, possibly because the target has a higher integrity level.");
        return true;
    }

    private async Task WaitForPhysicalReleaseAsync(ushort gestureKey, CancellationToken cancellationToken)
    {
        ushort[] watchedKeys = [VkControl, VkShift, VkMenu, VkLWin, VkRWin, gestureKey];
        var deadline = DateTime.UtcNow + releaseTimeout;
        while (watchedKeys.Distinct().Any(physicalKeys.IsDown))
        {
            if (DateTime.UtcNow >= deadline) throw new PhysicalKeysStillHeldException();
            await Task.Delay(10, cancellationToken);
        }
    }

    private static IEnumerable<ushort> GetModifierKeys(HotkeyModifiers modifiers)
    {
        if (modifiers.HasFlag(HotkeyModifiers.Control)) yield return VkControl;
        if (modifiers.HasFlag(HotkeyModifiers.Shift)) yield return VkShift;
        if (modifiers.HasFlag(HotkeyModifiers.Alt)) yield return VkMenu;
        if (modifiers.HasFlag(HotkeyModifiers.Windows)) yield return VkLWin;
    }

    private static Input KeyDown(ushort key) => new() { Type = InputKeyboard, Union = new() { Keyboard = new() { VirtualKey = key } } };
    private static Input KeyUpInput(ushort key) => new() { Type = InputKeyboard, Union = new() { Keyboard = new() { VirtualKey = key, Flags = KeyUp } } };

    [LibraryImport("user32.dll", SetLastError = true)]
    private static partial uint SendInput(uint inputCount, ReadOnlySpan<Input> inputs, int inputSize);

    [StructLayout(LayoutKind.Sequential)]
    private struct Input { public uint Type; public InputUnion Union; }
    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        [FieldOffset(0)] public MouseInput Mouse;
        [FieldOffset(0)] public KeyboardInput Keyboard;
        [FieldOffset(0)] public HardwareInput Hardware;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct MouseInput
    {
        public int X;
        public int Y;
        public uint MouseData;
        public uint Flags;
        public uint Time;
        public nuint ExtraInfo;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct KeyboardInput
    {
        public ushort VirtualKey;
        public ushort ScanCode;
        public uint Flags;
        public uint Time;
        public nuint ExtraInfo;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct HardwareInput
    {
        public uint Message;
        public ushort ParameterLow;
        public ushort ParameterHigh;
    }
}

public sealed partial class WindowsPhysicalKeyState : IPhysicalKeyState
{
    public bool IsDown(ushort virtualKey) => (GetAsyncKeyState(virtualKey) & 0x8000) != 0;

    [LibraryImport("user32.dll")]
    private static partial short GetAsyncKeyState(int virtualKey);
}
