// Port of `src/Snapik.App/EditorModels.cs`, SPEC §2.4, §1.3 (tool table), §1.5 (history unit)
import AppKit
import SnapikCore

/// Port of `EditorTool` (`EditorModels.cs:17-28`). Raw values are the single-letter hotkeys used
/// by `AnnotationCanvasView`/`OverlayEditorController+Keys` (SPEC §7.5/§7.6): `V R A B C P H T X`.
enum EditorTool: String {
    case select = "V"
    case rectangle = "R"
    case arrow = "A"
    case pen = "P"
    case highlight = "H"
    case text = "T"
    case conceal = "X"
    case blur = "B"
    case crop = "C"
    /// Port of `EditorTool.Comment` (SPEC-DELTA-2.md §1.3, SPEC-DELTA-2B.md §C2). One-shot: a
    /// single click places a pin and returns to `.select` (`OverlayEditorController+Chips.swift`).
    case comment = "N"
    /// Port of `EditorTool.Eraser` (`EditorModels.cs:29`, SPEC-DELTA-3 §1.4 E-5): a mode of the
    /// panel and never the kind of a mark. The eraser removes what it is clicked on and nothing
    /// carries this value into a session.
    case eraser = "E"

    /// Port of `IsDrawingTool` (`AnnotationCanvas.cs:355`): everything but Select and the eraser
    /// puts something on the capture, and shows the crosshair over it.
    var isDrawing: Bool { self != .select && self != .eraser }
}

/// Port of `AnnotationItem` (`EditorModels.cs:30-131`). A plain reference type (no
/// `INotifyPropertyChanged` binding machinery — the AppKit views that own one of these call
/// `needsDisplay = true` / the relevant reposition helpers directly after mutating it).
///
/// Points are stored in **image pixel space** (not normalized), matching the Windows `Point`
/// convention; conversion to/from Core's normalized `[0,1]` space happens only in `toCore`/
/// `fromCore` (SPEC §2.4).
final class EditorAnnotation {
    let id: SBGuid
    var kind: EditorTool
    var points: [CGPoint]
    var additionalPathSegments: [[CGPoint]]
    var color: NSColor
    var thickness: Double
    var label: String = ""
    var note: String = ""
    var text: String
    /// Port of `AnnotationItem.ParentAnnotationId` (SPEC-DELTA-2.md §2.1). `nil` = comment attached
    /// to the whole capture ("к снимку"); non-nil = attached to that annotation ("к отметке").
    var parentAnnotationId: SBGuid?
    /// Port of `AnnotationItem.ArrowStyle` (SPEC-DELTA-2.md §2.1): `"straight"`/`"curved"`/
    /// `"bold"`/`"wide"`. Meaningless for non-arrow kinds, always carried along regardless.
    var arrowStyle: String
    /// Port of `AnnotationItem.NoteOffset` (`EditorModels.cs:50`): the shift of the numbered badge
    /// from its automatic place, **in image pixels**; `nil` is automatic. A plain property on
    /// purpose: the drag of a note pill must not push a history entry per pixel.
    var noteOffset: CGPoint?
    /// Port of `Shape`/`Fill`/`FillColor`/`LineStyle`/`FontSize` (`EditorModels.cs:52-68`).
    var shape: AnnotationShape
    var fill: AnnotationFill
    /// The colour inside the box; `nil` means "the colour of the outline", which is how every mark
    /// drawn before the fill had a colour of its own still reads.
    var fillColor: NSColor?
    var lineStyle: AnnotationLineStyle
    /// The size a caption is typed in, in the pixels of the capture.
    var fontSize: Double

    init(
        id: SBGuid = SBGuid(),
        kind: EditorTool,
        points: [CGPoint],
        additionalPathSegments: [[CGPoint]] = [],
        color: NSColor,
        thickness: Double,
        text: String? = nil,
        note: String = "",
        parentAnnotationId: SBGuid? = nil,
        arrowStyle: String = "straight",
        noteOffset: CGPoint? = nil,
        shape: AnnotationShape = .rectangle,
        fill: AnnotationFill = .none,
        fillColor: NSColor? = nil,
        lineStyle: AnnotationLineStyle = .solid,
        fontSize: Double = TextMarkMetrics.defaultFontSize
    ) {
        self.id = id
        self.kind = kind
        self.points = points
        self.additionalPathSegments = additionalPathSegments
        self.color = color
        self.thickness = thickness
        self.text = text ?? ""
        self.note = note
        self.parentAnnotationId = parentAnnotationId
        self.arrowStyle = arrowStyle
        self.noteOffset = noteOffset
        self.shape = shape
        self.fill = fill
        self.fillColor = fillColor
        self.lineStyle = lineStyle
        self.fontSize = fontSize
    }

    /// Port of `AnnotationItem.Clone()` (`:62-74`). Identity (`id`) is preserved, matching the
    /// Windows deep-clone used for undo/redo snapshots.
    func clone() -> EditorAnnotation {
        let copy = EditorAnnotation(
            id: id,
            kind: kind,
            points: points,
            additionalPathSegments: additionalPathSegments,
            color: color,
            thickness: thickness,
            text: text,
            note: note,
            parentAnnotationId: parentAnnotationId,
            arrowStyle: arrowStyle,
            noteOffset: noteOffset,
            shape: shape,
            fill: fill,
            fillColor: fillColor,
            lineStyle: lineStyle,
            fontSize: fontSize)
        // The letter in the badge is state of the view and not of the model, but an undo that gave
        // it back blank would redraw every badge as a placeholder until the next `refreshLabels`.
        copy.label = label
        return copy
    }

    /// Port of `EditorTool` -> `AnnotationKind` (SPEC §2.4 table; `EditorModels.cs:78-88`).
    /// Select/Crop fall back to `.rectangle`, matching the C# `_ => AnnotationKind.Rectangle`.
    var coreKind: AnnotationKind { Self.coreKind(of: kind) }

    /// The same mapping without a mark to read it from: the panel asks it of the tool in the hand.
    static func coreKind(of tool: EditorTool) -> AnnotationKind {
        switch tool {
        case .arrow: return .arrow
        case .rectangle: return .rectangle
        case .pen: return .freehand
        case .highlight: return .highlight
        case .text: return .text
        case .conceal: return .redaction
        case .blur: return .blur
        case .comment: return .comment
        case .select, .crop, .eraser: return .rectangle
        }
    }

    /// Port of `ToCore` (`:76-100`, SPEC §2.4): points divided by image size and clamped to
    /// `[0,1]`; color formatted `#AARRGGBB` uppercase; `pathSegments` only populated when there
    /// are additional segments, with the primary `points` set included first.
    func toCore(imageWidth: Int, imageHeight: Int) -> AnnotationItem {
        let width = max(1, imageWidth)
        let height = max(1, imageHeight)
        func normalize(_ p: CGPoint) -> NormalizedPoint {
            NormalizedPoint(
                min(max(Double(p.x) / Double(width), 0), 1),
                min(max(Double(p.y) / Double(height), 0), 1))
        }

        let normalizedPoints = points.map(normalize)
        var pathSegments: [[NormalizedPoint]] = []
        if !additionalPathSegments.isEmpty {
            pathSegments.append(normalizedPoints)
            pathSegments.append(contentsOf: additionalPathSegments.map { $0.map(normalize) })
        }

        return AnnotationItem(
            id: id,
            kind: coreKind,
            points: normalizedPoints,
            strokeColor: color.hexARGB,
            thickness: thickness,
            text: text,
            note: note,
            pathSegments: pathSegments,
            parentAnnotationId: parentAnnotationId,
            arrowStyle: arrowStyle,
            // A shift, not a coordinate: it is divided by the size of the image and never clamped
            // into `[0,1]` (SPEC-DELTA-3 §2.1).
            noteOffset: noteOffset.map { NormalizedPoint(Double($0.x) / Double(width), Double($0.y) / Double(height)) },
            shape: shape,
            fill: fill,
            lineStyle: lineStyle,
            fillColor: fillColor?.hexARGB,
            // [ТЗ№4 D1] The switch is gone from the panel and the flag with it: `hasOutline` is
            // read and never written any more (SPEC-DELTA-4 §2.2).
            fontSize: fontSize)
    }

    /// Port of `AnnotationItem.FromCore` (`:102-127`).
    static func fromCore(_ item: AnnotationItem, imageWidth: Int, imageHeight: Int) -> EditorAnnotation {
        let width = Double(imageWidth)
        let height = Double(imageHeight)
        func denormalize(_ p: NormalizedPoint) -> CGPoint { CGPoint(x: p.x * width, y: p.y * height) }

        let segments = item.getPathSegments().map { segment in segment.map(denormalize) }
        let points = segments.first ?? item.points.map(denormalize)
        let additional = segments.count > 1 ? Array(segments.dropFirst()) : []

        let kind: EditorTool
        switch item.kind {
        case .arrow: kind = .arrow
        case .rectangle: kind = .rectangle
        case .freehand: kind = .pen
        case .highlight: kind = .highlight
        case .text: kind = .text
        // A session written by a build that still had the conceal tool carries "redaction" marks.
        // The tool is gone; what it drew is a region with a solid black fill, and it is written back
        // in that shape the next time the session is saved (SPEC-DELTA-3 §2.1).
        case .redaction: kind = .rectangle
        case .blur: kind = .blur
        case .comment: kind = .comment
        }
        let redaction = item.kind == .redaction
        // [ТЗ№4 D1] `hasOutline: false` on a boxed mark reads as "a solid fill of one colour"; the
        // field is never written again (SPEC-DELTA-4 §2.2). The colour of that fill is its own if
        // the file carries one, the colour of the stroke otherwise.
        let solidWithoutOutline = item.kind == .rectangle && item.legacyHasOutline == false
        let strokeColor = NSColor(argbHex: item.strokeColor)

        return EditorAnnotation(
            id: item.id,
            kind: kind,
            points: points,
            additionalPathSegments: additional,
            color: strokeColor,
            thickness: item.thickness,
            text: item.text,
            note: item.note,
            parentAnnotationId: item.parentAnnotationId,
            arrowStyle: item.arrowStyle,
            noteOffset: item.noteOffset.map { CGPoint(x: $0.x * width, y: $0.y * height) },
            shape: item.shape,
            fill: redaction || solidWithoutOutline ? .solid : item.fill,
            fillColor: redaction
                ? NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
                : (EditorAppearance.parseFillColor(item.fillColor) ?? (solidWithoutOutline ? strokeColor : nil)),
            lineStyle: item.lineStyle,
            fontSize: item.fontSize)
    }
}

/// Port of `CaptureItem` (`EditorModels.cs:133-198`).
final class EditorCapture {
    let id: SBGuid
    var image: CGImage
    var sourceImagePath: String
    var displayLabel: String = "A"
    /// Port of `CaptureItem.Title` (`EditorModels.cs:133-198`). The name of the file an imported
    /// capture came from, which the caption of the editor says out loud (SPEC-DELTA-4 §3.5); it is
    /// threaded through `toCore`/`fromCore` so a reopened capture's title round-trips instead of
    /// being silently blanked on every commit (finding R7).
    var title: String = ""
    /// Port of `CaptureItem.Kind`/`MonitorCount` (SPEC-DELTA-4 §2.1, E-7): what the capture is, and
    /// how many monitors a whole-screen one covered. The editor reads both for its caption and
    /// carries them back untouched — the strip is what sets them.
    var kind: CaptureKind = .region
    var monitorCount = 0
    var note: String = ""
    var annotations: [EditorAnnotation] = []
    var dpiX: Double
    var dpiY: Double

    init(id: SBGuid = SBGuid(), image: CGImage, sourceImagePath: String, dpiX: Double = 96, dpiY: Double = 96) {
        self.id = id
        self.image = image
        self.sourceImagePath = sourceImagePath
        self.dpiX = dpiX
        self.dpiY = dpiY
    }

    /// Port of `NoteCount` (`:156`): annotations with a non-blank note, plus one if the capture's
    /// own note is non-blank.
    var noteCount: Int {
        annotations.filter { !$0.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
            + (note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1)
    }

    /// Port of `CaptureItem.Snapshot()` (`:158`) — used as the undo/redo history unit (SPEC §1.5).
    func snapshot() -> CaptureSnapshot {
        CaptureSnapshot(
            captureId: id,
            image: image,
            sourceImagePath: sourceImagePath,
            displayLabel: displayLabel,
            note: note,
            annotations: annotations.map { $0.clone() })
    }

    /// Port of `CaptureItem.Restore(CaptureSnapshot)` (`:186-194`).
    func restore(_ snapshot: CaptureSnapshot) {
        image = snapshot.image
        sourceImagePath = snapshot.sourceImagePath
        displayLabel = snapshot.displayLabel
        note = snapshot.note
        annotations = snapshot.annotations.map { $0.clone() }
    }

    /// Port of `CaptureItem.ToCore()` (`:167-176`). `title` round-trips whatever `fromCore` last
    /// set (finding R7) rather than always writing `""`.
    func toCore() -> CaptureItem {
        CaptureItem(
            id: id,
            sourceImagePath: sourceImagePath,
            pixelWidth: image.width,
            pixelHeight: image.height,
            dpiX: dpiX > 0 ? dpiX : 96,
            dpiY: dpiY > 0 ? dpiY : 96,
            title: title,
            note: note,
            annotations: annotations.map { $0.toCore(imageWidth: image.width, imageHeight: image.height) },
            kind: kind,
            monitorCount: monitorCount)
    }

    /// Port of `CaptureItem.FromCore(CoreCapture, BitmapSource)` (`:178-184`).
    static func fromCore(_ item: CaptureItem, image: CGImage) -> EditorCapture {
        let capture = EditorCapture(id: item.id, image: image, sourceImagePath: item.sourceImagePath, dpiX: item.dpiX, dpiY: item.dpiY)
        capture.title = item.title
        capture.kind = item.kind
        capture.monitorCount = item.monitorCount
        capture.note = item.note
        capture.annotations = item.annotations.map { EditorAnnotation.fromCore($0, imageWidth: image.width, imageHeight: image.height) }
        return capture
    }
}

/// Port of `CaptureSnapshot` (`EditorModels.cs:200`) — the undo/redo unit for the whole capture.
struct CaptureSnapshot {
    let captureId: SBGuid
    let image: CGImage
    let sourceImagePath: String
    let displayLabel: String
    let note: String
    let annotations: [EditorAnnotation]
}

/// Port of `OverlaySnapshot` (`OverlayEditorWindow.xaml.cs:794`) — SPEC §1.5: the full local
/// undo/redo unit, one level above `CaptureSnapshot` (also captures the crop rect and which chips
/// were open).
struct OverlaySnapshot {
    let capture: CaptureSnapshot
    /// Crop rect in the active editing window's local point space (top-left origin, Y down —
    /// see `EditorGeometry`).
    let cropRect: CGRect
    let visibleChipIds: Set<SBGuid>
}

// MARK: - Color <-> `#AARRGGBB` hex (SPEC §2.4)

extension NSColor {
    /// Port of `$"#{Color.A:X2}{Color.R:X2}{Color.G:X2}{Color.B:X2}"`.
    var hexARGB: String {
        guard let rgb = usingColorSpace(.deviceRGB) else { return "#FF000000" }
        let a = UInt8((rgb.alphaComponent * 255).rounded())
        let r = UInt8((rgb.redComponent * 255).rounded())
        let g = UInt8((rgb.greenComponent * 255).rounded())
        let b = UInt8((rgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X%02X", a, r, g, b)
    }

    /// Port of `$"#{Color.R:X2}{Color.G:X2}{Color.B:X2}"` (`OverlayEditorWindow.Appearance.cs:55`)
    /// — the appearance popover's hex field display format: RGB only, no alpha, unlike
    /// `hexARGB` (the annotation-storage format).
    var hexRGB: String {
        guard let rgb = usingColorSpace(.deviceRGB) else { return "#000000" }
        let r = UInt8((rgb.redComponent * 255).rounded())
        let g = UInt8((rgb.greenComponent * 255).rounded())
        let b = UInt8((rgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// Port of `(Color)ColorConverter.ConvertFromString(item.StrokeColor)` for the `#AARRGGBB`
    /// format this app always writes. Falls back to opaque black on malformed input.
    convenience init(argbHex: String) {
        var value: UInt64 = 0
        let hexString = argbHex.hasPrefix("#") ? String(argbHex.dropFirst()) : argbHex
        Scanner(string: hexString).scanHexInt64(&value)
        guard hexString.count == 8 else {
            self.init(srgbRed: 0, green: 0, blue: 0, alpha: 1)
            return
        }
        let a = CGFloat((value & 0xFF00_0000) >> 24) / 255.0
        let r = CGFloat((value & 0x00FF_0000) >> 16) / 255.0
        let g = CGFloat((value & 0x0000_FF00) >> 8) / 255.0
        let b = CGFloat(value & 0x0000_00FF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: a)
    }
}
