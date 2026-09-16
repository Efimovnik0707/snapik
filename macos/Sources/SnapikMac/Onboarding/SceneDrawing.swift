// The clock, the easing and the pieces every scene of the wizard is drawn out of. Ports of the
// storyboards and canvases of `src/Snapik.App/Controls/CaptureSceneSmall.xaml` and
// `Controls/HowToSlides.xaml`, SPEC-DELTA-3 §1.6 O-3, O-7.
import AppKit
import SnapikCore

/// A scene is a function of one number — how far into its nine seconds it is — and not a pile of
/// clocks attached to properties. WPF animates properties through a `Storyboard`; here the same key
/// frames are read at the time the clock stands on and the whole scene is drawn from them, which is
/// also what makes "the animations of the system are off" a single line: the clock is parked on the
/// finished frame and never started.
final class SceneClock {
    /// The loop every scene of this round runs on.
    static let duration: Double = 9
    /// A frame this close to the end of a repeating loop is the finished picture; the end itself
    /// would wrap back to the beginning.
    static let finishedFrame: Double = 8.9

    private(set) var time: Double = 0
    private var startedAt: Date?
    /// Which run of the clock a scheduled tick belongs to: a tick of a run that has been stopped (or
    /// restarted) is dropped instead of moving the scene it no longer belongs to.
    private var generation = 0
    private let onTick: (Double) -> Void

    init(onTick: @escaping (Double) -> Void) {
        self.onTick = onTick
    }

    /// Whether the system is willing to show movement at all; with it off the scene shows its
    /// finished picture and waits (`NSWorkspace.accessibilityDisplayShouldReduceMotion`, the macOS
    /// equivalent of `SystemParameters.ClientAreaAnimation`, SPEC-DELTA-3 §4).
    static var animationsAllowed: Bool {
        !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Runs the scene from its beginning; calling it twice restarts it, as `Storyboard.Begin` does.
    func start() {
        stop()
        guard Self.animationsAllowed else {
            seek(to: Self.finishedFrame)
            return
        }
        generation += 1
        startedAt = Date()
        time = 0
        onTick(time)
        scheduleTick(generation)
    }

    private func scheduleTick(_ run: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 30) { [weak self] in
            guard let self, self.generation == run, let startedAt = self.startedAt else { return }
            self.time = Date().timeIntervalSince(startedAt).truncatingRemainder(dividingBy: Self.duration)
            self.onTick(self.time)
            self.scheduleTick(run)
        }
    }

    /// Gives the clock back; calling it twice is allowed and does nothing.
    func stop() {
        generation += 1
        startedAt = nil
    }

    /// Parks the scene on one frame without running it: what a hidden step and a machine with the
    /// animations switched off both get.
    func seek(to time: Double) {
        self.time = time
        onTick(time)
    }

    var isRunning: Bool { startedAt != nil }
}

/// The key frames of a storyboard, read at a point in time.
enum SceneEase {
    /// The WPF spline `0.25,0.1 0.25,1` — the "ease" of the reference — as the eased fraction of a
    /// segment. Approximated by the cubic ease-out it is nearly identical to over 0…1; the exact
    /// Bezier would need a solver per frame and the difference is under a pixel at these sizes.
    static func ease(_ fraction: CGFloat) -> CGFloat {
        let clamped = min(max(fraction, 0), 1)
        return 1 - pow(1 - clamped, 3)
    }

    /// A value that waits until `from`, moves to its end by `to` and stays there: the shape every key
    /// frame block of the storyboards has.
    static func value(
        _ time: Double, from: Double, to: Double, start: CGFloat, end: CGFloat, eased: Bool = true
    ) -> CGFloat {
        if time <= from { return start }
        if time >= to { return end }
        let fraction = CGFloat((time - from) / max(to - from, 0.0001))
        return start + (end - start) * (eased ? ease(fraction) : fraction)
    }

    /// A value that comes, holds and goes again (the capsule of slide 4, the panel that folds).
    static func pulse(
        _ time: Double, in inRange: ClosedRange<Double>, out outRange: ClosedRange<Double>,
        low: CGFloat, high: CGFloat
    ) -> CGFloat {
        if time < outRange.lowerBound {
            return value(time, from: inRange.lowerBound, to: inRange.upperBound, start: low, end: high)
        }
        return value(time, from: outRange.lowerBound, to: outRange.upperBound, start: high, end: low)
    }
}

/// The drawings the scenes are made of. Everything here takes the rectangle it is drawn in, so the
/// numbers of the XAML canvases are kept verbatim and a scene only says where a piece goes.
enum SceneDrawing {
    static let accentTextColour = NSColor(hex: "#9AB8E8")

    static func fill(_ rect: NSRect, _ colour: NSColor, radius: CGFloat = 0) {
        colour.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }

    static func stroke(_ rect: NSRect, _ colour: NSColor, radius: CGFloat = 0, width: CGFloat = 1) {
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: width / 2, dy: width / 2), xRadius: radius, yRadius: radius)
        path.lineWidth = width
        colour.setStroke()
        path.stroke()
    }

    static func accentFill(_ rect: NSRect, radius: CGFloat = 0) {
        AppearanceBrush.fill(ThemeService.accent(ThemeService.currentAccent).brush, in: rect, radius: radius)
    }

    static func text(
        _ value: String, at point: NSPoint, size: CGFloat, weight: NSFont.Weight = .regular,
        colour: NSColor = NSColor(hex: "#EEF2F8")
    ) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: colour,
        ]
        NSAttributedString(string: value, attributes: attributes).draw(at: point)
    }

    static func width(of value: String, size: CGFloat, weight: NSFont.Weight = .regular) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight)
        ]
        return NSAttributedString(string: value, attributes: attributes).size().width
    }

    /// The screen a capture is taken from: a page with two lines of text and a panel on it.
    /// `CaptureSceneSmall.xaml:86-97` — 210 × 180 with the page inset by 10.
    static func mockScreen(in rect: NSRect) {
        fill(rect, NSColor(hex: "#2A3140"), radius: 8)
        let page = NSRect(x: rect.minX + 10, y: rect.minY + 10, width: 190, height: 160)
        fill(page, NSColor(hex: "#E9EDF2"), radius: 6)
        fill(NSRect(x: page.minX, y: page.minY, width: 190, height: 16), NSColor(hex: "#FFFFFF"), radius: 6)
        fill(NSRect(x: page.minX, y: page.minY + 15, width: 190, height: 1), NSColor(hex: "#DDE2EA"))
        fill(NSRect(x: page.minX + 14, y: page.minY + 28, width: 76, height: 6), NSColor(hex: "#C9D0DA"), radius: 3)
        fill(NSRect(x: page.minX + 14, y: page.minY + 42, width: 118, height: 6), NSColor(hex: "#D9DEE6"), radius: 3)
        let panel = NSRect(x: page.minX + 14, y: page.minY + 58, width: 162, height: 90)
        fill(panel, NSColor(hex: "#FFFFFF"), radius: 5)
        stroke(panel, NSColor(hex: "#DDE2EA"), radius: 5)
    }

    /// The shade with a hole in it: in the reference it is a shadow of the frame itself, which
    /// neither WPF nor AppKit has an equivalent of.
    static func shade(in rect: NSRect, hole: NSRect, opacity: CGFloat) {
        guard opacity > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        let path = NSBezierPath(rect: rect)
        path.append(NSBezierPath(rect: hole))
        path.windingRule = .evenOdd
        NSColor(hex: "#0A0D12").withAlphaComponent(opacity).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// A mark on the capture: the accent badge and the plaque beside it, the plaque cut off on the
    /// right as it grows — what grows is the room the text is allowed, not the text.
    static func mark(
        at point: NSPoint, badge: String, plaque: String, scale: CGFloat, opacity: CGFloat,
        plaqueWidth: CGFloat
    ) {
        guard opacity > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: point.x, yBy: point.y)
        transform.scaleX(by: scale, yBy: scale)
        transform.translateX(by: -point.x, yBy: -point.y)
        transform.concat()

        let badgeWidth = width(of: badge, size: 8, weight: .bold) + 10
        let badgeRect = NSRect(x: point.x, y: point.y, width: badgeWidth, height: 13)
        accentFill(badgeRect, radius: 6.5)
        text(
            badge, at: NSPoint(x: badgeRect.minX + 5, y: badgeRect.minY + 1), size: 8, weight: .bold,
            colour: .white)

        if plaqueWidth > 1 {
            let full = width(of: plaque, size: 10) + 14
            let shown = min(full, plaqueWidth)
            let plaqueRect = NSRect(x: badgeRect.maxX + 4, y: point.y - 2, width: shown, height: 17)
            fill(plaqueRect, NSColor(hex: "#F7171A20"), radius: 7)
            stroke(plaqueRect, NSColor(hex: "#3A424E"), radius: 7)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: plaqueRect).addClip()
            text(plaque, at: NSPoint(x: plaqueRect.minX + 7, y: plaqueRect.minY + 2), size: 10)
            NSGraphicsContext.restoreGraphicsState()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// The arrow between the two halves of a scene.
    static func arrow(in rect: NSRect, pointsRight: Bool, opacity: CGFloat) {
        guard opacity > 0 else { return }
        let path = NSBezierPath()
        let y = rect.midY
        let from = pointsRight ? rect.minX + 2 : rect.maxX - 2
        let to = pointsRight ? rect.maxX - 6 : rect.minX + 6
        path.move(to: NSPoint(x: from, y: y))
        path.line(to: NSPoint(x: to, y: y))
        path.move(to: NSPoint(x: to + (pointsRight ? -7 : 7), y: y - 6))
        path.line(to: NSPoint(x: to, y: y))
        path.line(to: NSPoint(x: to + (pointsRight ? -7 : 7), y: y + 6))
        path.lineWidth = 2
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        ThemeService.accent(ThemeService.currentAccent).flat.withAlphaComponent(opacity).setStroke()
        path.stroke()
    }

    /// Where a capture lands: the chat with its header, its message box and the paste chip.
    /// `CaptureSceneSmall.xaml:137-160` — 206 × 180.
    static func chatWindow(in rect: NSRect, pasteLabel: String, chatTitle: String) {
        fill(rect, NSColor(hex: "#1B212B"), radius: 8)
        stroke(rect, NSColor(hex: "#33404F"), radius: 8)
        fill(NSRect(x: rect.minX, y: rect.minY + 23, width: rect.width, height: 1), NSColor(hex: "#2A3240"))
        fill(NSRect(x: rect.minX + 9, y: rect.minY + 6, width: 12, height: 12), NSColor(hex: "#4E5A6B"), radius: 6)
        text(
            chatTitle, at: NSPoint(x: rect.minX + 27, y: rect.minY + 5), size: 10, weight: .semibold,
            colour: NSColor(hex: "#C6CEDA"))
        for index in 0..<3 {
            fill(
                NSRect(x: rect.maxX - 30 + CGFloat(index) * 6, y: rect.minY + 11, width: 3, height: 3),
                NSColor(hex: "#6F7A8A"), radius: 1.5)
        }

        let input = NSRect(x: rect.minX + 7, y: rect.maxY - 31, width: 190, height: 24)
        fill(input, NSColor(hex: "#222A35"), radius: 6)
        stroke(input, NSColor(hex: "#3A4553"), radius: 6)
        text(
            "Текст…", at: NSPoint(x: input.minX + 8, y: input.minY + 6), size: 9,
            colour: NSColor(hex: "#6F7A8A"))
        let chipWidth = width(of: pasteLabel, size: 9, weight: .semibold) + 14
        let chip = NSRect(x: input.maxX - 4 - chipWidth, y: input.minY + 4, width: chipWidth, height: 16)
        fill(chip, NSColor(hex: "#253B58"), radius: 4)
        stroke(chip, ThemeService.accent(ThemeService.currentAccent).flat, radius: 4)
        text(pasteLabel, at: NSPoint(x: chip.minX + 7, y: chip.minY + 2), size: 9, weight: .semibold)
    }

    /// The strip as a picture of itself: the header, the cards and the button under them
    /// (`HowToSlides.xaml:430-497`). `letters` is read bottom card first, the way the canvas stacks
    /// them, and `highlighted` is the card the pointer has just opened.
    static func stripPanel(
        in rect: NSRect, letters: [(String, String)], newCaptureLabel: String, highlighted: Int? = nil,
        cardsOpacity: CGFloat = 1
    ) {
        fill(rect, NSColor(hex: "#F5171A20"), radius: 10)
        stroke(rect, NSColor(hex: "#2A3240"), radius: 10)
        let inner = rect.insetBy(dx: 8, dy: 8)

        accentFill(NSRect(x: inner.minX, y: inner.minY + 4, width: 5, height: 5), radius: 2.5)
        text(
            "Snapik", at: NSPoint(x: inner.minX + 9, y: inner.minY), size: 9, weight: .semibold)
        let count = "\(letters.count)"
        let pill = NSRect(x: inner.minX + 42, y: inner.minY + 1, width: 14, height: 11)
        fill(pill, NSColor(hex: "#2B3440"), radius: 5.5)
        text(count, at: NSPoint(x: pill.minX + 5, y: pill.minY - 1), size: 7, colour: NSColor(hex: "#BFC8D6"))

        guard cardsOpacity > 0 else { return }
        var top = inner.minY + 18
        for (index, letter) in letters.enumerated() {
            let card = NSRect(x: inner.minX, y: top, width: inner.width, height: 40)
            fill(card, NSColor(hex: "#E9EDF2").withAlphaComponent(cardsOpacity), radius: 7)
            if index == highlighted {
                stroke(card, ThemeService.accent(ThemeService.currentAccent).flat, radius: 7, width: 2)
            } else {
                stroke(card, NSColor(hex: "#46505E").withAlphaComponent(cardsOpacity), radius: 7)
            }
            fill(
                NSRect(x: card.minX + 6, y: card.minY + 6, width: card.width * 0.4, height: 3),
                NSColor(hex: "#C9D0DA").withAlphaComponent(cardsOpacity), radius: 1.5)
            let footer = NSRect(x: card.minX + 1, y: card.maxY - 16, width: card.width - 2, height: 15)
            fill(footer, NSColor(hex: "#E6171A20").withAlphaComponent(cardsOpacity))
            let badge = NSRect(x: footer.minX + 5, y: footer.minY + 2, width: 11, height: 11)
            accentFill(badge, radius: 5.5)
            text(
                letter.0, at: NSPoint(x: badge.minX + 3.5, y: badge.minY + 1), size: 6, weight: .bold,
                colour: NSColor.white.withAlphaComponent(cardsOpacity))
            text(
                letter.1, at: NSPoint(x: badge.maxX + 4, y: badge.minY + 1), size: 6,
                colour: NSColor(hex: "#DCE3ED").withAlphaComponent(cardsOpacity))
            top += 20
        }

        let button = NSRect(x: inner.minX, y: rect.maxY - 8 - 20, width: inner.width, height: 20)
        accentFill(button, radius: 6)
        let labelWidth = width(of: newCaptureLabel, size: 8, weight: .semibold)
        text(
            newCaptureLabel, at: NSPoint(x: button.midX - labelWidth / 2, y: button.minY + 4), size: 8,
            weight: .semibold, colour: .white)
    }

    /// The pointer of slides 3 and 4, at the place it has moved to and at the size of its click.
    static func cursor(at point: NSPoint, scale: CGFloat, opacity: CGFloat) {
        guard opacity > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: point.x, yBy: point.y)
        transform.scaleX(by: scale, yBy: scale)
        transform.concat()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 0, y: 0))
        path.line(to: NSPoint(x: 0, y: 13))
        path.line(to: NSPoint(x: 3.2, y: 10))
        path.line(to: NSPoint(x: 5.2, y: 14))
        path.line(to: NSPoint(x: 7.2, y: 13))
        path.line(to: NSPoint(x: 5.2, y: 9.2))
        path.line(to: NSPoint(x: 9.4, y: 9.2))
        path.close()
        NSColor(hex: "#EEF2F8").withAlphaComponent(opacity).setFill()
        path.fill()
        NSColor(hex: "#171B22").withAlphaComponent(opacity).setStroke()
        path.lineWidth = 1
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
}
