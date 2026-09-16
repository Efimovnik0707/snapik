using System.Windows.Media.Imaging;

namespace Snapik.App.Imaging;

/// <summary>Takes a frame away from the decoder that produced it.</summary>
public static class FrameCopy
{
    /// <summary>
    /// A BitmapFrame holds on to the decoder and to the stream it was read from, and a frozen frame
    /// is still not safe to encode from another thread: the decoder behind it is not. The copy owns
    /// its pixels, so the stream can be closed at once and the picture can travel into a pool
    /// thread. An indexed format keeps its palette: WriteableBitmap copies the format as it is.
    /// </summary>
    public static BitmapSource Detach(BitmapSource frame)
    {
        var copy = new WriteableBitmap(frame);
        copy.Freeze();
        return copy;
    }
}
