using System;
using System.IO;
using System.Threading.Tasks;
using System.Windows.Media.Imaging;

namespace SnapBrief.App;

internal static class LocalImageSave
{
    internal static async Task WriteAsync(BitmapSource image, string path, string format, int quality, bool overwrite)
    {
        image.Freeze();
        var bytes = await Task.Run(() =>
        {
            BitmapEncoder encoder = format == "jpeg" ? new JpegBitmapEncoder { QualityLevel = Math.Clamp(quality, 1, 100) } : new PngBitmapEncoder();
            encoder.Frames.Add(BitmapFrame.Create(image));
            using var stream = new MemoryStream();
            encoder.Save(stream);
            return stream.ToArray();
        });
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
        // Encode before touching an existing file; atomically replace only after the full write succeeds.
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try { await File.WriteAllBytesAsync(temporary, bytes); File.Move(temporary, path, overwrite); }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
    internal static string NewPath(HotkeySettings settings) => Path.Combine(settings.SaveDirectory,
        $"SnapBrief-{DateTime.Now:yyyy-MM-dd-HHmmss-fff}-{Guid.NewGuid().ToString("N")[..4]}.{(settings.SaveFormat == "jpeg" ? "jpg" : "png")}");
}
