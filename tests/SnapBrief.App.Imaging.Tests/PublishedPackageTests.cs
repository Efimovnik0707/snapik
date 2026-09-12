using System;

namespace SnapBrief.App.Imaging.Tests;

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
}
