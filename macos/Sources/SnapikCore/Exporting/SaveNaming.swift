import Foundation

/// Port of `src/Snapik.App/SaveNaming.cs`.
///
/// What the two save dialogs are named and filtered with. Both rules are pure so they can be tested
/// without a window: the file dialog of a single capture and the package folder picker.
public enum SaveNaming {
    /// How many names with a suffix are tried before the save gives up on the folder.
    public static let nameAttempts = 100

    /// A name nothing is saved under yet: the one that was asked for, or the same name with `-2`,
    /// `-3` … after it. `nil` means every attempt is taken and the user has to pick another folder.
    /// The check is done once, before the first file is copied, so a package never lands half
    /// written next to the files of another one.
    public static func freeName(_ baseName: String, taken: (String) -> Bool) -> String? {
        if !taken(baseName) { return baseName }
        for attempt in 2...nameAttempts {
            let candidate = "\(baseName)-\(attempt)"
            if !taken(candidate) { return candidate }
        }
        return nil
    }

    /// Port of `ImageFilter`, kept verbatim in the Windows shape (`caption (patterns)|patterns|…`)
    /// so both builds answer the same string. Its first line is "all supported", so saving does not
    /// start with a choice of format, and the patterns in it are ordered by the preferred format:
    /// the dialog appends the extension of the first one.
    public static func imageFilter(saveFormat: String, allSupportedCaption: String) -> String {
        let supported = saveFormat == "jpeg" ? "*.jpg;*.jpeg;*.png" : "*.png;*.jpg;*.jpeg"
        return
            "\(allSupportedCaption) (\(supported))|\(supported)|PNG (*.png)|*.png|JPEG (*.jpg;*.jpeg)|*.jpg;*.jpeg"
    }
}
