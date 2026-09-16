// Port of the `ScaleSwitch` border of `OverlayEditorWindow.xaml:291-298` and the caption
// `ShotKindChip` of `:175-182`, SPEC-DELTA-4 §1.3 E-5, E-7, §3.5, §4.
import AppKit

/// Beside the panel, and only for a capture too large to be shown at its own size: the left segment
/// fits it into the screen and says how far it was scaled down, the right one shows it pixel for
/// pixel and lets the wheel, Shift, Cmd and the space bar move it.
@MainActor
final class EditorScaleSwitchView: NSView {
    static let height: CGFloat = 36

    /// Both handlers of the controller end with `syncScaleSwitch()`: a press on the segment that is
    /// already in force changes no scale, the canvas raises nothing, and the two segments would be
    /// left showing neither of them (SPEC-DELTA-4 §5 point 3).
    var onFitClicked: (() -> Void)?
    var onOneToOneClicked: (() -> Void)?

    /// What the left segment says and which of the two is in force, read back by the smoke probe of
    /// the round (SPEC-DELTA-4 §6, `RunEditorScaleProbe`).
    private(set) var fitCaption = ""
    private(set) var isFitted = true

    private let fitSegment: EditorSegmentView
    private let oneToOneSegment: EditorSegmentView
    private static let segmentInset: CGFloat = 1
    private static let captionPadding: CGFloat = 24

    override var isFlipped: Bool { true }

    init(language: String) {
        fitSegment = EditorSegmentView(tag: "fit", caption: "")
        oneToOneSegment = EditorSegmentView(tag: "one-to-one", caption: EditorStrings.oneToOne)
        super.init(frame: CGRect(x: 0, y: 0, width: 200, height: Self.height))
        fitSegment.onClick = { [weak self] in self?.onFitClicked?() }
        oneToOneSegment.onClick = { [weak self] in self?.onOneToOneClicked?() }
        addSubview(fitSegment)
        addSubview(oneToOneSegment)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The caption of the left segment and which of the two is in force, in one call — the switch
    /// has no state of its own to fall out of step with the canvas.
    func update(fitCaption: String, fitted: Bool) {
        self.fitCaption = fitCaption
        isFitted = fitted
        fitSegment.caption = fitCaption
        fitSegment.setAccessibilityLabel(fitCaption)
        fitSegment.isChosen = fitted
        oneToOneSegment.isChosen = !fitted
        needsLayout = true
        needsDisplay = true
    }

    /// The width the two segments ask for, which is what the placement of the panel keeps room for
    /// (`PositionToolbar`, `OverlayEditorWindow.xaml.cs:1741-1746`).
    func sizeToFitContent() -> CGSize {
        let width = Self.segmentInset * 2 + captionWidth(of: fitSegment) + captionWidth(of: oneToOneSegment)
        let size = CGSize(width: max(120, width), height: Self.height)
        setFrameSize(size)
        layout()
        return size
    }

    private func captionWidth(of segment: EditorSegmentView) -> CGFloat {
        let caption = segment.caption ?? ""
        let measured = NSAttributedString(string: caption, attributes: [.font: EditorTheme.systemFont(12)]).size().width
        return measured + Self.captionPadding
    }

    override func layout() {
        super.layout()
        let inset = Self.segmentInset
        let height = bounds.height - inset * 2
        let fitWidth = captionWidth(of: fitSegment)
        let oneWidth = max(bounds.width - inset * 2 - fitWidth, 0)
        fitSegment.frame = CGRect(x: inset, y: inset, width: fitWidth, height: height)
        oneToOneSegment.frame = CGRect(x: inset + fitWidth, y: inset, width: oneWidth, height: height)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9)
        EditorTheme.toolbarBackground.setFill()
        path.fill()
        path.lineWidth = 1
        EditorTheme.toolbarBorder.setStroke()
        path.stroke()
    }
}

/// What the capture is, inside its top right corner: the whole screen with the number of monitors,
/// or a file that was imported, and the size in pixels either way. A capture of a region says
/// nothing and the caption stays away (`ShotKindChip`, `SyncShotKind`).
@MainActor
final class EditorShotKindView: NSView {
    private static let padding = CGSize(width: 10, height: 4)
    private static let glyphWidth: CGFloat = 16
    private static let glyphGap: CGFloat = 6

    private var symbolName = EditorIcon.display
    /// Read back by the smoke probe: the caption is the one string the editor says about the kind of
    /// the capture (SPEC-DELTA-4 §6).
    private(set) var caption = ""

    override var isFlipped: Bool { true }

    /// The caption belongs to the picture under it: it never takes a press away from the canvas
    /// (`IsHitTestVisible="False"`).
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// A monitor for the whole screen, a sheet of paper for a file: the two glyphs the card in the
    /// strip wears for the same two kinds.
    func update(symbolName: String, caption: String) {
        self.symbolName = symbolName
        self.caption = caption
        setAccessibilityLabel(caption)
        needsDisplay = true
    }

    func sizeToFitContent() -> CGSize {
        let measured = NSAttributedString(string: caption, attributes: [.font: EditorTheme.systemFont(12)]).size()
        return CGSize(
            width: Self.padding.width * 2 + Self.glyphWidth + Self.glyphGap + measured.width,
            height: Self.padding.height * 2 + max(measured.height, Self.glyphWidth))
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
        EditorTheme.hintBackground.setFill()
        path.fill()

        let glyph = CGRect(x: Self.padding.width, y: 0, width: Self.glyphWidth, height: bounds.height)
        EditorIcon.draw(symbol: symbolName, in: glyph, color: EditorTheme.textSecondaryD9, pointSize: 12)

        let text = NSAttributedString(
            string: caption,
            attributes: [.font: EditorTheme.systemFont(12), .foregroundColor: EditorTheme.textSecondaryD9])
        let size = text.size()
        text.draw(at: CGPoint(x: glyph.maxX + Self.glyphGap, y: bounds.midY - size.height / 2))
    }
}
