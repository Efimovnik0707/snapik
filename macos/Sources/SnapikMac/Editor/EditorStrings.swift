// Port of literal RU strings from OverlayEditorWindow.xaml / .xaml.cs / CaptureOverlay.xaml,
// routed through `MacUiText.text(_:language:)` (which itself falls back to Core's
// `UiLanguage.text(_:language:)`), SPEC §1.20, §6.1-6.3, SPEC-DELTA-3 §1.4.
import Foundation
import SnapikCore

/// Every user-facing string the editor shows, as the exact Russian source text used by
/// `UiLanguage.text(_:language:)` (mirrors how the Windows XAML hardcodes Russian literals that
/// `UiLanguage.Apply` translates by walking the tree; there is no tree walker on macOS, so each
/// call site here routes explicitly through `UiLanguage.text`). Unknown keys simply return
/// themselves (SPEC §1.20), matching the C# fallback.
enum EditorStrings {
    /// Routes through `MacUiText` (`Sources/SnapikMac/App/MacUiText.swift`) rather than Core's
    /// `UiLanguage.text` directly, so the macOS-adapted strings (SPEC §1.20, e.g. "Сохранить на
    /// компьютер (Cmd+S)" instead of the Windows "(Ctrl+S)") apply here too.
    static func text(_ value: String, language: String) -> String {
        MacUiText.text(value, language: language)
    }

    // Hint / selection mode
    static func selectHint(_ language: String) -> String { text("Выделите область · Esc отменяет", language: language) }

    // The name of a tool comes from `EditorShortcuts.tools`, which carries the letter beside it; the
    // pencil is named here as well because its capsule shows the name without a letter of its own.
    static func toolPencil(_ language: String) -> String { text("Карандаш", language: language) }

    // Panel buttons and their popovers (SPEC-DELTA-3 §1.4 E-3, E-16, E-17, E-18)
    static func colorHeading(_ language: String) -> String { text("Цвет", language: language) }
    static func thickness(_ language: String) -> String { text("Толщина", language: language) }
    static func lineStyle(_ language: String) -> String { text("Линия", language: language) }
    static func fill(_ language: String) -> String { text("Заливка", language: language) }
    static func fillColorHeading(_ language: String) -> String { text("Цвет заливки", language: language) }
    static func fontSize(_ language: String) -> String { text("Размер", language: language) }
    static func shape(_ language: String) -> String { text("Фигура", language: language) }
    static func shapeRectangle(_ language: String) -> String { text("Прямоугольник", language: language) }
    static func shapeRounded(_ language: String) -> String { text("Скруглённый прямоугольник", language: language) }
    static func shapeEllipse(_ language: String) -> String { text("Овал", language: language) }
    static func lineSolid(_ language: String) -> String { text("Сплошная", language: language) }
    static func lineDashed(_ language: String) -> String { text("Пунктир", language: language) }
    static func lineDotted(_ language: String) -> String { text("Точки", language: language) }
    static func fillOutline(_ language: String) -> String { text("Контур", language: language) }
    static func fillSolid(_ language: String) -> String { text("Сплошная заливка", language: language) }
    static func fillTranslucent(_ language: String) -> String { text("Полупрозрачная заливка", language: language) }
    static func fillBlur(_ language: String) -> String { text("Заливка размытием", language: language) }
    static func savedColors(_ language: String) -> String { text("Сохранённые цвета", language: language) }
    static func pickColorFromScreen(_ language: String) -> String { text("Взять цвет с экрана", language: language) }
    static func paletteName(_ key: String, _ language: String) -> String { text(key, language: language) }
    static func closeTooltip(_ language: String) -> String { text("Закрыть", language: language) }
    static func colorHexAccessibilityName(_ language: String) -> String { text("Цвет HEX", language: language) }
    static func strokeThicknessAccessibilityName(_ language: String) -> String { text("Толщина линии", language: language) }
    static func fontSizeAccessibilityName(_ language: String) -> String { text("Размер шрифта", language: language) }
    /// The "+" beside the HEX field, which saves the colour in force into the own palette
    /// (SPEC-DELTA-4 §1.3 E-9).
    static func addColorToCustomPalette(_ language: String) -> String { text("Добавить цвет в свою палитру", language: language) }
    static func addComment(_ language: String) -> String { text("Добавить комментарий", language: language) }

    // The caption of the capture and the switch of the scale (SPEC-DELTA-4 §3.5, §4)

    static func wholeScreen(_ language: String) -> String { text("весь экран", language: language) }
    static func importedFile(_ language: String) -> String { text("импорт", language: language) }
    /// "мониторов: 2", said only by a whole-screen capture that covered more than one.
    static func monitorCount(_ language: String, _ count: Int) -> String {
        UiFormat.text(text("мониторов: {0}", language: language), "\(count)")
    }
    static func removeComment(_ language: String) -> String { text("Удалить комментарий", language: language) }
    static func undo(_ language: String) -> String { text("Отменить", language: language) }
    static func redo(_ language: String) -> String { text("Повторить", language: language) }
    /// The pair Windows carries, without the keys in it: the shortcut is appended by whoever shows a
    /// tooltip, the way "Отменить (Cmd+Z)" is built (`EditorToolbarView`).
    static func saveToComputer(_ language: String) -> String { text("Сохранить на компьютер", language: language) }
    static func copyCapture(_ language: String) -> String { text("Копировать снимок", language: language) }
    /// "Снимок B скопирован": what the plate of the editor says when the strip took the copy.
    static func captureCopied(_ language: String, _ label: String) -> String {
        UiFormat.text(text("Снимок {0} скопирован", language: language), label)
    }
    static func couldNotCopyCapture(_ language: String) -> String {
        text("Не удалось скопировать снимок", language: language)
    }
    static func done(_ language: String) -> String { text("Готово", language: language) }

    // Key cheat sheet (SPEC-DELTA-3 §1.4 E-19)
    static func shortcutSheet(_ language: String) -> String { text("Сочетания клавиш", language: language) }
    static func shortcutTools(_ language: String) -> String { text("Инструменты", language: language) }
    static func shortcutActions(_ language: String) -> String { text("Действия", language: language) }

    // Comments panel (SPEC-DELTA-3 §1.4 E-12)
    static func comments(_ language: String) -> String { text("Комментарии", language: language) }
    static func noComments(_ language: String) -> String { text("Нет комментариев", language: language) }

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

    /// A value in pixels on a button, e.g. "4 px".
    static func pixelLabel(_ points: Double) -> String {
        "\(Int(points.rounded())) px"
    }

    /// The size of a caption on the second capsule, e.g. "20 pt" (`LineCapsuleValue`).
    static func pointLabel(_ points: Double) -> String {
        "\(Int(points.rounded())) pt"
    }

    /// The short name of a shape, the one the second capsule carries (`ShapeName`,
    /// `.Appearance.cs:357-362`). Short on purpose: the capsule is 105 points wide, and the menu of
    /// the shapes says the long names.
    static func shapeNameKey(_ shape: AnnotationShape) -> String {
        switch shape {
        case .rounded: return "Скруглённый"
        case .ellipse: return "Овал"
        case .rectangle: return "Прямоугольник"
        }
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
