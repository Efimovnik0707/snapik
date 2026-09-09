import Foundation

/// Port of `src/SnapBrief.Core/Editing/SessionOperations.cs`.
public enum SessionOperations {
    public static func addCapture(_ session: SnapBriefSession, capture: CaptureItem, nowUtc: Date) throws -> SnapBriefSession {
        var updated = session
        updated.captures.append(capture)
        return try touch(updated, nowUtc)
    }

    public static func removeCapture(_ session: SnapBriefSession, captureId: SBGuid, nowUtc: Date) throws -> SnapBriefSession {
        let index = try indexOf(session.captures, captureId)
        var updated = session
        updated.captures.remove(at: index)
        return try touch(updated, nowUtc)
    }

    public static func moveCapture(
        _ session: SnapBriefSession,
        captureId: SBGuid,
        destinationIndex: Int,
        nowUtc: Date
    ) throws -> SnapBriefSession {
        guard destinationIndex >= 0 && destinationIndex < session.captures.count else {
            throw SnapBriefError.argumentOutOfRange("destinationIndex")
        }

        let sourceIndex = try indexOf(session.captures, captureId)
        if sourceIndex == destinationIndex {
            return session
        }

        var captures = session.captures
        let capture = captures.remove(at: sourceIndex)
        captures.insert(capture, at: destinationIndex)

        var updated = session
        updated.captures = captures
        return try touch(updated, nowUtc)
    }

    public static func updateGlobalNote(_ session: SnapBriefSession, note: String, nowUtc: Date) throws -> SnapBriefSession {
        if session.globalNote == note {
            return session
        }
        var updated = session
        updated.globalNote = note
        return try touch(updated, nowUtc)
    }

    public static func updateCapture(_ session: SnapBriefSession, capture: CaptureItem, nowUtc: Date) throws -> SnapBriefSession {
        let index = try indexOf(session.captures, capture.id)
        if session.captures[index] == capture {
            return session
        }
        var updated = session
        updated.captures[index] = capture
        return try touch(updated, nowUtc)
    }

    private static func touch(_ session: SnapBriefSession, _ nowUtc: Date) throws -> SnapBriefSession {
        var updated = session
        updated.modifiedAtUtc = nowUtc
        updated.revision += 1
        try SessionValidation.validate(updated)
        return updated
    }

    private static func indexOf(_ captures: [CaptureItem], _ captureId: SBGuid) throws -> Int {
        for (index, capture) in captures.enumerated() where capture.id == captureId {
            return index
        }
        throw SnapBriefError.keyNotFound("Capture \(captureId) does not exist in this session.")
    }
}
