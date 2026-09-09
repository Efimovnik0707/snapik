// Port of `src/SnapBrief.App/Controls/AnnotationCanvas.cs`, SPEC §6.3 (state + interaction half;
// see `AnnotationCanvasView+Drawing.swift` for `draw(_:)`).
import AppKit
import SnapBriefCore

/// Custom drawing surface for the active capture's annotations (SPEC §6.3). `isFlipped = true` so
/// its coordinate system matches the WPF `Canvas` (top-left origin, Y down) the spec's formulas
/// were written against, and the `IconPath`/IconPath-style geometry used elsewhere in the editor.
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

    var tool: EditorTool = .rectangle
    var activeColor: NSColor = EditorTheme.accent
    var activeThickness: Double = 4
    /// Forced to 0 by the overlay (SPEC §1.3: "холст разметки `AnnotationCanvas` ... с
    /// `ImagePadding = 0`"); left configurable to match the Windows default of 28 for any future
    /// non-overlay host.
    var imagePadding: CGFloat = 0

    private(set) var selectedAnnotation: EditorAnnotation?
    // Setter is internal (not private) so `AnnotationCanvasView+Drawing.swift` can refresh it.
    var imageRect: CGRect = .zero

    var onAnnotationCreated: ((EditorAnnotation) -> Void)?
    var onSelectionChanged: ((EditorAnnotation?) -> Void)?
    var onAnnotationChanged: (() -> Void)?
    var onCropRequested: ((CGRect) -> Void)?

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
        imageRect = EditorGeometry.fitRect(
            imageWidth: Double(capture.image.width), imageHeight: Double(capture.image.height),
            width: Double(bounds.width), height: Double(bounds.height), padding: Double(imagePadding))
    }

    // MARK: - Coordinate mapping

    private func toImage(_ point: CGPoint) -> CGPoint {
        guard let capture, imageRect.width > 0, imageRect.height > 0 else { return .zero }
        return CGPoint(
            x: (point.x - imageRect.minX) * CGFloat(capture.image.width) / imageRect.width,
            y: (point.y - imageRect.minY) * CGFloat(capture.image.height) / imageRect.height)
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
        let point = convert(event.locationInWindow, from: nil)
        guard imageRect.contains(point) else { return }

        let handleHit = findResizeHandle(point)
        if tool == .select || handleHit.annotation != nil {
            let imagePoint = toImage(point)
            let hit = handleHit.annotation ?? hitTestAnnotation(imagePoint)
            select(hit)
            if let hit {
                gestureStart = imagePoint
                originalPoints = hit.points
                originalAdditionalSegments = hit.additionalPathSegments
                originalBounds = EditorGeometry.boundsOf(points: hit.points, additionalSegments: hit.additionalPathSegments)
                resizeCorner = handleHit.corner
                resizing = resizeCorner >= 0
                manipulating = true
                manipulationChanged = false
            }
            return
        }

        let start = toImage(point)
        gestureStart = start
        draft = EditorAnnotation(
            kind: tool,
            points: [start, start],
            color: tool == .conceal ? .black : activeColor,
            thickness: activeThickness)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let capture else { return }

        if manipulating, let selected = selectedAnnotation, let gestureStart {
            let current = clampToImage(toImage(point))
            if resizing {
                // `ResizeGeometry` (Sources/SnapBriefCore/Geometry/ResizeGeometry.swift) is
                // Foundation-only; CG-typed overloads with matching labels live in
                // `Sources/SnapBriefMac/Imaging/GeometryBridging.swift`.
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

        guard let draft, gestureStart != nil else { return }
        let point2 = clampToImage(toImage(point))
        if draft.kind == .pen || draft.kind == .highlight {
            draft.points.append(point2)
        } else if draft.points.count > 1 {
            draft.points[1] = point2
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if manipulating {
            manipulating = false
            resizing = false
            gestureStart = nil
            originalPoints = []
            originalAdditionalSegments = []
            if manipulationChanged { onAnnotationChanged?() }
            needsDisplay = true
            return
        }

        guard let draft else { return }
        if EditorGeometry.gestureHasSize(kind: draft.kind, points: draft.points) {
            if draft.kind == .crop {
                onCropRequested?(EditorGeometry.boundsOf(points: draft.points))
            } else {
                draft.label = ""
                capture?.annotations.append(draft)
                select(draft)
                onAnnotationCreated?(draft)
            }
        }
        self.draft = nil
        gestureStart = nil
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        guard draft == nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        let handle = findResizeHandle(point)
        if handle.corner < 0 {
            (tool == .select ? NSCursor.arrow : NSCursor.crosshair).set()
        } else {
            // CHECK-API: AppKit has no public diagonal (NWSE/NESW) resize cursor, unlike WPF's
            // `Cursors.SizeNWSE`/`SizeNESW` (SPEC §1.6). `.crosshair` is used for both corner
            // families as the closest stock cursor; revisit with a custom `NSCursor` image if
            // exact diagonal cursors are required later.
            NSCursor.crosshair.set()
        }
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
        case Keycode.escape:
            if draft != nil {
                draft = nil
                gestureStart = nil
                needsDisplay = true
            } else {
                super.keyDown(with: event)
            }
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: - Hit testing (SPEC §6.3)

    private func findResizeHandle(_ displayPoint: CGPoint) -> (annotation: EditorAnnotation?, corner: Int) {
        guard let capture else { return (nil, -1) }
        if let selected = selectedAnnotation {
            let corner = ResizeGeometry.hitCorner(bounds: displayBounds(of: selected), point: displayPoint, radius: 10)
            if corner >= 0 { return (selected, corner) }
        }
        for annotation in capture.annotations.reversed() {
            let corner = ResizeGeometry.hitCorner(bounds: displayBounds(of: annotation), point: displayPoint, radius: 10)
            if corner >= 0 { return (annotation, corner) }
        }
        return (nil, -1)
    }

    private func hitTestAnnotation(_ imagePoint: CGPoint) -> EditorAnnotation? {
        guard let capture else { return nil }
        for annotation in capture.annotations.reversed() {
            let bounds = EditorGeometry.boundsOf(points: annotation.points, additionalSegments: annotation.additionalPathSegments)
            let inflated = EditorGeometry.hitTestInflatedBounds(bounds, thickness: annotation.thickness)
            if inflated.contains(imagePoint) { return annotation }
        }
        return nil
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
}
