// The three drawn slides of "Как пользоваться" (the first one is `CaptureSceneSmallView`), ported
// from the canvases and storyboards of `src/Snapik.App/Controls/HowToSlides.xaml`,
// SPEC-DELTA-3 §1.6 O-7.
import AppKit
import SnapikCore

/// What every slide of the control has in common: it is flipped, so the XAML numbers are read as
/// they are written, and it is drawn out of one number — how far into the nine seconds it is.
class SlideSceneView: NSView {
    var time: Double = 0 { didSet { needsDisplay = true } }
    var language = "ru" { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    func text(_ russian: String) -> String { MacUiText.text(russian, language: language) }
}

/// Slide 2, "Несколько снимков сразу": the same screen, the strip that gathers the captures, and one
/// message that carries the lot.
final class SlideTwoSceneView: SlideSceneView {
    override func draw(_ dirtyRect: NSRect) {
        let origin = NSPoint(x: (bounds.width - 454) / 2, y: (bounds.height - 180) / 2)
        let screen = NSRect(x: origin.x, y: origin.y, width: 210, height: 180)
        SceneDrawing.mockScreen(in: screen)

        let frame = NSRect(
            x: screen.minX + 22, y: screen.minY + 40,
            width: SceneEase.value(time, from: 0.36, to: 1.44, start: 0, end: 100),
            height: SceneEase.value(time, from: 0.36, to: 1.44, start: 0, end: 78))
        SceneDrawing.shade(
            in: screen, hole: frame,
            opacity: SceneEase.value(time, from: 0.36, to: 0.54, start: 0, end: 0.62, eased: false))
        let frameOpacity = SceneEase.value(time, from: 0.36, to: 0.54, start: 0, end: 1, eased: false)
        if frameOpacity > 0 {
            SceneDrawing.stroke(
                frame, ThemeService.accent(ThemeService.currentAccent).flat.withAlphaComponent(frameOpacity),
                width: 2)
        }
        SceneDrawing.mark(
            at: NSPoint(x: screen.minX + 30, y: screen.minY + 50), badge: "A1",
            plaque: text("Кнопку ярче"),
            scale: SceneEase.value(time, from: 1.62, to: 1.98, start: 0.6, end: 1),
            opacity: SceneEase.value(time, from: 1.62, to: 1.98, start: 0, end: 1, eased: false),
            plaqueWidth: SceneEase.value(time, from: 1.98, to: 2.88, start: 0, end: 140))

        // The strip drawn here is a picture of the real one, not the real one; it grows out of its
        // own top-right corner, where the real strip lives.
        let stripOpacity = SceneEase.value(time, from: 3.06, to: 3.42, start: 0, end: 1, eased: false)
        if stripOpacity > 0 {
            let scale = SceneEase.value(time, from: 3.06, to: 3.42, start: 0.6, end: 1)
            let full = NSRect(x: screen.minX + 118, y: screen.minY + 6, width: 86, height: 130)
            NSGraphicsContext.saveGraphicsState()
            let transform = NSAffineTransform()
            transform.translateX(by: full.maxX, yBy: full.minY)
            transform.scaleX(by: scale, yBy: scale)
            transform.translateX(by: -full.maxX, yBy: -full.minY)
            transform.concat()
            SceneDrawing.stripPanel(
                in: full, letters: [("C", "0"), ("B", "1"), ("A", "1")],
                newCaptureLabel: text("Новый снимок"), cardsOpacity: stripOpacity)
            NSGraphicsContext.restoreGraphicsState()
        }

        SceneDrawing.arrow(
            in: NSRect(x: screen.maxX, y: screen.minY, width: 38, height: 180), pointsRight: true,
            opacity: SceneEase.value(time, from: 4.68, to: 5.22, start: 0, end: 1, eased: false))

        let chat = NSRect(x: screen.maxX + 38, y: screen.minY, width: 206, height: 180)
        SceneDrawing.chatWindow(in: chat, pasteLabel: "Cmd + V", chatTitle: text("Чат"))
        drawBubble(in: chat)
    }

    private func drawBubble(in chat: NSRect) {
        let opacity = SceneEase.value(time, from: 5.4, to: 6.12, start: 0, end: 1)
        guard opacity > 0 else { return }
        let lift = SceneEase.value(time, from: 5.4, to: 6.12, start: 8, end: 0)
        let height: CGFloat = 30 + 4 + 36 + 12
        let bubble = NSRect(
            x: chat.maxX - 7 - 171, y: chat.maxY - 38 - height + lift, width: 171, height: height)
        NSColor(hex: "#253B58").withAlphaComponent(opacity).setFill()
        NSBezierPath(roundedRect: bubble, xRadius: 9, yRadius: 9).fill()

        for (index, letter) in ["A", "B", "C"].enumerated() {
            let shot = NSRect(x: bubble.minX + 6 + CGFloat(index) * 53, y: bubble.minY + 6, width: 49, height: 30)
            SceneDrawing.fill(shot, NSColor(hex: "#E9EDF2").withAlphaComponent(opacity), radius: 4)
            let badge = NSRect(x: shot.minX + 4, y: shot.minY + 4, width: 14, height: 11)
            SceneDrawing.accentFill(badge, radius: 5.5)
            SceneDrawing.text(
                letter, at: NSPoint(x: badge.minX + 4, y: badge.minY + 1), size: 6, weight: .bold,
                colour: NSColor.white.withAlphaComponent(opacity))
        }

        var y = bubble.minY + 40
        // "Снимок A" is the line the table carries; the other two letters are that line with its last
        // character replaced, so the English "Capture A" works the same way.
        let captionBase = String(text("Снимок A").dropLast())
        for (letter, note) in [("A", "Кнопку ярче"), ("B", "Убрать блок"), ("C", "Как на первом")] {
            let caption = captionBase + letter
            SceneDrawing.text(
                caption, at: NSPoint(x: bubble.minX + 6, y: y), size: 9, weight: .semibold,
                colour: SceneDrawing.accentTextColour.withAlphaComponent(opacity))
            let width = SceneDrawing.width(of: caption, size: 9, weight: .semibold)
            SceneDrawing.text(
                " — \(text(note))", at: NSPoint(x: bubble.minX + 6 + width, y: y), size: 9,
                colour: NSColor(hex: "#EEF2F8").withAlphaComponent(opacity))
            y += 12
        }
    }
}

/// Slide 3, "Открыть снимок снова": the pointer goes to the card in the strip, and the capture comes
/// back with its frame and its comments already on it.
final class SlideThreeSceneView: SlideSceneView {
    override func draw(_ dirtyRect: NSRect) {
        let origin = NSPoint(x: (bounds.width - 454) / 2, y: (bounds.height - 180) / 2)

        let shotOpacity = SceneEase.value(time, from: 2.7, to: 3.6, start: 0, end: 1)
        if shotOpacity > 0 {
            let scale = SceneEase.value(time, from: 2.7, to: 3.6, start: 0.9, end: 1)
            let screen = NSRect(x: origin.x, y: origin.y, width: 210, height: 180)
            NSGraphicsContext.saveGraphicsState()
            let transform = NSAffineTransform()
            transform.translateX(by: screen.midX, yBy: screen.midY)
            transform.scaleX(by: scale, yBy: scale)
            transform.translateX(by: -screen.midX, yBy: -screen.midY)
            transform.concat()
            SceneDrawing.mockScreen(in: screen)
            let frame = NSRect(x: screen.minX + 26, y: screen.minY + 40, width: 140, height: 104)
            SceneDrawing.shade(in: screen, hole: frame, opacity: 0.62 * shotOpacity)
            SceneDrawing.stroke(
                frame, ThemeService.accent(ThemeService.currentAccent).flat.withAlphaComponent(shotOpacity),
                width: 2)
            SceneDrawing.mark(
                at: NSPoint(x: screen.minX + 36, y: screen.minY + 52), badge: "A1",
                plaque: text("Кнопку ярче"), scale: 1, opacity: shotOpacity, plaqueWidth: 140)
            SceneDrawing.mark(
                at: NSPoint(x: screen.minX + 36, y: screen.minY + 104), badge: "A2",
                plaque: text("Убрать блок"), scale: 1, opacity: shotOpacity, plaqueWidth: 140)
            SceneDrawing.arrow(
                in: NSRect(x: screen.maxX, y: screen.minY, width: 38, height: 180), pointsRight: false,
                opacity: shotOpacity)
            NSGraphicsContext.restoreGraphicsState()
        }

        let panel = NSRect(x: origin.x + 248 + 41, y: origin.y + 25, width: 124, height: 130)
        SceneDrawing.stripPanel(
            in: panel, letters: [("C", "0"), ("B", "1"), ("A", "2")], newCaptureLabel: text("Новый снимок"),
            highlighted: 2)

        // The pointer comes in from the lower right, clicks the top card, and the capture opens.
        let cursorOpacity = SceneEase.value(time, from: 0.54, to: 0.9, start: 0, end: 1, eased: false)
        let dx = SceneEase.value(time, from: 0.54, to: 2.16, start: 40, end: 0)
        let dy = SceneEase.value(time, from: 0.54, to: 2.16, start: 30, end: 0)
        let press = SceneEase.pulse(time, in: 2.16...2.52, out: 2.88...3.24, low: 1, high: 0.85)
        SceneDrawing.cursor(
            at: NSPoint(x: panel.minX + 46 + dx, y: panel.minY + 31 + dy), scale: press,
            opacity: cursorOpacity)
    }
}

/// Slide 4, "Лента снимков": two halves of the same strip — on the left it is emptied, on the right
/// it is folded into the capsule and opened again. The two pointers move together.
final class SlideFourSceneView: SlideSceneView {
    override func draw(_ dirtyRect: NSRect) {
        let origin = NSPoint(x: (bounds.width - 454) / 2, y: (bounds.height - 180) / 2)
        let left = NSRect(x: origin.x, y: origin.y, width: 214, height: 180)
        let right = NSRect(x: left.maxX + 26, y: origin.y, width: 214, height: 180)

        SceneDrawing.fill(left, NSColor(hex: "#1E2430"), radius: 8)
        let leftStrip = NSRect(x: left.maxX - 12 - 150, y: left.minY + 12, width: 150, height: 130)
        let cards = SceneEase.value(time, from: 2.88, to: 3.78, start: 1, end: 0)
        SceneDrawing.stripPanel(
            in: leftStrip, letters: [("C", "0"), ("B", "1"), ("A", "2")],
            newCaptureLabel: text("Новый снимок"), cardsOpacity: cards)
        SceneDrawing.text(
            text("Очистить ленту"), at: NSPoint(x: left.minX + 10, y: left.maxY - 20), size: 9,
            colour: NSColor(hex: "#8F9AAA"))
        let leftCursor = SceneEase.value(time, from: 0.72, to: 1.08, start: 0, end: 1, eased: false)
        SceneDrawing.cursor(
            at: NSPoint(
                x: left.minX + 136 + SceneEase.value(time, from: 0.72, to: 2.16, start: -30, end: 0),
                y: left.minY + 14 + SceneEase.value(time, from: 0.72, to: 2.16, start: 40, end: 0)),
            scale: SceneEase.pulse(time, in: 2.16...2.52, out: 2.88...3.6, low: 1, high: 0.85),
            opacity: leftCursor)

        SceneDrawing.fill(right, NSColor(hex: "#1E2430"), radius: 8)
        // The panel folds into the capsule and comes back out of it; both are drawn from their own
        // top-right corner, which is the edge of the screen the strip lives on.
        let fold = SceneEase.pulse(time, in: 0...0.01, out: 3.06...3.96, low: 0.15, high: 1)
        let unfold = SceneEase.value(time, from: 6.12, to: 7.02, start: 0.15, end: 1)
        let scale = time < 6.12 ? fold : unfold
        let opacity = time < 6.12
            ? SceneEase.value(time, from: 3.06, to: 3.96, start: 1, end: 0)
            : SceneEase.value(time, from: 6.12, to: 7.02, start: 0, end: 1)
        if opacity > 0 {
            let full = NSRect(x: right.maxX - 12 - 150, y: right.minY + 12, width: 150, height: 130)
            NSGraphicsContext.saveGraphicsState()
            let transform = NSAffineTransform()
            transform.translateX(by: full.maxX, yBy: full.minY)
            transform.scaleX(by: scale, yBy: scale)
            transform.translateX(by: -full.maxX, yBy: -full.minY)
            transform.concat()
            SceneDrawing.stripPanel(
                in: full, letters: [("C", "0"), ("B", "1"), ("A", "2")],
                newCaptureLabel: text("Новый снимок"), cardsOpacity: opacity)
            NSGraphicsContext.restoreGraphicsState()
        }

        let capsuleOpacity = SceneEase.pulse(time, in: 3.6...4.14, out: 5.94...6.48, low: 0, high: 1)
        if capsuleOpacity > 0 {
            let capsuleScale = SceneEase.pulse(time, in: 3.6...4.14, out: 5.94...6.48, low: 0.4, high: 1)
            let width: CGFloat = 76 * capsuleScale
            let height: CGFloat = 26 * capsuleScale
            let capsule = NSRect(x: right.maxX - 12 - width, y: right.minY + 12, width: width, height: height)
            NSColor(hex: "#F5171A20").withAlphaComponent(capsuleOpacity).setFill()
            NSBezierPath(roundedRect: capsule, xRadius: height / 2, yRadius: height / 2).fill()
            SceneDrawing.accentFill(
                NSRect(x: capsule.minX + 9, y: capsule.midY - 2.5, width: 5, height: 5), radius: 2.5)
            SceneDrawing.text(
                "Snapik", at: NSPoint(x: capsule.minX + 18, y: capsule.midY - 6), size: 9,
                weight: .semibold, colour: NSColor(hex: "#EEF2F8").withAlphaComponent(capsuleOpacity))
        }

        let rightCursor = SceneEase.value(time, from: 0.72, to: 1.08, start: 0, end: 1, eased: false)
        SceneDrawing.cursor(
            at: NSPoint(
                x: right.maxX - 40 + SceneEase.value(time, from: 0.72, to: 2.16, start: -30, end: 0),
                y: right.minY + 14 + SceneEase.value(time, from: 0.72, to: 2.16, start: 40, end: 0)),
            scale: SceneEase.pulse(time, in: 2.16...2.52, out: 2.88...3.6, low: 1, high: 0.85),
            opacity: rightCursor)
    }
}
