using System;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace SnapBrief.App.Imaging;

/// <summary>Applies a bounded blur to one rectangle in source pixel coordinates.</summary>
public static class RegionBlur
{
    private const int BytesPerPixel = 4;
    private const int PassCount = 3;
    private const int MaximumRadius = 512;

    public static BitmapSource Apply(BitmapSource source, Int32Rect pixelRegion, int radius)
    {
        ArgumentNullException.ThrowIfNull(source);
        if (radius is < 1 or > MaximumRadius)
            throw new ArgumentOutOfRangeException(nameof(radius), $"Blur radius must be between 1 and {MaximumRadius} pixels.");

        var converted = source.Format == PixelFormats.Bgra32
            ? source
            : new FormatConvertedBitmap(source, PixelFormats.Bgra32, null, 0);
        var width = converted.PixelWidth;
        var height = converted.PixelHeight;
        var stride = checked(width * BytesPerPixel);
        var fullPixels = new byte[checked(stride * height)];
        converted.CopyPixels(fullPixels, stride, 0);

        var clipped = Clip(pixelRegion, width, height);
        if (!clipped.IsEmpty)
            BlurRegion(fullPixels, stride, clipped, radius);

        var result = BitmapSource.Create(
            width,
            height,
            source.DpiX,
            source.DpiY,
            PixelFormats.Bgra32,
            null,
            fullPixels,
            stride);
        result.Freeze();
        return result;
    }

    private static Int32Rect Clip(Int32Rect region, int imageWidth, int imageHeight)
    {
        if (region.Width <= 0 || region.Height <= 0) return Int32Rect.Empty;

        var left = Math.Clamp((long)region.X, 0, imageWidth);
        var top = Math.Clamp((long)region.Y, 0, imageHeight);
        var right = Math.Clamp((long)region.X + region.Width, 0, imageWidth);
        var bottom = Math.Clamp((long)region.Y + region.Height, 0, imageHeight);
        return right <= left || bottom <= top
            ? Int32Rect.Empty
            : new Int32Rect((int)left, (int)top, (int)(right - left), (int)(bottom - top));
    }

    private static void BlurRegion(byte[] fullPixels, int fullStride, Int32Rect region, int radius)
    {
        var regionStride = checked(region.Width * BytesPerPixel);
        var regionPixels = new byte[checked(regionStride * region.Height)];
        var scratch = new byte[regionPixels.Length];

        for (var row = 0; row < region.Height; row++)
        {
            var sourceOffset = checked((region.Y + row) * fullStride + region.X * BytesPerPixel);
            Buffer.BlockCopy(fullPixels, sourceOffset, regionPixels, row * regionStride, regionStride);
        }

        for (var pass = 0; pass < PassCount; pass++)
        {
            BlurHorizontal(regionPixels, scratch, region.Width, region.Height, regionStride, radius);
            BlurVertical(scratch, regionPixels, region.Width, region.Height, regionStride, radius);
        }

        for (var row = 0; row < region.Height; row++)
        {
            var destinationOffset = checked((region.Y + row) * fullStride + region.X * BytesPerPixel);
            Buffer.BlockCopy(regionPixels, row * regionStride, fullPixels, destinationOffset, regionStride);
        }
    }

    private static void BlurHorizontal(byte[] source, byte[] destination, int width, int height, int stride, int radius)
    {
        var divisor = checked(radius * 2 + 1);
        Span<int> sums = stackalloc int[BytesPerPixel];
        for (var y = 0; y < height; y++)
        {
            sums.Clear();
            for (var offset = -radius; offset <= radius; offset++)
                AddPixel(source, y * stride + Math.Clamp(offset, 0, width - 1) * BytesPerPixel, sums, 1);

            for (var x = 0; x < width; x++)
            {
                WriteAverage(destination, y * stride + x * BytesPerPixel, sums, divisor);
                var outgoingX = Math.Clamp(x - radius, 0, width - 1);
                var incomingX = Math.Clamp(x + radius + 1, 0, width - 1);
                AddPixel(source, y * stride + outgoingX * BytesPerPixel, sums, -1);
                AddPixel(source, y * stride + incomingX * BytesPerPixel, sums, 1);
            }
        }
    }

    private static void BlurVertical(byte[] source, byte[] destination, int width, int height, int stride, int radius)
    {
        var divisor = checked(radius * 2 + 1);
        Span<int> sums = stackalloc int[BytesPerPixel];
        for (var x = 0; x < width; x++)
        {
            sums.Clear();
            for (var offset = -radius; offset <= radius; offset++)
                AddPixel(source, Math.Clamp(offset, 0, height - 1) * stride + x * BytesPerPixel, sums, 1);

            for (var y = 0; y < height; y++)
            {
                WriteAverage(destination, y * stride + x * BytesPerPixel, sums, divisor);
                var outgoingY = Math.Clamp(y - radius, 0, height - 1);
                var incomingY = Math.Clamp(y + radius + 1, 0, height - 1);
                AddPixel(source, outgoingY * stride + x * BytesPerPixel, sums, -1);
                AddPixel(source, incomingY * stride + x * BytesPerPixel, sums, 1);
            }
        }
    }

    private static void AddPixel(byte[] pixels, int offset, Span<int> sums, int sign)
    {
        for (var channel = 0; channel < BytesPerPixel; channel++)
            sums[channel] += sign * pixels[offset + channel];
    }

    private static void WriteAverage(byte[] pixels, int offset, ReadOnlySpan<int> sums, int divisor)
    {
        for (var channel = 0; channel < BytesPerPixel; channel++)
            pixels[offset + channel] = (byte)((sums[channel] + divisor / 2) / divisor);
    }
}
