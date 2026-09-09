using System;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace SnapBrief.App;

public partial class CaptureOverlay : Window
{
    private readonly BitmapSource _desktop;
    private Point? _start;
    private Rect _selection;

    private CaptureOverlay(BitmapSource desktop, int left, int top, int width, int height)
    {
        InitializeComponent();
        _desktop = desktop;
        DesktopImage.Source = desktop;
        WindowStartupLocation = WindowStartupLocation.Manual;
        Left = 0;
        Top = 0;
        Width = 1;
        Height = 1;
        SourceInitialized += (_, _) =>
        {
            var handle = new WindowInteropHelper(this).Handle;
            SetWindowPos(handle, new IntPtr(-1), left, top, width, height, 0x0010 | 0x0040);
        };
        Loaded += (_, _) => { UpdateShade(); Activate(); Focus(); };
    }

    public BitmapSource? CapturedImage { get; private set; }

    public static async Task<BitmapSource?> CaptureAsync(Window owner)
    {
        owner.Hide();
        await Task.Delay(120);
        try
        {
            var left = GetSystemMetrics(76);
            var top = GetSystemMetrics(77);
            var width = GetSystemMetrics(78);
            var height = GetSystemMetrics(79);
            var bitmap = CaptureDesktop(left, top, width, height);
            var overlay = new CaptureOverlay(bitmap, left, top, width, height) { Owner = owner };
            overlay.ShowDialog();
            return overlay.CapturedImage;
        }
        finally
        {
            owner.Show();
            owner.Activate();
        }
    }

    public static DesktopFrame CaptureDesktopFrame(bool includeCursor = false)
    {
        var left = GetSystemMetrics(76);
        var top = GetSystemMetrics(77);
        var width = GetSystemMetrics(78);
        var height = GetSystemMetrics(79);
        return new DesktopFrame(CaptureDesktop(left, top, width, height, includeCursor), left, top, width, height);
    }

    private static BitmapSource CaptureDesktop(int left, int top, int width, int height, bool includeCursor = false)
    {
        using var bitmap = new System.Drawing.Bitmap(width, height, System.Drawing.Imaging.PixelFormat.Format32bppPArgb);
        using (var graphics = System.Drawing.Graphics.FromImage(bitmap))
        {
            graphics.CopyFromScreen(left, top, 0, 0, new System.Drawing.Size(width, height), System.Drawing.CopyPixelOperation.SourceCopy);
            if (includeCursor) CaptureCursorDrawing.Draw(graphics, left, top);
        }
        var handle = bitmap.GetHbitmap();
        try
        {
            var source = System.Windows.Interop.Imaging.CreateBitmapSourceFromHBitmap(handle, IntPtr.Zero, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());
            source.Freeze();
            return source;
        }
        finally { DeleteObject(handle); }
    }

    private void OnMouseDown(object sender, MouseButtonEventArgs e)
    {
        _start = e.GetPosition(this);
        _selection = new Rect(_start.Value, _start.Value);
        CaptureMouse();
        UpdateSelection();
    }

    private void OnMouseMove(object sender, MouseEventArgs e)
    {
        if (_start is null || e.LeftButton != MouseButtonState.Pressed) return;
        var point = e.GetPosition(this);
        _selection = Normalize(_start.Value, point);
        UpdateSelection();
    }

    private void OnMouseUp(object sender, MouseButtonEventArgs e)
    {
        if (_start is null) return;
        ReleaseMouseCapture();
        if (_selection.Width >= 4 && _selection.Height >= 4)
        {
            var scaleX = _desktop.PixelWidth / ActualWidth;
            var scaleY = _desktop.PixelHeight / ActualHeight;
            var crop = new Int32Rect(
                Math.Clamp((int)Math.Round(_selection.X * scaleX), 0, _desktop.PixelWidth - 1),
                Math.Clamp((int)Math.Round(_selection.Y * scaleY), 0, _desktop.PixelHeight - 1),
                Math.Clamp((int)Math.Round(_selection.Width * scaleX), 1, _desktop.PixelWidth),
                Math.Clamp((int)Math.Round(_selection.Height * scaleY), 1, _desktop.PixelHeight));
            if (crop.X + crop.Width > _desktop.PixelWidth) crop.Width = _desktop.PixelWidth - crop.X;
            if (crop.Y + crop.Height > _desktop.PixelHeight) crop.Height = _desktop.PixelHeight - crop.Y;
            var cropped = new CroppedBitmap(_desktop, crop);
            cropped.Freeze();
            CapturedImage = cropped;
            DialogResult = true;
        }
        else
        {
            _start = null;
            _selection = Rect.Empty;
            UpdateSelection();
        }
    }

    private void UpdateSelection()
    {
        var visible = _selection.Width > 0 && _selection.Height > 0;
        SelectionBorder.Visibility = visible ? Visibility.Visible : Visibility.Collapsed;
        SizeBadge.Visibility = visible ? Visibility.Visible : Visibility.Collapsed;
        if (visible)
        {
            SelectionBorder.Margin = new Thickness(_selection.Left, _selection.Top, 0, 0);
            SelectionBorder.Width = _selection.Width;
            SelectionBorder.Height = _selection.Height;
            SelectionBorder.HorizontalAlignment = HorizontalAlignment.Left;
            SelectionBorder.VerticalAlignment = VerticalAlignment.Top;
            SizeBadge.Margin = new Thickness(_selection.Left, Math.Max(0, _selection.Top - 28), 0, 0);
            SizeText.Text = $"{Math.Round(_selection.Width)} × {Math.Round(_selection.Height)}";
        }
        UpdateShade();
    }

    private void UpdateShade()
    {
        var geometry = new PathGeometry { FillRule = FillRule.EvenOdd };
        geometry.AddGeometry(new RectangleGeometry(new Rect(0, 0, ActualWidth, ActualHeight)));
        if (_selection.Width > 0 && _selection.Height > 0) geometry.AddGeometry(new RectangleGeometry(_selection));
        Shade.Data = geometry;
    }

    private void OnKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key != Key.Escape) return;
        DialogResult = false;
        e.Handled = true;
    }

    private static Rect Normalize(Point a, Point b) => new(new Point(Math.Min(a.X, b.X), Math.Min(a.Y, b.Y)), new Point(Math.Max(a.X, b.X), Math.Max(a.Y, b.Y)));

    [DllImport("user32.dll")]
    private static extern int GetSystemMetrics(int index);

    [DllImport("gdi32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DeleteObject(IntPtr handle);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWindowPos(IntPtr hwnd, IntPtr insertAfter, int x, int y, int width, int height, uint flags);
}

public sealed record DesktopFrame(BitmapSource Image, int Left, int Top, int PixelWidth, int PixelHeight);

