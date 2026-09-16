import Foundation

/// Port of the data half of `src/Snapik.App/UiLanguage.cs`: the RU/EN string table and
/// `Text(value, language)` lookup, verbatim. The WPF-tree-walking `Apply(DependencyObject, ...)`
/// method is UI plumbing (`TextBlock`/`ContentControl`/`HeaderedItemsControl` traversal) with no
/// AppKit-free cross-platform equivalent and is intentionally not ported here; the Mac app target
/// re-implements the equivalent view-tree localization pass using `UiLanguage.text(_:language:)`.
public enum UiLanguage {
    public static var current: String = "ru"

    /// Ordered like the C# dictionary initializer: `FirstOrDefault` reverse lookup relies on insertion order.
    /// Neither a Russian key nor an English value may repeat: the way back is a search by value,
    /// and a duplicate would answer with the wrong key (`UiLanguage.EnglishValues` on Windows).
    static let englishPairs: [(String, String)] = [
        ("Настройки", "Settings"),
        ("Настройки Snapik", "Snapik settings"),
        ("Общие", "General"),
        ("Клавиши", "Hotkeys"),
        ("Сохранение", "Saving"),
        ("Показывать уведомления", "Show notifications"),
        ("Предлагать ту же область, что в прошлый раз", "Offer the same area as last time"),
        ("Показывать курсор мыши на скриншоте", "Show the mouse pointer in the screenshot"),
        ("Звуки", "Sounds"),
        ("Громкость", "Volume"),
        ("Автоматически сохранять готовые снимки", "Automatically save completed captures"),
        ("Укажите папку сохранения.", "Choose a save folder."),
        ("Автосохранение не выполнено", "Auto-save failed"),
        // The tooltips of the settings rows; they are translated on the way through
        // UiLanguage.Apply.
        (
            "Всплывающее окно у часов: «Скопировано», «Сохранено»",
            "A pop-up by the clock: \"Copied\", \"Saved\""
        ),
        (
            "Щелчок затвора при снимке и тихие тики ленты",
            "The shutter click on a capture and the quiet ticks of the strip"
        ),
        ("Насколько громко звучит интерфейс", "How loud the interface sounds are"),
        (
            "После Ctrl+V лента очищается сама, снимки удаляются",
            "After Ctrl+V the strip clears itself and the captures are deleted"
        ),
        (
            "Каждый готовый снимок сразу ложится в папку сохранения",
            "Every finished capture goes straight into the save folder"
        ),
        ("JPEG легче, PNG точнее", "JPEG is lighter, PNG is sharper"),
        ("Куда падают снимки и пакеты", "Where the captures and the packages land"),
        ("Открывать при включении компьютера", "Open when the computer starts"),
        ("Язык", "Language"),
        ("Вид", "Appearance"),
        ("Акцент", "Accent"),
        ("Акцент: {0}", "Accent: {0}"),
        ("синий", "blue"),
        ("фиолетовый", "violet"),
        // The identifier of an accent and the word for it have drifted apart on purpose: "teal" is
        // shown as green and "coral" as orange, and renaming the identifiers would cost a
        // migration.
        ("зелёный", "green"),
        ("оранжевый", "orange"),
        // [ТЗ№4 A5] Four more accents: two flat and, below, two gradients.
        ("розовый", "rose"),
        ("бирюзовый", "cyan"),
        ("сине-фиолетовый", "blue to violet"),
        ("оранжево-розовый", "orange to rose"),
        ("зелёно-бирюзовый", "green to cyan"),
        ("янтарно-розовый", "amber to pink"),
        ("розово-фиолетовый", "rose to violet"),
        ("бирюзово-синий", "cyan to blue"),
        ("Тёмная", "Dark"),
        // [ТЗ№4 B1] There is no light theme of its own any more: the card that carried it is the
        // dawn one, and `Рассвет` below stays the name of that theme.
        ("Светлая · Рассвет", "Light · Dawn"),
        ("Стекло", "Glass"),
        ("Ночь", "Night"),
        ("Закат", "Sunset"),
        ("Море", "Sea"),
        ("Рассвет", "Dawn"),
        ("Тема: {0}", "Theme: {0}"),
        ("Предыдущая тема", "Previous theme"),
        ("Следующая тема", "Next theme"),
        ("Тема · фон и панели", "Theme · background and panels"),
        ("Цвет · рамки, кнопки, номера отметок", "Color · frames, buttons, marker numbers"),
        ("так будут выглядеть отметки", "this is how the marks will look"),
        ("Палитра отметок", "Marker palette"),
        ("Сделать скриншот", "Take a screenshot"),
        // [ТЗ№4 C8, E1] The shortcut saves the whole screen wherever the captures go, and the row
        // says what it takes rather than where it puts it (`tasks/tz-005-plan.md` §3).
        ("Снимок всего экрана", "Whole-screen capture"),
        ("Формат", "Format"),
        ("Папка сохранения", "Save folder"),
        ("Выбрать папку", "Choose folder"),
        (
            "Качество JPEG: {0} % (меньше, легче файл)",
            "JPEG quality: {0} % (lower means a smaller file)"
        ),
        ("Сохранить", "Save"),
        ("Отмена", "Cancel"),
        ("Закрыть", "Close"),
        ("Нажмите своё сочетание клавиш", "Press your shortcut"),
        ("Нажми, чтобы изменить", "Click to change"),
        ("Добавь Cmd, Option или Shift", "Add Cmd, Option or Shift"),
        ("Уже занято", "Already taken"),
        // SPEC-DELTA-3 §4: the system that keeps a shortcut is named as the system here, and the
        // modifiers offered are the ones this keyboard has.
        ("Это сочетание занято системой", "The system keeps this shortcut"),
        (
            "Одно сочетание на два действия. Поменяй одно из них.",
            "One shortcut for two actions. Change one of them."
        ),
        ("Предложить: {0}", "Suggest: {0}"),
        ("Не назначено", "Not assigned"),
        ("Новый снимок", "New capture"),
        ("+ Снимок", "+ Capture"),
        ("Готово", "Done"),
        ("Выбор", "Select"),
        ("Область", "Region"),
        ("Стрелка", "Arrow"),
        ("Маркер", "Highlight"),
        ("Текст", "Text"),
        ("Ластик", "Eraser"),
        ("Размыть", "Blur"),
        ("Обрезать", "Crop"),
        ("Сочетания клавиш", "Keyboard shortcuts"),
        ("Инструменты", "Tools"),
        ("Действия", "Actions"),
        ("Отменить снимок", "Cancel the capture"),
        ("Закончить заметку", "Finish the note"),
        ("Новая строка в заметке", "New line in the note"),
        ("Цвет отметки", "Annotation color"),
        ("Толщина", "Thickness"),
        ("Карандаш", "Pencil"),
        ("Размер", "Size"),
        ("Размер шрифта", "Font size"),
        ("Цвет", "Color"),
        ("Цвет HEX", "HEX color"),
        ("Толщина линии", "Line thickness"),
        ("Линия", "Line"),
        ("Тип линии", "Line style"),
        ("Сплошная", "Solid"),
        ("Пунктир", "Dashed"),
        ("Точки", "Dotted"),
        ("Стандартная", "Standard"),
        ("Пастель", "Pastel"),
        ("Своя", "Custom"),
        ("Оттенок", "Hue"),
        ("Насыщенность и яркость", "Saturation and brightness"),
        ("Пипетка", "Eyedropper"),
        ("Взять цвет с экрана", "Pick a color from the screen"),
        ("Сохранённые цвета", "Saved colors"),
        ("Выделите область · Esc отменяет", "Select an area · Esc cancels"),
        ("СНИМОК {0}", "CAPTURE {0}"),
        ("Добавить комментарий", "Add comment"),
        ("Удалить комментарий", "Remove comment"),
        ("Переместить заметку", "Move the note"),
        ("Отменить", "Undo"),
        ("Повторить", "Redo"),
        ("Комментарий", "Comment"),
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
        ("Фигура", "Shape"),
        ("Прямоугольник", "Rectangle"),
        ("Скруглённый прямоугольник", "Rounded rectangle"),
        ("Овал", "Ellipse"),
        ("Заливка", "Fill"),
        ("Контур", "Outline"),
        ("Сплошная заливка", "Solid fill"),
        ("Полупрозрачная заливка", "Translucent fill"),
        ("Заливка размытием", "Blurred fill"),
        ("Рамка", "Frame"),
        ("Цвет заливки", "Fill color"),
        ("Сохранить на компьютер", "Save to computer"),
        ("Свернуть в трей", "Hide to tray"),
        ("Ещё", "More"),
        ("Свернуть в капсулу", "Collapse to a capsule"),
        ("Развернуть ленту", "Expand the strip"),
        ("Удалить", "Delete"),
        ("Открыть снимок", "Open capture"),
        ("Вернуть", "Restore"),
        ("Показать ленту", "Show the strip"),
        ("Запускать с Windows", "Start with Windows"),
        ("Выйти", "Exit"),
        ("Snapik — Лента снимков", "Snapik — Capture strip"),
        ("Очистить ленту", "Clear the strip"),
        ("Лента очищена", "Strip cleared"),
        (
            "В ленте максимум {0} снимков. Отправьте или удалите лишние",
            "The strip holds at most {0} captures. Paste or delete some first."
        ),
        (
            "Чаты обычно принимают до {0} картинок за раз",
            "Chats usually take up to {0} images at a time"
        ),
        ("Удалить снимки сессии?", "Delete the captures of this session?"),
        (
            "Снимки этой сессии будут удалены. Чтобы сохранить, нажмите «Сохранить пакет…» в меню •••",
            "The captures of this session will be deleted. To keep them, use \"Save package…\" in the ••• menu."
        ),
        ("Больше не спрашивать", "Do not ask again"),
        ("Очищать ленту после вставки", "Clear the strip after pasting"),
        ("Копировать пакет", "Copy package"),
        ("Сохранить пакет…", "Save package…"),
        ("Импортировать файл…", "Import file…"),
        ("Вставить изображение из буфера", "Paste image from clipboard"),
        ("Вернуть удалённый снимок", "Restore deleted capture"),
        ("Сохранить пакет", "Save package"),
        ("Куда", "Where"),
        ("Обзор…", "Browse…"),
        ("Имя папки", "Folder name"),
        ("Создать подпапку", "Create a subfolder"),
        (
            "В папку лягут снимки и prompt.md, текст с комментариями для ИИ",
            "The folder takes the captures and prompt.md, the text with the comments for the AI"
        ),
        (
            "Снимки в пакете нумеруются заново: A, B, C…",
            "The captures in the package are lettered again: A, B, C…"
        ),
        ("Укажите имя папки.", "Enter a folder name."),
        (
            "В имени папки есть недопустимые символы.",
            "The folder name contains characters that are not allowed."
        ),
        (
            "Укажите полный путь к папке, например C:\\Users\\Public\\Pictures.",
            "Enter a full path to the folder, for example C:\\Users\\Public\\Pictures."
        ),
        (
            "Этот путь не подходит. Выберите папку кнопкой обзора.",
            "This path cannot be used. Choose the folder with the browse button."
        ),
        (
            "В этой папке нет свободного имени для пакета. Выберите другую папку.",
            "There is no free name for the package in this folder. Choose another folder."
        ),
        ("Не удалось сохранить пакет", "Could not save the package"),
        ("Горячие клавиши…", "Settings…"),
        ("Настройки клавиш", "Shortcut settings"),
        ("Снимок сохранён", "Capture saved"),
        ("Снимки скопированы", "Captures copied"),
        ("Скопировано", "Copied"),
        ("Изображения и комментарии готовы к вставке", "Images and comments are ready to paste"),
        (
            "Снимки сохранены, но вставка не завершена",
            "Captures were saved, but pasting did not finish"
        ),
        (
            "Вставлено: {0} изображений · {1} заметок. Снимки помечены как отправленные",
            "Pasted: {0} images · {1} notes. The captures are marked as sent"
        ),
        (
            "Пакет вытеснен другим приложением. Сессия сохранена.",
            "Another app replaced the package. The session was saved."
        ),
        ("Изображения", "Images"),
        ("Все файлы", "All files"),
        ("Все поддерживаемые", "All supported"),
        ("Выберите PNG или JPEG.", "Choose PNG or JPEG."),
        ("Добавлено снимков: {0}", "Captures added: {0}"),
        ("Изображение добавлено.", "Image added."),
        ("В буфере нет изображения.", "There is no image on the clipboard."),
        ("Не удалось добавить", "Could not add"),
        ("Формат не поддерживается системой", "The system does not support this format"),
        ("Поверх других окон", "Always on top"),
        ("Не удалось сохранить настройки", "Could not save the settings"),
        ("Файл настроек не читается.", "The settings file cannot be read."),
        (
            "Файл настроек не читался, настройки созданы заново",
            "The settings file could not be read, the settings were created anew"
        ),
        ("Снимок удалён", "Capture removed"),
        ("Снимок восстановлен.", "Capture restored."),
        ("Порядок снимков изменён.", "Capture order changed."),
        ("Пакет сохранён.", "Package saved."),
        ("Готово: {0} изображений · {1} заметок", "Ready: {0} images · {1} notes"),
        ("Не удалось изменить автозапуск", "Could not change the startup setting"),
        ("Не удалось восстановить сессию", "Could not restore the session"),
        ("Захват", "Capture"),
        ("Отслеживание вставки недоступно", "Paste tracking is unavailable"),
        ("Сочетание занято", "The shortcut is taken"),
        ("захват", "capture"),
        ("сохранение экрана", "screen saving"),
        (
            "Не удалось подтвердить содержимое текущего пакета. Сессия сохранена.",
            "Could not confirm what the current package holds. The session was saved."
        ),
        (
            "Вставка замечена, но лента не обновлена",
            "The paste was noticed, but the strip was not updated"
        ),
        ("Захват не завершён", "The capture did not finish"),
        ("Сначала сделайте снимок.", "Take a capture first."),
        (
            "Все снимки уже отправлены. Сделайте новый снимок.",
            "Every capture was already sent. Take a new one."
        ),
        (
            "Регистрация клавиш недоступна. Перезапустите Snapik.",
            "Shortcut registration is unavailable. Restart Snapik."
        ),
        (
            "Эта клавиша уже занята. Освободите её в другом приложении или выберите другую.",
            "This shortcut is already taken. Free it in the other application or pick another one."
        ),
        (
            "Не удалось назначить сочетание. Возможно, оно уже занято — нажмите другое.",
            "Could not assign the shortcut. It may already be taken — press another one."
        ),
        ("Готовим PNG и текст…", "Preparing the PNG and the text…"),
        ("Не удалось подготовить", "Could not prepare"),
        (
            "Снимок сохранён, но буфер не обновлён",
            "The capture was saved, but the clipboard was not updated"
        ),
        ("Повторите копирование через меню.", "Copy the package again from the menu."),
        ("Вставка остановлена", "Pasting stopped"),
        ("Не удалось выполнить действие", "Could not run the action"),
        (
            "PNG и текст скопированы. Если получатель выберет один формат, используйте кнопку вставки.",
            "The PNG and the text were copied. If the receiver takes only one format, use the paste button."
        ),
        ("PNG и текст скопированы.", "The PNG and the text were copied."),
        ("Не удалось сохранить", "Could not save"),
        ("Не удалось очистить ленту", "Could not clear the strip"),
        ("Буфер не обновлён", "The clipboard was not updated"),
        ("Шаг {0} из {1}", "Step {0} of {1}"),
        ("Назад", "Back"),
        ("Далее", "Next"),
        ("Начать", "Get started"),
        ("Пропустить", "Skip"),
        // The wizard is an ordinary window now: it has a header of its own, and the header
        // minimizes.
        ("Свернуть", "Minimize"),
        ("Пропустить настройку", "Skip setup"),
        ("Выдели. Прокомментируй. Отправь.", "Select. Comment. Send."),
        (
            "Скриншотер для одной задачи: несколько снимков с заметками — и сразу в дело. В чат с ИИ, в мессенджер, в письмо, в задачу.",
            "A screenshot tool for one task: a few captures with notes, ready to use straight away. In an AI chat, a messenger, an email, a ticket."
        ),
        // The words inside the drawings: they are read, so they are translated, and the smoke run
        // sweeps them together with the rest of the wizard.
        ("Кнопку ярче", "Make the button brighter"),
        ("Убрать блок", "Drop this block"),
        ("Чат", "Chat"),
        ("Снимок A", "Capture A"),
        ("Снимок B", "Capture B"),
        ("Снимок C", "Capture C"),
        ("Как на первом", "Same as the first one"),
        ("Текст…", "Message…"),
        ("Чтобы всегда был под рукой", "So it is always at hand"),
        (
            "Два переключателя — и Snapik не придётся искать.",
            "Two switches, and you will never have to look for Snapik."
        ),
        (
            "Ждёт в углу экрана, клавиша работает сразу",
            "It waits in the corner of the screen, the shortcut works right away"
        ),
        (
            "Иконка внизу экрана, клик открывает ленту",
            "An icon at the bottom of the screen, a click opens the strip"
        ),
        ("Закрепить", "Pin"),
        ("Закреплено", "Pinned"),
        (
            "Готово: иконка Snapik теперь на панели задач",
            "Done: the Snapik icon is on the taskbar now"
        ),
        ("Открой «Пуск»", "Open Start"),
        ("Нажми правой кнопкой на Snapik", "Right-click Snapik"),
        ("Выбери «Закрепить на панели задач»", "Choose \"Pin to taskbar\""),
        ("Как будет выглядеть", "How it will look"),
        (
            "Нажми — окно сразу перекрасится. Поменять можно в любой момент в настройках.",
            "Click and the window repaints at once. You can change it any time in the settings."
        ),
        ("Язык интерфейса", "Interface language"),
        ("Клавиша для снимка", "The capture shortcut"),
        ("Нажми на поле и введи своё сочетание", "Click the field and press your own shortcut"),
        ("Автозапуск недоступен", "Autostart is unavailable"),
        ("Закрепить на панели задач", "Pin to taskbar"),
        ("Как пользоваться", "How it works"),
        ("Предыдущий слайд", "Previous slide"),
        ("Следующий слайд", "Next slide"),
        ("Слайд {0} из {1}", "Slide {0} of {1}"),
        // The four slides: the name of each and the lines that appear under it one after another.
        ("Снимок с комментариями", "A capture with comments"),
        ("Несколько снимков сразу", "Several captures at once"),
        ("Открыть снимок снова", "Open a capture again"),
        ("Лента снимков", "The capture strip"),
        (
            "Выдели область экрана, которую хочешь снять.",
            "Select the part of the screen you want to capture."
        ),
        (
            "Поставь комментарии там, где удобно — сколько нужно.",
            "Put comments wherever you like, as many as you need."
        ),
        (
            "Ctrl+V в любой чат — картинка и комментарии вставятся вместе.",
            "Ctrl+V into any chat, and the picture and the comments go in together."
        ),
        ("Сделай несколько снимков подряд.", "Take several captures one after another."),
        (
            "Все они собираются в ленту у края экрана.",
            "They all gather into the strip at the edge of the screen."
        ),
        ("У каждого — свои комментарии.", "Each one keeps its own comments."),
        (
            "Ctrl+V — и вся пачка уходит одним сообщением.",
            "Ctrl+V, and the whole batch goes as one message."
        ),
        ("Каждый снимок хранит свои комментарии.", "Every capture keeps its own comments."),
        (
            "Клик по снимку в ленте — он открывается снова, всё на месте.",
            "Click a capture in the strip and it opens again, with everything in place."
        ),
        (
            "Поправь и закрой — изменения останутся в ленте.",
            "Fix it and close it, the changes stay in the strip."
        ),
        (
            "Лента живёт, пока открыта. Закроешь — снимки удалятся.",
            "The strip lives while it is open. Close it and the captures are gone."
        ),
        (
            "Сохранить — «Сохранить пакет…», или включи автосохранение в папку.",
            "To keep them, use \"Save package…\", or switch on auto-saving to a folder."
        ),
        (
            "Мешает — сверни в капсулу, клик разворачивает обратно.",
            "In the way? Collapse it into the capsule, a click opens it again."
        ),
        (
            "Лишний снимок — крестик. Всё сразу — «Очистить».",
            "One capture too many: the cross. All of them: \"Clear\"."
        ),
        // SPEC-DELTA-3 §3.3: the pairs Windows no longer has. The preview window that
        // owned the first of them is gone (W0-6); the rest are still read by the
        // settings, the editor and the strip, and leave with the code of wave 1.
        ("Уведомления о копировании и сохранении", "Notify on copy and save"),
        ("Запоминать последнюю область", "Remember the last region"),
        ("Захватывать курсор", "Capture the cursor"),
        ("Звуки захвата и стопки", "Capture and stack sounds"),
        ("Захват области", "Capture region"),
        ("Быстро сохранить весь экран", "Instantly save the full screen"),
        ("Качество JPEG", "JPEG quality"),
        ("Нажмите клавишу…", "Press a key…"),
        ("Перо", "Pen"),
        ("Скрыть", "Conceal"),
        ("Ещё инструменты", "More tools"),
        ("Цвет и толщина", "Color and thickness"),
        ("Добавить комментарий (N)", "Add comment (N)"),
        ("Закрыть ввод текста", "Close text editor"),
        ("Сохранить на компьютер (Ctrl+S)", "Save to computer (Ctrl+S)"),
        ("Показать стопку", "Show stack"),
        (
            "Вставлено: {0} изображений · {1} заметок. Пакет остаётся в буфере, следующий снимок начнёт новую стопку",
            "Pasted: {0} images · {1} notes. The package stays on the clipboard, the next capture will start a new stack"
        ),
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
