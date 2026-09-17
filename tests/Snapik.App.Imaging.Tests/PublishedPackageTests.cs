using System;

namespace Snapik.App.Imaging.Tests;

public sealed class PublishedPackageTests
{
    private static PublishedPackage Package() =>
        new(["a.png"], "Снимок A.", [Guid.NewGuid()], @"C:\exports\revision-000001", 1);

    [Fact]
    public void APackageStillOnTheClipboardIsOurs() =>
        Assert.True(PublishedPackage.IsOwnPaste(Package(), 17u, 17u));

    [Fact]
    public void NothingPublishedIsNeverOurs() =>
        Assert.False(PublishedPackage.IsOwnPaste(null, 17u, 17u));

    [Fact]
    public void AForeignClipboardWriteIsNotOurs() =>
        Assert.False(PublishedPackage.IsOwnPaste(Package(), 17u, 18u));

    [Fact]
    public void APackageWithoutAReceiptIsNotOurs() =>
        Assert.False(PublishedPackage.IsOwnPaste(Package(), null, 17u));

    // An intercepted paste dispatches the files one by one: a package without any is nothing to
    // paste, and the intent belongs to whoever else wrote the clipboard.
    [Fact]
    public void APackageWithoutFilesIsNotOurs() =>
        Assert.False(PublishedPackage.IsOwnPaste(Package() with { Paths = [] }, 17u, 17u));

    [Fact]
    public void APastedPackageClearsTheStripWhenTheSettingSaysSo() =>
        Assert.True(PublishedPackage.ClearsTheStrip(Package(), true));

    [Fact]
    public void NothingIsClearedWhileTheSettingIsOff() =>
        Assert.False(PublishedPackage.ClearsTheStrip(Package(), false));

    // The capture copied on its own is one card out of many: the rest were never pasted, and
    // clearing would take them, the session on disk and the undo stack with it.
    [Fact]
    public void ASingleCaptureNeverClearsTheStrip() =>
        Assert.False(PublishedPackage.ClearsTheStrip(Package() with { IsSingleCapture = true }, true));
}
