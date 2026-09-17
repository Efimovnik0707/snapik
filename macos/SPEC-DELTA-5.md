# Дельта №5 (зонтичная спека и план): Windows `d84fbb0..f2cf62b` (1.6.0 + 1.7.0) → macOS

## 0. Статус и входы

**База.** `mac-sync-base-4` = `d84fbb0` (Windows 1.5.0). **Цель раунда:** `mac-sync-base-5` = `f2cf62b`
(Windows 1.7.0). Диапазон: 76 коммитов, два раунда ТЗ подряд (`tasks/tz-006-*` = 1.6.0,
`tasks/tz-007-*` = 1.7.0), по `src` + `tests` 52 файла, +4571 / −1199. Релиз по итогу: `macos-v1.7.0`.

**Этот файл не заменяет части дельты, а связывает их.** Числа, сигнатуры, `файл:строка` и ловушки живут
в трёх частях, ссылки на них в тексте вида `C §1.3`, `S §1.2 L-7`, `E §1.2 E-5`:

| Ссылка | Файл | Строк | Зона |
|---|---|---|---|
| `C` | `macos/SPEC-DELTA-5-core-settings.md` | 1236 | Core, настройки, мастер, звук, App/Smoke |
| `S` | `macos/SPEC-DELTA-5-stack.md` | 1116 | лента, транспорт пакета, `AppCoordinator` |
| `E` | `macos/SPEC-DELTA-5-editor.md` | 898 | редактор, холст, рендер экспорта |

Правила порта: `macos/SYNC.md`. Владение файлами: `macos/CONTRACTS.md` (отклонения этого раунда: §2.7,
§2.8, §5.1). Образец процесса: `macos/SPEC-DELTA-4.md` §7, `macos/WAVE0-NOTES-4.md`.

**Условия проверки.** Swift локально не собирается, macOS-раннера на машине нет: единственная проверка
это CI (`.github/workflows/macos-build.yml`, около 5 минут: сборка SwiftPM и Xcode, тесты, `--smoke-test`,
DMG). Раннер платный, квота в прошлый раз выбиралась на 90 %, поэтому **один пуш на всю пачку**, а не
прогон после каждого коммита. Компилируемость внутри волн проверить нечем, вместо компилятора
самопроверка по чек-листу (§4, §5.6).

**Схема раунда.** Волна 0 (Core и контракты, один исполнитель на `master`, без CI между коммитами) →
три порции параллельно в worktree и ветках `mac-sync-5-{stack,editor,settings}` от коммита волны 0 →
сведение одним исполнителем → один пуш на CI → цикл «лог ошибок, фикс-коммит, пуш» не более трёх раз →
тег, журнал, релиз (§7).

**Объём:** **S** ≤ 60 строк Swift, **M** 60–250, **L** > 250.

---

## 1. Резюме по модулям Mac

### 1.1 Core (`Sources/SnapikCore`)

Два аддитивных ключа настроек (`StackHeightManual` булевым, `toolAppearance` словарём, `C §1.1`), новый
`ToolAppearanceEntry` как форма записи в файле (`C §4.2`). `SettingsMigration` не трогается вовсе: версия
остаётся 2, оба ключа мигрируют по отсутствию, а не по версии (`C §1.2`). Геометрия списка переезжает в
Core целиком: шесть констант и четыре чистые функции `listHeightForCount`, `listHeight`, `capsuleLeft`,
`restoreRect` (`C §1.10`, `C §4.4`, `S §5.1`). Квадратичная кривая громкости `SoundVolumeCurve` (`C §1.4`).
Одиночный пакет: `singleCaptureLabel` у `PromptGenerator` и `FileExportService` (`C §1.5`), правило
`SentCaptureRules.clearsTheStrip` (§2.2). Таблица `UiLanguage`: +9 пар, −3 сразу, −3 в сведении
(`C §1.3`). Модель `AnnotationItem` не меняется ни на поле (`C §2.6`).

### 1.2 Stack (`Sources/SnapikMac/Stack`, `App/AppCoordinator*`)

Четырнадцать позиций (`S §0.2`), из них две крупные. Высота списка перестаёт быть сохранённым числом и
считается по содержимому с потолком, а сохранённое число становится потолком, пока пользователь не тянул
угол (`S §1.1 L-2`, `S §1.2 L-12`). Постановка окна делится надвое: первая постановка у края и все
следующие показы, которые только клампят прямоугольник, поэтому оттащенная лента остаётся там, куда её
оттащили, а капсула встаёт на угол ленты, а не на угол монитора (`S §1.1 L-6`, `L-7`). Дальше вид карточки
(поля `4,14,12,8`, полоса 3 / 6, клип 10, тень 12, градиентная плашка 30, три рамки из темы, раскрытие под
курсором с задержкой 150 мс), прокрутка к последнему снимку и самый крупный кусок: контекстное меню
карточки, копия одного снимка и четыре правила её жизни (`S §1.2 L-13`, `L-14`).

### 1.3 Editor + Imaging (`Sources/SnapikMac/Editor`, `Imaging`)

Тридцать четыре позиции (`E §0.2`), самая тяжёлая порция раунда. Переключатель масштаба уходит целиком,
снимок открывается 1:1 через `placeCapture`, вход в масштаб только Cmd+колесо (`E §1.2 E-1`). Панель
разметки перекладывается в три блока и две строки с укладкой через `ToolbarLayout.measure` и
перетаскиванием (`E-2`). Блок свойств становится инспектором из двух капсул поверх словаря
«инструмент → настройки», и настройки каждого инструмента переживают перезапуск (`E-3`, `E-4`). Нажатие
получает одно правило на все инструменты (`E-5`), комментарий становится самостоятельным объектом (`E-6`),
экспорт получает поле `#2A3140` под вынесенные бейджи (`E-7`), выноска идёт от обода точки и точка
появляется в экспорте (`E-9`, `E-10`), у размытия нет блока свойств (`E-11`), появляются кнопка
«Копировать» и Shift+Cmd+C (`E-12`).

### 1.4 Settings + Onboarding (`Sources/SnapikMac/Settings`, `Onboarding`)

Четыре позиции и все мелкие (`C §0.2`). Окно настроек 620 × 620 вместо 620 × 520, и смоук вместо сверки
числа с числом начинает мерить корень каждой вкладки (`C §1.6 S5-1`). У ползунка громкости появляется
число справа и тик по таймеру 150 мс на временных настройках (`S5-2`). В ряду палитр четвёртый сегмент
«Неон» и расширенный белый список сеттера, без которого выбранный в редакторе неон стирается любым
«Сохранить» (`S5-3`). Конец ряда галереи тем становится меткой, а не выключенностью кнопки, плюс кламп
`firstCard` при смене ширины (`S5-4`, §2.14). Мастер первого запуска не меняется вовсе: `OnboardingVersion`
остаётся 3, шага закрепа на панели задач на macOS не существует (`C §1.7`).

### 1.5 App + Smoke (`Sources/SnapikMac/App`)

Две новые пробы: одиночный экспорт носит букву карточки (`A5-2`) и вкладки настроек влезают в окно вместе
с числом громкости и порядком ряда палитр (`A5-1`, `C §1.9`). Правки существующих: набор «нестандартных»
настроек round-trip получает `stackHeightManual` и непустой `toolAppearance`, названия палитр становятся
четвёркой, языковая таблица смоука теряет «По ширине/По высоте» и получает «Копировать снимок». В ленте
семь новых утверждений (`S §4.2`), в редакторе пять новых проб и шесть переписанных (`E §4.2`). Пустых
крючков в реестре не заводить: порции не спорят за место, каждая пишет в свой файл расширения, реестр
`SmokeTestRunner.swift` трогает только сведение.

---

## 2. Решения по спорным местам

Ниже решено всё, что части оставили открытым, и всё, в чём они друг другу противоречат. Исполнителям
читать этот раздел раньше своей части: он её переопределяет.

**2.1. Ротации `exports/revision-*` на Mac нет, и `trimExports` не существует.** `S §1.2 L-13` просит
`exportSingle` «обрезать старые экспорты тем же `trimExports`»; такого метода в дереве нет
(`grep -rn "trimExports" Sources/` пусто), `SessionWorkspace.swift:100-123` умеет только сносить сессию
целиком. Прав `C §1.5`. **Решение:** `exportSingle` ничего не обрезает, строку `TrimExports` не
переносить, в коде оставить комментарий. Каждое «Копировать снимок» создаёт ещё один каталог
`revision-*`, который живёт до очистки ленты или до следующего старта. Это долг, записать в §7
«не перенесено», отдельной задачей не в эту дельту.

**2.2. Правило «одиночная вставка не чистит ленту» живёт в `SentCaptureRules`, не в `ExportContracts`.**
`C §1.5` предлагал `PreparedExport.clearsTheStrip`, `S §1.2 L-14` предлагал `SentCaptureRules`.
**Решение:** `SentCaptureRules` (`Sources/SnapikCore/Exporting/SentCaptureRules.swift`), потому что это
файл правил «что лента делает с отправленными снимками», а `ExportContracts` описывает форму экспорта.
Сигнатура одна на дерево:

```swift
public static func clearsTheStrip(isSingleCapture: Bool, clearStackAfterPaste: Bool) -> Bool
```

Тест ложится в `Tests/SnapikCoreTests/SentCaptureRulesTests.swift`.

**2.3. Признак одиночной публикации это одно поле, а не два.** Windows держит два разных
(`_ownedClipboardIsSingleCapture` у буфера и `PublishedPackage.IsSingleCapture` у пакета), `C §1.5` назвал
его `publishedIsSingleCapture`, `S §1.2 L-14` назвал `ownedClipboardIsSingleCapture`. **Решение:** на Mac
`PublishedPackage` нет, опубликованный пакет в каждый момент один, и оба Windows-поля живут один и тот же
срок. Заводится **одно** поле `var publishedIsSingleCapture = false` в `App/AppCoordinator.swift` рядом с
`:56`, только в памяти, в файлы не попадает. Его читают все четыре правила (§2.4). Второго имени в дереве
быть не должно, проверяется грепом при сведении.

**2.4. Четыре правила одиночной копии без `PublishedPackage` и без ротации.** Реализуются полем §2.3 и
чистой функцией §2.2:
1. буфер не пересобирается до вставки: ранний выход в `refreshOwnedClipboard()`
   (`AppCoordinator+Package.swift:77`, сразу после проверки receipt);
2. одиночная вставка не чистит ленту: `AppCoordinator+PasteIntent.swift:133` спрашивает
   `SentCaptureRules.clearsTheStrip(isSingleCapture:clearStackAfterPaste:)`;
3. очистка ленты и выход не затирают одиночную копию: `releaseOwnedClipboard()`
   (`AppCoordinator.swift:591-612`) при поднятом флаге в буфер не пишет, `defer` с обнулением receipt
   остаётся как есть;
4. копия из редактора отвечает плашкой редактора: редактор говорит результат своим `hintView`
   (`E §1.3 E-12`).

**Как редактор дотягивается до ленты (иначе на CI `does not conform to protocol`).** Редактор не видит
`AppCoordinator` вовсе, он ходит только через `OverlayEditorDelegate`
(`Editor/OverlayEditorController.swift:6-14`, `delegate` `:32`). Поэтому подписей две, и обе записаны
здесь дословно, чтобы порции написали одно и то же:

```swift
// Editor, задача 16: требование протокола рядом с `overlayEditor(_:didSaveFileAt:)`
protocol OverlayEditorDelegate: AnyObject {
    func overlayEditorCopiesSingleCapture(_ editor: OverlayEditorController) async -> Bool
}

// Stack, задача 10: реализация-переходник в `App/AppCoordinator+OverlayEditorDelegate.swift`
func overlayEditorCopiesSingleCapture(_ editor: OverlayEditorController) async -> Bool
// тело: координатор берёт снимок, с которым он открыл редактор, и его `displayLabel` (а не букву
// ленты: у отправленного снимка она `nil`), зовёт `copySingleCapture` и возвращает результат.
// Редактор буквы ленты не знает и знать не должен.

// Stack, задача 10: сам метод в `AppCoordinator+Package.swift`
@discardableResult
func copySingleCapture(_ capture: CaptureItem, label: String) async -> Bool
```

Реализация протокола живёт в файле порции Stack (`§5.1`), требование в файле порции Editor: без пары
правок дерево не соберётся, поэтому обе порции обязаны сделать свою половину в один раунд.

Снятие признака: следующим захватом, явным «Копировать пакет», очисткой ленты и замеченной вставкой
(точки перечислены в `S §1.2 L-14`).

**2.5. `restoreRect` на `Double`, а не на `CGRect`, и возвращает только точку.** `C §4.4` оставлял выбор
порции Stack, `S §1.1 L-6` требовал `Double`. **Решение:** `Double`, Core остаётся без `CoreGraphics`
(`Geometry/ResizeGeometry.swift:2` знает только `Foundation`, все существующие функции берут и отдают
`Double`). Ширина и высота в правиле не меняются никогда, поэтому возврат это точка:

```swift
public static func restoreRect(x: Double, y: Double, width: Double, height: Double,
                               workX: Double, workY: Double, workWidth: Double,
                               workHeight: Double) -> (x: Double, y: Double)
```

Порядок гардов переносить дословно с Windows (`!work.IsEmpty && work.Width > 0 && work.Height > 0 &&
!work.Contains(stored)`), перевод `NSRect` в восемь чисел делает вызывающий в зоне Stack. Имя оставлено
Windows-овским ради грепа, хотя возвращает оно точку.

**2.6. Многомониторный `workArea()` входит в перенос в минимальном виде.** Сейчас
`EdgeStackWindowController.workArea()` (`:212-213`) всегда отдаёт `NSScreen.screens.first`, и это
сознательное решение прошлого раунда (Finding 14: `NSScreen.main` ходит за фокусом и бывает `nil`).
После L-6 и L-7 лента остаётся там, куда её оттащили, и кламп рамкой чужого монитора начнёт её дёргать.
**Решение:** завести `func workArea(for window: NSWindow?) -> NSRect`, которая берёт
`window?.screen?.visibleFrame` и падает на нынешнее тело; звать её **только** из `ensureStripPlaced()`,
из ветки капсулы `positionAtEdge()` и из `expandFromCapsule()`. Прежняя `workArea()` остаётся как есть и
обслуживает первую постановку, кламп ширины и смоук, поэтому на одноэкранном раннере поведение и числа
проб не меняются. Полноценный многомониторный ремонт (захват, окно настроек, мастер) в раунд **не
входит**, строка в §7 «не перенесено».

**2.7. `AppCoordinator*.swift` целиком у порции Stack, включая `AppCoordinator+PasteIntent.swift`.**
По `CONTRACTS.md` (дополнение sync 2) файл `AppCoordinator+PasteIntent.swift` принадлежит
`exec-transport`, транспортного аналитика в раунде нет. **Решение:** отклонение от `CONTRACTS.md`,
записать его в §7 отдельной строкой. Ни Settings, ни Editor в `App/AppCoordinator*.swift` не заходят;
редактор дотягивается до ленты только через `OverlayEditorDelegate` (§2.4).

**2.8. `ToolAppearanceStore.swift` пишет волна 0, хотя файл лежит в `Editor/`.** `C §5.2` предлагал
писать его порцией Settings, `E §1.1 W0-2` требовал его в своей волне 0. **Решение:** его пишет **волна
0** (W0-6), потому что от него зависят обе порции: Editor читает и пишет словарь, Settings без непустого
`toolAppearance` не соберёт round-trip пробы `A5-3`. Волна 0 кладёт `ToolAppearance`,
`ToolAppearanceStore.read/write`, таблицу имён (§2.9) и тесты чтения, записи и зеркала старых ключей
(`Tests/SnapikMacTests/Editor/ToolAppearanceStoreTests.swift`). Порция Editor пишет **только**
`InspectorView`, `SecondCapsule`, `EditorInspector.inspectorViewOf/inspectedTool` и свои тесты
(`Tests/SnapikMacTests/Editor/ToolAppearanceTests.swift`, другой файл, конфликта нет). Отклонение от
`CONTRACTS.md` (`Sources/SnapikMac/Editor/**` = exec-editor) записать в §7.

**2.9. Имя инструмента в JSON заводит волна 0 отдельным свойством.** `EditorTool.rawValue` на Mac это
буква горячей клавиши (`EditorModels.swift:7-23`: `.rectangle = "R"`, `.blur = "B"`), в файл такие ключи
писать нельзя: Windows их не поймёт. **Решение:** волна 0 заводит в
`Sources/SnapikMac/Editor/ToolAppearanceStore.swift`

```swift
extension EditorTool {
    /// Имя инструмента в `settings.json`, а не буква клавиши: `rawValue` это "R"/"B".
    var appearanceKey: String? { ToolAppearanceStore.names[self] }
    init?(appearanceKey: String) { /* разбор по `lowercased()`, как `ignoreCase: true` на Windows */ }
}
```

со словарём `names` для шести инструментов (`rectangle`, `arrow`, `pen`, `highlight`, `text`, `blur`).
**Ловушка, которой нет у Windows:** на Mac есть ещё `select`, `conceal`, `crop`, `comment`, `eraser`, у
которых своих настроек нет. Они не попадают ни в `tools`, ни в файл, а `appearance(of:)` падает на набор
рамки: прямой индексации словаря в коде быть не должно, проверяется грепом.

**2.10. Ключ `toolAppearance` строго camelCase среди PascalCase-соседей.** Windows выбрал это осознанно
(`tz-006-notes-0.md`), паритет формата важнее единообразия имён: файл, записанный одной платформой,
должен открываться другой. Имя ключа в `CodingKeys` писать буква в букву, поля записи тоже camelCase
(`color`, `thickness`, `lineStyle`, `fill`, `fillColor`, `fontSize`, `arrowStyle`, `shape`). `fillColor`
обязан **исчезать** из файла, когда он `nil`, а не писаться как `"fillColor": null`: читается это
одинаково, но расходится с файлом Windows побайтно. Даётся это тем, что `encode(to:)` у
`ToolAppearanceEntry` руками не пишется (§4, чек-лист п. 4).

**2.11. «Прокрутка к концу» на неперевёрнутом `listContainer` это `scroll(to: y = 0)`.** `StackListView`
намеренно не flipped (`EdgeStackContentView.swift:102-104`), фреймы считаются как
`y = documentHeight − top − cardHeight`, то есть новейшая карточка имеет наименьший `y`.
`NSView.scrollToEndOfDocument` уедет к самому старому снимку. Целевое:
`scrollView.contentView.scroll(to: NSPoint(x: 0, y: 0))` плюс `reflectScrolledClipView(_:)`, и делать это
**внутри** `layoutCards` под флагом, а не вызовом после: `layoutCards` в конце сам ставит `origin` и
затрёт прокрутку. Проба утверждает `contentView.bounds.origin.y == 0`.

**2.12. Числа геометрии списка: источник один, Core.** `StripResizeGeometry.swift` (Core) и
`StackMetrics.swift` (Stack) дублируют `cardHeight`, `cardOverlap`, `cardStep`, `emptyHintHeight`,
`listPaddingTop`. **Решение:** владелец чисел это Core, владелец файла `StackMetrics.swift` это порция
Stack. Волна 0 пишет константы и функции в Core и `StackMetrics.swift` **не трогает**; порция Stack в
своём первом шаге превращает эти константы в псевдонимы
(`static let cardHeight = CGFloat(StripResizeGeometry.cardHeight)`) и там же правит `listPaddingLeft` 8→4,
`listPaddingRight` 8→12, `listPaddingBottom` 52→8, `scrollBarWidth` 4→3. `StackMetrics.listContentHeight`
снять: две формулы одного числа держать нельзя.

**2.13. `SessionWorkspace.exportSingle` пишет волна 0, а не порция.** `C §5.2` и `S §1.2 L-13` спорят за
него, а зовут его обе порции плюс проба `A5-2` в зоне Settings. **Решение:** волна 0 (W0-7), единственная
сигнатура:

```swift
func exportSingle(_ capture: CaptureItem, label: String? = nil,
                  renderer: ExportImageRendering) async throws -> PreparedExport
```

Рендерер передаёт вызывающий (так устроен `prepareExport(renderer:includingSent:)` на Mac, в отличие от
Windows, который строит его внутри). Сессия собирается в памяти из одного снимка, на диск не пишется,
ревизия не двигается. После волны 0 `SessionWorkspace.swift` не трогает никто.

**2.14. Дефект стрелок галереи тем (tz-006 A-1) на Mac не воспроизводится, переносится половина.**
Механики нет: `AppearancePickerView` считает `firstCard` сам (`:90`), а не вычитывает его из офсета
`ScrollViewer`, аналога `OnGalleryScrolled` нет вовсе, `visibleCards` при нулевой ширине даёт 1, то есть
худший случай это «обе стрелки включены». **Переносится:** правило «конец ряда это метка, а не
выключенность» (`ChevronButton.atEnd`, альфа 0.42, `isEnabled` всегда `true`) ради одинакового поведения
двух платформ, и кламп `firstCard = min(firstCard, lastPage)` в `layout()` перед
`layoutGallery(animated: false)` как аналог Windows-подписки на `SizeChanged`. **Не переносится:** гвард
`OnGalleryScrolled` (нечего гвардить), `DescribeGallery()`, `DescribeChevronHit()` и трасса
`WM_DPICHANGED` в `startup.log`. Смоук получает два утверждения: в начале ряда «назад» помечена концом,
«вперёд» нет, и обе кнопки остаются нажимаемыми.

**2.15. Порядок ключей и порядок пар держать как на Windows.** `CodingKeys` и `encode` пишут в порядке
объявления, `UiLanguage` держит Windows-часть в Windows-порядке, macOS-блок в хвосте. Причина
техническая: обратный поиск `UiLanguage.text(_:language:"ru")` это
`englishPairs.first(where: { $0.1 == value })` (`UiLanguage.swift:483`), и дубль английского значения
ответит чужим ключом. Проверять таблицу **скриптом, а не грепом** (`«Нет»` = `"None"`, `«Неон»` = `"Neon"`,
`«Обводка»` = `"Stroke"`: слова короткие и рискуют совпасть с уже написанным).

**2.16. Одинаковые имена у разных частей, разведённые сюда:** `ToolAppearance` и `ToolAppearanceEntry`
(волна 0, §2.8), `clearsTheStrip` (волна 0, §2.2), `publishedIsSingleCapture` (Stack, §2.3),
`exportSingle` (волна 0, §2.13), `copySingleCapture` (Stack, зовёт Editor), `applyListHeight` (Stack),
`listHeight(count:stored:manual:)` и `restoreRect` (Core), `interpolation(ratio:)` (Editor). Каждое имя
объявляется ровно один раз, список грепов при сведении в §6.

---

## 3. Изменения формата

Пять абзацев «Изменение формата» обоих раундов сведены здесь. `SettingsMigration.currentVersion`
остаётся **2** во всём раунде, ни одна порция его не поднимает.

### 3.1 `settings.json`: ключ `toolAppearance` (1.6.0)

Словарь «имя инструмента → запись»; ключ camelCase (§2.10), имена инструментов camelCase, шесть штук.
Поля записи: `color` (`#RRGGBB`), `thickness`, `lineStyle` (`solid|dashed|dotted`), `fill`
(`none|solid|translucent|blur`), `fillColor` (отсутствует = «как обводка»), `fontSize`, `arrowStyle`,
`shape` (`rectangle|rounded|ellipse`).

**`arrowStyle`: формат принимает четыре значения, панель предлагает три.** В файле и в модели живут
`straight`, `curved`, `bold`, `wide` (`SnapikCore/Models/AnnotationItem.swift:81`, дефолт `straight`), и
`bold` обязан **читаться**: он стоит в уже сохранённых сессиях. Windows в этом раунде убрал пункт
«толстая» из поповера стрелки (`OverlayEditorWindow.Arrows.cs:15-17`), поэтому предлагать его больше
нельзя (задача Editor 8). `C §4.2` перечисляет три значения, имея в виду именно предлагаемые: в файле их
четыре.

**Чтение старого файла:** у файла без ключа ошибки нет, каждый инструмент берёт старые общие значения
(`AnnotationColor`, `AnnotationThickness`, у маркера `AnnotationHighlightThickness`, у текста
`AnnotationFontSize`), то есть файл 1.5.0 открывается ровно так, как выглядел. Неизвестное имя
инструмента пропускается молча, неизвестное имя перечисления, цифра вместо имени и битый HEX падают на
значение по умолчанию этого же инструмента. **Запись:** пишутся все шесть, и старые общие ключи
продолжают писаться зеркалом рамки, маркера и текста, поэтому файл читается 1.5.0 целиком.
Подробно `C §2.1`, `E §2.1`.

### 3.2 `settings.json`: ключ `StackHeightManual` (1.7.0)

Аддитивный `Bool` рядом со `StackHeight`, дефолт `false`, JSON-ключ PascalCase. Файл без ключа читается
как `false`, старый билд лишний ключ игнорирует. Смысл: при `false` `StackHeight` это потолок и список
стоит по содержимому, при `true` то же число становится высотой списка с полом `minimumListHeight = 180`
и потолком рабочей области. Флаг поднимает только завершённое перетаскивание **углового** грипа, двойной
клик по ручке возвращает `false`, перетаскивание ширины флаг не трогает. Подробно `C §2.2`, `S §2.1`.

### 3.3 `settings.json`: смысл `StackHeight` и `SoundVolume` (схема та же)

`StackHeight` из «высоты списка» стал «потолком высоты списка» (1.6.0), тип и диапазон те же.
`SoundVolume` остался числом `0…100`, но превращается теперь в `(v / 100)² × gain`: ползунок 40 звучит
примерно на 8 дБ тише прежнего, ползунок 100 не меняется. Обе платформы обязаны считать одинаково, иначе
одно и то же число звучит по-разному (`C §2.3`, `C §2.4`).

### 3.4 `prompt.md` и имя файла одиночного пакета (1.7.0)

Только запись, читать нечего. У пакета **ровно из одного** снимка метка берётся из необязательного
`singleCaptureLabel`: скопировали карточку B, значит `01-B.png`, «Снимок B» в `prompt.md`, `B1`/`B2` в
подписях отметок, `Images[0].DisplayLabel == "B"` в `manifest.json` и «Снимок B скопирован» в тосте.
Обычный пакет не меняется ни на байт: параметр по умолчанию `nil`, метки раздаются по позиции. Интерфейс
`ExportService` не трогается (`C §2.5`, `S §2.2`).

### 3.5 `session.json`: схема не менялась, подтверждено по коду

`SchemaVersion` тот же, `AnnotationItem` на Windows в раунде не правился, `parentAnnotationId` остаётся
полем и **продолжает читаться**: сессия 1.5.0 сохраняет подпись «К отметке A2» и пометку «(к области A2)»
в `prompt.md`. Меняется только то, что никто больше не присваивает родителя (`toCore()` его не переносит,
как `legacyHasOutline` прошлого раунда). У комментария по-прежнему две точки, вторая остаётся в модели
как прямоугольник для обрезки и хит-теста. **Два изменения смысла при целой схеме:** `noteOffset` после
снятия клампа может выйти за `[0, 1]` (это допустимо, `SessionValidation` проверяет наличие, а не
диапазон), и отметка 1.5.0 с `fill = solid`, `fillColor = #0000FF`, `strokeColor = #FF3B30` теперь
рисуется красной обводкой, а не синей (`E §2.2`, `E §2.3`, `E §2.4`, `C §2.6`, `C §2.7`).

---

## 4. Волна 0: Core и контракты

Один исполнитель, ветка `mac-sync-5-wave0` от `master` (`220fe49`), коммит на задачу, префикс сообщения
`macos:`, CI между коммитами не запускать. Порции ветвятся от последнего коммита волны 0.

| # | Задача | Файлы | Тесты `XCTest` | Объём |
|---|---|---|---|---|
| W0-1 | `ToolAppearanceEntry: Codable, Equatable, **Sendable**` (`HotkeySettings` объявлен `Codable, Equatable, Sendable` на `Settings/HotkeySettings.swift:40`, поэтому без `Sendable` у значения словаря соответствие сломается; строгой конкурентности в пакете нет (`swift-tools-version: 5.9`, `SWIFT_VERSION: "5"`), `@MainActor` и лишних `Sendable` сверх этого не добавлять). Публичный `init` объявить явно: memberwise у публичной структуры internal. Плюс `toolAppearance` и `stackHeightManual` в `HotkeySettings` (поле, `CodingKeys`, `decodeIfPresent`, `encode`, четыре места на ключ) | `SnapikCore/Settings/ToolAppearanceEntry.swift` (новый), `SnapikCore/Settings/HotkeySettings.swift` | `SettingsMigrationTests`: файл 1.5.0 даёт `false` и пустой словарь; круг записи и чтения с обоими ключами; файл с `toolAppearance` не считается мигрированным | S |
| W0-2 | `StripResizeGeometry`: `emptyListHeight 92`, `listTopPadding 14`, `listBottomPadding 8`, `listPaddingLeft 4`, `listPaddingRight 12`, `cardHeight 78`, `cardOverlap 48`, `cardPitch = cardHeight - cardOverlap`; `listHeightForCount(_:cap:)`, `listHeight(count:stored:manual:)`, `capsuleLeft(stripLeft:stripWidth:capsuleWidth:)`, `restoreRect(...)` по §2.5 | `SnapikCore/Geometry/StripResizeGeometry.swift` | `StripResizeGeometryTests`: восемь случаев `listHeightForCount` (`0→92`, `1→100`, `2→130`, `5→220`, `12→372`, `cap 500→430`, `cap 130→130`, `NaN→372`); пять `listHeight` (`3,310,true→310`; `3,310,false→160`; `15,310,true→310`; `0,310,true→310`; `0,310,false→92`); `capsuleLeft(1600,244,180) == 1664`; три случая `restoreRect` | M |
| W0-3 | `SoundVolumeCurve.amplitude(volume:gain:)` (`C §4.6`) | `SnapikCore/Settings/SoundVolumeCurve.swift` (новый) | новый `SoundVolumeCurveTests`: `amplitude(100, 0.6) == 0.6`; `50 → 0.15`; `25 → 0.0375`; ноль это тишина на двух гейнах; `−5 → 0`, `250 → gain`; кривая только растёт (101 точка × гейны `0.6`, `0.25`, `0.7`), `accuracy: 1e-6` | S |
| W0-4 | `PromptGenerator(singleCaptureLabel:)` и `FileExportService(renderer:timeProvider:singleCaptureLabel:)`, развилка «один снимок и есть буква» внутри обоих. Правку и восемь вызывающих в тестах делать **одним коммитом** | `SnapikCore/Exporting/PromptGenerator.swift`, `SnapikCore/Exporting/FileExportService.swift` | `PersistenceAndExportTests`: пакет из одного снимка держит букву (`01-B.png`, «Снимок B», `B1:`, `B2:`); пакет из трёх букву игнорирует (`A`, `B`, `C`); пакет из одного **без** буквы прежний (`01-A.png`) | S |
| W0-5 | `SentCaptureRules.clearsTheStrip(isSingleCapture:clearStackAfterPaste:)` (§2.2) | `SnapikCore/Exporting/SentCaptureRules.swift` | `SentCaptureRulesTests`: настройка включена чистит, выключена не чистит, одиночная копия не чистит никогда | S |
| W0-6 | `EditorTool.appearanceKey` и `init?(appearanceKey:)` (§2.9), `struct ToolAppearance`, `enum ToolAppearanceStore` с `tools`, `read(_:)`, `write(_:tools:)` (`C §4.3`) | `SnapikMac/Editor/ToolAppearanceStore.swift` (новый) | новый `SnapikMacTests/Editor/ToolAppearanceStoreTests.swift`: файл без ключа раздаёт всем шести старые общие значения; файл с ключом читается им, инструмент без записи падает на общие, `"telepathy"` пропускается, в словаре остаётся 6; круг `write → read` с проверкой зеркала четырёх старых ключей | M |
| W0-7 | `SessionWorkspace.exportSingle(_:label:renderer:)` (§2.13), без `trimExports` (§2.1), с комментарием про долг | `SnapikMac/App/SessionWorkspace.swift` | покрыт пробой `A5-2` порции Settings, своего юнита не требует | S |
| W0-8 | `UiLanguage`: **+5** пар 1.6.0 после `«Добавить цвет в свою палитру»` и до комментария SPEC-DELTA-3 (`«Панель разметки»`, `«Обводка»`, `«Скруглённый»`, `«Нет»`, `«Неон»`); **+4** пары 1.7.0 перед `«Вставить изображение из буфера»` (`«Копировать снимок»`, `«Сохранить снимок…»`, `«Снимок {0} скопирован»`, `«Не удалось скопировать снимок»`); **−3** сразу (`«Цвет отметки»`, `«Тип линии»`, `«+ Снимок»`: проверено грепом, читателей нет, только комментарии кода). Ещё **четыре** пары снимаются в сведении, а не здесь: три после порции Editor (`«Толстая стрелка»`, `«По ширине · {0} %»`, `«По высоте · {0} %»`) и одна после порции Settings (`«Горячие клавиши…»`, `:243`, её последний читатель `Settings/HotkeySettingsWindowController.swift:244` переезжает на уже существующую пару `«Настройки клавиш»`). Все четыре отложенные и две остающиеся пары описать комментарием на месте, чтобы сведение знало, что снимать | `SnapikCore/Settings/UiLanguage.swift` | `SerializationCyrillicTests` ловят дубли; отдельно прогнать проверку уникальности английских значений скриптом (§2.15) | S |
| W0-9 | Сводный проход: все дописанные наборы лежат в существующих целях, новых тестовых целей не заведено, чек-лист ниже пройден | `Tests/SnapikCoreTests/**`, `Tests/SnapikMacTests/Editor/ToolAppearanceStoreTests.swift` | — | S |

**Порядок жёсткий в двух местах:** W0-4 трогает `PromptGenerator`, который зовут восемь тестов, правка и
тесты идут одним коммитом; W0-6 идёт после W0-1, потому что читает `HotkeySettings.toolAppearance`.

**Критерий готовности (компилятора нет, поэтому самопроверка по чек-листу):**

1. каждый новый тип и каждая новая функция объявлены ровно один раз: греп по имени даёт одно
   объявление, слева якорить (`grep -rn "[^A-Za-z]placeCapture(" Sources/`, §6 пункт 1);
2. `public` / `internal` расставлены по `CONTRACTS.md`: всё новое в `SnapikCore` публичное, всё новое в
   `SnapikMac` internal;
3. в подписях Core нет `NSColor`, `CGRect`, `NSRect`, `AppKit` и `CoreGraphics`:
   `grep -rn "import AppKit\|import CoreGraphics" Sources/SnapikCore/` пусто (правило дельты №4);
4. `CodingKeys` перечисляют новые ключи в порядке Windows. У `ToolAppearanceEntry` **`encode(to:)`
   руками не писать**: синтезированный `Codable` с явными `CodingKeys` (образец
   `HotkeySettings.swift:312-345`) сам не пишет `null` у `nil`-свойства, и `fillColor` исчезает из файла
   сам собой. `encodeIfPresent` понадобится только тому, кто всё-таки напишет `encode(to:)` руками;
5. у `PromptGenerator` объявлен явный `public init(singleCaptureLabel: String? = nil)`, иначе восемь
   вызовов `PromptGenerator()` в тестах перестают компилироваться;
6. `SettingsMigration.currentVersion` по-прежнему `2`;
7. ни один файл порций (`Stack/**`, `Settings/**`, `Onboarding/**`, `Imaging/**`, `Editor/**` кроме
   `ToolAppearanceStore.swift`) волной 0 не тронут: `git diff --name-only master` сверить со списком §5.1;
8. `swift build` и `swift test` **не запускать**: локально они не соберутся, их ошибки не сигнал.

**Записка исполнителю.** По итогу волны 0 завести `macos/WAVE0-NOTES-5.md` по образцу
`WAVE0-NOTES-4.md`: фактические имена, что где легло, что пришлось сделать иначе, чем в §4, и что порции
обязаны знать до старта. Пишет её волна 0, не сборщик этого плана.

---

## 5. Порции волны 1

Три ветки от коммита волны 0, параллельно, в отдельных worktree.

### 5.1 Владение файлами (пересечений нет)

| Путь | Владелец |
|---|---|
| `Sources/SnapikCore/**`, `Tests/SnapikCoreTests/**`, `SnapikMac/App/SessionWorkspace.swift`, `SnapikMac/Editor/ToolAppearanceStore.swift`, `Tests/SnapikMacTests/Editor/ToolAppearanceStoreTests.swift` | волна 0, порции только читают |
| `Sources/SnapikMac/Stack/**`, `SnapikMac/App/AppCoordinator*.swift` (все расширения, включая `+PasteIntent`, §2.7), `SnapikMac/App/SmokeTestRunner+Stack.swift`, `Tests/SnapikMacTests/Transport/**` | **Stack** |
| `Sources/SnapikMac/Editor/**` (кроме `ToolAppearanceStore.swift`), `SnapikMac/Imaging/**`, `SnapikMac/App/SmokeTestRunner+Editor.swift`, `Tests/SnapikMacTests/{Editor,Imaging}/**` (кроме файла волны 0) | **Editor** |
| `Sources/SnapikMac/Settings/**`, `SnapikMac/Onboarding/**`, `SnapikMac/App/UiSoundService.swift`, `SnapikMac/App/SmokeTestRunner+Settings.swift` | **Settings** |
| `Sources/SnapikCore/Settings/UiLanguage.swift` | волна 0; **одно исключение**: последний коммит порции Editor снимает три пары (§5.3, задача 16) |
| `Sources/SnapikMac/App/SmokeTestRunner.swift` (реестр проб **и** набор `custom.*` round-trip на `:76-89`, §6 пункт 5), `macos/project.yml`, `macos/SYNC.md`, `macos/README.md`, `macos/CONTRACTS.md` | только сведение |

Отклонения от `CONTRACTS.md`, которые надо записать в §7: `AppCoordinator+PasteIntent.swift` уходит от
`exec-transport` к Stack; `Editor/ToolAppearanceStore.swift` пишет волна 0, а не exec-editor.

### 5.2 Порция Stack (`mac-sync-5-stack`), 12 задач

Источник: `S §1`, порядок из `S §6.1` жёсткий, каждый шаг опирается на предыдущий.

| # | Задача | Ссылка | Объём |
|---|---|---|---|
| 1 | Числа `StackMetrics` и псевдонимы Core (§2.12): поля `4,14,12,8`, полоса 3 / 6, тень 12, снять `listContentHeight` и `expandedMargin` | `S §1.1 L-3`, `L-5` | S |
| 2 | `applyListHeight()` и высота по содержимому; звать из `refresh()` до `layoutWindow()`; открыть `rowCount`, массив `rows` оставить приватным | `S §1.1 L-2` | M |
| 3 | Ручная высота: `persistStackGeometry(manual:)` поднимает флаг только при `kind == .corner`, ранний выход при неизменившейся геометрии, двойной клик по ручке через `clickCount == 2` | `S §1.2 L-12` | M |
| 4 | `placeStripInitially()` / `ensureStripPlaced()`, флаг `placedOnce`, `workArea(for:)` по §2.6. **Гард капсулы дословно:** `positionAtEdge()` (`:220-247`) обслуживает две ветки и зовётся из `reveal()` `:79` и из `collapseToCapsule()` `:336`, а у `ensureStripPlaced()` ветки капсулы нет. `reveal()` зовёт `ensureStripPlaced()` **только при `!isCapsuleMode`**, иначе по-прежнему `positionAtEdge()` (аналог Windows-овского `if (!_capsuleMode) EnsureStripPlaced();`); вызов из `collapseToCapsule()` не трогать | `S §1.1 L-7` | M |
| 5 | Капсула: поле `expandedLeft`, `capsuleLeft`, `expandFromCapsule` через `restoreRect` одним `setFrame` | `S §1.1 L-6` | M |
| 6 | Снять раскрытие по выбору и фокусу (`isSelected` из условия, `cardSelectedBorder`, крестик по hover) | `S §1.1 L-1` | S |
| 7 | Раскрытие под курсором: `isUnfolded`, одна отложенная задача на ленту, 150 мс, 0.13 на обе стороны, `.inVisibleRect` у tracking area | `S §1.2 L-11` | M |
| 8 | Прокрутка к последнему снимку: флаг внутри `layoutCards` (§2.11), вызовы из `reveal()` и двух импортов, остальные точки не трогать | `S §1.2 L-8` | M |
| 9 | Вид карточки: клип 10 через `cardBorderWidth`, градиентная плашка 30 тремя стопами через `draw(_:)`, белые иконка и счётчик с общей тенью, три рамки из темы | `S §1.2 L-4`, `L-9`, `L-10` | M |
| 10 | Контекстное меню карточки через `menu(for:)`, три пункта, `NSSavePanel` под `withTopmostSuspended`, `copySingleCapture(_:label:) async -> Bool` в `AppCoordinator+Package.swift` **и реализация-переходник `overlayEditorCopiesSingleCapture(_:)` в `App/AppCoordinator+OverlayEditorDelegate.swift`** (подписи дословно в §2.4; без неё дерево не соберётся, как только Editor добавит требование в протокол) | `S §1.2 L-13`, §2.4 | L |
| 11 | Четыре правила одиночной копии (§2.3, §2.4) | `S §1.2 L-14` | M |
| 12 | Тесты и пробы одним куском: семь утверждений в `SmokeTestRunner+Stack.swift`, форматы пастборда в `TransportMacTests` | `S §4` | M |

**Нельзя трогать:** `SessionWorkspace.swift` (волна 0), `Editor/**`, `Settings/**`, `SmokeTestRunner.swift`,
`StripResizeGeometry.swift`, `UiLanguage.swift`. Свойство `isSelected` и `setSelectedCapture(_:)`
остаются, снимается только их влияние на геометрию и цвет.

### 5.3 Порция Editor (`mac-sync-5-editor`), 16 задач

Источник: `E §1`, порядок из `E §6.2`. Первые четыре задачи это чистые функции: без них ничего не встаёт.
После задачи 6 номера строк в `Editor/` поедут, дальше адреса искать грепом, а не по документу.

| # | Задача | Ссылка | Объём |
|---|---|---|---|
| 1 | `AnnotationRules`: `outlineColorOf(fill:color:)`, `enum PressTarget` (девять шагов, включая `deselect`), `pressTargetOf(...)` | `E §1.1 W0-1` | S |
| 2 | `NoteBadgeGeometry`: `exportScale(_:)`, `anchorRadius = 5`, `leader(..., fromRadius:)`, `ExportMargin`, `exportMargins(badges:width:height:)` | `E §1.1 W0-3` | M |
| 3 | `EditorGeometry`: `fit` отдаёт `Double` (снять `FitBound`/`FitResult`), `placeCapture(image:work:panel:gap:margin:)`, `placeToolbar(..., mayOverlap:)`, новый `ToolbarLayout.measure(...)`. Снятый `FitBound` держит `EditorStrings.fitPercent` и три её читателя: они уходят задачей 6, между задачами 3 и 6 порция заведомо не собирается, и это нормально (CI один, после сведения) | `E §1.1 W0-4` | M |
| 4 | `InspectorView`, `SecondCapsule`, `EditorInspector.inspectorViewOf/inspectedTool` поверх `ToolAppearanceStore` волны 0 (§2.8) | `E §1.1 W0-2` | S |
| 5 | E-8: обводка не красится заливкой, два вызывающих | `E §1.2 E-8` | S |
| 6 | E-1: переключателя масштаба нет, снимок 1:1 через `placeCapture`, `zoomByNotches`, разрезание `EditorScaleSwitchView.swift`, переименование `+Scale.swift`. **Заодно снять `EditorStrings.fitPercent`** (`Editor/EditorStrings.swift:65-70`): она принимает `EditorGeometry.FitBound`, который удаляет задача 3, а её читатели (`+Scale.swift:88`, `+SmokeTest.swift:438`) уходят здесь же | `E §1.2 E-1` | L |
| 7 | E-2: три блока, две строки, ширина свойств 176, `mayOverlap`, перетаскивание панели тремя отдельными методами | `E §1.2 E-2` | L |
| 8 | E-3: две капсулы вместо шести кнопок и ряда точек, `syncAppearance`/`applyAppearance` по инспектору, слияние поповера стиля в поповер толщины, четвёртая палитра «неон». **Плюс снять пункт `"bold"` из поповера стрелки** (`+Editing.swift:315`, `add(EditorStrings.arrowBold(language), "bold")`): Windows убрал «толстую» из списка (`OverlayEditorWindow.Arrows.cs:15-17`), в модели значение остаётся читаемым (§3.1) | `E §1.2 E-3`, §3.1 | L |
| 9 | E-4: настройки инструментов переживают перезапуск, не потеряв `AnnotationPalette`, `CustomPaletteColors`, `AnnotationPencil` | `E §1.2 E-4` | S |
| 10 | E-5: `pressTargetOf` в `beginGesture`, углы только у выделенной, `reach = 8`, инфляция текста 4, гейт `manipulationMoved` | `E §1.2 E-5` | L |
| 11 | E-6: `badgeDrag`, постановка жестом, наведение разворачивает пилюлю, шаг Esc `expandedNote`, снятие привязки | `E §1.2 E-6` | L |
| 12 | E-7: поле `#2A3140`, `exportMargins`, `captureOrigin`, снятие клампа бейджа | `E §1.2 E-7` | M |
| 13 | H-1 (заливка на клике) и H-2 (`interpolation(ratio:)`) отдельными коммитами, чтобы снимались одним revert | `E §1.2 H-1`, `H-2` | S |
| 14 | E-9, затем E-10: выноска от обода точки в обоих рисовальщиках, потом точка в экспорте и в файле на диске | `E §1.3 E-9`, `E-10` | M |
| 15 | E-11: у размытия нет блока свойств, форма пишется только у рамки, зеркало `tools[.blur].shape` остаётся | `E §1.3 E-11` | S |
| 16 | E-12 **последней**: кнопка «Копировать», Shift+Cmd+C, шпаргалка, плашка ответа, **требование `overlayEditorCopiesSingleCapture(_:) async -> Bool` в `OverlayEditorDelegate`** (подпись дословно в §2.4, реализация у Stack); плюс **отдельным коммитом** снятие трёх пар `UiLanguage` после того, как сняты все их читатели: `«Толстая стрелка»` (два читателя, `EditorStrings.swift:94` и `+Editing.swift:315`, оба уходят задачей 8), `«По ширине · {0} %»` и `«По высоте · {0} %»` (`EditorStrings.fitPercent`, уходит задачей 6) | `E §1.3 E-12`, `C §1.3`, §2.4 | M |

**Нельзя трогать:** `ToolAppearanceStore.swift` и его тесты (волна 0), `Stack/**`, `Settings/**`,
`App/AppCoordinator*.swift`, `SmokeTestRunner.swift`. Кнопка E-12 зовёт `copySingleCapture` порции Stack,
до сведения этот вызов не проверить: писать по сигнатуре §2.4 и не изобретать свою.

### 5.4 Порция Settings (`mac-sync-5-settings`), 9 задач

| # | Задача | Ссылка | Объём |
|---|---|---|---|
| 1 | Высота окна 620 × 620 и переписанный комментарий-обоснование | `C §1.6 S5-1` | S |
| 2 | `UiSoundService` переводится на `SoundVolumeCurve.amplitude(volume:gain:)`, гейны `0.6 / 0.25 / 0.7` не трогать | `C §1.4` | S |
| 3 | Число у ползунка громкости, таймер 150 мс, гашение при выключенных звуках, при закрытии окна и после локализации; значение ставится до подписки на action | `C §1.6 S5-2` | M |
| 4 | Четвёртый сегмент «Неон» и белый список сеттера в четырёх местах `AppearancePickerView` | `C §1.6 S5-3` | S |
| 5 | Конец ряда галереи это метка (`atEnd`), кламп `firstCard` в `layout()` (§2.14) | `C §1.7 S5-4` | S |
| 6 | Проба `A5-1`: высота четырёх вкладок против высоты окна с гвардом «меньше 200 px это не измерение»; `"60 %"` переживает смену языка; последовательность ряда палитр равна `EditorAppearance.palettes` | `C §1.9` | M |
| 7 | Проба `A5-2`: `exportSingle(capture, label: "B")` даёт `01-B.png` и текст со «Снимок B» | `C §1.9` | S |
| 8 | Правки `A5-3` **в своём файле**: `smokePaletteTitles` в четыре названия, окно на файле с `AnnotationPalette = "neon"` показывает неон. Набор `custom.*` для round-trip лежит **не здесь**, а в `SmokeTestRunner.swift:76-89`, который принадлежит сведению: `custom.stackHeightManual` и непустой `custom.toolAppearance` дописывает сведение (§6, пункт 5) | `C §1.9` | S |
| 9 | Правки языковой таблицы смоука `A5-4`; перевести accessibility-подпись вкладки с `«Горячие клавиши…»` на `«Настройки клавиш»`, чтобы пара снялась | `C §1.3`, `C §1.9` | S |

**Нельзя трогать:** `App/AppCoordinator*.swift` (§2.7), `Stack/**`, `Editor/**`, `Imaging/**`,
`SmokeTestRunner.swift` (в том числе набор `custom.*` на `:76-89`), `UiLanguage.swift` (пара
`«Горячие клавиши…»` снимается в сведении, §6 пункт 2). Утверждение про порядок палитр в `A5-1` станет
истинным только после слияния порции Editor: это ожидаемо, CI один и после сведения.

### 5.5 Правила исполнителю порции (в промпт каждому дословно)

1. Первым шагом `git merge <ветка волны 0>`; прочитать `macos/WAVE0-NOTES-5.md`, если он есть.
2. После `git worktree add` сверить `git worktree list`. Установка зависимостей не нужна, это SwiftPM.
3. **Запрещено** `swift build`, `swift test`, `xcodebuild`: macOS-раннера локально нет, ошибки этих
   команд не сигнал, проверка только на CI после сведения.
4. **Запрещено** `git checkout`, `git restore`, `git reset`: они откатывают чужие незакоммиченные правки.
5. **Запрещено** заходить в чужие файлы по §5.1, даже «на одну строчку». Нужна чужая правка, писать её в
   отчёт, а не делать.
6. Одно ревью в конце порции, а не после каждой задачи. CI не трогать вовсе.
7. Коммит на задачу, префикс `macos:`, сообщение по-английски, как в журнале репозитория.

### 5.6 Самопроверка вместо компилятора: типичные ошибки прошлых синхронизаций

Перед последним коммитом порции пройти список. Каждый пункт это уже случившаяся на этом порте ошибка.

1. **Флип контекста при блите.** Вокруг каждого блита локальный анти-флип внутри
   `saveGState`/`restoreGState`; сдвиг контекста делается **после** флипа, иначе то, что рисуется после
   painter'а, уезжает вместе со снимком (`E §1.2 E-7`).
2. **Знак тени.** `DropShadowEffect.Direction = 270` на WPF это «вниз» в системе, где Y растёт вниз; слой
   AppKit не перевёрнут, поэтому вниз это `shadowOffset = CGSize(width: 0, height: -1)`. Не копировать
   знак у тени карточки, которая намеренно идёт вверх (`S §1.2 L-9`).
3. **Неперевёрнутый контейнер ленты.** Низ документа это `y = 0` (§2.11).
4. **`Timer.scheduledTimer` держит сильную ссылку на target.** Брать
   `Timer(timeInterval:repeats:block:)` со `[weak self]`, `invalidate()` в `deinit` и при закрытии окна;
   образец teardown `Hotkeys/GlobalHotkeyService.swift:54-59`.
5. **`NSEvent.addLocalMonitorForEvents` требует парного `removeMonitor`.** Новых мониторов не заводить,
   переопределять `scrollWheel(with:)` / `menu(for:)` / `mouseDown(with:)` на самой вью.
6. **`sharingType`.** Исключение окна из захвата ставится только на время захвата
   (`WindowCaptureExclusion.swift:23-31`), новых окон в этот список не добавлять.
7. **`init(rawValue:)` регистрозависим**, а Windows терпит `"Rounded"` из правленного руками файла:
   везде `lowercased()` перед разбором (§2.9, §3.1).
8. **Публичная структура теряет memberwise-init при добавлении хранимого свойства**, и её memberwise-init
   всё равно internal: объявлять `public init` явно (W0-1, W0-4).
9. **Строка проверяется дословно.** `"60 %"` с пробелом перед знаком, без `NumberFormatter` и локали.
10. **`isHidden` против удаления вью.** Скрытая вью держит кадр и соседей не двигает: `removeFromSuperview`
    не использовать там, где Windows пишет `Visibility.Hidden`.
11. **Грепы на месте правки.** После правки `clampToImage` в `updateGesture` пересчитать все четыре
    вхождения; после снятия цикла в `findResizeHandle` проверить, что углы отвечают только у выделенной;
    после снятия пары `UiLanguage` проверить, что читателей не осталось.
12. **Ошибки в логе CI ищутся по `": error: "`**, а не по слову «error»: предупреждения печатаются так же.

---

## 6. Сведение

Один исполнитель на ветке синхронизации, порции мержатся **по одной**, после каждой прогоняются проверки
ниже. Локальной сборки нет, поэтому сведение это дисциплина грепов.

**Порядок: Settings → Editor → Stack.** Обоснование: Settings самая маленькая и трогает папки, которых не
касается никто (`Settings/**`, `Onboarding/**`, `UiSoundService.swift`), поэтому она садится без конфликтов
и даёт базу. Editor второй, потому что его последний коммит снимает три пары `UiLanguage`, а до этого
момента их читатели ещё живы; после Editor таблица строк окончательная, и `A5-1` получает свой
неон. Stack последний: он самый большой, трогает `App/AppCoordinator*.swift` и `SmokeTestRunner+Stack.swift`,
то есть переплетён с остальным сильнее всех, и разрешать его конфликты проще на устоявшемся дереве.

**После каждого мержа:**

1. Греп по координированным именам ровно одно объявление (§2.16). **Якорить слева**, иначе счёт врёт:
   `grep -rn "[^A-Za-z]placeCapture(" Sources/` (без якоря ловится `replaceCapture(`,
   `App/SessionWorkspace.swift:223` плюс пять вызывающих), так же `[^A-Za-z]listHeight(count:` и
   `[^A-Za-z]ToolbarLayout` (коллизия со `smokeVerifyToolbarLayout`). Полный список имён:
   `listHeightForCount(`, `listHeight(count:`, `capsuleLeft(`, `restoreRect(`, `clearsTheStrip(`,
   `exportSingle(`, `amplitude(volume:`, `ToolAppearanceStore`, `appearanceKey`,
   `publishedIsSingleCapture`, `copySingleCapture(`, `overlayEditorCopiesSingleCapture(`,
   `applyListHeight(`, `pressTargetOf(`, `placeCapture(`, `exportMargins(`, `interpolation(ratio:`.
2. `UiLanguage.swift`: ни одного повторяющегося русского ключа и ни одного повторяющегося английского
   значения, разбирать таблицу скриптом (§2.15). Отложенные пары снимаются здесь, а не в порциях:
   `«Горячие клавиши…»` (`:243`) **сразу после мержа Settings**, три пары редактора (`«Толстая стрелка»`,
   `«По ширине · {0} %»`, `«По высоте · {0} %»`) **после мержа Editor**, и перед каждым снятием грепом
   проверить, что читателей действительно не осталось. Две остающиеся пары (`«Свернуть в трей»`,
   `«Изображения и комментарии готовы к вставке»`) на месте и снабжены комментарием, как уже сделано для
   пары SPEC-DELTA-3 §3.3.
3. `git diff --name-only` сведённой порции сверить со списком §5.1: в чужие файлы никто не зашёл.

**После всех трёх:**

4. Реестр `App/SmokeTestRunner.swift`: каждая новая проба раунда вызывается **ровно один раз**,
   осиротевших нет, `smokeRunEditorScaleProbe` не остался после снятия переключателя масштаба.
5. **Правка сведения, а не порции:** там же, `SmokeTestRunner.swift:76-89`, в набор `custom.*` дописать
   `custom.stackHeightManual = true` и непустой `custom.toolAppearance` (часть `A5-3`, которую порция
   Settings сделать не могла: файл принадлежит сведению). Без этого проба «всё, что записали,
   вернулось» новых ключей не увидит.
6. Пара `overlayEditorCopiesSingleCapture(_:)` сошлась: требование в `OverlayEditorDelegate` (Editor) и
   реализация в `AppCoordinator+OverlayEditorDelegate.swift` (Stack) есть обе, подписи совпадают буква
   в букву (§2.4).
7. Числа `StackMetrics` выведены из `StripResizeGeometry`, литералов не осталось (§2.12).
8. `SettingsMigration.currentVersion == 2`.
9. `AppCoordinator.swift`: поле `publishedIsSingleCapture` одно, точка применения правила одна,
   `workArea(for:)` зовётся только из трёх мест §2.6.
10. Версия `1.7.0` в `macos/project.yml` (`CFBundleShortVersionString`, сейчас `1.5.0`).
11. Обновить `macos/CONTRACTS.md` дополнением sync 5: два отклонения владения (§5.1), снятый
    `EditorScaleSwitchView`, снятые `EditorGeometry.reopenFitBox`/`reopenCropRect`, снятая
    `EditorStrings.fitPercent`, новые кросс-зонные сигнатуры (`exportSingle`, `copySingleCapture`,
    `overlayEditorCopiesSingleCapture`, `clearsTheStrip`, `ToolAppearanceStore`, `restoreRect`).
12. **Один пуш.**

---

## 7. Закрытие

### 7.1 Цикл CI

Пуш ветки синхронизации запускает `.github/workflows/macos-build.yml`: сборка SwiftPM и Xcode, тесты,
`--smoke-test` на собранном `.app`, `--demo --demo-screenshot`, DMG. Прогон около пяти минут.

1. Прочитать лог, матчить `": error: "` (не слово «error»: предупреждения пишутся так же).
2. Одним фикс-коммитом чинить **всё**, что нашёл прогон, и пушить.
3. Не более **трёх** таких кругов. Если на третьем круге ошибки остались, остановиться и написать
   Никите, что именно не сходится: дальше идёт выжигание квоты раннера.

### 7.2 Тег и журнал

Тег `mac-sync-base-5` = `f2cf62b` (на коммите Windows, как все предыдущие, а не на коммите Mac-порта).
Черновик строки в таблицу `macos/SYNC.md`:

> | 5 | `mac-sync-base-5` = `f2cf62b` (Windows 1.7.0, 76 коммитов, два раунда ТЗ; спека `SPEC-DELTA-5.md`
> плюс три части, заметки волны 0 `WAVE0-NOTES-5.md`) | лента считает высоту по содержимому и помнит
> вытянутую руками (`StackHeightManual`, двойной клик по ручке); лента остаётся там, куда её оттащили, а
> капсула встаёт на её угол; прокрутка к последнему снимку; вид карточки (поля `4,14,12,8`, полоса 3 / 6,
> клип 10, тень 12, градиентная плашка 30, три рамки из темы, раскрытие под курсором с задержкой);
> контекстное меню карточки, копия одного снимка с её буквой (`01-B.png`, «Снимок B») и четыре правила её
> жизни; редактор открывает снимок 1:1 без переключателя масштаба, панель разметки в трёх блоках с
> перетаскиванием, блок свойств как инспектор из двух капсул поверх памяти каждого инструмента
> (`toolAppearance` в настройках), одно правило нажатия, самостоятельный комментарий, экспорт с полем
> `#2A3140` и точкой комментария, кнопка «Копировать» и Shift+Cmd+C; окно настроек 620 с числом у
> громкости и квадратичной кривой звука, четвёртая палитра «Неон», конец ряда галереи как метка; 9 новых
> пар `UiLanguage`, 3 снятых | `macos-v1.7.0` |

Абзац «не перенесено» под таблицей переписать целиком:

> Не перенесено синхронизацией №5 и ждёт следующей: **ротации `exports/revision-*` на Mac нет вовсе**
> (ни у пакета, ни у одиночной копии; Windows чистит `TrimExports`, каждое «Копировать снимок» на Mac
> оставляет ещё один каталог до очистки ленты или до следующего старта); **многомониторный `workArea()`**
> перенесён частично (кламп уже стоящей ленты берёт экран окна, всё остальное по-прежнему считает первый
> экран); **прокрутка внутри окна настроек** (высота 620 лечит обрезку содержимого, а не маленький
> монитор); **платформенное Windows**: закреп на панели задач (`TaskbarPinLegacy`, `CarryOverLegacyPin`,
> шаг `PinCarryOver` мастера, три пары `UiLanguage` про панель задач, проба
> `VerifyALegacyPinIsCarriedOver`), `VerifyALayeredWindowMinimisesAsync` и лента как окно панели задач
> (приложение на Mac живёт агентом, `LSUIElement`), трасса `WM_DPICHANGED` с `DescribeGallery` и
> `DescribeChevronHit`, `Controls/RoundedClip.cs` (на Mac это `layer.cornerRadius`), `FrameCopy.Detach`,
> `installer/Snapik.iss`. Отклонения владения этого раунда: `AppCoordinator+PasteIntent.swift` правила
> порция Stack, `Editor/ToolAppearanceStore.swift` писала волна 0. Интерактивная проверка на живом Mac
> по-прежнему не проведена, список в `README.md`. База следующей синхронизации: Windows HEAD на момент её
> начала.

### 7.3 `README.md`, раздел «Что проверено и что нет»

В «проверено в CI» дописать пробы раунда: вкладки настроек влезают в окно, одиночный экспорт носит букву
карточки, высота ленты по содержимому и ручная высота, раскрытая карточка не растит ленту, панель
редактора в двух строках, память инструментов переживает перезапуск, точка комментария в экспорте,
правила интерполяции. В «не проверено» дописать всё из §7.4. Раздел «Что умеет» обновить в трёх местах:
переключателя масштаба у редактора больше нет (снимок открывается 1:1, масштаб только Cmd+колесо), у
каждого инструмента своя память настроек, у карточки ленты есть контекстное меню с копией и сохранением
одного снимка.

### 7.4 Что глазам на живом Mac или на виртуалке

Автопрогон не закрывает ничего из списка. Сведено из `S §6.2`, `E §6.3`, `C §5.3`.

1. **Лента.** Раскрытие карточки: задержка 150 мс, плавность на 26 карточках, быстрый проезд курсором
   мимо шести карточек не должен дёргать ни одну. Угол ленты: потянуть вниз, отпустить, сделать захват,
   двойной клик по ручке. Прокрутка: двенадцать снимков, последний внизу, прокрутить вверх и сделать
   снимок. Полоса 3 в покое и 6 по наведению, второй тусклой полосы нет, тень карточки в дорожку не
   заходит. Скруглённые углы миниатюры после клипа 10.
2. **Два монитора.** Капсула у границы двух мониторов и разворот в те же координаты; лента, оттащенная от
   края и на второй экран (это и есть проверка §2.6); перенос вытянутой ленты на монитор другого масштаба.
3. **Цвета.** Шесть снимков на «Стекле» и на «Рассвете»: плашка прозрачная, снимок читается под буквой,
   буква читается на светлом снимке, тёмной кромки в углу нет.
4. **Копия одного снимка.** Настоящий Cmd+V в Claude, ChatGPT и Telegram: один PNG с отметками и полем,
   текст комментариев этого снимка, галочка только на скопированной карточке, следующий захват даёт пакет
   из неотправленных. Отдельно та же вставка при включённой «Очистить ленту после вставки»: лента обязана
   остаться на месте. Правая кнопка на 125 % и на втором мониторе.
5. **Редактор.** Шов и прокрутка снимка двух мониторов 1:1, Cmd+колесо «ощущением руки», порог 4 px.
   Панель на узком экране и при масштабе 2×: две строки, блок свойств 176, четвёртый сегмент палитры.
   Перетаскивание панели мышью (проба двигает её методами, а не указателем). Наведение на бейдж и Esc над
   раскрытой пилюлей. Постановка комментария жестом, бейдж на затемнённом фоне. Пустой блок свойств у
   размытия: не читается ли он как поломка панели. Крап на тёмной фотографии после H-2: во вписанном
   состоянии его быть не должно.
6. **Экспорт.** Как выглядит поле `#2A3140` в картинке, уехавшей в чат; линия комментария касается обода
   точки без зазора; «Сохранить на компьютер» даёт тот же кадр, что и копия в буфер; старая сессия с
   двухточечными комментариями рисует линию от точки, а не от угла квадрата.
7. **Звук.** Тик громкости на ползунке: смоук проверяет число и то, что таймер гасится, но не звук.
   Дефолт 40 по новой кривой примерно на 8 дБ тише прежнего, сказать Никите вслух.
8. **Настройки.** Окно 620 на маленьком мониторе: содержимое не обрезано, но окно целиком может не
   влезть, прокрутки внутри нет.
