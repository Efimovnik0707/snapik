// macOS-adapted overrides for the 3 UI strings that need a different wording than Windows,
// SPEC §1.20 "Три строки требуют адаптации на macOS".
import Foundation
import SnapBriefCore

/// Wraps `UiLanguage.text(_:language:)`, substituting the three macOS-specific strings before
/// delegating everything else to Core's dictionary verbatim.
enum MacUiText {
    private static let overrides: [String: (ru: String, en: String)] = [
        "Сохранить на компьютер (Ctrl+S)": ("Сохранить на компьютер (Cmd+S)", "Save to computer (Cmd+S)"),
        "Свернуть в трей": ("Свернуть в меню-бар", "Hide to menu bar"),
        "Запускать с Windows": ("Запускать при входе", "Start at login"),
    ]

    static func text(_ value: String, language: String) -> String {
        if let override = overrides[value] {
            return language == "en" ? override.en : override.ru
        }
        return UiLanguage.text(value, language: language)
    }
}
