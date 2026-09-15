using System.Windows;
using System.Windows.Media;

namespace Snapik.App.Controls;

/// <summary>
/// Hover and pressed fills read by the button template from the button itself, so a derived style
/// (PrimaryButton) can change them without losing to the template's own setters on the Chrome border.
/// </summary>
public static class ButtonChrome
{
    public static readonly DependencyProperty HoverBackgroundProperty =
        DependencyProperty.RegisterAttached("HoverBackground", typeof(Brush), typeof(ButtonChrome), new PropertyMetadata(Brushes.Transparent));
    public static readonly DependencyProperty PressedBackgroundProperty =
        DependencyProperty.RegisterAttached("PressedBackground", typeof(Brush), typeof(ButtonChrome), new PropertyMetadata(Brushes.Transparent));

    public static Brush? GetHoverBackground(DependencyObject element) => (Brush?)element.GetValue(HoverBackgroundProperty);
    public static void SetHoverBackground(DependencyObject element, Brush? value) => element.SetValue(HoverBackgroundProperty, value);
    public static Brush? GetPressedBackground(DependencyObject element) => (Brush?)element.GetValue(PressedBackgroundProperty);
    public static void SetPressedBackground(DependencyObject element, Brush? value) => element.SetValue(PressedBackgroundProperty, value);
}
