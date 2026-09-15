import Foundation

/// Port of `src/Snapik.Core/Models/SessionValidation.cs`.
public enum SessionValidation {
    public static func validate(_ session: SnapikSession) throws {
        if session.id == SBGuid.empty {
            throw SnapikError.invalidData("Session ID cannot be empty.")
        }
        if session.schemaVersion != SnapikSession.currentSchemaVersion {
            throw SnapikError.invalidData("Unsupported session schema version: \(session.schemaVersion).")
        }
        if session.revision < 0 {
            throw SnapikError.invalidData("Session revision cannot be negative.")
        }

        var captureIds = Set<SBGuid>()
        var annotationIds = Set<SBGuid>()

        for capture in session.captures {
            if capture.id == SBGuid.empty || captureIds.contains(capture.id) {
                throw SnapikError.invalidData("Capture IDs must be non-empty and unique.")
            }
            captureIds.insert(capture.id)

            if !RelativePathValidation.isRelativeAndSafe(capture.sourceImagePath) {
                throw SnapikError.invalidData(
                    "Capture image paths must be relative and cannot escape the session directory.")
            }

            if capture.pixelWidth <= 0 || capture.pixelHeight <= 0 || capture.dpiX <= 0 || capture.dpiY <= 0 {
                throw SnapikError.invalidData("Capture dimensions and DPI must be positive.")
            }

            for annotation in capture.annotations {
                if annotation.id == SBGuid.empty || annotationIds.contains(annotation.id) {
                    throw SnapikError.invalidData(
                        "Annotation IDs must be non-empty and unique within a session.")
                }
                annotationIds.insert(annotation.id)

                if annotation.thickness <= 0 || annotation.points.isEmpty {
                    throw SnapikError.invalidData("Annotations require positive thickness and geometry.")
                }

                if annotation.points.contains(where: { !isNormalized($0) }) {
                    throw SnapikError.invalidData(
                        "Annotation coordinates must be normalized to the [0, 1] image space.")
                }

                if !annotation.pathSegments.isEmpty {
                    let kindAllowsSegments = annotation.kind == .freehand || annotation.kind == .highlight
                    let everySegmentHasTwoPoints = annotation.pathSegments.allSatisfy { $0.count >= 2 }
                    if !kindAllowsSegments || !everySegmentHasTwoPoints {
                        throw SnapikError.invalidData(
                            "Only freehand and highlight annotations may contain multi-segment paths, and every segment requires at least two points.")
                    }
                    if annotation.pathSegments.contains(where: { segment in segment.contains { !isNormalized($0) } }) {
                        throw SnapikError.invalidData(
                            "Annotation path-segment coordinates must be normalized to the [0, 1] image space.")
                    }
                }
            }
        }
    }

    private static func isNormalized(_ point: NormalizedPoint) -> Bool {
        point.x.isFinite && point.y.isFinite && point.x >= 0 && point.x <= 1 && point.y >= 0 && point.y <= 1
    }
}
