// Port of Themes/SnapikTheme.xaml (dark overlay/toolbar palette only), SPEC §6.0
import AppKit

/// Parses a `#RRGGBB` or `#AARRGGBB` hex string (as used verbatim throughout SPEC.md) into an
/// `NSColor`. Kept private to this file; every editor color is defined once below via this
/// helper so the hex literals here can be diffed 1:1 against the spec tables.
extension NSColor {
    convenience init(hex: String) {
        var value: UInt64 = 0
        let hexString = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        Scanner(string: hexString).scanHexInt64(&value)

        let a: CGFloat
        let r: CGFloat
        let g: CGFloat
        let b: CGFloat
        if hexString.count == 8 {
            a = CGFloat((value & 0xFF00_0000) >> 24) / 255.0
            r = CGFloat((value & 0x00FF_0000) >> 16) / 255.0
            g = CGFloat((value & 0x0000_FF00) >> 8) / 255.0
            b = CGFloat(value & 0x0000_00FF) / 255.0
        } else {
            a = 1.0
            r = CGFloat((value & 0xFF_0000) >> 16) / 255.0
            g = CGFloat((value & 0x00_FF00) >> 8) / 255.0
            b = CGFloat(value & 0x00_00FF) / 255.0
        }
        self.init(srgbRed: r, green: g, blue: b, alpha: a)
    }
}

/// Dark palette tokens used by the overlay/editor surfaces (SPEC §6.0, "Тёмная палитра основных
/// поверхностей"). The light `SnapikTheme.xaml` tokens are not needed here: the settings
/// window is owned by exec-shell.
enum EditorTheme {
    // Backgrounds
    static let overlayWindowBackground = NSColor(hex: "#0A0D12")
    static let shade = NSColor(hex: "#A20A0D12")
    static let toolbarBackground = NSColor(hex: "#F2171A20")
    static let annotationChipBackground = NSColor(hex: "#F4171A20")
    static let hintBackground = NSColor(hex: "#E8171A20")
    static let toolHoverBackground = NSColor(hex: "#29303A")
    static let toolActiveBackground = NSColor(hex: "#253B58")
    static let moreToolsMenuBackground = NSColor(hex: "#F8171A20")

    // Borders / dividers
    static let toolbarBorder = NSColor(hex: "#3A424E")
    static let toolbarDivider = NSColor(hex: "#3A424E")
    static let moreToolsMenuBorder = NSColor(hex: "#3A424E")
    static let focusRing = NSColor(hex: "#7AB8FF")
    static var cropBorder: NSColor { accent }

    // Text
    static let textPrimary = NSColor(hex: "#EEF2F8")
    static let textSecondaryD9 = NSColor(hex: "#D9DEE8")
    static let textSecondaryBF = NSColor(hex: "#BFC8D6")
    static let textSecondary9A = NSColor(hex: "#9AA7B8")
    static let textSecondaryAE = NSColor(hex: "#AEB8C7")
    static let errorText = NSColor(hex: "#FF9B95")

    // Accent (SPEC-DELTA-3 §1.4 E-15): everything the editor draws as chrome reads the accent from
    // `AccentPalette` and from nowhere else, so a violet accent reaches the badge and the crop
    // border as well as the settings window. What used to be the colour of a *mark* is
    // `defaultAnnotationColor` below instead.
    static var accent: NSColor { AccentPalette.flat }

    /// Red, the first colour of the standard palette (`OverlayEditorWindow.Appearance.cs:20`): on a
    /// clean install the active colour has to belong to the palette, otherwise no swatch is circled.
    static let defaultAnnotationColor = NSColor(hex: "#FF3B30")

    // Appearance popover (SPEC §1.3, §6.2 "Дополнение 2026-09-09", port of the new
    // `AppearancePopup`/`StrokeSliderStyle` chrome in `Themes/SnapikTheme.xaml`/
    // `OverlayEditorWindow.xaml:40-52,147-158`). No separate border/corner-radius token: unlike
    // WPF's borderless `Popup`, `NSPopover` draws and clips its own rounded bezel, so this content
    // view only fills a flat background (`EditorAppearancePopoverContentView.draw(_:)`).
    static let appearancePopoverBackground = NSColor(hex: "#171A20")
    static let appearanceHexFieldBackground = NSColor(hex: "#252C36")
    static let appearanceHexFieldBorder = NSColor(hex: "#465366")
    static let appearanceHexFieldErrorBorder = NSColor(hex: "#FF6E6E")
    static let appearancePreviewBackground = NSColor(hex: "#222933")
    static let appearanceSliderFilledTrack = NSColor(hex: "#5EAAFF")
    static let appearanceSliderEmptyTrack = NSColor(hex: "#465366")
    static let appearanceSliderThumbFill = NSColor(hex: "#EEF2F8")
    static let appearanceSliderThumbBorder = NSColor(hex: "#8193AB")
    /// The "•••" button's active-extra-tool highlight (`Color.FromRgb(40, 75, 120)`,
    /// `OverlayEditorWindow.Appearance.cs:66`).
    static let moreToolsActiveBackground = NSColor(hex: "#284B78")

    // Selection / handles (SPEC §6.3). The frame and the handles take the accent, like everything
    // else the editor draws as chrome (SPEC-DELTA-3 §1.4 E-15).
    static let handleFill = NSColor.white
    static var handleBorder: NSColor { accent }

    /// The outline the eraser puts around what it is about to take (`AnnotationCanvas.cs:160`,
    /// SPEC-DELTA-3 §1.4 E-5). A colour of its own and not the accent: it means "this goes away".
    static let eraseHoverOutline = NSColor(hex: "#FF3B30")

    // Blur / crop draft fills (SPEC §1.7, §6.3)
    static let blurPreviewFill = NSColor(hex: "#36FFFFFF")
    static let cropPreviewFill = NSColor(hex: "#182F8CFF")

    // Thicknesses / radii
    static let toolbarCornerRadius: CGFloat = 16
    static let toolCornerRadius: CGFloat = 9
    static let buttonCornerRadius: CGFloat = 9
    static let annotationChipCornerRadius: CGFloat = 13
    static let hintCornerRadius: CGFloat = 10
    static let menuCornerRadius: CGFloat = 6
    static let appearancePreviewCornerRadius: CGFloat = 7

    // Fonts (SPEC §6.0: SF Pro Text at the same point sizes as the Windows Segoe UI Variable Text)
    static func systemFont(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: weight)
    }
}
