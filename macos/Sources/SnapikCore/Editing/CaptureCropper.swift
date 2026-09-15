import Foundation

/// Port of `NormalizedRect(double X, double Y, double Width, double Height)`
/// from `src/Snapik.Core/Editing/CaptureCropper.cs`.
public struct NormalizedRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(_ x: Double, _ y: Double, _ width: Double, _ height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var left: Double { x }
    public var top: Double { y }
    public var right: Double { x + width }
    public var bottom: Double { y + height }
}

/// Port of `CropResult`.
public struct CropResult: Sendable {
    public let previousCapture: CaptureItem
    public let croppedCapture: CaptureItem
    public let removedAnnotationIds: [SBGuid]
}

/// Port of `src/Snapik.Core/Editing/CaptureCropper.cs`.
public enum CaptureCropper {
    private static let epsilon = 1e-12

    public static func crop(
        source: CaptureItem,
        cropBounds: NormalizedRect,
        croppedSourceImagePath: String,
        croppedPixelWidth: Int,
        croppedPixelHeight: Int
    ) throws -> CropResult {
        try validateCrop(
            cropBounds,
            sourcePath: croppedSourceImagePath,
            pixelWidth: croppedPixelWidth,
            pixelHeight: croppedPixelHeight)

        var retained: [AnnotationItem] = []
        var removed: [SBGuid] = []

        for annotation in source.annotations {
            if annotation.kind == .freehand || annotation.kind == .highlight {
                let croppedSegments = cropPolyline(annotation.getPathSegments(), cropBounds)
                if croppedSegments.isEmpty {
                    removed.append(annotation.id)
                } else {
                    var updated = annotation
                    updated.points = croppedSegments[0]
                    updated.pathSegments = croppedSegments.count > 1 ? croppedSegments : []
                    retained.append(updated)
                }
                continue
            }

            let croppedPoints: [NormalizedPoint]
            switch annotation.kind {
            case .arrow:
                croppedPoints = cropLine(annotation.points, cropBounds)
            case .rectangle, .text, .redaction, .blur, .comment:
                croppedPoints = cropBox(annotation.points, cropBounds)
            case .highlight, .freehand:
                croppedPoints = []
            }

            if croppedPoints.isEmpty {
                removed.append(annotation.id)
            } else {
                var updated = annotation
                updated.points = croppedPoints
                retained.append(updated)
            }
        }

        // Port of `:70-74` (SPEC-DELTA-2B §B): a linked comment whose parent annotation was
        // removed by the crop loses the link but keeps its own note/geometry.
        let retainedIds = Set(retained.map(\.id))
        for index in retained.indices where retained[index].parentAnnotationId.map({ !retainedIds.contains($0) }) == true {
            retained[index].parentAnnotationId = nil
        }

        var cropped = source
        cropped.sourceImagePath = croppedSourceImagePath
        cropped.pixelWidth = croppedPixelWidth
        cropped.pixelHeight = croppedPixelHeight
        cropped.annotations = retained

        return CropResult(previousCapture: source, croppedCapture: cropped, removedAnnotationIds: removed)
    }

    private static func cropLine(_ points: [NormalizedPoint], _ crop: NormalizedRect) -> [NormalizedPoint] {
        guard points.count >= 2, let clipped = tryClipSegment(points[0], points[1], crop),
            distance(clipped.0, clipped.1) > epsilon
        else {
            return []
        }
        return [mapToCrop(clipped.0, crop), mapToCrop(clipped.1, crop)]
    }

    private static func cropBox(_ points: [NormalizedPoint], _ crop: NormalizedRect) -> [NormalizedPoint] {
        guard points.count >= 2 else { return [] }

        let left = max(min(points[0].x, points[1].x), crop.left)
        let top = max(min(points[0].y, points[1].y), crop.top)
        let right = min(max(points[0].x, points[1].x), crop.right)
        let bottom = min(max(points[0].y, points[1].y), crop.bottom)
        if right - left <= epsilon || bottom - top <= epsilon {
            return []
        }

        return [
            mapToCrop(NormalizedPoint(left, top), crop),
            mapToCrop(NormalizedPoint(right, bottom), crop),
        ]
    }

    private static func cropPolyline(
        _ paths: [[NormalizedPoint]],
        _ crop: NormalizedRect
    ) -> [[NormalizedPoint]] {
        var runs: [[NormalizedPoint]] = []

        for points in paths {
            var current: [NormalizedPoint]?
            for index in stride(from: 1, to: points.count, by: 1) {
                guard let clipped = tryClipSegment(points[index - 1], points[index], crop),
                    distance(clipped.0, clipped.1) > epsilon
                else {
                    finishRun(&current, &runs)
                    continue
                }
                let (start, end) = clipped

                if current == nil || distance(current!.last!, start) > epsilon {
                    finishRun(&current, &runs)
                    current = [start]
                }
                if distance(current!.last!, end) > epsilon {
                    current!.append(end)
                }
            }
            finishRun(&current, &runs)
        }

        return runs
            .filter { $0.count >= 2 }
            .filter { polylineLength($0) > epsilon }
            .map { run in run.map { mapToCrop($0, crop) } }
    }

    private static func finishRun(_ current: inout [NormalizedPoint]?, _ runs: inout [[NormalizedPoint]]) {
        if let run = current, run.count >= 2 {
            runs.append(run)
        }
        current = nil
    }

    private static func tryClipSegment(
        _ start: NormalizedPoint,
        _ end: NormalizedPoint,
        _ crop: NormalizedRect
    ) -> (NormalizedPoint, NormalizedPoint)? {
        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        var minimum = 0.0
        var maximum = 1.0

        guard clipTest(-deltaX, start.x - crop.left, &minimum, &maximum),
            clipTest(deltaX, crop.right - start.x, &minimum, &maximum),
            clipTest(-deltaY, start.y - crop.top, &minimum, &maximum),
            clipTest(deltaY, crop.bottom - start.y, &minimum, &maximum)
        else {
            return nil
        }

        let clippedStart = NormalizedPoint(start.x + minimum * deltaX, start.y + minimum * deltaY)
        let clippedEnd = NormalizedPoint(start.x + maximum * deltaX, start.y + maximum * deltaY)
        return (clippedStart, clippedEnd)
    }

    private static func clipTest(
        _ denominator: Double,
        _ numerator: Double,
        _ minimum: inout Double,
        _ maximum: inout Double
    ) -> Bool {
        if abs(denominator) <= epsilon {
            return numerator >= 0
        }

        let ratio = numerator / denominator
        if denominator < 0 {
            if ratio > maximum { return false }
            if ratio > minimum { minimum = ratio }
        } else {
            if ratio < minimum { return false }
            if ratio < maximum { maximum = ratio }
        }
        return true
    }

    private static func mapToCrop(_ point: NormalizedPoint, _ crop: NormalizedRect) -> NormalizedPoint {
        NormalizedPoint(
            min(max((point.x - crop.left) / crop.width, 0), 1),
            min(max((point.y - crop.top) / crop.height, 0), 1))
    }

    private static func polylineLength(_ points: [NormalizedPoint]) -> Double {
        var length = 0.0
        for index in stride(from: 1, to: points.count, by: 1) {
            length += distance(points[index - 1], points[index])
        }
        return length
    }

    private static func distance(_ first: NormalizedPoint, _ second: NormalizedPoint) -> Double {
        let x = second.x - first.x
        let y = second.y - first.y
        return (x * x + y * y).squareRoot()
    }

    private static func validateCrop(
        _ crop: NormalizedRect,
        sourcePath: String,
        pixelWidth: Int,
        pixelHeight: Int
    ) throws {
        if !crop.x.isFinite || !crop.y.isFinite || !crop.width.isFinite || !crop.height.isFinite
            || crop.x < 0 || crop.y < 0 || crop.width <= 0 || crop.height <= 0
            || crop.right > 1 || crop.bottom > 1
        {
            throw SnapikError.argumentOutOfRange(
                "crop: Crop bounds must be a positive rectangle within normalized [0, 1] image space.")
        }

        if sourcePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Port of `ArgumentException.ThrowIfNullOrWhiteSpace`: `sourcePath` is a non-optional
            // Swift `String`, so only the empty/whitespace case (ArgumentException) is reachable
            // here; the null case (ArgumentNullException) cannot occur.
            throw SnapikError.argument("sourcePath must not be empty or whitespace.")
        }
        if !RelativePathValidation.isRelativeAndSafe(sourcePath) {
            throw SnapikError.argument(
                "sourcePath: Cropped source image path must remain relative to the session directory.")
        }
        if pixelWidth <= 0 {
            throw SnapikError.argumentOutOfRange("pixelWidth")
        }
        if pixelHeight <= 0 {
            throw SnapikError.argumentOutOfRange("pixelHeight")
        }
    }
}
