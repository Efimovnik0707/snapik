// Port of `src/Snapik.App/Controls/CaptureSceneSmall.xaml(.cs)`, SPEC-DELTA-3 §1.6 O-3.
import AppKit
import SnapikCore

/// The scene of the first step and of the first slide: a capture is framed, two comments are typed on
/// it, and the whole thing lands in a chat. The two places show the same drawing with the same
/// timings and differ only in what is around them, so there is one view and not two copies.
///
/// The view is flipped, so the numbers of the XAML canvas are read here as they are written there.
/// The loop runs while the scene is on screen and is parked when it is not: a clock left on a hidden
/// step keeps repainting it for nobody.
final class CaptureSceneSmallView: NSView {
    static let sceneSize = NSSize(width: 454, height: 180)

    private var language = "ru"
    private lazy var clock = SceneClock { [weak self] _ in self?.needsDisplay = true }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize { Self.sceneSize }

    /// Runs the scene from its beginning. With the animations of the system switched off it shows the
    /// finished picture instead of moving: the step still explains itself, and nothing flickers.
    func play() { clock.start() }

    /// Gives the clock back; calling it twice is allowed and does nothing.
    func halt() { clock.stop() }

    /// The two lines of the message are built here out of the badge, a dash and the translated text.
    func applyLanguage(_ language: String) {
        self.language = language
        needsDisplay = true
    }

    /// The frame the scene stands on, for the probe and for a machine with the animations off.
    func seek(to time: Double) { clock.seek(to: time) }

    override func draw(_ dirtyRect: NSRect) {
        let time = clock.time
        let origin = NSPoint(
            x: (bounds.width - Self.sceneSize.width) / 2, y: (bounds.height - Self.sceneSize.height) / 2)
        let screen = NSRect(x: origin.x, y: origin.y, width: 210, height: 180)
        SceneDrawing.mockScreen(in: screen)

        // The frame the user drags, and the shade with its hole.
        let frameWidth = SceneEase.value(time, from: 0.36, to: 1.44, start: 0, end: 140)
        let frameHeight = SceneEase.value(time, from: 0.36, to: 1.44, start: 0, end: 104)
        let frame = NSRect(
            x: screen.minX + 26, y: screen.minY + 40, width: frameWidth, height: frameHeight)
        SceneDrawing.shade(
            in: screen, hole: frame,
            opacity: SceneEase.value(time, from: 0.36, to: 0.54, start: 0, end: 0.62, eased: false))
        let frameOpacity = SceneEase.value(time, from: 0.36, to: 0.54, start: 0, end: 1, eased: false)
        if frameOpacity > 0 {
            SceneDrawing.stroke(
                frame, ThemeService.accent(ThemeService.currentAccent).flat.withAlphaComponent(frameOpacity),
                width: 2)
        }

        // The two marks, each of them the badge first and the plaque growing out of it.
        SceneDrawing.mark(
            at: NSPoint(x: screen.minX + 36, y: screen.minY + 52), badge: "A1",
            plaque: MacUiText.text("Кнопку ярче", language: language),
            scale: SceneEase.value(time, from: 1.62, to: 1.98, start: 0.6, end: 1),
            opacity: SceneEase.value(time, from: 1.62, to: 1.98, start: 0, end: 1, eased: false),
            plaqueWidth: SceneEase.value(time, from: 1.98, to: 2.88, start: 0, end: 140))
        SceneDrawing.mark(
            at: NSPoint(x: screen.minX + 36, y: screen.minY + 104), badge: "A2",
            plaque: MacUiText.text("Убрать блок", language: language),
            scale: SceneEase.value(time, from: 3.06, to: 3.42, start: 0.6, end: 1),
            opacity: SceneEase.value(time, from: 3.06, to: 3.42, start: 0, end: 1, eased: false),
            plaqueWidth: SceneEase.value(time, from: 3.42, to: 4.32, start: 0, end: 140))

        SceneDrawing.arrow(
            in: NSRect(x: screen.maxX, y: screen.minY, width: 38, height: 180), pointsRight: true,
            opacity: SceneEase.value(time, from: 4.68, to: 5.22, start: 0, end: 1, eased: false))

        let chat = NSRect(x: screen.maxX + 38, y: screen.minY, width: 206, height: 180)
        // The paste chip of the scene is the shortcut of this platform; the sentence under the slide
        // comes from the shared table and stays as Windows wrote it.
        SceneDrawing.chatWindow(
            in: chat, pasteLabel: "Cmd + V", chatTitle: MacUiText.text("Чат", language: language))
        drawBubble(in: chat, time: time)
    }

    private func drawBubble(in chat: NSRect, time: Double) {
        let opacity = SceneEase.value(time, from: 5.4, to: 6.12, start: 0, end: 1)
        guard opacity > 0 else { return }
        let lift = SceneEase.value(time, from: 5.4, to: 6.12, start: 8, end: 0)
        let height: CGFloat = 50 + 4 + 36 + 12
        let bubble = NSRect(
            x: chat.maxX - 7 - 171, y: chat.maxY - 38 - height + lift, width: 171, height: height)

        NSGraphicsContext.saveGraphicsState()
        NSColor(hex: "#253B58").withAlphaComponent(opacity).setFill()
        NSBezierPath(roundedRect: bubble, xRadius: 9, yRadius: 9).fill()

        let shot = NSRect(x: bubble.minX + 6, y: bubble.minY + 6, width: 157, height: 50)
        SceneDrawing.fill(shot, NSColor(hex: "#E9EDF2").withAlphaComponent(opacity), radius: 5)
        SceneDrawing.fill(
            NSRect(x: shot.minX + 8, y: shot.minY + 7, width: 63, height: 4),
            NSColor(hex: "#C9D0DA").withAlphaComponent(opacity), radius: 2)
        SceneDrawing.fill(
            NSRect(x: shot.minX + 8, y: shot.minY + 15, width: 94, height: 4),
            NSColor(hex: "#D9DEE6").withAlphaComponent(opacity), radius: 2)
        SceneDrawing.fill(
            NSRect(x: shot.minX + 8, y: shot.minY + 25, width: 141, height: 17),
            NSColor(hex: "#FFFFFF").withAlphaComponent(opacity), radius: 4)
        for (index, badge) in ["A1", "A2"].enumerated() {
            let rect = NSRect(
                x: shot.minX + 8, y: shot.minY + 14 + CGFloat(index) * 19, width: 16, height: 11)
            SceneDrawing.accentFill(rect, radius: 5.5)
            SceneDrawing.text(
                badge, at: NSPoint(x: rect.minX + 3, y: rect.minY + 1), size: 6, weight: .bold,
                colour: NSColor.white.withAlphaComponent(opacity))
        }

        var y = shot.maxY + 4
        SceneDrawing.text(
            MacUiText.text("Снимок A", language: language), at: NSPoint(x: bubble.minX + 6, y: y), size: 9,
            weight: .semibold, colour: SceneDrawing.accentTextColour.withAlphaComponent(opacity))
        y += 12
        SceneDrawing.text(
            "A1 — \(MacUiText.text("Кнопку ярче", language: language))",
            at: NSPoint(x: bubble.minX + 6, y: y), size: 9,
            colour: NSColor(hex: "#EEF2F8").withAlphaComponent(opacity))
        y += 12
        SceneDrawing.text(
            "A2 — \(MacUiText.text("Убрать блок", language: language))",
            at: NSPoint(x: bubble.minX + 6, y: y), size: 9,
            colour: NSColor(hex: "#EEF2F8").withAlphaComponent(opacity))
        NSGraphicsContext.restoreGraphicsState()
    }
}
