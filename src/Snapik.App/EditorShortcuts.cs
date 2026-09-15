using System.Collections.Generic;
using System.Linq;
using System.Windows.Input;
using Snapik.Core.Editing;

namespace Snapik.App;

// One source of truth for the editor keys. The toolbar tooltips, the "•••" menu, the caption
// SyncAppearance builds and the key handler all read the letters from here, so a key can be
// changed in one place. Names are the Russian keys of the UiLanguage table, without the letter:
// the capsule next to the name carries it (through Uid of the button, see the tooltip style of the
// editor window).
internal static class EditorShortcuts
{
    internal sealed record Shortcut(EditorTool Tool, Key Key, string Name)
    {
        internal string Caption => Key.ToString();
    }

    internal static IReadOnlyList<Shortcut> Tools { get; } =
    [
        new(EditorTool.Select, Key.V, "Выбор"),
        new(EditorTool.Rectangle, Key.R, "Область"),
        new(EditorTool.Arrow, Key.A, "Стрелка"),
        new(EditorTool.Pen, Key.P, "Карандаш"),
        new(EditorTool.Highlight, Key.H, "Маркер"),
        new(EditorTool.Text, Key.T, "Текст"),
        new(EditorTool.Eraser, Key.E, "Ластик"),
        new(EditorTool.Blur, Key.B, "Размыть"),
        new(EditorTool.Crop, Key.C, "Обрезать"),
        new(EditorTool.Comment, Key.N, "Добавить комментарий")
    ];

    // Everything the cheat sheet lists beside the tools; the keys are handled in OnWindowKeyDown
    // and in the note editor, and they are the same in both languages.
    internal static IReadOnlyList<(string Caption, string Name)> Actions { get; } =
    [
        ("Ctrl+Z", "Отменить"),
        ("Ctrl+Y", "Повторить"),
        ("Ctrl+S", "Сохранить на компьютер"),
        ("Ctrl+C", "Готово"),
        ("Esc", "Отменить снимок"),
        ("Enter", "Закончить заметку"),
        ("Shift+Enter", "Новая строка в заметке")
    ];

    internal static Shortcut? Find(EditorTool tool) => Tools.FirstOrDefault(shortcut => shortcut.Tool == tool);

    internal static EditorTool? ToolFor(Key key) => Tools.FirstOrDefault(shortcut => shortcut.Key == key)?.Tool;

    // The name in the current language plus the letter in brackets, for the places that cannot
    // show a capsule: the "•••" menu and the caption of the button that opens it.
    internal static string Caption(EditorTool tool, string? language = null) =>
        Find(tool) is { } shortcut ? $"{UiLanguage.Text(shortcut.Name, language)} ({shortcut.Caption})" : tool.ToString();
}
