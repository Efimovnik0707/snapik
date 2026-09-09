using SnapBrief.App.Imaging;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace SnapBrief.App.Imaging.Tests;

public sealed class RegionBlurTests
{
    [Fact]
    public void Apply_PreservesDimensionsDpiAndOriginalPixels()
    {
        var originalPixels = CreateGradientPixels(7, 5);
        var source = CreateBitmap(7, 5, 144, 120, originalPixels);

        var result = RegionBlur.Apply(source, new Int32Rect(1, 1, 5, 3), 2);

        Assert.Equal(7, result.PixelWidth);
        Assert.Equal(5, result.PixelHeight);
        Assert.Equal(144, result.DpiX);
        Assert.Equal(120, result.DpiY);
        Assert.True(result.IsFrozen);
        Assert.Equal(originalPixels, ReadPixels(source));
    }

    [Fact]
    public void Apply_BlursAnImpulseButLeavesOutsideRegionUnchanged()
    {
        const int width = 7;
        const int height = 7;
        var pixels = new byte[width * height * 4];
        FillAlpha(pixels);
        SetPixel(pixels, width, 3, 3, 255, 255, 255, 255);
        SetPixel(pixels, width, 0, 0, 20, 30, 40, 255);
        var source = CreateBitmap(width, height, 96, 96, pixels);

        var result = RegionBlur.Apply(source, new Int32Rect(1, 1, 5, 5), 1);
        var blurred = ReadPixels(result);

        Assert.Equal(new byte[] { 20, 30, 40, 255 }, GetPixel(blurred, width, 0, 0));
        Assert.InRange(GetPixel(blurred, width, 3, 3)[0], 1, 254);
        Assert.True(GetPixel(blurred, width, 3, 2)[0] > 0);
    }

    [Fact]
    public void Apply_ClipsPartiallyOutOfBoundsRectangle()
    {
        var pixels = CreateGradientPixels(4, 4);
        var source = CreateBitmap(4, 4, 96, 96, pixels);

        var result = RegionBlur.Apply(source, new Int32Rect(-3, -2, 5, 4), 2);
        var output = ReadPixels(result);

        Assert.NotEqual(GetPixel(pixels, 4, 0, 0), GetPixel(output, 4, 0, 0));
        Assert.Equal(GetPixel(pixels, 4, 3, 3), GetPixel(output, 4, 3, 3));
    }

    [Fact]
    public void Apply_EmptyIntersectionReturnsIndependentUnchangedBitmap()
    {
        var pixels = CreateGradientPixels(3, 2);
        var source = CreateBitmap(3, 2, 96, 96, pixels);

        var result = RegionBlur.Apply(source, new Int32Rect(10, 10, 2, 2), 3);

        Assert.NotSame(source, result);
        Assert.Equal(pixels, ReadPixels(result));
    }

    [Theory]
    [InlineData(0)]
    [InlineData(513)]
    public void Apply_RejectsInvalidRadius(int radius)
    {
        var source = CreateBitmap(1, 1, 96, 96, new byte[] { 0, 0, 0, 255 });
        Assert.Throws<ArgumentOutOfRangeException>(() => RegionBlur.Apply(source, new Int32Rect(0, 0, 1, 1), radius));
    }

    private static BitmapSource CreateBitmap(int width, int height, double dpiX, double dpiY, byte[] pixels)
    {
        var bitmap = BitmapSource.Create(width, height, dpiX, dpiY, PixelFormats.Bgra32, null, pixels, width * 4);
        bitmap.Freeze();
        return bitmap;
    }

    private static byte[] CreateGradientPixels(int width, int height)
    {
        var pixels = new byte[width * height * 4];
        for (var y = 0; y < height; y++)
        for (var x = 0; x < width; x++)
            SetPixel(pixels, width, x, y, (byte)(x * 31), (byte)(y * 37), (byte)((x + y) * 19), 255);
        return pixels;
    }

    private static void FillAlpha(byte[] pixels)
    {
        for (var offset = 3; offset < pixels.Length; offset += 4) pixels[offset] = 255;
    }

    private static void SetPixel(byte[] pixels, int width, int x, int y, byte blue, byte green, byte red, byte alpha)
    {
        var offset = (y * width + x) * 4;
        pixels[offset] = blue;
        pixels[offset + 1] = green;
        pixels[offset + 2] = red;
        pixels[offset + 3] = alpha;
    }

    private static byte[] GetPixel(byte[] pixels, int width, int x, int y) => pixels[((y * width + x) * 4)..((y * width + x) * 4 + 4)];

    private static byte[] ReadPixels(BitmapSource source)
    {
        var stride = source.PixelWidth * 4;
        var pixels = new byte[stride * source.PixelHeight];
        source.CopyPixels(pixels, stride, 0);
        return pixels;
    }
}
