using System.Collections.Specialized;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace SnapBrief.Windows;

public sealed partial class WindowsClipboardService : IClipboardService, IDisposable
{
    private const int ClipboardBusyHResult = unchecked((int)0x800401D0);
    private readonly StaWorkQueue queue = new("SnapBrief clipboard");
    private readonly int retryCount;

    public WindowsClipboardService(int retryCount = 5)
    {
        if (retryCount < 1) throw new ArgumentOutOfRangeException(nameof(retryCount));
        this.retryCount = retryCount;
    }

    public Task<ClipboardSnapshot> CaptureAsync(CancellationToken cancellationToken) =>
        queue.InvokeAsync(CaptureCore, cancellationToken);

    public Task<ClipboardWriteReceipt> SetPackageGuardedAsync(
        IReadOnlyList<string> pngPaths,
        string text,
        uint expectedSequenceNumber,
        CancellationToken cancellationToken) => queue.InvokeAsync(() =>
        {
            var data = CreatePackageDataObject(pngPaths, text);
            SetDataObjectWithRetry(data, expectedSequenceNumber);
            return new ClipboardWriteReceipt(GetClipboardSequenceNumber());
        }, cancellationToken);

    public Task<ClipboardWriteReceipt> SetPngOnlyGuardedAsync(
        string pngPath,
        uint expectedSequenceNumber,
        CancellationToken cancellationToken) => queue.InvokeAsync(() =>
        {
            var data = CreatePngOnlyDataObject(pngPath);
            SetDataObjectWithRetry(data, expectedSequenceNumber);
            return new ClipboardWriteReceipt(GetClipboardSequenceNumber());
        }, cancellationToken);

    public Task<ClipboardWriteReceipt> SetPngGuardedAsync(string pngPath, uint expectedSequenceNumber, CancellationToken cancellationToken) =>
        queue.InvokeAsync(() =>
        {
            var data = CreatePngDataObject(pngPath);
            SetDataObjectWithRetry(data, expectedSequenceNumber);
            return new ClipboardWriteReceipt(GetClipboardSequenceNumber());
        }, cancellationToken);

    public Task<ClipboardWriteReceipt> SetTextGuardedAsync(string text, uint expectedSequenceNumber, CancellationToken cancellationToken) =>
        queue.InvokeAsync(() =>
        {
            var data = new DataObject();
            data.SetText(text, TextDataFormat.UnicodeText);
            SetDataObjectWithRetry(data, expectedSequenceNumber);
            return new ClipboardWriteReceipt(GetClipboardSequenceNumber());
        }, cancellationToken);

    public Task<bool> IsCurrentAsync(ClipboardWriteReceipt receipt, CancellationToken cancellationToken) =>
        queue.InvokeAsync(() => GetClipboardSequenceNumber() == receipt.SequenceNumber, cancellationToken);

    public Task<bool> RestoreIfCurrentAsync(
        ClipboardSnapshot snapshot,
        ClipboardWriteReceipt receipt,
        CancellationToken cancellationToken) => queue.InvokeAsync(() =>
        {
            if (!snapshot.IsComplete || GetClipboardSequenceNumber() != receipt.SequenceNumber) return false;
            var data = new DataObject();
            foreach (var item in snapshot.Data) data.SetData(item.Key, CloneClipboardValue(item.Value), false);
            SetDataObjectWithRetry(data);
            return true;
        }, cancellationToken);

    private ClipboardSnapshot CaptureCore()
    {
        for (var attempt = 0; attempt < retryCount; attempt++)
        {
            var sequenceBefore = GetClipboardSequenceNumber();
            var source = GetDataObjectWithRetry();
            if (source is null) return new(sequenceBefore, new Dictionary<string, object>(), true);

            var copy = new Dictionary<string, object>(StringComparer.Ordinal);
            var complete = true;
            foreach (var format in source.GetFormats(autoConvert: false))
            {
                try
                {
                    var value = source.GetData(format, autoConvert: false);
                    if (value is not null) copy[format] = CloneClipboardValue(value);
                }
                catch
                {
                    complete = false;
                }
            }
            var sequenceAfter = GetClipboardSequenceNumber();
            if (sequenceBefore == sequenceAfter) return new(sequenceAfter, copy, complete);
        }
        throw new ClipboardChangedException();
    }

    private IDataObject? GetDataObjectWithRetry() => Retry(Clipboard.GetDataObject);

    private void SetDataObjectWithRetry(IDataObject data, uint? expectedSequenceNumber = null)
    {
        var ownsClipboard = false;
        for (var attempt = 0; ; attempt++)
        {
            if (ownsClipboard && !Clipboard.IsCurrent(data)) throw new ClipboardChangedException();
            if (!ownsClipboard && expectedSequenceNumber.HasValue) RequireCurrent(expectedSequenceNumber.Value);
            try
            {
                if (ownsClipboard) Clipboard.Flush();
                else Clipboard.SetDataObject(data, copy: true);
                return;
            }
            catch (COMException ex) when (ex.HResult == ClipboardBusyHResult && attempt + 1 < retryCount)
            {
                // SetDataObject(copy:true) first becomes owner, then flushes. If only the
                // flush failed, continue flushing our object instead of treating our own
                // sequence increment as an external clipboard write.
                ownsClipboard = Clipboard.IsCurrent(data);
                Thread.Sleep(TimeSpan.FromMilliseconds(20 * (attempt + 1)));
            }
        }
    }

    private static void RequireCurrent(uint expectedSequenceNumber)
    {
        if (GetClipboardSequenceNumber() != expectedSequenceNumber) throw new ClipboardChangedException();
    }

    private T Retry<T>(Func<T> action)
    {
        for (var attempt = 0; ; attempt++)
        {
            try { return action(); }
            catch (COMException ex) when (ex.HResult == ClipboardBusyHResult && attempt + 1 < retryCount)
            {
                Thread.Sleep(TimeSpan.FromMilliseconds(20 * (attempt + 1)));
            }
        }
    }

    private static object CloneClipboardValue(object value) => value switch
    {
        MemoryStream stream => new MemoryStream(stream.ToArray(), writable: false),
        Stream stream => CopyStream(stream),
        string[] paths => paths.ToArray(),
        StringCollection collection => CloneCollection(collection),
        BitmapSource bitmap => CloneBitmap(bitmap),
        ICloneable cloneable => cloneable.Clone()!,
        _ => value,
    };

    private static MemoryStream CopyStream(Stream source)
    {
        var originalPosition = source.CanSeek ? source.Position : 0;
        if (source.CanSeek) source.Position = 0;
        var destination = new MemoryStream();
        source.CopyTo(destination);
        destination.Position = 0;
        if (source.CanSeek) source.Position = originalPosition;
        return destination;
    }

    private static StringCollection CloneCollection(StringCollection source)
    {
        var copy = new StringCollection();
        copy.AddRange(source.Cast<string>().ToArray());
        return copy;
    }

    private static BitmapSource CloneBitmap(BitmapSource source)
    {
        var clone = source.Clone();
        clone.Freeze();
        return clone;
    }

    private static BitmapImage DecodePng(byte[] bytes)
    {
        using var stream = new MemoryStream(bytes, writable: false);
        var image = new BitmapImage();
        image.BeginInit();
        image.CacheOption = BitmapCacheOption.OnLoad;
        image.StreamSource = stream;
        image.EndInit();
        image.Freeze();
        return image;
    }

    internal static DataObject CreatePngDataObject(string pngPath)
    {
        var bytes = File.ReadAllBytes(pngPath);
        var image = DecodePng(bytes);
        var data = CreatePngOnlyDataObject(bytes);
        data.SetData(DataFormats.Dib, CreateDib(image), false);
        data.SetData(DataFormats.Bitmap, image, true);
        return data;
    }

    internal static DataObject CreatePngOnlyDataObject(string pngPath) =>
        CreatePngOnlyDataObject(File.ReadAllBytes(pngPath));

    private static DataObject CreatePngOnlyDataObject(byte[] bytes)
    {
        var data = new DataObject();
        // Chromium reads its registered PNG format as the complete HGLOBAL byte
        // range. A fixed-size stream preserves the file's exact encoded bytes when
        // WPF persists the data object with copy:true.
        data.SetData("PNG", new MemoryStream(bytes, writable: false), false);
        return data;
    }

    internal static DataObject CreatePackageDataObject(IReadOnlyList<string> pngPaths, string text)
    {
        ArgumentNullException.ThrowIfNull(pngPaths);
        ArgumentNullException.ThrowIfNull(text);
        if (pngPaths.Count == 0) throw new ArgumentException("A clipboard package needs at least one PNG path.", nameof(pngPaths));

        // A single image can expose both standard image representations and its
        // file path. Multi-image packages remain an ordered file list because the
        // Windows clipboard has no standard format for multiple independent images.
        var data = pngPaths.Count == 1 ? CreatePngDataObject(pngPaths[0]) : new DataObject();
        var files = new StringCollection();
        foreach (var path in pngPaths) files.Add(path);
        data.SetFileDropList(files);
        data.SetText(text, TextDataFormat.UnicodeText);
        return data;
    }

    internal static MemoryStream CreateDib(BitmapSource source)
    {
        const int bitmapInfoHeaderSize = 40;
        var converted = source.Format == PixelFormats.Bgra32
            ? source
            : new FormatConvertedBitmap(source, PixelFormats.Bgra32, null, 0);
        var stride = checked(converted.PixelWidth * 4);
        var pixels = new byte[checked(stride * converted.PixelHeight)];
        converted.CopyPixels(pixels, stride, 0);

        var stream = new MemoryStream(bitmapInfoHeaderSize + pixels.Length);
        using (var writer = new BinaryWriter(stream, System.Text.Encoding.UTF8, leaveOpen: true))
        {
            writer.Write(bitmapInfoHeaderSize);
            writer.Write(converted.PixelWidth);
            writer.Write(converted.PixelHeight); // Positive height: DIB rows are bottom-up.
            writer.Write((ushort)1);
            writer.Write((ushort)32);
            writer.Write(0u); // BI_RGB
            writer.Write((uint)pixels.Length);
            writer.Write(0);
            writer.Write(0);
            writer.Write(0u);
            writer.Write(0u);
            for (var row = converted.PixelHeight - 1; row >= 0; row--)
                writer.Write(pixels, row * stride, stride);
        }
        stream.Position = 0;
        return stream;
    }

    public void Dispose() => queue.Dispose();

    [LibraryImport("user32.dll")]
    private static partial uint GetClipboardSequenceNumber();
}
