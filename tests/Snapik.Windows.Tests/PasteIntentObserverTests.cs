namespace Snapik.Windows.Tests;

public sealed class PasteIntentObserverTests
{
    [Fact]
    public void NativeImports_ResolveActualWindowsExports()
    {
        var imports = typeof(WindowsPasteIntentObserver).GetMethods(
            System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Static)
            .Select(method => (Method: method, Import: System.Reflection.CustomAttributeExtensions.GetCustomAttribute<System.Runtime.InteropServices.LibraryImportAttribute>(method)))
            .Where(item => item.Import is not null).ToArray();
        Assert.NotEmpty(imports);
        foreach (var (method, import) in imports)
        {
            var library = System.Runtime.InteropServices.NativeLibrary.Load(import!.LibraryName);
            try
            {
                Assert.True(System.Runtime.InteropServices.NativeLibrary.TryGetExport(library, import.EntryPoint ?? method.Name, out _),
                    $"Missing Windows export: {import.LibraryName}!{import.EntryPoint ?? method.Name}");
            }
            finally { System.Runtime.InteropServices.NativeLibrary.Free(library); }
        }
    }
    [Fact]
    public void ControlV_IsReportedOnceUntilVIsReleased()
    {
        var state = new PasteIntentKeyState();
        Assert.Null(state.Observe(PasteIntentKeyState.LeftControl, true, false));
        Assert.Equal(HotkeyGesture.CtrlV, state.Observe(PasteIntentKeyState.V, true, false));
        Assert.Null(state.Observe(PasteIntentKeyState.V, true, false));
        Assert.Null(state.Observe(PasteIntentKeyState.V, false, false));
        Assert.Equal(HotkeyGesture.CtrlV, state.Observe(PasteIntentKeyState.V, true, false));
    }

    [Fact]
    public void AltV_IsReportedWithEitherAltKey()
    {
        var state = new PasteIntentKeyState();
        state.Observe(PasteIntentKeyState.RightAlt, true, false);
        Assert.Equal(HotkeyGesture.AltV, state.Observe(PasteIntentKeyState.V, true, false));
    }

    [Fact]
    public void PlainV_ControlAltV_ExtraModifierV_AndInjectedV_AreIgnored()
    {
        var plain = new PasteIntentKeyState();
        Assert.Null(plain.Observe(PasteIntentKeyState.V, true, false));

        var altGr = new PasteIntentKeyState();
        altGr.Observe(PasteIntentKeyState.LeftControl, true, false);
        altGr.Observe(PasteIntentKeyState.RightAlt, true, false);
        Assert.Null(altGr.Observe(PasteIntentKeyState.V, true, false));

        var shifted = new PasteIntentKeyState();
        shifted.Observe(PasteIntentKeyState.LeftControl, true, false);
        shifted.Observe(PasteIntentKeyState.LeftShift, true, false);
        Assert.Null(shifted.Observe(PasteIntentKeyState.V, true, false));

        var injected = new PasteIntentKeyState();
        injected.Observe(PasteIntentKeyState.LeftControl, true, false);
        Assert.Null(injected.Observe(PasteIntentKeyState.V, true, true));
    }

    [Fact]
    public void ReleasedModifierDoesNotRemainLatched()
    {
        var state = new PasteIntentKeyState();
        state.Observe(PasteIntentKeyState.Control, true, false);
        state.Observe(PasteIntentKeyState.Control, false, false);
        Assert.Null(state.Observe(PasteIntentKeyState.V, true, false));
    }

    [Fact]
    public void ResetClearsHeldAndRepeatState()
    {
        var state = new PasteIntentKeyState();
        state.Observe(PasteIntentKeyState.LeftAlt, true, false);
        Assert.Equal(HotkeyGesture.AltV, state.Observe(PasteIntentKeyState.V, true, false));
        state.Reset();
        Assert.Null(state.Observe(PasteIntentKeyState.V, true, false));
    }

    [Fact]
    public void InterceptedPhysicalV_SuppressesInitialAndRepeatKeyDownsUntilRelease()
    {
        var state = new PasteIntentInterceptionState();

        Assert.True(state.ShouldSuppress(PasteIntentKeyState.V, true, false, interceptThisGesture: true));
        Assert.True(state.ShouldSuppress(PasteIntentKeyState.V, true, false, interceptThisGesture: false));
        Assert.False(state.ShouldSuppress(PasteIntentKeyState.V, false, false, interceptThisGesture: false));
        Assert.False(state.ShouldSuppress(PasteIntentKeyState.V, true, false, interceptThisGesture: false));
    }

    [Fact]
    public void Interception_NeverSuppressesInjectedOrUnrelatedKeys()
    {
        var state = new PasteIntentInterceptionState();

        Assert.False(state.ShouldSuppress(PasteIntentKeyState.V, true, true, interceptThisGesture: true));
        Assert.False(state.ShouldSuppress(PasteIntentKeyState.LeftControl, true, false, interceptThisGesture: true));
    }

    [Fact]
    public void InterceptedPhysicalAltV_SuppressesTheGestureAndOwnPhysicalReleaseIsNotInjected()
    {
        // Alt+V is classified the same way as Ctrl+V is: the interceptor only cares about the
        // physical V key, so an Alt+V paste must be suppressible exactly like a Ctrl+V paste.
        var keyState = new PasteIntentKeyState();
        var interceptionState = new PasteIntentInterceptionState();

        keyState.Observe(PasteIntentKeyState.LeftAlt, true, false);
        var gesture = keyState.Observe(PasteIntentKeyState.V, true, false);
        Assert.Equal(HotkeyGesture.AltV, gesture);

        Assert.True(interceptionState.ShouldSuppress(PasteIntentKeyState.V, true, false, interceptThisGesture: true));
        Assert.True(interceptionState.ShouldSuppress(PasteIntentKeyState.V, true, false, interceptThisGesture: false));

        // Snapik's own synthetic Alt+V keystrokes are injected and must never be suppressed.
        Assert.False(interceptionState.ShouldSuppress(PasteIntentKeyState.V, true, isInjected: true, interceptThisGesture: false));

        Assert.False(interceptionState.ShouldSuppress(PasteIntentKeyState.V, false, false, interceptThisGesture: false));
    }
}
