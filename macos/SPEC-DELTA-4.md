# Дельта №4: Windows `1c7d727..d84fbb0` (1.5.0) → macOS

**База.** `mac-sync-base-3` = `1c7d727` (1.4.0 + переименование). Цель раунда: `mac-sync-base-4` = `d84fbb0`.
Диапазон: 38 коммитов, `src` + `tests`, 56 файлов, +2244 / −537.

**Что уже сделано порциями №3.** Синхронизация №3 (`SPEC-DELTA-3.md`) вела часть пунктов ТЗ №4 сразу в целевом виде
(пометки `[ТЗ№4]`). Проверено по коду веток, а не по спеке: сделано и переносить не надо —
шесть тем и двенадцать акцентов (`Theme.swift:85, 90-93, 309-327` на `mac-sync-3-ci`), разделитель ряда акцентов
по признаку градиента (`AppearancePickerView.swift:247-257` на `mac-sync-3-MC`), колесо над галереей
(`AppearancePickerView.swift:473-484`), один активный цвет у всех инструментов
(`OverlayEditorController.swift:85` на `mac-sync-3-MB`), захват существующего комментария якорем и бейджем
(`AnnotationCanvasView.swift:243-252, 573`), лупа пипетки (`ScreenColorPicker.swift:101-108, 225-262`),
лента без ZIndex и новый снимок сверху (`EdgeStackContentView.swift:321-322`), пустая лента
(`EdgeStackContentView.swift:333-336`, `StackMetrics.swift:60`), скроллбар 4 px без анимации
(`StackScroller.swift:60-97`), тени панели и карточки (`StackMetrics.swift:33-34, 78-82`),
перетаскивание за панель (`EdgeStackWindowController.swift:56`), `sharingType` только на время захвата
(`WindowCaptureExclusion.swift:23-31`), «Пройти знакомство заново» (`SettingsTabViews.swift:54, 96`),
подписи слайдов 140 (`HowToSlidesView.swift:18`), кнопки шапки 22 px (`StackMetrics.swift:38`),
поля списка `8,14,8,52` (`StackMetrics.swift:50-53`), карточка 168 (`StackMetrics.swift:108`).

Все ссылки Windows — по `d84fbb0`. Ссылки Swift — по веткам `mac-sync-3-*`; после их сведения
номера строк сместятся, символы остаются.

---

## 1. Резюме по модулям Mac

Объём: **S** ≤ 60 строк Swift, **M** 60–250, **L** > 250.

### 1.1 Core (`macos/Sources/SnapikCore`)

| # | Фича | Windows-источник | Целевой Swift | Объём | Статус |
|---|---|---|---|---|---|
| K-1 | `CaptureKind` (`region` / `fullscreen` / `import`) | `src/Snapik.Core/Models/CaptureKind.cs:5-10` (`be1aa81`) | новый `Models/CaptureKind.swift` | S | нет на Mac |
| K-2 | `CaptureItem.kind` + `monitorCount` (кламп `max(0, …)`), `title` получает смысл | `src/Snapik.Core/Models/CaptureItem.cs:21-28` (`be1aa81`) | `Models/CaptureItem.swift` (на `mac-sync-3-ci` поля нет: `CaptureItem.swift:1-27` знает только `sent`) | S | нет на Mac |
| K-3 | `PromptGenerator.KindTitle`: «Снимок C — весь экран.» даже без заметок | `src/Snapik.Core/Exporting/PromptGenerator.cs:23, 66` (`be1aa81`) | `Exporting/PromptGenerator.swift` (на `ci` правки раунда 3 в строках 1-12) | S | нет на Mac |
| K-4 | `hasOutline` → `LegacyHasOutline`: читается, **не пишется** | `src/Snapik.Core/Models/AnnotationItem.cs:70-79` (`3e934c7`) | `Models/AnnotationItem.swift:102, 221, 246` | S | есть частично: чтение с дефолтом `true` есть (`:221`), но `encode` всегда пишет поле (`:246`) — сделать `Bool?`, не кодировать |
| K-5 | Правило чтения: `kind == rectangle && hasOutline == false` → `fill = solid`, `fillColor = fillColor ?? strokeColor` | `AnnotationCanvas.cs:810-826` (`OutlineColorOf`) | `Editor/EditorModels.swift:216-237` (`mac-sync-3-MB`) | — | **есть целиком**, переносить нечего |
| K-6 | `SettingsMigration`: версия 2, порог на каждое правило, `light` → `dark` | `src/Snapik.App/SettingsMigration.cs:13, 25-38` (`9a7e6a5`) | `Settings/SettingsMigration.swift:9, 26-30` | S | расходится: `currentVersion = 1`, правило громкости спрашивает общий `needsMigration`, правила темы нет |
| K-7 | Геометрия ленты: `ShadowMargin 20`, `MinimumPanelWidth 204`, `Minimum = Default = 244`, `EdgeGap 0`, `ShellPadding 10`, `ListPadding 8`, `CardWidth(w)`, `EstimatedChromeHeight 160` | `src/Snapik.App/Controls/StripResizeGeometry.cs:18-40, 58` (`70d3c59`, `87e1168`) | `Geometry/StripResizeGeometry.swift:15-16, 21, 32` | S | расходится: 224 / 224, `edgeGap 10`, `estimatedChromeHeight 140`, `shadowMargin` живёт в `StackMetrics.swift:30` = 10 |
| K-8 | Пары `UiLanguage` раунда (11 новых, 3 снятых) | `src/Snapik.App/UiLanguage.cs:45, 52, 188-196` (`92a7c10`, `66ee13d`, `9a7e6a5`) | `Settings/UiLanguage.swift` | S | см. §3.4 |

### 1.2 Stack (`macos/Sources/SnapikMac/Stack`, `App`)

| # | Фича | Windows-источник | Целевой Swift | Объём | Статус |
|---|---|---|---|---|---|
| S-1 | Снимок всего экрана ложится в ленту: `CaptureFullscreenAsync`, порядок гвардов «диалог → `_busy` → `StripIsFull` → `HideForCapture`», `Kind = Fullscreen`, `MonitorCount = Screen.AllScreens.Length`, автосохранение вместо записи PNG мимо ленты | `src/Snapik.App/EdgeStackWindow.Saving.cs:45-73`; вызов `EdgeStackWindow.xaml.cs:292` (`526f2e3`) | `App/AppCoordinator.swift` (сейчас клавиша `fullscreen-save` идёт мимо ленты), `Stack/EdgeStackWindowController.swift` | M | нет на Mac |
| S-2 | Безусловный показ ленты в `finally` (была `if (wasVisible)`) | `EdgeStackWindow.Saving.cs:72` | там же | S | нет на Mac (следствие S-1) |
| S-3 | Импорт: `Kind = Import`, `Title = Path.GetFileName(path)`, перевод окна сразу после `Renumber()` | `EdgeStackWindow.xaml.cs:1052-1085` | `App/AppCoordinator.swift:210` (`importFiles()`), `Stack/EdgeStackContentView.swift` | S | есть частично: импорт есть, `kind` и `title` не проставляются, чипа нет |
| S-4 | Чипы карточки «экран» / «импорт» + `Stretch=Uniform` у снимка всего экрана | `EdgeStackWindow.xaml:257-267, 293-300` (`526f2e3`) | `Stack/ThumbnailCardView.swift` (на `MA` карточка знает только букву и галочку: `:124-126`) | M | нет на Mac |
| S-5 | Геометрия 244 / 20 / 0 в окне и позиционировании у края | `StripResizeGeometry.cs:18-40`; `EdgeStackWindow.xaml` | `Stack/StackMetrics.swift:30`, `Stack/EdgeStackWindowController.swift` (`positionAtEdge`) | S | расходится, см. K-7 и §3.1 |
| S-6 | Лента показывается после мастера: из `OnLoaded` после `PositionAtEdge()`, а не сразу после `ShowDialog` | `EdgeStackWindow.xaml.cs:226-232` (`db43426`) | `App/AppCoordinator.swift:164-177` | S | нет на Mac: мастера в `AppCoordinator` ещё нет вовсе (`OnboardingWindowController.swift:45` на `MC` помечает хук как «волна 2 №3») |
| S-7 | Иконки ленты на глифах системного шрифта | `EdgeStackWindow.xaml`, `IconFont` (`65d962e`, `8e72591`) | `Editor/IconPath.swift`, `Stack/*` | S | адаптация: на Mac уже SF Symbols (`EditorToolbarView.swift:80-86` на `MB`); переносить только правило «своих пиктограмм не рисовать» |
| S-8 | Пустая лента, скроллбар, тени, порядок карточек, drag за панель, `sharingType` | — | — | — | **есть целиком** (см. шапку) |

### 1.3 Editor + Imaging (`macos/Sources/SnapikMac/Editor`, `Imaging`)

| # | Фича | Windows-источник | Целевой Swift | Объём | Статус |
|---|---|---|---|---|---|
| E-1 | `EditorGeometry`: чистые `Fit` / `ClampOffset` / `ZoomAround` | `src/Snapik.App/Controls/EditorGeometry.cs:7-56` (`96b3786`) | `Editor/EditorGeometry.swift` (дописать; `FitBound` и `FitResult` — новые типы) | M | нет на Mac |
| E-2 | `ViewScale` (`nil` = «вписать») и `ViewOffset` на канве; все замеры от `_imageRect` | `Controls/AnnotationCanvas.cs:72-91, 190, 1033-1034` | `Editor/AnnotationCanvasView.swift:138-142` (сейчас только `fitRect` / `displayScale`) | L | нет на Mac |
| E-3 | Колесо прокручивает, Shift — вбок, Ctrl+колесо — масштаб на десятую вокруг курсора, потолок 1:1, возврат в «вписать» на `FitScale` | `AnnotationCanvas.cs:1039-1061` | `AnnotationCanvasView.scrollWheel(with:)` | M | нет на Mac |
| E-4 | Пробел + мышь тянет картинку (`Panning`) | `AnnotationCanvas.cs:99-100, 224-228, 333, 398-399`; клавиша `OverlayEditorWindow.xaml.cs:1958` | `Editor/OverlayEditorController+Keys.swift`, `AnnotationCanvasView` | S | нет на Mac |
| E-5 | Переключатель «По ширине · 35 %» / «По высоте · 23 %» ↔ «1:1», виден только у уменьшенного снимка; `SyncScaleSwitch()` | `OverlayEditorWindow.xaml:291-298`; `.xaml.cs:1677-1714` | новый `Editor/EditorScaleSwitchView.swift` + `OverlayEditorController` | M | нет на Mac |
| E-6 | Укладка панели считает ширину переключателя | `OverlayEditorWindow.xaml.cs:1741-1746` | `Editor/OverlayContentView.swift` / раскладка тулбара | S | нет на Mac |
| E-7 | Подпись вида снимка сверху справа: «весь экран · мониторов: 2 · 3840×1125» либо имя импортированного файла с размером | `OverlayEditorWindow.xaml:180` (`ShotKindText`); `.xaml.cs:1649-1650` | `Editor/OverlayContentView.swift` | S | нет на Mac |
| E-8 | При прокрученной картинке ручки рамок и пилюли ушедших отметок убираются | `OverlayEditorWindow.xaml.cs:1592` | `AnnotationCanvasView+Drawing.swift` | S | нет на Mac |
| E-9 | «+» рядом с HEX: сохранить цвет в свою палитру из любой показанной палитры | `OverlayEditorWindow.xaml:333` (`OnAddColorClick`) | `Editor/EditorAppearancePopover.swift` | S | нет на Mac |
| E-10 | `HasColor` удалено, `HasStroke` — явный список инструментов | `OverlayEditorWindow.Appearance.cs:39` | `Editor/OverlayEditorController.swift:85` | — | **есть целиком** (`[ТЗ№4 D1]`) |
| E-11 | Лупа пипетки: 16 пикселей ×8, сетка, центр обведён, HEX, зеркалирование у края | `Controls/ScreenColorPicker.cs:34, 69-76, 142` | `Editor/ScreenColorPicker.swift:101-108, 225-262` | — | **есть целиком**; остаётся правка альфы, §5 |
| E-12 | `FrameCopy.Detach` | `src/Snapik.App/Imaging/FrameCopy.cs:14-19`; `SessionWorkspace.cs:282-286` (`d4a55d9`) | — | — | **не переносится**, обоснование §4.4 |

### 1.4 Settings + Onboarding (`macos/Sources/SnapikMac/Settings`, `Onboarding`)

| # | Фича | Windows-источник | Целевой Swift | Объём | Статус |
|---|---|---|---|---|---|
| T-1 | Название клавиши «Снимок всего экрана» | `UiLanguage.cs:52` | `Settings/UiLanguage.swift:89`, `Settings/SettingsTabViews.swift:162` | S | расходится по английской стороне, §3.3 |
| T-2 | «Пройти знакомство заново» через таблицу, а не литералом по месту | `UiLanguage.cs:188` | `Settings/SettingsTabViews.swift:96` (на `MC` тернарник по `language`) | S | есть частично: строка есть, локализована по месту → перевести на `MacUiText.text(_:language:)` |
| T-3 | Флаг «размещено один раз»: ставится после успешного размещения, `dpiChanged` — только страховка | `OnboardingWindow.xaml.cs:101-136` (`_placed`) | `Onboarding/OnboardingWindowController.swift:189-195` | S | нет на Mac: аналог `_placed` отсутствует |
| T-4 | Мастер меряет монитор под курсором, весь верхний пояс тянет | `OnboardingWindow.xaml.cs:112, 144` | `OnboardingWindowController.swift:83, 189-195` | — | **есть целиком** |
| T-5 | Галерея тем колесом, разделитель по признаку, подписи 140 | — | — | — | **есть целиком** |
| T-6 | Скругление окна через DWM | `src/Snapik.App/DwmWindowCorners.cs:1-76` (`2ad6efc`) | — | — | **не переносится**: на macOS скругление и тень даёт система (`SPEC-DELTA-3` O-1) |
| T-7 | Правило слияния настроек мастера вынесено в `MergeOnboarding(stored, candidate)`, его же зовёт `WriteOnboarding` | `EdgeStackWindow.xaml.cs:1269-1284` | `Settings/HotkeySettingsWindowController.swift` / `App/AppCoordinator.swift` | S | нет на Mac (нужно вместе с S-6) |

### 1.5 App + Smoke (`macos/Sources/SnapikMac/App`)

| # | Фича | Windows-источник | Целевой Swift | Объём | Статус |
|---|---|---|---|---|---|
| A-1 | Проба «снимок всего экрана называет себя» | `SmokeTestRunner.cs:578` (`VerifyAWholeScreenCaptureNamesItselfAsync`) | `App/SmokeTestRunner+Stack.swift` | S | нет на Mac |
| A-2 | Проба «файл с диска доезжает до ленты» | `SmokeTestRunner.cs:579` | `App/SmokeTestRunner+Stack.swift` | S | нет на Mac |
| A-3 | Проба масштаба редактора на снимке 3840×1125 | `SmokeTestRunner.cs:460` (`RunEditorScaleProbe`); тело `OverlayEditorWindow.xaml.cs:523-530` | `Editor/OverlayEditorController+SmokeTest.swift` | M | нет на Mac |
| A-4 | Проба «мастер сохраняет вид через `MergeOnboarding`» | `SmokeTestRunner.cs:580` (`VerifyTheWizardKeepsItsAppearance`) | `App/SmokeTestRunner+Settings.swift` | S | нет на Mac |
| A-5 | `VerifyStripIsBoundedByItsMonitor` с новым клампом ширины | `SmokeTestRunner.cs:49, 822` | `App/SmokeTestRunner+Stack.swift` | S | есть частично: проба есть, числа старые |
| A-6 | Версия 1.5.0 | `src/Snapik.App/Snapik.App.csproj` (`364226b`) | `macos/project.yml` | S | нет на Mac |

**Итого дельты:** 30 позиций к работе (9 Core, 7 Stack, 9 Editor, 3 Settings, 6 Smoke — с пересечениями по таблицам),
из них «нет на Mac» 21, «есть частично» 5, «расходится» 4. Плюс 16 позиций уже закрыты порциями №3 и 3 не переносятся.

---

## 2. Изменения формата

Сверено с `tasks/verification.md:903-917` (семь абзацев «Изменение формата»).

### 2.1 `session.json`: `captures[].kind`, `monitorCount`, `title`

Целевой вид:

```json
{ "id": "…", "sourceImagePath": "…", "title": "IMG_0512.png",
  "kind": "region" | "fullscreen" | "import", "monitorCount": 2, … }
```

- `kind` пишется всегда, дефолт `region`; неизвестное значение читается как `region`.
- `monitorCount` — `Int`, дефолт `0`, заполняется только у `fullscreen`; отрицательное из чужого файла
  приводится к `0` при чтении (`CaptureItem.cs:28`). `SessionValidation` про эти поля не знает — на Mac
  `Models/SessionValidation.swift` не трогать.
- `title`: у импорта — имя файла, у области и у всего экрана — пустая строка.
- `SchemaVersion` остаётся 1, миграции нет: файл до 1.5.0 читается как `region` / `0` / `""`.
- Следствие для `prompt.md`: снимок всего экрана и импорт дают строку «Снимок C — весь экран.» /
  «Снимок D — IMG_0512.png.» даже без заметок, тогда как раньше снимок без заметок в текст не попадал.
  Слово «весь экран» в `prompt.md` — литерал по-русски, через `UiLanguage` не ходит
  (`PromptGenerator.cs:66`), на Mac так же.

### 2.2 `session.json`: `hasOutline` выведен из обращения

- **Запись:** начиная с 1.5.0 `hasOutline` не пишется вообще. На Mac `AnnotationItem.swift:102` объявлено
  `public var hasOutline: Bool` и безусловно кодируется (`:246`) — заменить на `public var legacyHasOutline: Bool?`
  с `CodingKeys` `case legacyHasOutline = "hasOutline"`, `decodeIfPresent`, и **не** кодировать
  (`encodeIfPresent` не годится, поле не восстанавливается: просто убрать строку `:246`).
- **Чтение:** если `kind == "rectangle"` и `hasOutline == false` → отметка читается как сплошная заливка
  одним цветом: `fill = .solid`, `fillColor = fillColor ?? strokeColor`. Во всех прочих случаях
  (поле отсутствует, `true`, либо `kind != rectangle`) поле игнорируется.
  Это правило на Mac **уже реализовано**: `Editor/EditorModels.swift:216-237` на `mac-sync-3-MB`
  (`solidWithoutOutline`, `parseFillColor(item.fillColor) ?? (solidWithoutOutline ? strokeColor : nil)`).
  Остаётся снять запись и переименовать поле.
- Старая отметка `kind == "redaction"` читается как прежде: `fill = solid`, `fillColor = #FF000000`
  (`EditorModels.swift:211-215, 234-236`) — не трогать.
- Обратной совместимости назад нет: сессия 1.5.0 в 1.4.0 откроется с контуром там, где его не было.
  Принято осознанно, Mac переносит один в один.

### 2.3 `settings.json`: четыре поля разметки выведены из обращения

`annotationOutline`, `annotationShape`, `annotationFill`, `annotationFillColor` больше не пишутся и не читаются;
старые значения игнорируются и исчезают при первой перезаписи. Каждый снимок начинается с «контур, без заливки,
прямоугольник». Между снимками запоминаются только цвет, толщина, размер шрифта, палитра, ряд «Своей»,
карандаш/маркер. На Mac эти ключи перечислены в `SPEC-DELTA-3.md:158` — снять их из
`Settings/HotkeySettings.swift` (кодирование и декодирование) и из дефолтов.

### 2.4 `settings.json`: `SettingsVersion` 1 → 2 и пороги миграции

Целевой `SettingsMigration.swift`:

```swift
public static let currentVersion = 2
public static func soundVolume(storedVersion: Int, storedVolume: Int) -> Int {
    storedVersion < 1 && storedVolume == previousDefaultSoundVolume ? defaultSoundVolume : storedVolume
}
public static func theme(storedVersion: Int, storedTheme: String) -> String {
    storedVersion < 2 && storedTheme.lowercased() == "light" ? "dark" : storedTheme
}
```

Каждое правило спрашивает **свой** порог, а не `needsMigration(_:)`: общий порог прогнал бы правило громкости
второй раз по файлам версии 1 и вернул 40 тем, кто выставил 60 руками (`SettingsMigration.cs:22-28`).
`needsMigration(_:)` остаётся только признаком «файл надо переписать». Файл переписывается один раз при чтении.
Тема `light` при `storedVersion < 2` читается как `dark`: карточка «Светлая» ушла, `Рассвет` и есть светлая тема.

### 2.5 `settings.json`: ширина ленты

`MinimumWidth` 200 → **244**, `DefaultWidth` 208 → **244**. Состав полей не меняется, меняется трактовка:
сохранённая `StackWidth` меньше 244 поднимается до 244 существующим `clampWidth`. Видимая панель становится
на 20 px уже: поле ушло под тень. Видимый зазор до края экрана остаётся 20 px — раньше это было поле 10
плюс `EdgeGap` 10, теперь поле 20 при `EdgeGap = 0`. Mac переносит числа целиком: окно 244, поле 20,
панель 204, карточка 168, `edgeGap` 0.

### 2.6 `settings.json`: темы и акценты

Шесть тем, двенадцать акцентов, два новых токена ползунка (`ScrollThumbBrush`, `ScrollThumbHoverBrush`)
в каждой палитре, неизвестное значение гаснет в `blue` / `dark`. **Уже сделано** порциями №3
(`Theme.swift:85, 90-93, 309-327`, токены ползунка читает `StackScroller.swift:76-77`).
В дельте №4 остаётся только правило миграции `light → dark` из §2.4.

### 2.7 Изменение поведения (не схема): клавиша «весь экран»

Клавиша перестала писать PNG прямо в папку: снимок идёт в ленту и попадает в папку автосохранением.
При выключенном «Автоматически сохранять готовые снимки» файл в папку не падает вовсе.
Id клавиши `fullscreen-save` и поле `FullscreenSaveId` не меняются. Порядок гвардов переносится дословно:
проверка потолка ленты **раньше** скрытия окон (`EdgeStackWindow.Saving.cs:53, 57`).
Скрытая пользователем лента после такого снимка показывается всегда (`:72`).

---

## 3. Расхождения, которые надо привести к Windows

### 3.1 Геометрия ленты: 244 / 20 / 0 против 224 / 10 / 10

`mac-sync-3` взяла промежуточные числа ТЗ (§C4: 224), Windows свёл их с §C6 и получил 244.

| Константа | Mac сейчас | Целевое | Файл |
|---|---|---|---|
| `minimumWidth` | 224 | **244** | `Geometry/StripResizeGeometry.swift:15` |
| `defaultWidth` | 224 | **244** | `Geometry/StripResizeGeometry.swift:16` |
| `edgeGap` | 10 | **0** | `Geometry/StripResizeGeometry.swift:21` |
| `estimatedChromeHeight` | 140 | **160** | `Geometry/StripResizeGeometry.swift:32` |
| `shadowMargin` | 10 | **20** | `Stack/StackMetrics.swift:30` |
| `panelWidth` | 204 (= 224 − 2×10) | 204 (= 244 − 2×20) | `Stack/StackMetrics.swift:100` — формула та же, число не меняется |
| `cardWidth` | 168 | 168 | `Stack/StackMetrics.swift:108` — не трогать |

Windows выражает панель и карточку формулами, а не литералами (`StripResizeGeometry.cs:21-40`);
на Mac они уже выведены, поэтому правка — пять констант. Проверить `positionAtEdge()`
(`Stack/EdgeStackWindowController.swift`): при `edgeGap = 0` видимый зазор даёт поле под тенью,
окно прижимается к краю рабочей области вплотную.

### 3.2 Пустая лента по содержимому

На Mac высота при пустой ленте — `chromeHeight + emptyHintHeight` (`EdgeStackContentView.swift:445`),
список и ручка прячутся (`:333-336`), ручка не возвращается из капсулы (`:379` считает `collapsed || rows.isEmpty`).
Это и есть целевое поведение Windows (`EdgeStackWindow.xaml.cs:1398-1410`), включая HIGH-находку ревью.
Дописать одно: Windows первым снимком разворачивает список **до запомненной высоты**
(`UpdateEmptyState` возвращает `CaptureList.Visibility`, а высоту несёт сам список через `PositionAtEdge`).
Проверить, что `EdgeStackWindowController` помнит `listHeight` через пустое состояние и не сбрасывает
его в `defaultListHeight`. Текст подсказки — через новые пары §3.4, сейчас `applyEmptyHintText()`
строит его сам (`EdgeStackContentView.swift:341-344`).

### 3.3 Название клавиши «Снимок всего экрана»

`UiLanguage.swift:89` на `mac-sync-3-ci`: `("Снимок всего экрана", "Whole-screen capture")`.
Windows (`UiLanguage.cs:52`): `["Снимок всего экрана"] = "Capture the whole screen"`.
Русская сторона совпала, английская разошлась. Привести к Windows: смоук-проверка «ни одного
повторяющегося английского значения» опирается на точное совпадение таблиц.

### 3.4 Пары `UiLanguage` из волны 0 Windows

Diff `src/Snapik.App/UiLanguage.cs` между `1c7d727` и `d84fbb0`.

**Добавить в `UiLanguage.swift` (11 пар, ни одной нет на `mac-sync-3-ci`):**

```
("Пройти знакомство заново", "Take the tour again")
("Нажми {0} или «Новый снимок»", "Press {0} or \"New capture\"")
("Нажми «Новый снимок»", "Press \"New capture\"")
("экран", "screen")
("импорт", "import")
("Не удалось снять экран", "The screen could not be captured")
("весь экран", "whole screen")
("мониторов: {0}", "monitors: {0}")
("По ширине · {0} %", "Fit width · {0} %")
("По высоте · {0} %", "Fit height · {0} %")
("Добавить цвет в свою палитру", "Add the colour to my palette")
```

`("Пройти знакомство заново", …)` заменяет тернарник `SettingsTabViews.swift:96` на `MC`.
`("весь экран", "whole screen")` — интерфейсная пара для подписи редактора; литерал `prompt.md` из §2.1
это отдельная строка и через таблицу не ходит.

**Изменить (1):** `("Снимок всего экрана", "Whole-screen capture")` → `"Capture the whole screen"`
(`UiLanguage.swift:89`).

**Снять (2):** `("Рамка", "Frame")` (`UiLanguage.swift:178`) и `("Рассвет", "Dawn")` (`UiLanguage.swift:78`).
Windows снял обе: переключатель контура удалён вместе с флагом (§2.2), а имя темы живёт теперь
только в паре `("Светлая · Рассвет", "Light · Dawn")` (`UiLanguage.cs:45`). Пары `("Показывать рамку", …)`
на Mac нет — проверять нечего. Перед снятием `("Рамка", "Frame")` убедиться, что на неё не ссылается
`Editor/EditorStrings.swift` и поповер внешнего вида.

**Уже на месте:** `("розовый","rose")`, `("бирюзовый","cyan")`, `("розово-фиолетовый","rose to violet")`,
`("бирюзово-синий","cyan to blue")`, `("Светлая · Рассвет","Light · Dawn")` — `UiLanguage.swift:62-73`.

Порядок пар в файле держать тот же, что на Windows: §5 `SYNC.md` требует «в том же порядке».

### 3.5 Подпись «мониторов: {0}»

Windows строит подпись редактора из трёх частей: `весь экран · мониторов: 2 · 3840×1125`, причём
`мониторов: {0}` добавляется только при `MonitorCount > 1` (`OverlayEditorWindow.xaml.cs:1649-1650`).
На Mac ни подписи, ни `monitorCount` нет — заводить вместе с K-2 и E-7.

---

## 4. Редактор с масштабом (C8 / D5)

### 4.1 Модель

`AnnotationCanvas` получил два свойства (`Controls/AnnotationCanvas.cs:72-91`):

- `ViewScale: double?` — `null` означает «вписать», число — фиксированный масштаб (потолок 1).
- `ViewOffset: Vector` — на сколько прокручена картинка; прямоугольник рисуется от `-ViewOffset`.

`OnRender` выбирает прямоугольник одной строкой (`:190`):
`_imageRect = ViewScale is { } s ? ScaledRect(s) : FitRect(...)`. Все одиннадцать мест, считающие от
`_imageRect`, следуют без своей строки. `ScaledRect` зажимает офсет через `EditorGeometry.ClampOffset`
(`:1033-1034`). В режиме 1:1 канва рисует сами пиксели, поэтому шов двух мониторов не смазан.

`Controls/EditorGeometry.cs` — три чистые функции, тесты `EditorGeometryTests.cs`:

- `Fit(imageW, imageH, boxW, boxH) -> FitResult(Scale, BoundBy)`, `BoundBy ∈ {None, Width, Height}`;
  `scale >= 1` → `(1, None)`, то есть снимку, который влезает, переключать нечего (`:24-31`).
- `ClampOffset(image, scale, viewport, offset)`: ось, по которой картинка короче вьюпорта, центрируется
  отрицательным офсетом `-(box - picture)/2`; иначе `clamp(offset, 0, picture - box)` (`:39-44`).
- `ZoomAround(cursor, offset, fromScale, toScale)`: точка под курсором остаётся на месте (`:51-56`).

**Порт:** `macos/Sources/SnapikMac/Editor/EditorGeometry.swift` уже существует (там живёт
`gestureThreshold` и геометрия чипов) — дописать `FitBound`, `FitResult`, `fit`, `clampOffset`, `zoomAround`
туда же, новых файлов не заводить. `Vector` → `CGPoint` или `CGVector`; знак офсета сохранить Windows-овский
(офсет положительный = картинка уехала влево/вверх).

### 4.2 Жесты

- Колесо без модификаторов: `ViewOffset += (0, travel)`, с Shift — `(travel, 0)` (`AnnotationCanvas.cs:1061`).
- Ctrl+колесо: `wanted = clamp(scale * pow(1.1, delta/120), FitScale, 1)`; если `wanted <= FitScale` —
  возврат в режим «вписать» (`ViewScale = null`, `ViewOffset = default`), иначе
  `ViewOffset = ZoomAround(...)`, затем `ViewScale = wanted` (`:1042-1054`). На macOS модификатор зума —
  **Cmd**, как в заготовке (`PreviewImageScrollView.swift:27-28` на `mac-preview-zoom-stash`).
- Пробел: `Panning = true`, нажатие тянет картинку независимо от того, что под курсором
  (`:99-100, 224-228, 333`), курсор становится «рукой» (`:398-399`); клавиша ловится
  в `OverlayEditorWindow.xaml.cs:1958`.

### 4.3 Как использовать заготовку `mac-preview-zoom-stash`

Ветка `mac-preview-zoom-stash` (`57503c4`) содержит `Preview/PreviewImageScrollView.swift`:
`NSScrollView` с `allowsMagnification = true`, `minMagnification = 0.05`, `maxMagnification = 4`,
плоским `PreviewImageContentView` (`:8-23`), колбэками `onViewportResized` и `onMagnificationChanged`
(`:34-39`) и Cmd+колесом. Файл писался для окна предпросмотра, которое порциями №3 снесено целиком
(`Preview/*` удалены на всех четырёх ветках).

**Решение: брать идеи, не файл.** Причины:

1. `NSScrollView.magnification` масштабирует **весь** `documentView`, включая слои отметок. Редактору
   нужно, чтобы картинка масштабировалась, а ручки, бейджи и пилюли рисовались в экранных пикселях —
   ровно это и делает `_imageRect` на Windows. С `magnification` пришлось бы контр-масштабировать
   каждый оверлей.
2. Windows-контракт задан тремя чистыми функциями с тестами (E-1). Свой `viewScale` / `viewOffset`
   в `AnnotationCanvasView` их переиспользует один в один; `magnification` дал бы вторую модель
   истины и рассинхрон с `SyncScaleSwitch` (это ровно та MEDIUM-находка ревью, §5.3).
3. `minMagnification 0.05` / `maxMagnification 4` противоречат потолку 1:1 из ТЗ.

**Что взять:** `PreviewImageContentView` как образец flipped-вью, который блитит `CGImage`
в `bounds` (`:8-23`, `translateBy` + `scaleBy(x:1,y:-1)` + `ctx.draw`) — это и есть режим 1:1
без промежуточного ресэмпла; `onViewportResized` через `NSView.frameDidChangeNotification`
(`:56-58`) как способ пересчитать `fit` при смене размера окна; комментарий `CHECK-API` (`:54-55`)
оставить в порту, API не проверялось компилятором. Саму `PreviewImageScrollView` в дерево не возвращать.

### 4.4 C9 (`FrameCopy`) — не переносится

Windows: `BitmapFrame` держит декодер и поток, а замороженный кадр всё равно небезопасно кодировать
с другого потока, потому что небезопасен декодер за ним. `FrameCopy.Detach` делает `WriteableBitmap`
и замораживает копию (`Imaging/FrameCopy.cs:14-19`), `SessionWorkspace.LoadBitmap` зовёт её сразу
(`SessionWorkspace.cs:282-286`).

На Mac аналога проблемы нет. `CGImageSourceCreateImageAtIndex` возвращает `CGImage`, который владеет
своими данными и не связан ни с потоком-создателем, ни с живым `CGImageSource`: `CGImage` иммутабелен
и потокобезопасен для чтения, источник можно отпустить сразу. Декодирование ленивое, но оно происходит
в потоке, который первым коснётся пикселей, без привязки к исходному. Текущий `Imaging/ImageCodec.swift:34-42`
на `mac-sync-3-MB` — обычные `CGImageSourceCreate*` без обходных путей, и этого достаточно.
Переносится только **тест-намерение**: «картинка, прочитанная с диска, кодируется с фонового потока»
(§6, аналог `FrameCopyTests.A_detached_copy_is_encoded_from_a_pool_thread`); сам `FrameCopy` не заводить.

---

## 5. Исправления из ревью раунда

`tasks/tz-005-notes.md:130-168`. Аналог на Mac есть у пяти из семи.

1. **Ручка угла после капсулы (HIGH).** Windows: `ExpandFromCapsule` поднимал `CornerGrip` безусловно;
   владельцем стал `UpdateEmptyState()` (`EdgeStackWindow.xaml.cs:682-691, 1398-1404`).
   На Mac уже верно: `EdgeStackContentView.swift:379` считает `collapsed || rows.isEmpty`.
   **Аналога проблемы нет**, но владельцев два (`:336` и `:379`) — при правке §3.2 свести в один метод,
   чтобы не завести тот же баг позже.
2. **Чип «импорт» при смене языка (HIGH).** Аналог **есть**: карточка на Mac локализуется явным
   `card.applyLocalization(language:)` в `refresh` (`EdgeStackContentView.swift:327`), а чипов ещё нет.
   Вводя чипы (S-4), локализовать их там же и не литералом — тогда карточка, родившаяся в открытой
   ленте при `en`, приедет уже переведённой. Windows решает это вызовом `UiLanguage.Apply(this)`
   после `Renumber()` (`EdgeStackWindow.xaml.cs:1083`).
3. **`SyncScaleSwitch` (MEDIUM).** Аналог **есть и обязателен**: сеттер `ViewScale` при равном значении
   выходит рано и события не шлёт, поэтому повторное нажатие на активный сегмент гасило оба.
   Оба обработчика зовут `SyncScaleSwitch()` сами (`OverlayEditorWindow.xaml.cs:1694-1695, 1706-1707`).
   На Swift `didSet` при равном значении **сработает**, что маскирует баг, — всё равно звать явно
   из обоих обработчиков, чтобы поведение не зависело от того, `didSet` там или `guard`.
4. **`_placed` мастера (MEDIUM).** Аналог **есть**: мастер прыгал в центр при переносе на монитор
   другого масштаба, потому что флаг поднимался только в `OnDpiChanged`. Целевое: флаг ставится
   в конце размещения, обработчик смены масштаба — только страховка (`OnboardingWindow.xaml.cs:113, 131-132`).
   На Mac (`OnboardingWindowController.swift:189-195`) флага нет; эквивалент сигнала —
   `NSWindow.didChangeBackingPropertiesNotification` / `windowDidChangeScreen`. Завести `private var placed = false`
   и не переразмещать окно повторно (T-3).
5. **Альфа лупы (PLAUSIBLE).** Windows: `CopyFromScreen` в `Format32bppPArgb` оставляет альфу как нашёл,
   копия заливает её `0xFF` (`Controls/ScreenColorPicker.cs:217-228`). Аналог **возможен**:
   проверить `bitmapInfo` источника лупы в `Editor/ScreenColorPicker.swift:101-108` — если контекст
   создаётся с `premultipliedFirst`/`premultipliedLast` без гарантии непрозрачности, поставить
   `.noneSkipFirst` либо заливать альфу единицей перед показом. Стекло лупы не должно быть прозрачным.
6. **`RemoveHook` (LOW).** Windows: `AppearancePicker` снимает оконный хук перед установкой, иначе второй
   `Loaded` без `Unloaded` даёт два хука и два шага галереи на один поворот колеса
   (`Controls/AppearancePicker.xaml.cs:76-79`). Аналог **есть**: на Mac галерея ловит колесо переопределением
   `scrollWheel(with:)` (`AppearancePickerView.swift:473`), а не монитором событий, поэтому дубля хука
   там нет. Но `NSEvent.addLocalMonitorForEvents` в других местах Mac-кода парного `removeMonitor`
   требует; образец правильного teardown — `Hotkeys/GlobalHotkeyService.swift:54-59`.
   Проверить по этому правилу новые вью раунда (переключатель масштаба, чипы), мониторов не заводить.
7. **Мелочи Windows без аналога:** возврат комментария к `VerifyTheAccentsOfTheRound`, снятый устаревший
   комментарий про «переключатель контура», отступы четырёх строк `Unregister("fullscreen-save")`.
   Переносить нечего.

**Замечание без правки кода**, которое надо перенести: безусловный показ ленты в `finally`
(§2.7, `EdgeStackWindow.Saving.cs:72`) оставлен сознательно — на Mac тоже безусловный.

---

## 6. Тесты

`git diff --stat 1c7d727..d84fbb0 -- tests`: 9 файлов, 4 новых. Новых тестовых целей на Mac не заводить —
всё раскладывается по существующим `macos/Tests/SnapikCoreTests` и `macos/Tests/SnapikMacTests`.

| Windows-файл | Тесты | Swift-набор |
|---|---|---|
| `tests/Snapik.Core.Tests/CaptureKindTests.cs:15, 42, 60` | снимок до появления `kind` читается как `region`; `fullscreen` переживает файл; вид говорит за снимок в `prompt.md` | новый `SnapikCoreTests/CaptureKindTests.swift` (набор существует, файл новый) |
| `tests/Snapik.App.Imaging.Tests/LegacyOutlineTests.cs:20, 29, 40, 49` | рамка без контура берёт цвет обводки; рамка без контура со своим `fillColor` его сохраняет; флаг `true`/отсутствует читается как пустой; стрелка без контура не трогается | новый `SnapikCoreTests/LegacyOutlineTests.swift` (правило живёт в `EditorModels.swift`, но чистое — годится в Core-набор; при желании `SnapikMacTests/Editor/`) |
| `tests/Snapik.App.Imaging.Tests/EditorGeometryTests.cs:14-58` | шесть: снимок двух мониторов вписан по ширине; высокий импорт по высоте; влезающий снимок переключать нечем; офсет не пускает край внутрь; короткая ось центрируется; точка под курсором стоит | новый `SnapikMacTests/Editor/EditorGeometryTests.swift` (рядом с `EditorGeometryChipTests.swift`) |
| `tests/Snapik.App.Imaging.Tests/SettingsMigrationTests.cs:36, 50` | громкость, выставленная руками, переживает версию после своей; снятая тема `light` становится `dark` (теория по `storedVersion`) | дописать в `SnapikCoreTests/SettingsMigrationTests.swift` (есть на всех ветках №3, 198 строк) |
| `tests/Snapik.App.Imaging.Tests/FrameCopyTests.cs:18, 31` | копия заморожена и того же размера; копия кодируется с потока пула | **не переносить** как есть (§4.4). Оставить один тест намерения в `SnapikMacTests/Imaging/ImageCodecTests.swift`: прочитанный с диска `CGImage` кодируется с фонового потока |
| `tests/Snapik.App.Imaging.Tests/StripResizeGeometryTests.cs` (+28) | кламп ширины под 244 | дописать в `SnapikCoreTests/Geometry/StripResizeGeometryTests.swift` (173 строки на ветках №3) |
| `tests/Snapik.Core.Tests/PersistenceAndExportTests.cs` (+21) | round-trip сессии с `kind` / `monitorCount` / `title` | дописать в `SnapikCoreTests/PersistenceAndExportTests.swift` (281 строка) |
| `tests/Snapik.Core.Tests/CaptureCropperTests.cs` (+5) | обрезка переживает `kind` | дописать в `SnapikCoreTests/CaptureCropperTests.swift` |

**Smoke** (`macos/Sources/SnapikMac/App/SmokeTestRunner*.swift`), по одному вызову на пробу:

- `verifyAWholeScreenCaptureNamesItself` — Windows `SmokeTestRunner.cs:578`;
- `verifyAFileFromDiskReachesTheStrip` — `:579`;
- `verifyTheWizardKeepsItsAppearance` через `mergeOnboarding(stored:candidate:)` — `:580`
  (проба должна гонять настоящую запись, а не round-trip файла мимо кода мастера);
- `runEditorScaleProbe` на снимке 3840×1125 — `:460`, тело `OverlayEditorWindow.xaml.cs:517-531`;
- `verifyStripIsBoundedByItsMonitor` — `:822`, обновить числа под 244 / `edgeGap 0`;
- `verifyGestureRules` / `verifyHoverManipulation` — `:435-436`, правила захвата уже есть на `MB`
  (`OverlayEditorController+SmokeTest.swift`), проверить, что масштаб их не ломает.

---

## 7. Порядок реализации

### Волна 0: Core, один исполнитель, последовательно

Файлы: `SnapikCore/Models/*`, `SnapikCore/Settings/*`, `SnapikCore/Exporting/PromptGenerator.swift`,
`SnapikCore/Geometry/StripResizeGeometry.swift`, `SnapikMac/Stack/StackMetrics.swift` (одна константа).

1. `CaptureKind.swift`, `CaptureItem.kind` / `monitorCount` / смысл `title`, `PromptGenerator.kindTitle` (K-1…K-3).
2. `AnnotationItem.legacyHasOutline`: `Bool?`, ключ `hasOutline`, `decodeIfPresent`, снять `encode` (K-4).
3. `SettingsMigration`: версия 2, пороги, `theme(storedVersion:storedTheme:)`; снять четыре поля разметки
   из `HotkeySettings` (K-6, §2.3).
4. `UiLanguage.swift`: 11 добавить, 1 изменить, 2 снять, порядок как на Windows (K-8, §3.4).
5. Геометрия: `minimumWidth` / `defaultWidth` 244, `edgeGap` 0, `estimatedChromeHeight` 160,
   `StackMetrics.shadowMargin` 20 (K-7, §3.1).
6. Тесты Core из §6: `CaptureKindTests`, `LegacyOutlineTests`, дополнения `SettingsMigrationTests`,
   `StripResizeGeometryTests`, `PersistenceAndExportTests`, `CaptureCropperTests`.

Ветка волны 0 — от сведённой `mac-sync-3-ci`; порции ветвятся от её коммита.

### Волна 1: три порции, без пересечений по папкам

| Порция | Папки Swift | Содержание |
|---|---|---|
| **Stack** | `SnapikMac/Stack/*`, `SnapikMac/App/AppCoordinator*.swift`, `App/SmokeTestRunner+Stack.swift` | S-1…S-4, S-6 (своя половина), §3.2, пробы A-1, A-2, A-5 |
| **Editor** | `SnapikMac/Editor/*`, `SnapikMac/Imaging/*`, `SnapikMacTests/Editor/*`, `SnapikMacTests/Imaging/*` | E-1…E-9, §4, проба A-3, `EditorGeometryTests`, тест намерения вместо `FrameCopyTests` |
| **Settings** | `SnapikMac/Settings/*`, `SnapikMac/Onboarding/*`, `App/SmokeTestRunner+Settings.swift` | T-1…T-3, T-7, проба A-4 |

Пересечения: `AppCoordinator.swift` трогают Stack (S-1, S-6) и Settings (T-7, вызов мастера).
Отдать `AppCoordinator.swift` **только Stack**, а Settings отдаёт свою половину колбэком
(`onOnboardingFinished` уже есть: `HotkeySettingsWindowController.swift:382` на `MC`).
`App/SmokeTestRunner.swift` (реестр вызовов) трогает только сведение.

Каждой порции в промпт: `git merge <ветка волны 0>` первым шагом; запрет `git checkout/restore/reset`;
`swift build` не гонять (нет macOS-раннера локально) — проверка на CI; после `git worktree add` сверить
`git worktree list`.

### Волна 2: сведение

Один исполнитель на `master`-ветке синхронизации, порции мержатся по одной:

1. `AppCoordinator.swift`: клавиша `fullscreen-save` → лента (S-1), показ ленты после мастера (S-6),
   `mergeOnboarding` (T-7).
2. `App/SmokeTestRunner.swift`: каждая новая проба раунда вызывается ровно один раз, без осиротевших.
3. `UiLanguage.swift`: ни одного повторяющегося русского ключа и ни одного повторяющегося английского
   значения (Windows держит 290 пар после трёх слияний — Mac-число своё, правило то же).
4. Проверка координированных символов: `grep -c "func kindTitle" == 1`, то же для `fit(`, `clampOffset(`,
   `zoomAround(`, `mergeOnboarding(`, `syncScaleSwitch(`.
5. Версия 1.5.0 в `macos/project.yml` (A-6).

### Закрытие

- Тег `mac-sync-base-4` = `d84fbb0`.
- Строка в журнал `macos/SYNC.md`: «4 | `mac-sync-base-4` = `d84fbb0` | вид снимка (`kind`,
  `monitorCount`, чипы, весь экран и импорт в ленту), редактор с масштабом и переключателем,
  миграция настроек до версии 2, геометрия ленты 244/20/0, лупа и «+» палитры | `macos-v…`».
- CI на macOS-раннере: сборка, тесты, `--smoke-test`, DMG; релизный тег `macos-v…` по итогу зелёного прогона.
