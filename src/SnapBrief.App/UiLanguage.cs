using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;

namespace SnapBrief.App;

internal static class UiLanguage
{
    internal static string Current { get; set; } = "ru";
    private static readonly Dictionary<string, string> English = new()
    {
        ["Настройки"] = "Settings", ["Настройки SnapBrief"] = "SnapBrief settings",
        ["Общие"] = "General", ["Клавиши"] = "Hotkeys", ["Сохранение"] = "Saving",
        ["Уведомления о копировании и сохранении"] = "Notify on copy and save",
        ["Запоминать последнюю область"] = "Remember the last region", ["Захватывать курсор"] = "Capture the cursor",
        ["Звуки захвата и стопки"] = "Capture and stack sounds", ["Автоматически сохранять готовые снимки"] = "Automatically save completed captures",
        ["Укажите папку сохранения."] = "Choose a save folder.", ["Автосохранение не выполнено"] = "Auto-save failed",
        ["Язык"] = "Language", ["Захват области"] = "Capture region", ["Быстро сохранить весь экран"] = "Instantly save the full screen",
        ["Формат"] = "Format", ["Качество JPEG"] = "JPEG quality", ["Папка сохранения"] = "Save folder", ["Выбрать папку"] = "Choose folder",
        ["Сохранить"] = "Save", ["Отмена"] = "Cancel", ["Нажмите клавишу…"] = "Press a key…",
        ["Нажмите своё сочетание клавиш"] = "Press your shortcut", ["Новый снимок"] = "New capture", ["+ Снимок"] = "+ Capture",
        ["Готово"] = "Done", ["Выбор"] = "Select", ["Область"] = "Region", ["Стрелка"] = "Arrow", ["Перо"] = "Pen",
        ["Маркер"] = "Highlight", ["Текст"] = "Text", ["Скрыть"] = "Conceal", ["Размыть"] = "Blur", ["Обрезать"] = "Crop",
        ["Цвет отметки"] = "Annotation color", ["Толщина"] = "Thickness", ["Ещё инструменты"] = "More tools",
        ["Добавить комментарий"] = "Add comment", ["Удалить комментарий"] = "Remove comment", ["Отменить"] = "Undo", ["Повторить"] = "Redo",
        ["Просмотр снимка"] = "Capture preview", ["По размеру окна"] = "Fit to window", ["Увеличить"] = "Zoom in", ["Уменьшить"] = "Zoom out",
        ["На весь экран"] = "Full screen", ["Вернуть размер"] = "Restore size", ["Разметка"] = "Mark up", ["Закрыть просмотр"] = "Close preview",
        ["Комментарии"] = "Comments", ["Нет комментариев"] = "No comments yet", ["Комментарий к снимку"] = "Capture comment",
        ["К снимку"] = "To capture", ["К отметке"] = "To annotation",
        ["Прямая стрелка"] = "Straight arrow", ["Изогнутая стрелка"] = "Curved arrow", ["Толстая стрелка"] = "Bold arrow", ["Широкая стрелка"] = "Wide arrow",
        ["Стиль стрелки"] = "Arrow style",
        ["Добавить комментарий (N)"] = "Add comment (N)", ["Закрыть ввод текста"] = "Close text editor",
        ["Сохранить на компьютер (Ctrl+S)"] = "Save to computer (Ctrl+S)", ["Свернуть в трей"] = "Hide to tray", ["Ещё"] = "More",
        ["Удалить"] = "Delete", ["Открыть снимок"] = "Open capture", ["Вернуть"] = "Restore", ["Показать стопку"] = "Show stack",
        ["Запускать с Windows"] = "Start with Windows", ["Выйти"] = "Exit", ["Новая сессия"] = "New session",
        ["Копировать пакет"] = "Copy package", ["Сохранить пакет…"] = "Save package…", ["Импортировать файл…"] = "Import file…",
        ["Вставить изображение из буфера"] = "Paste image from clipboard", ["Вернуть удалённый снимок"] = "Restore deleted capture",
        ["Горячие клавиши…"] = "Settings…", ["Настройки клавиш"] = "Settings", ["Снимок сохранён"] = "Capture saved",
        ["Снимки скопированы"] = "Captures copied", ["Скопировано"] = "Copied", ["Изображения и комментарии готовы к вставке"] = "Images and comments are ready to paste"
    };
    internal static string Text(string value, string? language = null) => (language ?? Current) == "en" ? (English.TryGetValue(value, out var translated) ? translated : value) : (English.FirstOrDefault(pair => pair.Value == value).Key ?? value);
    internal static void Apply(DependencyObject root, string? language = null)
    {
        var visited = new HashSet<DependencyObject>();
        void Walk(DependencyObject item)
        {
            if (!visited.Add(item)) return;
            if (item is TextBlock text && !System.Windows.Data.BindingOperations.IsDataBound(text, TextBlock.TextProperty)) text.Text = Text(text.Text, language);
            if (item is ContentControl control && control.Content is string caption) control.Content = Text(caption, language);
            if (item is HeaderedContentControl header && header.Header is string title) header.Header = Text(title, language);
            if (item is HeaderedItemsControl menu && menu.Header is string menuTitle) menu.Header = Text(menuTitle, language);
            if (item is FrameworkElement element && element.ToolTip is string tip) element.ToolTip = Text(tip, language);
            foreach (var child in LogicalTreeHelper.GetChildren(item)) if (child is DependencyObject dependency) Walk(dependency);
            if (item is Visual)
                for (var i = 0; i < VisualTreeHelper.GetChildrenCount(item); i++) Walk(VisualTreeHelper.GetChild(item, i));
        }
        Walk(root);
    }
}
