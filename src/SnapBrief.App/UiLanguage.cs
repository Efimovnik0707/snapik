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
        ["Показывать уведомления"] = "Show notifications",
        ["Предлагать ту же область, что в прошлый раз"] = "Offer the same area as last time",
        ["Показывать курсор мыши на скриншоте"] = "Show the mouse pointer in the screenshot",
        ["Звуки"] = "Sounds", ["Автоматически сохранять готовые снимки"] = "Automatically save completed captures",
        ["Укажите папку сохранения."] = "Choose a save folder.", ["Автосохранение не выполнено"] = "Auto-save failed",
        ["Язык"] = "Language", ["Акцент"] = "Accent", ["Акцент: {0}"] = "Accent: {0}",
        ["синий"] = "blue", ["бирюзовый"] = "teal", ["фиолетовый"] = "violet", ["коралловый"] = "coral",
        ["Сделать скриншот"] = "Take a screenshot", ["Скриншот всего экрана в папку"] = "Save the whole screen to a folder",
        ["Формат"] = "Format", ["Папка сохранения"] = "Save folder", ["Выбрать папку"] = "Choose folder",
        ["Качество JPEG: {0} % (меньше, легче файл)"] = "JPEG quality: {0} % (lower means a smaller file)",
        ["Сохранить"] = "Save", ["Отмена"] = "Cancel", ["Закрыть"] = "Close",
        ["Нажмите своё сочетание клавиш"] = "Press your shortcut", ["Нажми, чтобы изменить"] = "Click to change", ["Новый снимок"] = "New capture", ["+ Снимок"] = "+ Capture",
        ["Готово"] = "Done", ["Выбор"] = "Select", ["Область"] = "Region", ["Стрелка"] = "Arrow", ["Перо"] = "Pen",
        ["Маркер"] = "Highlight", ["Текст"] = "Text", ["Скрыть сплошным"] = "Conceal", ["Размыть"] = "Blur", ["Обрезать"] = "Crop",
        ["Цвет и толщина"] = "Color and thickness", ["Сочетания клавиш"] = "Keyboard shortcuts", ["Инструменты"] = "Tools", ["Действия"] = "Actions",
        ["Отменить снимок"] = "Cancel the capture", ["Закончить заметку"] = "Finish the note", ["Новая строка в заметке"] = "New line in the note",
        ["Цвет отметки"] = "Annotation color", ["Толщина"] = "Thickness", ["Ещё инструменты"] = "More tools",
        ["Цвет"] = "Color", ["Цвет HEX"] = "HEX color", ["Толщина линии"] = "Line thickness",
        ["Выделите область · Esc отменяет"] = "Select an area · Esc cancels", ["СНИМОК {0}"] = "CAPTURE {0}",
        ["Добавить комментарий"] = "Add comment", ["Удалить комментарий"] = "Remove comment", ["Отменить"] = "Undo", ["Повторить"] = "Redo",
        ["Просмотр снимка"] = "Capture preview", ["По размеру окна"] = "Fit to window", ["Увеличить"] = "Zoom in", ["Уменьшить"] = "Zoom out",
        ["На весь экран"] = "Full screen", ["Вернуть размер"] = "Restore size", ["Разметка"] = "Mark up", ["Закрыть просмотр"] = "Close preview",
        ["Комментарии"] = "Comments", ["Нет комментариев"] = "No comments yet", ["Комментарий к снимку"] = "Capture comment",
        ["К снимку"] = "To capture", ["К отметке"] = "To annotation",
        ["Прямая стрелка"] = "Straight arrow", ["Изогнутая стрелка"] = "Curved arrow", ["Толстая стрелка"] = "Bold arrow", ["Широкая стрелка"] = "Wide arrow",
        ["Стиль стрелки"] = "Arrow style",
        ["Закрыть ввод текста"] = "Close text editor",
        ["Сохранить на компьютер"] = "Save to computer", ["Свернуть в трей"] = "Hide to tray", ["Ещё"] = "More",
        ["Удалить"] = "Delete", ["Открыть снимок"] = "Open capture", ["Вернуть"] = "Restore", ["Показать стопку"] = "Show stack",
        ["Запускать с Windows"] = "Start with Windows", ["Выйти"] = "Exit",
        ["Очистить ленту"] = "Clear the strip", ["Лента очищена"] = "Strip cleared",
        ["Очищать ленту после вставки"] = "Clear the strip after pasting",
        ["Копировать пакет"] = "Copy package", ["Сохранить пакет…"] = "Save package…", ["Импортировать файл…"] = "Import file…",
        ["Вставить изображение из буфера"] = "Paste image from clipboard", ["Вернуть удалённый снимок"] = "Restore deleted capture",
        ["Горячие клавиши…"] = "Settings…", ["Настройки клавиш"] = "Shortcut settings", ["Снимок сохранён"] = "Capture saved",
        ["Снимки скопированы"] = "Captures copied", ["Скопировано"] = "Copied", ["Изображения и комментарии готовы к вставке"] = "Images and comments are ready to paste",
        ["Снимки сохранены, но вставка не завершена"] = "Captures were saved, but pasting did not finish",
        ["Вставлено: {0} изображений · {1} заметок. Снимки помечены как отправленные"] = "Pasted: {0} images · {1} notes. The captures are marked as sent",
        ["Пакет вытеснен другим приложением. Сессия сохранена."] = "Another app replaced the package. The session was saved.",
        ["Изображения"] = "Images", ["Все файлы"] = "All files", ["Добавлено снимков: {0}"] = "Captures added: {0}",
        ["Изображение добавлено."] = "Image added.", ["В буфере нет изображения."] = "There is no image on the clipboard.",
        ["Не удалось добавить"] = "Could not add", ["Формат не поддерживается системой"] = "The system does not support this format",
        ["Поверх других окон"] = "Always on top", ["Не удалось сохранить настройки"] = "Could not save the settings",
        ["Файл настроек не читается."] = "The settings file cannot be read.",
        ["Файл настроек не читался, настройки созданы заново"] = "The settings file could not be read, the settings were created anew",
        ["Снимок удалён"] = "Capture removed", ["Снимок восстановлен."] = "Capture restored.",
        ["Порядок снимков изменён."] = "Capture order changed.", ["Пакет сохранён."] = "Package saved.",
        ["Готово: {0} изображений · {1} заметок"] = "Ready: {0} images · {1} notes",
        ["Не удалось изменить автозапуск"] = "Could not change the startup setting",
        ["Не удалось восстановить сессию"] = "Could not restore the session",
        ["Захват"] = "Capture", ["Отслеживание вставки недоступно"] = "Paste tracking is unavailable",
        ["Сочетание занято"] = "The shortcut is taken", ["захват"] = "capture", ["сохранение экрана"] = "screen saving",
        ["Не удалось подтвердить содержимое текущего пакета. Сессия сохранена."] = "Could not confirm what the current package holds. The session was saved.",
        ["Вставка замечена, но лента не обновлена"] = "The paste was noticed, but the strip was not updated",
        ["Захват не завершён"] = "The capture did not finish", ["Сначала сделайте снимок."] = "Take a capture first.",
        ["Все снимки уже отправлены. Сделайте новый снимок."] = "Every capture was already sent. Take a new one.",
        ["Регистрация клавиш недоступна. Перезапустите SnapBrief."] = "Shortcut registration is unavailable. Restart SnapBrief.",
        ["Эта клавиша уже занята. Освободите её в другом приложении или выберите другую."] = "This shortcut is already taken. Free it in the other application or pick another one.",
        ["Не удалось назначить сочетание. Возможно, оно уже занято — нажмите другое."] = "Could not assign the shortcut. It may already be taken — press another one.",
        ["Готовим PNG и текст…"] = "Preparing the PNG and the text…", ["Не удалось подготовить"] = "Could not prepare",
        ["Снимок сохранён, но буфер не обновлён"] = "The capture was saved, but the clipboard was not updated",
        ["Повторите копирование через меню."] = "Copy the package again from the menu.",
        ["Вставка остановлена"] = "Pasting stopped", ["Не удалось выполнить действие"] = "Could not run the action",
        ["PNG и текст скопированы. Если получатель выберет один формат, используйте кнопку вставки."] = "The PNG and the text were copied. If the receiver takes only one format, use the paste button.",
        ["PNG и текст скопированы."] = "The PNG and the text were copied.",
        ["Не удалось сохранить"] = "Could not save", ["Не удалось очистить ленту"] = "Could not clear the strip",
        ["Буфер не обновлён"] = "The clipboard was not updated",
        ["Знакомство со SnapBrief"] = "Welcome to SnapBrief", ["Шаг {0} из {1}"] = "Step {0} of {1}",
        ["Назад"] = "Back", ["Далее"] = "Next", ["Начать"] = "Get started", ["Пропустить"] = "Skip",
        ["Выберите язык"] = "Choose your language",
        ["Интерфейс и подсказки будут на этом языке."] = "The interface and the hints will be in this language.",
        ["Клавиша для снимка"] = "The capture shortcut",
        ["Нажми на поле и введи своё сочетание"] = "Click the field and press your own shortcut",
        ["Запуск и панель задач"] = "Startup and the taskbar",
        ["Чтобы лента всегда была под рукой, закрепи SnapBrief: открой Пуск, нажми правой кнопкой на SnapBrief и выбери «Закрепить на панели задач»"] =
            "To keep the strip within reach, pin SnapBrief: open Start, right-click SnapBrief and choose \"Pin to taskbar\"",
        ["Повторный запуск ярлыка не открывает второе окно, а показывает ленту."] = "Starting the shortcut again does not open a second window, it shows the strip.",
        ["Автозапуск недоступен"] = "Autostart is unavailable",
        ["Показать ярлык"] = "Show the shortcut", ["Не удалось открыть папку с ярлыком"] = "Could not open the folder with the shortcut",
        ["Как пользоваться"] = "How it works", ["Нажми клавишу"] = "Press the shortcut", ["Выдели область"] = "Select an area",
        ["Добавь комментарии"] = "Add comments", ["Вставь в чат: Ctrl+V"] = "Paste into the chat: Ctrl+V"
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
