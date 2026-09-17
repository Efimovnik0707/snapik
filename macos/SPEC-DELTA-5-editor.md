# Дельта №5, порция Editor: Windows `d84fbb0..f2cf62b` (1.6.0 + 1.7.0) → macOS

**База.** `mac-sync-base-4` = `d84fbb0` (Windows 1.5.0). Цель раунда: `mac-sync-base-5` = `f2cf62b` (1.7.0).
Диапазон: 76 коммитов, `src` + `tests`, 52 файла, +4571 / −1199. Два раунда ТЗ Кати подряд:
1.6.0 = `tasks/tz-006-*` (ТЗ №5), 1.7.0 = `tasks/tz-007-*` (ТЗ №6), плюс хотфиксы 1.6.1.

**Зона этого документа.** Редактор, холст, рендер экспорта. Windows: `Controls/AnnotationCanvas.cs`,
`Controls/AnnotationRules.cs`, `Controls/EditorGeometry.cs`, `Controls/ToolbarLayout.cs`,
`Imaging/NoteBadgeGeometry.cs`, `WpfExportImageRenderer.cs`, `ToolAppearance.cs`,
`OverlayEditorWindow.xaml(.cs)`, `.Appearance.cs`, `.Comments.cs`, `.Save.cs`, `.Shapes.cs`,
`.Toolbar.cs` (удалён), `EditorShortcuts.cs`, пробы редактора в `SmokeTestRunner.cs`.
Mac: `Sources/SnapikMac/Editor/**`, `Sources/SnapikMac/Imaging/**`, `Sources/SnapikCore/Editing/**`,
`Sources/SnapikCore/Exporting/**` (рендер картинки), `App/SmokeTestRunner+Editor.swift`,
`Tests/SnapikMacTests/{Editor,Imaging}/**`.

**Не моя зона.** Лента и `copySingleCapture` — порция `stack`. Модель настроек, ключи `settings.json`,
`UiLanguage`, `PromptGenerator` — порция `core-settings`. `Controls/RoundedClip.cs` в Windows читает
только карточка ленты (`EdgeStackWindow.xaml:283`), редактор его не трогает — переносит `stack`.

Ссылки Windows — по `f2cf62b`. Ссылки Swift — по `master` на момент написания.

---

## 0. Резюме

### 0.1 Что из зоны уже есть на Mac

Проверено по коду, а не по спеке:

- **Чистая геометрия масштаба** — `fit`, `clampOffset`, `zoomAround` (`Editor/EditorGeometry.swift:38, 51, 64`),
  шесть тестов (`Tests/SnapikMacTests/Editor/EditorGeometryTests.swift:15-57`). Дельта №4 её перенесла;
  в этом раунде правится только `fit` (теряет `FitResult`).
- **Масштаб канвы** — `viewScale`/`viewOffset`/`fitScale`/`imageRect` (`Editor/AnnotationCanvasView.swift:61, 70, 181, 80`),
  панорама пробелом (`:73`), колесо с Cmd и Shift (`:536-575`).
- **Правило чтения старой рамки** `legacyHasOutline` (`Editor/EditorModels.swift`, тесты `Editor/LegacyOutlineTests.swift`).
- **Якорь выноски** — `anchorDrag` с компенсацией `noteOffset` и порогом 4 px (`AnnotationCanvasView.swift:112, 382-396`),
  `anchorRadius = 5` / `anchorHoverRadius = 7` (`:120-121`), отрисовка точки на экране
  (`AnnotationCanvasView+Drawing.swift:203-212`).
- **`findLeaderAnchor` отвечает любому инструменту** (`AnnotationCanvasView.swift:695-702`) — это уже целевое
  поведение tz-006 C-5.
- **`hasResizeHandles` исключает текст и комментарий**, `hasInteriorGrab` включает текст и залитую рамку
  (`AnnotationCanvasView.swift:754-756`).
- **Инфляция хит-теста** `max(8, thickness/2 + 4)` (`EditorGeometry.swift:126-129`) — база для правки E-5.
- **Порог жеста 4 px на экране** `gestureThreshold` (`EditorGeometry.swift:117`), `gestureHasSize` с
  одиночным кликом для комментария и текста (`:107-114`).
- **`placeToolbar` с четырьмя кандидатами и обходом пилюль** (`EditorGeometry.swift:231-259`) — не хватает
  только параметра `mayOverlap`.
- **Общий рисовальщик отметок** `AnnotationPainter` (`Imaging/AnnotationPainter.swift`) и выноска в нём
  (`:293-303`) — уже одна точка на экспорт, «Сохранить на компьютер» и автосохранение.
- **`NoteBadgeGeometry`** с `screen`/`export`/`exportLeaderThickness`/`leader` (`Imaging/NoteBadgeGeometry.swift`).
- **Спектр, пипетка с лупой, «+» в палитру, узоры штриха, кегль подписи** — дельты №3 и №4, не трогаются.

### 0.2 Что переносится

Тридцать четыре позиции, из них четыре — контракт волны 0 (чистые функции с тестами), двадцать шесть —
порция Editor, четыре — правки хотфиксов и ревью. Крупное:

1. Переключатель масштаба уходит целиком, снимок открывается 1:1 через `placeCapture`, вход в масштаб —
   только Cmd+колесо из вписанного состояния.
2. Панель разметки перекладывается из плоского переноса по ширине в три блока (инструменты · свойства ·
   действия) с двумя строками, укладкой через `ToolbarLayout.measure` и перетаскиванием за свободное место.
3. Блок свойств становится инспектором из двух капсул поверх словаря «инструмент → настройки»
   (`ToolAppearance`), каждый инструмент помнит своё, и настройки переживают перезапуск.
4. Нажатие мыши получает одно правило на все инструменты (`pressTargetOf`), углы только у выделенной
   отметки, полоса захвата 8 у всех.
5. Комментарий становится самостоятельным: бейдж двигается сам без клампа, ставится жестом,
   привязка к рамке снята, выноска идёт от центра `points[0]` до обода точки, точка появляется в экспорте
   и в файле на диске.
6. Экспорт получает поле `#2A3140` под вынесенные бейджи и единую точку отсчёта `captureOrigin`.
7. Обводка перестаёт краситься заливкой, у размытия нет блока свойств вовсе.
8. Кнопка «Копировать» и Cmd+Shift+C в редакторе.
9. Интерполяция картинки выбирается по реальному размеру отрисовки, а не по наличию своего масштаба.

### 0.3 Что не переносится и почему

| Что | Почему |
|---|---|
| `FrameCopy.Detach` и `FrameCopyTests` | Решено дельтой №4 (`SPEC-DELTA-4.md` §4.4): `CGImage` владеет своими данными. Windows в этом раунде дописал `FrameCopyTests.cs` (+47, два теста про сохранность цвета тёмного пикселя) — на Mac аналога нет, тест-намерение уже стоит в `Tests/SnapikMacTests/Imaging/ImageCodecTests.swift` |
| `Controls/RoundedClip.cs` | Читает только карточка ленты, зона `stack` |
| `SoundVolumeCurve`, `PublishedPackageTests`, `TaskbarPinLegacy`, `AppearancePicker` | Вне зоны редактора |
| `RenderOptions.BitmapScalingMode` как API | Переносится **по смыслу**: на Mac тот же выбор делает `NSGraphicsContext.imageInterpolation` (`AnnotationCanvasView+Drawing.swift:28-31`). Правило одно — см. H-2 |
| WPF-специфика `Popup.StaysOpen` (причина хотфикса H-1) | На Mac поповеры это `NSPopover`, открываются из `onClick` кнопки (`OverlayEditorController+Appearance.swift:43`). Проблемы «поповер живёт, пока держат кнопку» нет. Переносится только **итоговое поведение**: квадрат заливки внутри капсулы цвета открывает поповер заливки, сама капсула — поповер обводки, оба на клике |
| `Uid` капсул | Windows разобрал и осознанно не сделал (`tz-006-notes.md`, отступления дорожки C). На Mac тем более: клавиши у капсул нет |
| Пара `["Размытие"] = "Blur"` | Windows её не завёл: английское значение занято кнопкой «Размыть», а смоук держит инвариант уникальности. Капсула размытия всё равно скрыта (E-11) |

---

## 1. По пунктам обоих раундов

Объём: **S** ≤ 60 строк Swift, **M** 60–250, **L** > 250.

### 1.1 Контракт волны 0 (чистые функции моей зоны)

Эти четыре пункта — фундамент: на них стоят и порция Editor, и тесты, и (для `toolAppearance`) порция
`core-settings`. Делать их первыми и последовательно.

| # | Что | Windows-источник | Целевой Swift | Объём | Статус |
|---|---|---|---|---|---|
| W0-1 | `AnnotationRules`: `outlineColorOf(fill:color:)` без `fillColor`; `enum PressTarget` (девять шагов, включая `deselect`); `pressTargetOf(tool:panning:clickCount:onAnchor:onSelectedHandle:onObject:activatable:)` | `Controls/AnnotationRules.cs:17-18, 21, 32-46` (новый файл раунда) | новый `Editor/AnnotationRules.swift` | S | нет на Mac: правило обводки живёт в `Editor/EditorAppearanceModel.swift:127` и берёт `fillColor`; правила нажатия нет вовсе |
| W0-2 | `ToolAppearance` (запись), `ToolAppearanceStore.read/write`, `enum SecondCapsule`, `struct InspectorView`, `EditorInspector.inspectorViewOf/inspectedTool` | `ToolAppearance.cs:13-29, 56-155, 158-192` (новый файл раунда) | новый `Editor/ToolAppearance.swift`; `ToolAppearanceEntry` (Codable) — **в Core**, см. §2.1 | M | нет на Mac |
| W0-3 | `NoteBadgeGeometry`: `exportScale(_:)`, `anchorRadius = 5`, `leader(..., fromRadius:)`, `ExportMargin`, `exportMargins(badges:width:height:)` | `Imaging/NoteBadgeGeometry.cs:9-14, 40-41, 47, 59, 77-98, 108-121` | `Imaging/NoteBadgeGeometry.swift` (дописать; `leader` `:60` получает параметр) | M | нет на Mac: `exportLeaderThickness` `:38` считает то же выражение сам, `anchorRadius` живёт в канве (`AnnotationCanvasView.swift:120`), `fromRadius` и полей экспорта нет |
| W0-4 | `EditorGeometry.Fit` → `double` (снять `FitResult`/`FitBound`), `placeCapture(image:work:panel:gap:margin:)`; новый `ToolbarLayout`: `ToolbarRows`, `ToolbarShape`, `measure(tools:properties:actions:freeWidth:padding:gap:rowGap:)`, `placeToolbar(crop:work:size:notes:mayOverlap:)` | `Controls/EditorGeometry.cs:19-44`; `Controls/ToolbarLayout.cs:8-68` (новый файл раунда) | `Editor/EditorGeometry.swift:24-45` (снять типы, сменить возврат), `:231-259` (`placeToolbar` получает `mayOverlap`), туда же `placeCapture`; `measure` — новым `enum ToolbarLayout` в том же файле либо отдельным `Editor/ToolbarLayout.swift` | M | расходится: `fit` возвращает `FitResult`, `placeCapture` нет, `placeToolbar` без `mayOverlap`, `measure` нет |

**Почему `ToolAppearanceEntry` обязан жить в Core.** На Mac `HotkeySettings` — это
`Sources/SnapikCore/Settings/HotkeySettings.swift:40` с явными `CodingKeys` (`:328-345`), а SnapikCore не
видит SnapikMac. Значит тип, который лежит в словаре `toolAppearance`, объявляет `core-settings`, а
`ToolAppearance` (с `NSColor` и `EditorTool`) и `ToolAppearanceStore` (перевод между ними) — моя зона.
Граница: Core отдаёт `[String: ToolAppearanceEntry]`, редактор возвращает такой же словарь.

**Где положить `ToolbarLayout`.** Windows вынес его отдельным файлом, чтобы линковать в тест-проект.
На Mac `Editor/EditorGeometry.swift` уже линкуется в `SnapikMacTests` без ухищрений, и там же лежит
`placeToolbar`. Класть туда же; отдельный файл — только если файл перевалит за тысячу строк.

### 1.2 tz-006 (ТЗ №5, 1.6.0) — редактор

| # | Фича | Windows-источник | Целевой Swift | Объём | Статус |
|---|---|---|---|---|---|
| E-1 | Снимок открывается 1:1, переключателя масштаба нет, Cmd+колесо работает из вписанного | `xaml.cs:1186-1202`; `AnnotationCanvas.cs:1168-1214` (`90e6ea8`) | `OverlayEditorController.swift:272-274`, `+Scale.swift` целиком, `EditorScaleSwitchView.swift`, `AnnotationCanvasView.swift:536-560` | L | нет на Mac |
| E-2 | Панель: три блока, две строки, `measure`, `mayOverlap`, перетаскивание | `xaml:203-318`; `xaml.cs:1926-2030` (`51e78e0`) | `Editor/EditorToolbarView.swift:286-489`, `OverlayEditorController+Chips.swift:520-539` | L | нет на Mac |
| E-3 | Блок свойств = две капсулы поверх словаря `_tools` | `xaml:272-305`; `.Appearance.cs:99-105, 204-357, 369-441` (`bbd8258`) | `EditorToolbarView.swift:298-304, 374-381`, `OverlayEditorController+Appearance.swift:145-267, 228-310`, `EditorAppearanceModel.swift:86-115` | L | нет на Mac |
| E-4 | Правило 6: настройки инструментов переживают перезапуск | `.Appearance.cs` `SaveAppearanceDefaults` (`57276e4`) | `OverlayEditorController+Appearance.swift` (`saveAppearanceDefaults`/`flushAppearanceDefaults`) | S | нет на Mac |
| E-5 | Одно правило нажатия: `pressTargetOf`, углы у выделенной, `reach = 8`, порог 4 px, текст 4 px | `AnnotationCanvas.cs:287-400, 452-455, 749-773, 1010-1046` (`915a3ac`) | `AnnotationCanvasView.swift:270-330, 398-435, 716-758, 760-772`, `EditorGeometry.swift:126-129` | L | расходится |
| E-6 | Комментарий сам по себе: `badgeDrag`, постановка жестом, наведение → пилюля, Esc, снятие привязки | `AnnotationCanvas.cs:39-41, 349-358, 437-447, 486-494, 572-581, 601-605`; `xaml.cs:1896-1901`; `.Appearance.cs:691-698` (`52505e7`) | `AnnotationCanvasView.swift:112-118, 340-360, 397-408, 470-490`, `OverlayEditorController+Chips.swift`, `+Appearance.swift:458-463` | L | нет на Mac |
| E-7 | Экспорт с полем `#2A3140`, `exportMargins`, `captureOrigin` | `WpfExportImageRenderer.cs:19-39, 43-78, 120-124, 174-205, 217-232` (`0406421`) | `Imaging/ExportImageRenderer.swift:25-79`, `Imaging/AnnotationPainter.swift:264-276` | M | нет на Mac |
| E-8 | Обводка не красится заливкой | `AnnotationRules.cs:17-18`; `WpfExportImageRenderer.cs:151-156` | `EditorAppearanceModel.swift:127-134`, вызов `AnnotationCanvasView+Drawing.swift:113-117` | S | расходится |
| H-1 | Поповер заливки открывается на клике, а не на нажатии | `.Appearance.cs:485-517` (`53c921d`) | `EditorToolbarView.swift` (капсула цвета), `+Appearance.swift` | S | адаптация, см. §0.3 |
| H-2 | Интерполяция по реальному размеру отрисовки | `AnnotationCanvas.cs:239-240, 260-274`, `VerifyScalingRules` `:128-157` (`a3861c7`) | `AnnotationCanvasView+Drawing.swift:28-31` | S | расходится |

#### E-1. Снимок открывается в своём размере, переключателя нет

**Windows.** `ScaleSwitch`, `SyncScaleSwitch`, `OnFitScaleClick`, `OnOneToOneScaleClick`, учёт переключателя
в `PositionToolbar` и поле `_fitBox` в обеих точках инициализации удалены. `OnLoaded` кладёт
`_cropRect = EditorGeometry.PlaceCapture(imageSize, work, MeasureToolbar(work).Size)`
(`xaml.cs:1199-1201`): панель меряется **до** снимка, потому что вопрос «влезает ли снимок 1:1» — это
вопрос о высоте панели под ним. Режим `ViewScale is not null` не вводится: `_cropRect` просто делается
размером с картинку, канва вписывает её в свои же границы, `FitRect` даёт ровно 1, и ни одна из
одиннадцати точек холста не меняется. `OnSurfaceViewChanged` остаётся (держит ручки границ и пилюли),
перестаёт звать `SyncScaleSwitch`.

Вместе с переключателем чинится вход в масштаб: `OnMouseWheel` выходил, пока `ViewScale is null`
(`AnnotationCanvas.cs:1172`), и единственным входом в 1:1 был правый сегмент переключателя. Теперь
затравкой служит `FitScale`, а пол зажат `Math.Min(FitScale, 1)` — из вписанного состояния снимка 1:1
`FitScale ≈ 1`, и без пола `Clamp` получал диапазон наоборот и кидал исключение (`:1207`). Логика
вынесена в `ZoomByNotches(delta, cursor)` (`:1189-1214`), потому что смоук не может зажать Ctrl.

**Mac-цель.**

| Что | Файл:строка | Что делать |
|---|---|---|
| `EditorScaleSwitchView` | `Editor/EditorScaleSwitchView.swift:9-93` | удалить класс. **Файл не удалять целиком:** в нём же лежит `EditorShotKindView` (`:95-141`), подпись вида снимка, которая остаётся. Разрезать: `Editor/EditorShotKindView.swift` отдельным файлом, остаток выбросить |
| `OverlayEditorController+Scale.swift` | `:11-32, 80-111` | `setupScaleViews` теряет половину про переключатель, `syncScaleSwitch`/`fitScaleClicked`/`oneToOneScaleClicked` удаляются; `syncShotKind` (`:40-61`), `positionShotKind` (`:65-73`) и `surfaceViewChanged` (`:116-123`) остаются. Файл переименовать в `OverlayEditorController+CaptureView.swift` — имя `+Scale` после правки врёт |
| `scaleSwitchView` | `OverlayEditorController.swift:163` | убрать поле; `shotKindView` (`:164`) оставить |
| `fitBox` | `OverlayEditorController.swift:168`, `:273`; `+Scale.swift:26-28` | убрать поле и обе инициализации. `EditorGeometry.reopenFitBox` (`:406-408`) удаляется вместе с ним |
| `reopenCropRect` | `EditorGeometry.swift:412-418`; вызов `OverlayEditorController.swift:274` | заменить на `placeCapture(image:work:panel:)`. Коэффициент 0.72 уходит |
| колесо | `AnnotationCanvasView.swift:536-543` | `guard capture != nil, let scale = viewScale` → выход только когда `viewScale == nil` **и** Cmd не зажат; затравка `let scale = viewScale ?? fitScale`; офсет при `viewScale == nil` — центрированная картинка, записанная офсетом; пол `min(fitScale, 1)`. Вынести тело в `func zoomByNotches(_ notches: Double, cursor: CGPoint)` — пробе негде взять `NSEvent` с зажатым Cmd |
| укладка панели | `OverlayEditorController+Chips.swift:529-538` | снять `switchSize`/`gap`: переключателя нет, панель ставится сама |
| проба | `Editor/OverlayEditorController+SmokeTest.swift:410-470`, `App/SmokeTestRunner+Editor.swift:31` | см. §4 |

**Ловушки AppKit.**

- `placeCapture` возвращает прямоугольник в **оконных** координатах редактора, а окно оверлея у нас
  flipped (`OverlayContentView`, `AnnotationCanvasView.isFlipped == true`), то есть Y вниз — формула
  переносится дословно. Но `layoutWorkArea(screenIndex:)` строится из `NSScreen.visibleFrame`, где Y
  вверх, и переводится в локальные координаты окна. Это **единственное место порта, которое не
  дословное**: проверить, что `work.minY` после перевода — это верх рабочей области, а не низ, иначе
  снимок прижмётся к нижнему краю вместо верхнего (`C1-editor-layout.md` §9).
- Порядок «померить панель → положить снимок → положить панель» обязателен. На Windows панель на момент
  замера `Collapsed` и меряется в ноль; на Mac `EditorToolbarView.sizeToFitContent()` (`:441`) меряет
  всегда, скрытость на размер не влияет — но `maximumWidth` (`:323`) должен быть выставлен до замера,
  иначе панель посчитает себя в одну строку и снимку достанется лишняя высота.
- `fitScale` (`AnnotationCanvasView.swift:181`) считается от `bounds` минус `imagePadding * 2`. У Mac
  `imagePadding` тоже 0 — прибить это комментарием на месте затравки, как сделал Windows: вернут
  отступ — картинка прыгнет на первом щелчке Cmd.

#### E-2. Панель: три блока, две строки, перетаскивание

**Windows.** `WrapPanel` заменён `Grid` 2×4 (`xaml:212-221`): колонка 0 — инструменты (`ToolbarTools`),
колонка 1 — свойства (`ToolbarProperties`, фиксированная ширина 176 из ресурса `ToolbarPropertiesWidth`),
колонка 2 — звёздное свободное место и оно же ручка, колонка 3 — действия (`ToolbarActions`). При нехватке
ширины свойства уезжают во вторую строку с `ColumnSpan = 4`, а кнопки справа остаются на месте.
`MeasureToolbar` (`xaml.cs:1926-1962`) меряет три блока по отдельности, зовёт `ToolbarLayout.Measure`,
раскладывает `Grid.SetRow/Column/ColumnSpan` и ставит `Toolbar.Width = shape.Size.Width` (звезда иначе
растянула бы панель на монитор). `PositionToolbar` (`:1968-1999`) зовёт
`PlaceToolbar(..., mayOverlap: _capture?.Kind == Fullscreen || _isNew)`. Перетаскивание: `ToolbarBody`
с прозрачным фоном ловит нажатие, кнопки забирают его раньше; хранится **абсолютная точка**
`_toolbarUserPosition`, а не смещение (при переключении строк якорь меняется).

Два бага, починенных заодно и обязательных к переносу: `Margin` входит в `DesiredSize`, поэтому
`MeasureToolbar` обнуляет его перед замером и возвращает после (`:1949-1951`); видимость панели тоже
восстанавливается (`:1957`, находка ревью — иначе проверка видимости в `UpdateNoteButton` теряет смысл).

**Mac сейчас.** `EditorToolbarView.sizeToFitContent()` (`:441-474`) — плоский перенос по ширине:
`placementOrder` (`:374-381`) выкладывается в ряд, при переполнении `maximumWidth` начинается новая
строка. То есть ровно тот `WrapPanel`, который Windows снял. `positionToolbar()`
(`OverlayEditorController+Chips.swift:520-539`) зовёт `EditorGeometry.positionToolbar` (`:262-265`) —
обёртку над `placeToolbar` без `mayOverlap`. Перетаскивания панели нет. Ширина блока свойств не
фиксирована: кнопки `thicknessButton`/`lineStyleButton`/`fillButton`/`fontSizeButton` (`:300-303`)
объявлены с шириной 64/64/96/64, но в ряду стоят вперемешку с инструментами.

**Что менять.**

1. Разбить `placementOrder` на три массива: `toolsOrder` (select … crop, comment, shortcutSheet и три
   шеврона), `propertiesOrder` (капсулы из E-3), `actionsOrder` (разделитель, undo, redo, save, copy, done).
2. `sizeToFitContent()` переписать: измерить три блока (`toolsSize`, `propertiesSize`, `actionsSize`),
   позвать `ToolbarLayout.measure(...)`, разложить по результату. Одна строка — блоки слева направо,
   свободное место посередине; две — инструменты и действия в первой, свойства во второй с отступом
   сверху 7. Возвращать `ToolbarShape`, а не `CGSize`: `placeCapture` из E-1 просит размер до раскладки.
3. Блоку свойств выдать константу ширины `EditorToolbarView.propertiesWidth: CGFloat = 176` — это
   требование контракта: пока ширина блока плавает, «одна строка или две» меняется от инструмента в руке,
   и панель прыгает под курсором.
4. `positionToolbar()` зовёт `placeToolbar(..., mayOverlap: capture?.kind == .fullscreen || isNewSelection)`.
   Признак «свежее выделение» на Mac — путь `presentExisting` против `present`; взять его у контроллера,
   отдельного поля не заводить, если уже есть.
5. Перетаскивание. На Mac `EditorToolbarView` — `NSView` без собственного `mouseDown`. Завести на самом
   `EditorToolbarView` (не на кнопках: `ToolbarButtonBaseView.mouseDown` `:32` съедает нажатие раньше,
   и это ровно тот же приём «кнопки забирают нажатие первыми») `mouseDown`/`mouseDragged`/`mouseUp`,
   хранить `userOrigin: CGPoint?` в контроллере, клампить в рабочую область с полем 8. Три метода
   вынести отдельно (`beginToolbarDrag`/`dragToolbarTo`/`endToolbarDrag`) — пробе негде взять `NSEvent`.
6. `positionToolbar()` при `userOrigin != nil` только пере-зажимает точку и выходит.

**Ловушки AppKit.**

- Захват мыши. У AppKit нет `CaptureMouse`/`LostMouseCapture`: перетаскивание внутри `mouseDown` ведётся
  либо циклом `nextEvent(matching:)`, либо обычными `mouseDragged`/`mouseUp` на той же вью — второе
  проще и достаточно, потому что `NSView` и так получает весь трек до `mouseUp`. Но тогда нет и риска
  «захват не отпущен и рисование зависло» (риск 5 `C1-editor-layout.md` §7): переносить нечего, сказать
  об этом вслух в комментарии.
- `NSTrackingArea` кнопок (`ToolbarButtonBaseView.updateTrackingAreas` `:24`) пересоздаётся на каждом
  изменении кадра. После перекладки в три блока кадры меняются при каждом `sizeToFitContent` — убедиться,
  что `updateTrackingAreas` не накапливает области (сейчас старая снимается, проверить после правки).
- Тень панели рисуется в `draw(_:)` самой вью (`EditorToolbarView.swift:477-488`) от `bounds`. При двух
  строках `bounds` вырастет сам, правки не требует.

#### E-3. Блок свойств как инспектор

**Windows.** Восемь активных полей (`_activeColor`, `_activeThickness`, …) заменены словарём
`Dictionary<EditorTool, ToolAppearance> _tools` с шестью ключами (`rectangle`, `arrow`, `pen`,
`highlight`, `text`, `blur`). Единственная дверь к словарю — `AppearanceOf(tool)` с падением на набор
рамки (`.Appearance.cs:99-100`): при снимке из ленты `Surface.Tool == Select`, и прямая индексация
кидала бы исключение на каждом открытии карточки. Что показывать — решает таблица
`EditorInspector.InspectorViewOf(tool)`, чьи это настройки — `InspectedTool(selected, armed)`.
Пять предикатов `HasStroke`/`HasShape`/`HasFill`/`HasFontSize`/`HasLineStyle` удалены и сведены к полям
`InspectorView`; `HasLineStyle` остался внутри `InspectorViewOf` вызовом `StrokePattern.Participates`.

На экране это две капсулы вместо ряда точек и шести кнопок (`xaml:272-305`):

| Элемент | Что | Размер |
|---|---|---|
| `ColorCapsule` | кнопка, открывает поповер обводки | H 36, `Padding="10,0"`, радиус из `OverlayButton` |
| `StrokeDot` | круг цвета обводки внутри капсулы | 18 × 18, обводка `#D9DEE8` 1 px |
| `FillSquare` | квадрат цвета заливки, своя дверь в поповер заливки | 18 × 18, радиус 4, рамка `#D9DEE8` 1 px, отступ слева 7 |
| `FillSquareNone` | косая черта, когда заливки нет | `#FF5C5C`, 1.6 px |
| `FillSquareBlur` | превью узора размытия | по квадрату |
| `LineCapsule` | вторая капсула: толщина со стилем, размер подписи или форма | H 36, отступ слева 6 |
| `LineCapsuleGlyph` | `A` у текста, `▢` у формы; скрыт у штриховых | 13 pt |
| `LineCapsuleValue` | `4 px` / `20 pt` / `Скруглённый` / пусто | 12 pt, `#EEF2F8` |
| `LineCapsuleSample` | образец штриха с толщиной и пунктиром | 22 × 6, `#D9DEE8` |
| `LineCapsuleChevron` | уголок «есть поповер» | 9 × 5 |

Выключенное состояние: обе капсулы `IsEnabled = false`, `Opacity = 0.28`, место держат. Скрытое
(у размытия — цвета нет, форма ушла в 1.7.0): `Visibility.Hidden`, не `Collapsed` — блок держит ширину.

Поповеров у блока осталось **четыре**, а не два (отступление дорожки C): `AppearancePopup` на круге
обводки, `ThicknessPopup` (с блоком «Линия» внутри, `LineStylePopup` слит в него) и `FontSizePopup` на
капсуле линии, `FillPopup` на квадрате заливки. Палитра «неон» вернулась четвёртым сегментом.

**Mac сейчас.** `activeColor`/`activeThickness`/`activeHighlightThickness`/`activeFillColor`/
`activeShape`/`activeFill`/`activeLineStyle`/`activeFontSize` — восемь полей контроллера, один набор на
все инструменты; `syncAppearance` (`+Appearance.swift:145-267`) читает их и предикаты
`EditorAppearance.hasStroke/hasShape/hasFill/hasFontSize/hasLineStyle` (`EditorAppearanceModel.swift:86-105`);
на панели — `colorDotsView` (ряд быстрых цветов), `appearanceButton`, `thicknessButton`, `lineStyleButton`,
`fillButton`, `fontSizeButton` (`EditorToolbarView.swift:298-303`). Поповеров пять
(`EditorPopovers.swift:153, 296, 380, 472, 575`).

**Что менять.**

1. `Editor/ToolAppearance.swift` (W0-2) и словарь `tools: [EditorTool: ToolAppearance]` в контроллере
   вместо восьми полей. Дверь — `func appearance(of tool: EditorTool) -> ToolAppearance` с падением на
   `.rectangle`. Прямой индексации в коде быть не должно (грепом проверяется).
2. Две капсулы. Завести два класса рядом с существующими кнопками панели:
   `ToolbarColorCapsuleView` (круг + квадрат, квадрат отдельной под-вью со своим `mouseDown`) и
   `ToolbarLineCapsuleView` (глиф + значение + образец + шеврон). Обе — наследники
   `ToolbarButtonBaseView` (`EditorToolbarView.swift:8`), чтобы hover и нажатие работали как у остальных.
   Убрать `colorDotsView`, `appearanceButton`, `thicknessButton`, `lineStyleButton`, `fillButton`,
   `fontSizeButton` и `setQuickColors`/`setCurrentQuickColor` (`:404-434`): быстрый ряд переезжает в
   поповер, где двенадцать образцов и так есть.
3. `syncAppearance` переписать по `InspectorViewOf`/`InspectedTool`. Точный порядок — как на Windows
   (`.Appearance.cs:226-266`): видимость и `isEnabled` первой капсулы, цвет круга, вид квадрата по
   заливке; затем вторая капсула — видимость (`Hidden` при `SecondCapsule.None`), подсказка, глиф,
   значение, образец. Отдельно `syncSurfaceDefaults()`: `canvasView.active*` всегда из
   `appearance(of: canvasView.tool)`, что бы ни было выделено.
4. `applyAppearance` переписать по правилу 2: выделено — пишем в отметку, не выделено — в
   `tools[tool]`. Проверка «можно ли» — поля `InspectorView`, а не пять предикатов. Форма пишется только
   при `tool == .rectangle` и зеркалится в `tools[.blur]` (см. E-11).
5. Слить поповер стиля линии в поповер толщины
   (`EditorPopovers.swift:296` принимает блок из `:380`), перенацелить оставшиеся четыре на капсулы:
   обводка → `colorCapsule`, толщина и размер → `lineCapsule`, заливка → квадрат внутри капсулы цвета.
6. Палитра «неон» четвёртым набором — согласовать с `core-settings`: ключ `AnnotationPalette` строковый,
   неизвестный id падает на стандартную, откат безопасен в обе стороны.

**Ловушки AppKit.**

- Ширина 176. `ToolbarValueButtonView.layout()` (`:139-148`) центрирует содержимое по `bounds.width`;
  капсулам ширину задаёт не содержимое, а блок. Капсулы кладутся в блок фиксированной ширины, а сами
  просят `MinWidth 36` — это две разные величины, не путать.
- `Hidden` против `Collapsed`. У AppKit `isHidden = true` и есть `Hidden`: вью не рисуется, но кадр её
  остаётся, и соседи не сдвигаются, потому что раскладку считает наш код, а не autolayout. Это ровно то,
  что нужно; `removeFromSuperview` не использовать.
- Квадрат заливки внутри капсулы. Чтобы нажатие на квадрат отличалось от нажатия на капсулу, квадрат
  должен быть отдельной `NSView` поверх капсулы с собственным `hitTest`. Порядок как на Windows:
  нажатие на квадрат ставит признак, клик по капсуле по признаку решает, какой из двух поповеров
  открыть (H-1). На Mac это не обязательное лечение бага, но правило то же, и смоук его читает.

#### E-4. Настройки инструментов переживают перезапуск

`SaveAppearanceDefaults` сводится к `TryLoad → ToolAppearanceStore.Write → Save`. Важно: этот метод —
**единственный писатель ещё трёх общих ключей** (`AnnotationPalette`, `CustomPaletteColors`,
`AnnotationPencil`). Они остаются общими (не по инструментам) и обязаны попасть в ту же запись, которую
кладёт `write`. На Mac смотреть, где сейчас пишутся эти три ключа при закрытии редактора, и не потерять
их: иначе результат прошлого раунда (палитра «Своя», двенадцать слотов, режим карандаша) откатится молча.

#### E-5. Одно правило нажатия

**Windows.** `BeginGesture` (`AnnotationCanvas.cs:287-400`) собирает четыре сигнала (`anchored`,
`handleHit`, `grabbed`, `under`) и отдаёт их `AnnotationRules.PressTargetOf`. Дальше `switch` по девяти
шагам. Что изменилось в источниках сигналов:

| Сигнал | Было | Стало | Mac-цель |
|---|---|---|---|
| `FindLeaderAnchor` | условие `Tool is not (Select or Comment)` | отвечает любому инструменту | **уже так** (`AnnotationCanvasView.swift:695-702`) |
| `FindResizeHandle` | исключение для `Comment` + цикл по всем отметкам | углы **только у выделенной** (`:749-755`) | `AnnotationCanvasView.swift:760-772`: снять цикл `for annotation in capture.annotations.reversed()` (`:766-769`) |
| `IsMoveHandle` | `Tool == Comment` → только комментарии; `reach = item.Kind == Tool ? 10 : 6` | ветка по инструменту снята, `const double reach = 8` для всех (`:1032-1044`) | `AnnotationCanvasView.swift:716-753`: убрать `if tool == .comment { … }` (`:719`) и `let reach: CGFloat = item.kind == tool ? 10 : 6` (`:742`) → `let reach: CGFloat = 8` |
| `HitTestAnnotation` | инфляция `max(8, Thickness/2 + 4)` для всех | у текста инфляция ровно 4 без вклада толщины (`:768`) | `EditorGeometry.hitTestInflatedBounds` (`:126-129`) получает вид отметки либо вызывающий (`AnnotationCanvasView.swift:773-780`) решает сам |
| порог перетаскивания | любое движение писало запись истории | гейт `manipulationMoved` по `gestureThreshold` (`:454-455`) | `AnnotationCanvasView.swift:398-400`: завести `manipulationMoved`, сбрасывать в `beginGesture` и там же, где сбрасывается `manipulationChanged` |

`activatable` — это «под курсором текст или комментарий». Следствие, записанное вслух: двойной клик по
рамке и стрелке больше не открывает их заметку (заметку у рамки заводит кнопка «+» рядом). И: с
«Комментарием» в руке нельзя поставить булавку на контур нарисованной рамки — press выделит рамку.
Прямое следствие правила 1 ТЗ, не баг.

`PressTarget.Deselect` — находка-блокер ревью: без неё протяжка «Выбором» по пустому месту клала в сессию
отметку вида `Select`, а экспорт рисовал на её месте прямоугольник. На Mac ветка `select(nil)` при
`tool == .select` сегодня есть неявно (`AnnotationCanvasView.swift:322`, `if tool == .select || …`),
но после перехода на `pressTargetOf` она должна быть явным шагом, иначе ошибка приедет вместе с правилом.
(Сейчас ветка `select` слита с ветками ручек и захвата: `AnnotationCanvasView.swift:318`
`if tool == .select || handleHit.annotation != nil || moveHandleHit != nil` — весь этот `if` заменяется
на `switch` по `PressTarget`.)

**Ловушки.** `PressTarget.Object` на Mac разветвляется на две: обычная манипуляция и `badgeDrag` из E-6
(комментарий, взятый не за угол). Порядок внутри `switch` менять нельзя: якорь спрашивается раньше
бейджа, поэтому при `noteOffset == nil`, когда они совпадают, выигрывает якорь и уезжает всё вместе —
это ожидаемое «не сдвинутый комментарий переносится целиком».

#### E-6. Комментарий как самостоятельный объект

Пять правок, все в `AnnotationCanvasView` и контроллере:

1. **Ветка жеста `badgeDrag`** рядом с `anchorDrag` (`AnnotationCanvasView.swift:112-118`):
   нажали на бейдж — двигается `noteOffset`, **без** `clampToImage`, порог `gestureThreshold`, одна
   запись истории на жест (`AnnotationCanvas.cs:39-41, 349-358, 437-447, 572-581`). Бейдж уезжает за
   границу снимка на затемнённый фон, точка стоит, линия ведёт внутрь.
2. **Постановка жестом «нажал — потянул»** (`AnnotationCanvas.cs:486-494`): пока черновик комментария
   тянут, правится `noteOffset`, а не `points[1]`; на отпускании смещение короче порога → `noteOffset = nil`
   (`:601-605`). Mac: `updateGesture` `AnnotationCanvasView.swift:436-446` (ветка черновика) и `endGesture`.
3. **Наведение на бейдж разворачивает пилюлю.** Windows: канва поднимает событие `NoteHovered` из
   `UpdateCursor` (`AnnotationCanvas.cs:527-529`), окно разворачивает чип (`xaml.cs:1896-1901`).
   Mac: `updateCursor` (`AnnotationCanvasView.swift:580+`) уже считает `findMoveHandle`; добавить
   `onNoteHovered: ((EditorAnnotation?) -> Void)?` рядом с существующими колбэками (`:82-91`) и
   разворот чипа в `OverlayEditorController+Chips.swift`.
4. **Esc получает шаг `expandedNote`** перед `comment` (`.Appearance.cs:691-698`). Mac:
   `nextEscapeStep()` (`+Appearance.swift:458-463`) — вставить `if expandedChipId != nil { return .expandedNote }`
   после проверки поповера.
5. **Снятие привязки.** `MoveLinkedComments`, её вызов, поле `_commentParentId`, присвоение при создании
   и запоминание родителя удалены. При переносе рамки комментарий стоит на месте. Mac: искать по
   `parentAnnotationId` (`Editor/EditorModels.swift:49`) — поле **остаётся и продолжает читаться**, но не
   пишется (см. §2.2).

**Ловушки CoreGraphics.** Четыре места с `clampToImage` в `updateGesture`, и только два первых остаются
для комментария: якорь тянет точку (`AnnotationCanvasView.swift:383, 388`), бейдж и черновик комментария —
нет. Перепутать легко, проверять грепом по `clampToImage` после правки.

#### E-7. Экспорт с полем под вынесенные бейджи

**Windows.** `MarginsOf(capture, label, width, height)` считает `ExportMargins` по бейджам отметок с
заметкой (`WpfExportImageRenderer.cs:24-32`), `CaptureOrigin(margin) = (margin.Left, HeaderHeight + margin.Top)`
(`:39`) становится **единственной точкой отсчёта**: лист `Left + width + Right` на
`HeaderHeight + Top + height + Bottom`, поле залито `#2A3140` одним прямоугольником под всем, поверх
него белый заголовок во всю новую ширину, снимок в `Rect(origin, width, height)`, все `P(…)` считают от
`origin` (`:123`). Кламп бейджа под заголовок снят: `ExportBadge` зовёт `Export(..., topMargin: -∞)`
(`:229-231`) — между заголовком и снимком теперь есть поле, куда бейджу и положено уйти.

Поле считается по кругу, который **действительно рисуется**: бейдж стоит выше своей точки на половину
диаметра плюс зазор 4, поэтому место просит и тот бейдж, который никуда не переносили
(`NoteBadgeGeometry.cs:88-89`, находка ревью HIGH). Комментарии без номера в расчёт не входят (`:84`).
Без вынесенных бейджей `ExportMargins` даёт `None`, и картинка байт в байт как прежде.

**Mac-цель.** `Imaging/ExportImageRenderer.swift:25-79`:

- `let margin = NoteBadgeGeometry.exportMargins(...)`, `let origin = captureOrigin(margin)`;
- размеры контекста: `width: margin.left + width + margin.right`,
  `height: headerHeight + margin.top + height + margin.bottom` (`:25-27`);
- первым делом заливка всего листа `#2A3140`, затем белый заголовок во всю ширину (`:47-50`);
- `ctx.translateBy(x: CGFloat(margin.left), y: CGFloat(headerHeight + margin.top))` вместо нынешнего
  `translateBy(x: 0, y: headerHeight)` (`:71`);
- `labelTopMargin` (`:68`) с `2` меняется на `-.greatestFiniteMagnitude`: кламп снят;
- `drawCaptureBadge` (`:91`) рисует в координатах листа, `x: 12` остаётся — заголовок начинается с левого
  края листа, а не снимка.

Отдельно: `exportMargins` читает `points[0]` и `noteOffset` каждой отметки с непустой меткой. На Mac
метки раздаёт `CaptureLabels.forNotedAnnotations` (`ExportImageRenderer.swift:57`) — тот же список, что и
для `labelsById`, собрать его один раз.

**Ловушки CoreGraphics.** Флип. Контекст экспорта переворачивается один раз (`:43-44`), и вся арифметика
после этого идёт в Y-вниз. Сдвиг на поле делается **после** флипа и внутри `saveGState`/`restoreGState`,
иначе `drawCaptureBadge`, который рисуется после painter'а (`:79`), уедет вместе со снимком. Правило
проекта: вокруг каждого блита — локальный анти-флип; здесь блит делает сам `AnnotationPainter`
(`options.sourceImage`), значит трогать его нельзя, только сдвигать контекст вокруг.

#### E-8. Обводка не красится заливкой

`AnnotationRules.OutlineColorOf(fill, color)` теряет параметр `fillColor`: обводка всегда своего цвета,
у размытой области обводки нет вовсе. Два вызывающих на Windows — канва и экспорт.

Mac: `EditorAppearanceModel.outlineColor(fill:color:fillColor:)` (`EditorAppearanceModel.swift:127-134`)
→ `AnnotationRules.outlineColorOf(fill:color:)`; вызывающих ровно два —
`AnnotationCanvasView+Drawing.swift:113-117` и `Imaging/AnnotationPainter.swift:172`.
`fillColor(_:fill:)` (`EditorAppearanceModel.swift:137-143`), кисть внутренности, **не трогать**.

Побочное следствие вслух: снимок 1.5.0 с `fill = solid`, `fillColor = #0000FF`, `strokeColor = #FF3B30`
рисовался с синей обводкой, теперь нарисуется с красной. Формат цел, меняется чтение. Решение Кати.

#### H-2. Интерполяция по реальному размеру отрисовки

**Windows.** Режим стоял в сеттере `ViewScale` и знал только, есть у вида свой масштаб или нет. После E-1
вписанный снимок — это `ViewScale == null`, то есть `Unspecified` (в .NET `Linear`), а Cmd+колесо из
вписанного даёт `ViewScale` **меньше единицы** и прежний `NearestNeighbor`. Оба режима на уменьшении
фотографии выбрасывают пиксели вместо усреднения, и тёмная фактура идёт крапом. Решение переехало в
`ApplyScalingMode` (`AnnotationCanvas.cs:267-275`), который зовётся из `OnRender` (`:240`), где известен
настоящий прямоугольник отрисовки: `_imageRect.Width / Image.PixelWidth >= 0.999` → `NearestNeighbor`,
иначе `HighQuality` (`Fant`).

**Mac.** Ровно тот же дефект и ровно в одной строке: `AnnotationCanvasView+Drawing.swift:29`
`NSGraphicsContext.current?.imageInterpolation = viewScale == nil ? .default : .none`. Целевое:

```swift
let ratio = imageRect.width / CGFloat(displayImage.width)
NSGraphicsContext.current?.imageInterpolation = ratio >= 0.999 ? .none : .high
```

`.none` = `NearestNeighbor` (шов двух мониторов и пиксель в пиксель не размываются), `.high` = усреднение
(аналог `Fant`). `.default` не использовать вовсе: это и есть тот самый `Linear`.

Миниатюры карточек ленты и галереи Windows тоже перевёл на `HighQuality` — это зона `stack` и
`core-settings`, сказать им явно.

### 1.3 tz-007 (ТЗ №6, 1.7.0) — редактор

| # | Фича | Windows-источник | Целевой Swift | Объём | Статус |
|---|---|---|---|---|---|
| E-9 | Выноска комментария от центра `points[0]` до обода точки | `NoteBadgeGeometry.cs:108-121`; `AnnotationCanvas.cs:826-871` (`dd61b82`) | `Imaging/NoteBadgeGeometry.swift:60-69`, `AnnotationCanvasView+Drawing.swift:180-195`, `Imaging/AnnotationPainter.swift:285-305` | M | нет на Mac |
| E-10 | Точка в экспорте и в файле на диске | `WpfExportImageRenderer.cs:174-205`; `AnnotationCanvas.cs:858-866` (`c8a2ad0`) | `Imaging/AnnotationPainter.swift:277-318` | S | нет на Mac |
| E-11 | У размытия нет блока свойств, форма только у рамки | `ToolAppearance.cs:181`; `.Appearance.cs:249-268, 394-405, 519-531`; `.Shapes.cs:50, 59-64` (`2fca9ed`) | `Editor/ToolAppearance.swift` (W0-2), `+Appearance.swift`, меню формы | S | нет на Mac |
| E-12 | Кнопка «Копировать» и Cmd+Shift+C | `xaml:313-315`; `.Save.cs:56-85`; `EditorShortcuts.cs:38` (`4de1e67`) | `EditorToolbarView.swift` (кнопка), `OverlayEditorController+Save.swift`, `+Keys.swift:61-87`, `EditorShortcuts.swift:32-40` | M | нет на Mac |

#### E-9. Линия комментария идёт от точки

**Причина.** `TryLeader` брала `from` как ближайшую к бейджу точку прямоугольника отметки. У комментария
прямоугольник — квадрат 8 × 8 от `points[0]` до `points[1]`, поэтому при бейдже справа-сверху линия
начиналась в правом верхнем углу квадрата, на 8 px правее центра точки.

**Решение (вариант A Windows, единственный).** Вторая точка **остаётся в модели** как прямоугольник
комментария: её читают обрезка (`CaptureCropper.cropBox` вернул бы пустой массив на вырожденном
прямоугольнике и **удалил бы комментарий при любой обрезке снимка**), хит-тест, двойной клик и раскладка
пилюль. Из расчёта линии она выводится явно: у `kind == .comment` выноска считается от `points[0]`, а не
от `boundsOf`. Правило живёт в **отрисовке**, а не в создании — только так старые сессии с двухточечными
комментариями рисуются по новому.

**Что менять.**

1. `Imaging/NoteBadgeGeometry.swift`:
   - `public static func exportScale(_ label: String) -> CGFloat { max(1, exportDiameter(label) / screenDiameter(label)) }`,
     а `exportLeaderThickness` (`:38-40`) выражается через неё. Одно число на толщину линии, радиус точки
     и её обод — иначе три числа разъедутся.
   - `public static let anchorRadius: CGFloat = 5` (`:55` рядом с `create`). Сейчас пятёрка живёт в канве
     (`AnnotationCanvasView.swift:120`); файл геометрии существует именно затем, чтобы экран и экспорт
     сходились.
   - `leader(bounds:badge:fromRadius:)` (`:60`) с дефолтом `0`: после нормализации направления
     `guard length > badge.radius + fromRadius + 1 else { return nil }` и `from += direction * fromRadius`.
     С нулём картинка прежняя.
2. `AnnotationCanvasView.swift:120`: `anchorRadius` → ссылка на `NoteBadgeGeometry.anchorRadius`;
   `anchorHoverRadius = 7` (`:121`) остаётся на месте, это только наведение.
3. `AnnotationCanvasView+Drawing.swift:180-195` (`drawLabelBadge`): развилка по виду отметки —
   у комментария `outline = CGRect(origin: map(item.points[0]), size: .zero)`, `fromRadius = anchorRadius`;
   у остальных всё как было, `fromRadius = 0`. **`boundsOf` для комментария не звать** (риск ниже).
4. `Imaging/AnnotationPainter.swift:285-305` (`drawLabel`): та же развилка. Здесь `fromRadius` для
   комментария — `anchorRadius * exportScale(label)` при `style == .export` и `anchorRadius` при `.screen`.

**Три рисовальщика Windows против двух на Mac.** На Windows выноску рисуют три места: экран
(`AnnotationCanvas.OnRender`), файл на диск (`AnnotationCanvas.RenderAnnotated`) и картинка в чат
(`WpfExportImageRenderer.DrawAnnotation`). На Mac путей тоже три, но кода два:

| Путь | Mac-код | Стиль |
|---|---|---|
| экран | `AnnotationCanvasView+Drawing.swift:186` | — |
| картинка в чат | `Imaging/ExportImageRenderer.swift:72` → `AnnotationPainter.drawLabel` | `.export` |
| «Сохранить на компьютер» | `AnnotationCanvasView+Drawing.swift:337` (`renderFinalImage`, `:314`) → тот же `drawLabel` | `.screen` |
| автосохранение | `App/AutoSaveService.swift:45` → тот же `drawLabel` | `.screen` |

Это дешевле Windows, но меняет адрес правки: на Windows «файл на диск» чинился снятием `includeSelection &&`
в канве, потому что `RenderAnnotated` переиспользует `DrawAnnotation`. На Mac `renderFinalImage` идёт
через `AnnotationPainter`, и правка обязана лечь **туда**. Две копии правила должны совпадать — это
подтверждается тестом «выноска комментария начинается на ободе точки» на обеих (§4).

**Риск: вырожденный прямоугольник.** `CGRect` нулевого размера безопасен для `min(max(…))` внутри
`leader`. Опасен `CGRect.null` (у отметки без точек): `boundsOf` (`EditorGeometry.swift:79-87`) возвращает
`.null`, чьи `minX`/`maxX` — «бесконечные» значения, и зажим даст мусор. Ветку комментария писать через
`points[0]` напрямую, не через `boundsOf`, чтобы этот путь не появился.

**Риск: короткая выноска.** `endGesture` обнуляет `noteOffset` короче порога, но пилюлю можно дотащить
обратно вручную. Тогда `leader` вернёт `nil` (линии нет), а точка нарисуется под бейджем. На экране так
и сегодня; в экспорте появится кружок под бейджем. Допустимо, проверить глазами.

#### E-10. Точка в экспорте и в файле на диске

В обоих рисовальщиках, внутри уже существующего блока `if item.noteOffset != nil`, **после** линии
(чтобы линия не легла поверх кружка):

```swift
if item.kind == .comment {
    let radius = NoteBadgeGeometry.anchorRadius * scale   // scale = 1 на экране и в .screen
    ctx.setFillColor(accent.cgColor)
    ctx.fillEllipse(in: CGRect(x: anchor.x - radius, y: anchor.y - radius, width: radius * 2, height: radius * 2))
    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.setLineWidth(1.5 * scale)
    ctx.strokeEllipse(in: …)
}
```

Windows: `WpfExportImageRenderer.cs:200-203`, `AnnotationCanvas.cs:858-866`. На экране радиус
переключается на `anchorHoverRadius` под курсором — это остаётся **только** в канве
(`AnnotationCanvasView+Drawing.swift:205`), в painter'е наведения нет.

Один и тот же `anchor` считается дважды (для бейджа и для точки) — на Windows вынесен в `ExportAnchor`
(`:220-221`), чтобы два места не разъехались. На Mac у `AnnotationPainter.badge(for:…)` (`:264-274`) уже
есть эта арифметика: вынести `mapPoint(first, imageSize:)` в маленькую функцию и звать её обоими.

**Ограничение, записанное вслух.** `exportMargins` считает поле только по бейджам, точка сидит на
`points[0]` и клампится в снимок при перетаскивании якоря, поэтому за лист выйти может максимум на
~6.5 px, если якорь стоит вплотную к краю. `exportMargins` ради этого **не менять**: она задаёт байты
экспорта и покрыта десятью тестами.

#### E-11. У размытия нет блока свойств

Пять правок, все мелкие:

1. `inspectorViewOf(.blur)` → `InspectorView(stroke: false, fillSwatch: false, second: .none, enabled: true)`
   (`ToolAppearance.cs:181`).
2. `syncAppearance`: первой строкой блока второй капсулы `lineCapsule.isHidden = view.second == .none`;
   значение и подсказка при `.none` — пустая строка (`.Appearance.cs:249, 259-266`; правка ревью:
   скрытая капсула держала чужую подсказку «Толщина»).
3. Обработчик клика по капсуле линии: `case .none: return` перед `default` (`.Appearance.cs:528-530`).
   Кнопка скрыта, но `default` открыл бы толщину у инструмента без обводки.
4. `applyAppearance`: условие записи формы `tool is Rectangle or Blur` сужается до `tool == .rectangle`
   (`.Appearance.cs:394`). **Зеркало `tools[.blur].shape` в ветке «ничего не выделено» остаётся**
   (`:404`) — иначе в `settings.json` останется протухшее значение, которое прочитает вторая платформа.
5. Меню формы: `is { Kind: Rectangle or Blur }` → `is { Kind: Rectangle }` в обоих местах
   (`.Shapes.cs:50` — какая галочка стоит, `:62` — переключать ли инструмент). После сужения выбор формы
   при выделенном блюре переключает на рамку, как при любом другом чужом выделении.

Размытие по-прежнему рисуется формой рамки: черновик берёт `activeShape`
(`AnnotationCanvasView.swift:352` — `EditorAppearance.hasShape(tool) ? activeShape : .rectangle`),
и `activeShape` читается только с рамки. `EditorAppearance.hasShape` (`EditorAppearanceModel.swift:95`)
после E-3 уходит в `InspectorView`, но правило «блюр рисуется формой рамки» остаётся.

#### E-12. Кнопка «Копировать» и Cmd+Shift+C

**Windows.** Кнопка `CopyImageButton` в блоке действий между «Сохранить на компьютер» и «Готово»
(`xaml:313-315`). Обработчик (`.Save.cs:56-85`): те же гарды, что у сохранения
(`_capture is null`, `_busyCrop`, `_captureResizeCorner >= 0`, `Surface.IsMouseCaptured`), `CommitTextEdit()`
первым делом (пока открыт ввод подписи, канва её не рисует, и картинка ушла бы без слов на экране), затем
`stack.CopySingleCaptureAsync(_capture, label)`. Гард `_busyCrop` поднимается на время экспорта — правка
ревью: повторный Ctrl+Shift+C ставил второй экспорт в очередь. Ответ говорится **плашкой редактора**
(`Hint`), а не тостом ленты: лента спрятана, пока редактор открыт, и тост уходил в невидимое окно.
Строка `("Ctrl+Shift+C", "Копировать снимок")` добавлена в `EditorShortcuts.Actions` **перед**
`("Ctrl+C", "Готово")` (`EditorShortcuts.cs:38-39`).

**Mac-цель.**

| Что | Файл:строка |
|---|---|
| кнопка в блоке действий | `EditorToolbarView.swift:306-309` (объявить рядом с `saveButton` `:308`), в `actionsOrder` между `saveButton` и `doneButton` `:309` |
| обработчик | новый `copyToClipboard()` в `OverlayEditorController+Save.swift` рядом с `saveToFile()` (`:11`), гарды один в один с `:12` плюс `busyCrop = true` на время |
| плашка ответа | `showHintError`-сосед: `OverlayEditorController+Commit.swift:160-166` уже показывает `hintView` (`OverlayContentView.swift:20`); завести `showHint(_:)` без «ошибочной» окраски либо переиспользовать |
| клавиша | `OverlayEditorController+Keys.swift:61-87`: ветка `"c" where event.modifierFlags.contains(.shift)` **до** существующей `case "c"` (`:81`), иначе Cmd+C «Готово» съест её |
| шпаргалка | `EditorShortcuts.swift:32-40`: `("Shift+Cmd+C", "Копировать снимок")` перед `("Cmd+C", "Готово")` |

**Зависимость от порции `stack`.** `copySingleCapture` на Mac **нет вовсе** (грепом по `Sources/` — ноль
вхождений). Интерфейс брать у порции `stack`: нужен метод вида
`func copySingleCapture(_ capture: CaptureItem, label: String) async -> Bool`, возвращающий успех
(Windows именно так и сделал после ревью). До его появления кнопка и клавиша не собираются — ставить
E-12 последним пунктом порции.

**Порядок относительно E-10.** Копия идёт тем же экспортом, что и пакет. Если E-12 примут раньше E-10,
кнопка отгрузит в чат картинку без точки комментария. Windows зафиксировал порядок: экспорт с точкой
раньше кнопки.

---

## 2. Изменения формата в зоне

Сверено с `tasks/verification.md` (секции «Изменения формата» обоих раундов).

### 2.1 `settings.json`: ключ `toolAppearance` — как его читает и пишет редактор

Сам ключ описывает порция `core-settings`. Здесь — что с ним делает редактор.

Целевой вид (`ToolAppearance.cs:36-48`, `verification.md`):

```json
"toolAppearance": {
  "rectangle": { "color": "#34C759", "thickness": 4, "lineStyle": "dashed",
                 "fill": "translucent", "fillColor": "#FF3B30", "fontSize": 20,
                 "arrowStyle": "straight", "shape": "rounded" },
  "arrow":     { … }, "pen": { … }, "highlight": { … }, "text": { … }, "blur": { … }
}
```

- Имя ключа в файле — **`toolAppearance` с маленькой буквы**, в отличие от всех соседних ключей
  (`AnnotationColor`, `StackHeight`, …), которые PascalCase. Windows: `[JsonPropertyName("toolAppearance")]`
  (`HotkeySettings.cs:107`). На Mac `CodingKeys` (`SnapikCore/Settings/HotkeySettings.swift:328-345`)
  обязаны написать это буква в букву, иначе файл, записанный одной платформой, откроется другой без
  настроек инструментов.
- Имена инструментов — camelCase от членов `EditorTool`: `rectangle`, `arrow`, `pen`, `highlight`,
  `text`, `blur`. Шесть, не больше: `select`, `eraser`, `crop`, `comment` своих настроек не имеют.
- `fillColor` отсутствует в файле, когда он `null` («как обводка»); все остальные поля пишутся всегда.
- Неизвестный инструмент в словаре и `null`-запись пропускаются молча (`ToolAppearance.cs:81`): файл из
  более новой сборки не должен ронять старую.
- Числовое значение вместо имени перечисления (`"2"` в правленом руками файле) падает на дефолт, а не
  выбирает члена по индексу (`:136-139`).
- **Чтение при отсутствии ключа:** каждый инструмент получает старые общие значения — `AnnotationColor`
  и `AnnotationThickness` все, `AnnotationHighlightThickness` маркер, `AnnotationFontSize` текст
  (`:65-75`). То есть файл 1.5.0 открывается ровно так, как выглядел.
- **Запись:** прежние общие ключи остаются и продолжают писаться зеркалом рамки, маркера и текста
  (`:92-100`), поэтому файл, записанный 1.6.0+, полностью читается 1.5.0.
- `SettingsVersion` **не поднимается**: миграция здесь по отсутствию ключа. На Mac `SettingsMigration.currentVersion`
  остаётся 2.
- Сравнение при чтении: словарь сравнивается по содержимому, а не по ссылке, иначе файл с пустым
  `toolAppearance` будет считаться «мигрированным» и переписываться на каждом старте
  (`HotkeySettings.cs:186-196`). На Swift `[String: ToolAppearanceEntry]` с `Equatable`-значением
  сравнивается по содержимому сам — но `ToolAppearanceEntry` обязан быть `Equatable`.

Четыре ключа разметки (`AnnotationOutline`, `AnnotationShape`, `AnnotationFill`, `AnnotationFillColor`)
были сняты ещё дельтой №4 и не возвращаются.

### 2.2 `session.json`: `parentAnnotationId` — читаем, не пишем

С 1.6.0 поле у комментария **не пишется**, но продолжает читаться. Сессия 1.5.0, открытая заново,
сохраняет подпись «К отметке A2» в панели комментариев и пометку «(к области A2)» в `prompt.md`;
у новых комментариев подпись всегда «К снимку A». `SchemaVersion` не меняется.

Mac: `Editor/EditorModels.swift:49` (`var parentAnnotationId: SBGuid?`) — поле остаётся, `fromCore`
читает, `toCore` перестаёт переносить (тот же приём, что у `legacyHasOutline`). Очистку повисшей ссылки
при обрезке (`SnapikCore/Editing/CaptureCropper.swift`) и валидацию **оставить**: они защищают чужой файл.

### 2.3 `session.json` для комментариев не менялся — подтверждено

Проверено по коду `f2cf62b`:

- у комментария по-прежнему **две** точки, `points[1] = points[0] + (8, 8)` при создании; вторая точка
  не участвует в расчёте выноски начиная с 1.7.0, но остаётся в модели как прямоугольник для обрезки,
  хит-теста и раскладки пилюль (`tz-007-details/C-editor.md` §0.1, §0.5);
- `noteOffset` как был (доли размера снимка, может выйти за `[0, 1]` после снятия клампа — это
  допустимо, `SessionValidation` проверяет наличие, а не диапазон);
- `toolAppearance.blur.shape` продолжает писаться намеренно, чтобы вторая платформа не прочитала
  протухшее значение;
- ничего нового не пишется и не снимается. Абзац «Изменение формата» для tz-007 по редактору не нужен —
  Windows его и не завёл.

### 2.4 Изменение чтения (не формата): старый снимок с заливкой перекрасится

`outlineColorOf` потерял параметр, поэтому отметка 1.5.0 с `fill = solid`, `fillColor = #0000FF`,
`strokeColor = #FF3B30` рисовалась с синей обводкой, а теперь нарисуется с красной. Формат цел, меняется
чтение (§1.2 E-8).

---

## 3. Расхождения Mac ↔ Windows, которые надо привести к Windows

Не «новая фича раунда», а места, где Mac уже разошёлся и правка обязана это учесть.

### 3.1 `fit` возвращает `FitResult`, а не число

| Символ | Mac сейчас | Целевое | Файл |
|---|---|---|---|
| `FitBound` | объявлен | снять | `Editor/EditorGeometry.swift:24-28` |
| `FitResult` | объявлен | снять | `:31-34` |
| `fit(...)` | `-> FitResult` | `-> Double` | `:38-45` |

`FitBound`/`FitResult` существовали ради подписи «По ширине · N %» у переключателя. Подписи нет.
Три теста ломаются, см. §4.1.

### 3.2 Коробка 0.72 против `placeCapture`

`reopenFitBox` (`:406-408`) и `reopenCropRect` (`:412-418`) масштабируют снимок в 72 % окна. Windows имел
78/72 и снял обе точки инициализации; вместо них `placeCapture`, где коробка — рабочая область минус поля
8 и минус высота панели с зазором 10. Снимок 1420 × 700 в области 1536 × 824 при однострочной панели
высотой 50 получает ровно 1420 × 700; при двухстрочной (94) 1420 × 720 уже вписывается. На Mac обе
функции удаляются вместе с `fitBox`.

### 3.3 Углы правки у любой отметки, а не только у выделенной

`findResizeHandle` (`AnnotationCanvasView.swift:760-772`) сначала спрашивает выделенную, а потом идёт
циклом по **всем** отметкам (`:766-769`). Windows цикл снял (`AnnotationCanvas.cs:749-755`): углы
отвечают только у выделенной. Это и есть «ручки выделенного» из ТЗ; старое поведение снимается намеренно.

### 3.4 Полоса захвата 10/6 против 8

`isMoveHandle` (`AnnotationCanvasView.swift:742`): `let reach: CGFloat = item.kind == tool ? 10 : 6`.
Целевое — `8` для всех (`AnnotationCanvas.cs:1035`). Полоса, меняющая ширину с инструментом в руке,
делала один и тот же пиксель двумя разными нажатиями.

### 3.5 Ветка «с комментарием в руке отвечают только комментарии»

`isMoveHandle` (`:719`): `if tool == .comment { return item.kind == .comment && … }`. Windows снял
(`AnnotationCanvas.cs:1010-1046` — ветки по `Tool` там больше нет). Следствие: с «Комментарием» в руке
press по контуру нарисованной рамки выделит рамку, а не поставит булавку. Записано как осознанный риск.

### 3.6 Порог перетаскивания существующей отметки

`updateGesture` (`AnnotationCanvasView.swift:398-433`): ветка `manipulating` ставит
`manipulationChanged = true` при любом движении. Windows добавил гейт `manipulationMoved` по
`gestureThreshold` (`AnnotationCanvas.cs:454-455`): клик по объекту с дрожанием руки на 1 px больше не
пишет запись истории.

### 3.7 Интерполяция по наличию масштаба

`AnnotationCanvasView+Drawing.swift:29` — см. H-2.

### 3.8 Выноска считается от `boundsOf` у всех отметок

Оба рисовальщика (`AnnotationCanvasView+Drawing.swift:180-186`, `Imaging/AnnotationPainter.swift:285-293`)
собирают прямоугольник из всех точек. Для комментария это квадрат 8 × 8 — см. E-9.

### 3.9 Экспорт клампит бейдж под заголовок

`ExportImageRenderer.swift:68` — `labelTopMargin: 2`. После E-7 кламп снимается
(`-.greatestFiniteMagnitude`): между заголовком и снимком появляется поле, куда бейджу и положено уйти.

### 3.10 Пять поповеров вместо четырёх

`EditorPopovers.swift:296` (толщина) и `:380` (стиль линии) — два отдельных. Windows слил стиль в толщину
одним листом (эталон 01 рисует их вместе). После E-3 у блока свойств четыре поповера: обводка, толщина
(со стилем), размер подписи, заливка.

---

## 4. Тесты и пробы smoke

`git diff --stat d84fbb0..f2cf62b -- tests`: в моей зоне четыре файла тестов.
Новых тестовых целей на Mac не заводить — всё раскладывается по `Tests/SnapikMacTests/{Editor,Imaging}`.

### 4.1 Windows-тесты зоны → Swift

| Windows-файл | Тесты | Swift-набор |
|---|---|---|
| `tests/Snapik.App.Imaging.Tests/AnnotationRulesTests.cs:13, 23` (новый) | обводка держит цвет отметки, что бы ни стояло внутри (четыре заливки); имя нажатия в одном порядке для всех инструментов (девять входов, включая `Deselect`) | новый `Tests/SnapikMacTests/Editor/AnnotationRulesTests.swift` |
| `tests/Snapik.App.Imaging.Tests/ToolAppearanceTests.cs:21, 47, 55, 69, 95, 120, 133` (новый) | таблица инспектора по семи кадрам эталона (рамка, стрелка/карандаш, маркер, текст, размытие `None`, `conceal` как залитая область, безнастроечные `enabled: false`); выделенная отметка владеет блоком; файл без ключа отдаёт старые общие значения; файл с ключом читается им, неизвестный инструмент пропускается; круг `write → read` плюс зеркало старых ключей; с размытием в руке блок не показывает ничего; форма читается только у рамки, у блюра остаётся зеркало в файле | новый `Tests/SnapikMacTests/Editor/ToolAppearanceTests.swift` |
| `tests/Snapik.App.Imaging.Tests/NoteBadgeGeometryTests.cs:23-68` (десять случаев `ExportMargins`) | снимок без бейджей поля не просит; бейдж внутри снимка не просит; бейдж, который никуда не двигали, просит место, над которым он висит; бейдж за левым/правым/верхним краем; два бейджа в разные стороны; комментарий без номера не влияет; длинный номер просит шире | новый `Tests/SnapikMacTests/Imaging/NoteBadgeGeometryTests.swift` |
| `tests/Snapik.App.Imaging.Tests/NoteBadgeGeometryTests.cs:74, 84, 99, 108, 116` (пять случаев `TryLeader`) | выноска рамки начинается на её контуре (`fromRadius = 0`); выноска комментария начинается на ободе точки (вырожденный прямоугольник, `fromRadius = 5`, расстояние от якоря до `from` равно 5, направление на центр бейджа); выноска кончается на ободе бейджа; выноска короче `radius + fromRadius + 1` не рисуется; `exportScale("1") == exportLeaderThickness("1")` и больше 1 | туда же |
| `tests/Snapik.App.Imaging.Tests/EditorGeometryTests.cs:14-58` (правка) | `fit` возвращает число: «снимок двух мониторов вписан по ширине» и «высокий импорт по высоте» проверяют только масштаб (0.312 / 0.247); «влезающий снимок переключать нечем» → «снимок меньше коробки не масштабируется», `== 1`; три теста `clampOffset`/`zoomAround` **не трогать** | `Tests/SnapikMacTests/Editor/EditorGeometryTests.swift:15, 21, 27` правятся; `:33, 48, 57` остаются |
| `EditorGeometryTests.cs:72-123` (новые, `PlaceCapture`) | шесть: снимок, влезающий под панель, открывается 1:1; слишком высокий вписывается по высоте; снимок двух мониторов вписывается по ширине в рабочую область; вторая строка панели снимает снимок с 1:1 (1420 × 720); панель комментариев забирает ширину; прямоугольник держит поле 8 и место `panel.height + gap` под собой | дописать в `EditorGeometryTests.swift` |
| `EditorGeometryTests.cs:125-170` (новые, `ToolbarLayout`) | панель переносится только когда одна строка не влезает (теория: 1077 → одна, 781 → две); две строки выше на строку и зазор; число строк не зависит от инструмента (тест на контракт с блоком свойств); панели, которой некуда встать снаружи, при `mayOverlap: false` нельзя лечь на снимок; при наличии места панель встаёт под снимком | новый `Tests/SnapikMacTests/Editor/ToolbarLayoutTests.swift` |
| `tests/Snapik.App.Imaging.Tests/FrameCopyTests.cs` (+47) | копия заморожена и того же размера; копия кодируется с потока пула; цвет тёмного пикселя не меняется | **не переносится** (§0.3). Тест-намерение уже стоит в `Tests/SnapikMacTests/Imaging/ImageCodecTests.swift` |

Ещё: `Tests/SnapikMacTests/Editor/LegacyOutlineTests.swift` (пять тестов) и
`EditorGeometryChipTests.swift` (пять) правок не требуют; `Imaging/ExportImageRendererTests.swift:12, 48, 79`
правятся под новый размер листа только если снимок несёт вынесенные бейджи — без них лист прежний, и
тесты должны остаться зелёными **без правки**. Это и есть проверка «байт в байт как раньше».

### 4.2 Пробы smoke

Реестр — `App/SmokeTestRunner+Editor.swift:20-33` (восемь проб с контроллером) и `:38-43` (две без).

| Проба | Что делать |
|---|---|
| `editor: a capture of two monitors offers the scale switch` (`:31` → `smokeRunEditorScaleProbe`, тело `OverlayEditorController+SmokeTest.swift:410-470`) | переименовать в «the view of the editor». Снять гард по `scaleSwitchView` и утверждения про переключатель, снять `fitBox` (`:423`). Сохранить: подпись вида снимка, ручки границ при прокрутке, пилюля за краем. Добавить: `placeCapture(1420×700, 1536×824, панель 460×50)` даёт ровно 1420 × 700; из вписанного состояния `zoomByNotches` даёт `viewScale != nil` и `≤ 1` (регрессия на «Cmd+колесо из вписанного не работало вообще») |
| `editor: the panel keeps its width and wraps when it must` (`:28`, тело `+SmokeTest.swift:485-510`) | переписать под три блока: при свободной ширине 781 свойства во второй строке, при 1077 — в первой, кнопки справа в первой всегда; ширина панели одинакова при пяти инструментах (`rectangle`, `text`, `blur`, `select`, `arrow`); блок свойств держит 176 у каждого; три шеврона на месте в блоке инструментов; `placeToolbar(..., mayOverlap: false)` не пересекает `cropRect` в трёх рабочих областях; перетаскивание за свободное место двигает панель и следующий `positionToolbar()` его не сбрасывает |
| **новая** «память каждого инструмента» | сценарий Кати дословно (`C2-editor-model.md` §1.12, семь шагов): рамка зелёная с полупрозрачной красной заливкой и 4 px → стрелка синяя пунктирная → текст белый 20 → маркер жёлтый → снова рамка отдаёт своё, и капсулы показывают его же → жестом нарисованная рамка рождается с ним → редактор закрывается (настройки пишутся), над **тем же** рабочим каталогом открывается второе окно на новом снимке, шаг 5 повторяется целиком. Отдельное утверждение: после записи файл по-прежнему несёт выбранную палитру, ряд «Своей» и режим карандаша |
| **новая** «с размытием в руке блок пуст» | после `selectTool(.blur)` обе капсулы `isHidden`, ширина блока не изменилась; с блюром в руке меню формы от шеврона рамки переключает на `.rectangle` и меняет `activeShape`; форма `.ellipse` у рамки доезжает до нарисованного жестом блюра |
| **новая** «правила интерполяции» | аналог `VerifyScalingRules` (`AnnotationCanvas.cs:128-157`): после отрисовки на четырёх масштабах (вписанный, 0.5, 1, 2) читать выбранный режим. Вписанный снимок с `fitScale < 1` обязан быть `.high`; 1 и 2 — `.none`. На Mac режим не хранится в вью: вынести выбор в чистую `static func interpolation(ratio: CGFloat) -> NSImageInterpolation` и проверять её |
| **новая** «точка комментария в экспорте» | рендер пробы с переставленным бейджем в PNG: пиксель в центре `points[0]`, пересчитанный в координаты листа через `captureOrigin(margin)`, акцентный; пиксель на `anchorRadius * exportScale + 2` от центра по нормали к бейджу белый. Негативная проверка (комментарий **без** `noteOffset` — ни точки, ни линии) — **вторым снимком**, а не вторым комментарием в тот же: список «отметок с заметкой» в пробе берётся как единственный, и второй комментарий его сломает (`tz-007-plan.md` §5.C, C-2) |
| **новая** «шпаргалка знает Shift+Cmd+C» | `EditorShortcuts.actions` содержит `("Shift+Cmd+C", "Копировать снимок")` (аналог `VerifyTz007Editor`, `SmokeTestRunner.cs:1637-1647`) |
| `editor: hover manipulation and the comment tool` (`:41`, тело `AnnotationCanvasView.swift:792+`) | арифметика `interiorGrabs` и «того же вида 10 px» пересчитывается под единый `reach = 8`; проверки «стрелка берётся за линию, а не рядом» и «булавка берётся за бейдж» остаются; блок про «Комментарий» переписать — нажатие рядом с углом выделенной рамки при комментарии теперь попадает в угол, точку для новой булавки брать заведомо вдали от выделенного. Комментарий из двух точек с `+8` в пробе **оставить как есть**: прямоугольник 8 × 8 в ней осмыслен |
| `editor: the comment tool grabs what is already there` (`:24`) | дополнить: с «Рамкой» в руке клик по существующей рамке выделяет её и не создаёт вторую; перетаскивание за контур пишет **одну** запись истории; клик без движения не пишет ничего; протяжка «Выбором» по пустоте не создаёт отметку (регрессия на блокер ревью) |
| проба комментария (`smokeRunNoteAffordanceProbe`) | дополнить бейджем, вынесенным **за** границу снимка, и лестницей Esc на двух состояниях: новая булавка сразу разворачивает свою пилюлю, поэтому первый шаг Esc — `expandedNote`, а `comment` под ним |

---

## 5. Что беру из контракта волны 0 и от ленты

### 5.1 Из волны 0 (мои же четыре пункта, §1.1)

`AnnotationRules` (`outlineColorOf`, `PressTarget`, `pressTargetOf`), `ToolAppearance` +
`ToolAppearanceStore` + `EditorInspector`, `NoteBadgeGeometry` (`exportScale`, `anchorRadius`,
`leader(fromRadius:)`, `ExportMargin`, `exportMargins`), `EditorGeometry`/`ToolbarLayout`
(`fit -> Double`, `placeCapture`, `measure`, `placeToolbar(mayOverlap:)`). Все четыре — чистые функции с
тестами, без AppKit кроме `CGRect`/`CGSize`/`NSColor`. Делать их до порции и одним исполнителем.

### 5.2 От порции `core-settings`

| Что нужно | Зачем |
|---|---|
| `ToolAppearanceEntry: Codable, Equatable` в `SnapikCore` и поле `toolAppearance: [String: ToolAppearanceEntry]` в `HotkeySettings` с ключом **`"toolAppearance"`** (camelCase, не как соседи) | `ToolAppearanceStore` моей зоны читает и пишет именно его; SnapikCore не видит SnapikMac, поэтому тип обязан жить в Core (§2.1) |
| Правило «пустой словарь не считается миграцией» | иначе `settings.json` переписывается на каждом старте |
| Новые пары `UiLanguage`: «Панель разметки», «Обводка», «Скруглённый», «Нет», «Неон», «Копировать снимок», «Снимок {0} скопирован», «Не удалось скопировать снимок» | подписи капсул, доступность ручки панели, четвёртый сегмент палитры, ответ кнопки «Копировать» |
| Снятые пары: «По ширине · {0} %», «По высоте · {0} %» (переключателя нет), «Цвет отметки», «Тип линии», «Толстая стрелка» | у них не осталось читателей в редакторе |
| Подтверждение, что `SettingsMigration.currentVersion` остаётся 2 | `toolAppearance` мигрирует по отсутствию ключа |

### 5.3 От порции `stack`

| Что нужно | Зачем |
|---|---|
| `copySingleCapture(_ capture:label:) async -> Bool` (или эквивалент с результатом) | кнопка «Копировать» и Shift+Cmd+C в редакторе (E-12). На Mac метода нет вовсе; редактор его только зовёт и сам говорит ответ плашкой `hintView` |
| Подтверждение, что лента спрятана, пока редактор открыт | это причина, по которой ответ говорит редактор, а не тост ленты |

Общих Mac-файлов с `stack` у меня нет: `App/SmokeTestRunner+Editor.swift` мой, `App/SmokeTestRunner.swift`
(реестр вызовов) трогает только сведение. С `core-settings` общий файл один —
`SnapikCore/Settings/HotkeySettings.swift`, и в нём я не пишу ни строки.

---

## 6. Размер, порядок, что глазам

### 6.1 Размер по пунктам

| # | Пункт | Объём | Почему |
|---|---|---|---|
| W0-1 | `AnnotationRules` | S | две функции и перечисление |
| W0-2 | `ToolAppearance` + store + инспектор | M | запись, чтение/запись словаря с разбором цветов и перечислений, таблица из семи строк |
| W0-3 | `NoteBadgeGeometry` | M | `exportScale`, `anchorRadius`, параметр `fromRadius`, `ExportMargin` с полем по восьми правилам |
| W0-4 | `EditorGeometry` + `ToolbarLayout` | M | `placeCapture`, `measure`, `mayOverlap`; `fit` теряет типы |
| E-1 | снимок 1:1, переключателя нет | L | удаление класса, разрезание файла, переименование расширения, переписанное колесо |
| E-2 | панель в три блока и две строки | L | переписанная раскладка плюс перетаскивание |
| E-3 | инспектор из двух капсул | L | две новые вью, переписанные `syncAppearance`/`applyAppearance`, удаление шести кнопок и ряда точек, слияние поповеров |
| E-4 | правило 6 | S | три строки плюс сохранность трёх общих ключей |
| E-5 | правило нажатия | L | `beginGesture` целиком плюс четыре источника сигналов |
| E-6 | комментарий сам по себе | L | ветка жеста, постановка жестом, наведение, Esc, снятие привязки |
| E-7 | экспорт с полем | M | размеры листа, сдвиг контекста, снятие клампа |
| E-8 | обводка не красится заливкой | S | одна сигнатура, два вызывающих |
| H-1 | заливка на клике | S | разделение нажатия на квадрат и на капсулу |
| H-2 | интерполяция | S | одна строка плюс чистая функция под тест |
| E-9 | выноска от точки | M | два рисовальщика |
| E-10 | точка в экспорте | S | десять строк в `AnnotationPainter` |
| E-11 | размытие без блока свойств | S | пять точечных правок |
| E-12 | кнопка «Копировать» | M | кнопка, обработчик, клавиша, шпаргалка, плашка |

### 6.2 Порядок внутри порции

Строгий, по зависимостям:

1. **Волна 0** W0-1 … W0-4 с тестами. Без них ничего не компилируется и `git merge` порции не имеет смысла.
2. **E-8** (обводка) — меняет сигнатуру, которую читают оба рисовальщика; правится один раз и до всего.
3. **E-1** (снимок 1:1) — вырезает переключатель и разрезает файл; после него номера строк в
   `Editor/` поедут, дальше все адреса пересчитывать грепом, а не по этому документу.
4. **E-2** (контейнеры панели) — **до** содержимого блока свойств.
5. **E-3** (инспектор), затем **E-4** (правило 6): E-4 пишет то, что E-3 держит.
6. **E-5** (правило нажатия) — ломает много проб, поэтому после того, как панель устаканилась.
7. **E-6** (комментарий) — опирается на `PressTarget.Object` из E-5.
8. **E-7** (поле экспорта) — опирается на `exportMargins` из W0-3 и на вынесенный бейдж из E-6.
9. **H-1**, **H-2** — независимы, кладутся отдельными коммитами, чтобы снимались одним revert.
10. **E-9** (выноска на экране), затем **E-10** (точка в экспорте): экран раньше экспорта, видно глазами,
    что правило верное.
11. **E-11** (размытие).
12. **E-12** (кнопка «Копировать») — последним: зависит от `copySingleCapture` порции `stack` и обязан
    лечь **после** E-10, иначе кнопка отгрузит картинку без точки.

Один прогон проверки на всю порцию в конце, а не после каждого пункта. Локально `swift build` не гонять —
macOS-раннера на машине нет, проверка на CI.

### 6.3 Что глазам на живом Mac

Ничего из списка ниже автопрогон не закрывает.

- Шов и прокрутка снимка двух мониторов в масштабе 1:1; Cmd+колесо «ощущением руки»; порог 4 px.
- Вид панели на узком экране и при масштабе 2×: две строки, ширина блока свойств 176, четвёртый сегмент
  палитры в поповере обводки (поповер шире прежнего на один сегмент).
- Перетаскивание панели мышью (проба двигает её через методы, а не через указатель).
- Наведение на бейдж → раскрытие пилюли; Esc над раскрытой пилюлей.
- Постановка комментария жестом «нажал — потянул»; бейдж, вытащенный на затемнённый фон рядом со снимком.
- Как выглядит поле `#2A3140` в картинке, уехавшей в чат.
- Линия комментария касается обода точки без зазора (перо линии 1, обод точки 1.5); комментарий, чей
  бейдж дотащили почти на точку, — линии нет, кружок под бейджем.
- «Сохранить на компьютер» даёт тот же кадр, что и копия в буфер (три рисовальщика Mac сошлись в двух
  кодах — проверить, что они действительно рисуют одно).
- Старая сессия с двухточечными комментариями: линия идёт от точки, а не от угла квадрата.
- Пустой блок свойств у размытия — не читается ли пустота как поломка панели.
- Рисование поверх залитой рамки и поверх текста теперь выделяет их — удобно ли так.
- Крап на фотографии (тёмная фактура) после H-2: во вписанном состоянии его быть не должно.
