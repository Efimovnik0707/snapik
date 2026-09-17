// Port of `src/Snapik.App/Controls/AnnotationCanvas.cs`, SPEC §6.3 (state + interaction half;
// see `AnnotationCanvasView+Drawing.swift` for `draw(_:)`), SPEC-DELTA-3 §1.4 E-4, E-5, E-8, E-9,
// E-10, E-13.
import AppKit
import SnapikCore

/// Custom drawing surface for the active capture's annotations (SPEC §6.3). `isFlipped = true` so
/// its coordinate system matches the WPF `Canvas` (top-left origin, Y down) the spec's formulas
/// were written against, and the `IconPath`/IconPath-style geometry used elsewhere in the editor.
@MainActor
final class AnnotationCanvasView: NSView {
    /// The capture currently being edited. Reassigning it (as `OverlayEditorController` does on
    /// every `setupEditor`/undo-redo restore) resets the selection, mirroring
    /// `AnnotationCanvas.OnAnnotationsChanged` (`:83-90`) which fires whenever the bound
    /// `Annotations` collection is replaced.
    var capture: EditorCapture? {
        didSet {
            selectedAnnotation = nil
            blurCache = nil
            needsDisplay = true
        }
    }

    var tool: EditorTool = .rectangle {
        didSet {
            // Another tool was armed from a button or a key without the pointer moving: what the
            // eraser was pointing at is not its target any more (`OnToolChanged`, `:129-132`).
            if tool != .eraser { clearEraseHover() }
        }
    }
    var activeColor: NSColor = EditorTheme.defaultAnnotationColor
    var activeThickness: Double = EditorAppearance.defaultAnnotationThickness
    /// Port of `AnnotationCanvas.cs:43` `ActiveArrowStyle = "straight"` (SPEC-DELTA-2.md §1.2):
    /// the style a brand-new Arrow annotation is created with; updated by the arrow-style menu.
    var activeArrowStyle: String = "straight"
    /// Port of `ActiveShape`/`ActiveFill`/`ActiveFillColor`/`ActiveLineStyle`/`ActiveFontSize`
    /// (`AnnotationCanvas.cs:57-63`): what the next mark is born with.
    var activeShape: AnnotationShape = .rectangle
    var activeFill: AnnotationFill = .none
    var activeFillColor: NSColor?
    var activeLineStyle: AnnotationLineStyle = .solid
    var activeFontSize: Double = TextMarkMetrics.defaultFontSize
    /// Port of `EditingTextId` (`AnnotationCanvas.cs:65`, SPEC-DELTA-3 §1.4 E-6): the caption whose
    /// letters are being typed on the capture right now. The canvas leaves it to the field standing
    /// over it, otherwise the caption is drawn twice.
    var editingTextId: SBGuid?
    /// Set by the controller on every `setupEditor()` (finding 22): the real UI language, used
    /// only for a new Text-tool draft's placeholder ("Текст"/"Text") — everywhere else on this
    /// view text is either annotation-authored or drawn by `AnnotationPainter`/the controller.
    var language: String = "ru"
    /// Forced to 0 by the overlay (SPEC §1.3: "холст разметки `AnnotationCanvas` ... с
    /// `ImagePadding = 0`"); left configurable to match the Windows default of 28 for any future
    /// non-overlay host.
    var imagePadding: CGFloat = 0

    /// Port of `ViewScale` (`AnnotationCanvas.cs:75-87`, SPEC-DELTA-4 §4.1). `nil` is "fit": the
    /// picture is scaled down to the canvas and centred, the way it always was. Anything else is the
    /// scale in points per pixel of the picture, and the picture stands where `viewOffset` holds it.
    /// Everything the canvas measures is counted from `imageRect`, which those two decide, so the
    /// marks follow without a line of their own.
    var viewScale: Double? {
        didSet {
            guard viewScale != oldValue else { return }
            needsDisplay = true
            onViewChanged?()
        }
    }

    /// How far the picture is scrolled, in points. Ignored while fitting (`:90`).
    var viewOffset: CGPoint = .zero

    /// Space is held down: the next press drags the picture instead of drawing on it (`:99-100`).
    var panning = false

    private var panStart: CGPoint?
    private var panOrigin: CGPoint = .zero

    private(set) var selectedAnnotation: EditorAnnotation?
    // Setter is internal (not private) so `AnnotationCanvasView+Drawing.swift` can refresh it.
    var imageRect: CGRect = .zero

    var onAnnotationCreated: ((EditorAnnotation) -> Void)?
    var onSelectionChanged: ((EditorAnnotation?) -> Void)?
    var onAnnotationChanged: (() -> Void)?
    var onCropRequested: ((CGRect) -> Void)?
    /// Port of `ViewChanged` (`:101`): the scale or the offset changed, and the switch beside the
    /// panel, the corner handles and the pills all follow it.
    var onViewChanged: (() -> Void)?
    /// Port of `AnnotationActivated` (`:203-208`): a double click opens the note of whatever it
    /// lands on — the text editor for a caption, the note pill for everything else.
    var onAnnotationActivated: ((EditorAnnotation) -> Void)?

    // Draft gesture state (SPEC §6.3 "Взаимодействие")
    var draft: EditorAnnotation?
    private var gestureStart: CGPoint?

    // Manipulation (move/resize an existing annotation) state
    // Internal (not private): read by `AnnotationCanvasView+Drawing.swift`'s blur-manipulation check.
    var manipulating = false
    private var resizing = false
    private var resizeCorner = -1
    private var originalBounds: CGRect = .zero
    private var originalPoints: [CGPoint] = []
    private var originalAdditionalSegments: [[CGPoint]] = []
    private var manipulationChanged = false
    /// A click on a mark with a pixel of tremor in it is a click and not a drag: without this gate
    /// every press on a selected mark wrote an entry of the history. The threshold is the one the
    /// anchor and a new mark are both measured by, and it is measured on screen
    /// (`AnnotationCanvas.cs:454-455`).
    private var manipulationMoved = false

    // Eraser (SPEC-DELTA-3 §1.4 E-5) — read by `+Drawing.swift`.
    private(set) var eraseHover: EditorAnnotation?

    // Leader anchor drag (SPEC-DELTA-3 §1.4 E-8) — `anchorHoverId` is read by `+Drawing.swift`.
    private(set) var anchorHoverId: SBGuid?
    private var anchorDrag: EditorAnnotation?
    private var anchorOriginPoints: [CGPoint] = []
    private var anchorOriginOffset: CGPoint?
    private var anchorDragStart: CGPoint = .zero
    private var anchorMoved = false

    /// Five pixels of circle and seven of reach: the circle grows to the reach under the pointer, so
    /// what answers the press is what is seen at that moment (`AnnotationCanvas.cs:780-782`).
    static let anchorRadius: CGFloat = 5
    static let anchorHoverRadius: CGFloat = 7

    // Blur raster cache (SPEC §1.7)
    var blurCache: CGImage?
    var blurCacheKey: Int?

    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func layout() {
        super.layout()
        recomputeImageRect()
    }

    // Internal (not private): also called from `AnnotationCanvasView+Drawing.swift`.
    func recomputeImageRect() {
        guard let capture else { imageRect = .zero; return }
        // One line decides the rectangle the picture is drawn in, and the eleven places that count
        // from it follow without a line of their own (`OnRender`, `:190`).
        if let scale = viewScale {
            imageRect = scaledRect(scale, capture: capture)
            return
        }
        imageRect = EditorGeometry.fitRect(
            imageWidth: Double(capture.image.width), imageHeight: Double(capture.image.height),
            width: Double(bounds.width), height: Double(bounds.height), padding: Double(imagePadding))
    }

    /// Port of `ScaledRect` (`:1031-1035`): the picture at a scale of its own, with the offset held
    /// first, so no edge of it ever comes inside the canvas.
    private func scaledRect(_ scale: Double, capture: EditorCapture) -> CGRect {
        let image = CGSize(width: capture.image.width, height: capture.image.height)
        viewOffset = EditorGeometry.clampOffset(image: image, scale: scale, viewport: bounds.size, offset: viewOffset)
        return CGRect(
            x: -viewOffset.x, y: -viewOffset.y,
            width: image.width * CGFloat(scale), height: image.height * CGFloat(scale))
    }

    /// Port of `FitScale` (`:93-97`): the scale the picture is shown at while fitting, and the floor
    /// of the wheel held with Cmd.
    var fitScale: Double {
        guard let capture, capture.image.width > 0, capture.image.height > 0 else { return 1 }
        return min(
            Double(max(1, bounds.width - imagePadding * 2)) / Double(capture.image.width),
            Double(max(1, bounds.height - imagePadding * 2)) / Double(capture.image.height))
    }

    /// Points-per-image-pixel, the number every on-screen measurement is taken in.
    var displayScale: CGFloat {
        guard let capture, capture.image.width > 0, imageRect.width > 0 else { return 1 }
        return imageRect.width / CGFloat(capture.image.width)
    }

    // MARK: - Coordinate mapping

    private func toImage(_ point: CGPoint) -> CGPoint {
        guard let capture, imageRect.width > 0, imageRect.height > 0 else { return .zero }
        return CGPoint(
            x: (point.x - imageRect.minX) * CGFloat(capture.image.width) / imageRect.width,
            y: (point.y - imageRect.minY) * CGFloat(capture.image.height) / imageRect.height)
    }

    /// Port of `ToDisplay` (`:855-857`).
    func toDisplay(_ imagePoint: CGPoint) -> CGPoint {
        guard let capture, capture.image.width > 0, capture.image.height > 0 else { return imagePoint }
        return CGPoint(
            x: imageRect.minX + imagePoint.x * imageRect.width / CGFloat(capture.image.width),
            y: imageRect.minY + imagePoint.y * imageRect.height / CGFloat(capture.image.height))
    }

    private func clampToImage(_ point: CGPoint) -> CGPoint {
        guard let capture else { return point }
        return CGPoint(
            x: EditorGeometry.clamp(point.x, 0, CGFloat(capture.image.width)),
            y: EditorGeometry.clamp(point.y, 0, CGFloat(capture.image.height)))
    }

    /// Port of `AnnotationCanvas.GetDisplayBounds` (`:259-268`).
    func displayBounds(of annotation: EditorAnnotation) -> CGRect {
        guard let capture else { return .null }
        let bounds = EditorGeometry.boundsOf(points: annotation.points, additionalSegments: annotation.additionalPathSegments)
        return EditorGeometry.displayBounds(
            imageBounds: bounds, imageRect: imageRect,
            imageWidth: Double(capture.image.width), imageHeight: Double(capture.image.height))
    }

    /// Port of `BadgeOf` (`:836-845`): the circle with the number of a noted mark, in `target`'s
    /// coordinate space. A pin without a note carries no badge yet, but it still has to be grabbable.
    func badgeOf(_ item: EditorAnnotation, target: CGRect) -> NoteBadge {
        guard let capture, let first = item.points.first else { return NoteBadge(center: .zero, radius: 13) }
        let width = CGFloat(capture.image.width)
        let height = CGFloat(capture.image.height)
        let anchor = CGPoint(
            x: target.minX + first.x * target.width / width,
            y: target.minY + first.y * target.height / height)
        if item.kind == .comment, item.label.isEmpty { return NoteBadge(center: anchor, radius: 13) }
        let offset = item.noteOffset.map { CGPoint(x: $0.x * target.width / width, y: $0.y * target.height / height) } ?? .zero
        return NoteBadgeGeometry.screen(anchor: anchor, label: item.label, offset: offset)
    }

    /// Port of `GetBadgeCenter`/`GetBadgeRadius` (`:848-853`): where the pill of a note stands.
    func badgeCenter(of annotation: EditorAnnotation) -> CGPoint { badgeOf(annotation, target: imageRect).center }

    func badgeRadius(of annotation: EditorAnnotation) -> CGFloat { badgeOf(annotation, target: imageRect).radius }

    // MARK: - Selection (public, used by the controller for the context-note button flow)

    func selectAnnotation(id: SBGuid?) {
        guard let capture else { select(nil); return }
        select(id.flatMap { targetId in capture.annotations.first(where: { $0.id == targetId }) })
    }

    private func select(_ annotation: EditorAnnotation?) {
        selectedAnnotation = annotation
        onSelectionChanged?(annotation)
        needsDisplay = true
    }

    // MARK: - Mouse events

    override func mouseDown(with event: NSEvent) {
        recomputeImageRect()
        window?.makeFirstResponder(self)
        guard capture != nil else { return }
        beginGesture(convert(event.locationInWindow, from: nil), clickCount: event.clickCount)
    }

    /// Port of `BeginGesture` (`:184-272`). Not private: a smoke run presses, drags and lets go
    /// through these three without a pointer on screen.
    func beginGesture(_ point: CGPoint, clickCount: Int = 1) {
        guard let capture else { return }
        // Space held down turns the press into a drag of the picture itself, wherever it lands
        // (`:224-228`). It is `PressTarget.pan` of the rule below, asked here because only the canvas
        // knows whether the picture has a scale of its own to be dragged at.
        if panning, viewScale != nil {
            panStart = point
            panOrigin = viewOffset
            return
        }
        guard imageRect.contains(point) else { return }

        let imagePoint = toImage(point)
        let anchored = findLeaderAnchor(point)
        let handleHit = findResizeHandle(point)
        let under = hitTestAnnotation(imagePoint)
        let grabbed = findMoveHandle(point) ?? under
        // One order for every tool, and no branch per tool: whatever is in the hand, the corners of
        // the selected mark, the anchor of a comment and the mark under the cursor answer before a
        // new mark is begun. The rule itself lives in `AnnotationRules`, where a test can reach it.
        switch AnnotationRules.pressTargetOf(
            tool: tool, panning: false, clickCount: clickCount,
            onAnchor: anchored != nil, onSelectedHandle: handleHit.annotation != nil,
            onObject: grabbed != nil, activatable: under?.kind == .text || under?.kind == .comment
        ) {
        case .pan:
            // The drag of the picture is taken above, where the mode of the view is known.
            return

        // The eraser draws nothing: it removes the mark under the pointer and tells the controller,
        // which turns that into one history entry, exactly as the Delete key does.
        case .erase:
            guard let target = eraseTarget(point) else { return }
            select(nil)
            capture.annotations.removeAll(where: { $0 === target })
            eraseHover = nil
            onAnnotationChanged?()
            needsDisplay = true
            return

        // A double click opens what can be typed into: the field of a caption, the pill of a
        // comment. On a frame or an arrow it is two single clicks, that is, a selection, and it
        // falls to the branches below.
        case .activate:
            guard let under else { return }
            select(under)
            onAnnotationActivated?(under)
            return

        // The anchor of a leader is taken before the resize handles: it sits on the point of a
        // comment, a place where the handle of a neighbouring mark may lie as well, and the handle
        // would win the press by being asked first.
        case .commentAnchor:
            guard let anchored else { return }
            select(anchored)
            anchorDrag = anchored
            anchorOriginPoints = anchored.points
            anchorOriginOffset = anchored.noteOffset
            anchorDragStart = imagePoint
            anchorMoved = false
            return

        case .resizeHandle, .object:
            guard let hit = handleHit.annotation ?? grabbed else { return }
            select(hit)
            gestureStart = imagePoint
            originalPoints = hit.points
            originalAdditionalSegments = hit.additionalPathSegments
            originalBounds = EditorGeometry.boundsOf(points: hit.points, additionalSegments: hit.additionalPathSegments)
            resizeCorner = handleHit.corner
            resizing = resizeCorner >= 0
            manipulating = true
            manipulationChanged = false
            manipulationMoved = false
            return

        // The pointer over an empty place: the selection goes and nothing is begun. It draws no mark
        // of its own, and a draft of its kind would reach `session.json` and the export.
        case .deselect:
            select(nil)
            return

        case .cropDraft, .empty:
            break
        }

        // A press on an empty part of the capture, or the frame of a crop over whatever lies under
        // it: the selection is dropped at once, and from now on the panel belongs to the next mark.
        select(nil)
        let start = imagePoint
        gestureStart = start
        draft = EditorAnnotation(
            kind: tool,
            points: [start, start],
            color: activeColor,
            thickness: activeThickness,
            // The word a new caption starts with comes from the table of the interface: an English
            // window must not get a Russian one.
            text: tool == .text ? EditorStrings.defaultText(language) : "",
            arrowStyle: activeArrowStyle,
            // The frame belongs to a region and to a blur alike; what stands inside it belongs to
            // the region alone. On a caption or a stroke they would only travel into `session.json`
            // and change what a later build draws there.
            shape: EditorAppearance.hasShape(tool) ? activeShape : .rectangle,
            fill: EditorAppearance.hasFill(tool) ? activeFill : .none,
            fillColor: EditorAppearance.hasFill(tool) ? activeFillColor : nil,
            lineStyle: activeLineStyle,
            fontSize: activeFontSize)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        updateGesture(convert(event.locationInWindow, from: nil), pressed: true)
    }

    /// Port of `UpdateGesture` (`:279-336`).
    func updateGesture(_ displayPoint: CGPoint, pressed: Bool) {
        guard let capture else { return }

        // The picture travels under the pointer, and nothing else moves: the marks keep the pixels
        // of the capture they were put on (`:331-336`).
        if let panStart, pressed {
            viewOffset = CGPoint(
                x: panOrigin.x - (displayPoint.x - panStart.x),
                y: panOrigin.y - (displayPoint.y - panStart.y))
            needsDisplay = true
            onViewChanged?()
            return
        }

        // The anchor travels and its badge stays: the note keeps the place it was put in, so the
        // offset of the badge gives back exactly what the anchor takes, and the leader grows between
        // the two. A note that was never moved has no offset to compensate, and its badge follows.
        if let anchored = anchorDrag, pressed, !anchorOriginPoints.isEmpty {
            let current = clampToImage(toImage(displayPoint))
            let moved = CGPoint(x: current.x - anchorDragStart.x, y: current.y - anchorDragStart.y)
            if !anchorMoved, hypot(moved.x, moved.y) * displayScale < EditorGeometry.gestureThreshold { return }
            anchorMoved = true
            for index in anchored.points.indices where index < anchorOriginPoints.count {
                anchored.points[index] = clampToImage(
                    CGPoint(x: anchorOriginPoints[index].x + moved.x, y: anchorOriginPoints[index].y + moved.y))
            }
            if let offset = anchorOriginOffset {
                anchored.noteOffset = CGPoint(x: offset.x - moved.x, y: offset.y - moved.y)
            }
            needsDisplay = true
            return
        }

        if manipulating, let selected = selectedAnnotation, let gestureStart, pressed {
            let current = clampToImage(toImage(displayPoint))
            if !manipulationMoved,
                hypot(current.x - gestureStart.x, current.y - gestureStart.y) * displayScale < EditorGeometry.gestureThreshold {
                return
            }
            manipulationMoved = true
            if resizing {
                // `ResizeGeometry` (Sources/SnapikCore/Geometry/ResizeGeometry.swift) is
                // Foundation-only; CG-typed overloads with matching labels live in
                // `Sources/SnapikMac/Imaging/GeometryBridging.swift`.
                let resized = ResizeGeometry.resize(
                    original: originalBounds, corner: resizeCorner, point: current,
                    limit: CGRect(x: 0, y: 0, width: CGFloat(capture.image.width), height: CGFloat(capture.image.height)),
                    minimum: 2)
                for index in selected.points.indices {
                    selected.points[index] = ResizeGeometry.map(originalPoints[index], original: originalBounds, resized: resized)
                }
                for segmentIndex in selected.additionalPathSegments.indices {
                    for pointIndex in selected.additionalPathSegments[segmentIndex].indices {
                        selected.additionalPathSegments[segmentIndex][pointIndex] = ResizeGeometry.map(
                            originalAdditionalSegments[segmentIndex][pointIndex], original: originalBounds, resized: resized)
                    }
                }
            } else {
                var delta = CGPoint(x: current.x - gestureStart.x, y: current.y - gestureStart.y)
                delta.x = EditorGeometry.clamp(delta.x, -originalBounds.minX, CGFloat(capture.image.width) - originalBounds.maxX)
                delta.y = EditorGeometry.clamp(delta.y, -originalBounds.minY, CGFloat(capture.image.height) - originalBounds.maxY)
                for index in selected.points.indices {
                    selected.points[index] = CGPoint(x: originalPoints[index].x + delta.x, y: originalPoints[index].y + delta.y)
                }
                for segmentIndex in selected.additionalPathSegments.indices {
                    for pointIndex in selected.additionalPathSegments[segmentIndex].indices {
                        let original = originalAdditionalSegments[segmentIndex][pointIndex]
                        selected.additionalPathSegments[segmentIndex][pointIndex] = CGPoint(x: original.x + delta.x, y: original.y + delta.y)
                    }
                }
            }
            manipulationChanged = true
            needsDisplay = true
            return
        }

        guard let draft, gestureStart != nil, pressed else {
            updateCursor(displayPoint)
            return
        }
        let point = clampToImage(toImage(displayPoint))
        if draft.kind == .pen || draft.kind == .highlight {
            draft.points.append(point)
        } else if draft.points.count > 1 {
            draft.points[1] = point
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        endGesture()
    }

    /// Port of `EndGesture` (`:379-436`).
    func endGesture() {
        if panStart != nil {
            panStart = nil
            return
        }

        if anchorDrag != nil {
            let moved = anchorMoved
            anchorDrag = nil
            anchorOriginPoints = []
            anchorOriginOffset = nil
            anchorMoved = false
            // One entry of history for one drag, the way a moved note writes one.
            if moved { onAnnotationChanged?() }
            needsDisplay = true
            return
        }

        if manipulating {
            manipulating = false
            resizing = false
            manipulationMoved = false
            gestureStart = nil
            originalPoints = []
            originalAdditionalSegments = []
            if manipulationChanged { onAnnotationChanged?() }
            needsDisplay = true
            return
        }

        guard let draft else { return }
        self.draft = nil
        gestureStart = nil
        if EditorGeometry.gestureHasSize(kind: draft.kind, points: draft.points, scale: displayScale) {
            if draft.kind == .crop {
                onCropRequested?(EditorGeometry.boundsOf(points: draft.points))
            } else {
                draft.label = ""
                // A caption owns the box its letters take, from the moment it is placed.
                fitTextMark(draft)
                capture?.annotations.append(draft)
                // A stroke of the pen or the highlighter is not selected after the hand lets go: it
                // is drawing, not an object to adjust (SPEC-DELTA-3 §1.4 E-4).
                if draft.kind != .pen && draft.kind != .highlight { select(draft) }
                onAnnotationCreated?(draft)
            }
        }
        needsDisplay = true
    }

    /// Port of `TextMarkMetrics.Fit` (`TextMarkMetrics.cs:39-46`) against the editor's own model:
    /// the second point of a caption is not what the hand drew, it is what the letters take.
    func fitTextMark(_ item: EditorAnnotation) {
        guard item.kind == .text, let anchor = item.points.first else { return }
        let fitted = TextMarkMetrics.fit(
            anchor: GeometryPoint(Double(anchor.x), Double(anchor.y)), text: item.text, fontSize: item.fontSize)
        let second = CGPoint(x: fitted.x, y: fitted.y)
        if item.points.count < 2 {
            item.points.append(second)
        } else {
            item.points[1] = second
        }
    }

    override func mouseMoved(with event: NSEvent) {
        guard draft == nil else { return }
        updateCursor(convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        // The red outline of the eraser belongs to where the pointer is, and the pointer is gone.
        clearEraseHover()
    }

    /// How many points one line of the wheel travels, and the divisor that turns the same number
    /// back into notches: a trackpad reports points and a wheel reports lines, so the two are
    /// brought to one scale before either the picture or the scale moves. Windows counts a notch as
    /// `Delta / 120` (`:1042, 1059`).
    private static let lineTravel: CGFloat = 40

    /// Port of `OnMouseWheel` (`:1168-1182`). The wheel scrolls the picture only while it is shown at
    /// a scale of its own: fitted, there is nothing to scroll. Cmd and the wheel answer from either
    /// state — with the switch beside the panel gone, this is the one way into a scale of one's own
    /// (SPEC-DELTA-5-editor.md §1.2 E-1).
    override func scrollWheel(with event: NSEvent) {
        let zooming = event.modifierFlags.contains(.command)
        guard capture != nil, viewScale != nil || zooming else {
            super.scrollWheel(with: event)
            return
        }

        if zooming {
            // The modifier is Cmd and not Ctrl, which on macOS belongs to the zoom of the system
            // itself. A trackpad reports its travel in points, a wheel in lines.
            let notches = Double(event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / Self.lineTravel : event.scrollingDeltaY)
            zoomByNotches(notches, cursor: convert(event.locationInWindow, from: nil))
            return
        }

        // Shift turns the wheel sideways; two fingers on a trackpad say which way they went by
        // themselves, and AppKit reports that on the other axis already.
        var travelX = event.scrollingDeltaX
        var travelY = event.scrollingDeltaY
        if event.modifierFlags.contains(.shift), travelX == 0 {
            travelX = travelY
            travelY = 0
        }
        let factor = event.hasPreciseScrollingDeltas ? 1 : Self.lineTravel
        viewOffset = CGPoint(x: viewOffset.x - travelX * factor, y: viewOffset.y - travelY * factor)
        needsDisplay = true
        onViewChanged?()
    }

    /// Port of `ZoomByNotches` (`:1189-1214`): one notch of the wheel apart from the modifier that
    /// carries it, because a smoke run has no keyboard to hold Cmd down with.
    func zoomByNotches(_ notches: Double, cursor: CGPoint) {
        guard let capture else { return }
        // The scale the picture stands at right now, a scale of its own or the one it was fitted
        // with. `fitScale` counts from `bounds` less `imagePadding` twice, and the editor hands the
        // canvas `imagePadding = 0`, so the seed is the picture on screen to the pixel and the first
        // notch does not make it jump. Put the padding back and it will.
        let scale = viewScale ?? fitScale
        // Fitted, the picture is centred by `fitRect` and `viewOffset` is never read; scaled, that
        // offset is what holds it. The centred picture written as an offset is the seed, so the
        // point under the cursor stays where it is on the very first notch.
        let offset = viewScale == nil
            ? CGPoint(
                x: -(bounds.width - CGFloat(capture.image.width) * CGFloat(scale)) / 2,
                y: -(bounds.height - CGFloat(capture.image.height) * CGFloat(scale)) / 2)
            : viewOffset
        // A tenth of the scale per notch, between "fit" and the picture at its own size, and nothing
        // beyond those two ends. A capture small enough to stand at its own size is fitted at a scale
        // of one or above, and the floor and the ceiling meet there — without the floor held down to
        // one, the clamp is asked for a range that runs backwards.
        let floor = min(fitScale, 1)
        let wanted = min(max(scale * pow(1.1, notches), floor), 1)
        // Back at the scale the picture is fitted with, the view goes back to fitting.
        guard wanted > floor else {
            viewOffset = .zero
            viewScale = nil
            return
        }
        viewOffset = EditorGeometry.zoomAround(cursor: cursor, offset: offset, fromScale: scale, toScale: wanted)
        viewScale = wanted
        needsDisplay = true
    }

    /// Port of `UpdateCursor` (`:341-362`): arrows on the corners of a selected mark, a hand where a
    /// mark can be grabbed, a crosshair over the capture with a drawing tool armed, and the ordinary
    /// arrow everywhere else.
    private func updateCursor(_ displayPoint: CGPoint) {
        // Space is held: whatever stands under the pointer, the next press drags the picture
        // (`:398-399`).
        if panning, viewScale != nil {
            NSCursor.openHand.set()
            return
        }
        if tool == .eraser {
            let hover = eraseTarget(displayPoint)
            if hover !== eraseHover {
                eraseHover = hover
                needsDisplay = true
            }
            (hover == nil ? NSCursor.arrow : NSCursor.openHand).set()
            return
        }
        clearEraseHover()

        // The anchor is asked first here for the same reason it is asked first on a press: it has to
        // answer for the pixels it covers, handles of neighbouring marks included.
        let anchorHover = findLeaderAnchor(displayPoint)?.id
        if anchorHover != anchorHoverId {
            anchorHoverId = anchorHover
            needsDisplay = true
        }
        if anchorHover != nil {
            NSCursor.openHand.set()
            return
        }

        if findResizeHandle(displayPoint).corner >= 0 {
            // CHECK-API: AppKit has no public diagonal (NWSE/NESW) resize cursor, unlike WPF's
            // `Cursors.SizeNWSE`/`SizeNESW` (SPEC §1.6). `.crosshair` is used for both corner
            // families as the closest stock cursor.
            NSCursor.crosshair.set()
            return
        }

        // [ТЗ№4 D3] The hand over a pin is no longer reserved for the Select tool: with the Comment
        // tool armed a badge is grabbable, so the cursor has to say so (`D-editor.md` §4.2).
        let movablePin = hitTestAnnotation(toImage(displayPoint))?.kind == .comment
        if findMoveHandle(displayPoint) != nil || movablePin {
            NSCursor.openHand.set()
        } else if tool.isDrawing && imageRect.contains(displayPoint) {
            NSCursor.crosshair.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    private func clearEraseHover() {
        guard eraseHover != nil else { return }
        eraseHover = nil
        needsDisplay = true
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case Keycode.delete, Keycode.forwardDelete:
            if let selected = selectedAnnotation, capture != nil {
                select(nil)
                capture?.annotations.removeAll(where: { $0.id == selected.id })
                onAnnotationChanged?()
            } else {
                super.keyDown(with: event)
            }
        case Keycode.space:
            // Space drags the picture while it is held, and the key belongs to no tool: outside the
            // scaled mode it does nothing at all (`OverlayEditorWindow.xaml.cs:1958-1963`).
            if viewScale != nil {
                panning = true
            } else {
                super.keyDown(with: event)
            }
        case Keycode.escape:
            // Escape gives up what is going on, one step at a time: the mark being drawn first, the
            // selection after it. Only with neither of them does the window itself hear the key.
            if draft != nil {
                draft = nil
                gestureStart = nil
                needsDisplay = true
            } else if selectedAnnotation != nil {
                select(nil)
            } else {
                super.keyDown(with: event)
            }
        default:
            super.keyDown(with: event)
        }
    }

    /// Space let go of: the picture stops following the pointer, whatever the mode is by then
    /// (`OverlayEditorWindow.xaml.cs:2012-2017`).
    override func keyUp(with event: NSEvent) {
        guard event.keyCode == Keycode.space, panning else {
            super.keyUp(with: event)
            return
        }
        panning = false
    }

    // MARK: - Hit testing (SPEC §6.3)

    /// Port of `EraseTarget` (`:368-369`): the eraser takes whatever the hand can already grab — the
    /// edge of a frame, the line of an arrow, the stroke of a pen, the badge of a comment, the
    /// inside of a filled or blurred region.
    private func eraseTarget(_ displayPoint: CGPoint) -> EditorAnnotation? {
        findMoveHandle(displayPoint) ?? hitTestAnnotation(toImage(displayPoint))
    }

    /// Port of `FindLeaderAnchor` (`:771-777`). [ТЗ№4 D3] the `Tool == Select` condition is gone:
    /// the anchor answers under every tool, so a comment can be re-aimed without putting the tool
    /// down (`D-editor.md` §4.1 step 1).
    private func findLeaderAnchor(_ point: CGPoint) -> EditorAnnotation? {
        guard let capture else { return nil }
        return capture.annotations.reversed().first(where: { item in
            guard item.kind == .comment, !item.label.isEmpty, let first = item.points.first else { return false }
            let anchor = toDisplay(first)
            return hypot(point.x - anchor.x, point.y - anchor.y) <= Self.anchorHoverRadius
        })
    }

    /// Port of `FindMoveHandle` (`:784-788`): whatever tool is in the hand, the mark under the
    /// pointer answers, and the order of the press decides what that means (`pressTargetOf`).
    func findMoveHandle(_ displayPoint: CGPoint) -> EditorAnnotation? {
        guard let capture else { return nil }
        return capture.annotations.reversed().first(where: { isMoveHandle($0, displayPoint) })
    }

    /// Port of `IsMoveHandle` (`:790-827`): every mark can be grabbed and moved whatever tool is
    /// armed — a box by the band along its outline, a line by the line itself, a comment by its
    /// badge. The interior of a frame stays free for the next drawing, except where the mark is
    /// opaque and there is nothing to draw into.
    private func isMoveHandle(_ item: EditorAnnotation, _ point: CGPoint) -> Bool {
        guard capture != nil, !item.points.isEmpty else { return false }
        // The branch for the Comment tool is gone with the round of 1.6.0: with a pin in the hand a
        // press on the outline of a drawn frame selects the frame, because the order of the press is
        // one for every tool (SPEC-DELTA-5-editor.md §3.5). A pin is put down on an empty place.
        let scale = displayScale
        let band = max(6, item.thickness * scale)
        switch item.kind {
        case .comment:
            return badgeOf(item, target: imageRect).contains(point, slack: 4)
        case .arrow:
            guard item.points.count > 1 else { return false }
            let shaft = ArrowDrawing.shaft(from: toDisplay(item.points[0]), to: toDisplay(item.points[1]), style: item.arrowStyle)
            return EditorGeometry.distanceToPolyline(shaft, point) <= band
        case .pen, .highlight:
            // Half the stroke plus a little slack: the thickness of a mark is the width it is really
            // drawn with now, for the highlighter as well as for the pencil (SPEC-DELTA-3 §1.4 E-4).
            let width = max(6, item.thickness * scale / 2 + 4)
            for segment in [item.points] + item.additionalPathSegments {
                if EditorGeometry.distanceToPolyline(segment.map(toDisplay), point) <= width { return true }
            }
            return false
        default:
            let bounds = displayBounds(of: item)
            // One band for every mark and every tool: eight pixels, which is what a hand hits. A
            // band that changed width with the tool in the hand made the same press mean two things
            // on the same pixel (`AnnotationCanvas.cs:1035`, SPEC-DELTA-5-editor.md §3.4). The
            // interior of an empty frame stays free to draw into.
            let reach: CGFloat = 8
            guard bounds.insetBy(dx: -reach, dy: -reach).contains(point) else { return false }
            // An opaque mark has no free interior, and a small one has no room for a band.
            if Self.hasInteriorGrab(item) || bounds.width < 24 || bounds.height < 24 { return true }
            return EditorGeometry.findMoveEdge(displayBounds: bounds, point: point, band: reach)
        }
    }

    /// Port of `HasInteriorGrab` (`:831-832`): opaque marks are grabbed anywhere inside, and so is a
    /// filled frame; the fill of any other kind means nothing on screen, so its interior stays free
    /// for a new mark. A caption is its own interior — the box around it is the letters.
    private static func hasInteriorGrab(_ item: EditorAnnotation) -> Bool {
        item.kind == .blur || item.kind == .text || (item.kind == .rectangle && item.fill != .none)
    }

    /// Port of `FindResizeHandle` (`AnnotationCanvas.cs:749-755`). The corners belong to the selected
    /// mark and to no other: they are drawn on it alone, and a corner that answers where nothing is
    /// drawn promises a resize the press will not make. Every tool is offered them, the comment
    /// included — one order of the press for all of them (SPEC-DELTA-5-editor.md §3.3). Skips the
    /// kinds without handles (SPEC-DELTA-2B.md §C4: a pin never has resize handles; a caption is
    /// sized by the panel, not by its corners).
    private func findResizeHandle(_ displayPoint: CGPoint) -> (annotation: EditorAnnotation?, corner: Int) {
        guard capture != nil, let selected = selectedAnnotation,
            AnnotationCanvasView.hasResizeHandles(selected)
        else { return (nil, -1) }
        let corner = ResizeGeometry.hitCorner(bounds: displayBounds(of: selected), point: displayPoint, radius: 10)
        return corner >= 0 ? (selected, corner) : (nil, -1)
    }

    private func hitTestAnnotation(_ imagePoint: CGPoint) -> EditorAnnotation? {
        guard let capture else { return nil }
        for annotation in capture.annotations.reversed() {
            let bounds = EditorGeometry.boundsOf(points: annotation.points, additionalSegments: annotation.additionalPathSegments)
            let inflated = EditorGeometry.hitTestInflatedBounds(
                bounds, kind: annotation.kind, thickness: annotation.thickness)
            if inflated.contains(imagePoint) { return annotation }
        }
        return nil
    }

    // MARK: - Smoke probe (CONTRACTS.md "Editor → Shell (smoke)", SPEC-DELTA-2B.md §C8/§F)

    /// Port of the hover-manipulation half of `RunNoteAffordanceProbe`/`VerifyHoverManipulation`
    /// (SPEC §8.4 point 9, SPEC-DELTA-2.md §5 "WPF smoke"): a rectangle's edge is movable and its
    /// corner is resizable **even while a different tool is active**, its interior is not a
    /// handle, hovering never mutates `tool`, and a comment pin has no resize handles. [ТЗ№4 D3]
    /// adds the Comment half: with a pin armed, the band along a frame answers nothing and the badge
    /// of a comment answers the comment. Builds its own off-screen view rather than needing a window.
    @discardableResult
    static func smokeVerifyHoverManipulation(image: CGImage) -> Bool {
        let view = AnnotationCanvasView(frame: NSRect(x: 0, y: 0, width: 480, height: 300))
        let capture = EditorCapture(image: image, sourceImagePath: "")
        let rectangle = EditorAnnotation(
            kind: .rectangle, points: [CGPoint(x: 40, y: 40), CGPoint(x: 200, y: 160)],
            color: EditorTheme.defaultAnnotationColor, thickness: 4)
        let pin = EditorAnnotation(
            kind: .comment, points: [CGPoint(x: 300, y: 60), CGPoint(x: 308, y: 68)],
            color: EditorTheme.defaultAnnotationColor, thickness: 4)
        pin.label = "A1"
        capture.annotations = [rectangle, pin]
        view.capture = capture
        // A tool other than Select/Rectangle: hover manipulation must still work (SPEC §1.4
        // "hover-манипуляция краями при любом инструменте").
        view.tool = .blur
        view.recomputeImageRect()

        let rectangleBounds = view.displayBounds(of: rectangle)
        let edgePoint = CGPoint(x: rectangleBounds.midX, y: rectangleBounds.minY)
        let interiorPoint = CGPoint(x: rectangleBounds.midX, y: rectangleBounds.midY)
        let cornerPoint = CGPoint(x: rectangleBounds.maxX, y: rectangleBounds.maxY)

        guard view.findMoveHandle(edgePoint) === rectangle else { return false }
        guard view.findMoveHandle(interiorPoint) == nil else { return false }

        // The corners belong to the selected mark and to no other: unselected, the frame offers
        // none, and selected it offers the one under the pointer (SPEC-DELTA-5-editor.md §3.3).
        guard view.findResizeHandle(cornerPoint).annotation == nil else { return false }
        view.selectAnnotation(id: rectangle.id)
        let cornerHit = view.findResizeHandle(cornerPoint)
        guard cornerHit.annotation === rectangle, cornerHit.corner == 2 else { return false }

        view.selectAnnotation(id: pin.id)
        guard view.findResizeHandle(view.badgeCenter(of: pin)).annotation == nil else { return false }
        view.selectAnnotation(id: nil)

        // With the Comment tool armed the band along a frame answers the frame, the way it does
        // under every other tool: the order of the press is one for all of them, and a pin goes
        // down on an empty place (SPEC-DELTA-5-editor.md §3.5). The badge answers its comment.
        view.tool = .comment
        guard view.findMoveHandle(edgePoint) === rectangle else { return false }
        guard view.findMoveHandle(view.badgeCenter(of: pin)) === pin else { return false }
        // And an empty place well away from both is nothing to grab, so a new pin lands there.
        guard view.findMoveHandle(CGPoint(x: rectangleBounds.maxX + 60, y: rectangleBounds.maxY + 40)) == nil else {
            return false
        }

        // Hovering never mutates the active tool (only the cursor).
        return view.tool == .comment
    }
}

/// Minimal virtual key-code constants for the codes this view checks directly (`NSEvent.keyCode`
/// is a hardware scan code, not ASCII; tool-letter hotkeys are handled one level up in
/// `OverlayEditorController+Keys` via `charactersIgnoringModifiers`, which does not need this
/// table). CHECK-API: values match the standard ANSI keyboard layout's virtual key codes.
enum Keycode {
    static let delete: UInt16 = 51
    static let forwardDelete: UInt16 = 117
    static let escape: UInt16 = 53
    /// Space: the key that turns a press into a drag of the picture (SPEC-DELTA-4 §4.2).
    static let space: UInt16 = 49
    /// Return (main keyboard) / Enter (numeric keypad) — SPEC-DELTA-2.md §1.3's `keyCode 36/76`.
    static let enter: UInt16 = 36
    static let enterAlternate: UInt16 = 76
}
