using System;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using Snapik.App.Imaging;

namespace Snapik.App.Controls;

/// <summary>
/// The whole circle of colours in two pieces: a strip of hue and a square where saturation runs
/// left to right and brightness top to bottom. What is picked here is a colour like any other, and
/// the HEX field beside it shows the same one.
///
/// The hue, the saturation and the brightness are kept as numbers rather than read back out of the
/// colour every time: black has no hue and grey has no saturation, so a marker dragged into the
/// corner would otherwise jump back to red on the way out.
/// </summary>
public partial class ColorSpectrum : UserControl
{
    private double _hue;
    private double _saturation = 1;
    private double _brightness = 1;
    private bool _dragging;

    public ColorSpectrum()
    {
        InitializeComponent();
        Loaded += (_, _) => Refresh();
        Refresh();
    }

    /// <summary>Raised while the colour is being picked, on every move of a marker.</summary>
    public event EventHandler? ColorChanged;

    /// <summary>Raised once the picking is over: what the row of saved colours listens to.</summary>
    public event EventHandler? ColorCommitted;

    /// <summary>
    /// The colour the markers stand on. Set from outside (the HEX field, a swatch) it moves them;
    /// a colour without a hue of its own leaves the strip where it is.
    /// </summary>
    public Color SelectedColor
    {
        get => ColorConversion.HsvToRgb(_hue, _saturation, _brightness);
        set
        {
            var (hue, saturation, brightness) = ColorConversion.RgbToHsv(value);
            if (saturation > 0) _hue = hue;
            _saturation = saturation;
            _brightness = brightness;
            Refresh();
        }
    }

    internal void ApplyLanguage(string language)
    {
        AutomationProperties.SetName(Hue, UiLanguage.Text("Оттенок", language));
        AutomationProperties.SetName(Square, UiLanguage.Text("Насыщенность и яркость", language));
    }

    private void Refresh()
    {
        SaturationLayer.Fill = new LinearGradientBrush(
            Color.FromRgb(0xFF, 0xFF, 0xFF), ColorConversion.HsvToRgb(_hue, 1, 1), new Point(0, 0), new Point(1, 0));
        var x = _saturation * Square.Width;
        var y = (1 - _brightness) * Square.Height;
        foreach (var marker in new FrameworkElement[] { SquareMarker, SquareMarkerShadow })
        {
            Canvas.SetLeft(marker, x - marker.Width / 2);
            Canvas.SetTop(marker, y - marker.Height / 2);
        }
        Canvas.SetLeft(HueMarker, (Hue.Width - HueMarker.Width) / 2);
        Canvas.SetTop(HueMarker, _hue / 360 * Hue.Height - HueMarker.Height / 2);
    }

    private void OnSquarePressed(object sender, MouseButtonEventArgs e)
    {
        _dragging = Square.CaptureMouse();
        PickInSquare(e.GetPosition(Square));
    }

    private void OnSquareMoved(object sender, MouseEventArgs e)
    {
        if (_dragging && e.LeftButton == MouseButtonState.Pressed) PickInSquare(e.GetPosition(Square));
    }

    private void OnHuePressed(object sender, MouseButtonEventArgs e)
    {
        _dragging = Hue.CaptureMouse();
        PickInHue(e.GetPosition(Hue));
    }

    private void OnHueMoved(object sender, MouseEventArgs e)
    {
        if (_dragging && e.LeftButton == MouseButtonState.Pressed) PickInHue(e.GetPosition(Hue));
    }

    // The press is what the picking runs on, and the release is what it is remembered by: a colour
    // dragged through is shown, a colour let go of is saved.
    private void OnReleased(object sender, MouseButtonEventArgs e)
    {
        if (!_dragging) return;
        _dragging = false;
        ((UIElement)sender).ReleaseMouseCapture();
        ColorCommitted?.Invoke(this, EventArgs.Empty);
    }

    internal void PickInSquare(Point position)
    {
        _saturation = Math.Clamp(position.X / Square.Width, 0, 1);
        _brightness = 1 - Math.Clamp(position.Y / Square.Height, 0, 1);
        Refresh();
        ColorChanged?.Invoke(this, EventArgs.Empty);
    }

    internal void PickInHue(Point position)
    {
        _hue = Math.Clamp(position.Y / Hue.Height, 0, 1) * 360;
        Refresh();
        ColorChanged?.Invoke(this, EventArgs.Empty);
    }

    /// <summary>
    /// The smoke check: the strip moves the hue, the square moves the saturation and the brightness,
    /// and a colour given from outside puts both markers where that colour lives.
    /// </summary>
    internal static void RunProbe()
    {
        var spectrum = new ColorSpectrum();
        spectrum.ApplyLanguage("en");
        spectrum.Measure(new Size(240, 180));
        spectrum.Arrange(new Rect(0, 0, 240, 180));
        var changes = 0;
        spectrum.ColorChanged += (_, _) => changes++;
        spectrum.PickInHue(new Point(8, 80));
        spectrum.PickInSquare(new Point(160, 0));
        if (changes != 2 || spectrum.SelectedColor != Color.FromRgb(0x00, 0xFF, 0xFF))
            throw new InvalidOperationException("The middle of the strip with the corner of the square must be pure cyan.");
        spectrum.SelectedColor = Color.FromRgb(0x2F, 0x8C, 0xFF);
        if (spectrum.SelectedColor != Color.FromRgb(0x2F, 0x8C, 0xFF) ||
            Math.Abs(Canvas.GetTop(spectrum.HueMarker) + spectrum.HueMarker.Height / 2 -
                     ColorConversion.RgbToHsv(Color.FromRgb(0x2F, 0x8C, 0xFF)).Hue / 360 * spectrum.Hue.Height) > 0.5)
            throw new InvalidOperationException("A colour given from outside must move the markers to where it lives.");
        // Black has no hue of its own; the strip must not jump back to red under it.
        var blueHue = ColorConversion.RgbToHsv(Color.FromRgb(0x2F, 0x8C, 0xFF)).Hue;
        spectrum.SelectedColor = Color.FromRgb(0, 0, 0);
        spectrum.PickInSquare(new Point(160, 0));
        if (spectrum.SelectedColor != ColorConversion.HsvToRgb(blueHue, 1, 1))
            throw new InvalidOperationException("A colour without a hue must leave the strip where it stands.");
    }
}
