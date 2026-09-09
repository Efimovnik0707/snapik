// Port of the color tokens in `Themes/SnapBriefTheme.xaml` and the dark palette hard-coded in
// `EdgeStackWindow.xaml` / `OverlayEditorWindow.xaml`, SPEC §6.0.
//
// `NSColor.init(hex:)` (`"#RRGGBB"`/`"#AARRGGBB"`) is not declared here: it already exists as an
// `NSColor` extension in `Sources/SnapBriefMac/Editor/EditorTheme.swift` (exec-editor's zone),
// and since both files compile into the same `SnapBriefMac` target, redeclaring it here would be
// a duplicate-symbol build error. Reused as-is.
import AppKit

/// Light theme tokens (`Themes/SnapBriefTheme.xaml:3-13`), used by the settings window only.
enum LightTheme {
    static let ink = NSColor(hex: "#172033")
    static let mutedInk = NSColor(hex: "#5E687A")
    static let accent = NSColor(hex: "#315CF5")
    static let accentHover = NSColor(hex: "#2449D8")
    static let paper = NSColor(hex: "#FCFBF8")
    static let chrome = NSColor(hex: "#F3F5F8")
    static let panel = NSColor(hex: "#FFFFFF")
    static let line = NSColor(hex: "#DDE2EA")
    static let hover = NSColor(hex: "#E8ECF3")
    static let selected = NSColor(hex: "#E8EDFF")
    static let danger = NSColor(hex: "#B42318")
}

/// Dark palette used by the edge stack and overlay editor surfaces (not a named XAML resource
/// dictionary on Windows — collected here from the literal colors in the markup, SPEC §6.0).
enum DarkPalette {
    static let floatingPanelBackground = NSColor(hex: "#F2171A20")
    static let hintBackground = NSColor(hex: "#E8171A20")
    static let thumbnailStripBackground = NSColor(hex: "#D9171A20")
    static let cardBackground = NSColor(hex: "#242A33")
    static let cardBorder = NSColor(hex: "#39424E")
    static let fieldBorder = NSColor(hex: "#3A424E")
    static let buttonBorder = NSColor(hex: "#333C49")
    static let panelHover = NSColor(hex: "#29303A")
    static let stackHover = NSColor(hex: "#303845")
    static let accent = NSColor(hex: "#2F8CFF")
    static let toolEnabledBackground = NSColor(hex: "#253B58")
    static let toolEnabledBorder = NSColor(hex: "#2F8CFF")
    static let focusRing = NSColor(hex: "#7AB8FF")
    static let primaryText = NSColor(hex: "#EEF2F8")
    static let secondaryTextD9 = NSColor(hex: "#D9DEE8")
    static let secondaryTextBF = NSColor(hex: "#BFC8D6")
    static let secondaryText9A = NSColor(hex: "#9AA7B8")
    static let secondaryTextAE = NSColor(hex: "#AEB8C7")
    static let errorText = NSColor(hex: "#FF9B95")
    static let chipFieldBackground = NSColor(hex: "#262B34")
    static let settingsFieldBackground = NSColor(hex: "#252B35")
    static let settingsWindowBackground = NSColor(hex: "#171B22")
    static let settingsWindowBorder = NSColor(hex: "#354052")
    static let restoreLinkText = NSColor(hex: "#7AB8FF")
}

enum ThemeMetrics {
    static let stackWidth: CGFloat = 196
    static let stackMinHeight: CGFloat = 128
    static let stackMaxHeight: CGFloat = 620
    static let stackEdgeInset: CGFloat = 10
    static let stackAppearAnimationSeconds: CGFloat = 0.18
    static let cardHeight: CGFloat = 82
    static let cardCornerRadius: CGFloat = 10
    static let cardListMaxHeight: CGFloat = 346
    static let outerCornerRadius: CGFloat = 16
    static let outerPadding: CGFloat = 10
    static let buttonCornerRadius: CGFloat = 10
    static let buttonHeight: CGFloat = 36
}
