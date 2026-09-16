// Port of `EdgeStackWindow.xaml`'s window/list/card geometry, SPEC-DELTA-3 §1.3 S-3…S-7 and
// `tasks/tz-005-details/C-strip.md` §C1, §C2, §C3, §C4, §C6.
import AppKit
import SnapikCore

/// Every number the strip is built from, in one place. The chain of this round reads left to right
/// and only once: the window is `StripResizeGeometry.defaultWidth` wide, the field that carries the
/// shadow takes `shadowMargin` off each side, the panel takes `panelPadding`, the list takes its
/// own padding, and what is left is the card — 244 − 2·20 − 2·10 − 2·8 = **168** ([ТЗ№4 C4], C6,
/// `reference-png/04`: "окно 244 · панель 204 · паддинг 10 · карточка 168×78").
///
/// Deliberately separate from `App/Theme.swift`'s `ThemeMetrics`, which belongs to the shell and
/// still carries the numbers the strip had before this round.
enum StackMetrics {
    // MARK: - Window and panel

    /// [ТЗ№4 C6] The field between the edge of the window and the edge of the visible panel, which is
    /// also the gap the strip keeps to the edge of the screen: the window sits flush against the
    /// working area and the panel is seen twenty points away from it, which is why
    /// `StripResizeGeometry.edgeGap` is nil — a gap of its own would double the visible one.
    ///
    /// **Twenty.** The two figures of the intermediate round did not fit each other — a window of
    /// 224 with a field of 20 leaves a card of 148, where the reference draws 168 — and sync 3 cut
    /// the field back to ten to keep the window at 224. Windows settled the same contradiction the
    /// other way: the window is 244 now, the field is the 20 a blur of 24 and a depth of 5 need,
    /// and the panel and the card stay at 204 and 168 (SPEC-DELTA-4 §2.5, §3.1).
    static let shadowMargin: CGFloat = 20
    static let panelPadding: CGFloat = 10
    static let panelCornerRadius: CGFloat = 16
    static let panelShadowBlur: CGFloat = 16
    static let panelShadowOffset: CGFloat = 3

    static let headerHeight: CGFloat = 28
    /// [ТЗ№4 C4] 22, not 26: four of them and their gaps have to fit the narrower header.
    static let headerButtonSize: CGFloat = 22
    static let buttonHeight: CGFloat = 36
    static let buttonCornerRadius: CGFloat = 10

    // MARK: - List

    /// `Margin="0,7,0,8"` of the list: the gap to the header above and to the capture button below.
    static let listTopGap: CGFloat = 7
    static let listBottomGap: CGFloat = 8
    /// [ТЗ№4 C6] `Padding="8,14,8,52"`: the left and right eights are what the card gives up so the
    /// scroll bar has a lane of its own, the fourteen is the room the shadow of the first card
    /// needs, and the fifty-two lets the last card be scrolled clear of the capture button.
    static let listPaddingLeft: CGFloat = 8
    static let listPaddingTop: CGFloat = 14
    static let listPaddingRight: CGFloat = 8
    static let listPaddingBottom: CGFloat = 52
    /// [ТЗ№4 C2] Four points wide, at rest and under the pointer alike: the bar no longer grows on
    /// hover, only the grip changes colour.
    static let scrollBarWidth: CGFloat = 4

    /// [ТЗ№4 C3] The empty strip is the header, this block and the capture button — nothing else,
    /// and no corner grip.
    static let emptyHintHeight: CGFloat = 92

    // MARK: - Card

    static let cardHeight: CGFloat = 78
    static let cardOverlap: CGFloat = 48
    /// Vertical distance between the tops of two collapsed cards (`cardHeight - cardOverlap`).
    static let cardStep: CGFloat = cardHeight - cardOverlap
    static let cardCornerRadius: CGFloat = 11
    /// The room a hovered or selected card opens above and below itself.
    static let expandedMargin: CGFloat = 4
    /// The strip with the letter and the number of notes, now at the **top** of the card ([ТЗ№4 C1]):
    /// the card below covers all but the first 30 points of this one, and the letter has to live in
    /// what is still seen.
    static let cardLabelStripHeight: CGFloat = 26
    static let cardDeleteButtonSize: CGFloat = 22

    /// [ТЗ№4 C6] The only two shadows of the strip are this one and the one under the window.
    static let cardShadowBlur: CGFloat = 16
    /// Upwards, onto the card the new one is drawn over: the seam that is seen is the top edge of
    /// the lower card, and the shadow falls into it.
    static let cardShadowOffset: CGFloat = 6
    static let cardShadowOpacity: Float = 0.35

    // MARK: - Capsule

    static let capsuleHeight: CGFloat = 44
    static let capsuleCornerRadius: CGFloat = 22

    // MARK: - Animation

    static let expandInSeconds: TimeInterval = 0.18
    static let expandOutSeconds: TimeInterval = 0.16
    static let appearSeconds: TimeInterval = 0.18
    static let toastLifetimeSeconds: TimeInterval = 5
    static let toastFadeSeconds: TimeInterval = 0.15

    // MARK: - Derived widths

    /// The visible panel inside a window of `windowWidth`.
    static func panelWidth(windowWidth: CGFloat) -> CGFloat { windowWidth - shadowMargin * 2 }

    /// What the header, the list and the capture button are laid out in.
    static func contentWidth(windowWidth: CGFloat) -> CGFloat {
        panelWidth(windowWidth: windowWidth) - panelPadding * 2
    }

    /// The card: the content less the two paddings of the list. 168 at the width of this round.
    static func cardWidth(windowWidth: CGFloat) -> CGFloat {
        contentWidth(windowWidth: windowWidth) - listPaddingLeft - listPaddingRight
    }

    /// The height a list of `count` collapsed cards asks for, its paddings included.
    static func listContentHeight(count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return listPaddingTop + CGFloat(count - 1) * cardStep + cardHeight + listPaddingBottom
    }
}

/// The palette and the accent as the strip reads them: through `ThemeService` and the pair the user
/// picked, never through colours written into this zone (SPEC-DELTA-3 §1.5 G-1, G-2).
enum StackTheme {
    static var palette: ThemePalette { ThemeService.palette(ThemeService.currentTheme) }
    static var accent: AccentTokens { ThemeService.accent(ThemeService.currentAccent) }

    static var cardBorder: NSColor { palette.surfaceLine }
    static let cardHoverBorder = NSColor(hex: "#718096")
    static var cardSelectedBorder: NSColor { accent.focus }
    static var cardBackground: NSColor { palette.elevated }
    /// The plate the letter sits on, at the top of the card.
    static let cardLabelStripBackground = NSColor(hex: "#E6171A20")
    static let sentBadgeBackground = NSColor(hex: "#4A5563")
    static let sentCardBorder = NSColor(hex: "#333C49")

    /// [ТЗ№4 C2] The grip of the scroll bar: 28 % of the text colour of the palette at rest, 45 %
    /// under the pointer. The round asks for white, and on the five dark palettes the text colour
    /// *is* white enough for the two to be the same thing; on `dawn` the same percentages of a dark
    /// text colour keep the grip visible, which a hard-coded white would not.
    static var scrollThumb: NSColor { palette.text.withAlphaComponent(0.28) }
    static var scrollThumbHover: NSColor { palette.text.withAlphaComponent(0.45) }
}

/// How tall a wrapping label is at a given width. `NSTextField` measures itself through its cell,
/// and the strip needs the figure before the field has been laid out, so the text is measured
/// directly instead.
enum StackTextMeasure {
    static func height(of field: NSTextField, width: CGFloat) -> CGFloat {
        let text = field.stringValue as NSString
        guard width > 0, text.length > 0 else { return 0 }
        let rect = text.boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: field.font ?? NSFont.systemFont(ofSize: 11)])
        return ceil(rect.height)
    }
}

/// Fills a path with a `ThemeBrush`: one colour, or the run of them the gradient palettes paint
/// with. The stops are written in the WPF unit square (`0,0` the top-left corner, y downwards), so
/// they are mapped onto the AppKit rect here, once, instead of in every view that paints.
enum StackBrush {
    static func fill(_ brush: ThemeBrush, in path: NSBezierPath, bounds: NSRect) {
        switch brush {
        case .solid(let colour):
            colour.setFill()
            path.fill()
        case .gradient(_, let start, let end):
            guard let gradient = brush.nsGradient() else {
                brush.flat.setFill()
                path.fill()
                return
            }
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            gradient.draw(from: point(start, in: bounds), to: point(end, in: bounds), options: [])
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private static func point(_ unit: CGPoint, in bounds: NSRect) -> NSPoint {
        NSPoint(x: bounds.minX + unit.x * bounds.width, y: bounds.maxY - unit.y * bounds.height)
    }
}
