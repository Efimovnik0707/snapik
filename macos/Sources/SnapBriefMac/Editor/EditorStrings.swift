// Port of literal RU strings from OverlayEditorWindow.xaml / .xaml.cs / CaptureOverlay.xaml,
// routed through `MacUiText.text(_:language:)` (which itself falls back to Core's
// `UiLanguage.text(_:language:)`), SPEC §1.20, §6.1-6.3.
import Foundation
import SnapBriefCore

/// Every user-facing string the editor shows, as the exact Russian source text used by
/// `UiLanguage.text(_:language:)` (mirrors how the Windows XAML hardcodes Russian literals that
/// `UiLanguage.Apply` translates by walking the tree; there is no tree walker on macOS, so each
/// call site here routes explicitly through `UiLanguage.text`). Unknown keys simply return
/// themselves (SPEC §1.20), matching the C# fallback.
enum EditorStrings {
    /// Routes through `MacUiText` (`Sources/SnapBriefMac/App/MacUiText.swift`) rather than Core's
    /// `UiLanguage.text` directly, so the 3 macOS-adapted strings (SPEC §1.20, e.g. "Сохранить на
    /// компьютер (Cmd+S)" instead of the Windows "(Ctrl+S)") apply here too.
    static func text(_ value: String, language: String) -> String {
        MacUiText.text(value, language: language)
    }

    // Hint / selection mode
    static func selectHint(_ language: String) -> String { text("Выделите область · Esc отменяет", language: language) }

    // Tool tooltips (also used as "•••" menu titles, with the trailing key letter appended by callers)
    static func toolSelect(_ language: String) -> String { text("Выбор", language: language) }
    static func toolRectangle(_ language: String) -> String { text("Область", language: language) }
    static func toolArrow(_ language: String) -> String { text("Стрелка", language: language) }
    static func toolPen(_ language: String) -> String { text("Перо", language: language) }
    static func toolHighlight(_ language: String) -> String { text("Маркер", language: language) }
    static func toolText(_ language: String) -> String { text("Текст", language: language) }
    static func toolConceal(_ language: String) -> String { text("Скрыть", language: language) }
    static func toolConcealSolid(_ language: String) -> String { text("Скрыть сплошным", language: language) }
    static func toolBlur(_ language: String) -> String { text("Размыть", language: language) }
    static func toolCrop(_ language: String) -> String { text("Обрезать", language: language) }
    static func thickness(_ language: String) -> String { text("Толщина", language: language) }
    static func moreTools(_ language: String) -> String { text("Ещё инструменты", language: language) }
    // Appearance popover (SPEC §1.3, §6.2 "Дополнение 2026-09-09"). "Цвет отметки" (the old
    // cycling menu item) is gone with the cycle it labeled; these four are new.
    static func appearanceButtonTooltip(_ language: String) -> String { text("Цвет и толщина", language: language) }
    static func colorHeading(_ language: String) -> String { text("Цвет", language: language) }
    static func closeTooltip(_ language: String) -> String { text("Закрыть", language: language) }
    static func colorHexAccessibilityName(_ language: String) -> String { text("Цвет HEX", language: language) }
    static func strokeThicknessAccessibilityName(_ language: String) -> String { text("Толщина линии", language: language) }
    static func addComment(_ language: String) -> String { text("Добавить комментарий", language: language) }
    /// Port of the toolbar Comment button's tooltip (SPEC-DELTA-2.md §3: "Добавить комментарий
    /// (N)"), distinct from `addComment` (used by SPEC-DELTA-2B.md §D's preview panel, out of this
    /// zone, and by the plain "Добавить комментарий" reused string).
    static func addCommentWithKey(_ language: String) -> String { text("Добавить комментарий (N)", language: language) }
    static func removeComment(_ language: String) -> String { text("Удалить комментарий", language: language) }
    static func closeTextInput(_ language: String) -> String { text("Закрыть ввод текста", language: language) }
    static func undo(_ language: String) -> String { text("Отменить", language: language) }
    static func redo(_ language: String) -> String { text("Повторить", language: language) }
    static func saveToComputer(_ language: String) -> String { text("Сохранить на компьютер (Ctrl+S)", language: language) }
    static func done(_ language: String) -> String { text("Готово", language: language) }

    // Arrow style menu (SPEC-DELTA-2.md §1.2, §3; SPEC-DELTA-2B.md §C6).
    static func arrowStyle(_ language: String) -> String { text("Стиль стрелки", language: language) }
    static func arrowStraight(_ language: String) -> String { text("Прямая стрелка", language: language) }
    static func arrowCurved(_ language: String) -> String { text("Изогнутая стрелка", language: language) }
    static func arrowBold(_ language: String) -> String { text("Толстая стрелка", language: language) }
    static func arrowWide(_ language: String) -> String { text("Широкая стрелка", language: language) }

    static func defaultText(_ language: String) -> String { text("Текст", language: language) }

    /// Port of `RefreshLabels`'s empty-badge placeholders (SPEC-DELTA-2.md §1.3): not translated
    /// (single glyphs, not sentences), matching the Windows source's own hardcoded `"T"`/`"+"`.
    static let textPlaceholderBadge = "T"
    static let commentPlaceholderBadge = "+"

    // Capture corner handles
    static func resizeCaptureBounds(_ language: String) -> String { text("Изменить границы снимка", language: language) }
    static func captureCorner(_ language: String, _ oneBasedIndex: Int) -> String {
        "\(text("Угол снимка", language: language)) \(oneBasedIndex)"
    }

    // Thickness button content, e.g. "4 px"
    static func thicknessLabel(_ points: Double) -> String {
        "\(Int(points)) px"
    }

    // Errors / notifications
    static func couldNotSaveCapture(_ language: String, _ message: String) -> String {
        "\(text("Не удалось сохранить снимок", language: language)): \(message)"
    }
    static func couldNotCropCapture(_ language: String, _ message: String) -> String {
        "\(text("Не удалось обрезать снимок", language: language)): \(message)"
    }
    static func couldNotResizeCapture(_ language: String, _ message: String) -> String {
        "\(text("Не удалось изменить границы снимка", language: language)): \(message)"
    }
    static func choosePngOrJpeg(_ language: String) -> String { text("Выберите PNG или JPEG.", language: language) }
    static func captureSaved(_ language: String) -> String { text("Снимок сохранён", language: language) }
    static func saveDialogTitle(_ language: String) -> String { saveToComputer(language) }
}
