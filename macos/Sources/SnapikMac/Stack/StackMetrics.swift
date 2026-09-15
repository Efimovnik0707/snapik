// Port of `EdgeStackWindow.xaml:100-162` (window/list/card geometry, accordion animation
// durations, border colors), SPEC-DELTA-2 §1.7, SPEC-DELTA-2B §E1.
import AppKit

/// Card-list-specific metrics. Deliberately separate from `App/Theme.swift`'s `ThemeMetrics`
/// (owned by exec-shell, read-only for this zone): sync 2 changes the stack window's width and
/// the card's collapsed/expanded geometry, and `Theme.swift`'s older `stackWidth`/`cardHeight`/
/// `cardListMaxHeight`/`cardCornerRadius` constants are left untouched rather than edited outside
/// this zone's folder ownership.
enum StackMetrics {
    static let width: CGFloat = 208
    static let cardHeight: CGFloat = 78
    static let cardOverlap: CGFloat = 48
    /// Vertical distance between two collapsed cards' tops (`cardHeight - cardOverlap`).
    static let cardStep: CGFloat = cardHeight - cardOverlap
    static let expandedMargin: CGFloat = 4
    static let listMaxHeight: CGFloat = 372
    static let listBottomPadding: CGFloat = 52
    static let expandInSeconds: TimeInterval = 0.18
    static let expandOutSeconds: TimeInterval = 0.16
    static let selectedBorder = NSColor(hex: "#7AB8FF")
    static let hoverBorder = NSColor(hex: "#718096")
    static let cardBorder = NSColor(hex: "#46505E")
    static let cornerRadius: CGFloat = 11
}
