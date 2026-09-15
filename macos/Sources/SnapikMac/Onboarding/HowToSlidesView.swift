// Port of `src/Snapik.App/Controls/HowToSlides.xaml(.cs)`, SPEC-DELTA-3 §1.6 O-7 and
// `tasks/tz-005-details/A-onboarding.md` §A6.
import AppKit
import SnapikCore

/// The four how-to slides: a capture into a chat, a package of captures, comments on the markers and
/// the life of the strip. Each of them is one loop of nine seconds; the control shows one drawing at
/// a time, moves on by a clock of its own and lets the user step through the dots and the chevrons.
/// It is a view of its own so that the wizard keeps its shape, and so that the menu bar can open the
/// slides alone. The automatic run goes round; the user does not, and the first move the user makes
/// stops the automatic run for good.
final class HowToSlidesView: NSView {
    static let slideCount = 4
    static let contentWidth: CGFloat = 480
    /// [ТЗ№4 A6] The block of captions is this tall on every slide, so the dots under it stand in one
    /// place. 140 and not the 120 of the brief: slide 4 is four rows, its second one wraps in both
    /// languages, and 120 would cut it off (`A-onboarding.md` §A6, the arithmetic is there).
    static let captionsHeight: CGFloat = 140
    static let fittingHeight: CGFloat = 30 + 4 + 21 + 12 + 210 + 14 + captionsHeight + 2 + 30

    /// The name of every slide, in the language the control is shown in.
    private static let slideNames = [
        "Снимок с комментариями", "Несколько снимков сразу", "Открыть снимок снова", "Лента снимков",
    ]

    private static let slideCaptions: [[String]] = [
        [
            "Выдели область экрана, которую хочешь снять.",
            "Поставь комментарии там, где удобно — сколько нужно.",
            "Ctrl+V в любой чат — картинка и комментарии вставятся вместе.",
        ],
        [
            "Сделай несколько снимков подряд.",
            "Все они собираются в ленту у края экрана.",
            "У каждого — свои комментарии.",
            "Ctrl+V — и вся пачка уходит одним сообщением.",
        ],
        [
            "Каждый снимок хранит свои комментарии.",
            "Клик по снимку в ленте — он открывается снова, всё на месте.",
            "Поправь и закрой — изменения останутся в ленте.",
        ],
        [
            "Лента живёт, пока открыта. Закроешь — снимки удалятся.",
            "Сохранить — «Сохранить пакет…», или включи автосохранение в папку.",
            "Мешает — сверни в капсулу, клик разворачивает обратно.",
            "Лишний снимок — крестик. Всё сразу — «Очистить».",
        ],
    ]

    private let heading = NSTextField(labelWithString: "")
    private let slideTitle = NSTextField(labelWithString: "")
    private let sceneBox = SceneBoxView()
    private let welcomeScene = CaptureSceneSmallView(frame: .zero)
    private let scene2 = SlideTwoSceneView(frame: .zero)
    private let scene3 = SlideThreeSceneView(frame: .zero)
    private let scene4 = SlideFourSceneView(frame: .zero)
    private let captions = SlideCaptionsView(frame: .zero)
    private let previousButton = SlideChevronButton(pointsLeft: true)
    private let nextButton = SlideChevronButton(pointsLeft: false)
    private let dots: [SlideDotButton]

    private var language = "ru"
    private var slide = 0
    private var running = false
    private var autoAdvance = true
    // The user has taken the slides into their own hands, for as long as this view lives. In the
    // wizard the step with the slides is left and entered again (Back, then Next), and Start runs a
    // second time; without this the carousel began moving on its own under a hand that had stopped it.
    private var steppedByHand = false
    private var lastTick: Double = 0
    private lazy var clock = SceneClock { [weak self] time in self?.tick(time) }

    override init(frame frameRect: NSRect) {
        dots = (0..<Self.slideCount).map { SlideDotButton(index: $0) }
        super.init(frame: frameRect)
        heading.font = NSFont.systemFont(ofSize: 24, weight: .semibold)
        slideTitle.font = NSFont.systemFont(ofSize: 14)
        addSubview(heading)
        addSubview(slideTitle)
        for scene in [welcomeScene, scene2, scene3, scene4] as [NSView] { sceneBox.addSubview(scene) }
        addSubview(sceneBox)
        addSubview(captions)
        previousButton.target = self
        previousButton.action = #selector(previousClicked)
        nextButton.target = self
        nextButton.action = #selector(nextClicked)
        addSubview(previousButton)
        addSubview(nextButton)
        for dot in dots {
            dot.onPick = { [weak self] index in self?.goTo(index) }
            addSubview(dot)
        }
        showSlide(0)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Which slide is on screen, 0 based.
    var currentSlide: Int { slide }

    /// Whether the slides still move on by themselves; the first move of the user ends it.
    var isAutoAdvancing: Bool { running && autoAdvance }

    /// Starts the slides from the one on screen; calling it twice changes nothing.
    func start() {
        guard !running else { return }
        running = true
        autoAdvance = !steppedByHand
        play()
    }

    /// Stops the slides and parks their clock. It runs whenever the step goes off screen and when the
    /// window closes, and it has to survive being called twice.
    func stop() {
        running = false
        clock.stop()
        welcomeScene.halt()
    }

    /// Shows one slide and restarts its clock while the slides are running.
    func showSlide(_ index: Int) {
        slide = min(max(index, 0), Self.slideCount - 1)
        slideTitle.stringValue = MacUiText.text(Self.slideNames[slide], language: language)
        welcomeScene.isHidden = slide != 0
        scene2.isHidden = slide != 1
        scene3.isHidden = slide != 2
        scene4.isHidden = slide != 3
        captions.rows = Self.slideCaptions[slide].map { MacUiText.text($0, language: language) }
        for (index, dot) in dots.enumerated() { dot.isCurrent = index == slide }
        // The chevrons say where the ends are instead of wrapping around silently.
        previousButton.isEnabled = slide > 0
        nextButton.isEnabled = slide < Self.slideCount - 1
        if running { play() }
    }

    /// One slide forward or back, on behalf of the user: a chevron, a dot or an arrow key. The ends
    /// hold, and the automatic run stops, because the user has said which slide to look at.
    func step(_ delta: Int) {
        stopAutoAdvance()
        let target = min(max(slide + delta, 0), Self.slideCount - 1)
        guard target != slide else { return }
        showSlide(target)
    }

    /// The slide the user picked by its dot; out of range is clamped, as in `showSlide`.
    func goTo(_ index: Int) {
        stopAutoAdvance()
        showSlide(index)
    }

    func applyLanguage(_ language: String) {
        self.language = language
        heading.stringValue = MacUiText.text("Как пользоваться", language: language)
        previousButton.toolTip = MacUiText.text("Предыдущий слайд", language: language)
        nextButton.toolTip = MacUiText.text("Следующий слайд", language: language)
        for (index, dot) in dots.enumerated() {
            dot.toolTip = UiFormat.text(
                MacUiText.text("Слайд {0} из {1}", language: language), "\(index + 1)", "\(Self.slideCount)")
        }
        welcomeScene.applyLanguage(language)
        for scene in [scene2, scene3, scene4] { scene.language = language }
        showSlide(slide)
        needsLayout = true
    }

    func applyTheme(_ palette: ThemePalette) {
        heading.textColor = palette.text
        slideTitle.textColor = palette.textMuted
        captions.palette = palette
        for dot in dots { dot.palette = palette }
        previousButton.palette = palette
        nextButton.palette = palette
        sceneBox.needsDisplay = true
    }

    private func play() {
        lastTick = 0
        clock.start()
        if slide == 0 { welcomeScene.play() } else { welcomeScene.halt() }
        // With the animations of the system switched off the slide shows its finished picture and the
        // clock never runs; the user steps through the slides by hand.
        if !SceneClock.animationsAllowed { tick(SceneClock.finishedFrame) }
    }

    private func tick(_ time: Double) {
        // The loop has come round: the wait is always a whole slide long, whichever slide it is and
        // however it was reached. Left alone, the slides go round — a carousel that stops on the
        // fourth slide looks broken.
        if time < lastTick && running && autoAdvance {
            lastTick = time
            showSlide((slide + 1) % Self.slideCount)
            return
        }
        lastTick = time
        scene2.time = time
        scene3.time = time
        scene4.time = time
        captions.time = time
        sceneBox.progress = CGFloat(time / SceneClock.duration)
    }

    private func stopAutoAdvance() {
        autoAdvance = false
        steppedByHand = true
    }

    @objc private func previousClicked() { step(-1) }

    @objc private func nextClicked() { step(1) }

    /// How tall the captions of one slide are in one language, measured the way they are drawn: what
    /// [ТЗ№4 A6] fixes the block at 140 for.
    func smokeCaptionsHeight(forSlide index: Int, language: String) -> CGFloat {
        let rows = Self.slideCaptions[min(max(index, 0), Self.slideCount - 1)]
            .map { MacUiText.text($0, language: language) }
        return SlideCaptionsView.height(of: rows, width: Self.contentWidth)
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        heading.frame = NSRect(x: 0, y: bounds.height - 30, width: width, height: 30)
        slideTitle.frame = NSRect(x: 0, y: bounds.height - 30 - 4 - 21, width: width, height: 21)
        var y = bounds.height - 30 - 4 - 21 - 12 - 210
        sceneBox.frame = NSRect(x: 0, y: y, width: width, height: 210)
        for scene in [welcomeScene, scene2, scene3, scene4] as [NSView] {
            scene.frame = sceneBox.bounds
        }
        y -= 14 + Self.captionsHeight
        captions.frame = NSRect(x: 0, y: y, width: width, height: Self.captionsHeight)
        y -= 2 + 30
        let rowWidth: CGFloat = 30 + 14 + CGFloat(Self.slideCount) * 24 + 14 + 30
        var x = (width - rowWidth) / 2
        previousButton.frame = NSRect(x: x, y: y, width: 30, height: 30)
        x += 30 + 14
        for dot in dots {
            dot.frame = NSRect(x: x, y: y + 7, width: 16, height: 16)
            x += 24
        }
        x += 14 - 8
        nextButton.frame = NSRect(x: x, y: y, width: 30, height: 30)
    }
}

// MARK: - Pieces

/// The box the drawing sits in, with the bar along its bottom edge saying how much of the loop is
/// left.
private final class SceneBoxView: NSView {
    var progress: CGFloat = 0 { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerRadius = 12
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        SceneDrawing.fill(bounds, NSColor(hex: "#12161D"), radius: 12)
        SceneDrawing.stroke(bounds, NSColor(hex: "#2A3240"), radius: 12)
        SceneDrawing.fill(NSRect(x: 0, y: 0, width: bounds.width, height: 2), NSColor(hex: "#2A3240"))
        let accent = ThemeService.accent(ThemeService.currentAccent).flat.withAlphaComponent(0.7)
        SceneDrawing.fill(NSRect(x: 0, y: 0, width: bounds.width * progress, height: 2), accent)
    }
}

/// The lines of the slide: a number in a circle and the sentence beside it. They come one after
/// another and stay, so by the end of the loop the whole list is on screen. The block is a fixed
/// height, which is why the dots under it never move ([ТЗ№4 A6]).
private final class SlideCaptionsView: NSView {
    /// When each row after the first one arrives; the first one is there from the start.
    private static let arrivals: [(Double, Double)] = [(1.62, 2.07), (3.06, 3.51), (5.04, 5.49)]

    var rows: [String] = [] { didSet { needsDisplay = true } }
    var time: Double = 0 { didSet { needsDisplay = true } }
    var palette: ThemePalette = ThemeService.palette(nil) { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    /// The height of a block of rows, measured the way `draw` lays them out: a circle of 22 or the
    /// wrapped text, whichever is taller, and 10 under every row but the last.
    static func height(of rows: [String], width: CGFloat) -> CGFloat {
        let textWidth = width - 22 - 12
        var total: CGFloat = 0
        for (index, row) in rows.enumerated() {
            let text = NSAttributedString(
                string: row, attributes: [.font: NSFont.systemFont(ofSize: 14)])
            let rect = text.boundingRect(
                with: NSSize(width: textWidth, height: 1000),
                options: [.usesLineFragmentOrigin, .usesFontLeading])
            total += max(22, ceil(rect.height))
            if index < rows.count - 1 { total += 10 }
        }
        return total
    }

    override func draw(_ dirtyRect: NSRect) {
        let textWidth = bounds.width - 22 - 12
        var y: CGFloat = 0
        for (index, row) in rows.enumerated() {
            let opacity: CGFloat
            let shift: CGFloat
            if index == 0 {
                opacity = 1
                shift = 0
            } else {
                let arrival = Self.arrivals[min(index - 1, Self.arrivals.count - 1)]
                opacity = SceneEase.value(time, from: arrival.0, to: arrival.1, start: 0, end: 1)
                shift = SceneEase.value(time, from: arrival.0, to: arrival.1, start: -8, end: 0)
            }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: palette.text.withAlphaComponent(opacity),
            ]
            let text = NSAttributedString(string: row, attributes: attributes)
            let textRect = text.boundingRect(
                with: NSSize(width: textWidth, height: 1000),
                options: [.usesLineFragmentOrigin, .usesFontLeading])
            let rowHeight = max(22, ceil(textRect.height))

            if opacity > 0 {
                let badge = NSRect(x: shift, y: y, width: 22, height: 22)
                AppearanceBrush.fill(
                    ThemeService.accent(ThemeService.currentAccent).brush,
                    in: NSBezierPath(ovalIn: badge), bounds: badge)
                SceneDrawing.text(
                    "\(index + 1)", at: NSPoint(x: badge.minX + 7.5, y: badge.minY + 4), size: 11,
                    weight: .bold, colour: NSColor.white.withAlphaComponent(opacity))
                text.draw(
                    with: NSRect(x: 22 + 12 + shift, y: y, width: textWidth, height: rowHeight + 4),
                    options: [.usesLineFragmentOrigin, .usesFontLeading])
            }
            y += rowHeight + 10
        }
    }
}

/// The chevron beside the dots.
private final class SlideChevronButton: NSButton {
    private let pointsLeft: Bool
    var palette: ThemePalette = ThemeService.palette(nil) { didSet { needsDisplay = true } }

    init(pointsLeft: Bool) {
        self.pointsLeft = pointsLeft
        super.init(frame: .zero)
        isBordered = false
        title = ""
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let alpha: CGFloat = isEnabled ? 1 : 0.42
        let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        palette.elevated.withAlphaComponent(alpha).setFill()
        box.fill()
        palette.divider.withAlphaComponent(alpha).setStroke()
        box.lineWidth = 1
        box.stroke()

        let arrow = NSBezierPath()
        let dx: CGFloat = pointsLeft ? 3 : -3
        arrow.move(to: NSPoint(x: bounds.midX + dx, y: bounds.midY + 5.5))
        arrow.line(to: NSPoint(x: bounds.midX - dx, y: bounds.midY))
        arrow.line(to: NSPoint(x: bounds.midX + dx, y: bounds.midY - 5.5))
        arrow.lineWidth = 1.5
        arrow.lineCapStyle = .round
        arrow.lineJoinStyle = .round
        palette.text.withAlphaComponent(alpha).setStroke()
        arrow.stroke()
    }
}

/// One dot of the row: the slide it stands for, in the accent while it is the one on screen.
private final class SlideDotButton: NSView {
    private let index: Int
    var isCurrent = false { didSet { needsDisplay = true } }
    var palette: ThemePalette = ThemeService.palette(nil) { didSet { needsDisplay = true } }
    var onPick: ((Int) -> Void)?

    init(index: Int) {
        self.index = index
        super.init(frame: .zero)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func mouseDown(with event: NSEvent) { onPick?(index) }

    override func draw(_ dirtyRect: NSRect) {
        let dot = NSRect(x: bounds.midX - 4, y: bounds.midY - 4, width: 8, height: 8)
        if isCurrent {
            AppearanceBrush.fill(
                ThemeService.accent(ThemeService.currentAccent).brush, in: NSBezierPath(ovalIn: dot),
                bounds: dot)
        } else {
            palette.divider.setFill()
            NSBezierPath(ovalIn: dot).fill()
        }
    }
}
