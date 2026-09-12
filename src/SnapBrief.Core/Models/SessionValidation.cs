namespace SnapBrief.Core.Models;

public static class SessionValidation
{
    public static void Validate(SnapBriefSession session)
    {
        ArgumentNullException.ThrowIfNull(session);

        if (session.Id == Guid.Empty)
        {
            throw new InvalidDataException("Session ID cannot be empty.");
        }

        if (session.SchemaVersion != SnapBriefSession.CurrentSchemaVersion)
        {
            throw new InvalidDataException($"Unsupported session schema version: {session.SchemaVersion}.");
        }

        if (session.Revision < 0)
        {
            throw new InvalidDataException("Session revision cannot be negative.");
        }

        var captureIds = new HashSet<Guid>();
        var annotationIds = new HashSet<Guid>();

        foreach (var capture in session.Captures)
        {
            if (capture.Id == Guid.Empty || !captureIds.Add(capture.Id))
            {
                throw new InvalidDataException("Capture IDs must be non-empty and unique.");
            }

            if (Path.IsPathRooted(capture.SourceImagePath) ||
                capture.SourceImagePath.Split(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar).Contains(".."))
            {
                throw new InvalidDataException("Capture image paths must be relative and cannot escape the session directory.");
            }

            if (capture.PixelWidth <= 0 || capture.PixelHeight <= 0 || capture.DpiX <= 0 || capture.DpiY <= 0)
            {
                throw new InvalidDataException("Capture dimensions and DPI must be positive.");
            }

            foreach (var annotation in capture.Annotations)
            {
                if (annotation.Id == Guid.Empty || !annotationIds.Add(annotation.Id))
                {
                    throw new InvalidDataException("Annotation IDs must be non-empty and unique within a session.");
                }

                if (annotation.Thickness <= 0 || annotation.Points.IsDefaultOrEmpty)
                {
                    throw new InvalidDataException("Annotations require positive thickness and geometry.");
                }

                if (annotation.Points.Any(point =>
                        !double.IsFinite(point.X) || !double.IsFinite(point.Y) ||
                        point.X is < 0 or > 1 || point.Y is < 0 or > 1))
                {
                    throw new InvalidDataException("Annotation coordinates must be normalized to the [0, 1] image space.");
                }

                // The badge offset is a shift, not a coordinate: it may be negative and it may point
                // outside the image, so only a finite number is required of it.
                if (annotation.NoteOffset is { } noteOffset &&
                    (!double.IsFinite(noteOffset.X) || !double.IsFinite(noteOffset.Y)))
                {
                    throw new InvalidDataException("The note offset of an annotation must be a finite shift.");
                }

                if (!annotation.PathSegments.IsDefaultOrEmpty)
                {
                    if (annotation.Kind is not (AnnotationKind.Freehand or AnnotationKind.Highlight) ||
                        annotation.PathSegments.Any(segment => segment.Length < 2))
                    {
                        throw new InvalidDataException("Only freehand and highlight annotations may contain multi-segment paths, and every segment requires at least two points.");
                    }
                    if (annotation.PathSegments.SelectMany(segment => segment).Any(point =>
                            !double.IsFinite(point.X) || !double.IsFinite(point.Y) ||
                            point.X is < 0 or > 1 || point.Y is < 0 or > 1))
                    {
                        throw new InvalidDataException("Annotation path-segment coordinates must be normalized to the [0, 1] image space.");
                    }
                }
            }
        }
    }
}
