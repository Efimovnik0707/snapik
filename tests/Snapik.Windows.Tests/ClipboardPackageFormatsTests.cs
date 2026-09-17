using System;
using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace Snapik.Windows.Tests;

/// <summary>
/// A package of one capture is what "Copy capture" puts on the clipboard, and the chat it is pasted
/// into has to see the same formats it sees from a package: the registered PNG a browser reads, the
/// DIB and the Bitmap every desktop application reads, the file the receiver may want to attach and
/// the text of the comments. The single path goes through CreatePngDataObject, so the three image
/// formats come from there; the file list and the text are added on top of it.
/// </summary>
public sealed class ClipboardPackageFormatsTests
{
    [Fact]
    public void A_package_of_one_capture_carries_every_format_a_package_carries()
    {
        var png = WriteSmallPng();
        try
        {
            var data = WindowsClipboardService.CreatePackageDataObject([png], "Снимок B.\r\n  B1: тест");

            Assert.True(data.GetDataPresent("PNG"));
            Assert.True(data.GetDataPresent(DataFormats.Dib));
            Assert.True(data.GetDataPresent(DataFormats.Bitmap));
            Assert.True(data.GetDataPresent(DataFormats.FileDrop));
            Assert.True(data.GetDataPresent(DataFormats.UnicodeText));
            Assert.Equal(png, Assert.Single(data.GetFileDropList()));
            Assert.Equal("Снимок B.\r\n  B1: тест", data.GetText(TextDataFormat.UnicodeText));
        }
        finally
        {
            if (File.Exists(png)) File.Delete(png);
        }
    }

    [Fact]
    public void A_capture_without_comments_puts_no_empty_line_on_the_clipboard()
    {
        var png = WriteSmallPng();
        try
        {
            var data = WindowsClipboardService.CreatePackageDataObject([png], string.Empty);

            Assert.True(data.GetDataPresent("PNG"));
            Assert.False(data.GetDataPresent(DataFormats.UnicodeText));
        }
        finally
        {
            if (File.Exists(png)) File.Delete(png);
        }
    }

    private static string WriteSmallPng()
    {
        var path = Path.Combine(Path.GetTempPath(), $"snapik-clipboard-{Guid.NewGuid():N}.png");
        var bitmap = new WriteableBitmap(4, 4, 96, 96, PixelFormats.Bgra32, null);
        var pixels = new byte[4 * 4 * 4];
        Array.Fill(pixels, (byte)200);
        bitmap.WritePixels(new Int32Rect(0, 0, 4, 4), pixels, 4 * 4, 0);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var stream = File.Create(path);
        encoder.Save(stream);
        return path;
    }
}
