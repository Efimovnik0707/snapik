# Дельта №5, порция «Core + Settings + Onboarding + App/Smoke»: Windows `d84fbb0..f2cf62b` → macOS

**База.** `mac-sync-base-4` = `d84fbb0` (Windows 1.5.0). Цель раунда: `f2cf62b` (Windows 1.7.0).
Диапазон: два раунда ТЗ подряд — 1.6.0 (`tasks/tz-006-*`, база `d84fbb0..1df53ce`) и 1.7.0
(`tasks/tz-007-*`, `1df53ce..f2cf62b`); по `src` + `tests` 52 файла, +4571 / −1199.

**Зона этой спеки.** Windows: `src/Snapik.Core/**`, `src/Snapik.Infrastructure/Exporting/FileExportService.cs`
и из `src/Snapik.App` — `HotkeySettings.cs`, `SettingsMigration.cs`, `HotkeySettingsWindow.*`,
`Controls/AppearancePicker.*`, `OnboardingWindow.*`, `UiLanguage.cs`, `UiSoundService.cs`,
`SoundVolumeCurve.cs`, `ToolAppearance.cs` (модель и хранилище), `App.xaml.cs`, `SessionWorkspace.cs`,
`PublishedPackage.cs`, `SmokeTestRunner.cs`; тесты `tests/Snapik.Core.Tests`,
`tests/Snapik.App.Imaging.Tests` (кроме ленты и редактора), `tests/Snapik.Windows.Tests`.
Swift: `macos/Sources/SnapikCore/**`, `macos/Sources/SnapikMac/{Settings,Onboarding,App}/**`,
`macos/Tests/SnapikCoreTests/**`.

**Не эта спека.** Лента (`EdgeStackWindow.*`, `Stack/`) — порция `stack`; редактор и рендер
(`OverlayEditorWindow.*`, `AnnotationCanvas`, `Imaging/*`, `EditorGeometry`, `ToolbarLayout`,
`Editor/`, `Imaging/`) — порция `editor`. Чистые функции Core, которыми они пользуются, описаны
здесь как контракт волны 0 (§4), поведение окон — у них.

Все ссылки Windows — по `f2cf62b`. Все ссылки Swift — по `master` дерева `macos/` на момент
написания (тег `mac-sync-base-4`).

Объём: **S** ≤ 60 строк Swift, **M** 60–250, **L** > 250.

---

## 0. Резюме

### 0.1 Уже есть на Mac — переносить нечего

Проверено по коду, а не по спекам:

- **`SettingsMigration` целиком.** `Settings/SettingsMigration.swift:9` уже `currentVersion = 2`,
  `soundVolume(storedVersion:storedVolume:)` :28 спрашивает `< 1`, `theme(storedVersion:storedTheme:)`
  :37 спрашивает `< 2`. Windows в этом раунде файл `SettingsMigration.cs` **не трогал** — дельта пуста,
  версия остаётся 2 (см. §1.2).
- **Флаг `placed` мастера.** `Onboarding/OnboardingWindowController.swift:41`, ставится в `place(_:)`
  :204, `windowDidChangeScreen` :626 — только страховка. Это T-3 дельты №4, сделано.
- **`mergeOnboarding(stored:candidate:)`** — `OnboardingWindowController.swift:431`, зовётся :474 и из
  смоука `SmokeTestRunner+Settings.swift:179`. Windows в раунде его не менял.
- **`OnboardingVersion`.** Windows намеренно не поднимал (`tz-006-notes.md`, «Волна 2»);
  `OnboardingWindowController.swift:16` `currentVersion = 3` совпадает — не трогать.
- **Гейны трёх звуков** `0.6 / 0.25 / 0.7` — `App/UiSoundService.swift:19-21`, у Windows те же
  (`UiSoundService.cs:22-24`), в раунде не менялись. Меняется только кривая (§1.4).
- **`«Пройти знакомство заново»`** через таблицу — `SettingsTabViews.swift:96` уже
  `MacUiText.text(...)`; T-2 дельты №4 сделано.
- **Геометрия ленты 244 / 0 / 160 / 180 / 372** — `Geometry/StripResizeGeometry.swift:19-39`. В раунде
  Windows эти числа не менял.

### 0.2 Переносится

| # | Что | Раунд | Объём |
|---|---|---|---|
| C5-1 | Ключ `StackHeightManual` в `HotkeySettings` | 1.7.0 | S |
| C5-2 | Ключ `toolAppearance` и тип `ToolAppearanceEntry` в `HotkeySettings` | 1.6.0 | M |
| C5-3 | `ToolAppearanceStore.read/write` (шесть наборов инструментов и зеркало старых ключей) | 1.6.0 | M |
| C5-4 | Константы списка и четыре чистые функции `StripResizeGeometry` (`listHeightForCount`, `listHeight`, `capsuleLeft`, `restoreRect`) | 1.6.0 + 1.7.0 | M |
| C5-5 | `UiLanguage`: 12 добавить, 9 снять (из них 5 — только после смежных порций) | оба | S |
| C5-6 | `SoundVolumeCurve.amplitude(volume:gain:)` и переход `UiSoundService` на неё | 1.7.0 | S |
| C5-7 | `PromptGenerator(singleCaptureLabel:)` и `FileExportService(..., singleCaptureLabel:)` | 1.7.0 | S |
| C5-8 | `SessionWorkspace.exportSingle(capture:label:)` | 1.7.0 | S |
| C5-9 | Признак «одиночная публикация» и правило `clearsTheStrip(published:clearStackAfterPaste:)` | 1.7.0 | S |
| S5-1 | Высота окна настроек 620 (и смоук, который её меряет) | 1.7.0 | S |
| S5-2 | Число справа от ползунка громкости и тик через таймер 150 мс на временных настройках | 1.7.0 | M |
| S5-3 | Четвёртый сегмент «Неон» в ряду палитр и белый список `selectedPalette` | 1.7.0 | S |
| S5-4 | Конец ряда галереи тем — метка, а не выключенность; кламп `firstCard` при смене ширины | 1.6.0 | S |
| A5-1 | Проба «вкладки настроек влезают в окно» (+ число громкости, + ряд палитр против списка редактора) | 1.7.0 | M |
| A5-2 | Проба «буква одиночного пакета доезжает до файла и до `prompt.md`» | 1.7.0 | S |
| A5-3 | Правки существующей пробы round-trip настроек (новые ключи, четыре палитры, `quick` снят) | оба | S |
| A5-4 | Правки языковой таблицы смоука | оба | S |

### 0.3 Не переносится

- **`TaskbarPinLegacy.cs` целиком, `TaskbarPinService.CarryOverLegacyPin`, строка `PinCarryOver`
  шага 3 мастера, три пары `UiLanguage` про значок на панели задач, проба
  `VerifyALegacyPinIsCarriedOver`.** Закреп на панели задач, `IShellLink`/`IPropertyStore`/AUMID и
  `IPinnedList3.LegacyModify` — это Windows. На macOS приложение живёт в строке меню и в Dock, старого
  имени `SnapBrief` в Dock не остаётся как отдельного закрепа, перенацеливать нечего. Сами три
  русские строки в таблицу Mac **не добавлять**: они называют Windows дословно
  (`«Подпись на панели задач обновится после перезахода в Windows»`).
- **`VerifyALayeredWindowMinimisesAsync`** (`SmokeTestRunner.cs:1506`) — `WS_MINIMIZEBOX`,
  `ShowWindow(SW_SHOWNOACTIVATE)`, `ShowInTaskbar`. Windows-only; окно ленты на Mac сворачивается
  иначе, это зона `stack`.
- **`TraceDpiChange` и `GetWindowRect`** (`OnboardingWindow.xaml.cs:162-213`) — трасса `WM_DPICHANGED`
  в `startup.log` заведена ради живого прогона, который нельзя воспроизвести на агенте. Аналог
  сигнала на Mac (`windowDidChangeScreen`) уже есть, а сам дефект на Mac не воспроизводится (§1.7),
  поэтому трасса не нужна. `DescribeGallery()`/`DescribeChevronHit()` не переносить.
- **`installer/Snapik.iss`** (табуляция в `{sys}\taskkill.exe`) — установщик Windows.
- **`SingleInstanceActivation`, `DwmWindowCorners`, `WindowsStartupService`** — в раунде не менялись и
  не переносятся по прежним решениям.

---

## 1. По подсистемам

### 1.1 Ключи настроек обоих раундов (а)

Сверено построчно: `git show d84fbb0:src/Snapik.App/HotkeySettingsWindow.xaml.cs` (запись
`HotkeySettings` жила там) против `src/Snapik.App/HotkeySettings.cs` на `f2cf62b`.

**Состав полей изменился ровно на два.** Все остальные 33 свойства, их типы и дефолты совпадают
байт в байт; `DefaultFullscreenSaveId = "custom:7:83"`, `MaxCustomPaletteColors = 12`,
`CurrentSettingsVersion = SettingsMigration.CurrentVersion`, `Choices`/`PasteChoices`, `Find`,
`TryRead`, `Save`, `KeepPaletteColors` — без изменений по смыслу. Переезд записи из
`HotkeySettingsWindow.xaml.cs` в новый `src/Snapik.App/HotkeySettings.cs` (коммит `2456fde`,
W0-0) — организационный: на Mac запись **уже** живёт отдельно в
`Sources/SnapikCore/Settings/HotkeySettings.swift`, переносить нечего.

#### C5-1 `StackHeightManual`

- **Windows:** `HotkeySettings.cs:53` (`public bool StackHeightManual { get; init; }`), коммит
  `7789ae6` (B-4, ТЗ B3). Документирующий комментарий `:47-52`.
- **Mac-цель:** `Sources/SnapikCore/Settings/HotkeySettings.swift` — четыре места:
  - поле после `stackHeight` (`:68`): `public var stackHeightManual: Bool = false`;
  - `CodingKeys` после `case stackHeight = "StackHeight"` (`:331`): `case stackHeightManual = "StackHeightManual"`;
  - `init(from:)` после `:377`: `stackHeightManual = try container.decodeIfPresent(Bool.self, forKey: .stackHeightManual) ?? false`;
  - `encode(to:)` после `:419`: `try container.encode(stackHeightManual, forKey: .stackHeightManual)`.
- **Смысл:** `false` — прежнее поведение, `StackHeight` это потолок, список стоит по содержимому.
  `true` — то же число становится высотой списка, пол `minimumListHeight = 180`, потолок рабочей
  области через `clampListHeight`. Двойной клик по ручке угла возвращает `false`.
  `SettingsMigration.currentVersion` не поднимается (§2.2).
- **Вызывающие на Mac:** читает `Stack/EdgeStackWindowController.swift:236-237` (там сейчас
  `StripResizeGeometry.clampListHeight(settings.stackHeight, …)`), пишет `:321`
  (`settings.stackHeight = listHeight`). Обе точки — зона `stack`; от меня только ключ и обе ветки
  `StripResizeGeometry.listHeight(count:stored:manual:)` (§1.10, §4).
- **Ловушка Swift.** `HotkeySettings` на Mac `Equatable`, и `tryRead` (`:287`) считает
  `migrated = settings != stored`. Новое булево поле с дефолтом `false` сравнение не ломает:
  файл без ключа декодится в `false`, и `stored == settings`. Порядок ключей в
  `CodingKeys`/`encode` держать тем же, что на Windows, чтобы diff файла оставался читаемым.

#### C5-2 Ключ `toolAppearance` и `ToolAppearanceEntry`

- **Windows:** `HotkeySettings.cs:112-116` (`[JsonPropertyName("toolAppearance")]`,
  `Dictionary<string, ToolAppearanceEntry>`, пустой словарь — один общий экземпляр
  `NoToolAppearance`), `KeepToolAppearance` `:266`, участие в `migrated` `:191-197`; сам тип —
  `src/Snapik.App/ToolAppearance.cs:36-49`. Коммит `11e8948` (W0-5).
- **Mac-цель:** новый тип в `Sources/SnapikCore/Settings/` (рядом с `HotkeySettings.swift`) либо в
  самом файле; и четыре места в `HotkeySettings.swift`, как у C5-1, но с ключом в camelCase:

```swift
/// Форма одного инструмента в settings.json. Отдельная запись, а не сам набор настроек:
/// файл держит цвета как "#RRGGBB" и перечисления по именам.
public struct ToolAppearanceEntry: Codable, Equatable, Sendable {
    public var color: String?
    public var thickness: Double?
    public var lineStyle: String?
    public var fill: String?
    public var fillColor: String?      // null = «как обводка»
    public var fontSize: Double?
    public var arrowStyle: String?
    public var shape: String?
    enum CodingKeys: String, CodingKey {
        case color, thickness, lineStyle, fill, fillColor, fontSize, arrowStyle, shape
    }
}
```

  В `HotkeySettings`: `public var toolAppearance: [String: ToolAppearanceEntry] = [:]`,
  `case toolAppearance = "toolAppearance"` (единственный camelCase-ключ среди PascalCase — так
  решено на Windows осознанно, `tz-006-notes-0.md`, «Ключ в JSON один camelCase среди PascalCase»),
  `decodeIfPresent(...) ?? [:]`, `try container.encode(toolAppearance, forKey: .toolAppearance)`.
- **Ловушки Swift.**
  1. **`KeepToolAppearance` на Mac не нужен.** В C# словарь и массив сравниваются по ссылке, и без
     нормализации пустого словаря к одному экземпляру каждый старт переписывал бы `settings.json`.
     В Swift `[String: ToolAppearanceEntry]` и `[String]` сравниваются структурно, поэтому
     `settings != stored` не сработает на пустом словаре. Ничего нормализовать не надо; неизвестный
     инструмент выбрасывается не при чтении файла, а в `ToolAppearanceStore.read` (C5-3), ровно как
     на Windows.
  2. **`fillColor` должен исчезать из файла, когда он `nil`.** На Windows это
     `[JsonIgnore(Condition = WhenWritingNull)]` (`ToolAppearance.cs:42`). `JSONEncoder` в Swift
     пишет `Optional.none` как отсутствие ключа **только** при синтезированном `encode`; если
     писать `encode(to:)` руками — брать `encodeIfPresent`, иначе появится `"fillColor": null`, что
     читается так же, но расходится с файлом Windows побайтно.
  3. **Порядок ключей.** `JSONEncoder` без `.sortedKeys` пишет в порядке `CodingKeys`; держать тот
     же порядок, что в `ToolAppearanceEntry` на Windows.

#### C5-3 `ToolAppearanceStore`

- **Windows:** `src/Snapik.App/ToolAppearance.cs:12-29` (запись `ToolAppearance` с дефолтами),
  `:51-155` (`ToolAppearanceStore.Tools/Read/Write/Apply/EntryOf/TryParseTool/ParseEnum/NameOf/CamelCase/Hex/ParseColor`).
- **Mac-цель:** новый `Sources/SnapikMac/Editor/ToolAppearanceStore.swift`.
  **Почему не в Core:** `EditorTool` объявлен в `Sources/SnapikMac/Editor/EditorModels.swift:7`,
  Core его не видит; `ToolAppearanceEntry` (Codable-форма файла) остаётся в Core, а словарь
  `[EditorTool: ToolAppearance]` — в `SnapikMac`. Точно та же развилка, что на Windows
  (`HotkeySettings` публичная, `ToolAppearance` internal).
- **Целевые сигнатуры:**

```swift
struct ToolAppearance: Equatable {
    static let defaultColor = NSColor(srgbRed: 1.0, green: 59/255, blue: 48/255, alpha: 1) // #FF3B30
    static let defaultThickness: Double = 4
    var color: NSColor = ToolAppearance.defaultColor
    var thickness: Double = ToolAppearance.defaultThickness
    var lineStyle: AnnotationLineStyle = .solid
    var fill: AnnotationFill = .none
    var fillColor: NSColor?            // nil = «как обводка»
    var fontSize: Double = TextMarkMetrics.defaultFontSize
    var arrowStyle: String = "straight"
    var shape: AnnotationShape = .rectangle
}

enum ToolAppearanceStore {
    static let tools: [EditorTool] = [.rectangle, .arrow, .pen, .highlight, .text, .blur]
    static func read(_ settings: HotkeySettings) -> [EditorTool: ToolAppearance]
    static func write(_ settings: HotkeySettings, tools: [EditorTool: ToolAppearance]) -> HotkeySettings
}
```

- **Правила, которые переносятся дословно:**
  - `read` сперва раздаёт **всем шести** инструментам общие старые ключи: `annotationColor`,
    `annotationThickness` (у `.highlight` — `annotationHighlightThickness`), `annotationFontSize`.
    Файл без `toolAppearance` открывается ровно так, как выглядел в 1.5.0.
  - Затем поверх ложится то, что в словаре. Неизвестное имя инструмента пропускается молча.
  - `write` пишет все шесть и **зеркалит** в старые ключи: цвет и толщину рамки → `annotationColor` /
    `annotationThickness`, толщину маркера → `annotationHighlightThickness`, кегль текста →
    `annotationFontSize`. Файл, записанный этой версией, читается 1.5.0 целиком.
- **Ловушка Swift — главная.** `EditorTool.rawValue` на Mac это **буква горячей клавиши**
  (`EditorModels.swift:8-23`: `.rectangle = "R"`, `.arrow = "A"`, `.pen = "P"`, `.highlight = "H"`,
  `.text = "T"`, `.blur = "B"`). Использовать `rawValue` как ключ JSON **нельзя** — в файл уедут
  `"R"`, `"A"`, и Windows такой файл не поймёт. Нужна отдельная таблица имён:

```swift
private static let names: [EditorTool: String] = [
    .rectangle: "rectangle", .arrow: "arrow", .pen: "pen",
    .highlight: "highlight", .text: "text", .blur: "blur"
]
```

  и обратный разбор по ней же, с `lowercased()` перед сравнением (Windows парсит
  `ignoreCase: true`).
- **Ловушка Swift — вторая.** `AnnotationShape`, `AnnotationFill`, `AnnotationLineStyle` на Mac уже
  `String`-enum с нужными rawValue (`Models/AnnotationItem.swift:18-41`: `rectangle/rounded/ellipse`,
  `none/solid/translucent/blur`, `solid/dashed/dotted`) — это ровно то, что Windows получает из
  `CamelCase(value.ToString())`. Но `init(rawValue:)` регистрозависим, а Windows терпит `"Rounded"`
  из руками правленного файла: писать `AnnotationShape(rawValue: value.lowercased()) ?? fallback`.
  И отдельный шаг Windows «цифра — не имя» (`ParseEnum`, `!char.IsDigit(value[0])`) в Swift
  получается сам собой: `AnnotationShape(rawValue: "2")` даёт `nil`.
- **Цвет.** `Hex(Color)` на Windows это `#RRGGBB` без альфы. На Mac — через `NSColor` в
  `sRGB`-пространстве; в дереве уже есть `SnapikCore/Editing/ColorConversion.swift`, брать его, а не
  писать третий разбор HEX.
- **Не моя зона.** `InspectorView`, `SecondCapsule`, `EditorInspector.inspectorViewOf/inspectedTool`
  лежат в том же файле `ToolAppearance.cs:157-193`, но это поведение инспектора редактора —
  порция `editor` (там же tz-007 C2: у размытия `SecondCapsule.None`,
  `ToolAppearance.cs:180-181`). Она же читает `toolAppearanceStore` и решает, что помнит каждый
  инструмент (`OverlayEditorController.swift:85-98` сейчас держит один цвет и две толщины на всё).
  Передача — §4.

#### Чего в ключах **не** появилось

Проверено грепом по `f2cf62b`: `AnnotationShape`, `AnnotationFill`, `AnnotationFillColor`,
`AnnotationOutline` так и не вернулись (сняты дельтой №4). `PaletteSet.Quick` удалён из кода и в
файл никогда не писался — на Mac `EditorPalette.quick` (`Editor/EditorAppearanceModel.swift:61-66`)
живёт только в памяти, снимать его — зона `editor`, формата это не касается.
`AnnotationPalette` остался `String` с дефолтом `"standard"`; меняется только множество допустимых
значений — прибавилось `"neon"` (§1.6, S5-3).

### 1.2 `SettingsMigration` (б)

**Версия осталась 2.** `src/Snapik.App/SettingsMigration.cs` в диапазоне `d84fbb0..f2cf62b`
**не менялся** (`git diff --name-status` его не показывает), `CurrentVersion = 2`,
`DefaultSoundVolume = 40`, `PreviousDefaultSoundVolume = 60`, оба порога (`< 1` у громкости,
`< 2` у темы) на месте. Абзац «Изменение формата» tz-007 говорит то же прямым текстом:
«`SettingsMigration.CurrentVersion` остаётся 2».

Оба новых ключа раунда аддитивны и мигрируются **по отсутствию ключа**, а не по версии:
`StackHeightManual` отсутствует → `false` (прежнее поведение); `toolAppearance` отсутствует → каждый
инструмент берёт старые общие значения. Поднимать версию нельзя: это прогнало бы правило темы по
файлам, которые её уже пережили.

`Sources/SnapikCore/Settings/SettingsMigration.swift` править **не нужно**. Единственная правка
рядом — `HotkeySettings.migrate(_:)` (`:238-247`) трогать тоже не нужно: новые поля миграция не
касается.

### 1.3 Пары `UiLanguage` обоих раундов (в)

Diff `src/Snapik.App/UiLanguage.cs`: **+12 пар, −9 пар**. На Windows после сведения 289 пар.

#### Добавить (12)

**Раунд 1.6.0 — 8 пар, в самом конце Windows-части таблицы, сразу после
`("Добавить цвет в свою палитру", …)`** (`UiLanguage.cs:199-208`):

```
// The strings of the 1.6.0 round: the taskbar pin carried over from SnapBrief, the drag
// handle of the markup panel and the words of the properties block beside it.
("На панели задач остался старый значок SnapBrief. Нажми на него правой кнопкой и выбери «Открепить от панели задач»",
 "An old SnapBrief icon is still on the taskbar. Right-click it and choose \"Unpin from taskbar\"")   ← НЕ переносить
("Старый значок SnapBrief теперь открывает Snapik", "The old SnapBrief icon opens Snapik now")        ← НЕ переносить
("Подпись на панели задач обновится после перезахода в Windows",
 "The taskbar label will update after you sign out and back in")                                      ← НЕ переносить
("Панель разметки", "Markup panel")
("Обводка", "Stroke")
("Скруглённый", "Rounded")
("Нет", "None")
("Неон", "Neon")
```

Три первые — §0.3, закреп на панели задач. **На Mac добавляются пять пар**: `«Панель разметки»`,
`«Обводка»`, `«Скруглённый»`, `«Нет»`, `«Неон»`. Проверено: ни одной из пяти в
`Sources/SnapikCore/Settings/UiLanguage.swift` нет; ближайшее — `«Скруглённый прямоугольник»` (:170),
это другая пара, её не трогать.

**Место вставки на Mac:** `UiLanguage.swift:456`, сразу после
`("Добавить цвет в свою палитру", "Add the colour to my palette"),` и **до** комментария
SPEC-DELTA-3 §3.3 (:457-464) и macOS-блока (:465-472). Порядок Windows-части сохраняется.

**Раунд 1.7.0 — 4 пары**, на Windows стоят между `«Импортировать файл…»` и
`«Вставить изображение из буфера»` (`UiLanguage.cs:96-99`):

```
// The single capture of the 1.7.0 round: the context menu of a card, the button of the editor and the two answers to them.
("Копировать снимок", "Copy capture")
("Сохранить снимок…", "Save capture…")
("Снимок {0} скопирован", "Capture {0} copied")
("Не удалось скопировать снимок", "Could not copy the capture")
```

**Место вставки на Mac:** перед `UiLanguage.swift:210`
(`("Вставить изображение из буфера", "Paste image from clipboard"),`).

#### Изменить (0)

Ни одна существующая пара в этом раунде значения не сменила.

#### Снять — с оговорками

Windows убрал **9 пар**, у которых не осталось читателей в `src` (`tz-006-notes.md`, «Волна 2»).
На Mac читатели есть у пяти из девяти, поэтому список делится надвое.

**Снять сразу (2 пары, читателей на Mac нет):**

| Пара | Строка Mac |
|---|---|
| `("Цвет отметки", "Annotation color")` | `UiLanguage.swift:129` |
| `("Тип линии", "Line style")` | `UiLanguage.swift:138` |

`("+ Снимок", "+ Capture")` (`:113`) на Mac встречается только в комментариях кода
(`AppCoordinator.swift:71,79,337,351` и др.) — как *текст кнопки* не читается нигде. Снять, но
перед снятием проверить, что кнопка «ещё снимок» в редакторе подписывается другой парой
(`Editor/EditorStrings.swift`); если подписывается этой — оставить и записать отклонение.

**Снять только после смежных порций (3 пары):**

| Пара | Читатель на Mac | Чья порция |
|---|---|---|
| `("Толстая стрелка", "Bold arrow")` `:165` | `Editor/EditorStrings.swift:94` (`arrowBold`) | `editor` — наконечник «толстая» Windows снял раньше |
| `("По ширине · {0} %", "Fit width · {0} %")` `:454` | `Editor/EditorStrings.swift:68` | `editor` — переключатель масштаба снимает tz-006 C-1 |
| `("По высоте · {0} %", "Fit height · {0} %")` `:455` | там же | `editor` |

Все три снимаются **в волне сведения**, после того как порция `editor` уберёт своих читателей.
Снять их раньше — оставить редактор с русским текстом в английском интерфейсе.

**Не снимать (4 пары, у Mac свои читатели; записать как расхождение таблиц):**

| Пара | Читатель на Mac | Почему остаётся |
|---|---|---|
| `("Свернуть в трей", "Hide to tray")` `:179` | `MacUiText.swift:12` (перекрыта на «Свернуть в меню-бар» / "Hide to menu bar") и `Stack/EdgeStackContentView.swift:411` | Windows заменил кнопку шапки на «Свернуть» (сворачивание в панель задач). На macOS панели задач нет, лента прячется в строку меню, и ключ **остаётся** живым. Снятие сломало бы `MacUiText.overrides`. |
| `("Горячие клавиши…", "Settings…")` `:243` | `Settings/HotkeySettingsWindowController.swift:244` — accessibility-подпись вкладки | Либо оставить пару, либо перевести :244 на `«Настройки клавиш»` и снять. **Решение: перевести читателя и снять** — так таблицы сходятся, а подпись вкладки при этом становится точнее («Настройки клавиш» — это и есть заголовок вкладки). |
| `("Изображения и комментарии готовы к вставке", "Images and comments are ready to paste")` `:248` | `App/AppCoordinator+Package.swift:62` — текст уведомления | Оставить. У Mac уже есть задокументированный прецедент лишней пары (`UiLanguage.swift:457-464`, SPEC-DELTA-3 §3.3): пару держим, комментарий рядом пишем такой же. |

Итог по Mac: **+5 пар (1.6.0) +4 пары (1.7.0), −3 пары сразу (`Цвет отметки`, `Тип линии`,
`+ Снимок`), −3 пары в сведении после `editor`, 2 пары остаются сознательно**
(`Свернуть в трей`, `Изображения и комментарии готовы к вставке`).

#### Инварианты, которые надо держать

- Ни одного повторяющегося русского ключа и ни одного повторяющегося английского значения:
  обратный поиск `UiLanguage.text(_:language:"ru")` — это `englishPairs.first(where: { $0.1 == value })`
  (`UiLanguage.swift:483`), дубль ответит чужим ключом. `«Нет»` = `"None"` — проверить, что
  `"None"` больше нигде не стоит значением (на Windows проверено, на Mac таблица другая).
- `«Неон»` = `"Neon"` и `«Обводка»` = `"Stroke"` — оба слова короткие и рискуют совпасть с
  чем-то уже написанным; проверять скриптом, не грепом (Windows так и делал).
- `MacUiText.overrides` (`MacUiText.swift:11-14`) обратного поиска не знает: если новая пара
  когда-нибудь попадёт в overrides, обратный путь пойдёт мимо неё. Ни одна из девяти новых пар в
  overrides не попадает.

### 1.4 Звук (г)

#### C5-6 Квадратичная кривая

- **Windows:** новый `src/Snapik.App/SoundVolumeCurve.cs` (коммит `7f87e80`, W0-4):

```csharp
internal static double Amplitude(int volume, double gain)
{
    var level = Math.Clamp(volume, 0, 100) / 100.0;
    return level * level * Math.Clamp(gain, 0, 1);
}
```

  и одна строка в `UiSoundService.cs:93`: `player.Volume = SoundVolumeCurve.Amplitude(volume, gain);`
  вместо `Math.Clamp(volume, 0, 100) / 100.0 * gain`.
- **Mac-цель:** новый `Sources/SnapikCore/Settings/SoundVolumeCurve.swift` (Core, чтобы кривая
  покрывалась обычными тестами, а не только смоуком — та же причина, по которой в Core живёт
  `SettingsMigration`):

```swift
public enum SoundVolumeCurve {
    /// Ползунок настроек против того, что слышит ухо. Амплитуда, делённая надвое, это всего −6 дБ,
    /// поэтому линейный ползунок почти ничего не делал на первой половине хода. Квадрат тратит ход
    /// там, где ухо замечает: четверть хода даёт −24 дБ. Верх не трогается: на 100 ответ это микс
    /// самого звука, и «громче некуда» после обновления не двигается.
    public static func amplitude(volume: Int, gain: Double) -> Double {
        let level = Double(min(max(volume, 0), 100)) / 100.0
        return level * level * min(max(gain, 0), 1)
    }
}
```

- **Точка применения:** `Sources/SnapikMac/App/UiSoundService.swift:139` —
  `sound.volume = Float(Double(max(0, min(100, volume))) / 100.0 * gain)` заменить на
  `sound.volume = Float(SoundVolumeCurve.amplitude(volume: volume, gain: gain))`.
  Больше нигде громкость не считается: `Sound.play(volume:)` — единственный путь.
- **Гейны не меняются.** `UiSoundService.swift:19-21`: `shutter 0.6`, `tickSound 0.25`,
  `copiedSound 0.7` — совпадают с `UiSoundService.cs:22-24`. Этот же тройной набор зашит в тесты
  (§3).
- **Вызывающие на Mac** (через `UiSoundService`, все три — не моя правка, но проверить, что
  ничего не считает громкость мимо): `App/AppCoordinator+OverlayEditorDelegate.swift:68`
  (`capture`), `App/AppCoordinator+Package.swift:132` (`copied`) и `:384` (`capture`),
  `Stack/EdgeStackWindowController.swift:512` (`tick`), `App/AppCoordinator.swift:167` (`preload`),
  `App/SmokeTestRunner.swift:41` (`verifyAssets`).
- **Ловушка.** `NSSound.volume` — `Float 0…1`, амплитуда, а не децибелы, ровно как
  `MediaPlayer.Volume`. Кривая переносится один в один; никакого дополнительного
  `pow(x, 1/2.2)` от AVFoundation/AppKit добавлять не надо.
- **Следствие для пользователя, которое надо сказать вслух:** дефолт `40` по квадратичной шкале
  примерно на 8 дБ тише прежнего. На Windows это записано в «Что сказать Кате» п. 3; на Mac то же
  самое, лечится ползунком, число рядом с которым теперь видно (S5-2).

#### `UiSoundService.Tick` на временных настройках

Окно настроек играет тик громкостью, которую держит ползунок, **не записывая её в файл**:
`HotkeySettingsWindow.xaml.cs:207` —

```csharp
private void PreviewVolume() =>
    UiSoundService.Tick(_original with { PlaySounds = true, SoundVolume = (int)VolumeSlider.Value });
```

На Mac `UiSoundService.tick(_ settings: HotkeySettings)` (`UiSoundService.swift:40`) принимает те же
настройки значением — временный экземпляр строится тривиально (`var preview = original;
preview.playSounds = true; preview.soundVolume = …`). Подробности окна — S5-2.

**Ловушка:** `UiSoundService.tick` глушится затвором на 400 мс и троттлится на 170 мс
(`UiSoundService.swift:23-24, 44-51`). Превью громкости приходит по таймеру и под троттл попадёт,
если пользователь дёргает ползунок чаще шести раз в секунду — на Windows ровно так же
(`SoundThrottle`), поведение считается верным, ничего не обходить.

### 1.5 Одиночный пакет (д)

#### C5-7 `singleCaptureLabel` в `PromptGenerator` и `FileExportService`

- **Windows:** коммит `f077f0d` (W0-2).
  - `src/Snapik.Core/Exporting/PromptGenerator.cs:11` — тип стал
    `public sealed class PromptGenerator(string? singleCaptureLabel = null)`; `:26-28` —
    `var captureLabel = singleCaptureLabel is { } only && session.Captures.Length == 1 ? only : CaptureLabels.ForIndex(captureIndex);`
  - `src/Snapik.Infrastructure/Exporting/FileExportService.cs:16` — третий параметр
    `string? singleCaptureLabel = null`; `:47-49` — та же развилка для метки, из которой строится
    `01-B.png`; `:72` — `new PromptGenerator(singleCaptureLabel)`.
  - Интерфейсы экспорта (`IExportService`) **не тронуты**.
- **Mac-цель:**
  - `Sources/SnapikCore/Exporting/PromptGenerator.swift:6-7` — сейчас
    `public struct PromptGenerator` с `public init() {}`. Стало:

```swift
public struct PromptGenerator {
    /// Буква пакета из одного снимка, когда этот снимок уже несёт букву в другом месте:
    /// скопированная карточка «B» не должна назваться «A» в тексте, пока карточка и тост
    /// говорят «B». Пакет из двух и более снимков нумеруется по позиции, как раньше.
    private let singleCaptureLabel: String?
    public init(singleCaptureLabel: String? = nil) { self.singleCaptureLabel = singleCaptureLabel }
    public func generate(_ session: SnapikSession) throws -> String
}
```

    внутри `generate` заменить `CaptureLabels.forIndex(index)` на развилку
    `if let only = singleCaptureLabel, session.captures.count == 1 { only } else { try CaptureLabels.forIndex(index) }`.
  - `Sources/SnapikCore/Exporting/FileExportService.swift:16` — `init` получает третий параметр
    `singleCaptureLabel: String? = nil` (после `timeProvider`), поле сохраняется;
    `:39` (`CaptureLabels.forIndex(index)` перед сборкой имени на `:44`) — та же развилка;
    `:74` — `try PromptGenerator(singleCaptureLabel: singleCaptureLabel).generate(session)`.
  - Протокол `ExportService` (`Exporting/ExportContracts.swift`) не трогать.
- **Вызывающие на Mac, которых правка не должна задеть** (все передают параметр по умолчанию):
  `FileExportService.swift:74`, `SnapikMac/App/SessionWorkspace.swift:163`,
  `SnapikMac/App/SmokeTestRunner+Stack.swift:174` и `:230`, и восемь мест в
  `Tests/SnapikCoreTests/{CaptureKindTests,ExtendedCommentsTests,SerializationCyrillicTests,SessionModelTests,PersistenceAndExportTests}.swift`.
  Параметр со значением по умолчанию их не ломает — **но** `PromptGenerator` на Mac это `struct`,
  и добавление хранимого свойства убивает бесплатный memberwise-init: явный
  `public init(singleCaptureLabel: String? = nil)` обязателен, иначе `PromptGenerator()` перестанет
  компилироваться во всех восьми местах.
- **`CaptureLabels` не трогать.** `forIndex` на Mac — `throws` (`CaptureLabels.swift:13`), в отличие
  от Windows; развилка должна оставаться внутри `try`, а ветка с готовой буквой — без него.

#### C5-8 `SessionWorkspace.exportSingle`

- **Windows:** `src/Snapik.App/SessionWorkspace.cs:227-236` (коммит `af569e2`, W0-3):

```csharp
public async Task<PreparedExport> ExportSingleAsync(CaptureItem capture, string? label = null, CancellationToken ct = default)
{
    var session = new SnapikSession(SessionId, SnapikSession.CurrentSchemaVersion, _createdAtUtc,
        DateTimeOffset.UtcNow, _revision, string.Empty, null, [capture.ToCore()]);
    var prepared = await new FileExportService(new WpfExportImageRenderer(), null, label)
        .PrepareAsync(session, SessionDirectory, ct);
    TrimExports(prepared.RootDirectory);
    return prepared;
}
```

  Три решения внутри, которые обязаны переехать: **сессия строится на лету из одного снимка**
  (`capture.ToCore()`), **на диск ничего не пишется** (снимок может быть черновиком редактора,
  которого лента ещё не видела), **ревизия не двигается** (её двигает только настоящая запись
  сессии).
- **Mac-цель:** `Sources/SnapikMac/App/SessionWorkspace.swift`, новый метод рядом с
  `prepareExport(renderer:includingSent:)` (`:156`):

```swift
/// Пакет из одного снимка: тот же рисунок и тот же текст, что у пакета, но снимок берётся как
/// есть и сессия на диск не пишется — это может быть черновик редактора, которого лента ещё не
/// видела. Ревизия тоже не двигается: её двигает только настоящая запись сессии. `label` —
/// буква карточки, чтобы картинка, текст и тост называли один и тот же снимок.
func exportSingle(_ capture: CaptureItem, label: String? = nil,
                  renderer: ExportImageRendering) async throws -> PreparedExport
```

- **Отличия Mac, которые надо учесть:**
  1. `prepareExport` на Mac принимает `renderer:` параметром (`:156`), а не строит его внутри —
     `exportSingle` делает так же, рендерер передаёт вызывающий.
  2. На Mac **нет `TrimExports`**: ротации каталогов `exports/revision-*` в дереве `macos/` нет
     вовсе (`SessionWorkspace.swift:100-123` умеет только удалять сессию целиком). Строку
     `TrimExports(...)` **не переносить**, но записать долг: каждый одиночный экспорт создаёт ещё
     один `revision-*`, а «Копировать снимок» может нажиматься часто. Это отдельная задача, не эта
     дельта; здесь — комментарий в коде и строка в §5.
  3. `SnapikSession` на Mac собирается своим инициализатором; поля `sessionId`,
     `SnapikSession.currentSchemaVersion`, `createdAtUtc`, `revision`, пустая общая заметка,
     массив из одного `capture` — один в один с Windows.
- **Вызывающие:** `EdgeStackWindow.CopySingleCaptureAsync` (`EdgeStackWindow.Saving.cs:51`) — зона
  `stack`; кнопка «Копировать» и Ctrl+Shift+C редактора (`4de1e67`) — зона `editor`. Обе получают
  метод из этой порции; передача — §4.

#### C5-9 Признак «одиночная публикация» и `clearsTheStrip`

- **Windows:** `src/Snapik.App/PublishedPackage.cs:11-22, 36-40` (коммит `2ed0b98`, приёмка):

```csharp
internal sealed record PublishedPackage(
    string[] Paths, string Prompt, Guid[] CaptureIds, string ExportDirectory,
    int NoteCount, bool IsSingleCapture = false)
{
    internal static bool ClearsTheStrip(PublishedPackage published, bool clearStackAfterPaste) =>
        clearStackAfterPaste && !published.IsSingleCapture;
}
```

  Применение — `EdgeStackWindow.xaml.cs:1759`. Тип живёт **только в памяти**: ни в `session.json`,
  ни в `settings.json` он не пишется, формат не меняется.
- **Mac-цель.** Отдельного `PublishedPackage` на Mac нет: его роль раздроблена на
  `PreparedExport` (`SnapikCore/Exporting/ExportContracts.swift:82`, поля `rootDirectory` :83 и
  `manifest` :84) и живые поля координатора (`App/AppCoordinator.swift:47` `prepared`,
  `:51` `ownedClipboardReceipt`, `:52` `ownedClipboardPromptText`,
  `:56` `pasteObservedForCurrentPackage`).
  Поэтому:
  1. завести в `App/AppCoordinator.swift` рядом с `:56` поле
     `var publishedIsSingleCapture = false` (только в памяти, в настройки не уезжает);
  2. завести **чистую** функцию, чтобы правило было покрыто обычным тестом, а не только смоуком.
     Место — `Sources/SnapikCore/Exporting/ExportContracts.swift` рядом с `PreparedExport`:

```swift
/// Очищает ли замеченная вставка ленту. «Очистить ленту после вставки» — про пакет: она говорит,
/// что всё, что только что отправлено, может уйти. Снимок, скопированный поодиночке, отправляет
/// одну карточку из многих, а остальные никто не вставлял — они получают только галочку, а стек
/// отмены и сессия остаются на месте.
public static func clearsTheStrip(isSingleCapture: Bool, clearStackAfterPaste: Bool) -> Bool {
    clearStackAfterPaste && !isSingleCapture
}
```

  3. точка применения на Mac — `App/AppCoordinator+PasteIntent.swift:133`
     (`if settings.clearStackAfterPaste { await clearStack(clipboardGateHeld: true) } else { … }`)
     становится `if PreparedExport.clearsTheStrip(isSingleCapture: publishedIsSingleCapture,
     clearStackAfterPaste: settings.clearStackAfterPaste) { … }`.
- **Правило снятия признака** (`EdgeStackWindow.xaml.cs:444, 1052, 1061, 1307, 1798`): признак
  ставится при «Копировать снимок» и снимается **следующим захватом**, явным «Копировать пакет»,
  очисткой ленты и замеченной вставкой. На Mac те же события живут в
  `AppCoordinator+Package.swift` (`copyPackage` :126, `saveAndCopyCommittedPackage` :19,
  `refreshOwnedClipboard` :77, `importFiles` :276, `importFromClipboard` :314) и
  `AppCoordinator.swift:569` (`clearStack`). Расстановка — вместе с порцией `stack`, потому что
  «Копировать снимок» это её меню; здесь — поле, правило и точка применения.
- **Второе правило приёмки, которое переносится сюда же:** буфер с одиночной копией **не
  пересобирается** до вставки. На Windows `RefreshOwnedClipboardCoreAsync` выходит рано при
  `_ownedClipboardIsSingleCapture` (`EdgeStackWindow.xaml.cs:1710`), а
  `ReleaseOwnedClipboardCoreAsync` на одиночной копии буфер не трогает (`:1806`). На Mac это
  `AppCoordinator+Package.swift:77` (`refreshOwnedClipboard`) и путь освобождения буфера —
  те же два гарда по `publishedIsSingleCapture`.

### 1.6 Окно настроек (е)

#### S5-1 Высота 620

- **Windows:** `HotkeySettingsWindow.xaml:3` — `Height="520"` → `Height="620"`, коммит `1da138b`
  (AD-1, ТЗ A1). Число выбрано по самой высокой вкладке «Вид», которая просит 558 px. Рядом
  `x:Name="Tabs"` на `TabControl` (`:19`) и `x:Name="AppearanceTabItem"` на вкладке «Вид» (`:70`) —
  оба заведены ради пробы.
- **Mac-цель:** `Settings/HotkeySettingsWindowController.swift:84` —
  `contentRect: NSRect(x: 0, y: 0, width: 620, height: 520)` → `height: 620`. Комментарий-обоснование
  на `:80-83` переписать: число задаёт самая высокая вкладка, окно не прокручивается и не тянется.
- **Смоук:** `App/SmokeTestRunner+Settings.swift:27` —
  `check("settings window 620x520", settings.window?.frame.size == NSSize(width: 620, height: 520))`
  переименовать и переставить на 620×620, **и заменить сравнение на настоящую проверку** (A5-1):
  честная проба меряет корень с бесконечной высотой по каждой из четырёх вкладок, а не сверяет
  число с числом.
- **Ловушка AppKit.** Вкладки на Mac — не `NSTabView`, а четыре `SettingsTabView` (`:66`), которые
  показываются `showTab(_:)` (`:266`). Скрытая вкладка в AppKit всё равно построена (в отличие от
  WPF `TabControl`, который строит только выбранную), поэтому шага «реализовать вкладку перед
  измерением» не нужно — достаточно `layoutSubtreeIfNeeded()` и `fittingSize`.
- **Оговорка, которую надо унести в записку:** 620 решают обрезку содержимого, а не размер экрана;
  на маленьком мониторе окно всё равно может не влезть. Настоящее лечение — прокрутка внутри окна,
  в этот раунд её не брали.

#### S5-2 Число у громкости и тик через таймер

- **Windows:** коммит `7b24853` (AD-2, ТЗ D1).
  - Разметка `HotkeySettingsWindow.xaml:32-40`: ползунок и `TextBlock x:Name="VolumeValueLabel"`
    в горизонтальном `StackPanel`, `FontSize 12`, `TextMutedBrush`, отступ слева 10.
  - `HotkeySettingsWindow.xaml.cs:54-55` — подписка **после** того, как значение поставлено, чтобы
    открытие окна не считалось изменением и ничего не играло:
    `VolumeSlider.ValueChanged += (_, _) => { UpdateVolumeCaption(); _volumePreview.Stop(); _volumePreview.Start(); };`
    и `_volumePreview.Tick += (_, _) => { _volumePreview.Stop(); PreviewVolume(); };`
  - `:149` — `DispatcherTimer { Interval = 150 ms }`; один таймер на все входы, потому что
    ползунок двигают перетаскиванием, кликом по дорожке и стрелками клавиатуры, а событие конца
    перетаскивания есть только у первого.
  - `:195-208` — `UpdateVolume()` гасит таймер, когда звуки выключены; `UpdateVolumeCaption()` —
    `$"{(int)VolumeSlider.Value} %"`, одинаково в обоих языках; `PreviewVolume()` — §1.4.
  - `:80-85` — `Closed` гасит таймер: тик, который никто не сохранил, не должен прийти после
    закрытия окна.
  - `:130-132` — после прохода `UiLanguage.Apply` число выставляется заново (проход переписывает
    текст любого несвязанного `TextBlock`).
- **Mac-цель:**
  - `Settings/SettingsTabViews.swift` — рядом с `volumeLabel` (`:48`) и `volumeSlider` (`:49`)
    завести `let volumeValueLabel = sectionLabel("")`; добавить его в список сабвью (`:64`),
    в `updateVolumeRow()` (`:73-77`), в `applyTheme` (`:101`, цвет `palette.textMuted`) и в
    раскладку (`:123-125`).
  - `Settings/HotkeySettingsWindowController.swift`:
    - **у ползунка громкости сейчас нет ни `target`, ни `action`** — значение читается только при
      сохранении (`:494`). Завести `@objc private func volumeChanged()` по образцу
      `qualityChanged()` (`:280`, вешается на `:153-154`);
    - таймер: `private var volumePreview: Timer?` либо `DispatchWorkItem`, 150 мс, перезапуск на
      каждом изменении;
    - `soundsChanged()` (`:284-286`) гасит таймер, когда звуки выключены;
    - `applyLocalization()` (`:232-248`) — выставить число заново после локализации;
    - закрытие окна (`windowWillClose` / `saveClicked` :390 / отмена) гасит таймер.
  - Значение ставится в `populateFields(from:)` (`:211`) **до** подписки на action, иначе открытие
    окна сыграет тик.
- **Ловушки AppKit.**
  1. `NSSlider` шлёт `action` непрерывно, пока его тянут (`isContinuous` по умолчанию `true`) —
     это то, что нужно: один таймер, перезапускаемый на каждом шаге, и есть «пауза = отпустили».
     Стрелки клавиатуры и клик по дорожке шлют то же действие, поэтому отдельных входов не надо.
  2. `Timer.scheduledTimer` держит сильную ссылку на target; брать
     `Timer(timeInterval:repeats:block:)` со `[weak self]` и `invalidate()` в `deinit` и при
     закрытии — иначе окно переживёт себя и тик придёт в мёртвый контроллер (правило teardown из
     SPEC-DELTA-4 §5 п. 6: образец — `Hotkeys/GlobalHotkeyService.swift:54-59`).
  3. Текст числа — `"\(Int(slider.doubleValue)) %"`, с пробелом перед знаком, без слов, одинаково в
     ru и en. Никакого `NumberFormatter` с локалью: проба сверяет строку `"60 %"` дословно.
  4. `volumeSlider` на Mac объявлен с `numberOfTickMarks = 101` и
     `allowsTickMarkValuesOnly = true` (`SettingsTabViews.swift:60-61`) — значения целые, каста
     хватает.

#### S5-3 Четыре палитры

- **Windows:** коммит `9e21d07` (AD-3, ТЗ D2).
  - `Controls/AppearancePicker.xaml:106-113` — четвёртый `RadioButton x:Name="NeonPalette"`,
    `Tag="neon"`, **между** «Пастель» и «Своя», в том же порядке, в каком палитры предлагает
    редактор.
  - `Controls/AppearancePicker.xaml.cs:126` — белый список сеттера:
    `var palette = value is "pastel" or "neon" or "custom" ? value : "standard";` (было без `neon`);
    `:132` — `NeonPalette.IsChecked = palette == "neon";`
  - `:158` — `NeonPalette.Content = Text("Неон");`
  - **Суть дефекта:** до правки любое «Сохранить» в настройках писало `AnnotationPalette` из
    сеттера, который «лечил» неизвестный ему `neon` в `standard`, — и выбранный в редакторе неон
    стирался, даже если вкладку «Вид» не открывали. Путь: `HotkeySettingsWindow.xaml.cs:70`
    (чтение) и `:278` (`AnnotationPalette = AppearanceTab.SelectedPalette` при сохранении).
- **Mac-цель:** `Settings/AppearancePickerView.swift`:
  - `:149-152` — четвёртая кнопка; `paletteButtons = [standard, pastel, neon, custom]`;
  - `:171-181` — теги 0…3, action тот же;
  - `:127-136` — белый список:
    `let value = (newValue == "pastel" || newValue == "neon" || newValue == "custom") ? newValue : "standard"`;
  - `:277-287` (`refreshPaletteRow`) — массив `ids` на `:278` становится
    `["standard", "pastel", "neon", "custom"]`;
  - `:367-369` (`paletteClicked`) — тот же массив;
  - `:208-211` — четвёртая подпись `text("Неон")` (пара добавляется в §1.3);
  - `:196-197` — высота ряда не меняется (сегменты в одну строку), но ширину ряда проверить: на
    Mac ряд раскладывается в `:404-412` фиксированными долями, четвёртый сегмент их сдвигает.
- **Точки на Mac, которые ведут себя как на Windows и потому сломались бы так же:**
  `Settings/HotkeySettingsWindowController.swift:229` (`picker.selectedPalette = settings.annotationPalette`)
  и `:505` (`candidate.annotationPalette = picker.selectedPalette`) — та же пара «чтение и запись
  через сеттер», то есть **как только порция `editor` добавит неон в
  `Editor/EditorAppearanceModel.swift:61`, дефект Windows воспроизведётся на Mac дословно**, если
  белый список не расширить. Обе правки должны попасть в один релиз.
- **Зависимость от порции `editor`.** Двенадцать цветов неона
  (`OverlayEditorWindow.Appearance.cs:55-56`:
  `#FF1744 #FF6D00 #FFEA00 #C6FF00 #00E676 #1DE9B6 #00E5FF #2979FF #651FFF #D500F9 #FF4081 #FFFFFF`)
  и сам `EditorPalette(id: "neon", …)` заводит порция `editor` в
  `Editor/EditorAppearanceModel.swift:59-62`; она же снимает `quick` (Windows удалил
  `PaletteSet.Quick`). Ряд настроек должен идти **в том же порядке**, что
  `EditorAppearance.palettes`, — за этим следит проба A5-1.

#### Что в окне настроек **не** менялось

Остальные 300 удалённых строк `HotkeySettingsWindow.xaml.cs` — это переезд записи `HotkeySettings`
в отдельный файл (W0-0). Логика окна, кроме трёх пунктов выше, та же.

### 1.7 Мастер и онбординг (ж)

#### S5-4 Стрелки галереи тем (tz-006 A-1)

- **Windows:** коммиты `22a332f`, `74fdbf6`.
  - `Controls/AppearancePicker.xaml:21-31` — триггер стиля `Chevron` по `IsEnabled=False` заменён
    триггером по `Tag="end"` (та же `Opacity 0.42`, плюс `Cursor="Arrow"`).
  - `.xaml.cs:318-329` — `MarkChevrons()` ставит `Tag` и `AutomationProperties.HelpText`, а не
    гасит кнопку: `MarkEnd(PreviousTheme, _firstCard <= 0); MarkEnd(NextTheme, _firstCard >= LastPage);`
  - `.xaml.cs:341` — гвард в `OnGalleryScrolled`: проход, в котором
    `Gallery.ViewportWidth <= 0 || Gallery.ExtentWidth <= 0`, выходит сразу. Именно такой проход
    гарантирован при смене DPI, и прочитанный один раз он оставлял счётчик «в конце ряда» навсегда.
  - `.xaml.cs:72` — конструктор подписан на `Gallery.SizeChanged` → `MarkChevrons()`.
  - `.xaml.cs:532-570` — `DescribeGallery()` и `DescribeChevronHit()` (трасса, §0.3 — не переносим).
- **Mac: механики дефекта нет.** `Settings/AppearancePickerView.swift` считает `firstCard` сам
  (`:90`), а не вычитывает его из офсета `ScrollViewer`; `visibleCards` (`:306-308`) при нулевой
  ширине даёт `max(1, 0) = 1`, `lastPage` (`:311`) — `cards.count - 1`, то есть `markChevrons()`
  (`:328-331`) в худшем случае оставляет обе стрелки **включёнными**. Залипания «выключена
  навсегда» нет и быть не может: аналога `OnGalleryScrolled` нет вовсе.
- **Что переносится всё равно (S):**
  1. **Правило «конец ряда — метка, а не выключенность»**, ради одинакового поведения на двух
     платформах: у `ChevronButton` (`:689`) завести `var atEnd = false { didSet { needsDisplay = true } }`,
     `draw(_:)` (`:703-723`) брать альфу из него (`atEnd ? 0.42 : 1`), `isEnabled` держать `true`
     всегда, `markChevrons()` (`:328-331`) ставить `atEnd` вместо `isEnabled`. Нажатие на конце
     ряда ничего не двигает — `pageBy` уже клампит (`:317`).
  2. **Кламп `firstCard` при смене ширины.** `layout()` (`:396`) зовёт `markChevrons()`, но не
     поправляет `firstCard`, а `lastPage` при расширении окна уменьшается: строка
     `firstCard = min(firstCard, lastPage)` перед `layoutGallery(animated: false)` (`:395`) — это
     аналог Windows-подписки на `SizeChanged`.
- **Смоук на Mac** (`SmokeTestRunner+Settings.swift:50-64`) `isEnabled` не проверяет — после
  правки дописать в `galleryOk` два утверждения: в начале ряда «назад» помечена концом, а «вперёд»
  нет; в конце ряда наоборот, и **обе кнопки остаются нажимаемыми**.

#### Онбординг: что менялось и что не переносится

- **`PinCarryOver`** (`OnboardingWindow.xaml:191-196`, `.xaml.cs:436-443`, коммит `2ca5c1f`) —
  строка шага «закреп» с тремя вариантами и чистая `TaskbarPinService.LegacyPinNote(...)`.
  **Не переносится** (§0.3): на macOS закрепа на панели задач нет.
  Соответствующий шаг на Mac — `startupStep`, индекс **2** из пяти
  (`OnboardingWindowController.swift:67`; вью — `Onboarding/OnboardingStepViews.swift:160`), и он
  про автозапуск при входе, а не про закреп. Ничего добавлять не надо.
- **`TraceDpiChange`, `WindowRectangle`, `GetWindowRect`** (`OnboardingWindow.xaml.cs:129-213`) —
  не переносятся (§0.3).
- **`OnboardingVersion`** — не менялся ни на Windows (`OnboardingWindow.xaml.cs:25`
  `CurrentVersion = 3`), ни на Mac (`OnboardingWindowController.swift:16`). Оставить как есть:
  полный мастер существующим пользователям повторно не показывается.
- **`_placed`** — уже есть на Mac (§0.1).

### 1.8 Темы и палитры (з)

- **Windows: новых кистей и ресурсов в раунде нет.** `src/Snapik.App/Themes/**`,
  `AccentPalette.cs`, `ThemeService.cs` в диапазоне `d84fbb0..f2cf62b` **не менялись**
  (`git diff --name-status` их не показывает). `ElevatedBrush`, `ElevatedLineBrush`,
  `SurfaceLineBrush`, `TextFaintBrush`, упомянутые в ТЗ B2, существовали и раньше — B2 просто
  перевёл карточку ленты с захардкоженных цветов на них.
- **Mac:** все четыре токена на месте под своими именами в `App/Theme.swift`, `struct ThemePalette`
  (`:54`): `elevated` `:59`, `elevatedLine` `:60`, `surfaceLine` `:58`, `textFaint` `:66`.
  Переносить нечего; перекраска карточки — зона `stack`, и она берёт эти токены как есть.
- **Единственное изменение вида в моей зоне** — четвёртый сегмент палитры (S5-3) и число у
  громкости (S5-2), оба через `palette.textMuted`.

### 1.9 `SmokeTestRunner`: реестр проб (и)

Реестр на Windows — `SmokeTestRunner.RunAsync`. Изменения раунда в моей зоне, чтобы сведение ничего
не потеряло.

| Проба Windows | Строка вызова | Что делать на Mac |
|---|---|---|
| `VerifyTz007SingleExport(root + "single-export-probe")` | `:650` | **Перенести (A5-2).** Тело `:1372-1386`: воркспейс, один снимок с заметкой, `ExportSingleAsync(capture, "B")`, проверка `Images[0].FileName == "01-B.png"` и `PromptText` начинается с «Снимок B». Смысл пробы — провод от окна до генератора: юнит-тесты зовут сервис напрямую и обрыв выше не поймают. |
| `VerifyTz007Settings()` | `:654` | **Перенести (A5-1).** Тело `:1585-1636`, три части: (1) высота всех четырёх вкладок против высоты окна, с гвардом «измерение меньше 200 px — это не измерение»; (2) число у громкости `"60 %"` переживает смену языка, и выключение звуков убирает строку; (3) последовательность `Tag` ряда палитр равна `OverlayEditorWindow.Palettes.Select(id)` — **последовательность, не множество**. |
| `VerifyALegacyPinIsCarriedOver(...)` | `:652` | **Не переносить** (§0.3). |
| `VerifyALayeredWindowMinimisesAsync()` | `:52` | **Не переносить** (§0.3). |
| `EdgeStackWindow.RunStripGrowthProbe` | `:653` | Зона `stack`. |
| `VerifyTz007Editor()` | `:655` | Зона `editor` (шпаргалка клавиш, точка выноски, пустой блок свойств). |
| `Controls.AnnotationCanvas.VerifyScalingRules` | `:447` | Зона `editor`. |
| `OverlayEditorWindow.RunToolMemoryProbe` / `RunEditorViewProbe` | `:475-476` | Зона `editor`; `RunEditorScaleProbe` **удалена** вместе с переключателем масштаба — при сведении проверить, что осиротевшего вызова `smokeRunEditorScaleProbe` (`SmokeTestRunner+Editor.swift:22-31`) не осталось. |
| `VerifyTheWizardKeepsItsAppearance(root)` | `:651` | Без изменений; на Mac уже есть (`SmokeTestRunner+Settings.swift:179`). |
| `Controls.AppearancePicker.RunProbe` | `:213` | **Правки (A5-3, S5-3, S5-4).** В пробу добавлены: неон не лечится в стандартную (`:425-431`), конец ряда — `Tag`, а не выключенность (`:450-478`), нажатие на конце ничего не двигает, проход с нулевой шириной оставляет галерею на месте. На Mac эти проверки уходят в `SmokeTestRunner+Settings.swift:50-64`. |

**Правки существующих проверок на Windows, которые надо повторить на Mac (A5-3, A5-4):**

- `SmokeTestRunner.cs:33-36` — набор «нестандартных» настроек для round-trip получил
  `StackHeightManual = true`. Mac-аналог: `SmokeTestRunner.swift:78-91` (`custom.…`), дописать
  `custom.stackHeightManual = true` и, когда появится C5-2, непустой `custom.toolAppearance`
  (иначе проба «всё, что записали, вернулось» новых ключей не увидит).
- `SmokeTestRunner.cs:84-100` — `ParseAnnotationPalette("neon").Id == "neon"` (было `"standard"`),
  `Palettes.Length == 4` (было 3), проверка `palette.Quick.Length != 5` снята вместе с полем.
  Mac-аналог — в `SmokeTestRunner+Editor.swift:22-31` (`smokeVerifyPalettes`), зона `editor`;
  от меня — `smokePaletteTitles` в `SmokeTestRunner+Settings.swift:42` должен стать
  `["Standard", "Pastel", "Neon", "Custom"]`.
- `SmokeTestRunner.cs:218-224` — окно настроек меряется **своим объявленным размером**
  (`window.Width/Height`), а не 530×480, и вкладка «Вид» реализуется принудительно. Mac-аналог —
  `SmokeTestRunner+Settings.swift:24-27`, см. S5-1.
- `SmokeTestRunner.cs:266-270` — окно, открытое на файле с `AnnotationPalette = "neon"`, показывает
  неон. Mac-аналог — новая строка в `runSettingsAndOnboardingProbes`.
- `SmokeTestRunner.cs:352-358` — языковая таблица смоука: пары «По ширине/По высоте» убраны,
  добавлена `("Копировать снимок", "Copy capture")`. Mac-аналог —
  `SmokeTestRunner+Settings.swift` (проверка перевода) плюс
  `SmokeTestRunner+Stack.swift:94` (`the strip translates into English`).

**Пустых крючков не заводить.** Windows завёл три (`88c3178`, W0-1), чтобы дорожки не спорили за
место в реестре, и один из них (`VerifyTz007Strip`) в приёмке пришлось убрать как «читается как
покрытие, которого нет» (`2ed0b98`). На Mac реестр — это список `check(...)` внутри
`runSettingsAndOnboardingProbes` (`SmokeTestRunner+Settings.swift:13-227`) и цикл
`SmokeTestRunner.swift:113-116`; порции не пересекаются по файлам расширений, крючки не нужны.

### 1.10 Геометрия Core: `StripResizeGeometry` (контракт, не поведение)

Windows раздал константы списка врозь и добавил четыре чистые функции
(`Controls/StripResizeGeometry.cs:37-103`, коммиты `6c2679a`, `5f2dc23`, `7789ae6`, `3c2ebba`).
На Mac все они попадают в `Sources/SnapikCore/Geometry/StripResizeGeometry.swift` — то есть в
Core, то есть в эту порцию (сигнатуры и тесты). **Поведение окон — зона `stack`.**

| Windows | Значение | Swift |
|---|---|---|
| `ListPaddingLeft` | 4 (было общее `ListPadding = 8`) | `public static let listPaddingLeft: Double = 4` |
| `ListPaddingRight` | 12 | `public static let listPaddingRight: Double = 12` |
| `EmptyListHeight` | 92 | `public static let emptyListHeight: Double = 92` |
| `ListTopPadding` | 14 | `public static let listTopPadding: Double = 14` |
| `ListBottomPadding` | 8 | `public static let listBottomPadding: Double = 8` |
| `CardHeight` | 78 | `public static let cardHeight: Double = 78` |
| `CardOverlap` | 48 | `public static let cardOverlap: Double = 48` |
| `CardPitch` | `CardHeight − CardOverlap` = 30 | `public static let cardPitch: Double = cardHeight - cardOverlap` |
| `CardWidth(w)` | `w − 2·ShadowMargin − 2·ShellPadding − ListPaddingLeft − ListPaddingRight` (244 → 168, число прежнее) | у Mac живёт в `Stack/StackMetrics.swift:108` — зона `stack` |

Сигнатуры четырёх функций — §4.

**Дубли, которые надо свести.** На Mac те же числа уже лежат в `Stack/StackMetrics.swift`:
`cardHeight` `:64`, `cardOverlap` `:65`, `cardStep` `:67`, `emptyHintHeight` `:60`,
`listPaddingTop` `:51`. После переноса **источник один — Core**, `StackMetrics` берёт из него
(`static let cardHeight = StripResizeGeometry.cardHeight` и т. д.), ровно как Windows выражает
панель и карточку формулами, а не литералами. `listPaddingLeft` `:50` = 8 и `listPaddingRight`
`:52` = 8 на Mac расходятся с целевыми 4 и 12, `listPaddingBottom` `:53` = 52 у Windows заменён
`ItemsPanel Margin="0,0,0,48"` плюс паддинг 8 — это правка зоны `stack`, здесь только константы.

---

## 2. Изменения формата

Все абзацы «Изменение формата» из `tasks/verification.md` обоих раундов — пять штук
(`:60`, `:62`, `:64`, `:66` для 1.6.0 и `:122`, `:124`, `:126` для 1.7.0; `:66` помечен «изменение
чтения», `:64` — «изменение смысла»).

### 2.1 `settings.json`: ключ `toolAppearance` (1.6.0)

Целевой вид:

```json
{
  "AnnotationColor": "#FF3B30",
  "AnnotationThickness": 9,
  "AnnotationHighlightThickness": 16,
  "AnnotationFontSize": 32,
  "toolAppearance": {
    "rectangle": { "color": "#FF3B30", "thickness": 9, "lineStyle": "dashed", "fill": "translucent", "fillColor": "#007AFF", "fontSize": 20, "arrowStyle": "straight", "shape": "rounded" },
    "arrow":     { "color": "#007AFF", "thickness": 4, "lineStyle": "solid", "fill": "none", "fontSize": 20, "arrowStyle": "curved", "shape": "rectangle" },
    "pen":       { … }, "highlight": { … }, "text": { … }, "blur": { … }
  }
}
```

- Ключ словаря — **camelCase** имя инструмента: `rectangle`, `arrow`, `pen`, `highlight`, `text`,
  `blur`. Единственный camelCase-ключ среди PascalCase остального файла; решено осознанно.
- Поля записи: `color`, `thickness`, `lineStyle`, `fill`, `fillColor`, `fontSize`, `arrowStyle`,
  `shape`. `null` (а на деле — **отсутствие**) в `fillColor` означает «как обводка».
- **Чтение Mac:** файла без `toolAppearance` → каждый инструмент получает старые общие значения
  (`AnnotationColor`, `AnnotationThickness` / `AnnotationHighlightThickness` у маркера,
  `AnnotationFontSize`), то есть файл 1.5.0 открывается ровно так, как выглядел. Неизвестное имя
  инструмента пропускается молча. Неизвестное имя перечисления, число вместо имени, битый HEX —
  падение на значение по умолчанию того же инструмента.
- **Запись Mac:** пишутся все шесть, и **старые общие ключи продолжают писаться** зеркалом рамки,
  маркера и текста. Файл, записанный этой версией, читается 1.5.0 целиком, и установка в обе
  стороны настроек не теряет.
- `SettingsVersion` **не поднимается**: миграция здесь по отсутствию ключа.
- Побочное следствие, которое надо перенести вместе с ключом: рамка теперь помнит фигуру, заливку
  и её цвет **между снимками**, тогда как раньше каждый снимок начинался с контурной рамки
  (это отменяет часть §2.3 дельты №4 — четыре общих ключа так и не вернулись, но per-tool память
  появилась). Поведение редактора — зона `editor`; формат — здесь.
- `PaletteSet.Quick` из кода удалён; в файл он никогда не писался — формата не касается.

### 2.2 `settings.json`: ключ `StackHeightManual` (1.7.0)

- Аддитивный `Bool` рядом со `StackHeight`, по умолчанию `false`.
- `false` — прежнее поведение: `StackHeight` служит потолком, список стоит по содержимому.
- `true` — то же число становится высотой списка, пол `MinimumListHeight = 180`, потолок рабочей
  области (`StripResizeGeometry.ClampListHeight`).
- Файл без ключа читается как `false`; старый билд лишний ключ игнорирует.
- `SettingsMigration.CurrentVersion` остаётся **2**.
- Двойной клик по ручке угла возвращает `false`.
- Mac переносит ключ и **обе ветки** `StripResizeGeometry.listHeight(count:stored:manual:)`.

### 2.3 `settings.json`: смысл `StackHeight` (1.6.0, изменение смысла, не схемы)

Из «высоты списка» число стало «потолком высоты списка». Тип и диапазон те же, `ClampListHeight`
сигнатуры не меняла, но лента с двумя снимками теперь 130 независимо от записанного, и упирается в
записанное число только когда содержимое до него дорастёт. В 1.7.0 поверх этого лёг
`StackHeightManual`, возвращающий старую трактовку по требованию.

**Что делает Mac:** читает `StackHeight` как раньше, но подаёт результат `clampListHeight(...)` в
`listHeight(count:stored:manual:)` потолком, а не высотой. Ни чтение, ни запись файла не меняются.

### 2.4 `settings.json`: смысл `SoundVolume` (1.7.0)

Само число прежнее, `0…100`, файл читается обоими билдами. Меняется то, во что оно превращается:
амплитуда теперь `(v / 100)² × gain`, а не линейная доля. Ползунок на 40 звучит примерно на 8 дБ
тише прежнего, ползунок на 100 не меняется.

**Что делает Mac:** читает и пишет то же число; обязан перенести кривую (§1.4), иначе одно и то же
значение будет звучать на двух платформах по-разному.

### 2.5 `prompt.md` и имя файла одиночного пакета (1.7.0)

- При копии **одного** снимка метка внутри пакета больше не всегда «A»: `FileExportService` и
  `PromptGenerator` получили необязательный `singleCaptureLabel`, и он применяется **только к
  сессии из одного снимка**, то есть к экспорту, который делает `ExportSingleAsync`.
- Скопировали карточку B — значит `01-B.png` в имени файла, «Снимок B» в `prompt.md`, `B1`, `B2` в
  подписях отметок и «Снимок B скопирован» в тосте.
- Обычный пакет **не меняется ни на байт**: по умолчанию параметр `nil`, метки раздаются по
  позиции.
- `manifest.json` тоже несёт эту букву: `Images[0].DisplayLabel == "B"`.

**Что делает Mac:** читать тут нечего — это только запись. Порт — C5-7, C5-8; проба — A5-2.

### 2.6 `session.json`: `parentAnnotationId` выведен из обращения (1.6.0)

- С 1.6.0 **ничего в него не записывается**, но оно продолжает **читаться**. Сессия 1.5.0,
  открытая заново, сохраняет подпись «К отметке A2» в панели комментариев и пометку
  «(к области A2)» в `prompt.md`; у новых комментариев подпись всегда «К снимку A», и при переносе
  рамки комментарий не двигается.
- `SchemaVersion` не меняется; из старых файлов ключ читается как раньше.

**Проверено по коду, и это важно для распределения работ.** `src/Snapik.Core/Models/AnnotationItem.cs`
в раунде **не менялся**: свойство `ParentAnnotationId` (`:57`) на месте и сериализуется как прежде.
«Не пишется» здесь значит «никто больше не присваивает значение»
(`OverlayEditorWindow.xaml.cs:1458`, снят `MoveLinkedComments`), а не «ключ исчез из JSON» — в
отличие от `LegacyHasOutline` прошлого раунда, где менялась именно модель.

**Что делает Mac:** `Sources/SnapikCore/Models/AnnotationItem.swift` (поле `:80`, `CodingKeys`
`:189`, `decodeIfPresent` `:210`, `encode` `:237`) — **не трогать**. Очистка повисшей ссылки при
обрезке (`Editing/CaptureCropper.swift:87`) и валидация остаются: они защищают чужой файл.
Вся правка — поведение редактора (никто не присваивает родителя, автопривязка снята) и подпись
панели комментариев, то есть **зона `editor`**. Здесь пункт зафиксирован, чтобы порция `editor`
не пошла править Core.

### 2.7 Изменение чтения (не формат): старый снимок с заливкой перекрасится (1.6.0)

`AnnotationRules.OutlineColorOf` потерял параметр `fillColor`: обводка больше не смотрит на цвет
заливки. Отметка 1.5.0 с `Fill=Solid`, `FillColor=#0000FF`, `StrokeColor=#FF3B30` раньше рисовалась
синей обводкой, а теперь нарисуется красной. Формат цел, меняется чтение.

**Что делает Mac:** правило живёт в `Editor/EditorModels.swift` и в рендерере — **зона `editor`**.
Здесь фиксируется как факт, потому что он меняет вид уже сохранённых файлов и должен попасть в
заметки релиза.

---

## 3. Тесты

`git diff --stat d84fbb0..f2cf62b -- tests`: 12 файлов, 6 новых. Новых тестовых целей на Mac не
заводить — всё раскладывается по `macos/Tests/SnapikCoreTests` и `macos/Tests/SnapikMacTests`.

### 3.1 Появилось на Windows в моей зоне

| Windows-файл | Тесты | Swift-набор |
|---|---|---|
| `tests/Snapik.App.Imaging.Tests/SoundVolumeCurveTests.cs` (новый, 46 строк, 6 тестов) | верх ползунка не сдвинулся (`Amplitude(100, 0.6) == 0.6`); половина ползунка — четверть звука (`50 → 0.15`); четверть — шестнадцатая (`25 → 0.0375`); ноль это тишина у двух гейнов; значение вне ползунка подтягивается (`−5 → 0`, `250 → gain`); кривая только растёт (101 точка × 3 гейна) | **новый** `SnapikCoreTests/SoundVolumeCurveTests.swift`. Три гейна-константы взять те же: `0.6`, `0.25`, `0.7`. `XCTAssertEqual(_:_:accuracy: 1e-6)` вместо `Assert.Equal(..., 6)` |
| `tests/Snapik.App.Imaging.Tests/ToolAppearanceTests.cs` (новый, 7 тестов) | из них **мои три**: файл без нового ключа раздаёт всем шести старые общие значения (маркер — свою толщину, текст — свой кегль); файл с ключом читается по нему, инструмент без записи падает на общие, неизвестный (`"telepathy"`) выбрасывается, в словаре остаётся 6; круг `Write`→`Read` по сценарию отчёта с проверкой зеркала четырёх старых ключей | **новый** `SnapikMacTests/Editor/ToolAppearanceStoreTests.swift` (набор Mac: `EditorTool` живёт в `SnapikMac`). Остальные четыре теста файла — таблица инспектора и `InspectedTool` — зона `editor` |
| `tests/Snapik.App.Imaging.Tests/PublishedPackageTests.cs` (+14, 3 теста) | вставленный пакет очищает ленту, когда настройка включена; выключенная настройка не очищает; одиночный снимок не очищает никогда | дописать в `SnapikCoreTests/PersistenceAndExportTests.swift` (или новый `SnapikCoreTests/ClearsTheStripTests.swift`, если `clearsTheStrip` уедет в `ExportContracts`) |
| `tests/Snapik.App.Imaging.Tests/StripResizeGeometryTests.cs` (+43) | `ListHeightForCount` восемью случаями (`0→92`, `1→100`, `2→130`, `5→220`, `12→372`, потолок `500→430`, потолок `130→130`, `NaN→372`); `ListHeight(count, stored, manual)` пятью (`3,310,true→310`; `3,310,false→160`; `15,310,true→310`; `0,310,true→310`; `0,310,false→92`); `CapsuleLeft(1600, 244, 180) == 1664`; `RestoreRect` — лента, оставленная вдали от края, возвращается туда же | дописать в `SnapikCoreTests/Geometry/StripResizeGeometryTests.swift` (173 строки) |
| `tests/Snapik.Core.Tests/PersistenceAndExportTests.cs` (+70, 3 теста) | пакет из одного снимка держит выданную букву (`labelsSeen == ["B"]`, `DisplayLabel == "B"`, `01-B.png`, «Снимок B», `B1:`, `B2:`); пакет из трёх букву игнорирует (`["A","B","C"]`, «Снимок A»); пакет из одного снимка **без** буквы такой, каким был (`["A"]`, `01-A.png`) | дописать в `SnapikCoreTests/PersistenceAndExportTests.swift` (516 строк, рядом с `test_The_images_of_a_package_are_numbered_and_lettered()` :488) |
| `tests/Snapik.Windows.Tests/ClipboardPackageFormatsTests.cs` (новый, 2 теста) | пакет из одного снимка несёт все форматы пакета (`PNG`, `DIB`, `Bitmap`, `FileDrop`, `UnicodeText`, и текст равен переданному); снимок без комментариев не кладёт пустую строку (`UnicodeText` отсутствует) | дописать в `SnapikMacTests/Transport/TransportMacTests.swift`: на Mac форматы называются иначе (`NSPasteboard.PasteboardType.png/tiff/fileURL/string`), проверять `MacClipboardService` тем же составом |

Новых тестов **не требуют**: `SettingsMigration` (не менялся — существующие 13 тестов
`SnapikCoreTests/SettingsMigrationTests.swift` остаются как есть), `UiLanguage` (дубли ловит
`SerializationCyrillicTests`), `AppearancePicker` (покрыт смоуком, как и на Windows).

### 3.2 Что дописать к существующим Swift-тестам

| Набор | Что дописать |
|---|---|
| `SnapikCoreTests/SettingsMigrationTests.swift:72` `test_A_file_written_by_the_previous_sync_keeps_its_keys_and_defaults_the_new_ones` | **новые ключи**: файл 1.5.0 читается, `stackHeightManual == false`, `toolAppearance.isEmpty` |
| `SnapikCoreTests/SettingsMigrationTests.swift:123` `test_Every_key_of_a_filled_file_survives_being_written_and_read_back` | круг записи-чтения **с** `stackHeightManual = true` и непустым `toolAppearance` |
| `SnapikCoreTests/SettingsMigrationTests.swift:171` `test_A_healthy_file_of_this_version_is_not_written_back` | тот же файл, но с `toolAppearance` — убедиться, что структурное сравнение словаря не поднимает `migrated` (C5-2, ловушка 1) |
| `SnapikCoreTests/Geometry/StripResizeGeometryTests.swift` | §3.1, четыре группы |
| `SnapikCoreTests/PersistenceAndExportTests.swift` | §3.1, три теста буквы |

### 3.3 Смоук

Смоук — §1.9. На Mac прибавляются: одна проба (`A5-2`, одиночный экспорт), одна переписанная
(`A5-1`, высота вкладок вместо сравнения чисел), пять точечных правок существующих
(`A5-3`, `A5-4`, S5-3, S5-4).

---

## 4. Контракт волны 0 для порций `stack` и `editor`

Точные Swift-сигнатуры, которые появляются в Core (и в двух местах в `SnapikMac`) и на которые
другие порции опираются. До того как они лежат в ветке волны 0, порции их не видят.

### 4.1 `SnapikCore/Settings/HotkeySettings.swift` — два ключа

```swift
public var stackHeightManual: Bool = false                             // JSON "StackHeightManual"
public var toolAppearance: [String: ToolAppearanceEntry] = [:]         // JSON "toolAppearance"
```

`SettingsMigration.currentVersion` остаётся `2`. Обе пары `CodingKeys` / `decodeIfPresent` /
`encode` — §1.1.

### 4.2 `SnapikCore/Settings/ToolAppearanceEntry.swift` — форма файла

```swift
public struct ToolAppearanceEntry: Codable, Equatable, Sendable {
    public var color: String?
    public var thickness: Double?
    public var lineStyle: String?    // solid | dashed | dotted
    public var fill: String?         // none | solid | translucent | blur
    public var fillColor: String?    // отсутствует = «как обводка»
    public var fontSize: Double?
    public var arrowStyle: String?   // straight | curved | wide
    public var shape: String?        // rectangle | rounded | ellipse
    public init(color: String? = nil, thickness: Double? = nil, lineStyle: String? = nil,
                fill: String? = nil, fillColor: String? = nil, fontSize: Double? = nil,
                arrowStyle: String? = nil, shape: String? = nil)
}
```

### 4.3 `SnapikMac/Editor/ToolAppearanceStore.swift` — для порции `editor`

```swift
struct ToolAppearance: Equatable {
    static let defaultColor: NSColor            // #FF3B30
    static let defaultThickness: Double         // 4
    var color: NSColor
    var thickness: Double
    var lineStyle: AnnotationLineStyle          // .solid
    var fill: AnnotationFill                    // .none
    var fillColor: NSColor?                     // nil = «как обводка»
    var fontSize: Double                        // TextMarkMetrics.defaultFontSize
    var arrowStyle: String                      // "straight"
    var shape: AnnotationShape                  // .rectangle
}

enum ToolAppearanceStore {
    static let tools: [EditorTool]              // [.rectangle, .arrow, .pen, .highlight, .text, .blur]
    static func read(_ settings: HotkeySettings) -> [EditorTool: ToolAppearance]
    static func write(_ settings: HotkeySettings, tools: [EditorTool: ToolAppearance]) -> HotkeySettings
}
```

**Порции `editor`:** имена инструментов в JSON — `rectangle/arrow/pen/highlight/text/blur`, а
**не** `EditorTool.rawValue` (это буквы клавиш). `InspectorView`, `SecondCapsule`,
`EditorInspector.inspectorViewOf(_:)` и `inspectedTool(selected:armed:)` в этот контракт **не
входят** — их пишет сама порция `editor` (Windows-источник `ToolAppearance.cs:157-193`), потому что
это поведение инспектора.

### 4.4 `SnapikCore/Geometry/StripResizeGeometry.swift` — для порции `stack`

```swift
public static let emptyListHeight: Double = 92
public static let listTopPadding: Double = 14
public static let listBottomPadding: Double = 8
public static let listPaddingLeft: Double = 4
public static let listPaddingRight: Double = 12
public static let cardHeight: Double = 78
public static let cardOverlap: Double = 48
public static let cardPitch: Double = cardHeight - cardOverlap      // 30

/// Высота, которую список хочет под `count` карточек, и потолок, записанный ручкой угла в
/// настройки. Ручка задаёт потолок, а не высоту: список из двух карточек 130 независимо от того,
/// что в настройках. `minimumListHeight` здесь **не** пол: он принадлежит только сохранённому
/// числу, иначе один снимок открывал бы список 180 вместо 100.
public static func listHeightForCount(_ count: Int, cap: Double) -> Double

/// Высота списка: вытянутый рукой — это само сохранённое число, автоматический — высота
/// содержимого. Сохранённое число и клампы, через которые оно прошло, в обеих ветках те же;
/// перетаскивание меняет только то, потолок это или высота.
public static func listHeight(count: Int, stored: Double, manual: Bool) -> Double

/// Левый край капсулы: она держит правый край ленты, из которой вышла, а не край монитора —
/// оба окна несут одинаковое поле под тенью, поэтому видимые стороны совпадают.
public static func capsuleLeft(stripLeft: Double, stripWidth: Double, capsuleWidth: Double) -> Double

/// Прямоугольник, который лента занимала до капсулы, возвращённый в рабочую область только когда
/// он в неё больше не влезает: лента, отодвинутая от края, остаётся там, где её оставили.
public static func restoreRect(stored: CGRect, work: CGRect) -> CGRect
```

**Ловушки для этих четырёх:**
- `listHeightForCount(0, …)` = `emptyListHeight` (92), а не 0 и не пол 180.
- Нефинитный `cap` (`NaN`, `inf`) и `cap <= 0` падают на `defaultListHeight` (372).
- `restoreRect` вводит `CGRect` в Core, который сейчас чисто `Foundation`
  (`Geometry/ResizeGeometry.swift:2`): добавить `import CoreGraphics`. Если решено держать Core без
  CoreGraphics — сигнатура
  `restoreRect(storedX:storedY:storedWidth:storedHeight:workX:workY:workWidth:workHeight:) -> (x: Double, y: Double, width: Double, height: Double)`;
  выбор за порцией `stack`, но выбрать надо **до** того, как она начнёт.
- `CGRect.contains(_:)` у пустого `work` (`work.isEmpty`) возвращает `false` — Windows пишет
  `!work.IsEmpty && work.Width > 0 && work.Height > 0 && !work.Contains(stored)`, порядок гардов
  переносить дословно.
- Числа `StackMetrics` (`cardHeight`, `cardOverlap`, `cardStep`, `emptyHintHeight`,
  `listPaddingTop`) после переноса выводятся из Core, а не дублируются (§1.10).

### 4.5 `SnapikCore/Exporting` — для порций `stack` и `editor`

```swift
public struct PromptGenerator {
    public init(singleCaptureLabel: String? = nil)
    public func generate(_ session: SnapikSession) throws -> String
}

public final class FileExportService: ExportService {
    public init(renderer: ExportImageRendering,
                timeProvider: TimeProvider = SystemTimeProvider(),
                singleCaptureLabel: String? = nil)
}

extension PreparedExport {
    public static func clearsTheStrip(isSingleCapture: Bool, clearStackAfterPaste: Bool) -> Bool
}
```

```swift
// SnapikMac/App/SessionWorkspace.swift
func exportSingle(_ capture: CaptureItem, label: String? = nil,
                  renderer: ExportImageRendering) async throws -> PreparedExport

// SnapikMac/App/AppCoordinator.swift
var publishedIsSingleCapture: Bool     // только в памяти, в файлы не пишется
```

**Порции `stack`:** «Копировать снимок» зовёт `exportSingle(capture, label: capture.displayLabel,
renderer:)`, ставит `publishedIsSingleCapture = true`, кладёт результат в буфер тем же путём, что
пакет, и снимает признак следующим захватом, явным «Копировать пакет», очисткой ленты и замеченной
вставкой. Тост — `«Снимок {0} скопирован»`, ошибка — `«Не удалось скопировать снимок»`.
**Порции `editor`:** кнопка «Копировать» и Cmd+Shift+C зовут то же самое и **сами** говорят
результат своей плашкой `Hint`, потому что лента спрятана, пока редактор открыт (отклонение
tz-007). Тот же гард занятости, что у «Сохранить на компьютер».

### 4.6 `SnapikCore/Settings/SoundVolumeCurve.swift`

```swift
public enum SoundVolumeCurve {
    public static func amplitude(volume: Int, gain: Double) -> Double
}
```

Единственный вызывающий — `SnapikMac/App/UiSoundService.swift:139`. Порциям не нужен, но лежит в
Core ради тестов.

### 4.7 `UiLanguage` — что порции могут звать

Новые пары, которые понадобятся другим (после §1.3):
`«Копировать снимок»`, `«Сохранить снимок…»`, `«Снимок {0} скопирован»`,
`«Не удалось скопировать снимок»` — порции `stack` (контекстное меню карточки) и `editor` (кнопка и
шпаргалка клавиш); `«Панель разметки»`, `«Обводка»`, `«Скруглённый»`, `«Нет»` — порции `editor`
(ручка панели и блок свойств); `«Неон»` — эта порция (ряд настроек) и `editor` (поповер палитры).

Пары `«Толстая стрелка»`, `«По ширине · {0} %»`, `«По высоте · {0} %»` порция `editor` должна
**освободить** (снять своих читателей) — снимаются в волне сведения.

---

## 5. Размер работ и порядок

Объём: **S** ≤ 60 строк Swift, **M** 60–250, **L** > 250.

### 5.1 Волна 0 (Core; блокирует обе другие порции — делать первой, последовательно)

| # | Что | Объём |
|---|---|---|
| 1 | C5-1 `stackHeightManual` — поле, `CodingKeys`, `init(from:)`, `encode` | **S** |
| 2 | C5-2 `ToolAppearanceEntry` + ключ `toolAppearance` в `HotkeySettings` | **S** |
| 3 | C5-4 константы списка и четыре функции `StripResizeGeometry` (+ сведение дублей со `StackMetrics` — согласовать с `stack`) | **M** |
| 4 | C5-6 `SoundVolumeCurve` | **S** |
| 5 | C5-7 `singleCaptureLabel` в `PromptGenerator` и `FileExportService` (обязательно **явный** `init` у `PromptGenerator`) | **S** |
| 6 | C5-9 `clearsTheStrip(isSingleCapture:clearStackAfterPaste:)` | **S** |
| 7 | — (§2.6 `parentAnnotationId` правки Core **не требует**: модель на Windows не менялась, меняется только поведение редактора) | — |
| 8 | C5-5 `UiLanguage`: +9 пар (5 от 1.6.0, 4 от 1.7.0), −3 пары сразу; три отложенные и две остающиеся записать комментарием | **S** |
| 9 | Тесты Core: `SoundVolumeCurveTests`, дополнения `StripResizeGeometryTests`, `PersistenceAndExportTests`, `SettingsMigrationTests` | **M** |

Порядок внутри волны 0 жёсткий только в одном месте: пункт 5 трогает `PromptGenerator`, который
зовут восемь тестов, — правку и тесты делать одним коммитом.

### 5.2 Волна 1, моя порция (после волны 0, параллельно `stack` и `editor`)

| # | Что | Объём | Зависимости |
|---|---|---|---|
| 1 | C5-8 `SessionWorkspace.exportSingle` | **S** | C5-7 |
| 2 | C5-9 поле `publishedIsSingleCapture` + точка применения `AppCoordinator+PasteIntent.swift:133` + два гарда буфера | **S** | — |
| 3 | S5-1 высота окна 620 | **S** | — |
| 4 | S5-2 число у громкости и тик через таймер | **M** | C5-6 |
| 5 | S5-3 четвёртый сегмент «Неон» и белый список | **S** | **порция `editor`**: `EditorAppearance.palettes` должна получить неон, иначе проба A5-1 упадёт на несовпадении списков |
| 6 | S5-4 конец ряда галереи — метка; кламп `firstCard` в `layout()` | **S** | — |
| 7 | A5-1 проба вкладок + громкости + ряда палитр | **M** | 3, 4, 5 |
| 8 | A5-2 проба одиночного экспорта | **S** | 1 |
| 9 | A5-3, A5-4 правки существующих проб и языковой таблицы смоука | **S** | 8 |
| 10 | C5-3 `ToolAppearanceStore` (`SnapikMac/Editor`) + тесты | **M** | **согласование с `editor`**: файл лежит в её папке, но пишет его эта порция; договориться до старта, кто его создаёт (рекомендация — я, порция `editor` только читает) |

### 5.3 Долги, которые эта дельта осознанно не закрывает

- **Ротации `exports/revision-*` на Mac нет вовсе** (§1.5, C5-8). `exportSingle` создаёт ещё один
  каталог на каждое «Копировать снимок». Windows лечит это `TrimExports`; на Mac аналога нет ни для
  пакета, ни для одиночного экспорта. Отдельная задача, не эта дельта — но записать, потому что
  одиночная копия делает проблему заметнее.
- **Прокрутка внутри окна настроек** (§1.6, S5-1): 620 решают обрезку содержимого, а не размер
  экрана.
- **Три пары `UiLanguage`** (`Толстая стрелка`, `По ширине`, `По высоте`) снимаются в волне
  сведения после порции `editor`; **две пары** (`Свернуть в трей`,
  `Изображения и комментарии готовы к вставке`) остаются на Mac сознательно, как уже остаётся пара
  SPEC-DELTA-3 §3.3.
- **Тик громкости** слышен только живьём: смоук проверяет число и то, что таймер гасится, но не
  звук.

### 5.4 Что проверять при сведении

1. `UiLanguage.swift`: ни одного повторяющегося русского ключа и ни одного повторяющегося
   английского значения — разбирать таблицу скриптом, не грепом.
2. Каждая новая проба смоука зовётся ровно один раз, осиротевших нет; `smokeRunEditorScaleProbe`
   не осталось после удаления переключателя масштаба порцией `editor`.
3. `grep -c` по координированным символам == 1: `listHeightForCount(`, `listHeight(count:`,
   `capsuleLeft(`, `restoreRect(`, `clearsTheStrip(`, `exportSingle(`, `amplitude(volume:`,
   `ToolAppearanceStore`.
4. Числа `StackMetrics` выведены из `StripResizeGeometry`, а не продублированы.
5. Версия `1.7.0` в `macos/project.yml`.
6. `SettingsMigration.currentVersion` по-прежнему `2` — ни одна порция его не подняла.
