# SPEC-DELTA-3: перенос Windows `mac-sync-base-2` → `a2f72e1` (1.4.0) на macOS

База переноса: `mac-sync-base-2` = `e588ad0` (Windows HEAD 9 сентября, `macos-v0.1.0-32`). Цель: `a2f72e1` (Windows 1.4.0, 14 сентября). Между ними 123 коммита, тронувших `src`/`tests`, четыре раунда ТЗ: 1.1.0-1.2.0 (установщик, мастер, звуки, окно сохранения пакета), 1.3.0 (ТЗ №2 Кати), 1.3.1-1.3.2 (ТЗ №3 Никиты), 1.4.0 (ТЗ №3 Кати, план `tasks/tz-004-plan.md`). Diff: `git diff mac-sync-base-2 HEAD -- src tests` = 118 файлов, +13399/-1593.

**Правило целевого состояния.** Windows-команда уже начала раунд ТЗ №4 (`tasks/handoff-005/TZ-004-v140-test.md`, цель 1.5.0), который часть свежих вещей 1.4.0 переопределяет. Там, где ТЗ №4 называет конечное состояние явно и оно не зависит от несуществующего Windows-кода, Mac делает **сразу целевое** и не проходит через промежуточное состояние 1.4.0. Каждая такая строка помечена **[ТЗ№4]** с пунктом. Там, где целевое состояние ещё не написано на Windows, работа помечена **[1.5.0]** и вынесена в раздел 5.

Правила синхронизации не меняются: `macos/SYNC.md`, контракты зон `macos/CONTRACTS.md`, общая спека `macos/SPEC.md`. Сборка и тесты только в CI (`.github/workflows/macos-build.yml`, macos-15, `swift build`, `swift test`, `macos/scripts/ci-smoke.sh`). Формат делты по образцу `macos/SPEC-DELTA-2.md`.

---

## 1. Резюме: что переносится, по модулям Mac-порта

Размер: S — правка в одном файле, M — файл целиком или два связанных, L — новая подсистема.

### 1.1 Core: модели, сериализация, правила

| # | Что | Windows-источник | Целевой Swift-файл | Объём |
|---|---|---|---|---|
| C-1 | `AnnotationItem` получает семь полей: `noteOffset` (`NormalizedPoint?`), `shape`, `fill` (+ значение `blur`), `fillColor` (`String?`), `hasOutline` (`Bool`, деф. `true`), `fontSize` (`Double`, деф. 20), `lineStyle` | `src/SnapBrief.Core/Models/AnnotationItem.cs:20-80`; коммиты `b0c2cb3`, `5473cee`, `e2618bd`, `63bd27d`, `3d34ddf` | `macos/Sources/SnapBriefCore/Models/AnnotationItem.swift:40-152` (все семь — в `CodingKeys`, `init(from:)` через `decodeIfPresent`, `encode`) | M |
| C-2 | Два новых enum: `AnnotationShape {rectangle, rounded, ellipse}`, `AnnotationLineStyle {solid, dashed, dotted}`; `AnnotationFill` получает `.blur` | `AnnotationItem.cs:20-43` | там же, рядом с `AnnotationKind` (`AnnotationItem.swift:4-13`) | S |
| C-3 | `CaptureItem.Sent` (bool, деф. `false`) | `src/SnapBrief.Core/Models/CaptureItem.cs:17`; `2a753ae` | `macos/Sources/SnapBriefCore/Models/CaptureItem.swift:5-37` | S |
| C-4 | `SentCaptureRules` — **файла в Swift нет вовсе**: `ForPackage` (пакет несёт только неотправленные), `StripLabels` (буквы только ожидающим), `MaxStripCaptures = 26`, `SoftStripWarning = 20` | `src/SnapBrief.Core/Exporting/SentCaptureRules.cs:8-37` | новый `macos/Sources/SnapBriefCore/Exporting/SentCaptureRules.swift` | M |
| C-5 | `SessionValidation`: `lineStyle` обязан быть из перечисления; `noteOffset` требует только `isFinite` (это сдвиг, не координата, он может быть отрицательным и вне картинки) | `src/SnapBrief.Core/Models/SessionValidation.cs:61-76` | `macos/Sources/SnapBriefCore/Models/SessionValidation.swift:34-62` | S |
| C-6 | `CaptureCropper`: `noteOffset` пересчитывается при обрезке (делится на ширину и высоту кропа); `fontSize` и поля заливки переживают кроп | `src/SnapBrief.Core/Editing/CaptureCropper.cs:75-84` | `macos/Sources/SnapBriefCore/Editing/CaptureCropper.swift` | S |
| C-7 | `PromptGenerator`: снимок без заголовка, без заметки снимка и без подписанных отметок в текст не попадает вовсе (буквы по-прежнему от позиции в пакете) | `src/SnapBrief.Core/Exporting/PromptGenerator.cs:19-33` | `macos/Sources/SnapBriefCore/Exporting/PromptGenerator.swift:9-19` | S |
| C-8 | `FileExportService`: имя картинки `01-A.png` вместо `A_<guid>.png`; при пустом тексте `prompt.md` не пишется, `promptFileName` и `promptSha256` — пустые строки | `src/SnapBrief.Infrastructure/Exporting/FileExportService.cs:40-85` | `macos/Sources/SnapBriefCore/Exporting/FileExportService.swift:40, 67-79` | S |
| C-9 | `HotkeySettings`: 24 новых ключа (раздел 2.2), `SettingsVersion` + миграция громкости, лечение битых id клавиш при чтении, `MaxCustomPaletteColors = 12` с отсевом невалидного hex | `src/SnapBrief.App/HotkeySettingsWindow.xaml.cs:14-270`, `SettingsMigration.cs:8-30` | `macos/Sources/SnapBriefCore/Settings/HotkeySettings.swift:40-226`, новый `macos/Sources/SnapBriefCore/Settings/SettingsMigration.swift` | L |
| C-10 | `HotkeyRules` — чистые правила клавиш: `IsShortcutOnItsOwn`, `IsModifierKey`, `TryParseCustom`, `IsSystemReserved`, `SameGesture`, `SuggestFree` | `src/SnapBrief.App/HotkeyRules.cs:12-110` | новый `macos/Sources/SnapBriefCore/Settings/HotkeyRules.swift` (ветка Cmd вместо Win, раздел 4) | M |
| C-11 | `TextMarkMetrics`: `Measure`/`Fit`/`Clamp`, пресеты кегля 12/16/20/24/32/48, диапазон 8..96; прямоугольник надписи считается по реальным метрикам букв | `src/SnapBrief.App/TextMarkMetrics.cs:11-60` | новый `macos/Sources/SnapBriefCore/Editing/TextMarkMetrics.swift` (CoreText вместо `FormattedText`; семейство — раздел 4) | M |
| C-12 | `SaveNaming`: свободное имя пакета (`name`, `name (2)`, … до 100), фильтр диалога сохранения по текущему формату | `src/SnapBrief.App/SaveNaming.cs:9-45` | новый `macos/Sources/SnapBriefCore/Exporting/SaveNaming.swift` | S |
| C-13 | `PublishedPackage` + `IsOwnPaste`: опубликованный пакет отделён от подготовленного | `src/SnapBrief.App/PublishedPackage.cs:11-28` | `macos/Sources/SnapBriefCore/Transport/TransportContracts.swift` (рядом с `ClipboardSnapshot`) | S |
| C-14 | `SoundThrottle`: тик 170 мс, подавление тиков после затвора 400 мс — вынесено из `CaptureFeedbackSound` в отдельный тип | `src/SnapBrief.App/SoundThrottle.cs:11-30` | `macos/Sources/SnapBriefMac/App/CaptureFeedbackSound.swift:10-16` уже держит те же числа: вынести в Core, чтобы покрыть тестами | S |
| C-15 | `SessionWorkspace`: `PurgePreviousSessionsAsync` (снос GUID-каталогов и `current-session.txt` на старте, посторонние файлы не трогать, занятый каталог пропустить), `DiscardCurrentSessionAsync`, отказ от восстановления прошлой сессии | `src/SnapBrief.App/SessionWorkspace.cs:86-137` | `macos/Sources/SnapBriefMac/App/SessionWorkspace.swift` | M |

### 1.2 Transport

| # | Что | Windows-источник | Целевой Swift-файл | Объём |
|---|---|---|---|---|
| T-1 | Пакет без заметок не несёт текста: `PasteCoordinator` пропускает шаг текста целиком (`hasText`), не ждёт его подтверждения и не считает его таймаут отказом | `src/SnapBrief.Windows/PasteCoordinator.cs:58-95, 131-170, 191` | `macos/Sources/SnapBriefCore/Transport/PasteCoordinator.swift` | M |
| T-2 | `CodexPasteCompletionResult.NeedsRepublish(packageIsStillCurrent)`: завершение, которое ничего не писало в буфер, больше не перепубликовывает пакет (иначе первый Cmd+V/Ctrl+V приходит в пустоту) | `src/SnapBrief.Windows/TransportContracts.cs:345-355` | `macos/Sources/SnapBriefCore/Transport/TransportContracts.swift` | S |
| T-3 | `CodexDesktopPasteCompletionService`: пустой текст — это `CompletedUnverified`, а не `NothingToDispatch`; последовательный путь требует только хотя бы одну картинку | `src/SnapBrief.Windows/CodexDesktopPasteCompletionService.cs:57-62, 144-190` | `macos/Sources/SnapBriefCore/Transport/CodexDesktopPasteCompletionService.swift` | S |
| T-4 | Пустой текст не кладётся в буфер отдельным форматом (иначе получатель вставляет пустую строку) | `src/SnapBrief.Windows/WindowsClipboardService.cs:230-233` | `macos/Sources/SnapBriefMac/Transport/MacClipboardService.swift` (не писать `public.utf8-plain-text` при пустом тексте) | S |
| T-5 | Вставленные снимки помечаются `Sent` и остаются в ленте; пакет собирается только из неотправленных, счётчик и буквы идут от них | `src/SnapBrief.App/EdgeStackWindow.xaml.cs` (`Renumber`, путь завершения вставки); `2a753ae` | `macos/Sources/SnapBriefMac/App/AppCoordinator+PasteIntent.swift`, `AppCoordinator+Package.swift` | M |

### 1.3 Stack (лента)

Вся зона переписывается в целевом виде ТЗ №4: порядок карточек, ширина, тени и поле под тень задаются один раз, а не дважды.

| # | Что | Windows-источник | Целевой Swift-файл | Объём |
|---|---|---|---|---|
| S-1 | Окно предпросмотра снимка убрано целиком, клик по карточке открывает редактор напрямую | удалены `CapturePreviewWindow.xaml(.cs)`, `EdgeStackWindow.Preview.cs`; `6a5c713` | **удалить** `macos/Sources/SnapBriefMac/Preview/**` (7 файлов) и `macos/Tests/SnapBriefMacTests/Preview/**` (2 файла); клик — в `EdgeStackWindowController` → `OverlayEditorController` | M |
| S-2 | Лимит ленты 26 снимков, мягкое предупреждение один раз после 20-го с флагом сброса, жёсткий тост с числом из константы; проверка на всех четырёх точках добавления (захват, импорт файлов, импорт из буфера, возврат удалённого) | `EdgeStackWindow.xaml.cs:577-596, 1050, 1078`; `SentCaptureRules.cs:15, 21` | `macos/Sources/SnapBriefMac/Stack/EdgeStackWindowController.swift` | M |
| S-3 | **[ТЗ№4 C1]** Порядок карточек: новый снимок **поверх** старых, полоса с буквой и числом заметок **сверху** карточки, шаг 30 px, перекрытие 48. `ZIndex`, `AlternationIndex`, конвертер глубины и виртуализация не переносятся вовсе — на Mac их аналогов и не заводить: список рисуется в порядке данных | 1.4.0: `EdgeStackWindow.xaml:224, 228-229, 248, 172`; целевое: `TZ-004-v140-test.md` §C1 | `macos/Sources/SnapBriefMac/Stack/EdgeStackContentView.swift`, `ThumbnailCardView.swift` | M |
| S-4 | **[ТЗ№4 C4]** Ширина ленты 224 (`DefaultWidth`, `MinimumWidth`), карточка 168×78, кнопки шапки 22 px. Сохранённая пользователем ширина клампится снизу до 224 | 1.4.0: `Controls/StripResizeGeometry.cs:13-14`; целевое: §C4 | `macos/Sources/SnapBriefMac/Stack/StackMetrics.swift:11-12` (сейчас 208) | S |
| S-5 | **[ТЗ№4 C6]** Тени: поле под тень окна 20 px (не 10), карточка `blur 16 / offset 6 / opacity .35`, тень направлена вверх на соседа; список получает отступы `8,14,8,52`. Поле участвует и в геометрии растягивания, и в прижатии к краю экрана | целевое: §C6; 1.4.0: `EdgeStackWindow.xaml:134-135` | `StackMetrics.swift`, `EdgeStackWindowController.swift` (позиционирование у края) | M |
| S-6 | **[ТЗ№4 C2]** Полоса прокрутки 4 px в правом поле карточек, без анимации ширины при наведении на список; ползунок `#FFFFFF` 28 %, под курсором 45 % | целевое: §C2; 1.4.0: `EdgeStackWindow.xaml:194-203` | `EdgeStackContentView.swift` (`NSScrollView` overlay-скроллер) | S |
| S-7 | **[ТЗ№4 C3]** Пустая лента компактная: шапка, подсказка в две строки (блок 92 px, `TextMutedBrush`), кнопка «Новый снимок», высота по содержимому; растягивание пустой ленты выключено | целевое: §C3; 1.4.0: `StripResizeGeometry.cs:31` | `EdgeStackContentView.swift`, `StackMetrics.swift` | M |
| S-8 | **[ТЗ№4 C5]** Перетаскивание за любое свободное место панели (`isMovableByWindowBackground` + прозрачный hit-target шапки), кнопки/карточки/скроллер/хваты нажатие забирают себе | целевое: §C5 | `EdgeStackWindowController.swift` | S |
| S-9 | Растягивание ленты: геометрия считается **абсолютом от стартовой позиции курсора**, а не суммой дельт (сумма копит путь за клампом и даёт мёртвую зону). `WidthFromStart`, `ListHeightFromStart`, `ClampWidth(width, workWidth)`, `ClampListHeight(height, workHeight, chromeHeight)`, `EdgeGap = 10`, `EstimatedChromeHeight = 140`. Потолок — рабочая область монитора, а не константа | `Controls/StripResizeGeometry.cs:11-120`; `46e0c56`, `cc308bc` | новый `macos/Sources/SnapBriefCore/Geometry/StripResizeGeometry.swift` (Core, чтобы покрыть тестами) + `EdgeStackWindowController.swift` | L |
| S-10 | Капсула: режим того же окна, кнопка «—» между «•••» и «×», при схлопывании прячется содержимое, окно жмётся к тому же углу; счётчик показывает неотправленные; снимок при свёрнутой капсуле её не разворачивает; флаг в настройки не пишется | `EdgeStackWindow.xaml.cs:649-726` | `EdgeStackWindowController.swift` + новый `StackCapsuleView.swift` | L |
| S-11 | Меню «•••»: колонка чек-марки у отмеченных пунктов («Поверх других окон», выбор получателя) | `EdgeStackWindow.xaml:74-87` | на Mac `NSMenuItem.state` даёт галочку системой: свериться, что состояние ставится, и не рисовать свою | S |
| S-12 | `StackTopmost` с переключателем в меню; `ClearStackAfterPaste`; тост «Вернуть» вместо постоянной кнопки; удаление/восстановление/реордер снимка | `EdgeStackWindow.xaml.cs:942-1000`, `84217a4`, `215d9d9` | `EdgeStackWindowController.swift` (`NSWindow.level`) | M |
| S-13 | Диалог подтверждения очистки ленты и выхода при непустой ленте, галочка «Больше не спрашивать» → `ConfirmSessionDiscard`; перед удалением буфер отдаётся, если в нём ещё наш пакет | `DiscardSessionWindow.xaml(.cs)`, `EdgeStackWindow.xaml.cs:1439` | новый `macos/Sources/SnapBriefMac/Stack/DiscardSessionSheet.swift` (`NSAlert` со `suppressionButton`) | M |
| S-14 | **[ТЗ№4 C7]** Постоянное исключение ленты из захвата снимается: лента прячется только на время нашего захвата, чужой скриншот (Cmd+Shift+4, запись экрана) её видит | целевое: §C7; 1.4.0: `EdgeStackWindow.xaml.cs:244` | `macos/Sources/SnapBriefMac/App/WindowCaptureExclusion.swift`: `sharingType = .none` ставить только на время `hideForCapture`, по умолчанию `.readOnly` | S |
| S-15 | **[ТЗ№4 A7]** После «Начать»/«Пропустить» в мастере лента показывается сама (пустая, компактная) | целевое: §A7 | `macos/Sources/SnapBriefMac/App/AppCoordinator.swift` | S |

### 1.4 Editor

| # | Что | Windows-источник | Целевой Swift-файл | Объём |
|---|---|---|---|---|
| E-1 | Фигура рамки (`rectangle`/`rounded`/`ellipse`) и заливка (`none`/`solid`/`translucent`/`blur`) как два независимых свойства; `ShapeMask` даёт покрытие пикселя со сглаживанием края, оба рендерера берут маску из одного места; `RegionBlur` смешивает по маске, радиус `clamp(min(w,h)/12, 6, 36)` и больше не зависит от толщины | `src/SnapBrief.App/Imaging/ShapeMask.cs:11-60`, `Imaging/RegionBlur.cs`, `EditorModels.cs`; `e2618bd`, `0e24600` | новый `macos/Sources/SnapBriefMac/Imaging/ShapeMask.swift`; `Imaging/RegionBlur.swift`, `AnnotationPainter.swift`, `ExportImageRenderer.swift`; `Editor/EditorModels.swift:42-165` | L |
| E-2 | Тип линии: `Solid`/`Dashed`/`Dotted`, узор задан **в толщинах пера** (`[3,2]`, `[0,2]` с круглым концом), поэтому экран и PNG совпадают при любом масштабе; участвуют рамка, овал, стрелка, карандаш; наконечник стрелки всегда сплошной | `Imaging/StrokePattern.cs:10-35`, `Imaging/ArrowDrawing.cs`, `WpfExportImageRenderer.cs:95-135`; `3d34ddf` | новый `macos/Sources/SnapBriefMac/Imaging/StrokePattern.swift`; `ArrowDrawing.swift`, `AnnotationPainter.swift`, `ExportImageRenderer.swift` | M |
| E-3 | Толщина: своя кнопка с поповером (пресеты 2/4/6/8, ползунок 1..16); у маркера своя толщина (пресеты 8/12/16/24, ползунок 4..48), чтение и запись через `ActiveThicknessFor(tool)` | `OverlayEditorWindow.Appearance.cs`, `93f80d7` | `macos/Sources/SnapBriefMac/Editor/EditorAppearancePopover.swift`, `EditorToolbarView.swift` | M |
| E-4 | Карандаш и маркер разошлись: штрих рисуется **одной геометрией на сегмент**, маркер — прозрачность 0.4 поверх непрозрачной кисти с квадратными торцами, карандаш — круглые торцы; split-капсула «Карандаш» с пунктами «Перо»/«Маркер», клавиши P/H; хват = `max(6, thickness*scale/2 + 4)` | `Controls/AnnotationCanvas.cs`, `93f80d7`, `8b027bc` | `macos/Sources/SnapBriefMac/Editor/AnnotationCanvasView+Drawing.swift`, `EditorToolbarView.swift` | M |
| E-5 | Ластик: `EditorTool.eraser` (клавиша E), в модель не попадает; обводка объекта под курсором `#FF3B30`, клик удаляет одной записью Undo | `EditorShortcuts.cs:20`, `67ed5aa` | `Editor/EditorModels.swift:7-28`, `AnnotationCanvasView.swift` | M |
| E-6 | Текст печатается прямо на снимке: поле ввода поверх холста в точке клика, кегль из модели, Enter завершает, Shift+Enter переносит, Esc отменяет, клик вне завершает; пустая надпись удаляется; правка существующей надписи — одна запись истории; кнопка «Размер» с поповером | `OverlayEditorWindow.Text.cs`, `TextMarkMetrics.cs`; `63bd27d`, `f19154d` | новый `macos/Sources/SnapBriefMac/Editor/OverlayEditorController+Text.swift`, `AnnotationCanvasView+Drawing.swift` | L |
| E-7 | Комментарии: один номерной бейдж на комментарий (второй из пилюли убран, сетка пилюли двухколоночная, ширина 226→200 и 270→244), ручка перетаскивания на самой пилюле, при непустом `noteOffset` пилюля встаёт **рядом** с бейджем, а не поверх | `OverlayEditorWindow.xaml.cs:1240-1290, 1330-1430`; `21828aa` | `macos/Sources/SnapBriefMac/Editor/CommentChipView.swift`, `ChipLayerView.swift`, `OverlayEditorController+Chips.swift` | M |
| E-8 | Якорь выноски: круг 10 px акцентом с белой обводкой в `points[0]`, под курсором 14 px и «лапка»; тянет обе точки, `noteOffset` компенсируется на ту же дельту; одна запись истории на завершение; в экспортный PNG якорь не идёт; рисуется только у отведённой в сторону заметки; захват якоря — за инструментом «Выбор» | `Controls/AnnotationCanvas.cs:196-210, 565-580`, `d4d51f5`, `ac94ad9` | `AnnotationCanvasView.swift`, `OverlayEditorController+Selection.swift` | M |
| E-9 | **[ТЗ№4 D3]** Инструмент «Комментарий» остаётся в руке после булавки (снимается Esc, кнопкой «Выбор», выбором другого инструмента), и при активном «Комментарии» порядок проверки нажатия — **якорь → бейдж → пилюля → пустое место**: первые три захватывают существующий комментарий, новая булавка ставится только на пустом месте. То же правило для остальных инструментов: нажатие по существующей отметке своего типа выделяет её | 1.4.0: `OverlayEditorWindow.xaml.cs:1072-1090`, `9f605d9`; целевое: §D3 | `AnnotationCanvasView.swift`, `OverlayEditorController+Editing.swift` | M |
| E-10 | Жесты и курсоры: объект рождается после сдвига в 4 **экранных** пикселя, перо и маркер после отпускания не выделяются, курсоры различают углы/хват/крестик/стрелку, `Esc` — лестница `NextEscapeStep` (черновик → поповер → выделение → отмена снимка), клик мимо снимка снова завершает разметку с классификацией `Ignore`/`Spent`/`Finish` | `02b7ea1`, `ed45d7d`; `OverlayEditorWindow.xaml.cs` | `AnnotationCanvasView.swift`, `OverlayEditorController+Keys.swift` | M |
| E-11 | Панель разметки не меняет ширину при смене инструмента и переносит хвост на вторую строку, когда рабочая область уже панели; проба укладки идёт против **синтетического** прямоугольника области, а не живого монитора | `a3ed6f7`, `1134388`; `OverlayEditorWindow.xaml.cs:402-433` | `macos/Sources/SnapBriefMac/Editor/EditorToolbarView.swift`, `EditorGeometry.swift` | M |
| E-12 | Панель комментариев справа (280 px) у повторно открытого снимка с хотя бы одной непустой заметкой; строки берут номера из `CaptureLabels.ForNotedAnnotations`, клик выделяет объект и раскрывает пилюлю без захвата фокуса; список перестраивается только при смене набора заметок | `21aacbd`; `Controls/CommentListEntry.cs` | `macos/Sources/SnapBriefMac/Editor/OverlayContentView.swift` (панель), новый `CommentListEntryView.swift`; часть кода можно взять из удаляемого `Preview/PreviewCommentsPanelView.swift` | M |
| E-13 | Хит-тест перестал хватать лишнее: раздутие габаритов `max(8, thickness/2 + 4)` вместо `max(8, thickness*2)` | `f19154d`; `Controls/AnnotationCanvas.cs` | `AnnotationCanvasView.swift` | S |
| E-14 | Кэш блюра выбирается предикатом «размыто» (`kind == blur` **или** `fill == blur`), а не по виду отметки: иначе при перетаскивании прямоугольника с размытой заливкой весь кадр пересоздаётся на каждом движении | `2e0658b` | `AnnotationCanvasView+Drawing.swift` | S |
| E-15 | Акцент во всём, что рисует редактор и лента, берётся из одного места (`AccentPalette`: замороженный клон, не сам ресурс), два места оказались цветом **отметки** и переведены на `DefaultAnnotationColor`; дефолтный цвет разметки `#2F8CFF` → `#FF3B30` | `AccentPalette.cs:17-55`, `502b6a2`, `2182a0d` | новый `macos/Sources/SnapBriefMac/App/AccentPalette.swift`; `Editor/EditorTheme.swift`, `Imaging/*` | M |
| E-16 | Палитры отметок: три сегмента по 12 цветов — Стандартная, Пастель, **Своя**; «Своя» = 12 сохранённых слотов (новый цвет в первый слот, дубль поднимается, ряд дорисовывается пустыми), `PaletteFor(settings)` вместо мутируемого статического поля | `OverlayEditorWindow.Appearance.cs:55-95, 480, 542` | `macos/Sources/SnapBriefMac/Editor/EditorAppearancePopover.swift` | M |
| E-17 | Спектр цвета: hue-полоса 16 px и квадрат S/V 160×160 двумя слоями, двусторонняя синхронизация с HEX; `ColorConversion.HsvToRgb`/`RgbToHsv` | `Controls/ColorSpectrum.xaml(.cs)`, `Imaging/ColorConversion.cs:12-60` | новые `macos/Sources/SnapBriefCore/Editing/ColorConversion.swift` (чистая математика, тестируется) и `macos/Sources/SnapBriefMac/Editor/ColorSpectrumView.swift` | L |
| E-18 | Пипетка: цвет берётся из копии экрана, снятой **до** показа оверлея (оверлею нужна альфа, и чтение сквозь него занижает каждый канал), работает на любом мониторе, Esc отменяет | `Controls/ScreenColorPicker.cs`, `ac94ad9` | новый `macos/Sources/SnapBriefMac/Editor/ScreenColorPicker.swift` (`CGWindowListCreateImage`/`SCScreenshotManager`, поповер прячется на время) | M |
| E-19 | Шпаргалка клавиш и подсказки с капсулами: `EditorShortcuts.Tools` (10 инструментов) и `Actions` (7 действий) | `EditorShortcuts.cs:20-45`, `1e4fa12` | `macos/Sources/SnapBriefMac/Editor/EditorStrings.swift`, `HintChipView.swift` (клавиши Cmd вместо Ctrl, раздел 4) | S |
| E-20 | Бейдж заметки и выноска считаются одной геометрией для экрана и экспорта (`NoteBadgeGeometry.Screen`/`Export`/`TryLeader`) | `Imaging/NoteBadgeGeometry.cs:14-60` | новый `macos/Sources/SnapBriefMac/Imaging/NoteBadgeGeometry.swift` | S |

### 1.5 Settings

| # | Что | Windows-источник | Целевой Swift-файл | Объём |
|---|---|---|---|---|
| G-1 | Токены темы: **[ТЗ№4 B1]** шесть палитр вместо семи — `dark`, `glass`, `night`, `sunset`, `sea`, `dawn` (карточка «Светлая · Рассвет»). Палитра `light` не заводится вовсе, значение `"light"` в старом файле гасится в `dark`. 14 ключей в каждой: `SurfaceBrush`, `SurfaceBarBrush`, `SurfaceLineBrush`, `ElevatedBrush`, `ElevatedLineBrush`, `HoverBrush`, `PressedBrush`, `DividerBrush`, `TextBrush`, `TextMutedBrush`, `TextFaintBrush`, `ShadowColor`, `ShadowOpacity`, `DangerBrush`. Значения — таблица §B1 ТЗ №4; «Стекло» — матовый градиент варианта B (§B2), без размытия | 1.4.0: `Themes/Palettes/*.xaml`, `ThemeService.cs:15-70`; целевое: §B1, §B2 | `macos/Sources/SnapBriefMac/App/Theme.swift:11-52` переписывается: вместо `LightTheme`/`DarkPalette` — `ThemePalette` (6 штук) и `ThemeService` | L |
| G-2 | Токены акцента: **[ТЗ№4 A5]** двенадцать акцентов вместо восьми, порядок и значения — таблица §A5 (`blue`, `teal`, `violet`, `coral`, `rose`, `cyan`, затем градиентные `blue-violet`, `orange-rose`, `green-cyan`, `amber-pink`, `rose-violet`, `cyan-blue`). 8 ключей в каждом, включая `AccentFlatColor` (у градиентных — первый стоп). Разделитель ряда ставится **перед первым градиентным по признаку**, а не по имени | 1.4.0: `Themes/Accents/*.xaml` (8 штук); целевое: §A5 | `macos/Sources/SnapBriefMac/App/Theme.swift`, `AccentPalette.swift` | M |
| G-3 | Окно настроек: четыре вкладки (Общие, Клавиши, Сохранение, **Вид**), язык сегментом вместо выпадающего списка, тултип у каждой строки «Общих» и «Сохранения», закрытие без сохранения возвращает тему и акцент, с которыми окно открыли | `HotkeySettingsWindow.xaml(.cs)`, `2f7e252` | `macos/Sources/SnapBriefMac/Settings/SettingsTabViews.swift`, `HotkeySettingsWindowController.swift` | M |
| G-4 | `AppearancePicker` — один контрол на мастер и настройки: галерея карточек тем (шаг 142 px, шевроны по одной карточке, гаснут на краях, при открытии стоит на первой, выбранная подсвечена рамкой), ряд кружков акцентов 28 px с разделителем, пример «так будут выглядеть отметки», строка «Палитра отметок» по флагу; живой предпросмотр делает сам, ничего не сохраняет; превью карточки рисуется из словаря, который карточка представляет | `Controls/AppearancePicker.xaml(.cs):29-345`, `1b9fe9c`, `a2f72e1`; целевое: §A4 | новый `macos/Sources/SnapBriefMac/Settings/AppearancePickerView.swift` | L |
| G-5 | **[ТЗ№4 A4]** Галерея листается колесом и горизонтальным жестом трекпада, не только шевронами; последний шаг заканчивается так, что последняя карточка видна целиком | целевое: §A4 | `AppearancePickerView.swift` (`scrollWheel`, `NSEvent.hasPreciseScrollingDeltas`) | S |
| G-6 | Правила клавиш подключены живьём: системное сочетание и сочетание соседнего поля отвергаются с красной рамкой и текстом, запись продолжается, старое остаётся; сохранение блокируется, когда обе клавиши включены и жест один; поле знает о соседях через `conflictsWith` | `Controls/HotkeyField.xaml.cs:119-138`, `HotkeySettingsWindow.xaml.cs:287-288, 380-406` | `macos/Sources/SnapBriefMac/Settings/HotkeyRecorderField.swift`, `HotkeySettingsWindowController.swift` | M |
| G-7 | Клавиша «весь экран» по умолчанию выключена, поле показывает «Не назначено», рядом чип «Предложить: {сочетание}» из `HotkeyRules.SuggestFree`; клик включает и подставляет; отказ регистрации двигает чип к следующему кандидату | `HotkeySettingsWindow.xaml.cs:19-22, 246-249, 439`, `8bc4adc` | `HotkeyRecorderField.swift`, `SettingsTabViews.swift` | M |
| G-8 | Из настроек убраны строки «Предлагать ту же область» и «Показывать курсор»; поля `RememberRegion` и `CaptureCursor` остаются в модели и переносятся при записи нетронутыми | `a1d5557`; `HotkeySettingsWindow.xaml:33-34` | `SettingsTabViews.swift` | S |
| G-9 | Тумблер автозапуска в «Общих» — тот же сервис, что в мастере и в меню строки состояния; при недоступности — серый с объяснением | `ee7f772`, `499efe8` | `macos/Sources/SnapBriefMac/App/LaunchAtLoginService.swift` уже есть — подключить к настройкам и мастеру | S |
| G-10 | Громкость звуков (`SoundVolume`, 0..100) отдельным ползунком; три звука вместо двух (затвор, тик, «скопировано») с разными гейнами | `UiSoundService.cs:15-60`, `8f27e90`, `c42bc19`, `00b6250` | `macos/Sources/SnapBriefMac/App/CaptureFeedbackSound.swift` → переименовать в `UiSoundService.swift`, добавить третий звук и громкость | M |
| G-11 | Аудиоресурсы заменены: `camera-shutter.wav` и `camera-dial-click.wav` уходят, приходят `shutter-1-039s.mp3` (гейн 0.6), `click-tiny-005s.mp3` (0.25), `notify-soft-040.mp3` (0.7); провенанс в `Assets/Audio/README.md` | `src/SnapBrief.App/Assets/Audio/`, `cffdf24`, `00b6250` | `macos/Sources/SnapBriefMac/Resources/Audio/` (заменить два wav на три mp3, править `Package.swift`/`project.yml`) | S |
| G-12 | Окно «Сохранить пакет»: папка, имя, галочка «Создать подпапку», проверка имени и свободного имени; `PackageSaveDirectory`, `PackageCreateSubfolder` | `SavePackageWindow.xaml(.cs)`, `30d0435` | новый `macos/Sources/SnapBriefMac/Settings/SavePackageSheet.swift` | M |
| G-13 | **[ТЗ№4 E2]** В «Общих» ссылка «Пройти знакомство заново» — открывает полный мастер с текущими значениями; «Начать» записывает изменённое, «Пропустить» не трогает ничего. Дубля в меню строки состояния не заводить | целевое: §E2 | `SettingsTabViews.swift` → `AppCoordinator.swift` | S |

### 1.6 Onboarding (мастера в Mac-порте нет вовсе — подсистема новая)

| # | Что | Windows-источник | Целевой Swift-файл | Объём |
|---|---|---|---|---|
| O-1 | Окно мастера: обычное окно, не поверх всех, с собственной шапкой «SnapBrief · — · ×», открывается по центру монитора с курсором, `MaxHeight` = рабочая область минус 40, содержимое в прокрутке при закреплённых шапке и низе. **[ТЗ№4 A1/A2]** На Mac скругление и тень даёт система, второго контура рисовать не надо; перетаскивание — весь верхний пояс (`isMovableByWindowBackground` + `NSWindow` titlebar accessory), а не полоса 28 px | `OnboardingWindow.xaml(.cs):1-120`, `6112b42`; целевое: §A1, §A2 | новый `macos/Sources/SnapBriefMac/Onboarding/OnboardingWindowController.swift` | L |
| O-2 | Пять шагов (`Step1..Step5`), `CurrentVersion = 3`, переключатель языка только на первом, «Пропустить настройку» текстом внизу слева на всех пяти; `SuggestedLanguage(settingsFileExists, settings, cultureLanguage)` — локаль спрашивается только у машины без файла настроек и без пройденного мастера; `LanguageForCulture` = `ru` только для `ru` | `OnboardingWindow.xaml.cs:21-22, 129-148`, `a1e3870`, `2e0658b` | `OnboardingWindowController.swift` | M |
| O-3 | Шаг 1 «Добро пожаловать» со сценой «клавиша → снимок → чат»: мок-скриншот 210×180, стрелка, окно чата 206×180, печатающиеся метки A1/A2, чип с клавишей вставки. Тот же контрол — первый слайд шага 5 | `Controls/CaptureSceneSmall.xaml(.cs)`, `be5659b` | новый `macos/Sources/SnapBriefMac/Onboarding/CaptureSceneSmallView.swift` | M |
| O-4 | Шаг 2 «Клавиша»: поле записи с капсулами клавиш, подпись «Нажми, чтобы изменить», правила из `HotkeyRules` (красное «Уже занято», «Это сочетание занято системой», чип «Предложить»); выключенная клавиша «весь экран» отказом не считается | `OnboardingWindow.xaml:111-115`, `719cd9a`, `ac94ad9` | `OnboardingWindowController.swift` + `Settings/HotkeyRecorderField.swift` | M |
| O-5 | Шаг 3: карточка автозапуска с тумблером 40×22 и карточка «Закрепить». **На Mac пункт «закрепить» не нужен** — см. раздел 4; карточка остаётся одна, автозапуск | `OnboardingWindow.xaml:117-167`, `499efe8`, `f445aa9` | `OnboardingWindowController.swift`, `App/LaunchAtLoginService.swift` | S |
| O-6 | Шаг 4 «Вид»: врезка `AppearancePicker` шириной 520 при окне 620, `ShowPaletteRow = false`; пара тема+акцент запоминается при входе и возвращается по «Пропустить настройку», по закрытию окна и по Alt+F4-эквиваленту | `OnboardingWindow.xaml` (`Step4`), `52e7dfe`, `ac94ad9` | `OnboardingWindowController.swift` + `Settings/AppearancePickerView.swift` | S |
| O-7 | Шаг 5: четыре слайда, цикл 9 с, подписи накапливаются вертикальным списком с кружками, листалка точками и шевронами, стрелки Left/Right листают только слайды и на краях ничего не делают, ручное листание выключает автопрокрутку навсегда, при выключенных системных анимациях ставится конечный кадр. **[ТЗ№4 A6]** Блок подписей фиксированной высоты под четыре строки по 30 px (120 px), точки стоят на одном месте на всех четырёх слайдах, прокрутки в мастере на шаге 5 нет | `Controls/HowToSlides.xaml(.cs)`, `1ce5c05`, `1b8f569`, `7611630`; целевое: §A6 | новый `macos/Sources/SnapBriefMac/Onboarding/HowToSlidesView.swift` | L |
| O-8 | Режим «только слайды» из меню строки состояния (`howToOnly: true`): открывается сразу пятый шаг, кнопка «Готово» | `OnboardingWindow.xaml.cs:54-85`, `efbeb4f` | `OnboardingWindowController.swift`, `App/StatusBarController.swift` | S |

### 1.7 Smoke / CI

| # | Что | Windows-источник | Целевой Swift-файл | Объём |
|---|---|---|---|---|
| K-1 | Проба палитр: наборы ключей всех шести палитр и всех двенадцати акцентов совпадают; неизвестная тема гасится в `dark`; `AccentPalette` отдаёт замороженный клон, а не сам ресурс; акцент читается как кисть, не кастуется в сплошной цвет (градиент уронил бы прогон) | `SmokeTestRunner.cs:160-172`, `ac94ad9` | `macos/Sources/SnapBriefMac/App/SmokeTestRunner.swift` | M |
| K-2 | Пробы редактора: `lineStyle` доезжает до PNG и переживает копию; «Комментарий» остаётся активным после булавки и снимается Esc; в пилюле нет второго номера; жесты, курсоры, ластик, кэш блюра; кегль надписи одинаков на экране и в экспорте | `SmokeTestRunner.cs`, `Controls/AnnotationCanvas.cs` (`VerifyGestureRules`, `VerifyBlurCache`) | `macos/Sources/SnapBriefMac/Editor/OverlayEditorController+SmokeTest.swift` | M |
| K-3 | Пробы ленты и мастера: лимит 26 и мягкое предупреждение, ширина/высота против рабочей области, капсула, пять шагов и «Шаг 5 из 5», режим только слайдов, обратный перевод новых строк без дублей, кириллический свип | `SmokeTestRunner.cs:216-265, 744-846` | `SmokeTestRunner.swift` | M |
| K-4 | Проверка уникальности английских значений в `UiLanguage`: обратный перевод идёт поиском по значению, дубль не ломает сборку и ловится только пробой | `UiLanguage.cs:129-132`, правило `tz-004-plan.md` §5 | `SmokeTestRunner.swift` + отдельный тест в `macos/Tests/SnapBriefCoreTests` | S |
| K-5 | `ci-smoke.sh` не трогается по структуре; в `--smoke-test` добавляются коды выхода новых проб; закрепление в Dock в пробе не выполняется | `macos/scripts/ci-smoke.sh:17-21` | там же | S |

---

## 2. Изменения формата данных

Все аддитивные. Версия схемы сессии остаётся **1**, `SettingsVersion` — **1**. Источник: абзацы «Изменение формата» в `tasks/verification.md:146-800`.

### 2.1 `session.json`

| Поле | Тип и дефолт | Правило | Источник |
|---|---|---|---|
| `captures[].sent` | bool, `false` | снимок уже уехал в пакете: остаётся в ленте, в следующий пакет не идёт, буквы получают только неотправленные | `verification.md:284` |
| `annotations[].noteOffset` | `{x, y}` или `null` | сдвиг номерного бейджа в долях размера снимка; **может быть отрицательным и вне картинки**, валидация требует только конечности; кроп делит на ширину и высоту кропа, ресайз масштабирует вместе с точками | `verification.md:476` |
| `annotations[].shape` | `"rectangle"` \| `"rounded"` \| `"ellipse"`, деф. `rectangle` | независимое свойство рамки; применяется и к `kind: "blur"` | `verification.md:488, 602` |
| `annotations[].fill` | `"none"` \| `"solid"` \| `"translucent"` \| `"blur"`, деф. `none` | четвёртое значение `blur` — совместимость только вперёд | `verification.md:488, 588` |
| `annotations[].fillColor` | строка `#AARRGGBB` или отсутствует | отсутствие = «цвет рамки» | `verification.md:590` |
| `annotations[].hasOutline` | bool, деф. `true` | **[ТЗ№4 D1]** поле остаётся в схеме ради чтения старых файлов, но переключателя в интерфейсе не будет: `hasOutline: false` читается как «сплошная заливка одним цветом». Писать всегда `true` — см. раздел 5 | `verification.md:592`, `TZ-004 §D1` |
| `annotations[].fontSize` | число, деф. 20, кламп 8..96 | кегль надписи в пикселях снимка; `thickness` у надписи больше ни на что не влияет; вторая точка текстовой отметки — вычисленный размер надписи, а не то, что провела рука | `verification.md:662` |
| `annotations[].lineStyle` | `"solid"` \| `"dashed"` \| `"dotted"`, деф. `solid` | узор рамки, овала, стрелки и карандаша; маркер, текст, размытие и комментарий пишут `solid`; валидация отклоняет значение вне перечисления; узор в толщинах пера | `verification.md:794` |
| `kind: "redaction"` | — | читается как `rectangle` + `fill: solid` + `fillColor: #FF000000` + `hasOutline: false`, при следующем сохранении пишется в новом виде; значение enum сохраняется ради чтения | `verification.md:594` |
| `annotations[].thickness` у `kind: "highlight"` | — | смысл поменялся: теперь это реальная ширина штриха, а не четверть (раньше оба рендерера умножали на 4) | `verification.md:658` |

### 2.2 `settings.json` (все имена PascalCase, как на Windows)

Новые ключи относительно `macos/Sources/SnapBriefCore/Settings/HotkeySettings.swift:170-185`:

`SettingsVersion` (int, 0, текущее 1) · `StackTopmost` (bool, true) · `StackWidth` (double, **224** [ТЗ№4 C4], на Windows 1.4.0 — 208) · `StackHeight` (double, 372, высота **списка**, не окна) · `ClearStackAfterPaste` (bool, false) · `ConfirmSessionDiscard` (bool, true) · `SoundVolume` (int 0..100, **40**) · `AnnotationColor` (string, **`#FF3B30`**) · `AnnotationThickness` (double, 4, кламп 1..16) · `AnnotationHighlightThickness` (double, 16, кламп 4..48) · `AnnotationFontSize` (double, 20, кламп 8..96) · `AnnotationShape` (string, `rectangle`) · `AnnotationFill` (string, `none`) · `AnnotationFillColor` (string, пустая = «цвет рамки») · `AnnotationOutline` (bool, true) · `AnnotationPalette` (string, `standard`; значения `standard`/`pastel`/`custom`, `"neon"` больше не существует и гасится в `standard`) · `AnnotationPencil` (string, `pen`/`highlight`) · `CustomPaletteColors` (массив hex, пустой, не длиннее **12**, невалидный hex выбрасывается) · `PackageSaveDirectory` (string, пустая = папка быстрого сохранения) · `PackageCreateSubfolder` (bool, true) · `OnboardingVersion` (int, 0; текущая версия мастера **3**) · `Theme` (string, `dark`) · `AccentId` (string, `blue`).

Изменения существующих:

- `FullscreenSaveId`: дефолт `"custom:4:44"` → **`"custom:7:83"`** (на Mac — эквивалент Cmd+Option+Shift+S, раздел 4). Уже записанное значение читается как записано.
- `JpegQuality`: дефолт **90 → 92** (в абзацах «Изменение формата» не описан, найден по коду: `HotkeySettingsWindow.xaml.cs:73` против `mac-sync-base-2`). Свериться с Windows перед переносом.
- `Theme` принимает шесть значений (**[ТЗ№4 B1]**, на Windows 1.4.0 их семь): `dark`, `glass`, `night`, `sunset`, `sea`, `dawn`; `light` и любое неизвестное гасятся в `dark`.
- `AccentId` принимает двенадцать значений (**[ТЗ№4 A5]**, на Windows 1.4.0 их восемь): `blue`, `teal`, `violet`, `coral`, `rose`, `cyan`, `blue-violet`, `orange-rose`, `green-cyan`, `amber-pink`, `rose-violet`, `cyan-blue`; неизвестное гасится в `blue`. Стопы градиентов в файл не пишутся — только идентификатор.
- `SoundVolume`: разовая миграция при чтении — файл с `SettingsVersion < 1` и ровно `SoundVolume == 60` получает 40 и версию 1 и сразу переписывается на диск; любое другое значение громкости не трогается. Чтение само по себе файл не пишет: писать только на старте приложения (`LoadAndMigrate`), а не на каждый снимок.

### 2.3 `manifest.json` и `prompt.md`

- `images[].fileName` = `01-A.png` (двузначный номер и буква) вместо `A_<guid>.png`; GUID остаётся в `images[].captureId`, имя обратно нигде не разбирается.
- Пакет без текста: `prompt.md` не пишется вовсе, `promptFileName` и `promptSha256` — пустые строки, `promptText` пустой. Читатель манифеста обязан допускать пустое имя файла.
- Метки снимков продолжаются после Z (`AA`, `AB`), но потолок ленты 26 до этого не пускает.

### 2.4 ID горячих клавиш

Формат `custom:{modifiers}:{virtualKey}` не меняется, меняются правила чтения (`verification.md:692`):

- Значение без модификаторов (`custom:0:<vk>`) невалидно для всего, кроме Print Screen (`0x2C`) и Pause (`0x13`).
- Значение, у которого основная клавиша сама модификатор (`0x10`, `0x11`, `0x12`, `0x5B`, `0x5C`, `0xA0`..`0xA5`), отвергается при любых модификаторах.
- На невалидный id `Find` отдаёт **дефолт того сочетания, для которого он читался** (`ctrl-alt-s` для захвата, `ctrl-alt-v` для вставки, `custom:7:83` для снимка экрана), а не первый элемент списка: иначе битый `FullscreenSaveId` делал три сочетания одним.
- Битый id лечится в самом файле один раз при старте, а не только в памяти.
- **[ТЗ№4]** чёрный список системных сочетаний: на Mac вместо Win-ветки — всё с Cmd+Tab, Cmd+Q, Cmd+Space, Cmd+Option+Esc, Ctrl+Cmd+Q, F11/F12 системных; голый Print Screen аналога не имеет. Список фиксируется в `HotkeyRules.swift` вместе с очередью кандидатов `SuggestFree`.

### 2.5 Контракты Core (не формат файла)

- `SentCaptureRules.MaxStripCaptures = 26`, `SoftStripWarning = 20` — оба обязательны, иначе ленты Windows и macOS разойдутся по вместимости.
- `StripResizeGeometry`: `MinimumWidth = 200` (**[ТЗ№4 C4]** поднимается до 224 вместе с `DefaultWidth`), `MinimumListHeight = 180`, `DefaultListHeight = 372`, `EdgeGap = 10` (**[ТЗ№4 C6]** поле под тень окна 20), `EstimatedChromeHeight = 140`; потолков-констант нет, потолок — рабочая область монитора.
- Жизненный цикл каталога сессий: на старте сносятся все GUID-каталоги и `current-session.txt`, прошлая сессия не восстанавливается, «Очистить ленту» и выход сносят каталог текущей сессии целиком, предварительно отдав буфер, если в нём наша запись. Схема `session.json` при этом не меняется.

---

## 3. `UiLanguage`: diff ключей

Сверка `src/SnapBrief.App/UiLanguage.cs:15-214` (278 пар) против `macos/Sources/SnapBriefCore/Settings/UiLanguage.swift:12-125` (91 пара). Порядок — как в Windows-файле: обратный перевод идёт поиском по значению, английские значения обязаны быть уникальны.

### 3.1 Новые пары: 213

**Настройки: общие строки и тултипы (13)**

`Показывать уведомления` = Show notifications · `Предлагать ту же область, что в прошлый раз` = Offer the same area as last time · `Показывать курсор мыши на скриншоте` = Show the mouse pointer in the screenshot · `Звуки` = Sounds · `Громкость` = Volume · `Всплывающее окно у часов: «Скопировано», «Сохранено»` = A pop-up by the clock: "Copied", "Saved" · `Щелчок затвора при снимке и тихие тики ленты` = The shutter click on a capture and the quiet ticks of the strip · `Насколько громко звучит интерфейс` = How loud the interface sounds are · `После Ctrl+V лента очищается сама, снимки удаляются` = After Ctrl+V the strip clears itself and the captures are deleted · `Каждый готовый снимок сразу ложится в папку сохранения` = Every finished capture goes straight into the save folder · `JPEG легче, PNG точнее` = JPEG is lighter, PNG is sharper · `Куда падают снимки и пакеты` = Where the captures and the packages land · `Открывать при включении компьютера` = Open when the computer starts

**Вид: темы, акценты, галерея (25)**

`Вид` = Appearance · `Акцент` = Accent · `Акцент: {0}` = Accent: {0} · `синий` = blue · `фиолетовый` = violet · `зелёный` = green · `оранжевый` = orange · `сине-фиолетовый` = blue to violet · `оранжево-розовый` = orange to rose · `зелёно-бирюзовый` = green to cyan · `янтарно-розовый` = amber to pink · `Тёмная` = Dark · `Светлая` = Light · `Стекло` = Glass · `Ночь` = Night · `Закат` = Sunset · `Море` = Sea · `Рассвет` = Dawn · `Тема: {0}` = Theme: {0} · `Предыдущая тема` = Previous theme · `Следующая тема` = Next theme · `Тема · фон и панели` = Theme · background and panels · `Цвет · рамки, кнопки, номера отметок` = Color · frames, buttons, marker numbers · `так будут выглядеть отметки` = this is how the marks will look · `Палитра отметок` = Marker palette

**Клавиши (10)**

`Сделать скриншот` = Take a screenshot · `Скриншот всего экрана в папку` = Save the whole screen to a folder · `Качество JPEG: {0} % (меньше, легче файл)` = JPEG quality: {0} % (lower means a smaller file) · `Нажми, чтобы изменить` = Click to change · `Добавь Ctrl, Alt или Shift` = Add Ctrl, Alt or Shift · `Уже занято` = Already taken · `Это сочетание занято Windows` = Windows keeps this shortcut · `Одно сочетание на два действия. Поменяй одно из них.` = One shortcut for two actions. Change one of them. · `Предложить: {0}` = Suggest: {0} · `Не назначено` = Not assigned

**Редактор: инструменты и шпаргалка (7)**

`Ластик` = Eraser · `Сочетания клавиш` = Keyboard shortcuts · `Инструменты` = Tools · `Действия` = Actions · `Отменить снимок` = Cancel the capture · `Закончить заметку` = Finish the note · `Новая строка в заметке` = New line in the note

**Редактор: карандаш, размер, тип линии (8)**

`Карандаш` = Pencil · `Размер` = Size · `Размер шрифта` = Font size · `Линия` = Line · `Тип линии` = Line style · `Сплошная` = Solid · `Пунктир` = Dashed · `Точки` = Dotted

**Редактор: палитры, спектр, пипетка (9)**

`Стандартная` = Standard · `Пастель` = Pastel · `Своя` = Custom · `Оттенок` = Hue · `Насыщенность и яркость` = Saturation and brightness · `Пипетка` = Eyedropper · `Взять цвет с экрана` = Pick a color from the screen · `Сохранённые цвета` = Saved colors · `Выделите область · Esc отменяет` = Select an area · Esc cancels

**Редактор: фигура, заливка, комментарии (16)**

`СНИМОК {0}` = CAPTURE {0} · `Переместить заметку` = Move the note · `Комментарий` = Comment · `Фигура` = Shape · `Прямоугольник` = Rectangle · `Скруглённый прямоугольник` = Rounded rectangle · `Овал` = Ellipse · `Заливка` = Fill · `Контур` = Outline · `Сплошная заливка` = Solid fill · `Полупрозрачная заливка` = Translucent fill · `Заливка размытием` = Blurred fill · `Рамка` = Frame · `Показывать рамку` = Show the frame · `Цвет заливки` = Fill color · `Сохранить на компьютер` = Save to computer

**Лента и капсула (8)**

`Свернуть в капсулу` = Collapse to a capsule · `Развернуть ленту` = Expand the strip · `Показать ленту` = Show the strip · `SnapBrief — Лента снимков` = SnapBrief — Capture strip · `Очистить ленту` = Clear the strip · `Лента очищена` = Strip cleared · `В ленте максимум {0} снимков. Отправьте или удалите лишние` = The strip holds at most {0} captures. Paste or delete some first. · `Чаты обычно принимают до {0} картинок за раз` = Chats usually take up to {0} images at a time

**Диалоги: удаление сессии и сохранение пакета (16)**

`Удалить снимки сессии?` = Delete the captures of this session? · `Снимки этой сессии будут удалены. Чтобы сохранить, нажмите «Сохранить пакет…» в меню •••` = The captures of this session will be deleted. To keep them, use "Save package…" in the ••• menu. · `Больше не спрашивать` = Do not ask again · `Очищать ленту после вставки` = Clear the strip after pasting · `Сохранить пакет` = Save package · `Куда` = Where · `Обзор…` = Browse… · `Имя папки` = Folder name · `Создать подпапку` = Create a subfolder · `В папку лягут снимки и prompt.md, текст с комментариями для ИИ` = The folder takes the captures and prompt.md, the text with the comments for the AI · `Снимки в пакете нумеруются заново: A, B, C…` = The captures in the package are lettered again: A, B, C… · `Укажите имя папки.` = Enter a folder name. · `В имени папки есть недопустимые символы.` = The folder name contains characters that are not allowed. · `Этот путь не подходит. Выберите папку кнопкой обзора.` = This path cannot be used. Choose the folder with the browse button. · `В этой папке нет свободного имени для пакета. Выберите другую папку.` = There is no free name for the package in this folder. Choose another folder. · `Не удалось сохранить пакет` = Could not save the package

**Тосты, статусы и ошибки (45)**

`Вставлено: {0} изображений · {1} заметок. Снимки помечены как отправленные` = Pasted: {0} images · {1} notes. The captures are marked as sent · `Изображения` = Images · `Все файлы` = All files · `Все поддерживаемые` = All supported · `Выберите PNG или JPEG.` = Choose PNG or JPEG. · `Добавлено снимков: {0}` = Captures added: {0} · `Изображение добавлено.` = Image added. · `В буфере нет изображения.` = There is no image on the clipboard. · `Не удалось добавить` = Could not add · `Формат не поддерживается системой` = The system does not support this format · `Поверх других окон` = Always on top · `Не удалось сохранить настройки` = Could not save the settings · `Файл настроек не читается.` = The settings file cannot be read. · `Файл настроек не читался, настройки созданы заново` = The settings file could not be read, the settings were created anew · `Снимок удалён` = Capture removed · `Снимок восстановлен.` = Capture restored. · `Порядок снимков изменён.` = Capture order changed. · `Пакет сохранён.` = Package saved. · `Готово: {0} изображений · {1} заметок` = Ready: {0} images · {1} notes · `Не удалось изменить автозапуск` = Could not change the startup setting · `Не удалось восстановить сессию` = Could not restore the session · `Захват` = Capture · `Отслеживание вставки недоступно` = Paste tracking is unavailable · `Сочетание занято` = The shortcut is taken · `захват` = capture · `сохранение экрана` = screen saving · `Не удалось подтвердить содержимое текущего пакета. Сессия сохранена.` = Could not confirm what the current package holds. The session was saved. · `Вставка замечена, но лента не обновлена` = The paste was noticed, but the strip was not updated · `Захват не завершён` = The capture did not finish · `Сначала сделайте снимок.` = Take a capture first. · `Все снимки уже отправлены. Сделайте новый снимок.` = Every capture was already sent. Take a new one. · `Регистрация клавиш недоступна. Перезапустите SnapBrief.` = Shortcut registration is unavailable. Restart SnapBrief. · `Эта клавиша уже занята. Освободите её в другом приложении или выберите другую.` = This shortcut is already taken. Free it in the other application or pick another one. · `Не удалось назначить сочетание. Возможно, оно уже занято — нажмите другое.` = Could not assign the shortcut. It may already be taken — press another one. · `Готовим PNG и текст…` = Preparing the PNG and the text… · `Не удалось подготовить` = Could not prepare · `Снимок сохранён, но буфер не обновлён` = The capture was saved, but the clipboard was not updated · `Повторите копирование через меню.` = Copy the package again from the menu. · `Вставка остановлена` = Pasting stopped · `Не удалось выполнить действие` = Could not run the action · `PNG и текст скопированы. Если получатель выберет один формат, используйте кнопку вставки.` = The PNG and the text were copied. If the receiver takes only one format, use the paste button. · `PNG и текст скопированы.` = The PNG and the text were copied. · `Не удалось сохранить` = Could not save · `Не удалось очистить ленту` = Could not clear the strip · `Буфер не обновлён` = The clipboard was not updated

**Мастер: кнопки, шаги, карточки (37)**

`Шаг {0} из {1}` = Step {0} of {1} · `Назад` = Back · `Далее` = Next · `Начать` = Get started · `Пропустить` = Skip · `Свернуть` = Minimize · `Пропустить настройку` = Skip setup · `Выдели. Прокомментируй. Отправь.` = Select. Comment. Send. · `Скриншотер для одной задачи: несколько снимков с заметками — и сразу в дело. В чат с ИИ, в мессенджер, в письмо, в задачу.` = A screenshot tool for one task: a few captures with notes, ready to use straight away. In an AI chat, a messenger, an email, a ticket. · `Кнопку ярче` = Make the button brighter · `Убрать блок` = Drop this block · `Чат` = Chat · `Снимок A` = Capture A · `Снимок B` = Capture B · `Снимок C` = Capture C · `Как на первом` = Same as the first one · `Текст…` = Message… · `Чтобы всегда был под рукой` = So it is always at hand · `Два переключателя — и SnapBrief не придётся искать.` = Two switches, and you will never have to look for SnapBrief. · `Ждёт в углу экрана, клавиша работает сразу` = It waits in the corner of the screen, the shortcut works right away · `Иконка внизу экрана, клик открывает ленту` = An icon at the bottom of the screen, a click opens the strip · `Закрепить` = Pin · `Закреплено` = Pinned · `Готово: иконка SnapBrief теперь на панели задач` = Done: the SnapBrief icon is on the taskbar now · `Открой «Пуск»` = Open Start · `Нажми правой кнопкой на SnapBrief` = Right-click SnapBrief · `Выбери «Закрепить на панели задач»` = Choose "Pin to taskbar" · `Как будет выглядеть` = How it will look · `Нажми — окно сразу перекрасится. Поменять можно в любой момент в настройках.` = Click and the window repaints at once. You can change it any time in the settings. · `Язык интерфейса` = Interface language · `Клавиша для снимка` = The capture shortcut · `Нажми на поле и введи своё сочетание` = Click the field and press your own shortcut · `Автозапуск недоступен` = Autostart is unavailable · `Закрепить на панели задач` = Pin to taskbar · `Как пользоваться` = How it works · `Предыдущий слайд` = Previous slide · `Следующий слайд` = Next slide

**Слайды (19)**

`Слайд {0} из {1}` = Slide {0} of {1} · `Снимок с комментариями` = A capture with comments · `Несколько снимков сразу` = Several captures at once · `Открыть снимок снова` = Open a capture again · `Лента снимков` = The capture strip · `Выдели область экрана, которую хочешь снять.` = Select the part of the screen you want to capture. · `Поставь комментарии там, где удобно — сколько нужно.` = Put comments wherever you like, as many as you need. · `Ctrl+V в любой чат — картинка и комментарии вставятся вместе.` = Ctrl+V into any chat, and the picture and the comments go in together. · `Сделай несколько снимков подряд.` = Take several captures one after another. · `Все они собираются в ленту у края экрана.` = They all gather into the strip at the edge of the screen. · `У каждого — свои комментарии.` = Each one keeps its own comments. · `Ctrl+V — и вся пачка уходит одним сообщением.` = Ctrl+V, and the whole batch goes as one message. · `Каждый снимок хранит свои комментарии.` = Every capture keeps its own comments. · `Клик по снимку в ленте — он открывается снова, всё на месте.` = Click a capture in the strip and it opens again, with everything in place. · `Поправь и закрой — изменения останутся в ленте.` = Fix it and close it, the changes stay in the strip. · `Лента живёт, пока открыта. Закроешь — снимки удалятся.` = The strip lives while it is open. Close it and the captures are gone. · `Сохранить — «Сохранить пакет…», или включи автосохранение в папку.` = To keep them, use "Save package…", or switch on auto-saving to a folder. · `Мешает — сверни в капсулу, клик разворачивает обратно.` = In the way? Collapse it into the capsule, a click opens it again. · `Лишний снимок — крестик. Всё сразу — «Очистить».` = One capture too many: the cross. All of them: "Clear".

### 3.2 Изменённые значения: 2

- `Цвет HEX`: было `Color HEX`, стало **`HEX color`**.
- `Настройки клавиш`: было `Settings` (дубль с `Настройки`), стало **`Shortcut settings`**.

### 3.3 Пары, которых на Windows больше нет: 26

Из окна предпросмотра, удалённого целиком (`Просмотр снимка`, `По размеру окна`, `Увеличить`, `Уменьшить`, `На весь экран`, `Вернуть размер`, `Разметка`, `Закрыть просмотр`, `Показать стопку`, `Новая сессия`, длинный тост «Пакет остаётся в буфере…»); из переименованных строк настроек (`Уведомления о копировании и сохранении`, `Запоминать последнюю область`, `Захватывать курсор`, `Звуки захвата и стопки`, `Захват области`, `Быстро сохранить весь экран`, `Качество JPEG`, `Нажмите клавишу…`); из редактора (`Перо` → `Карандаш`, `Скрыть`, `Ещё инструменты`, `Цвет и толщина`, `Добавить комментарий (N)`, `Закрыть ввод текста`, `Сохранить на компьютер (Ctrl+S)`).

Удалять их можно только вместе с кодом, который на них ссылается (окно предпросмотра — пункт S-1). До этого момента они остаются лишними, но безвредными.

### 3.4 Что ТЗ №4 ещё изменит в этом списке

Эти пары Mac заводит **сразу в целевом виде**, не повторяя 1.4.0:

| Пара 1.4.0 | Целевое состояние по ТЗ №4 |
|---|---|
| `Светлая` = Light | карточки «Светлая» нет (§B1). Вместо неё пара `Светлая · Рассвет` = `Light · Dawn` на карточке `dawn`; `Рассвет` = Dawn остаётся идентификатором темы |
| `Скриншот всего экрана в папку` | `Снимок всего экрана` = `Whole-screen capture` (§C8, §E1) |
| `Показывать рамку` = Show the frame | пары нет вовсе: переключатель убирается вместе с `HasOutline` (§D1) |
| восемь названий акцентов | двенадцать: добавляются `розовый` = rose, `бирюзовый` = cyan, `розово-фиолетовый` = rose to violet, `бирюзово-синий` = cyan to blue (§A5) |
| `Это сочетание занято Windows` | на Mac — `Это сочетание занято системой` = `The system keeps this shortcut`; `Добавь Ctrl, Alt или Shift` → `Добавь Cmd, Option или Shift` (раздел 4) |
| — | новые пары ТЗ №4, которых на Windows ещё нет: `Пройти знакомство заново` (§E2), чип `экран` и подписи масштаба (§C8) — заводятся на этапе 1.5.0, раздел 5 |

---

## 4. Что не переносится и почему

| Windows | Решение для macOS |
|---|---|
| `DwmSetWindowAttribute` (`DWMWA_WINDOW_CORNER_PREFERENCE`, `DWMWA_SYSTEMBACKDROP_TYPE`), `WindowChrome`, `AllowsTransparency`, вся возня с чёрными углами и вторым контуром (`OnboardingWindow.xaml:1-9`, ТЗ №4 §A1) | Не переносится. `NSWindow` со стилем `.titled` скругляется и отбрасывает тень системой. Внутреннего `Border` со своим скруглением **не рисовать вовсе** — именно от него на Windows двойной контур. Для ленты и капсулы: `NSWindow(.borderless)` + `NSVisualEffectView`/свой слой, скругление на `contentView.layer.cornerRadius` |
| `SetWindowDisplayAffinity(hwnd, WDA_EXCLUDEFROMCAPTURE)` (`EdgeStackWindow.xaml.cs:244`) | `NSWindow.sharingType = .none` в `macos/Sources/SnapBriefMac/App/WindowCaptureExclusion.swift`. **[ТЗ№4 C7]** постоянно его не держать: по умолчанию `.readOnly`, `.none` ставится только на время нашего захвата и снимается сразу после |
| Закрепление на панели задач: `IPinnedList3`, WinRT `TaskbarManager`, AUMID `YesWorkflow.SnapBrief`, `SetCurrentProcessExplicitAppUserModelID`, `AppUserModelID` у ярлыков установщика (`TaskbarPinService.cs:19-120`, `installer/SnapBrief.iss`) | Не переносится. В Dock приложение есть всегда, пока запущено, а «оставить в Dock» пользователь делает сам через контекстное меню иконки — отдельной кнопки не нужно. Карточка «Закрепить» из шага 3 мастера убирается, остаётся одна карточка автозапуска (пункт O-5). Программную запись в `com.apple.dock persistent-apps` **не делать**: она требует перезапуска Dock и на sandboxed-сборке недоступна. Эквивалент AUMID — `CFBundleIdentifier`, он уже есть |
| Реестр `HKCU\...\Run\SnapBrief` и `WindowsStartupService` | `SMAppService.mainApp` (`macos/Sources/SnapBriefMac/App/LaunchAtLoginService.swift`, уже есть). Ветка «реестр закрыт» → «системная политика запрещает» с той же строкой «Автозапуск недоступен» |
| Шрифт иконок Segoe Fluent Icons / Segoe MDL2 Assets; **[ТЗ№4 D2]** правило «только стандартные глифы» | SF Symbols: `eyedropper`, `trash`, `pin`, `minus`, `display`, `doc`, `bubble.left`, `ellipsis`, `camera`. Правило то же: своих пиктограмм «по мотивам» не рисовать. Часть путей уже лежит в `macos/Sources/SnapBriefMac/Editor/IconPath.swift` — заменить на SF Symbols там, где системный глиф существует |
| Модификатор Ctrl и виртуальные коды Win32 в подписях и правилах клавиш | Cmd/Option в подписях (`Cmd + Option + S`), но **числовой формат id `custom:{modifiers}:{virtualKey}` не меняется** — он общий с Windows и уже так работает (`macos/Sources/SnapBriefCore/Settings/HotkeySettings.swift:7-17, 123-150`). Чёрный список системных сочетаний свой (раздел 2.4) |
| Семейство шрифта `Segoe UI Variable Text` в `TextMarkMetrics` (`TextMarkMetrics.cs:13`) | `SF Pro Text` (`NSFont.systemFont`). **Важно:** метрики разойдутся, поэтому число в `TextMarkMetrics.Measure` сверять не с Windows, а с собственным экспортом: инвариант — «коробка чернил холста и экспортного рендерера совпадают с точностью 2 px», а не «то же число, что на Windows» |
| `MediaPlayer` и `pack://application` (`UiSoundService.cs`) | `NSSound`/`AVAudioPlayer` с громкостью; файлы — ресурсы бандла, как сейчас |
| Установщик Inno Setup, `installer/SnapBrief.iss`, страница «Дополнительные значки», очистка `Run` при деинсталляции | Не переносится: на macOS это DMG из `.github/workflows/macos-build.yml` |
| `IPinnedList3`-ресёрч, `tasks/tz-004-details/research-taskbar-pin.md` | Читать только §6 (там описан Dock-эквивалент), остальное — Win32 |
| `Panel.ZIndex`, `AlternationIndex`, `VirtualizationMode="Recycling"`, `StripDepthConverter` | **[ТЗ№4 C1]** не переносятся вовсе: целевой порядок ленты — порядок данных. Ни ZIndex-эквивалента, ни виртуализации на Mac не заводить |
| `RenderCapability.Tier`, `SystemParameters.ClientAreaAnimation` | `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` для ветки «конечный кадр вместо анимации» (пункт O-7) |

---

## 5. Помечено «ждёт Windows 1.5.0»

Эти части ТЗ №4 на Windows ещё не написаны: их поведение описано словами, но кода, с которого можно снять числа и структуру, нет. Mac делает их **после** того, как раунд ТЗ №4 сольётся в `master` и появится тег `mac-sync-base-3`. До этого момента Mac-исполнитель обязан оставить соответствующие места в состоянии «данные есть, интерфейса нет».

| # | Что ждёт | Что делать сейчас | Какие Windows-файлы смотреть потом |
|---|---|---|---|
| L-1 | **Модель цвета D1** (§D1): один активный цвет на всё, что рисует текущий инструмент; цвет принимается при любом инструменте, включая «Выбор», «Комментарий» и «Размытие»; заливка — свойство прямоугольника со своим цветом; сплошная и полупрозрачная = контур и заливка одним цветом; размытие = без контура; между снимками запоминаются только цвет, толщина, палитра и карандаш/маркер | Поля `fill`, `fillColor`, `hasOutline` завести в модели и сериализации (раздел 2.1) ради совместимости файлов, **писать `hasOutline: true` всегда**. Переключатель «Показывать рамку» в интерфейсе не рисовать, пару строк не заводить. Сегмент палитр оставить, но спектр и пипетку сделать доступными из любой палитры сразу (§D1 последний абзац, это не конфликтует ни с чем) | `OverlayEditorWindow.Appearance.cs:120-128, 256, 384-389, 423-429`, `OverlayEditorWindow.xaml:313-315`, `Controls/AnnotationCanvas.cs:59, 260, 744`, `SaveAppearanceDefaults` (`OverlayEditorWindow.xaml.cs:659-681`) |
| L-2 | **Модель вида снимка** (§C8): снимок всего экрана ложится в ленту как обычный; на карточке чип «экран» с иконкой монитора, миниатюра широкая; в редакторе подпись «весь экран · 2 монитора · 3840×1125»; импортированный файл — подпись «импорт · имя файла · размер»; текст в чат «Снимок C — весь экран» / «Снимок D — IMG_0512.png» | Не заводить ни поля в `CaptureItem`, ни чипа. Сейчас перенести только существующее поведение 1.4.0: снимок всего экрана пишется в папку и даёт уведомление (`EdgeStackWindow.Saving.cs:39-56`). Строку в `PromptGenerator` не трогать | `EdgeStackWindow.Saving.cs`, `SessionWorkspace.cs:139-164`, `SnapBrief.Core/Models/CaptureItem.cs`, `PromptGenerator.cs`, эталоны `tasks/handoff-005/reference-png/05, 07` |
| L-3 | **Редактор с масштабом** (§C8): широкая картинка с двух мониторов вписывается по ширине, вертикальная — по высоте; переключатель «По ширине · 35 %» ↔ «1:1»; в 1:1 прокрутка колесом, Ctrl+колесо меняет масштаб, пробел + мышь тянет; шов между мониторами остаётся тонкой линией | Не делать. Редактор Mac остаётся оверлеем поверх экрана (SPEC §9.5), как сейчас. Код зума из удаляемого `macos/Sources/SnapBriefMac/Preview/PreviewImageScrollView.swift` **не удалять насовсем, а перенести в ветку-заготовку**: он уже умеет ровно это | `OverlayEditorWindow.xaml`, `OverlayEditorWindow.Resize.cs`, эталоны `reference-png/06`, `reference-html/07, 08` |
| L-4 | **Настоящее стекло** (§B3): Acrylic/размытие под панелью | Не делать. Тема `glass` — матовый градиент варианта B (§B2), это и есть целевое состояние раунда | `reference-html/06-acrylic-later.html`; на Mac эквивалент — `NSVisualEffectView`, но только после того, как Windows решит, остаётся ли тема вообще |
| L-5 | **Импорт файла** (§C9): падение при кодировании кадра декодера на фоновом потоке | Windows-баг, у Mac его нет (`CGImage` потокобезопасен), но проверить, что импорт в `SessionWorkspace.swift` действительно копирует пиксели, а не держит ленивый источник | `SessionWorkspace.cs:139-147, 157-164, 274-288` |

---

## 6. Тесты

Windows-диффом добавлено 18 файлов тестов (+1181 строк), `git diff --stat mac-sync-base-2 HEAD -- tests`. Итог на Windows: 238 тестов. Ниже — куда ложатся Swift-аналоги.

| Windows-набор | Проверяет | Swift-набор |
|---|---|---|
| `tests/SnapBrief.Core.Tests/SessionModelTests.cs` (+5): `Sent_captures_leave_the_package_and_give_their_letters_to_the_waiting_ones`, `A_full_strip_stops_at_twenty_six_captures_and_its_last_letter_is_Z`, `Captures_without_notes_get_no_section_and_a_silent_session_gets_no_text` | `SentCaptureRules`, потолок 26, буква Z, молчащий снимок без секции в тексте | `macos/Tests/SnapBriefCoreTests/SessionModelTests.swift` (существует) |
| `tests/SnapBrief.Core.Tests/ExtendedCommentsTests.cs` (+3): `Note_offset_survives_json_and_stays_null_in_a_session_written_without_it`, `Shape_and_fill_survive_json_and_default_for_a_session_written_without_them` | round-trip `noteOffset`, `shape`, `fill` | `macos/Tests/SnapBriefCoreTests/ExtendedCommentsTests.swift` (существует) |
| `tests/SnapBrief.Core.Tests/CaptureCropperTests.cs` (+4): `Crop_rescales_the_note_offset_to_the_smaller_image`, `Crop_keeps_the_fill_colour_and_the_outline_flag_of_a_region`, `Crop_keeps_the_size_a_caption_was_typed_in` | пересчёт сдвига бейджа, сохранение полей заливки и кегля при обрезке | `macos/Tests/SnapBriefCoreTests/CaptureCropperTests.swift` (существует) |
| `tests/SnapBrief.Core.Tests/PersistenceAndExportTests.cs` (+7): `Json_store_round_trips_the_size_a_caption_was_typed_in`, `..._the_pattern_of_a_stroke_and_defaults_it_to_solid`, `A_line_style_outside_the_enumeration_is_refused`, `..._the_fill_colour_the_outline_flag_and_the_blur_fill`, `..._reads_a_session_without_the_fill_fields_and_one_that_still_holds_a_redaction`, `..._round_trips_the_sent_flag_and_reads_a_file_written_without_it`, `A_package_without_notes_carries_images_only_and_writes_no_prompt_file` | сериализация всех семи новых полей, валидация `lineStyle`, чтение legacy `redaction`, пакет без `prompt.md` | `macos/Tests/SnapBriefCoreTests/PersistenceAndExportTests.swift` (существует) |
| `tests/SnapBrief.App.Imaging.Tests/HotkeyRulesTests.cs` (новый, 21 факт) | голая клавиша, отпущенный модификатор, Print Screen/Pause, `SameGesture`, чёрный список, `SuggestFree` | новый `macos/Tests/SnapBriefCoreTests/HotkeyRulesTests.swift` (чёрный список — свой, раздел 2.4) |
| `tests/SnapBrief.App.Imaging.Tests/ColorConversionTests.cs` (новый, 16 фактов) | round-trip `HsvToRgb`/`RgbToHsv`, серый на любом оттенке, обход круга, чистые углы | новый `macos/Tests/SnapBriefCoreTests/ColorConversionTests.swift` |
| `tests/SnapBrief.App.Imaging.Tests/StripResizeGeometryTests.cs` (новый, 14 фактов) | `WidthFromStart`/`ListHeightFromStart` от старта, упор в рабочую область и минимум, возврат из клампа с первого пикселя, нечисло, DPI | новый `macos/Tests/SnapBriefCoreTests/Geometry/StripResizeGeometryTests.swift` (рядом с `ResizeGeometryTests.swift`) |
| `tests/SnapBrief.App.Imaging.Tests/TextMarkMetricsTests.cs` (новый, 12 фактов) | кириллица и латиница, пустая строка, рост от кегля и длины, клампы, `Fit` не двигает якорь и не трогает чужие отметки, копия сохраняет узор штриха | новый `macos/Tests/SnapBriefCoreTests/TextMarkMetricsTests.swift` (числа — от собственного рендера, см. раздел 4) |
| `tests/SnapBrief.App.Imaging.Tests/ShapeMaskTests.cs` (новый, 6 фактов) | покрытие прямоугольника, овала, скруглённой рамки, сглаживание края в один пиксель, радиус угла | новый `macos/Tests/SnapBriefMacTests/Imaging/ShapeMaskTests.swift` |
| `tests/SnapBrief.App.Imaging.Tests/RegionBlurTests.cs` (+3) | овальная маска, радиус от короткой стороны, отказ на неверном радиусе | `macos/Tests/SnapBriefMacTests/Imaging/RegionBlurTests.swift` (существует) |
| `tests/SnapBrief.App.Imaging.Tests/SettingsMigrationTests.cs` (новый, 4 факта) | миграция громкости 60→40 только при `SettingsVersion < 1`, чужая громкость не трогается | новый `macos/Tests/SnapBriefCoreTests/SettingsMigrationTests.swift` |
| `tests/SnapBrief.App.Imaging.Tests/SoundThrottleTests.cs` (новый, 3 факта) | окно тика 170 мс, подавление после затвора 400 мс | новый `macos/Tests/SnapBriefMacTests/App/SoundThrottleTests.swift` |
| `tests/SnapBrief.App.Imaging.Tests/SaveNamingTests.cs` (новый, 4 факта) | свободное имя пакета, фильтр диалога | новый `macos/Tests/SnapBriefCoreTests/SaveNamingTests.swift` |
| `tests/SnapBrief.App.Imaging.Tests/PublishedPackageTests.cs` (новый, 5 фактов) | «наша вставка» против чужой записи в буфер | `macos/Tests/SnapBriefCoreTests/Transport/ClipboardEchoDetectorTests.swift` (существует, дописать) |
| `tests/SnapBrief.App.Imaging.Tests/HotkeyLabelPartsTests.cs` (новый, 2 факта) | разбор подписи сочетания на капсулы | новый `macos/Tests/SnapBriefMacTests/App/HotkeyLabelPartsTests.swift` |
| `tests/SnapBrief.Windows.Tests/CodexDesktopPasteCompletionServiceTests.cs` (+3): `AltVDoesNotInject_AndAPackageWithoutTextSkipsTheTextStep`, `InterceptedPasteOfAPackageWithoutText_DispatchesImagesOnly`, `PhysicalCodexCtrlVOfAPackageWithoutText_LeavesTheClipboardAloneAfterTheCompletion` | пакет без текста: шаг текста пропускается, буфер не перезаписывается | `macos/Tests/SnapBriefCoreTests/Transport/CodexDesktopPasteCompletionServiceTests.swift` (существует) |
| `tests/SnapBrief.Windows.Tests/PasteCoordinatorTests.cs` (+1) | пакет без текста в координаторе | `macos/Tests/SnapBriefCoreTests/Transport/PasteCoordinatorTests.swift` (существует) |

Новых тестовых **целей** не заводить: всё ложится в существующие `SnapBriefCoreTests` и `SnapBriefMacTests`. UI-тестов не писать — их роль играет `SmokeTestRunner` (раздел 1.7).

---

## 7. Порядок реализации: порции

Деление по **папкам Swift**, как в `CONTRACTS.md`: внутри порции файлы не пересекаются, между порциями пересечений три — `UiLanguage.swift`, `SmokeTestRunner.swift`, `AppCoordinator.swift`. Правило то же, что в `tz-004-plan.md` §5: каждая порция дописывает свои строки **рядом с родственными**, а не в конец файла, и после каждого слияния прогоняется CI.

### Волна 0 (последовательно, один исполнитель, до ветвления)

Пока волна 0 не в `master`, остальные порции стартовать не могут: они все читают модель и токены.

| # | Что | Файлы | Готово, когда |
|---|---|---|---|
| W0-1 | Core-модель и сериализация: C-1, C-2, C-3, C-5, C-6 | `Sources/SnapBriefCore/Models/**`, `Editing/CaptureCropper.swift` | round-trip всех семи полей зелёный, сессия без них читается с дефолтами |
| W0-2 | `SentCaptureRules.swift`, `StripResizeGeometry.swift`, `SaveNaming.swift`, `ColorConversion.swift`, `TextMarkMetrics.swift`, `HotkeyRules.swift`, `SettingsMigration.swift` — чистые правила Core, каждое со своим тестовым файлом | `Sources/SnapBriefCore/{Exporting,Geometry,Editing,Settings}/**`, `Tests/SnapBriefCoreTests/**` | тесты раздела 6, которые не требуют AppKit, зелёные |
| W0-3 | `HotkeySettings.swift`: 24 новых ключа, миграция громкости, лечение битых id (C-9, раздел 2.2) | `Sources/SnapBriefCore/Settings/HotkeySettings.swift` | файл от `mac-sync-base-2` читается без потерь, новый читается старым билдом |
| W0-4 | `UiLanguage.swift`: 213 новых пар в порядке Windows-файла, 2 изменённых значения, целевые замены §3.4 | `Sources/SnapBriefCore/Settings/UiLanguage.swift` | ни одного повторяющегося ключа и ни одного повторяющегося EN-значения |
| W0-5 | `Theme.swift` → шесть палитр и двенадцать акцентов (G-1, G-2), `AccentPalette.swift` | `Sources/SnapBriefMac/App/Theme.swift`, `App/AccentPalette.swift` | наборы ключей всех шести палитр совпадают; `light` гасится в `dark`; градиентный акцент не роняет пробу |
| W0-6 | Удаление `Preview/**` и `Tests/SnapBriefMacTests/Preview/**` (S-1), заготовка зума из `PreviewImageScrollView.swift` уносится в отдельную ветку (L-3) | `Sources/SnapBriefMac/Preview/**` | сборка зелёная, клик по карточке ведёт в редактор |

### Волна 1: три порции параллельно, каждая в своём worktree и своей ветке от коммита волны 0

**Порция A — Stack.** Зона: `Sources/SnapBriefMac/Stack/**`, `App/WindowCaptureExclusion.swift`, `App/SessionWorkspace.swift`.
Порядок: S-9 (геометрия, разблокирует остальное) → S-4, S-5, S-6 → S-3 → S-7 → S-8 → S-2 → S-10 → S-11, S-12, S-13, S-14.

**Порция B — Editor и Imaging.** Зона: `Sources/SnapBriefMac/Editor/**`, `Sources/SnapBriefMac/Imaging/**`.
Порядок: E-1 (фигура, заливка, маска — на ней стоят оба рендерера) → E-2 → E-15, E-20 → E-3, E-4, E-5 → E-6 → E-7, E-8, E-9 → E-10, E-11, E-12, E-13, E-14 → E-16, E-17, E-18, E-19.

**Порция C — Settings и Onboarding.** Зона: `Sources/SnapBriefMac/Settings/**`, новый `Sources/SnapBriefMac/Onboarding/**`, `App/LaunchAtLoginService.swift`, `App/CaptureFeedbackSound.swift` → `UiSoundService.swift`, `Resources/Audio/**`.
Порядок: G-4, G-5 (контрол нужен и настройкам, и мастеру) → G-1-зависимые вкладки G-3 → G-6, G-7, G-8, G-9 → G-10, G-11 → G-12 → O-1, O-2 → O-3, O-4, O-5 → O-6 → O-7, O-8 → G-13.

Порции A, B и C не пересекаются по файлам. Единственные общие файлы — `UiLanguage.swift` (закрыт волной 0, дописывать не нужно), `SmokeTestRunner.swift` и `AppCoordinator.swift`: **в волне 1 их не трогать**, каждая порция выносит свои пробы в собственный файл (`Stack/StackSmokeProbes.swift`, `Editor/OverlayEditorController+SmokeTest.swift` — уже существует, `Onboarding/OnboardingProbes.swift`) и публикует одну точку входа.

Transport (T-1…T-5) — четвёртая, самая маленькая порция; её можно отдать любому освободившемуся исполнителю или сделать в волне 0: зона `Sources/SnapBriefCore/Transport/**` и `Sources/SnapBriefMac/Transport/**` не пересекается ни с A, ни с B, ни с C.

### Волна 2 (последовательно, после слияния A, B и C по одной)

| # | Что | Файлы |
|---|---|---|
| W2-1 | Сведение проб в `SmokeTestRunner.swift`: K-1…K-4, единый код выхода | `Sources/SnapBriefMac/App/SmokeTestRunner.swift` |
| W2-2 | Сведение `AppCoordinator`: показ ленты после мастера (S-15), помётка `sent` (T-5), автосохранение, жизненный цикл сессии (C-15) | `Sources/SnapBriefMac/App/AppCoordinator*.swift` |
| W2-3 | Ресурсы и сборка: три mp3 вместо двух wav, `Package.swift`, `project.yml`, `ci-smoke.sh` | `macos/Package.swift`, `macos/project.yml`, `macos/scripts/ci-smoke.sh` |
| W2-4 | Одно код-ревью по всему диапазону отдельным субагентом со свежим контекстом против этой спеки, затем один фикс-коммит | по результату |
| W2-5 | Журнал: новая строка в `macos/SYNC.md`, тег `mac-sync-base-3` на `a2f72e1`, ссылка на DMG | `macos/SYNC.md` |

Ревью — одно, в конце, а не после каждой порции.
