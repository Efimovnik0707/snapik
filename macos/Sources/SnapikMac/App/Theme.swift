// Port of the color tokens in `Themes/SnapikTheme.xaml` and the dark palette hard-coded in
// `EdgeStackWindow.xaml` / `OverlayEditorWindow.xaml`, SPEC §6.0.
//
// `NSColor.init(hex:)` (`"#RRGGBB"`/`"#AARRGGBB"`) is not declared here: it already exists as an
// `NSColor` extension in `Sources/SnapikMac/Editor/EditorTheme.swift` (exec-editor's zone),
// and since both files compile into the same `SnapikMac` target, redeclaring it here would be
// a duplicate-symbol build error. Reused as-is.
import AppKit

/// A brush of a palette or of an accent: one colour, or a run of them along a line. The points are
/// the WPF ones verbatim — the unit square of the element being painted, `0,0` its top-left corner —
/// so the numbers of `Themes/Palettes/*.xaml` are read here as they are written there, and a view
/// maps them onto its own bounds when it paints.
enum ThemeBrush: Equatable {
    case solid(NSColor)
    case gradient([ThemeGradientStop], start: CGPoint, end: CGPoint)

    /// The brush as a single colour: itself when it is solid, its first stop when it runs.
    var flat: NSColor {
        switch self {
        case .solid(let colour): return colour
        case .gradient(let stops, _, _): return stops.first?.colour ?? AccentPalette.fallback
        }
    }

    var isGradient: Bool {
        if case .gradient = self { return true }
        return false
    }

    /// `nil` for a solid brush: a caller that wants one colour asks for `flat` instead.
    func nsGradient() -> NSGradient? {
        guard case .gradient(let stops, _, _) = self else { return nil }
        let colours = stops.map(\.colour)
        return stops.map(\.offset).withUnsafeBufferPointer { locations in
            NSGradient(colors: colours, atLocations: locations.baseAddress, colorSpace: .sRGB)
        }
    }
}

struct ThemeGradientStop: Equatable {
    let offset: CGFloat
    let colour: NSColor

    init(_ offset: CGFloat, _ colour: NSColor) {
        self.offset = offset
        self.colour = colour
    }
}

/// The fourteen tokens a palette is made of (`Themes/Palettes/*.xaml`). A struct and not a
/// dictionary on purpose: the Windows smoke run has to compare the key sets of the palettes to catch
/// one that is short of a token, and here a palette that is short of one does not compile.
struct ThemePalette: Equatable {
    let id: String
    let surface: ThemeBrush
    let surfaceBar: ThemeBrush
    let surfaceLine: NSColor
    let elevated: NSColor
    let elevatedLine: NSColor
    let hover: NSColor
    let pressed: NSColor
    let divider: NSColor
    let text: NSColor
    let textMuted: NSColor
    let textFaint: NSColor
    let shadowColour: NSColor
    let shadowOpacity: CGFloat
    let danger: NSColor
}

/// Port of `src/Snapik.App/ThemeService.cs`, SPEC-DELTA-3 §1.5 G-1/G-2 and
/// `tasks/tz-005-details/B-themes-accents.md` §2, §3, §5.
///
/// On Windows the look is two resource dictionaries swapped under the windows, which repaints them
/// through `DynamicResource` without a restart. There is no such machinery here: this holds the pair
/// that is current, and a view that wants to follow it reads it when it redraws. Neither call saves
/// anything — the owner of the settings writes the pair it wants kept.
enum ThemeService {
    static let defaultTheme = "dark"
    static let defaultAccent = "blue"

    /// [ТЗ№4 B1] Six palettes: the light one is gone, and the card that carried it is the dawn one.
    /// A file still holding `"light"`, or anything else nothing answers to, is read as `dark`.
    static let themes: [String] = ["dark", "glass", "night", "sunset", "sea", "dawn"]

    /// [ТЗ№4 A5] Six solid accents and six gradients, in the order of the row. `teal` is called green
    /// in the interface and `coral` orange: the file carries the identifier, and renaming it would
    /// cost a migration.
    static let accents: [String] = [
        "blue", "teal", "violet", "coral", "rose", "cyan",
        "blue-violet", "orange-rose", "green-cyan", "amber-pink", "rose-violet", "cyan-blue",
    ]

    private(set) static var currentTheme = defaultTheme
    private(set) static var currentAccent = defaultAccent

    static func apply(theme: String?, accent: String?) {
        currentTheme = normalizeTheme(theme)
        currentAccent = normalizeAccent(accent)
    }

    static func normalizeTheme(_ themeId: String?) -> String {
        guard let themeId else { return defaultTheme }
        return themes.first { $0.caseInsensitiveCompare(themeId) == .orderedSame } ?? defaultTheme
    }

    static func normalizeAccent(_ accentId: String?) -> String {
        guard let accentId else { return defaultAccent }
        return accents.first { $0.caseInsensitiveCompare(accentId) == .orderedSame } ?? defaultAccent
    }

    /// The palette of a theme, read without applying it: the cards of the gallery show the theme they
    /// stand for while another one is on screen.
    static func palette(_ themeId: String?) -> ThemePalette {
        palettes[normalizeTheme(themeId)] ?? palettes[defaultTheme]!
    }

    static func accent(_ accentId: String?) -> AccentTokens {
        accentTokens[normalizeAccent(accentId)] ?? accentTokens[defaultAccent]!
    }

    /// Whether an accent paints with more than one colour; the row of accents puts its divider in
    /// front of the first one that does (`B-themes-accents.md` §5.4).
    static func isGradientAccent(_ accentId: String?) -> Bool { accent(accentId).isGradient }

    // MARK: - Palettes

    // The four gradient surfaces of the round are the CSS 160° of the reference written as WPF
    // points; "Стекло" is 150°, which is `0.6,1`. The bar takes the same stops horizontally.
    private static let surfaceEnd = CGPoint(x: 0.35, y: 1)
    private static let barStart = CGPoint(x: 0, y: 0)
    private static let barEnd = CGPoint(x: 1, y: 0)

    private static func surface(_ first: String, _ last: String) -> ThemeBrush {
        .gradient(
            [ThemeGradientStop(0, NSColor(hex: first)), ThemeGradientStop(1, NSColor(hex: last))],
            start: barStart, end: surfaceEnd)
    }

    private static func bar(_ first: String, _ last: String) -> ThemeBrush {
        .gradient(
            [ThemeGradientStop(0, NSColor(hex: first)), ThemeGradientStop(1, NSColor(hex: last))],
            start: barStart, end: barEnd)
    }

    // [ТЗ№4 B2] "Стекло" is the matte gradient B of `reference-html/03-glass-gradients-A-B-C.html`,
    // three stops instead of the translucent grey of 1.4.0.
    private static let glassStops = [
        ThemeGradientStop(0, NSColor(hex: "#5F5C8C")),
        ThemeGradientStop(0.55, NSColor(hex: "#7E5878")),
        ThemeGradientStop(1, NSColor(hex: "#58627A")),
    ]

    private static let palettes: [String: ThemePalette] = [
        "dark": ThemePalette(
            id: "dark",
            surface: .solid(NSColor(hex: "#F2171A20")),
            surfaceBar: .solid(NSColor(hex: "#F2171A20")),
            surfaceLine: NSColor(hex: "#46505E"),
            elevated: NSColor(hex: "#242A33"),
            elevatedLine: NSColor(hex: "#46505E"),
            hover: NSColor(hex: "#2A3240"),
            pressed: NSColor(hex: "#20262F"),
            divider: NSColor(hex: "#3A424E"),
            text: NSColor(hex: "#EEF2F8"),
            textMuted: NSColor(hex: "#8F9AAA"),
            textFaint: NSColor(hex: "#6F7A8A"),
            shadowColour: NSColor(hex: "#000000"),
            shadowOpacity: 0.4,
            danger: NSColor(hex: "#FF6B6B")),
        "glass": ThemePalette(
            id: "glass",
            surface: .gradient(glassStops, start: barStart, end: CGPoint(x: 0.6, y: 1)),
            surfaceBar: .gradient(glassStops, start: barStart, end: barEnd),
            surfaceLine: NSColor(hex: "#38FFFFFF"),
            elevated: NSColor(hex: "#1AFFFFFF"),
            elevatedLine: NSColor(hex: "#38FFFFFF"),
            hover: NSColor(hex: "#24FFFFFF"),
            pressed: NSColor(hex: "#33FFFFFF"),
            divider: NSColor(hex: "#3DFFFFFF"),
            text: NSColor(hex: "#EEF2F8"),
            textMuted: NSColor(hex: "#DDD6E6"),
            textFaint: NSColor(hex: "#C5BFD3"),
            shadowColour: NSColor(hex: "#000000"),
            shadowOpacity: 0.35,
            danger: NSColor(hex: "#FF6B6B")),
        "night": ThemePalette(
            id: "night",
            surface: surface("#1F2A4A", "#2A1F4A"),
            surfaceBar: bar("#1F2A4A", "#2A1F4A"),
            surfaceLine: NSColor(hex: "#408C96FF"),
            elevated: NSColor(hex: "#14FFFFFF"),
            elevatedLine: NSColor(hex: "#408C96FF"),
            hover: NSColor(hex: "#1FFFFFFF"),
            pressed: NSColor(hex: "#2EFFFFFF"),
            divider: NSColor(hex: "#4D8C96FF"),
            text: NSColor(hex: "#EEF2F8"),
            textMuted: NSColor(hex: "#C6CEDA"),
            textFaint: NSColor(hex: "#A9B4C2"),
            shadowColour: NSColor(hex: "#000000"),
            shadowOpacity: 0.45,
            danger: NSColor(hex: "#FF6B6B")),
        "sunset": ThemePalette(
            id: "sunset",
            surface: surface("#3D2436", "#4A2A22"),
            surfaceBar: bar("#3D2436", "#4A2A22"),
            surfaceLine: NSColor(hex: "#40FFA078"),
            elevated: NSColor(hex: "#14FFFFFF"),
            elevatedLine: NSColor(hex: "#40FFA078"),
            hover: NSColor(hex: "#1FFFFFFF"),
            pressed: NSColor(hex: "#2EFFFFFF"),
            divider: NSColor(hex: "#4DFFA078"),
            text: NSColor(hex: "#EEF2F8"),
            textMuted: NSColor(hex: "#C6CEDA"),
            textFaint: NSColor(hex: "#A9B4C2"),
            shadowColour: NSColor(hex: "#000000"),
            shadowOpacity: 0.45,
            danger: NSColor(hex: "#FF6B6B")),
        "sea": ThemePalette(
            id: "sea",
            surface: surface("#163A44", "#1B3A2C"),
            surfaceBar: bar("#163A44", "#1B3A2C"),
            surfaceLine: NSColor(hex: "#4050DCC8"),
            elevated: NSColor(hex: "#14FFFFFF"),
            elevatedLine: NSColor(hex: "#4050DCC8"),
            hover: NSColor(hex: "#1FFFFFFF"),
            pressed: NSColor(hex: "#2EFFFFFF"),
            divider: NSColor(hex: "#4D50DCC8"),
            text: NSColor(hex: "#EEF2F8"),
            textMuted: NSColor(hex: "#C6CEDA"),
            textFaint: NSColor(hex: "#A9B4C2"),
            shadowColour: NSColor(hex: "#000000"),
            shadowOpacity: 0.45,
            danger: NSColor(hex: "#FF6B6B")),
        "dawn": ThemePalette(
            id: "dawn",
            surface: surface("#FFF4EC", "#F1ECFF"),
            surfaceBar: bar("#FFF4EC", "#F1ECFF"),
            surfaceLine: NSColor(hex: "#14000000"),
            elevated: NSColor(hex: "#FFFFFF"),
            elevatedLine: NSColor(hex: "#E3E7ED"),
            hover: NSColor(hex: "#0D000000"),
            pressed: NSColor(hex: "#17000000"),
            divider: NSColor(hex: "#14000000"),
            text: NSColor(hex: "#172033"),
            textMuted: NSColor(hex: "#5E687A"),
            textFaint: NSColor(hex: "#8A93A3"),
            shadowColour: NSColor(hex: "#000000"),
            shadowOpacity: 0.15,
            danger: NSColor(hex: "#B42318")),
    ]

    // MARK: - Accents

    // Every gradient accent runs at 135 degrees, and its flat colour is its first stop.
    private static let accentEnd = CGPoint(x: 1, y: 1)

    private static func solidAccent(
        id: String, colour: String, hover: String, pressed: String, text: String
    ) -> AccentTokens {
        AccentTokens(
            id: id,
            flat: NSColor(hex: colour),
            brush: .solid(NSColor(hex: colour)),
            hover: .solid(NSColor(hex: hover)),
            pressed: .solid(NSColor(hex: pressed)),
            soft: NSColor(hex: "#55" + String(colour.dropFirst())),
            text: NSColor(hex: text),
            focus: NSColor(hex: text))
    }

    private static func gradientAccent(
        id: String, from: String, to: String, hover: (String, String), pressed: (String, String),
        text: String
    ) -> AccentTokens {
        func run(_ first: String, _ last: String) -> ThemeBrush {
            .gradient(
                [ThemeGradientStop(0, NSColor(hex: first)), ThemeGradientStop(1, NSColor(hex: last))],
                start: barStart, end: accentEnd)
        }
        return AccentTokens(
            id: id,
            flat: NSColor(hex: from),
            brush: run(from, to),
            hover: run(hover.0, hover.1),
            pressed: run(pressed.0, pressed.1),
            soft: NSColor(hex: "#55" + String(from.dropFirst())),
            text: NSColor(hex: text),
            focus: NSColor(hex: text))
    }

    private static let accentTokens: [String: AccentTokens] = [
        "blue": solidAccent(
            id: "blue", colour: "#2F8CFF", hover: "#297BE0", pressed: "#256DC7", text: "#7CB7FF"),
        "teal": solidAccent(
            id: "teal", colour: "#28BE80", hover: "#23A771", pressed: "#1F9464", text: "#78D6AF"),
        "violet": solidAccent(
            id: "violet", colour: "#AF81FF", hover: "#9A72E0", pressed: "#8865C7", text: "#CDB0FF"),
        "coral": solidAccent(
            id: "coral", colour: "#FF8C42", hover: "#E07B3A", pressed: "#C76D33", text: "#FFB788"),
        // [ТЗ№4 A5] The four accents this round adds; the tones beside the stops follow the rules the
        // other eight were built by (`B-themes-accents.md` §5.1): hover is every stop at 88 %,
        // pressed at 78 %, soft is the first stop at 33 %.
        "rose": solidAccent(
            id: "rose", colour: "#FF5C8A", hover: "#E05179", pressed: "#C7486C", text: "#FF98B5"),
        "cyan": solidAccent(
            id: "cyan", colour: "#22C1C3", hover: "#1EAAAC", pressed: "#1B9798", text: "#74D8D9"),
        "blue-violet": gradientAccent(
            id: "blue-violet", from: "#2F8CFF", to: "#AF81FF", hover: ("#297BE0", "#9A72E0"),
            pressed: ("#256DC7", "#8865C7"), text: "#9AAAFF"),
        "orange-rose": gradientAccent(
            id: "orange-rose", from: "#FF8C42", to: "#FF4D6D", hover: ("#E07B3A", "#E04460"),
            pressed: ("#C76D33", "#C73C55"), text: "#FF988A"),
        "green-cyan": gradientAccent(
            id: "green-cyan", from: "#28BE80", to: "#00C8DC", hover: ("#23A771", "#00B0C2"),
            pressed: ("#1F9464", "#009CAC"), text: "#5AD5C6"),
        "amber-pink": gradientAccent(
            id: "amber-pink", from: "#FFBE2E", to: "#FF79B7", hover: ("#E0A728", "#E06AA1"),
            pressed: ("#C79424", "#C75E8F"), text: "#FFBA9C"),
        "rose-violet": gradientAccent(
            id: "rose-violet", from: "#FF5C8A", to: "#AF81FF", hover: ("#E05179", "#9A72E0"),
            pressed: ("#C7486C", "#8865C7"), text: "#E39AD6"),
        "cyan-blue": gradientAccent(
            id: "cyan-blue", from: "#22C1C3", to: "#2F8CFF", hover: ("#1EAAAC", "#297BE0"),
            pressed: ("#1B9798", "#256DC7"), text: "#69C1EA"),
    ]
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
