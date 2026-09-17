# Дельта №5, зона «лента»: Windows `d84fbb0..f2cf62b` (1.6.0 и 1.7.0) → macOS

**База.** `mac-sync-base-4` = `d84fbb0` (Windows 1.5.0). Цель раунда: `mac-sync-base-5` = `f2cf62b` (Windows 1.7.0).
Диапазон: 76 коммитов, два раунда ТЗ (`tasks/tz-006-*` = 1.6.0, `tasks/tz-007-*` = 1.7.0).

**Зона этого документа.** Лента снимков и её транспорт. Windows: `EdgeStackWindow.xaml(.cs)`,
`EdgeStackWindow.Saving.cs`, `Controls/StripResizeGeometry.cs`, новый `Controls/RoundedClip.cs`,
`PublishedPackage.cs`, вызовы `SessionWorkspace` из ленты, пробы `RunStripGrowthProbe` / `ProbeStrip`,
тесты `StripResizeGeometryTests`, `PublishedPackageTests`, `ClipboardPackageFormatsTests`.
Mac: `macos/Sources/SnapikMac/Stack/**`, `macos/Sources/SnapikMac/Capture/**`,
`macos/Sources/SnapikMac/Transport/**`, `App/AppCoordinator*.swift` (входы показа ленты и публикации),
`App/SmokeTestRunner+Stack.swift`, `macos/Tests/SnapikMacTests/Stack*`.

**Не эта зона.** Core, настройки, строки, звук, мастер (аналитик `core-settings`); редактор и рендер
(аналитик `editor`). Кнопка «Копировать» в редакторе принадлежит `editor`, но зовёт копию одного
снимка из ленты: интерфейс описан в §5.2.

Все ссылки Windows даны по `f2cf62b`, все ссылки Swift по `master` того же коммита.
Объём: **S** ≤ 60 строк Swift, **M** 60–250, **L** > 250.

---

## 0. Резюме

### 0.1 Что из зоны уже есть на Mac

Проверено по коду, а не по спеке. Переносить не надо:

- **Геометрия окна раунда №4** уже стоит: `minimumWidth = defaultWidth = 244`, `edgeGap = 0`,
  `estimatedChromeHeight = 160` (`macos/Sources/SnapikCore/Geometry/StripResizeGeometry.swift:19, 20, 26, 39`),
  `shadowMargin = 20`, тень панели 24/5, панель 204, карточка 168
  (`macos/Sources/SnapikMac/Stack/StackMetrics.swift:27, 33, 34, 100, 108`).
- **Полоса прокрутки лежит поверх карточек, а не рядом.** Скроллер живёт в overlay-стиле
  (`EdgeStackContentView.swift:217-218`), ширина задаётся переопределением
  `scrollerWidth(for:scrollerStyle:)` (`:69`), дорожка не рисуется (`:73`), бегунок берёт цвета темы
  (`:75-81`). Появление и затухание делает система. Таймер на секунду, `BarField`, анимация `Opacity` и
  `MinWidth = 0` из Windows **не переносятся** (см. §1.1 L-3).
- **Пустая лента по содержимому** и один владелец состояния «пусто»
  (`EdgeStackContentView.updateEmptyState()`, `:350-356`): подсказка 92, список и угловой грип спрятаны.
  Это как раз то, к чему Windows пришёл в раунде №4.
- **Низ последней карточки не обрезается.** Раскладка на Mac ручная:
  `documentHeight = верх последней карточки + cardHeight + listPaddingBottom`
  (`EdgeStackContentView.swift:596-597`), то есть свеса за пределы `Extent` не существует.
  Костыль Windows `ItemsPanel Margin="0,0,0,48"` **не переносится** (§1.1 L-2).
- **Карточка уже клипует содержимое по скруглению** (`ThumbnailCardView.swift:131-133`,
  `clipView.layer.masksToBounds = true`). Прикреплённое свойство `RoundedClip` заводить не нужно,
  меняется только радиус (§1.1 L-4).
- **Локализация карточки при рождении** (`EdgeStackContentView.swift:334`) и чипы «экран» / «импорт»
  (`ThumbnailCardView.swift:234-243`) стоят с синхронизации №4.
- **Форматы буфера у пакета из одного снимка уже совпадают с Windows.**
  `MacClipboardService.setPackageGuarded` при одном пути кладёт `.png`, `.tiff` и `.fileURL` одним
  айтемом плюс отдельный айтем с текстом (`macos/Sources/SnapikMac/Transport/MacClipboardService.swift:61, 163-175, 152-156`).
  Это ровно то, что на Windows делает `CreatePackageDataObject` через `CreatePngDataObject`
  (`src/Snapik.Windows/WindowsClipboardService.cs:197-205, 219-236`). Правок в Transport раунд не требует.
- **Лента показывается на старте всегда.** Windows снял гейт `if (wizardShown)`
  (`EdgeStackWindow.xaml.cs:243`); на Mac обе ветки уже есть и вместе покрывают оба случая
  (`AppCoordinator.swift:215` без мастера, `:231` после мастера). Переносить нечего.

### 0.2 Что переносится

Четырнадцать позиций, из них «нет на Mac» девять, «расходится» пять. Подробно в §1.

| # | Что | Раунд | Объём |
|---|---|---|---|
| L-1 | Карточка не разворачивается по выбору и фокусу | tz-006 B1 | S |
| L-2 | Высота списка по содержимому: `listHeightForCount`, `applyListHeight()` | tz-006 B2 | M |
| L-3 | Поля списка `4,14,12,8` и ширина полосы 3 / 6 | tz-006 B2, B3 | S |
| L-4 | Клип миниатюры по внутренней кромке рамки (радиус 10, а не 11) | tz-006 B4 | S |
| L-5 | Тень карточки 12 вместо 16 | tz-006 B3 | S |
| L-6 | Капсула встаёт на угол ленты, разворот возвращает ленту туда же | tz-006 B5 | M |
| L-7 | `positionAtEdge()` делится на «поставить в первый раз» и «просто показать» | tz-006 B5 | M |
| L-8 | Прокрутка к последнему снимку на показе и на обоих импортах | tz-007 B1 | M |
| L-9 | Плашка карточки растяжкой 30 px в три стопа, белые иконка и счётчик с тенью | tz-007 B2 | M |
| L-10 | Цвета карточки и трёх рамок из темы | tz-007 B2 | S |
| L-11 | Раскрытие карточки под курсором с задержкой 150 мс | tz-007 B2 | M |
| L-12 | `StackHeightManual` и двойной клик по ручке угла | tz-007 B3 | M |
| L-13 | Контекстное меню карточки и копия одного снимка | tz-007 B4 | L |
| L-14 | Одиночная копия не пересобирается, не чистит ленту, переживает очистку и выход | tz-007 B4 | M |

### 0.3 Что не переносится, с обоснованием

1. **`MinWidth = 0` у полосы прокрутки, `BarField`, `_scrollBarTimer`, `FadeStripScrollBar`,
   `OnStripScrolled`, `OnBarFieldEnter/Leave`** (Windows `EdgeStackWindow.xaml:113-116, 164-181`,
   `.xaml.cs:293-336`). Вся «вторая, тусклая полоса» это дефект дефолтной темы WPF: `Width="4"`
   проигрывает `MinWidth = 17`. На Mac ширина задаётся переопределением класса
   (`EdgeStackContentView.swift:69`), минимума ниоткуда не приходит, появление и затухание overlay-скроллера
   делает система. Переносится только само число ширины (§1.1 L-3).
2. **Перешаблонивание `ListBox` в голый `ScrollViewer`** (Windows `EdgeStackWindow.xaml:233-243`) и
   `ControlTemplate x:Key="StackScrollViewer"` (`:155-183`). Лечили `Padding="1"` у `Border x:Name="Bd"`
   дефолтного шаблона, из-за которого влезающий список прокручивался на 2 px. На Mac `NSScrollView`
   создаётся руками, никакого чужого шаблона нет.
3. **`ItemsPanel` с `Margin="0,0,0,48"`** (Windows `EdgeStackWindow.xaml:253`). Компенсация того, что
   `StackPanel` не меряет отрицательный `Margin` последней карточки. На Mac фреймы считаются вручную
   (`EdgeStackContentView.swift:596-607`), свеса нет. Число 48 попадёт на Mac только как величина
   сдвига соседей при раскрытии (§1.2 L-11).
4. **`Controls/RoundedClip.cs`** (новый файл Windows, 45 строк). Прикреплённое свойство, которое на
   `SizeChanged` кладёт `RectangleGeometry` со скруглением. На Mac это `layer.cornerRadius +
   masksToBounds`, и он уже стоит (`ThumbnailCardView.swift:131-133`). Комментарий самого Windows-файла
   («it maps one to one onto the layer of the macOS port») это подтверждает.
5. **Вся B6 раунда tz-006 «лента как окно панели задач»**: `ShowInTaskbar="True"`,
   `ResizeMode="CanMinimize"`, `WindowState.Minimized` вместо `Hide()`, `ShowWindow(SW_SHOWNOACTIVATE)`,
   проба `VerifyALayeredWindowMinimisesAsync` (`SmokeTestRunner.cs:311`). Приложение на Mac живёт
   агентом: `app.setActivationPolicy(.accessory)` (`macos/Sources/SnapikMac/main.swift:29, 37, 44`) и
   `LSUIElement: true` (`macos/project.yml:32`), значка в Dock нет вовсе, а лента это `NSPanel` с
   `canBecomeKey == false` (`EdgeStackWindowController.swift:11-12`). Требование «пока Snapik работает,
   под иконкой линия» на Mac закрыто иконкой в строке меню (`StatusBarController`), кнопка шапки
   остаётся `hide()` → `orderOut` (`EdgeStackWindowController.swift:92-95`), пункт «Показать ленту» в
   строке меню работает как раньше. Смена политики активации на `.regular` это продуктовое решение, а
   не перенос, и в этот раунд не входит.
6. **Строка `("Свернуть в трей", "Hide to tray")` → `("Свернуть", "Minimize")`** у кнопки шапки.
   Следствие пункта 5: кнопка на Mac по-прежнему прячет ленту, а не сворачивает окно. Пара
   `("Свернуть", "Minimize")` на Windows существовала и раньше (`UiLanguage.cs:147`), новой строки в
   таблицу не добавлялось.
7. **`RenderOptions.BitmapScalingMode="HighQuality"` у миниатюры** (`EdgeStackWindow.xaml:286`,
   коммит `a3861c7`). На Mac миниатюра рисуется `NSImageView` с `imageScaling`
   (`ThumbnailCardView.swift:136, 197`), и Core Graphics по умолчанию интерполирует, а не берёт
   ближайший пиксель. Переносить нечего; если на живом Mac уменьшенный снимок будет «крошиться»,
   лечится `imageView.layer?.minificationFilter = .trilinear`, но это не дефект раунда.
8. **Порядок `e.Handled = true` до `await`** в `OnRemoveCaptureClick` (правка ревью,
   `EdgeStackWindow.xaml.cs:692`). Артефакт маршрутизируемых событий WPF, на AppKit смысла не имеет.
   Переносится только вынос тела удаления в отдельный метод, потому что его зовёт контекстное меню
   (на Mac метод уже отдельный: `AppCoordinator.removeCapture(_:)`, `AppCoordinator.swift:468`).

---

## 1. По пунктам

### 1.1 Раунд 1.6.0 (`tasks/tz-006-*`, ТЗ №5 Кати), дорожка B

Источники: `tasks/tz-006-details/B-strip.md`, `tasks/tz-006-notes-B.md`,
`tasks/verification.md` раздел «ТЗ №5 Кати … (tz-006)», подраздел «Дорожка B: лента».

#### L-1. Наведение, фокус и выбор не трогают геометрию карточки

**Windows.** Коммит `74fdbf6`. Из триггеров `IsMouseOver` и `IsKeyboardFocusWithin` убраны сеттеры
`Margin="0,4,0,4"`, триггер `IsSelected` удалён целиком вместе с акцентной рамкой. На `f2cf62b` от
триггера фокуса остался только `DeleteButton.Opacity` (`EdgeStackWindow.xaml:412-414`), от
`IsSelected` не осталось ничего. Смысл: после возврата из редактора карточка выглядит как все.

**Mac.** Аналог бага есть и он шире: `layoutCards` раскрывает карточку и по наведению, и по выбору
(`EdgeStackContentView.swift:589`, `let expanded = card.isHovered || card.isSelected`), добавляя
`StackMetrics.expandedMargin = 4` сверху и снизу (`:590-594`); рамка выбранной карточки красится
акцентом (`ThumbnailCardView.swift:314-315`, `StackTheme.cardSelectedBorder`,
`StackMetrics.swift:127`); крестик показывается и при выборе (`ThumbnailCardView.swift:325`).

**Что менять.**
1. `EdgeStackContentView.swift:589` — `isSelected` из условия раскрытия убрать. Само раскрытие по
   наведению переписывается в L-11, поэтому эти две правки делать одним куском.
2. `ThumbnailCardView.swift:312-321` — ветку `isSelected` из `updateAppearance()` убрать; остаются
   hover, sent и обычная.
3. `StackTheme.cardSelectedBorder` (`StackMetrics.swift:127`) снять, если после правки на него никто
   не ссылается (проверить `grep -rn "cardSelectedBorder" macos/`).
4. `StackMetrics.expandedMargin` (`:70`) снять: после L-11 раскрытие идёт другим числом.
5. `ThumbnailCardView.swift:325` — крестик по `isHovered`, без `isSelected`.

**Что НЕ трогать.** Само свойство `isSelected` и `setSelectedCapture(_:)`
(`EdgeStackContentView.swift:365`) остаются: Windows тоже оставил `capture.IsSelected`, оно ставится и
снимается симметрично и ничего не красит. Вызывающие `setSelectedCapture`:
`EdgeStackContentView.swift:657` (открытие карточки) и контракт
`EdgeStackWindowController.setSelectedCapture(_:)` из `CONTRACTS.md`.

**Объём:** S.

#### L-2. Высота списка по содержимому

**Windows.** Коммит `5f2dc23`. Формула `14 + (n − 1)·30 + 78 + 8` с потолком из настроек:
`StripResizeGeometry.ListHeightForCount(count, cap)` (`Controls/StripResizeGeometry.cs:67-73`) плюс
константы `EmptyListHeight = 92`, `ListTopPadding = 14`, `ListBottomPadding = 8`, `CardHeight = 78`,
`CardOverlap = 48`, `CardPitch = 30` (`:50-58`). Точка применения: `ApplyListHeight()`
(`EdgeStackWindow.xaml.cs:876-882`), которую зовёт `UpdateEmptyState()` (`:1587`), а через неё
`Renumber()` и все двенадцать путей изменения ленты. Контрольные числа: 2 → 130, 5 → 220, 12 → 372.
`MinimumListHeight = 180` остаётся полом только для сохранённого числа, к росту по содержимому не
применяется.

**Mac.** Аналога нет вовсе. `contentContainer.listHeight` пишется один раз, в `positionAtEdge()`
(`EdgeStackWindowController.swift:235-238`), и это всегда `clampListHeight(settings.stackHeight, …)`,
то есть сохранённое число. `StackMetrics.listContentHeight(count:)` (`StackMetrics.swift:113-116`)
объявлена и **не вызывается ниоткуда**: её формула совпадает с Windows, кроме нижнего паддинга 52.

**Что менять.**
1. Волна 0 (запрос к `core-settings`, §5.1): в `SnapikCore/Geometry/StripResizeGeometry.swift` добавить
   константы `emptyListHeight = 92`, `listTopPadding = 14`, `listBottomPadding = 8`, `cardHeight = 78`,
   `cardOverlap = 48`, `cardPitch = 30` и обе функции `listHeightForCount(count:cap:)` и
   `listHeight(count:stored:manual:)`. Числа геометрии карточки живут на Windows в
   `StripResizeGeometry`, а на Mac сейчас в `StackMetrics`; дублировать их нельзя, поэтому
   `StackMetrics.cardHeight/cardOverlap/cardStep/listPaddingTop/listPaddingBottom/emptyHintHeight`
   становятся псевдонимами Core-констант (`static let cardHeight = CGFloat(StripResizeGeometry.cardHeight)`),
   и в зоне Stack остаётся только приведение к `CGFloat`.
2. `StackMetrics.listContentHeight(count:)` (`:113`) снять: её заменяет
   `StripResizeGeometry.listHeightForCount`, и держать две формулы одного числа нельзя.
3. Новый метод `EdgeStackWindowController.applyListHeight()` рядом с `positionAtEdge()` (`:220`):

```swift
private func applyListHeight() {
    let settings = coordinator?.settings ?? HotkeySettings.default
    let stored = StripResizeGeometry.clampListHeight(
        settings.stackHeight, workHeight: Double(workArea().height),
        chromeHeight: Double(contentContainer.chromeHeight()))
    contentContainer.listHeight = CGFloat(
        StripResizeGeometry.listHeight(
            count: contentContainer.rowCount, stored: stored, manual: settings.stackHeightManual))
}
```

`contentContainer.rows` сейчас приватное (`EdgeStackContentView.swift:179`); открыть только счётчик
(`var rowCount: Int { rows.count }`), не сам массив.

4. Звать `applyListHeight()` из `refresh()` (`EdgeStackWindowController.swift:134-163`, перед
   `layoutWindow()`), а не из `reload(rows:)` вида: на Windows владелец `UpdateEmptyState`, на Mac
   эквивалент по покрытию это `refresh()`, через который проходят все изменения состава ленты.
   Список вызывающих `refresh()` (проверено grep): `AppCoordinator.swift:212` (старт), `:479`
   (удаление), `:496` (возврат удалённого), `:511` (перестановка), `:550` (сброс сессии),
   `AppCoordinator+Package.swift:308` (импорт файла), `:332` (импорт из буфера), `:382` (весь экран),
   `AppCoordinator+OverlayEditorDelegate.swift:62` (коммит из редактора),
   `AppCoordinator+PasteIntent.swift:179` (пометка «отправлено»),
   `EdgeStackWindowController.swift:78` (внутри `reveal()`). Это те же точки, что на Windows.
5. `positionAtEdge()` (`:235-238`) перестаёт считать высоту сам и зовёт `applyListHeight()`.

**Ловушки AppKit.** `chromeHeight()` (`EdgeStackContentView.swift:460`) считается из констант, а не
из фактической высоты окна, поэтому на Mac нет Windows-дефекта «на пустой ленте хром равен всему
окну». Зато `footerHeight()` (`:478`) зависит от видимости тоста и статуса, то есть `applyListHeight()`
надо звать до `layoutWindow()`, иначе окно поедет на один кадр.

**Объём:** M.

#### L-3. Поля списка и ширина полосы прокрутки

**Windows.** Коммиты `5f2dc23`, `6696861`. `Padding="8,14,8,52"` → `Padding="4,14,12,8"`
(`EdgeStackWindow.xaml:223`); правое поле 12 это дорожка полосы, левое отдаёт четыре пикселя обратно,
чтобы карточка осталась 168. В геометрии заведены `ListPaddingLeft = 4` и `ListPaddingRight = 12`
(`Controls/StripResizeGeometry.cs:42-43`), `CardWidth` считает
`w − 2·ShadowMargin − 2·ShellPadding − ListPaddingLeft − ListPaddingRight` (`:46-47`). Полоса 3 px в
покое и 6 по наведению (`EdgeStackWindow.xaml:168, 180`), поле полосы 12 (`:164`).

**Mac.** `listPaddingLeft = 8`, `listPaddingRight = 8`, `listPaddingBottom = 52`
(`StackMetrics.swift:50, 52, 53`), `scrollBarWidth = 4` (`:56`), `scrollerInsets` справа 1
(`EdgeStackContentView.swift:221`).

**Что менять.** Числа в `StackMetrics.swift`: `listPaddingLeft` 8 → **4**, `listPaddingRight` 8 → **12**,
`listPaddingBottom` 52 → **8**, `scrollBarWidth` 4 → **3**. Ширину 6 по наведению даёт уже
существующий `isHovered` скроллера: в `StackScroller.drawKnob()` (`:75-81`) вместо
`let width = StackMetrics.scrollBarWidth` писать `isHovered ? 6 : StackMetrics.scrollBarWidth`.
Само `scrollerWidth(for:scrollerStyle:)` (`:69`) оставить равным 12 или менять нельзя без проверки:
оно задаёт ширину полосы дорожки, а не бегунка. Рекомендация: `scrollerWidth` вернуть 12 (поле
Windows), а бегунок рисовать 3 / 6 внутри него, тогда числа сойдутся один в один и зона наведения
будет 12 pt, как `BarField` на Windows.

**Арифметика после правки.** `cardWidth(244) = 244 − 40 − 20 − 4 − 12 = 168`, прежние 168 сохраняются
(`StackMetrics.swift:108-110`, формула та же, слагаемые другие). Содержимое списка:
`documentHeight = 14 + (n − 1)·30 + 78 + 8`, побайтно как `ListHeightForCount` на Windows.

**Ловушка.** Тень карточки расходится вбок на половину блюра (L-5): при поле 12 и блюре 16 она залезет
на дорожку полосы, поэтому L-3 и L-5 делаются вместе.

**Объём:** S.

#### L-4. Клип миниатюры по внутренней кромке рамки

**Windows.** Коммит `539c6ec`. `ClipToBounds="True"` снят, на внутреннем `Grid` карточки стоит
`controls:RoundedClip.Radius="10"` (`EdgeStackWindow.xaml:283`); десять это одиннадцать у рамки минус
её толщина 1, чтобы картинка не наползала на штрих.

**Mac.** `clipView.layer?.cornerRadius = StackMetrics.cardCornerRadius` (`ThumbnailCardView.swift:132`),
то есть 11, а рамка шириной 1 у самого view (`:121-122`). Расхождение на один пиксель по всему контуру.

**Что менять.** `ThumbnailCardView.swift:132` →
`clipView.layer?.cornerRadius = StackMetrics.cardCornerRadius - 1`, и там же комментарий, откуда
берётся единица (`layer?.borderWidth` на `:122`). Лучше завести
`StackMetrics.cardBorderWidth: CGFloat = 1` и вычитать её, чтобы два числа не разъехались.

**Ловушка AppKit.** `clipView` занимает весь `bounds` карточки (`ThumbnailCardView.swift:257`), а
рамка рисуется слоем самой карточки поверх. Уменьшение радиуса клипа без уменьшения фрейма `clipView`
даст правильную картинку (клип идёт по внутренней кромке), фрейм не трогать.

**Объём:** S.

#### L-5. Тень карточки

**Windows.** Коммит `6696861`. `BlurRadius` 16 → **12** (`EdgeStackWindow.xaml:277`), `ShadowDepth`
остаётся 6, `Opacity` 0.35, направление вверх. Причина в комментарии: половина блюра это разлёт вбок,
и шестнадцать заходили в дорожку полосы.

**Mac.** `StackMetrics.cardShadowBlur = 16` (`:78`), применяется как
`layer?.shadowRadius = cardShadowBlur / 2` (`ThumbnailCardView.swift:125`), смещение +6 вверх (`:129`),
`shadowPath` пересчитывается в `layoutSubviews()` (`:258-260`).

**Что менять.** `StackMetrics.swift:78` — 16 → **12**. Пересчёт `shadowRadius = blur / 2` и
`shadowPath` трогать не надо.

**Объём:** S.

#### L-6. Капсула появляется на месте ленты и возвращает её туда же

**Windows.** Коммит `3c2ebba`. Новое поле `_expandedLeft` (`EdgeStackWindow.xaml.cs:87`), пишется в
`CollapseToCapsule` (`:774`); `PositionCapsuleAtEdge` заменён на `PositionCapsuleAtStrip`
(`:825-829`), который считает место через чистую
`StripResizeGeometry.CapsuleLeft(stripLeft, stripWidth, capsuleWidth)`
(`Controls/StripResizeGeometry.cs:88-89`); `ExpandFromCapsule` (`:795-822`) ставит окно одним
`PlaceWindow(RestoreRect(...))` (`:833-840`, `StripResizeGeometry.cs:95-104`), где `RestoreRect`
возвращает прямоугольник как есть, если он влезает в рабочую область, и подвигает его, только если не
влезает. Поле `_expandedListHeight` **снято** (правка ревью раунда): высота после разворота считается
из `UpdateEmptyState() → ApplyListHeight()`, потому что снимки могли добавиться, пока лента стояла
капсулой. `ShowStackWithoutActivation` капсулу не двигает вовсе (`:730`,
`if (!_capsuleMode) EnsureStripPlaced();`).

**Mac.** `collapseToCapsule()` (`EdgeStackWindowController.swift:329-337`) запоминает только
`expandedWidth` (`:332`) и `expandedTop` (`:333`); `positionAtEdge()` в ветке капсулы ставит её у
`work.maxX - size.width` (`:227`), то есть у края монитора; `expandFromCapsule()` (`:341-353`)
возвращает ленту к `work.maxX - width` (`:351`). Оттащенная от края лента после капсулы прыгает к краю,
и после каждого показа тоже (L-7).

**Что менять.**
1. Волна 0: `StripResizeGeometry.capsuleLeft(stripLeft:stripWidth:capsuleWidth:)` и
   `restoreRect(...)` в Core. **Про подпись `restoreRect`:** Core компилируется в том числе на Windows
   и намеренно не знает ни `CGRect`, ни `NSRect` (все существующие функции берут и отдают `Double`,
   см. `widthFromStart`, `StripResizeGeometry.swift:57`). Поэтому подпись должна быть на `Double`, а не
   на `CGRect`:
   `restoreRect(x:y:width:height:workX:workY:workWidth:workHeight:) -> (x: Double, y: Double)`.
   Зона Stack переводит `NSRect` в эти восемь чисел на месте вызова.
2. Новое поле `private var expandedLeft: CGFloat` рядом с `expandedWidth`
   (`EdgeStackWindowController.swift:31`), запись в `collapseToCapsule()` рядом с `:332-333`.
3. Ветка капсулы в `positionAtEdge()` (`:223-231`): `x` считать
   `CGFloat(StripResizeGeometry.capsuleLeft(stripLeft: Double(expandedLeft), stripWidth: Double(expandedWidth), capsuleWidth: Double(size.width)))`,
   а не `work.maxX - size.width`.
4. `expandFromCapsule()` (`:341-353`): вместо `work.maxX - width` пропустить прямоугольник
   `(expandedLeft, expandedTop - height, width, height)` через `restoreRect` и поставить окно одним
   `window.setFrame(_:display:)`.

**Ловушки AppKit.**
- **Порядок Windows тут не нужен.** Вся возня с `SizeToContent.Manual` и `SetWindowPos`
  (`EdgeStackWindow.xaml.cs:806-821`) лечит то, что WPF проводит собственный проход раскладки между
  присваиваниями `Width`, `Left` и `Top`. На AppKit `setFrame(_:display:)` уже один вызов, и
  `expandFromCapsule()` его и делает. Переносится только правило «монитор не пересчитывать»: рабочая
  область берётся как рамка для клампа, новый `x` из неё не выводится.
- **`workArea()` на Mac всегда отдаёт первый экран** (`EdgeStackWindowController.swift:212-213`,
  `NSScreen.screens.first ?? NSScreen.main`). Windows спрашивает монитор, на котором стоит окно
  (`Screen.FromHandle`). На одном мониторе разницы нет, на двух лента, оттащенная на второй экран,
  будет клампиться рамкой первого. Это расхождение старше раунда (§3.5), но именно `restoreRect`
  делает его видимым: рекомендую в этом же куске заменить `workArea()` на
  `window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? …`. Если это решат не делать, в
  `verification.md` надо записать строкой.
- `expandedTop` на Mac это `window.frame.maxY` (верх в координатах AppKit, Y вверх), а Windows-овский
  `_expandedTop` это `Top` (Y вниз). Формулу `y = expandedTop - height` менять не надо, но в
  `restoreRect` передавать надо именно `y` нижней кромки, а не `expandedTop`.

**Объём:** M.

#### L-7. Постановка ленты делится надвое

**Windows.** Коммит `5f2dc23`. `PositionAtEdge` разделён на `PlaceStripInitially()`
(`EdgeStackWindow.xaml.cs:887-906`, зовётся один раз из `OnLoaded`, `:241`) и `EnsureStripPlaced()`
(`:908-917`, зовётся из `ShowStackWithoutActivation`, `:730`). Первый ставит ширину из настроек,
прижимает к правому краю и центрирует по вертикали; второй только применяет высоту списка и
возвращает прямоугольник в рабочую область через `RestoreRect`, то есть оставляет ленту там, куда её
оттащили. Без этого разделения не закрывается ни B2 (`PositionAtEdge` затирал высоту на каждом
показе), ни B5 (лента прыгала к краю после каждого снимка).

**Mac.** `positionAtEdge()` (`EdgeStackWindowController.swift:220-247`) один на оба случая и зовётся
из `reveal()` (`:79`), то есть на **каждом** показе переписывает `x`, `y`, `width` и `listHeight`.
Перетаскивание окна за панель (`window?.performDrag`, `:501`) отменяется первым же снимком.

**Что менять.** Разделить на два метода по образцу Windows:

```swift
/// Первая постановка: правый край рабочей области, ширина из настроек, середина по вертикали.
private func placeStripInitially() { … нынешнее тело :233-246 с applyListHeight() вместо :235-238 … }

/// Каждый следующий показ: высота по содержимому и возврат прямоугольника на экран, если он с него ушёл.
private func ensureStripPlaced() {
    guard let window else { return }
    applyListHeight()
    contentContainer.layoutSubtreeIfNeeded()
    let height = contentContainer.windowHeight()
    let frame = NSRect(x: window.frame.minX, y: window.frame.maxY - height, width: window.frame.width, height: height)
    let work = workArea()
    let placed = StripResizeGeometry.restoreRect(…)
    window.setFrame(NSRect(x: placed.x, y: placed.y, width: frame.width, height: height), display: true)
    contentContainer.frame = NSRect(origin: .zero, size: NSSize(width: frame.width, height: height))
}
```

`reveal()` (`:76-88`) зовёт `ensureStripPlaced()` вместо `positionAtEdge()`, а `placeStripInitially()`
зовётся один раз. **Где именно первый раз:** на Windows это `OnLoaded`, до первого показа. На Mac
эквивалент это `AppCoordinator.start()` (`AppCoordinator.swift:161`, перед `refresh()` на `:212`) либо
флаг `private var placedOnce = false` внутри контроллера, который `reveal()` проверяет первым делом.
Рекомендую флаг: `start()` уже перегружен, а контроллер и так владеет геометрией.

**Вызывающие показа ленты на Mac.** Windows-овским десяти входам `ShowStackWithoutActivation()` /
`RevealStack()` (`App.xaml.cs:91`, `EdgeStackWindow.Saving.cs:151`, `EdgeStackWindow.xaml.cs:171, 193,
243, 666, 1103, 1975, 2069, 2081`) соответствует **семнадцать** вызовов `reveal()` на Mac, и все они
идут через один метод, так что правка одна:

| Mac, файл:строка | Что это |
|---|---|
| `App/AppDelegate.swift:36` | второй экземпляр приложения |
| `App/AppDelegate.swift:48` | пункт строки меню «Показать ленту» |
| `App/AppCoordinator.swift:215` | старт без мастера |
| `App/AppCoordinator.swift:231` | завершение мастера |
| `App/AppCoordinator.swift:292` | `newCapture()`, сессия не завелась |
| `App/AppCoordinator.swift:347` | лента переполнена |
| `App/AppCoordinator.swift:363` | кадр экрана не снялся |
| `App/AppCoordinator.swift:446, 454` | ошибки открытия карточки |
| `App/AppCoordinator+Package.swift:358` | снимок всего экрана, лента полна |
| `App/AppCoordinator+Package.swift:366` | `defer` снимка всего экрана |
| `App/AppCoordinator+Package.swift:435` | выход не сохранился |
| `App/AppCoordinator+OverlayEditorDelegate.swift:34` | коммит в сменившуюся сессию |
| `App/AppCoordinator+OverlayEditorDelegate.swift:71` | успешный коммит снимка |
| `App/AppCoordinator+OverlayEditorDelegate.swift:78` | ошибка коммита |
| `App/AppCoordinator+OverlayEditorDelegate.swift:91` | отмена в редакторе |
| `Stack/EdgeStackWindowController.swift:439` | после «Очистить ленту» |
| `Stack/EdgeStackWindowController.swift:578` | после «Пройти знакомство заново» |

**Объём:** M.

### 1.2 Раунд 1.7.0 (`tasks/tz-007-*`, ТЗ №6 Кати), дорожка B

Источники: `tasks/tz-007-details/B-strip.md`, `tasks/tz-007-notes.md`,
`tasks/verification.md` раздел «ТЗ №6 Кати … (tz-007)».

#### L-8. Прокрутка к последнему снимку

**Windows.** Коммит `93ba097`. `ScrollStripToEndCore()` (`EdgeStackWindow.xaml.cs:349-356`) и
отложенная обёртка `ScrollStripToEnd()` (`:358`, `DispatcherPriority.Loaded`); вьюер и полоса ищутся
один раз и кэшируются (`StripScrollViewer()`, `:328-335`; `StripScrollBar()`, `:337-347`). Зовётся
ровно в трёх местах: последней строкой `ShowStackWithoutActivation()` (`:738`), в `ImportFileAsync`
(`:1271`) и в `ImportClipboardAsync` (`:1287`). Сознательно **не** зовётся из `Renumber` и
`UpdateEmptyState`: те висят на удалении, перестановке и пометке «отправлено», где низ это неверное
место. `RestoreRemoved` тоже не трогается: он вставляет на прежний индекс.

Прокручивается низ ленты, а не последняя карточка: контейнер карточки на Windows высотой 30, и
`ScrollIntoView` показал бы 30 px из 78.

**Mac.** Прокрутки к концу нет вообще. Единственная работа со скроллом это сохранение позиции «от
верха» в `layoutCards` (`EdgeStackContentView.swift:599-623`): при добавлении карточки лента остаётся
там, где стояла, и новый снимок оказывается ниже обреза.

**Что менять.**
1. В `EdgeStackContentView` завести флаг и метод:

```swift
private var pinToNewestOnNextLayout = false
func scrollToNewest() { pinToNewestOnNextLayout = true; needsLayout = true }
```

и в конце `layoutCards` (`:620-623`) вместо восстановления позиции по `distanceFromTop` при поднятом
флаге ставить прокрутку на новейшую карточку и флаг гасить.

2. Вызовы: `EdgeStackWindowController.reveal()` последней строкой (после `positionAtEdge`/`ensureStripPlaced`
   и до или после fade-in, порядок неважен, важно после раскладки), плюс два импорта на Mac:
   `AppCoordinator+Package.swift:308` (`importFiles()`, после `refresh()`) и `:332`
   (`importFromClipboard()`, после `refresh()`). Точки `AppCoordinator.swift:495` (`restoreRemoved`),
   `:479` (`removeCapture`), `:512` (`reorderCapture`) и `AppCoordinator+PasteIntent.swift:179`
   (`markCapturesSent`) **не трогать**, ровно как на Windows.

**Ловушки AppKit. Это самое опасное место раунда.**

- **`scrollToEnd()` на Mac прокрутил бы не туда.** `listContainer` (`StackListView`) намеренно
  **не flipped** (`EdgeStackContentView.swift:102-104`), фреймы карточек считаются как
  `y = documentHeight − top − cardHeight` (`:605`), то есть **новейшая карточка имеет наименьший `y`,
  и она внизу документа**. «Показать последний снимок» на AppKit это
  `scrollView.contentView.scroll(to: NSPoint(x: 0, y: 0))` плюс
  `scrollView.reflectScrolledClipView(scrollView.contentView)`, а вовсе не `scrollToEnd()`
  (`NSView.scrollToEndOfDocument` на неперевёрнутом вью уедет вверх, к самому старому снимку).
- **Порядок с `layoutCards`.** `layoutCards` в конце сам ставит `origin` (`:620-622`). Если позвать
  прокрутку до него, он её затрёт. Поэтому прокрутка живёт внутри `layoutCards` под флагом, а не
  отдельным вызовом после. Это прямой аналог Windows-овского `DispatcherPriority.Loaded`.
- **Раскладка должна быть готова.** На Windows прокрутка откладывается до прохода раскладки. На Mac
  эквивалент это `contentContainer.layoutSubtreeIfNeeded()` перед прокруткой, что `positionAtEdge()`
  уже делает (`EdgeStackWindowController.swift:240`). Отдельный `DispatchQueue.main.async` не нужен и
  вреден: он даст видимый прыжок после появления окна.
- **Тик звука.** `TickingScrollView.scrollWheel` (`:54`) играет тик только на колесе, программная
  прокрутка через `contentView.scroll(to:)` его не трогает. Аналога Windows-овской проблемы «прокрутка
  зажигает полосу на секунду» нет: overlay-скроллер сам решает, показываться ли.

**Открытый пункт, который надо назвать Никите** (Windows его тоже не решил): возврат из редактора
(`AppCoordinator+OverlayEditorDelegate.swift:71`) идёт через `reveal()` и тоже уедет вниз, так что
после правки карточки C в ленте из четырнадцати вы окажетесь у последней, а не у C.

**Объём:** M.

#### L-9. Плашка карточки: растяжка вместо сплошной

**Windows.** Коммит `34ed57f`. Высота 26 → **30** (`EdgeStackWindow.xaml:297`), фон вместо сплошного
`#E6171A20` это вертикальный градиент в три стопа: `#8C141E1E` на 0, `#47141E1E` на 0.6, `#00141E1E`
на 1 (`:299-303`). Прозрачный стоп несёт тот же RGB, иначе градиент уходит через серый. Иконка заметок
и счётчик стали белыми (`:319-320`), под их `StackPanel` подложена одна общая тень
`BlurRadius="2" ShadowDepth="1" Direction="270" Opacity="0.6"` (`:310`), у кружка буквы своя
`BlurRadius="3" Opacity="0.4"` (`:312`). `ThumbImage.Opacity="0.86"` оставлена.

**Mac.** `labelStrip` это `NSView` со сплошной заливкой `StackTheme.cardLabelStripBackground = #E6171A20`
(`StackMetrics.swift:130`, применяется `ThumbnailCardView.swift:214`), высота
`cardLabelStripHeight = 26` (`StackMetrics.swift:74`, фрейм `ThumbnailCardView.swift:265`). Иконка
заметок `#AEB8C7` (`:161`), счётчик `#DCE3ED` (`:166`), теней нет ни у кого.

**Что менять.**
1. `StackMetrics.cardLabelStripHeight` 26 → **30** (`:74`).
2. `StackTheme.cardLabelStripBackground` (`:130`) заменить на три стопа. На AppKit `NSView` с
   `backgroundColor` градиента не умеет, вариантов два:
   - `CAGradientLayer` как слой `labelStrip`: `colors = [#8C141E1E, #47141E1E, #00141E1E]`,
     `locations = [0, 0.6, 1]`, `startPoint = CGPoint(x: 0.5, y: 1)`, `endPoint = CGPoint(x: 0.5, y: 0)`
     (у слоя Y вверх по умолчанию `isGeometryFlipped == false`, значит верх это `y = 1`);
   - подкласс `NSView` с `draw(_:)` и `NSGradient(colors:atLocations:colorSpace:)`, как уже сделано у
     панели (`StackPanelView.draw(_:)`, `EdgeStackContentView.swift:148`) и в `StackBrush.fill`
     (`StackMetrics.swift:161`).

   Рекомендую второй: в зоне уже есть `StackBrush` со своим переводом стопов из системы координат WPF
   (`StackMetrics.swift:179-181`), и `CONTRACTS.md` в общих правилах просит предпочитать
   `NSView` с ручным `draw(_:)` слоевым трюкам. Слой `labelStrip` при этом перестаёт красить фон,
   `ThumbnailCardView.swift:214` уходит.
3. Цвета иконки и счётчика (`ThumbnailCardView.swift:161, 166`) на белый; тень под ними одна на группу.
   На AppKit тень текста это `NSShadow` в атрибутах строки либо `layer.shadowOpacity` у контейнера.
   Отдельного контейнера у иконки и счётчика сейчас нет (оба лежат прямо в `labelStrip`, фреймы
   `:269, 283`): завести `NSView` вокруг них и повесить тень на его слой, как на Windows
   (`BlurRadius 2 → shadowRadius 1`, `ShadowDepth 1 Direction 270 → shadowOffset (0, -1)`,
   `Opacity 0.6`). Кружку буквы своя тень (`shadowRadius 1.5`, `offset (0, -1)`, `opacity 0.4`).
4. `ThumbnailCardView.swift:123` — `masksToBounds = false` у карточки оставить как есть, иначе тень
   карточки пропадёт; тени бейджа и группы вешаются на их собственные слои.

**Ловушка.** `WPF DropShadowEffect.Direction = 270` это «вниз» в системе, где Y растёт вниз. На AppKit
слой не перевёрнут (`ThumbnailCardView.swift:127-129` про это прямо говорит), поэтому вниз это
`shadowOffset = CGSize(width: 0, height: -1)`. Не скопировать сюда знак от тени карточки, которая
намеренно идёт вверх (`+6`).

**Объём:** M.

#### L-10. Цвета карточки и рамок из темы

**Windows.** Коммит `34ed57f`. Константы тёмной палитры, зашитые в карточку, заменены на токены:
фон `{DynamicResource ElevatedBrush}` и рамка `{DynamicResource ElevatedLineBrush}`
(`EdgeStackWindow.xaml:268-269`), рамка наведения `{DynamicResource TextFaintBrush}` вместо `#718096`
(`:409`), рамка отправленного снимка `{DynamicResource SurfaceLineBrush}` вместо `#333C49` (`:357`).
Радиусы 11 и 10 оставлены сознательно (пара «внешний минус толщина рамки»); «один радиус» из ТЗ
**не сделан**, и это записано в «Что сказать Кате» (`tasks/verification.md`, пункт 1).

**Mac.** Фон уже из темы (`StackTheme.cardBackground = palette.elevated`, `StackMetrics.swift:128`), а
три рамки разъехались:

| Состояние | Mac сейчас | Целевое |
|---|---|---|
| обычная | `palette.surfaceLine` (`StackMetrics.swift:125`) | `palette.elevatedLine` |
| наведение | `#718096` константа (`:126`) | `palette.textFaint` |
| отправленный | `#333C49` константа (`:132`) | `palette.surfaceLine` |

Все три токена в `ThemePalette` есть (`macos/Sources/SnapikMac/App/Theme.swift:58, 60, 66`).
`sentBadgeBackground = #4A5563` (`:131`) остаётся константой, Windows её тоже не тронул
(`EdgeStackWindow.xaml:358`). Чипы `#1FFFFFFF` (`ThumbnailCardView.swift:26`) не меняются, Windows их
тоже оставил (`EdgeStackWindow.xaml:328, 334`).

**Что менять.** Три строки в `StackMetrics.swift:125, 126, 132`, плюс `cardHoverBorder` и
`sentCardBorder` из `static let` становятся `static var` (читают палитру).

**Проверка глазами.** Тёмная тема после правки не меняется ни на пиксель (Windows проверил, что
зашитые константы равнялись токенам тёмной палитры), а «Стекло» и «Рассвет» перестают показывать
тёмный укус в углу карточки. Это и есть шаг F.4 живого прогона.

**Объём:** S.

#### L-11. Раскрытие карточки под курсором

**Windows.** Коммит `eb4d648`, правка ревью `1b2c3ce`. Карточка под курсором раскрывается на полные 78
и толкает карточки под ней на 48 вниз: анимация `ThicknessAnimation` по `Margin` из `0,0,0,-48` в
`0,0,0,0`, `BeginTime="0:0:0.15"`, `Duration="0:0:0.13"`, `CubicEase EaseOut`
(`EdgeStackWindow.xaml:388-411`). Складывание без задержки, той же длительностью. Высота списка при
этом **не меняется** (её пишет `ApplyListHeight` из `Captures.Count`), растёт только протяжённость
прокрутки на 48. Верх раскрытой карточки не двигается, двигаются карточки под ней.

Правка ревью важна для порта: `StopStoryboard` в `ExitActions` **убран**. Он снимал удержанное
значение раньше, чем складывающая анимация успевала взять точку старта, и карточка прыгала в −48, а
потом «складывалась» из −48 в −48. Складывающий сториборд вытесняет отложенный сам (`SnapshotAndReplace`).

Только курсор раскрывает карточку: выбор и фокус ничего не делают (L-1).

**Mac.** Аналог есть, но другой: `layoutCards` даёт раскрытой карточке `expandedMargin = 4` сверху и
снизу (`EdgeStackContentView.swift:589-594`), то есть раскрытия на полные 78 нет, есть сдвиг на 4, и
он срабатывает и по наведению, и по выбору, и **без задержки**.

**Что менять** в `layoutCards` (`EdgeStackContentView.swift:578-624`):

```swift
var cursor = StackMetrics.listPaddingTop
for card in cardViews {
    tops.append(cursor)
    cursor += card.isUnfolded ? StackMetrics.cardHeight : StackMetrics.cardStep
}
```

то есть раскрытая карточка не смещает саму себя (её `top` уже посчитан), а всё, что после неё,
уезжает ровно на `cardHeight − cardStep = cardOverlap = 48`. `documentHeight` вырастает на те же 48
автоматически (`:596-597`), `listHeight` не трогается вообще.

Задержку держит сам `EdgeStackContentView`, не карточка:

```swift
private var unfoldWork: DispatchWorkItem?

func thumbnailCard(_ card: ThumbnailCardView, hoverDidChange isHovered: Bool) {
    unfoldWork?.cancel(); unfoldWork = nil
    if isHovered {
        delegate?.edgeStackContentDidRequestTickSound(self)
        let work = DispatchWorkItem { [weak self, weak card] in
            card?.isUnfolded = true
            self?.layoutCards(animated: true, duration: 0.13)
        }
        unfoldWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    } else {
        card.isUnfolded = false
        layoutCards(animated: true, duration: 0.13)
    }
}
```

`isUnfolded` это новое свойство `ThumbnailCardView` рядом с `isHovered` (`:101`); `isHovered` остаётся
для рамки и крестика, которые по Windows реагируют **сразу**, без задержки.

`StackMetrics.expandInSeconds = 0.18` и `expandOutSeconds = 0.16` (`:91-92`) привести к Windows: 0.13
на обе стороны, задержка 0.15 отдельной константой `unfoldDelaySeconds`.

**Ловушки AppKit.**
- **Одна отложенная задача на всю ленту, а не по одной на карточку.** Быстрый проезд курсора по шести
  карточкам иначе положит шесть задач, и все шесть раскроются подряд. Отмена при любом изменении
  наведения, как в коде выше, воспроизводит Windows-овское «`BeginTime` не истёк, ничего не
  нарисовано».
- **`NSTrackingArea` и переезд карточек.** Сейчас область создаётся из `bounds`
  (`ThumbnailCardView.swift:295`) и пересоздаётся в `updateTrackingAreas()`. Когда карточки под
  курсором разъезжаются, AppKit шлёт `mouseExited`/`mouseEntered` тем, кто уехал из-под указателя.
  Раскрытая карточка сама не двигается (см. формулу выше), поэтому колебания «раскрылось, курсор ушёл,
  сложилось» невозможны, ровно как на Windows. Но области надо сделать самоподдерживающимися:
  добавить `.inVisibleRect` в опции (`:295`), иначе при анимации `animator().frame` область остаётся
  от старого фрейма до следующего `updateTrackingAreas()`.
- **Анимация и hit-test.** Во время `NSAnimationContext` фрейм у слоя presentation и у модели
  расходятся; hit-test идёт по модели, то есть по конечному фрейму. Это и нужно, но значит, что
  `mouseExited` может прийти раньше, чем карточка визуально доехала. Складывание без задержки это
  скрывает.
- **Два раскрытых одновременно не бывает:** карточки идут subview'ами в порядке данных
  (`EdgeStackContentView.swift:335`), последняя рисуется поверх, и hit-test отдаёт событие ровно одной.
- **Раскрытие последней карточки** растит прокрутку на 48 «в пустоту». Windows это принял и записал в
  «Что сказать Кате» (пункт 6); Mac принимает так же.

**Что автоматикой не проверить.** Задержка, плавность и быстрый проезд на 26 карточках. Проба
проверяет только «лента не выросла» (§4.2).

**Объём:** M.

#### L-12. Ручная высота ленты и двойной клик по ручке

**Windows.** Коммиты `7789ae6` и `ba16b28`. Новый аддитивный ключ настроек `StackHeightManual`
(`HotkeySettings.cs:54`, дефолт `false`) и чистая функция
`StripResizeGeometry.ListHeight(count, stored, manual)` (`Controls/StripResizeGeometry.cs:80-81`):
ручная высота это само сохранённое число, автоматическая это `ListHeightForCount`. `ApplyListHeight`
спрашивает флаг (`EdgeStackWindow.xaml.cs:880-881`); `OnCornerDragCompleted` пишет
`StackHeightManual = true` вместе с высотой (`:1008`); двойной клик по ручке возвращает `false`
(`OnCornerGripPress`, `:996-1002`, через `PreviewMouseLeftButtonDown` с `e.ClickCount == 2`, потому
что `Thumb` забирает мышь и `MouseDoubleClick` не доходит). Пол `MinimumListHeight = 180` и потолок
«рабочая область минус хром» остаются в `ClampListHeight` и к ручной высоте применяются тоже.

**Mac.** Ни флага, ни второй ветки. `persistStackGeometry()` (`EdgeStackWindowController.swift:315-323`)
пишет `stackWidth` и `stackHeight` **после любого перетаскивания**, в том числе после перетаскивания
только ширины.

**Что менять.**
1. Волна 0 (`core-settings`): ключ `stackHeightManual: Bool = false` в
   `SnapikCore/Settings/HotkeySettings.swift` рядом с `stackHeight` (`:68`), `CodingKeys` со строкой
   `"StackHeightManual"` рядом с `:331`, `decodeIfPresent ?? false` рядом с `:376`, `encode` рядом с
   `:419`. Плюс `StripResizeGeometry.listHeight(count:stored:manual:)`.
2. `applyListHeight()` из L-2 спрашивает `settings.stackHeightManual`.
3. `persistStackGeometry()` (`:315`) получает параметр `manual: Bool` и ставит
   `settings.stackHeightManual = true` **только** при `kind == .corner`. Вызов из `runResize` (`:312`)
   передаёт `kind == .corner`. Это тоньше, чем на Windows, где ширина и высота живут в разных
   обработчиках (`OnWidthDragCompleted` и `OnCornerDragCompleted`); на Mac цикл один, и различать надо
   явно. Заодно при перетаскивании только ширины больше не переписывается `stackHeight`.
4. Двойной клик по ручке. На Mac `cornerGrip` это `StackGripView` с
   `mouseDown(with:) → onMouseDown?(event)` (`EdgeStackContentView.swift:110`), и событие приходит
   **до** всякого захвата мыши, поэтому Windows-овский трюк с `Preview` не нужен: достаточно в
   `EdgeStackWindowController` в обработчике `edgeStackContent(_:didRequestResize:with:)` (`:497`)
   первым делом проверить `startEvent.clickCount == 2` и при `kind == .corner` сделать
   `mutateSettings { $0.stackHeightManual = false }` плюс `applyListHeight()` плюс `layoutWindow()`,
   вместо `runResize`.

**Ловушки AppKit.**
- `NSEvent.clickCount` у `mouseDown` считается системой по интервалу двойного клика, отдельной
  подписки не надо. Но событие первого клика приходит раньше, с `clickCount == 1`, и если по нему уже
  запущен `runResize`, второй клик попадёт внутрь цикла `nextEvent(…)`. Практически `runResize`
  выходит по `leftMouseUp` первого клика, так что второй `mouseDown` придёт нормально; но лента за это
  время успеет один раз записать геометрию. Поэтому `persistStackGeometry` должен выходить рано, если
  ни ширина, ни высота не изменились (сравнение с `startFrame`), иначе двойной клик сначала поставит
  `manual = true`, а потом снимет.
- Ручная высота на маленьком мониторе урезается `clampListHeight`, а флаг остаётся `true`. Так и
  задумано на Windows, поведение при переносе на второй монитор проверяется глазами (F.6).

**Объём:** M.

#### L-13. Контекстное меню карточки и копия одного снимка

**Windows.** Коммиты `af569e2` (волна 0), `f077f0d` (буква), `ec77082` (меню), `4de1e67` (кнопка
редактора).

- `SessionWorkspace.ExportSingleAsync(capture, label, ct)` (`src/Snapik.App/SessionWorkspace.cs:227-235`):
  пакет из одного снимка тем же экспортом, что и обычный, но сессия на диск не переписывается и
  ревизия не двигается.
- `EdgeStackWindow.CopySingleCaptureAsync(capture, label) -> Task<bool>`
  (`src/Snapik.App/EdgeStackWindow.Saving.cs:51-83`): очередь `_pasteIntentTransition`,
  `CancelReceiverEchoWatch()`, гейт публикации, экспорт, `SetPackageGuardedAsync` с одним путём, флаг
  `_ownedClipboardIsSingleCapture = true`, `SetPublished(Published(export) with { IsSingleCapture = true })`,
  звук `UiSoundService.Copied`, тост «Снимок B скопирован». Возвращает, дошло ли до буфера.
- `SaveSingleCaptureAsAsync(capture)` (`:86-121`): `SaveFileDialog` под `SuspendTopmost()`, запись
  `AnnotationCanvas.RenderAnnotated()`, то есть **без шапки и без поля под вынесенные бейджи**, в
  отличие от копии. Асимметрия сознательная, записана в «Что сказать Кате» (пункт 5).
- `OnCaptureListRightClick` (`EdgeStackWindow.xaml.cs:1984-1998`): меню строится в коде (иначе
  `UiLanguage.Apply` до него не дотянется), три пункта и разделитель, `PreviewMouseRightButtonUp` на
  списке (`EdgeStackWindow.xaml:228`). Тело удаления вынесено в `RemoveCapture(CaptureItem)` (`:703`).
- Буква. `FileExportService` и `PromptGenerator` получили необязательный `singleCaptureLabel`, который
  применяется **только** к сессии из одного снимка
  (`src/Snapik.Infrastructure/Exporting/FileExportService.cs:12, 47-49, 72`;
  `src/Snapik.Core/Exporting/PromptGenerator.cs:6-12, 26-28`). Скопировали карточку B, значит файл
  `01-B.png`, текст «Снимок B», подписи отметок `B1`, `B2` и тост про B. Обычный пакет не меняется.

**Mac.** Ничего этого нет: ни `exportSingle`, ни правой кнопки в ленте, ни одиночной публикации.
`NSMenu` в зоне ровно один, у кнопки «•••» (`EdgeStackWindowController.swift:522-546`).

**Что менять.**
1. Волна 0 (`core-settings`, §5.1): `singleCaptureLabel` в `FileExportService` и `PromptGenerator`
   (`macos/Sources/SnapikCore/Exporting/FileExportService.swift:21`,
   `Exporting/PromptGenerator.swift`).
2. `SessionWorkspace.exportSingle(capture:label:)` в
   `macos/Sources/SnapikMac/App/SessionWorkspace.swift` рядом с `prepareExport(renderer:includingSent:)`
   (`:156-165`): строит `SnapikSession` из одного снимка на текущей ревизии, зовёт
   `FileExportService(renderer:timeProvider:singleCaptureLabel:)`, обрезает старые экспорты тем же
   `trimExports`. **Ревизию не увеличивать.**
3. `AppCoordinator.copySingleCapture(_ capture: CaptureItem, label: String) async -> Bool` в
   `AppCoordinator+Package.swift` рядом с `copyPackage()` (`:126`): структура списывается с
   `saveAndCopyCommittedPackage` (`:19-75`) построчно, отличий три (источник экспорта,
   звук и тост вместо строки состояния, `prepared` не трогается).
4. Меню по правой кнопке на карточке. На AppKit идиома это переопределение `menu(for event:)` у
   `ThumbnailCardView`, а не `rightMouseDown`: оно же ловит Ctrl+клик и само показывает меню в нужной
   точке. Новый метод протокола `ThumbnailCardViewDelegate` (`ThumbnailCardView.swift:66-73`):
   `func thumbnailCardMenu(_ card: ThumbnailCardView) -> NSMenu?`, реализация в
   `EdgeStackContentView` (`:654`) пробрасывает наверх с id снимка, а меню собирает
   `EdgeStackWindowController` тем же `makeItem(_:language:action:)` (`:548`), что и «•••».
   Три пункта: «Копировать снимок», «Сохранить снимок…», разделитель, «Удалить».
5. «Удалить» зовёт уже существующий `AppCoordinator.removeCapture(_:)` (`AppCoordinator.swift:468`),
   выносить ничего не надо.
6. «Сохранить снимок…»: `NSSavePanel` под `withTopmostSuspended(_:)`
   (`EdgeStackWindowController.swift:375`), `ImageCodec.encode` от `AnnotationPainter.draw` по образцу
   уже существующего сохранения из редактора (`AutoSaveService`, `AppCoordinator+OverlayEditorDelegate.swift:127`).

**Ловушки AppKit.**
- **`menu(for:)` и ручной цикл перетаскивания.** Карточка ловит `mouseDown` и уходит в собственный
  event-tracking loop (`EdgeStackContentView.swift:677-706`). Правая кнопка в этот цикл не попадает:
  он ждёт `.leftMouseDragged` и `.leftMouseUp`. Конфликта нет, но `menu(for:)` надо ставить именно на
  карточку, а не на `listContainer`, иначе меню будет всплывать и по пустому месту между карточками.
- **Панель непробуждающаяся.** `EdgeStackPanel` имеет `canBecomeKey == false`
  (`EdgeStackWindowController.swift:11`). `NSMenu.popUp(positioning:at:in:)` из такого окна работает
  (это уже делает «•••», `:545`), но при возврате из `menu(for:)` AppKit показывает меню сам, и это
  надёжнее. Меню открывается на уровне `.popUpMenu`, то есть выше `.floating` ленты, так что
  `StackTopmost` ему не мешает.
- **Локализация.** Пункты строятся кодом через `MacUiText.text(_:language:)` (как `makeItem`,
  `:548-553`), не литералами: тот же урок, что на Windows про `UiLanguage.Apply(menu)`.
- **Буква карточки.** Метка берётся из `StackCaptureRow.label` (`EdgeStackContentView.swift:41`),
  которую раздаёт `SentCaptureRules.stripLabels` в `refresh()` (`EdgeStackWindowController.swift:143`).
  У отправленного снимка `label` может быть `nil` (на карточке вместо буквы галочка): в этом случае
  Windows отдаёт `capture.DisplayLabel`, и на Mac надо взять тот же источник, а не `row.label`.

**Объём:** L.

#### L-14. Одиночная копия живёт по своим правилам

Это не отдельный пункт ТЗ, а четыре правки ревью и приёмки (коммиты `1b2c3ce`, `2ed0b98`), без которых
L-13 сделан неверно. Все четыре переносятся.

**Windows.**
1. **Буфер не пересобирается до вставки.** Поле `_ownedClipboardIsSingleCapture`
   (`EdgeStackWindow.xaml.cs:55`); `RefreshOwnedClipboardCoreAsync` выходит рано, если оно поднято
   (`:1799`). Снимается: следующим захватом (`PrepareAsync`, `:1049`), явным «Копировать пакет»
   (`CopyPackageAsync`, `:1304`), очисткой ленты (`ReleaseOwnedClipboardCoreAsync`, `:1717`) и
   замеченной вставкой (`CompletePasteIntentAsync`, `:441`).
2. **Одиночная вставка не чистит ленту.** Признак поехал в сам пакет:
   `PublishedPackage.IsSingleCapture` (`src/Snapik.App/PublishedPackage.cs:19`) и правило
   `PublishedPackage.ClearsTheStrip(published, clearStackAfterPaste)` (`:37-38`).
   `MarkCapturesSentAsync` принимает теперь пакет, а не массив id, и спрашивает правило
   (`EdgeStackWindow.xaml.cs:1754-1761`). Тип живёт только в памяти, формат файлов не меняется.
3. **Очистка ленты и выход не затирают одиночную копию.** `ReleaseOwnedClipboardCoreAsync` пропускает
   отдачу буфера при поднятом флаге (`:1710`). Плата: сессия при этом удаляется, картинка и текст в
   буфере остаются, а пути в списке файлов никуда не ведут.
4. **Копия из редактора отвечает плашкой редактора**, потому что лента спрятана, пока редактор открыт:
   `CopySingleCaptureAsync` возвращает `bool`, редактор говорит результат своим `Hint`
   (`src/Snapik.App/OverlayEditorWindow.Save.cs:61-88`).

**Mac.** Типа `PublishedPackage` нет; его роль делят `PreparedExport`
(`macos/Sources/SnapikCore/Exporting/ExportContracts.swift:82`) и плоские поля координатора
`ownedClipboardReceipt` / `ownedClipboardPromptText` (`AppCoordinator.swift:51-52`).

**Что менять.**
1. Новое поле `var ownedClipboardIsSingleCapture = false` в `AppCoordinator.swift` рядом с `:51-52`.
   Поднимается в `copySingleCapture`, снимается там же, где снимаются receipt и prompt:
   `AppCoordinator.swift:315-316, 329-330, 548-549, 593-594`,
   `AppCoordinator+Package.swift:32-33, 87-88`, `AppCoordinator+PasteIntent.swift:207-208`,
   плюс явно после успешной публикации пакета (`AppCoordinator+Package.swift:50-51, 117-118`) и в
   `completePasteIntent` перед разбором результата (рядом с `AppCoordinator+PasteIntent.swift:121`).
2. `refreshOwnedClipboard()` (`AppCoordinator+Package.swift:77`) выходит рано при поднятом флаге,
   сразу после проверки receipt (`:82`).
3. `releaseOwnedClipboard()` (`AppCoordinator.swift:591-612`) при поднятом флаге не пишет в буфер, но
   `defer` с обнулением receipt оставляет как есть (`:592-595`).
4. Правило очистки ленты. `AppCoordinator+PasteIntent.swift:133` сейчас:
   `if settings.clearStackAfterPaste { await clearStack(clipboardGateHeld: true) }`. Становится
   `if clearsTheStrip(clearStackAfterPaste: settings.clearStackAfterPaste) { … }`, где функция это
   `clearStackAfterPaste && !ownedClipboardIsSingleCapture`. Windows вынес правило в сам пакет, чтобы
   покрыть его тремя тестами; на Mac пакета-типа нет, поэтому правило лучше вынести чистой функцией в
   Core рядом с `SentCaptureRules` (`macos/Sources/SnapikCore/Exporting/SentCaptureRules.swift`), тогда
   тест ложится в `SnapikCoreTests`, а координатор её зовёт.
   **Если `core-settings` откажется её брать**, функция остаётся статической в
   `macos/Sources/SnapikMac/App/AppCoordinator+Package.swift` и тестируется в `SnapikMacTests`.
5. Ответ редактору: `copySingleCapture` возвращает `Bool`, см. §5.2.

**Ловушка зон.** `AppCoordinator+PasteIntent.swift` по `CONTRACTS.md` (дополнение sync 2) принадлежит
`exec-transport`. В этот раунд транспортного аналитика нет, поэтому пункты 1 и 4 правит порция Stack;
это надо назвать явно в промпте исполнителя, чтобы файл не редактировали двое.

**Объём:** M.

---

## 2. Изменения формата в этой зоне

### 2.1 `settings.json`: ключ `StackHeightManual`

Абзац Windows: `tasks/verification.md:1044`. Ключ описан у `core-settings`; здесь фиксируется, **как
его читает лента**.

- Тип `Bool`, дефолт `false`, ключ JSON `"StackHeightManual"`, изменение аддитивное в обе стороны:
  файл без ключа читается как `false`, файл с ключом читается старым билдом (лишний ключ игнорируется).
  `SettingsMigration.currentVersion` остаётся 2, правил миграции не добавляется.
- **При `false`** `StackHeight` это потолок, и список стоит на высоте своего содержимого:
  `listHeightForCount(count, stored)` = `14 + (n − 1)·30 + 78 + 8`, при пустой ленте 92.
- **При `true`** то же число становится высотой списка, к которому по-прежнему применяются пол
  `minimumListHeight = 180` и потолок «рабочая область монитора минус хром окна» через
  `clampListHeight`. Пустая лента ручную высоту не показывает: список спрятан, стоит подсказка 92, и
  число возвращается с первым снимком.
- Флаг поднимает только завершённое перетаскивание **углового** грипа; двойной клик по нему возвращает
  `false`. Перетаскивание ширины флаг не трогает.

### 2.2 `prompt.md` и имя файла у одиночного пакета

Абзац Windows: `tasks/verification.md:1048`. Формат файлов не меняется, меняется правило раздачи
метки: `FileExportService` и `PromptGenerator` получают необязательный `singleCaptureLabel`, который
применяется **только** к сессии ровно из одного снимка. Копия карточки B даёт `01-B.png`, текст
«Снимок B», подписи отметок `B1`, `B2`. Обычный пакет не меняется ни на байт: параметр по умолчанию
`nil`, метки раздаются по позиции. Лента передаёт метку в `exportSingle(capture:label:)`, и она же
идёт в тост. Интерфейс `ExportService` не трогается.

### 2.3 Что в этой зоне НЕ меняется

- `session.json` дорожкой B не трогается вовсе. `exportSingle` строит `SnapikSession` в памяти и на
  диск её не пишет, **ревизию не увеличивает**. Имя каталога экспорта
  (`revision-NNNNNN-<guid>`) у одиночной копии повторяет номер последней сохранённой ревизии; это
  допустимо, потому что имя каталога нигде не разбирается (единственный читатель это
  `PreparedExport.imagePathsInOrder()`, а он берёт имена файлов из манифеста).
- `manifest.json`, формат ID горячих клавиш, `StackWidth`, `StackHeight` (тип и диапазон) без
  изменений.
- `PublishedPackage.IsSingleCapture` на Windows живёт только в памяти; на Mac эквивалентный флаг тоже
  только в памяти. В файлы не попадает ничего.

---

## 3. Расхождения Mac ↔ Windows, которые надо привести к Windows

Числа Windows по `src/Snapik.App/Controls/StripResizeGeometry.cs` и `EdgeStackWindow.xaml` на `f2cf62b`.

### 3.1 Геометрия списка и карточки

| Константа | Mac сейчас | Целевое | Файл Mac | Windows |
|---|---|---|---|---|
| `listPaddingLeft` | 8 | **4** | `Stack/StackMetrics.swift:50` | `StripResizeGeometry.cs:42` |
| `listPaddingRight` | 8 | **12** | `:52` | `:43` |
| `listPaddingBottom` | 52 | **8** | `:53` | `ListBottomPadding`, `:53` |
| `listPaddingTop` | 14 | 14 | `:51` | `ListTopPadding`, `:52` |
| `scrollBarWidth` | 4 | **3** (6 по наведению) | `:56` | `EdgeStackWindow.xaml:168, 180` |
| `cardLabelStripHeight` | 26 | **30** | `:74` | `EdgeStackWindow.xaml:297` |
| `cardShadowBlur` | 16 | **12** | `:78` | `EdgeStackWindow.xaml:277` |
| `expandedMargin` | 4 | **снять** | `:70` | сеттеры `Margin` сняты, `74fdbf6` |
| клип миниатюры | 11 | **10** | `ThumbnailCardView.swift:132` | `EdgeStackWindow.xaml:283` |
| `cardWidth(244)` | 168 (8 + 8) | 168 (4 + 12) | `StackMetrics.swift:108` | `StripResizeGeometry.cs:46-47` |
| `cardHeight` / `cardOverlap` / `cardStep` | 78 / 48 / 30 | те же | `:64, 65, 67` | `:56-58` |
| `emptyHintHeight` | 92 | 92 | `:60` | `EmptyListHeight`, `:50` |
| `shadowMargin` / панель / окно | 20 / 204 / 244 | те же | `:27, 100`, `StripResizeGeometry.swift:19` | `:18, 21, 23` |

Карточка после правки: `244 − 2·20 − 2·10 − 4 − 12 = 168`, как и было.
Содержимое списка после правки: `14 + (n − 1)·30 + 78 + 8`, то есть 2 → 130, 5 → 220, 12 → 430 с
потолком 372.

### 3.2 Цвета карточки

| Роль | Mac сейчас | Целевое | Файл |
|---|---|---|---|
| фон карточки | `palette.elevated` | без изменений | `StackMetrics.swift:128` |
| рамка обычная | `palette.surfaceLine` | **`palette.elevatedLine`** | `:125` |
| рамка по наведению | `#718096` константа | **`palette.textFaint`** | `:126` |
| рамка отправленного | `#333C49` константа | **`palette.surfaceLine`** | `:132` |
| рамка выбранного | `accent.focus` | **снять вместе с триггером** | `:127` |
| плашка подписи | сплошной `#E6171A20` | **градиент `#8C141E1E` / `#47141E1E` (0.6) / `#00141E1E`** | `:130` |
| бейдж отправленного | `#4A5563` | без изменений | `:131` |
| чипы «экран» / «импорт» | `#1FFFFFFF` | без изменений | `ThumbnailCardView.swift:26` |
| иконка и счётчик заметок | `#AEB8C7` / `#DCE3ED` | **белые, с общей тенью** | `ThumbnailCardView.swift:161, 166` |

### 3.3 Высота списка

Mac считает высоту списка **только** из сохранённого числа (`EdgeStackWindowController.swift:235-238`),
Windows считает её из содержимого с потолком. Это главное поведенческое расхождение раунда: на Mac
лента с двумя снимками занимает 372 точки, из которых 242 пустые. Лечится L-2 и L-12.

`StackMetrics.listContentHeight(count:)` (`:113-116`) объявлена и не вызывается ниоткуда: формула
правильная, нижний паддинг устаревший. После L-2 её заменяет Core-функция.

### 3.4 Поведение при показе

| Что | Mac сейчас | Целевое |
|---|---|---|
| позиция окна на показе | `positionAtEdge()` переписывает `x`, `y`, `width` каждый раз (`EdgeStackWindowController.swift:79, 233-246`) | первая постановка отдельно, дальше только кламп прямоугольника (L-7) |
| капсула | встаёт у края монитора (`:227`) | встаёт на правый верхний угол ленты (L-6) |
| разворот из капсулы | к `work.maxX` (`:351`) | в запомненный прямоугольник через `restoreRect` (L-6) |
| прокрутка при добавлении снимка | позиция «от верха» сохраняется (`EdgeStackContentView.swift:599-623`) | лента уезжает к последнему снимку (L-8) |
| запись `stackHeight` | после любого перетаскивания (`:315-323`) | только после перетаскивания углом, вместе с `stackHeightManual` (L-12) |

### 3.5 Расхождение старше раунда, которое раунд делает видимым

`workArea()` (`EdgeStackWindowController.swift:212-213`) всегда отдаёт `NSScreen.screens.first`, тогда
как Windows берёт монитор, на котором стоит окно. До этого раунда следствие было терпимым (лента и так
прыгала к краю первого экрана на каждом показе). После L-6 и L-7 лента остаётся там, куда её
оттащили, и кламп по рамке чужого монитора начнёт её дёргать. Рекомендую в том же куске заменить на
`window?.screen?.visibleFrame`. Если решат не менять, записать строкой в `verification.md` и в F.6.

---

## 4. Тесты и пробы smoke

### 4.1 Модульные тесты

Windows добавил в этом диапазоне три файла и одно дополнение в зоне ленты
(`git diff --stat d84fbb0..f2cf62b -- tests`).

| Windows | Что проверяет | Swift-набор |
|---|---|---|
| `tests/Snapik.App.Imaging.Tests/StripResizeGeometryTests.cs:161-170` (`The_list_is_as_tall_as_its_cards_up_to_the_ceiling`) | восемь случаев `ListHeightForCount`: `(0,372)→92`, `(1,372)→100`, `(2,372)→130`, `(5,372)→220`, `(12,372)→372`, `(12,500)→430`, `(5,130)→130`, `(12,NaN)→372` | дописать в `macos/Tests/SnapikCoreTests/Geometry/StripResizeGeometryTests.swift` (12 тестов, 170+ строк) |
| `…:172-186` (`A_height_dragged_by_hand_is_the_height_of_the_list`) | пять случаев `ListHeight`: `(3,310,true)→310`, `(3,310,false)→160`, `(15,310,true)→310`, `(0,310,true)→310`, `(0,310,false)→92` | там же |
| `…:188-190` (`The_capsule_keeps_the_right_edge_of_the_strip_it_came_from`) | `CapsuleLeft(1600, 244, 180) == 1664` | там же |
| `…:192-203` (`A_strip_dragged_away_from_the_edge_comes_back_where_it_was_left`) | прямоугольник внутри области возвращается как есть; ушедший вправо прижимается к `work.Right − Width`; шире области не уезжает левее `work.Left` | там же, с подписью на `Double` из §1.1 L-6 |
| `tests/Snapik.App.Imaging.Tests/PublishedPackageTests.cs:31-44` | три случая `ClearsTheStrip`: настройка включена, выключена, одиночная копия | новый `macos/Tests/SnapikCoreTests/SentCaptureRulesTests.swift` либо `SnapikMacTests/App/` в зависимости от того, где сядет правило (§1.2 L-14 пункт 4) |
| `tests/Snapik.Windows.Tests/ClipboardPackageFormatsTests.cs` (новый, 70 строк) | пакет из одного снимка несёт `PNG`, `DIB`, `Bitmap`, `FileDrop`, `UnicodeText` | **переносится как проверка типов пастборда**: `macos/Tests/SnapikMacTests/Transport/TransportMacTests.swift`, аналог `setPackageGuarded` с одним путём кладёт `.png`, `.tiff`, `.fileURL` и `.string`. Форматы уже правильные (§0.1), тест закрепляет их, чтобы не уехали |
| `tests/Snapik.Core.Tests/PersistenceAndExportTests.cs` (+70) | экспорт из одного снимка с меткой B даёт `01-B.png` и текст «Снимок B» | дописать в `macos/Tests/SnapikCoreTests/PersistenceAndExportTests.swift` (зона `core-settings`, но проверка нужна ленте) |

**Новых тестовых целей не заводить.** Отдельного набора `SnapikMacTests/Stack*` сейчас нет; чистая
геометрия ложится в `SnapikCoreTests/Geometry`, а всё, что требует окна, идёт в smoke (см. ниже).

### 4.2 Пробы smoke

Windows держит пробы ленты в `EdgeStackWindow.RunStripGrowthProbe()`
(`src/Snapik.App/EdgeStackWindow.xaml.cs:2129-2205`) и хелперах `ProbeStrip(count, checks)` (`:2207-2233`)
и `TheLastCardIsWhole(window, viewer)` (`:2196-2204`); регистрация одной строкой в
`SmokeTestRunner.cs:653`. Три случая:

1. **Пять карточек.** `CaptureList.Height == 220`, `ScrollableHeight == 0`, низ последней карточки не
   ниже низа презентера.
2. **Двенадцать карточек.** `CaptureList.Height == 372`, `ScrollableHeight > 0`, полоса видима и
   `ActualWidth <= 6`, после `ScrollStripToEndCore()` `|VerticalOffset − ScrollableHeight| < 0.5`, низ
   последней карточки цел.
3. **Пять карточек, третья раскрыта руками** (`ThumbCard.Margin = 0`, анимация не проигрывается):
   высота списка **по-прежнему 220**, `ScrollableHeight ≈ 48`, верх третьей карточки не сдвинулся.

Отдельно `VerifyTz007SingleExport` (`SmokeTestRunner.cs:232-242`): `ExportSingleAsync(capture, "B")`
даёт `01-B.png` и текст, начинающийся со «Снимок B». Проба `VerifyALayeredWindowMinimisesAsync`
(`:311`) не переносится (§0.3 пункт 5). Пустой крючок `VerifyTz007Strip` убран приёмкой.

**Что переносить в `macos/Sources/SnapikMac/App/SmokeTestRunner+Stack.swift`** (сейчас 251 строка,
`stackProbes(options:)` на `:14`, регистрация `SmokeTestRunner.swift:121-122`), новыми `checks.append`
в том же стиле, что и существующие:

| Проба | Что утверждает | Опора на Mac |
|---|---|---|
| «пять карточек занимают 220 и не прокручиваются» | `contentContainer.listHeight == 220`, `documentHeight <= visibleHeight` | `EdgeStackContentView.listHeight`, `scrollView.documentView!.frame.height` |
| «двенадцать карточек упираются в потолок 372 и прокручиваются» | `listHeight == 372`, `documentHeight > visibleHeight` | там же |
| «лента показывает последний снимок» | после `scrollToNewest()` и раскладки `scrollView.contentView.bounds.origin.y == 0` | §1.2 L-8, ноль это низ у неперевёрнутого контейнера |
| «низ последней карточки цел» | `cardViews.last!.frame.minY >= listPaddingBottom − 0.5` | `layoutCards` |
| «раскрытая карточка не растит ленту» | поставить `cardViews[2].isUnfolded = true`, позвать `layoutCards(animated: false)`: `listHeight` по-прежнему 220, `documentHeight` вырос ровно на `cardOverlap`, `cardViews[2].frame` не изменился | §1.2 L-11 |
| «высота, вытянутая рукой, остаётся» | `StripResizeGeometry.listHeight(count: 3, stored: 310, manual: true) == 310` и та же лента с `stackHeightManual = true` даёт окно `chrome + 310` | §1.2 L-12; чистая часть покрыта юнит-тестом, оконная нужна для `applyListHeight` |
| «одиночный экспорт носит букву карточки» | `exportSingle(capture, label: "B")` даёт `01-B.png` и текст со «Снимок B» | §1.2 L-13, аналог `VerifyTz007SingleExport` |

**Ловушка, которую Windows описал и которая на Mac тоже есть.** Список, перезаполненный на месте
(5 → 12), может сохранить прежнюю протяжённость: на Windows контейнеры не пересобирались, на Mac
`reload(rows:)` пересоздаёт карточки (`EdgeStackContentView.swift:321-337`), но `documentHeight`
считается только в `layoutCards`, который вызывается из `layout()`. Каждый случай пробы поднимать на
своём `EdgeStackContentView` и звать `layoutSubtreeIfNeeded()`, как это уже делает существующая
проба капсулы (`SmokeTestRunner+Stack.swift:109-135`).

Правило `ShutdownMode.OnExplicitShutdown` из Windows-проб на Mac не нужно: пробы ленты уже строят
окно, не показывая его (`stackProbes` на `:14`).

---

## 5. Границы с волной 0 и с редактором

### 5.1 Что мне нужно от контракта волны 0 (`core-settings`)

| Символ | Где | Зачем ленте |
|---|---|---|
| `HotkeySettings.stackHeightManual: Bool = false`, ключ `"StackHeightManual"` | `SnapikCore/Settings/HotkeySettings.swift` рядом с `stackHeight` (`:68`, `:331`, `:376`, `:419`) | L-12, §2.1 |
| `StripResizeGeometry.emptyListHeight = 92`, `listTopPadding = 14`, `listBottomPadding = 8`, `cardHeight = 78`, `cardOverlap = 48`, `cardPitch = 30` | `SnapikCore/Geometry/StripResizeGeometry.swift` | L-2, L-3, L-11; `StackMetrics` становится их псевдонимом, дублировать числа нельзя |
| `StripResizeGeometry.listHeightForCount(count: Int, cap: Double) -> Double` | там же | L-2 |
| `StripResizeGeometry.listHeight(count: Int, stored: Double, manual: Bool) -> Double` | там же | L-2, L-12 |
| `StripResizeGeometry.capsuleLeft(stripLeft: Double, stripWidth: Double, capsuleWidth: Double) -> Double` | там же | L-6 |
| `StripResizeGeometry.restoreRect(...)` **на `Double`, не на `CGRect`** | там же | L-6, L-7; Core компилируется на Windows и `CGRect` не знает |
| `FileExportService(renderer:timeProvider:singleCaptureLabel:)` | `SnapikCore/Exporting/FileExportService.swift:21` | L-13, §2.2 |
| `PromptGenerator(singleCaptureLabel:)` | `SnapikCore/Exporting/PromptGenerator.swift` | L-13, §2.2 |
| правило «одиночная вставка не чистит ленту» чистой функцией | `SnapikCore/Exporting/SentCaptureRules.swift` | L-14 пункт 4; если Core её не возьмёт, остаётся в зоне Stack |

Четыре пары `UiLanguage` раунда (`Копировать снимок` / `Copy capture`, `Сохранить снимок…` /
`Save capture…`, `Снимок {0} скопирован` / `Capture {0} copied`, `Не удалось скопировать снимок` /
`Could not copy the capture`) тоже волна 0, `src/Snapik.App/UiLanguage.cs:98-99`. Новых строк лента
больше не просит: «Свернуть» уже есть (`UiLanguage.cs:147`), «Удалить», «Сохранить на компьютер»,
«Изображения», «Все поддерживаемые», «Выберите PNG или JPEG.» переиспользуются как есть.

### 5.2 Что лента отдаёт редактору

Один метод и один тип возврата.

```swift
// AppCoordinator+Package.swift, зона Stack. Зовёт редактор и контекстное меню карточки.
@discardableResult
func copySingleCapture(_ capture: CaptureItem, label: String) async -> Bool
```

Контракт, дословно с Windows (`src/Snapik.App/EdgeStackWindow.Saving.cs:51-83`):

1. Кладёт в буфер пакет **из одного снимка**: тот же экспорт и те же форматы, что у обычного пакета
   (`.png`, `.tiff`, `.fileURL`, `.string`).
2. `label` это буква карточки ленты, и она попадает в имя файла, в `prompt.md`, в подписи отметок и в
   тост. Редактор передаёт `capture.displayLabel`, а не индекс.
3. Опубликованным пакетом становится он один, поэтому замеченная вставка помечает ✓ только его и
   ленту не чистит.
4. `prepared` не трогается: кнопка вставки по-прежнему отправляет всё, что ждёт.
5. **Возвращает, дошло ли до буфера.** Лента спрятана, пока редактор открыт, поэтому её тост и строка
   состояния там никому не видны, и редактор говорит результат своей плашкой: при `true` строкой
   «Снимок {label} скопирован», при `false` строкой «Не удалось скопировать снимок».
6. Гард со своей стороны держит редактор (Windows берёт тот же `_busyCrop`, что и сохранение:
   повторный Ctrl+Shift+C во время экспорта не ставит вторую копию в очередь,
   `src/Snapik.App/OverlayEditorWindow.Save.cs:61-88`).

Всё остальное в редакторе принадлежит аналитику `editor`: кнопка в панели, сочетание Cmd+Shift+C,
строка в шпаргалке клавиш, `commitTextEdit()` перед копией.

### 5.3 Пересечения по файлам

| Файл Mac | Кто ещё в него заходит | Как разводим |
|---|---|---|
| `SnapikCore/Geometry/StripResizeGeometry.swift` | `core-settings` (волна 0) | всё пишет волна 0, порция Stack только читает |
| `SnapikCore/Settings/HotkeySettings.swift` | `core-settings` | то же |
| `App/AppCoordinator.swift` | входы показа ленты и флаг одиночной копии — Stack; настройки и мастер — `core-settings` | отдать `AppCoordinator.swift` **только** порции Stack, `core-settings` отдаёт своё колбэками (так же, как в дельте №4) |
| `App/AppCoordinator+Package.swift` | публикация пакета и импорты — Stack | целиком Stack |
| `App/AppCoordinator+PasteIntent.swift` | формально зона `exec-transport` (`CONTRACTS.md`, sync 2) | транспортного аналитика в раунде нет, правит Stack; назвать в промпте исполнителя |
| `App/SmokeTestRunner.swift` | все три порции | только сведение, по одной строке регистрации на пробу |
| `Editor/**` | `editor` | порция Stack туда не заходит вовсе |

---

## 6. Объём, порядок и что глазам

### 6.1 Порядок внутри порции Stack

Порядок жёсткий: каждый следующий шаг опирается на предыдущий.

1. **L-3 и L-5, числа `StackMetrics`.** Пять констант, ничего не ломают, дают правильную арифметику
   всему, что дальше. **S.**
2. **L-2, высота списка по содержимому.** Требует Core-функций волны 0. После неё лента сама по себе
   становится похожа на Windows, и все дальнейшие пробы можно писать на настоящих числах. **M.**
3. **L-12, ручная высота.** Ложится сразу на `applyListHeight` из шага 2. **M.**
4. **L-7, разделение постановки ленты**, и **L-6, капсула**. Оба используют `restoreRect`, делать одним
   куском. **M + M.**
5. **L-1, снять раскрытие по выбору**, и **L-11, раскрытие по наведению с задержкой.** Обе правят
   `layoutCards`, делать одним куском. **S + M.**
6. **L-8, прокрутка к последнему снимку.** После L-11, потому что живёт в том же `layoutCards`. **M.**
7. **L-4, L-9, L-10, внешний вид карточки.** Независимы от всего выше, можно параллельно, но проще в
   конце: они меняют только `ThumbnailCardView` и `StackMetrics`. **S + M + S.**
8. **L-13, контекстное меню и копия одного снимка.** Самый крупный кусок, трогает `AppCoordinator+Package`
   и `SessionWorkspace`, от геометрии не зависит; можно вести параллельно с шагами 1–7 в той же
   порции, но сливать последним. **L.**
9. **L-14, правила одиночной копии.** Сразу после L-13, иначе L-13 сделан неверно. **M.**
10. **Тесты и пробы** одним куском в конце (§4), одно ревью на всю порцию.

Итого по зоне: три **L**-величины нет, восемь **M**, шесть **S**, один **L** (L-13).

### 6.2 Что обязательно глазами на живом Mac

Автоматикой не закрывается, взято из разделов «Что осталось глазам» обоих раундов
(`tasks/verification.md:1050-1057` и раздел ТЗ №5).

1. **Раскрытие карточки (F.5).** Задержка 150 мс, плавность на 26 карточках с тенями, складывание без
   задержки, быстрый проезд курсором мимо шести карточек не должен дёргать ни одну. Отдельно:
   раскрытие последней карточки растит прокрутку «в пустоту», это ожидаемо.
2. **Цвета карточки (F.4).** Шесть снимков на «Стекле» и на «Рассвете»: плашка прозрачная, снимок
   читается под буквой, буква читается на светлом снимке, тёмной кромки в углу нет.
3. **Угол ленты (F.6).** Три снимка, потянуть угол вниз на 150, отпустить: осталась. Захват: не
   изменилась. Двойной клик по ручке: села по содержимому. Перенос вытянутой ленты на второй монитор.
4. **Капсула у границы двух мониторов.** Встаёт на правый верхний угол ленты, разворот возвращает
   ленту в те же координаты, монитор не меняется. То же для ленты, оттащенной от края (это и есть
   проверка `workArea()` из §3.5).
5. **Прокрутка (F.3).** Двенадцать снимков, последний внизу; прокрутить вверх, сделать снимок: лента
   снова внизу. Отдельно посмотреть возврат из редактора (открытый пункт §1.2 L-8).
6. **Правая кнопка (F.7).** Меню по карточке не ломает перетаскивание порядка и не мешает
   перетаскиванию окна за панель; на 125 % и на втором мониторе меню встаёт в нужной точке.
7. **Копия одного снимка (F.7, F.8).** Настоящий Cmd+V в Claude, ChatGPT и Telegram: один PNG с
   отметками и полем, текст комментариев этого снимка, ✓ только на скопированной карточке, следующий
   захват даёт пакет из неотправленных. Отдельным шагом та же вставка при включённой «Очистить ленту
   после вставки»: лента обязана остаться на месте.
8. **Полоса прокрутки.** Три точки в покое, шесть по наведению, второй тусклой полосы нет, тень
   карточки в дорожку не заходит.
9. **Скруглённые углы миниатюры** после смены радиуса клипа на 10: картинка не наползает на штрих
   рамки и не оставляет светлой щели.
