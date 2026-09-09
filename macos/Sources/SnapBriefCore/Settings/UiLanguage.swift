import Foundation

/// Port of the data half of `src/SnapBrief.App/UiLanguage.cs`: the RU/EN string table and
/// `Text(value, language)` lookup, verbatim. The WPF-tree-walking `Apply(DependencyObject, ...)`
/// method is UI plumbing (`TextBlock`/`ContentControl`/`HeaderedItemsControl` traversal) with no
/// AppKit-free cross-platform equivalent and is intentionally not ported here; the Mac app target
/// re-implements the equivalent view-tree localization pass using `UiLanguage.text(_:language:)`.
public enum UiLanguage {
    public static var current: String = "ru"

    /// Ordered like the C# dictionary initializer: `FirstOrDefault` reverse lookup relies on insertion order.
    private static let englishPairs: [(String, String)] = [
        ("Настройки", "Settings"),
        ("Настройки SnapBrief", "SnapBrief settings"),
        ("Общие", "General"),
        ("Клавиши", "Hotkeys"),
        ("Сохранение", "Saving"),
        ("Уведомления о копировании и сохранении", "Notify on copy and save"),
        ("Запоминать последнюю область", "Remember the last region"),
        ("Захватывать курсор", "Capture the cursor"),
        // Sync 2 additions (SPEC-DELTA-2.md §3, order matches `src/SnapBrief.App/UiLanguage.cs`).
        ("Звуки захвата и стопки", "Capture and stack sounds"),
        ("Автоматически сохранять готовые снимки", "Automatically save completed captures"),
        ("Укажите папку сохранения.", "Choose a save folder."),
        ("Автосохранение не выполнено", "Auto-save failed"),
        ("Язык", "Language"),
        ("Захват области", "Capture region"),
        ("Быстро сохранить весь экран", "Instantly save the full screen"),
        ("Формат", "Format"),
        ("Качество JPEG", "JPEG quality"),
        ("Папка сохранения", "Save folder"),
        ("Выбрать папку", "Choose folder"),
        ("Сохранить", "Save"),
        ("Отмена", "Cancel"),
        ("Нажмите клавишу…", "Press a key…"),
        ("Нажмите своё сочетание клавиш", "Press your shortcut"),
        ("Новый снимок", "New capture"),
        ("+ Снимок", "+ Capture"),
        ("Готово", "Done"),
        ("Выбор", "Select"),
        ("Область", "Region"),
        ("Стрелка", "Arrow"),
        ("Перо", "Pen"),
        ("Маркер", "Highlight"),
        ("Текст", "Text"),
        ("Скрыть", "Conceal"),
        ("Размыть", "Blur"),
        ("Обрезать", "Crop"),
        ("Цвет отметки", "Annotation color"),
        ("Толщина", "Thickness"),
        ("Ещё инструменты", "More tools"),
        // macOS-only additions (SPEC §1.3, §6.2 "Дополнение 2026-09-09": appearance popover).
        // Not present in `src/SnapBrief.App/UiLanguage.cs` as of this sync — the Windows XAML
        // hardcodes these Russian strings directly and has no English translation for them yet.
        ("Цвет и толщина", "Color and thickness"),
        ("Цвет", "Color"),
        ("Закрыть", "Close"),
        ("Цвет HEX", "Color HEX"),
        ("Толщина линии", "Line thickness"),
        ("Добавить комментарий", "Add comment"),
        ("Удалить комментарий", "Remove comment"),
        ("Отменить", "Undo"),
        ("Повторить", "Redo"),
        // Sync 2 additions (SPEC-DELTA-2.md §3): preview window, comments, arrow styles.
        ("Просмотр снимка", "Capture preview"),
        ("По размеру окна", "Fit to window"),
        ("Увеличить", "Zoom in"),
        ("Уменьшить", "Zoom out"),
        ("На весь экран", "Full screen"),
        ("Вернуть размер", "Restore size"),
        ("Разметка", "Mark up"),
        ("Закрыть просмотр", "Close preview"),
        ("Комментарии", "Comments"),
        ("Нет комментариев", "No comments yet"),
        ("Комментарий к снимку", "Capture comment"),
        ("К снимку", "To capture"),
        ("К отметке", "To annotation"),
        ("Прямая стрелка", "Straight arrow"),
        ("Изогнутая стрелка", "Curved arrow"),
        ("Толстая стрелка", "Bold arrow"),
        ("Широкая стрелка", "Wide arrow"),
        ("Стиль стрелки", "Arrow style"),
        ("Добавить комментарий (N)", "Add comment (N)"),
        ("Закрыть ввод текста", "Close text editor"),
        ("Сохранить на компьютер (Ctrl+S)", "Save to computer (Ctrl+S)"),
        ("Свернуть в трей", "Hide to tray"),
        ("Ещё", "More"),
        ("Удалить", "Delete"),
        ("Открыть снимок", "Open capture"),
        ("Вернуть", "Restore"),
        ("Показать стопку", "Show stack"),
        ("Запускать с Windows", "Start with Windows"),
        ("Выйти", "Exit"),
        ("Новая сессия", "New session"),
        ("Копировать пакет", "Copy package"),
        ("Сохранить пакет…", "Save package…"),
        ("Импортировать файл…", "Import file…"),
        ("Вставить изображение из буфера", "Paste image from clipboard"),
        ("Вернуть удалённый снимок", "Restore deleted capture"),
        ("Горячие клавиши…", "Settings…"),
        ("Настройки клавиш", "Settings"),
        ("Снимок сохранён", "Capture saved"),
        ("Снимки скопированы", "Captures copied"),
        ("Скопировано", "Copied"),
        ("Изображения и комментарии готовы к вставке", "Images and comments are ready to paste"),
        // Sync 2 additions (SPEC-DELTA-2.md §3, appended at the end of the Windows dictionary).
        ("Снимки сохранены, но вставка не завершена", "Captures were saved, but pasting did not finish"),
        (
            "Вставлено: {0} изображений · {1} заметок. Пакет остаётся в буфере, следующий снимок начнёт новую стопку",
            "Pasted: {0} images · {1} notes. The package stays on the clipboard, the next capture will start a new stack"
        ),
        ("Пакет вытеснен другим приложением. Сессия сохранена.", "Another app replaced the package. The session was saved."),
    ]

    private static let english: [String: String] = Dictionary(englishPairs, uniquingKeysWith: { first, _ in first })

    /// Port of `Text(string value, string? language = null)`.
    public static func text(_ value: String, language: String? = nil) -> String {
        let resolvedLanguage = language ?? current
        if resolvedLanguage == "en" {
            return english[value] ?? value
        }
        return englishPairs.first(where: { $0.1 == value })?.0 ?? value
    }
}
