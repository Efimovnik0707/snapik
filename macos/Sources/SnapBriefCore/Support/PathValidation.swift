import Foundation

/// Port of the relative-path safety checks inlined in `SessionValidation.Validate`
/// (`src/SnapBrief.Core/Models/SessionValidation.cs`) and `CaptureCropper.ValidateCrop`
/// (`src/SnapBrief.Core/Editing/CaptureCropper.cs`):
/// `Path.IsPathRooted(path) || path.Split(DirectorySeparatorChar, AltDirectorySeparatorChar).Contains("..")`.
public enum RelativePathValidation {
    /// Returns `false` for empty paths, absolute/rooted paths (POSIX `/...`, Windows `C:\...`,
    /// `\...`, or UNC `\\...`), and any path containing a `".."` path component.
    public static func isRelativeAndSafe(_ path: String) -> Bool {
        if path.isEmpty {
            return false
        }
        if path.hasPrefix("/") || path.hasPrefix("\\") {
            return false
        }
        let characters = Array(path)
        if characters.count >= 2, characters[1] == ":" {
            // Windows drive-letter root, e.g. "C:\..." or "C:/...".
            return false
        }

        let separators = CharacterSet(charactersIn: "/\\")
        let components = path.components(separatedBy: separators)
        if components.contains("..") {
            return false
        }
        return true
    }
}
