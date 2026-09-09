using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace SnapBrief.Windows.Tests;

public sealed partial class PasteCoordinatorTests : IDisposable
{
    private readonly string tempDirectory = Path.Combine(Path.GetTempPath(), "SnapBrief.Windows.Tests", Guid.NewGuid().ToString("N"));

    public PasteCoordinatorTests() => Directory.CreateDirectory(tempDirectory);

    [Fact]
    public async Task StagedPaste_PreservesOrder_NeverUsesEnter_AndCanBeVerified()
    {
        var package = CreatePackage(3);
        var clipboard = new FakeClipboard();
        var input = new FakeInput();
        var coordinator = CreateCoordinator(clipboard, input, new FakeObserver(
            [AcceptanceOutcome.Accepted, AcceptanceOutcome.Accepted, AcceptanceOutcome.Accepted],
            AcceptanceOutcome.Accepted));

        var result = await coordinator.PasteAsync(package, Profile());

        Assert.Equal(PasteStatus.CompletedVerified, result.Status);
        Assert.Equal(package.ImagePaths.Concat(["TEXT"]), clipboard.Writes);
        Assert.Equal(4, input.Gestures.Count);
        Assert.DoesNotContain(input.Gestures, gesture => gesture.ContainsEnter);
        Assert.Equal(3, result.ImagesConfirmed);
        Assert.True(result.TextConfirmed);
    }

    [Fact]
    public async Task ExternalClipboardWrite_BeforeNextStage_IsNotOverwritten()
    {
        var package = CreatePackage(2);
        var clipboard = new FakeClipboard();
        var observer = new FakeObserver([AcceptanceOutcome.Accepted]);
        observer.AfterImage = _ => clipboard.ExternalWrite();
        var coordinator = CreateCoordinator(clipboard, new FakeInput(), observer);

        var result = await coordinator.PasteAsync(package, Profile());

        Assert.Equal(PasteStatus.ClipboardChanged, result.Status);
        Assert.Single(clipboard.Writes);
        Assert.Equal(package.ImagePaths[0], clipboard.Writes[0]);
    }

    [Fact]
    public async Task CancellationAfterDispatch_PreservesPartialProgress()
    {
        var package = CreatePackage(2);
        using var cancellation = new CancellationTokenSource();
        var observer = new FakeObserver([AcceptanceOutcome.Accepted]);
        observer.BeforeImage = _ => cancellation.Cancel();
        var coordinator = CreateCoordinator(new FakeClipboard(), new FakeInput(), observer);

        var result = await coordinator.PasteAsync(package, Profile(), cancellationToken: cancellation.Token);

        Assert.Equal(PasteStatus.Cancelled, result.Status);
        Assert.Equal(1, result.ImagesDispatched);
        Assert.Equal(0, result.ImagesConfirmed);
    }

    [Fact]
    public async Task TimeoutAfterConfirmedPrefix_ProvidesSafeResumeBoundary()
    {
        var package = CreatePackage(3);
        var observer = new FakeObserver([AcceptanceOutcome.Accepted, AcceptanceOutcome.TimedOut]);
        var coordinator = CreateCoordinator(new FakeClipboard(), new FakeInput(), observer);

        var result = await coordinator.PasteAsync(package, Profile());

        Assert.Equal(PasteStatus.AcceptanceTimedOut, result.Status);
        Assert.Equal(2, result.ImagesDispatched);
        Assert.Equal(1, result.ImagesConfirmed);
        Assert.Equal(1, result.SafeResumeToken?.ConfirmedImageCount);
    }

    [Fact]
    public async Task UnobservableStep_RemovesSafeResumeBoundary_AndReportsUnverified()
    {
        var package = CreatePackage(2);
        var observer = new FakeObserver([AcceptanceOutcome.NotObservable, AcceptanceOutcome.Accepted], AcceptanceOutcome.NotObservable);
        var coordinator = CreateCoordinator(new FakeClipboard(), new FakeInput(), observer);

        var result = await coordinator.PasteAsync(package, Profile());

        Assert.Equal(PasteStatus.CompletedUnverified, result.Status);
        Assert.Null(result.SafeResumeToken);
        Assert.False(result.DeliveryWasObserved);
    }

    [Fact]
    public async Task FocusedChildChange_StopsBeforeAnyClipboardWrite()
    {
        var package = CreatePackage(1);
        var target = new FakeTarget { Same = false };
        var clipboard = new FakeClipboard();
        var coordinator = new PasteCoordinator(clipboard, target, new FakeInput(), new FakeObserver([]));

        var result = await coordinator.PasteAsync(package, Profile());

        Assert.Equal(PasteStatus.TargetChanged, result.Status);
        Assert.Empty(clipboard.Writes);
    }

    [Fact]
    public async Task SinglePackage_DoesNotInferTextAcceptanceFromImages()
    {
        var package = CreatePackage(2);
        var observer = new FakeObserver([]) { Package = new(AcceptanceOutcome.Accepted, AcceptanceOutcome.NotObservable) };
        var profile = Profile(PasteTransport.SingleClipboardPackage, HotkeyGesture.CtrlV, HotkeyGesture.CtrlV);
        var coordinator = CreateCoordinator(new FakeClipboard(), new FakeInput(), observer);

        var result = await coordinator.PasteAsync(package, profile);

        Assert.Equal(PasteStatus.CompletedUnverified, result.Status);
        Assert.Equal(2, result.ImagesConfirmed);
        Assert.False(result.TextConfirmed);
    }

    [Fact]
    public void ProfilesRejectEnterAndSinglePackageWithTwoGestures()
    {
        var enter = new HotkeyGesture(HotkeyModifiers.None, HotkeyGesture.EnterVirtualKey);
        Assert.Throws<ArgumentException>(() => Profile(image: enter).Validate());
        Assert.Throws<ArgumentException>(() => Profile(PasteTransport.SingleClipboardPackage, HotkeyGesture.CtrlV, HotkeyGesture.AltV).Validate());
    }

    [Fact]
    public void NativeInputLayout_MatchesWin32Abi()
    {
        Assert.Equal(IntPtr.Size == 8 ? 40 : 28, WindowsInputInjector.NativeInputSize);
    }

    [Fact]
    public async Task InputInjector_TimesOutWithoutSynthesizingWhenTriggerModifierStaysHeld()
    {
        var injector = new WindowsInputInjector(new AlwaysHeldKeys(), TimeSpan.FromMilliseconds(20));
        await Assert.ThrowsAsync<PhysicalKeysStillHeldException>(() => injector.SendAsync(HotkeyGesture.CtrlV, CancellationToken.None));
    }

    [Fact]
    public async Task Coordinator_EnforcesObserverTimeout()
    {
        var package = CreatePackage(1);
        var profile = new TargetProfile(
            "timeout", "Timeout", PasteTransport.StagedSequence,
            HotkeyGesture.AltV, HotkeyGesture.CtrlV,
            new HashSet<string> { "Target" },
            TimeSpan.FromMilliseconds(20), TimeSpan.Zero, ProfileVerification.Unverified);
        var coordinator = new PasteCoordinator(new FakeClipboard(), new FakeTarget(), new FakeInput(), new NeverObserver());

        var result = await coordinator.PasteAsync(package, profile);

        Assert.Equal(PasteStatus.AcceptanceTimedOut, result.Status);
        Assert.Equal(1, result.ImagesDispatched);
    }

    [Fact]
    public void DibEncoder_WritesStandardBottomUpBitmapInfo()
    {
        byte[] topThenBottom =
        [
            1, 2, 3, 255, 4, 5, 6, 255,
            7, 8, 9, 255, 10, 11, 12, 255,
        ];
        var bitmap = BitmapSource.Create(2, 2, 96, 96, PixelFormats.Bgra32, null, topThenBottom, 8);

        using var dib = WindowsClipboardService.CreateDib(bitmap);
        using var reader = new BinaryReader(dib);
        Assert.Equal(40, reader.ReadInt32());
        Assert.Equal(2, reader.ReadInt32());
        Assert.Equal(2, reader.ReadInt32());
        dib.Position = 40;
        Assert.Equal(topThenBottom[8..16], reader.ReadBytes(8));
        Assert.Equal(topThenBottom[0..8], reader.ReadBytes(8));
    }

    [Fact]
    public async Task StaWorkQueue_HasStaApartmentAndMessageDispatcher()
    {
        using var queue = new StaWorkQueue("test STA");
        var state = await queue.InvokeAsync(
            () => (Thread.CurrentThread.GetApartmentState(), Dispatcher.FromThread(Thread.CurrentThread) is not null),
            CancellationToken.None);

        Assert.Equal(ApartmentState.STA, state.Item1);
        Assert.True(state.Item2);
    }

    [Fact]
    public async Task PngDataObject_ExposesRawPngAndDibBytesWithoutUsingSystemClipboard()
    {
        var pngPath = Path.Combine(tempDirectory, "valid.png");
        var pixels = new byte[] { 1, 2, 3, 255 };
        var bitmap = BitmapSource.Create(1, 1, 96, 96, PixelFormats.Bgra32, null, pixels, 4);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        await using (var output = File.Create(pngPath)) encoder.Save(output);

        using var queue = new StaWorkQueue("PNG data object test");
        var actual = await queue.InvokeAsync(
            () => (Png: ReadRawFormat(pngPath, "PNG", 8), Dib: ReadRawFormat(pngPath, DataFormats.Dib, 4)),
            CancellationToken.None);

        Assert.Equal(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 }, actual.Png);
        Assert.Equal(new byte[] { 40, 0, 0, 0 }, actual.Dib);
    }

    [Fact]
    public async Task SingleImagePackage_ExposesImageFileAndTextFormatsWithoutUsingSystemClipboard()
    {
        var pngPath = await WriteValidPngAsync("single-package.png");

        using var queue = new StaWorkQueue("single package data object test");
        var formats = await queue.InvokeAsync(() =>
        {
            var data = WindowsClipboardService.CreatePackageDataObject([pngPath], "Снимок A.");
            return (
                Png: data.GetDataPresent("PNG", false),
                Dib: data.GetDataPresent(DataFormats.Dib, false),
                Bitmap: data.GetDataPresent(DataFormats.Bitmap, false),
                Files: data.GetFileDropList().Cast<string>().ToArray(),
                Text: data.GetText(TextDataFormat.UnicodeText));
        }, CancellationToken.None);

        Assert.True(formats.Png);
        Assert.True(formats.Dib);
        Assert.True(formats.Bitmap);
        Assert.Equal([pngPath], formats.Files);
        Assert.Equal("Снимок A.", formats.Text);
    }

    [Fact]
    public async Task MultiImagePackage_ExposesAllFilesAndTextWithoutClaimingOneImageFormat()
    {
        var first = await WriteValidPngAsync("multi-a.png");
        var second = await WriteValidPngAsync("multi-b.png");

        using var queue = new StaWorkQueue("multi package data object test");
        var formats = await queue.InvokeAsync(() =>
        {
            var data = WindowsClipboardService.CreatePackageDataObject([first, second], "Снимок A. Снимок B.");
            return (
                Png: data.GetDataPresent("PNG", false),
                Dib: data.GetDataPresent(DataFormats.Dib, false),
                Bitmap: data.GetDataPresent(DataFormats.Bitmap, false),
                Files: data.GetFileDropList().Cast<string>().ToArray(),
                Text: data.GetText(TextDataFormat.UnicodeText));
        }, CancellationToken.None);

        Assert.False(formats.Png);
        Assert.False(formats.Dib);
        Assert.False(formats.Bitmap);
        Assert.Equal([first, second], formats.Files);
        Assert.Equal("Снимок A. Снимок B.", formats.Text);
    }

    [Theory]
    [InlineData(1)]
    [InlineData(3)]
    public async Task FileDropPackage_ExposesOnlyOrderedFiles_ForClaudeDesktop(int imageCount)
    {
        var paths = new List<string>();
        for (var index = 0; index < imageCount; index++)
            paths.Add(await WriteValidPngAsync($"claude-{index}.png"));

        using var queue = new StaWorkQueue("Claude file-drop data object test");
        var formats = await queue.InvokeAsync(() =>
        {
            var data = WindowsClipboardService.CreateFileDropDataObject(paths);
            return (
                Png: data.GetDataPresent("PNG", false),
                Dib: data.GetDataPresent(DataFormats.Dib, false),
                Bitmap: data.GetDataPresent(DataFormats.Bitmap, false),
                Text: data.GetDataPresent(DataFormats.UnicodeText, false),
                NativeFormats: data.GetFormats(autoConvert: false),
                Files: data.GetFileDropList().Cast<string>().ToArray());
        }, CancellationToken.None);

        Assert.False(formats.Png);
        Assert.False(formats.Dib);
        Assert.False(formats.Bitmap);
        Assert.False(formats.Text);
        Assert.Equal([DataFormats.FileDrop], formats.NativeFormats);
        Assert.Equal(paths, formats.Files);
    }

    [Fact]
    public void EmptyFileDropPackage_IsRejectedBeforeClipboardAccess() =>
        Assert.Throws<ArgumentException>(() => WindowsClipboardService.CreateFileDropDataObject([]));

    [Fact]
    public void EmptyPackage_IsRejectedBeforeClipboardAccess() =>
        Assert.Throws<ArgumentException>(() => WindowsClipboardService.CreatePackageDataObject([], "text"));

    private PreparedPastePackage CreatePackage(int count)
    {
        var paths = Enumerable.Range(0, count).Select(index => Path.Combine(tempDirectory, $"{index}.png")).ToArray();
        foreach (var path in paths) File.WriteAllBytes(path, [137, 80, 78, 71]);
        return new(Guid.NewGuid(), paths, "Русский текст\nwith emoji 🧭");
    }

    private async Task<string> WriteValidPngAsync(string fileName)
    {
        var path = Path.Combine(tempDirectory, fileName);
        var bitmap = BitmapSource.Create(1, 1, 96, 96, PixelFormats.Bgra32, null, new byte[] { 1, 2, 3, 255 }, 4);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        await using var output = File.Create(path);
        encoder.Save(output);
        return path;
    }

    private static PasteCoordinator CreateCoordinator(FakeClipboard clipboard, FakeInput input, FakeObserver observer) =>
        new(clipboard, new FakeTarget(), input, observer);

    private static TargetProfile Profile(
        PasteTransport transport = PasteTransport.StagedSequence,
        HotkeyGesture? image = null,
        HotkeyGesture? text = null) => new(
            "test", "Test", transport, image ?? HotkeyGesture.AltV, text ?? HotkeyGesture.CtrlV,
            new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "Target" },
            TimeSpan.FromSeconds(1), TimeSpan.Zero, ProfileVerification.Unverified);

    public void Dispose() => Directory.Delete(tempDirectory, recursive: true);

    private static byte[] ReadRawFormat(string path, string formatName, int byteCount)
    {
        var data = WindowsClipboardService.CreatePngDataObject(path);
        var oleData = (System.Runtime.InteropServices.ComTypes.IDataObject)data;
        var format = new FORMATETC
        {
            cfFormat = unchecked((short)DataFormats.GetDataFormat(formatName).Id),
            dwAspect = DVASPECT.DVASPECT_CONTENT,
            lindex = -1,
            tymed = TYMED.TYMED_HGLOBAL,
        };
        oleData.GetData(ref format, out var medium);
        try
        {
            var pointer = GlobalLock(medium.unionmember);
            if (pointer == 0) throw new InvalidOperationException("Could not lock PNG clipboard HGLOBAL.");
            try
            {
                var bytes = new byte[byteCount];
                Marshal.Copy(pointer, bytes, 0, bytes.Length);
                return bytes;
            }
            finally { _ = GlobalUnlock(medium.unionmember); }
        }
        finally { ReleaseStgMedium(ref medium); }
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern nint GlobalLock(nint memory);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GlobalUnlock(nint memory);

    [DllImport("ole32.dll")]
    private static extern void ReleaseStgMedium(ref STGMEDIUM medium);

    private sealed class FakeClipboard : IClipboardService
    {
        private uint sequence = 10;
        public List<string> Writes { get; } = [];
        public Task<ClipboardSnapshot> CaptureAsync(CancellationToken cancellationToken) => Task.FromResult(new ClipboardSnapshot(sequence, new Dictionary<string, object>(), true));
        public Task<ClipboardWriteReceipt> SetPackageGuardedAsync(IReadOnlyList<string> pngPaths, string text, uint expected, CancellationToken cancellationToken)
        {
            Require(expected); Writes.AddRange(pngPaths); Writes.Add("TEXT"); return Receipt();
        }
        public Task<ClipboardWriteReceipt> SetFileDropGuardedAsync(IReadOnlyList<string> pngPaths, uint expected, CancellationToken cancellationToken)
        {
            Require(expected); Writes.AddRange(pngPaths); return Receipt();
        }
        public Task<ClipboardWriteReceipt> SetPngGuardedAsync(string path, uint expected, CancellationToken cancellationToken)
        {
            Require(expected); Writes.Add(path); return Receipt();
        }
        public Task<ClipboardWriteReceipt> SetTextGuardedAsync(string text, uint expected, CancellationToken cancellationToken)
        {
            Require(expected); Writes.Add("TEXT"); return Receipt();
        }
        public Task<bool> IsCurrentAsync(ClipboardWriteReceipt receipt, CancellationToken cancellationToken) => Task.FromResult(receipt.SequenceNumber == sequence);
        public Task<bool> RestoreIfCurrentAsync(ClipboardSnapshot snapshot, ClipboardWriteReceipt receipt, CancellationToken cancellationToken) => Task.FromResult(false);
        public void ExternalWrite() => sequence++;
        private void Require(uint expected) { if (expected != sequence) throw new ClipboardChangedException(); }
        private Task<ClipboardWriteReceipt> Receipt() { sequence++; return Task.FromResult(new ClipboardWriteReceipt(sequence)); }
    }

    private sealed class FakeTarget : IForegroundTargetService
    {
        private readonly TargetSnapshot target = new(1, 2, 3, "Target", "Draft");
        public bool Same { get; set; } = true;
        public TargetSnapshot Capture() => target;
        public bool IsSame(TargetSnapshot expected) => Same && expected == target;
        public bool Matches(TargetSnapshot value, TargetProfile profile) => profile.AllowedProcessNames.Contains(value.ProcessName);
    }

    private sealed class FakeInput : IInputInjector
    {
        public List<HotkeyGesture> Gestures { get; } = [];
        public Task SendAsync(HotkeyGesture gesture, CancellationToken cancellationToken) { Gestures.Add(gesture); return Task.CompletedTask; }
    }

    private sealed class AlwaysHeldKeys : IPhysicalKeyState
    {
        public bool IsDown(ushort virtualKey) => true;
    }

    private sealed class NeverObserver : IPasteAcceptanceObserver
    {
        public async Task<PackageAcceptanceOutcome> WaitForPackageAsync(TargetSnapshot target, TargetProfile profile, CancellationToken cancellationToken)
        {
            await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
            throw new InvalidOperationException();
        }
        public async Task<AcceptanceOutcome> WaitForImageAsync(TargetSnapshot target, int imageIndex, TargetProfile profile, CancellationToken cancellationToken)
        {
            await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
            throw new InvalidOperationException();
        }
        public async Task<AcceptanceOutcome> WaitForTextAsync(TargetSnapshot target, TargetProfile profile, CancellationToken cancellationToken)
        {
            await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
            throw new InvalidOperationException();
        }
    }

    private sealed class FakeObserver(IEnumerable<AcceptanceOutcome> images, AcceptanceOutcome text = AcceptanceOutcome.Accepted) : IPasteAcceptanceObserver
    {
        private readonly Queue<AcceptanceOutcome> imageOutcomes = new(images);
        public Action<int>? BeforeImage { get; set; }
        public Action<int>? AfterImage { get; set; }
        public PackageAcceptanceOutcome Package { get; set; } = new(AcceptanceOutcome.Accepted, AcceptanceOutcome.Accepted);
        public Task<PackageAcceptanceOutcome> WaitForPackageAsync(TargetSnapshot target, TargetProfile profile, CancellationToken cancellationToken) => Task.FromResult(Package);
        public Task<AcceptanceOutcome> WaitForImageAsync(TargetSnapshot target, int imageIndex, TargetProfile profile, CancellationToken cancellationToken)
        {
            BeforeImage?.Invoke(imageIndex); cancellationToken.ThrowIfCancellationRequested();
            var outcome = imageOutcomes.Dequeue(); AfterImage?.Invoke(imageIndex); return Task.FromResult(outcome);
        }
        public Task<AcceptanceOutcome> WaitForTextAsync(TargetSnapshot target, TargetProfile profile, CancellationToken cancellationToken) => Task.FromResult(text);
    }
}
