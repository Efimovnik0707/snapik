# Заметки волны 0 синхронизации №5 для порций Stack / Editor / Settings

Волна 0 лежит коммитами прямо в `master` (от `059001e` до `63571b2`), отдельной ветки
`mac-sync-5-wave0` нет. Порции ветвятся от последнего коммита волны 0, первым шагом `git merge master`.
Компилятора на машине нет: всё ниже проверено грепами и чтением, не сборкой.

| Задача | Коммит | Что легло |
|---|---|---|
| W0-1 | `15dd2cb` | `ToolAppearanceEntry`, ключи `StackHeightManual` и `toolAppearance` |
| W0-2 | `1e69831` | константы списка и четыре функции `StripResizeGeometry` |
| W0-3 | `6dbfbae` | `SoundVolumeCurve` |
| W0-4 | `b21d10f` | `singleCaptureLabel` у `PromptGenerator` и `FileExportService` |
| W0-5 | `f0fc4f6` | `SentCaptureRules.clearsTheStrip` |
| W0-6 | `ac9a4a4` | `ToolAppearance`, `ToolAppearanceStore`, `EditorTool.appearanceKey` |
| W0-7 | `cf4bf71` | `SessionWorkspace.exportSingle` |
| W0-8 | `6ef7daf` | `UiLanguage`: +9 пар, −3 пары |
| W0-9 | `63571b2` | сводный проход по чек-листу и один правочный коммит из него |

## Core, настройки

- `public var stackHeightManual: Bool = false` сразу после `stackHeight`; JSON-ключ
  `"StackHeightManual"`. `public var toolAppearance: [String: ToolAppearanceEntry] = [:]` последним
  полем, после `customPaletteColors`; JSON-ключ `"toolAppearance"` строго camelCase, это порядок
  Windows. Оба ключа расписаны во всех четырёх местах (`CodingKeys`, `init(from:)`, `encode(to:)`).
- `SettingsMigration.currentVersion` остался `2`, ни одна порция его не поднимает.
- `ToolAppearanceEntry` (`SnapikCore/Settings/ToolAppearanceEntry.swift`) объявлен
  `Codable, Equatable, Sendable` с явным `public init(...)` и явными `CodingKeys`. Рукописного
  `encode(to:)` у него нет и заводить его нельзя: синтезированный сам зовёт `encodeIfPresent`, и
  `fillColor` исчезает из файла, когда он `nil`.
- `KeepToolAppearance` не понадобился: словарь в Swift сравнивается по содержимому, здоровый файл не
  считается мигрированным и не переписывается на каждом старте.

## Core, геометрия

- В `StripResizeGeometry` добавлены `emptyListHeight 92`, `listTopPadding 14`, `listBottomPadding 8`,
  `listPaddingLeft 4`, `listPaddingRight 12`, `cardHeight 78`, `cardOverlap 48`,
  `cardPitch = cardHeight - cardOverlap`, все `public static let Double`.
- Функции: `listHeightForCount(_ count: Int, cap: Double)`,
  `listHeight(count:stored:manual:)`, `capsuleLeft(stripLeft:stripWidth:capsuleWidth:)`.
- `restoreRect` сделан на числах, а не на `CGRect` (решение §2.5, вместо варианта `C §4.4`):

  ```swift
  public static func restoreRect(
      x: Double, y: Double, width: Double, height: Double,
      workX: Double, workY: Double, workWidth: Double, workHeight: Double
  ) -> (x: Double, y: Double)
  ```

  Разбор `NSRect` на восемь чисел и сборка обратно это зона Stack. Гард `!work.IsEmpty` отдельной
  строкой не нужен: пустая рабочая область на числах это и есть `workWidth <= 0 || workHeight <= 0`,
  и эти два сравнения стоят в том же порядке, что на Windows.
- `StackMetrics.swift` волна 0 не трогала вовсе. Порция Stack сама превращает свои константы в
  псевдонимы Core и сама правит `listPaddingLeft` 8→4, `listPaddingRight` 8→12,
  `listPaddingBottom` 52→8, `scrollBarWidth` 4→3, и снимает `listContentHeight`. Числа Core это
  `Double`, `StackMetrics` держит `CGFloat`: оборачивать `CGFloat(StripResizeGeometry.cardHeight)`.

## Core, экспорт

- `public init(singleCaptureLabel: String? = nil)` у `PromptGenerator` объявлен явно, восемь
  вызовов `PromptGenerator()` в тестах и два в `SmokeTestRunner+Stack.swift` менять не пришлось.
- `FileExportService.init(renderer:timeProvider:singleCaptureLabel:)`, третий параметр со значением
  по умолчанию. Интерфейс `ExportService` не тронут.
- Развилка «один снимок и есть буква» в обоих написана как `if/else`, а не как `??`: на Mac
  `CaptureLabels.forIndex` это `throws`, а `try` не может стоять справа от оператора.
- `SentCaptureRules.clearsTheStrip(isSingleCapture:clearStackAfterPaste:)` лежит в
  `SnapikCore/Exporting/SentCaptureRules.swift` (решение §2.2). В `ExportContracts.swift` и у
  `PreparedExport` этой функции **нет**, вариант `C §4.5` не реализован: звать надо
  `SentCaptureRules.clearsTheStrip(...)`.

## Core, звук

- `SoundVolumeCurve.amplitude(volume: Int, gain: Double) -> Double`
  (`SnapikCore/Settings/SoundVolumeCurve.swift`). Точка применения
  `SnapikMac/App/UiSoundService.swift:139` волной 0 **не тронута**, её правит порция Settings;
  гейны `0.6 / 0.25 / 0.7` не трогать.

## SnapikMac, память инструментов

- `Sources/SnapikMac/Editor/ToolAppearanceStore.swift` (internal, как всё в `SnapikMac`) держит
  `struct ToolAppearance: Equatable` и `enum ToolAppearanceStore` с `tools`, `names`, `read(_:)`,
  `write(_:tools:)`. Поля `ToolAppearance`: `color: NSColor`, `thickness: Double`,
  `lineStyle: AnnotationLineStyle`, `fill: AnnotationFill`, `fillColor: NSColor?`,
  `fontSize: Double`, `arrowStyle: String`, `shape: AnnotationShape`, с дефолтами
  `#FF3B30 / 4 / .solid / .none / nil / TextMarkMetrics.defaultFontSize / "straight" / .rectangle`.
- `ToolAppearanceStore.names` оставлен **internal**, а не private, как на Windows: из него читает
  `EditorTool.appearanceKey`, объявленный в том же файле расширением. Порциям нужен только
  `appearanceKey` и `init?(appearanceKey:)`, лезть в `names` не надо.
- HEX разбирается существующим `EditorAppearance.color(fromHex:)`, пишется существующим
  `NSColor.hexRGB`. Третьего разбора цвета в дереве не появилось.
- `read` возвращает словарь **ровно из шести** ключей (`rectangle`, `arrow`, `pen`, `highlight`,
  `text`, `blur`). `select`, `conceal`, `crop`, `comment`, `eraser` в нём отсутствуют: прямая
  индексация словаря по произвольному `EditorTool` даст `nil`, и `appearance(of:)` порции Editor
  обязана падать на набор рамки сама.
- `InspectorView`, `SecondCapsule`, `EditorInspector` волна 0 не заводила: их пишет порция Editor в
  своём файле, в дереве этих имён сейчас нет ни одного.

## SnapikMac, одиночный пакет

```swift
func exportSingle(_ capture: CaptureItem, label: String? = nil,
                  renderer: ExportImageRendering) async throws -> PreparedExport
```

Лежит в `App/SessionWorkspace.swift` рядом с `prepareExport(renderer:includingSent:)`. Сессия
собирается в памяти из одного снимка, на диск не пишется, ревизия не двигается, рендерер передаёт
вызывающий. Обрезки старых экспортов нет и не будет в этот раунд (§2.1), в коде на этом месте стоит
комментарий про долг. После волны 0 `SessionWorkspace.swift` не трогает никто.

## UiLanguage

- Добавлено 9 пар. Пять пар 1.6.0 (`«Панель разметки»`, `«Обводка»`, `«Скруглённый»`, `«Нет»`,
  `«Неон»`) стоят сразу после `«Добавить цвет в свою палитру»` и до комментария SPEC-DELTA-3 §3.3.
  Четыре пары 1.7.0 (`«Копировать снимок»`, `«Сохранить снимок…»`, `«Снимок {0} скопирован»`,
  `«Не удалось скопировать снимок»`) стоят между `«Импортировать файл…»` и
  `«Вставить изображение из буфера»`.
- Снято 3 пары: `«Цвет отметки»`, `«Тип линии»`, `«+ Снимок»`. Читателей у них не было, у последней
  только комментарии кода; кнопка «ещё снимок» подписывается парой `«Новый снимок»`.
- Ещё 4 пары остались на месте **с комментарием прямо в таблице**, их снимает сведение, а не порции:
  `«Толстая стрелка»`, `«По ширине · {0} %»`, `«По высоте · {0} %»` (после порции Editor) и
  `«Горячие клавиши…»` (после того, как порция Settings переведёт `HotkeySettingsWindowController`
  на `«Настройки клавиш»`). Порции свои пары не снимают, только освобождают читателей.
- Две пары остаются на Mac сознательно и тоже снабжены комментарием: `«Свернуть в трей»` и
  `«Изображения и комментарии готовы к вставке»`.
- В таблице 300 пар, повторов русских ключей и английских значений нет: проверено скриптом, который
  разбирает массив и считает `Counter`, а не грепом.

## Тесты

- Новые наборы: `SnapikCoreTests/SoundVolumeCurveTests.swift`,
  `SnapikCoreTests/SentCaptureRulesTests.swift`,
  `SnapikMacTests/Editor/ToolAppearanceStoreTests.swift`. Все в уже существующих целях, новых
  тестовых целей не заведено, `Package.swift` не менялся.
- Дописаны `SettingsMigrationTests` (три набора про оба ключа), `StripResizeGeometryTests` (четыре
  набора про список, капсулу и возврат прямоугольника), `PersistenceAndExportTests` (три набора про
  букву одиночного пакета плюс приватный помощник `makeSession(count:directory:)`),
  `SerializationCyrillicTests` (девять новых пар и три снятых).
- `exportSingle` своего юнита не получил: его закрывает проба `A5-2` порции Settings.

## Чего порции обязаны не делать

- Не заводить второе объявление ни одного из имён: `listHeightForCount(`, `listHeight(count:`,
  `capsuleLeft(`, `restoreRect(`, `clearsTheStrip(`, `exportSingle(`, `amplitude(volume:`,
  `ToolAppearanceStore`, `appearanceKey`, `ToolAppearanceEntry`, `SoundVolumeCurve`. На момент конца
  волны 0 каждое встречается в `Sources/` ровно один раз как объявление.
- Не заходить в `Sources/SnapikCore/**`, `App/SessionWorkspace.swift`,
  `Editor/ToolAppearanceStore.swift` и `Tests/SnapikMacTests/Editor/ToolAppearanceStoreTests.swift`:
  это файлы волны 0, порции их только читают.
- Не поднимать `SettingsMigration.currentVersion`.
- Не звать `swift build`, `swift test`, `xcodebuild`.

## Места, которые сведению стоит проверить первыми

1. `ToolAppearanceStoreTests.test_The_round_trip_keeps_every_tool_and_mirrors_the_common_keys`
   сравнивает `NSColor` целиком. Равенство держится на том, что `NSColor.hexRGB` (он ходит через
   `usingColorSpace(.deviceRGB)`) и `EditorAppearance.color(fromHex:)` (он строит `srgbRed`) дают
   один и тот же набор компонент. На это же опирается вся нынешняя запись цвета разметки в
   настройки, но отдельным тестом это до сих пор не закрывалось.
2. `HotkeySettings.encode` пишет словарь через `container.encode(toolAppearance, ...)`, а не руками,
   и `null` у `fillColor` не появляется только благодаря синтезированному `encode` у
   `ToolAppearanceEntry`. Проба round-trip `A5-3` и тест
   `test_The_manual_height_and_the_tool_settings_survive_being_written_and_read_back` проверяют это
   строкой `XCTAssertFalse(onDisk.contains("null"))`.
