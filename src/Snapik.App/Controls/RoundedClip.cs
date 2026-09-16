using System.Windows;
using System.Windows.Media;

namespace Snapik.App.Controls;

/// <summary>
/// A clip that follows the size of the element it is attached to:
/// <c>Controls:RoundedClip.Radius="10"</c> on a grid rounds whatever is drawn inside it, the
/// thumbnail of a card included. An attached property rather than a converter with a MultiBinding:
/// it is read in two windows, and it maps one to one onto the layer of the macOS port.
/// </summary>
internal static class RoundedClip
{
    public static readonly DependencyProperty RadiusProperty = DependencyProperty.RegisterAttached(
        "Radius", typeof(double), typeof(RoundedClip), new PropertyMetadata(0d, OnRadiusChanged));

    public static double GetRadius(DependencyObject element) => (double)element.GetValue(RadiusProperty);

    public static void SetRadius(DependencyObject element, double value) => element.SetValue(RadiusProperty, value);

    private static void OnRadiusChanged(DependencyObject element, DependencyPropertyChangedEventArgs e)
    {
        if (element is not FrameworkElement target) return;
        target.SizeChanged -= OnSizeChanged;
        if (e.NewValue is double radius && radius > 0)
        {
            target.SizeChanged += OnSizeChanged;
            Apply(target, radius);
        }
        else target.Clip = null;
    }

    private static void OnSizeChanged(object sender, SizeChangedEventArgs e)
    {
        if (sender is FrameworkElement target) Apply(target, GetRadius(target));
    }

    // The size the element was arranged with, not the one it asked for: a clip built from the wrong
    // one cuts the picture instead of rounding it.
    private static void Apply(FrameworkElement target, double radius)
    {
        if (target.ActualWidth <= 0 || target.ActualHeight <= 0) { target.Clip = null; return; }
        target.Clip = new RectangleGeometry(new Rect(0, 0, target.ActualWidth, target.ActualHeight), radius, radius);
    }
}
