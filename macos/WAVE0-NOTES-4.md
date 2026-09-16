# Заметки волны 0 синхронизации №4 для порций Stack / Editor / Settings

Ветка волны 0 поверх `mac-sync-3-ci`; порции ветвятся от её коммита, первым шагом `git merge`.

## Core, вид снимка
- `enum CaptureKind: String { region, fullscreen, `import` }` (`Models/CaptureKind.swift`); писать
  `.import` через точку можно, обратные кавычки только в объявлении.
- `CaptureItem.kind` (дефолт и неизвестное слово из файла — `.region`) и `CaptureItem.monitorCount`
  (кламп `max(0,…)` в `didSet` и в обоих инициализаторах) — параметры инициализатора после `sent:`;
  `create(...)` не менялся. `title` — имя файла у импорта, пусто у области и у всего экрана.
  Проставляет поля порция Stack; `SessionValidation` про них не знает, `EditorCapture.toCore()` их
  пока не переносит — это порция Editor (E-7).
- `PromptGenerator.kindTitle(_:) -> String?` (internal, один на дерево): «весь экран» у `fullscreen`,
  `nil` у остальных; литерал по-русски, через `UiLanguage` не ходит.

## Core, отметки и настройки
- `AnnotationItem.hasOutline` → `legacyHasOutline: Bool?`, ключ JSON прежний, `decodeIfPresent` без
  дефолта, в `encode` строки нет. Правило чтения в `EditorModels.fromCore` спрашивает
  `item.legacyHasOutline == false`; никто поле не пишет.
- `SettingsMigration.currentVersion = 2`; `soundVolume(storedVersion:storedVolume:)` спрашивает `< 1`,
  новая `theme(storedVersion:storedTheme:)` — `< 2` (`light` → `dark`). `needsMigration(_:)` остался
  признаком «файл переписать», `HotkeySettings.migrate(_:)` зовёт оба правила.
- Четыре ключа разметки (`AnnotationShape/Fill/FillColor/Outline`) сняты: каждый снимок начинается с
  «контур, без заливки, прямоугольник», порция Editor их не читает.

## Core, геометрия и строки
- `minimumWidth = defaultWidth = 244`, `edgeGap = 0`, `estimatedChromeHeight = 160`,
  `StackMetrics.shadowMargin = 20`; панель 204 и карточка 168 — те же формулы.
- Stack: тень считалась под поле 10 (`panelShadowBlur 16`, `panelShadowOffset 3`), Windows при поле 20
  даёт блюр 24 и глубину 5 — решение за Stack; проба A-5 и тест «панель не меняет ширину, когда
  растёт поле под тенью» не переносились, числа `StackMetrics` — зона Stack. `positionAtEdge()` уже
  прижимает окно к краю (`work.maxX - width`), правки не требует.
- `UiLanguage`: 11 пар раунда в хвосте Windows-части (перед macOS-блоком), «Снимок всего экрана» =
  `Capture the whole screen`, сняты `Рамка` и `Рассвет`. Генератора на ветке нет, правка ручная,
  дубли ловит `SerializationCyrillicTests`. Порциям: «Пройти знакомство заново» вместо тернарника
  `SettingsTabViews.swift:96`, «экран»/«импорт» — чипы карточки, «весь экран», «мониторов: {0}»,
  «По ширине/высоте» — подпись и переключатель редактора.

## Тесты
- Новые: `SnapikCoreTests/CaptureKindTests.swift` и `SnapikMacTests/Editor/LegacyOutlineTests.swift`
  (в Mac-наборе: правило живёт в `SnapikMac`). Дописаны `SettingsMigrationTests`,
  `StripResizeGeometryTests`, `SerializationCyrillicTests`; под новый формат поправлены
  `PersistenceAndExportTests` и `CaptureCropperTests`. Новых тестовых целей нет и не заводить.
