// macOS-adapted overrides for the UI strings whose Windows wording names Windows itself,
// SPEC §1.20 "Три строки требуют адаптации на macOS".
import Foundation
import SnapikCore

/// Wraps `UiLanguage.text(_:language:)`, substituting the macOS-specific strings before delegating
/// everything else to Core's dictionary verbatim. The row that carried "(Ctrl+S)" left with the pair
/// behind it (SPEC-DELTA-3 §3.3): the shortcut is appended where the tooltip is built, so the shared
/// table holds "Сохранить на компьютер" alone, as Windows does.
enum MacUiText {
    private static let overrides: [String: (ru: String, en: String)] = [
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
