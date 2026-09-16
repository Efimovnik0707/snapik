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
