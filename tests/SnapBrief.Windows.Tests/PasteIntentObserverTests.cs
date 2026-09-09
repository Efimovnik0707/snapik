namespace SnapBrief.Windows.Tests;

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
}
