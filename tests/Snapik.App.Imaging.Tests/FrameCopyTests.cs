using System.IO;
using System.Threading.Tasks;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Snapik.App.Imaging;

namespace Snapik.App.Imaging.Tests;

// An imported file is decoded on the UI thread and encoded in a pool thread, and a frame belongs to
// the decoder that made it: the copy is what makes the second half of that trip legal.
public sealed class FrameCopyTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), $"snapik-frame-copy-{Guid.NewGuid():N}");

    [Theory]
    [InlineData("png")]
    [InlineData("jpg")]
    public void Detach_gives_a_frozen_copy_of_the_same_size(string format)
    {
        var frame = ReadFirstFrame(WriteFile(format, 40, 24));

        var copy = FrameCopy.Detach(frame);

        Assert.True(copy.IsFrozen);
        Assert.Equal(40, copy.PixelWidth);
        Assert.Equal(24, copy.PixelHeight);
        Assert.NotSame(frame, copy);
    }

    // The photograph of a person in a black shirt is the hard case: the fabric is a fine texture of
    // nearly black pixels, and anything that rounds them about breaks it visibly. The copy keeps the
    // format of the frame, so no channel passes through a premultiplied one on the way.
    [Fact]
    public void Detach_keeps_the_colour_of_a_dark_pixel()
    {
        const int stride = 2 * 4;
        // Blue, green, red, alpha: a nearly black pixel, opaque, beside one that is fully clear.
        var pixels = new byte[] { 20, 18, 17, 255, 200, 150, 100, 0 };
        var source = BitmapSource.Create(2, 1, 96, 96, PixelFormats.Bgra32, null, pixels, stride);

        var copy = FrameCopy.Detach(source);

        Assert.Equal(PixelFormats.Bgra32, copy.Format);
        var read = new byte[pixels.Length];
        copy.CopyPixels(read, stride, 0);
        Assert.Equal(pixels, read);
    }

    [Fact]
    public void A_dark_pixel_comes_back_from_a_saved_file_unchanged()
    {
        var copy = FrameCopy.Detach(ReadFirstFrame(WriteDarkFile()));

        var stride = copy.PixelWidth * 4;
        var read = new byte[stride * copy.PixelHeight];
        new FormatConvertedBitmap(copy, PixelFormats.Bgra32, null, 0).CopyPixels(read, stride, 0);
        Assert.Equal(new byte[] { 20, 18, 17, 255 }, read[..4]);
    }

    [Fact]
    public async Task A_detached_copy_is_encoded_from_a_pool_thread()
    {
        var copy = FrameCopy.Detach(ReadFirstFrame(WriteFile("png", 16, 16)));

        var bytes = await Task.Run(() =>
        {
            var encoder = new PngBitmapEncoder();
            encoder.Frames.Add(BitmapFrame.Create(copy));
            using var memory = new MemoryStream();
            encoder.Save(memory);
            return memory.ToArray();
        });

        Assert.NotEmpty(bytes);
    }

    private string WriteFile(string format, int width, int height)
    {
        Directory.CreateDirectory(_root);
        var path = Path.Combine(_root, $"{Guid.NewGuid():N}.{format}");
        var stride = width * 4;
        var pixels = new byte[stride * height];
        for (var i = 0; i < pixels.Length; i += 4)
        {
            pixels[i] = (byte)(i % 251);
            pixels[i + 1] = (byte)(i % 199);
            pixels[i + 2] = (byte)(i % 149);
            pixels[i + 3] = 255;
        }
        var source = BitmapSource.Create(width, height, 96, 96, PixelFormats.Bgra32, null, pixels, stride);
        BitmapEncoder encoder = format == "png" ? new PngBitmapEncoder() : new JpegBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(source));
        using var file = File.Create(path);
        encoder.Save(file);
        return path;
    }

    private string WriteDarkFile()
    {
        Directory.CreateDirectory(_root);
        var path = Path.Combine(_root, $"{Guid.NewGuid():N}.png");
        var pixels = new byte[2 * 2 * 4];
        for (var i = 0; i < pixels.Length; i += 4)
        {
            pixels[i] = 20; pixels[i + 1] = 18; pixels[i + 2] = 17; pixels[i + 3] = 255;
        }
        var source = BitmapSource.Create(2, 2, 96, 96, PixelFormats.Bgra32, null, pixels, 2 * 4);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(source));
        using var file = File.Create(path);
        encoder.Save(file);
        return path;
    }

    private static BitmapSource ReadFirstFrame(string path)
    {
        using var stream = File.OpenRead(path);
        return BitmapDecoder.Create(stream, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad).Frames[0];
    }

    public void Dispose()
    {
        if (Directory.Exists(_root)) Directory.Delete(_root, true);
    }
}
