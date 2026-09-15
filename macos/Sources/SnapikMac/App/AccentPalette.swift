// Port of `src/Snapik.App/AccentPalette.cs` and of `Themes/Accents/*.xaml`, SPEC-DELTA-3 §1.5 G-2,
// `tasks/tz-005-details/B-themes-accents.md` §5.
import AppKit

/// One accent, as the twelve dictionaries of `Themes/Accents` hold it. Eight keys on Windows; here
/// they are eight fields, so a dictionary cannot be short of one — what the Windows smoke run has to
/// check by comparing key sets is a compile error on this side.
///
/// `flat` is the accent as a single colour: the accent itself when it is solid, the first stop when
/// it is a gradient. The alpha mixes and the exported PNG need a colour rather than something that
/// paints, and everything that paints takes `brush`.
struct AccentTokens: Equatable {
    let id: String
    let flat: NSColor
    let brush: ThemeBrush
    let hover: ThemeBrush
    let pressed: ThemeBrush
    let soft: NSColor
    let text: NSColor
    let focus: NSColor

    /// What the row of accents puts its divider in front of: the first accent that paints with more
    /// than one colour. The Windows row compared the identifier `"blue-violet"` instead, which stayed
    /// right by accident and would have broken silently the next time the row was reordered
    /// (`tasks/tz-005-details/B-themes-accents.md` §5.4).
    var isGradient: Bool { brush.isGradient }
}

/// The one place the accent is read from for everything that draws. Before this, a dozen renderers
/// wrote the blue down by hand, and a violet accent stopped at the chrome.
///
/// The fallback lives here and nowhere else: the tests and part of the probes run without a theme
/// ever having been applied, and a missing accent must not become a missing colour halfway down a
/// render.
enum AccentPalette {
    /// The accent to fall back on when nothing has been applied yet.
    static let fallback = NSColor(hex: "#2F8CFF")

    private static var tokens: AccentTokens { ThemeService.accent(ThemeService.currentAccent) }

    /// The accent as a single colour: the accent itself when it is solid, the first stop when it is
    /// a gradient.
    static var flat: NSColor { tokens.flat }

    /// What paints: a solid colour or a gradient, whichever the accent is.
    static var brush: ThemeBrush { tokens.brush }

    /// The accent thinned down to a wash: a fill behind a mark, a highlighted row.
    static func wash(alpha: CGFloat) -> NSColor {
        flat.withAlphaComponent(min(max(alpha, 0), 1))
    }
}
