// Port of Themes/SnapBriefTheme.xaml (dark overlay/toolbar palette only), SPEC §6.0
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
/// поверхностей"). The light `SnapBriefTheme.xaml` tokens are not needed here: the settings
/// window is owned by exec-shell.
enum EditorTheme {
    // Backgrounds
    static let overlayWindowBackground = NSColor(hex: "#0A0D12")
    static let shade = NSColor(hex: "#A20A0D12")
    static let toolbarBackground = NSColor(hex: "#F2171A20")
    static let annotationChipBackground = NSColor(hex: "#F4171A20")
    static let hintBackground = NSColor(hex: "#E8171A20")
    static let shotNoteChipBackground = NSColor(hex: "#F2171A20")
    static let shotNoteFieldBackground = NSColor(hex: "#262B34")
    static let contextNoteButtonBackground = NSColor(hex: "#F2171A20")
    static let toolHoverBackground = NSColor(hex: "#29303A")
    static let toolActiveBackground = NSColor(hex: "#253B58")
    static let moreToolsMenuBackground = NSColor(hex: "#F8171A20")

    // Borders / dividers
    static let contextNoteButtonBorder = NSColor(hex: "#46515F")
    static let toolbarBorder = NSColor(hex: "#3A424E")
    static let toolbarDivider = NSColor(hex: "#3A424E")
    static let moreToolsMenuBorder = NSColor(hex: "#3A424E")
    static let shotNoteFieldBorder = NSColor(hex: "#3A424E")
    static let focusRing = NSColor(hex: "#7AB8FF")
    static let cropBorder = NSColor(hex: "#2F8CFF")

    // Text
    static let textPrimary = NSColor(hex: "#EEF2F8")
    static let textSecondaryD9 = NSColor(hex: "#D9DEE8")
    static let textSecondaryBF = NSColor(hex: "#BFC8D6")
    static let textSecondary9A = NSColor(hex: "#9AA7B8")
    static let textSecondaryAE = NSColor(hex: "#AEB8C7")
    static let errorText = NSColor(hex: "#FF9B95")

    // Accent / annotation palette (SPEC §1.3, cycled by the color button)
    static let accent = NSColor(hex: "#2F8CFF")
    static let annotationPalette: [NSColor] = [
        NSColor(hex: "#2F8CFF"),
        NSColor(hex: "#FF4D4F"),
        NSColor(hex: "#FFBE2E"),
        NSColor(hex: "#28BE80"),
    ]

    // Selection / handles (SPEC §6.3)
    static let selectionOutline = NSColor(hex: "#315CF5")
    static let handleFill = NSColor.white
    static let handleBorder = NSColor(hex: "#2F8CFF")

    // Blur / crop draft fills (SPEC §1.7, §6.3)
    static let blurPreviewFill = NSColor(hex: "#36FFFFFF")
    static let cropPreviewFill = NSColor(hex: "#182F8CFF")

    // Thicknesses / radii
    static let toolbarCornerRadius: CGFloat = 16
    static let toolCornerRadius: CGFloat = 9
    static let buttonCornerRadius: CGFloat = 9
    static let annotationChipCornerRadius: CGFloat = 13
    static let shotNoteChipCornerRadius: CGFloat = 12
    static let hintCornerRadius: CGFloat = 10
    static let menuCornerRadius: CGFloat = 6

    // Fonts (SPEC §6.0: SF Pro Text at the same point sizes as the Windows Segoe UI Variable Text)
    static func systemFont(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: weight)
    }
}
