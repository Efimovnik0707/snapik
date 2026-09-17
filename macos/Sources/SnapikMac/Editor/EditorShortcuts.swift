// Port of `src/Snapik.App/EditorShortcuts.cs`, SPEC-DELTA-3 §1.4 E-19, §4 (Cmd instead of Ctrl).
import Foundation

/// One source of truth for the editor keys. The tooltips of the panel, the menus of the split
/// capsules and the cheat sheet all read the letters from here, so a key can be changed in one
/// place. The letters themselves are the same in both languages; only the name is translated.
enum EditorShortcuts {
    struct Shortcut {
        let tool: EditorTool
        /// The letter, as it is shown in the capsule beside the name.
        let caption: String
        /// The Russian key of `UiLanguage`.
        let nameKey: String
    }

    /// Ten tools, in the order of the cheat sheet (`EditorShortcuts.Tools`).
    static let tools: [Shortcut] = [
        Shortcut(tool: .select, caption: "V", nameKey: "Выбор"),
        Shortcut(tool: .rectangle, caption: "R", nameKey: "Область"),
        Shortcut(tool: .arrow, caption: "A", nameKey: "Стрелка"),
        Shortcut(tool: .pen, caption: "P", nameKey: "Карандаш"),
        Shortcut(tool: .highlight, caption: "H", nameKey: "Маркер"),
        Shortcut(tool: .text, caption: "T", nameKey: "Текст"),
        Shortcut(tool: .eraser, caption: "E", nameKey: "Ластик"),
        Shortcut(tool: .blur, caption: "B", nameKey: "Размыть"),
        Shortcut(tool: .crop, caption: "C", nameKey: "Обрезать"),
        Shortcut(tool: .comment, caption: "N", nameKey: "Добавить комментарий"),
    ]

    /// Everything the cheat sheet lists beside the tools. SPEC-DELTA-3 §4: Cmd instead of Ctrl, and
    /// redo is Shift+Cmd+Z rather than a key of its own — the letters of a Mac keyboard.
    static let actions: [(caption: String, nameKey: String)] = [
        ("Cmd+Z", "Отменить"),
        ("Shift+Cmd+Z", "Повторить"),
        ("Cmd+S", "Сохранить на компьютер"),
        ("Shift+Cmd+C", "Копировать снимок"),
        ("Cmd+C", "Готово"),
        ("Esc", "Отменить снимок"),
        ("Enter", "Закончить заметку"),
        ("Shift+Enter", "Новая строка в заметке"),
    ]

    static func find(_ tool: EditorTool) -> Shortcut? {
        tools.first(where: { $0.tool == tool })
    }

    static func tool(forKey key: String) -> EditorTool? {
        tools.first(where: { $0.caption == key.uppercased() })?.tool
    }

    /// The name in the current language plus the letter in brackets, for the places that cannot show
    /// a capsule: the items of a split-capsule menu and the tooltip of the button that opens it.
    static func caption(_ tool: EditorTool, language: String) -> String {
        guard let shortcut = find(tool) else { return "" }
        return "\(EditorStrings.text(shortcut.nameKey, language: language)) (\(shortcut.caption))"
    }
}
