# SPEC-DELTA-2: перенос Windows-изменений mac-sync-base-1 → HEAD на macOS

Дата: 2026-09-09. Источник истины: Windows-код в `src/` на коммите HEAD (`git diff mac-sync-base-1 HEAD -- src tests`, 10 коммитов, 39 файлов, +2497/−259). Дополняет `SPEC.md`; при противоречии действует этот файл. Состоит из трёх файлов:

- `SPEC-DELTA-2.md` (этот): принятые решения + Часть 1, инвентарь Windows-изменений.
- `SPEC-DELTA-2A.md`: Часть 2, дизайн транспорта на macOS (раздел A).
- `SPEC-DELTA-2B.md`: Часть 3, дизайн редактора, предпросмотра, стопки, звука, настроек, тестов (разделы B–F).

## Принятые решения

- Жесты на macOS: Cmd+V (основной) и **Ctrl+V** (так Claude Code вставляет картинки на Mac) плюс Option+V для паритета с Windows. Синтетический жест для картинок равен жесту пользователя; текст всегда Cmd+V. `PasteIntentGesture` / `InputInjecting` расширить на Ctrl+V.
- Перехват через `CGEvent tap .defaultTap` при наличии Accessibility; без него `listenOnly` (старое поведение «пакет как есть»), без обоих разрешений статус-ошибка.
- `setPNGGuarded`: один `NSPasteboardItem` с `.png` + `.tiff` + `.fileURL` (в этом порядке), флаг `pngItemIncludesFileURL` для отката.
- Окно предпросмотра: `.titled + .fullSizeContentView + .resizable`, стандартные кнопки скрыты, собственная шапка 46 px, перетаскивание через `performDrag`.
- Fullscreen предпросмотра: переключение frame ↔ `screen.visibleFrame`, без `toggleFullScreen`.
- Клавиши предпросмотра: Esc, F11 и Cmd+Ctrl+F, Cmd+0/1/+/−.
- Курсор перемещения: `NSCursor.openHand` (SizeAll в AppKit нет).
- `HotkeySettings`: явный `init(from:)` с `decodeIfPresent` для всех полей (старые settings.json должны читаться).
- Компилятора локально нет: все исполнители пишут консервативный Swift 5, перечитывают файлы целиком, помечают сомнительные API `// CHECK-API:`.

---

# Часть 1. Инвентарь Windows-изменений (mac-sync-base-1 → HEAD)

Коммиты (старые → новые):
```
73576ce windows: add guarded Claude desktop clipboard transport
bca702f windows: add linked comments and compact capture review workflow
cffdf24 windows: replace synthesized feedback with camera recordings
d01ad5f windows: paste individual PNG images into Claude before comments
10a3dc0 windows: make comment placement one-shot and keep note controls accessible
51b4a77 windows: publish DIB/Bitmap with PNG for per-image Claude paste
3bb9bbd windows: verification note for Claude image paste fix
110839c windows: universal per-image paste sequence for any foreground app
a93ed58 windows: keep clipboard package reusable after paste; rotate session
e588ad0 windows: re-arm clipboard package after receiver echo
```
Пути ниже относительно корня репозитория; `file:line` соответствуют HEAD.

## 1. Функциональные изменения по областям

### 1.1 Транспорт / буфер обмена (сводка; машина состояний в разделе 4)

Пользователь делает 1..N снимков; каждый коммит снимка публикует составной пакет (N PNG + Unicode-текст) в буфер и запоминает `ClipboardWriteReceipt`. Затем в любом приложении жмёт физический Ctrl+V (или Alt+V: терминал с Claude Code на Windows вставляет картинки по Alt+V). Snapik перехватывает нажатие (кроме Codex Desktop), подавляет его и проигрывает последовательность: изображение → пауза → изображение → … → текст. После завершения пакет перепубликуется и остаётся в буфере: тот же пакет можно вставить в следующее приложение без нового снимка. Новая стопка стартует только при следующем захвате.

Файлы: `src/Snapik.Windows/CodexDesktopPasteCompletionService.cs:121-214` (`CompleteSequentialAsync` + обёртка `CompleteClaudeAsync:208`), `WindowsPasteIntentObserver.cs:24-30, 57-109, 167-185`, `ClipboardEchoDetector.cs` (новый, 66 строк), `WindowsClipboardService.cs:33-42, 207-217`, `TransportContracts.cs:163-166, 313-314, 341, 352-367`, `src/Snapik.App/EdgeStackWindow.xaml.cs:49-56, 77-105, 215-282, 287-315, 317-344, 346-417, 452-484`.

Форматы буфера: раньше поштучная вставка клала только зарегистрированный формат `"PNG"`, Chromium (Claude Desktop) и Claude Code не видели картинку. Теперь для каждой картинки публикуется `PNG` + `CF_DIB` + `CF_BITMAP` через `SetPngGuardedAsync` (`:158-165`). `SetPngOnlyGuardedAsync` остался в контракте, в продуктовом пути не используется.

### 1.2 Редактор: стрелки

Новый `src/Snapik.App/Imaging/ArrowDrawing.cs` (33 строки), единый рендерер для редактора и экспорта. `ArrowDrawing.Draw(dc, start, end, brush, thickness, style)`, `style ∈ {straight, curved, bold, wide}`:
- `:11-12` длина `< 0.01` → ничего не рисуется.
- `:14` толщина пера `thickness * (bold ? 2 : 1)`; `StartLineCap/EndLineCap = Round`, `LineJoin = Round`.
- `:15-23` curved: контрольная точка квадратичного Безье `((start.X+end.X)/2 − vector.Y*0.25, (start.Y+end.Y)/2 + vector.X*0.25)`, `vector = end − start`. Направление наконечника от `control − end`.
- `:24` иначе прямая.
- `:27` `size = Min(length*0.7, Max(10, pen.Thickness*3.2))`; `:28` `halfWidth = size * (wide ? 0.85 : 0.45)`; `:29-31` треугольник заливается `brush` без обводки.

Меню стиля: `OverlayEditorWindow.Arrows.cs` (37 строк). `OverlayEditorWindow.xaml:100` кнопка `ArrowOptionsButton` справа от `ArrowTool`: `Width=23 MinWidth=23 Padding=6`, шеврон `Path 9×5 Stroke=#D9DEE8 StrokeThickness=1.5 Data="M1,1 L4.5,4 L8,1"`. `Arrows.cs:14` четыре пункта: `straight «Прямая стрелка»`, `curved «Изогнутая стрелка»`, `bold «Толстая стрелка»`, `wide «Широкая стрелка»`; `:16-19` образец: `ArrowDrawing.Draw(dc, (4,24), (70,8), White, 2, style)` в `Image 64×28 Margin="0,0,14,0"`; `:22` галочка `IsChecked` = (выбрана стрелка ? её `ArrowStyle` : `Surface.ActiveArrowStyle`) `== style`; `:25-31` клик: если выбрана стрелка → push undo, clear redo, `arrow.ArrowStyle = style`, `_lastSnapshot = SnapshotState()`, invalidate; иначе `SelectToolMode(Arrow)`; всегда `Surface.ActiveArrowStyle = style` + `SyncAppearance()`. Тултип «Стиль стрелки». `AnnotationCanvas.cs:43` `ActiveArrowStyle = "straight"`, новая аннотация получает его (`:146`). Рендер: `AnnotationCanvas.cs:377-379`, `WpfExportImageRenderer.cs:110-112`.

### 1.3 Редактор: комментарии (linked comments)

Модель: `EditorTool.Comment`, `AnnotationKind.Comment`, поле `ParentAnnotationId`.

One-shot: `OverlayEditorWindow.xaml.cs:653-658` `OnCommentClick`: `_commentParentId` = (выбрана отметка ? её Id : выбрана заметка ? её ParentAnnotationId : null), затем `SelectToolMode(Comment)`. `:400-418` `OnAnnotationCreated` для Comment: `ParentAnnotationId = _commentParentId`, `_commentParentId = null`, вторая точка = `Points[0] + (8,8)` с клампом по размерам изображения, сразу `SelectToolMode(Select)`. Клавиша `N` (`:867`) идёт через `OnCommentClick` (`:871`). Кнопка `CommentToolButton` в основной панели (`xaml:124-126`, иконка `Path 16×16 Stroke=#D9DEE8 StrokeThickness=1.6 Data="M2,2 L14,2 L14,11 L8,11 L4,15 L4,11 L2,11 Z"`); плавающая кнопка в углу удалена. Тултип «Добавить комментарий (N)», подсветка `Color.FromRgb(40,75,120)` при `Tool == Comment`.

Без ручек и рамки: `AnnotationCanvas.cs:407` `HasResizeHandles(item) => item.Kind != Comment`; `:305-320`, `:394` фильтруются; `:411` `GestureHasSize` → true для Comment и Text; `:193-194` в Select наведение на пин → `Cursors.SizeAll`; `:125` при `Tool == Comment` любой клик = новый пин.

Чипы (`OverlayEditorWindow.Comments.cs` 96 строк + `xaml.cs:449-621`). Геометрия/цвета (`:463-569`): бейдж `25×25 CornerRadius=13 #2F8CFF`, текст `11 Bold White`; поле `TextBox MinHeight=32 MaxHeight=78 AcceptsReturn Wrap Background=Transparent Foreground=White BorderThickness=0 CaretBrush=White SelectionBrush=#2F8CFF Padding="7,5,7,5"`; крестик `27×27 Padding=7`, `Path Stroke=#D9DEE8 1.5 "M1,1 L9,9 M9,1 L1,9"`; сетка 3 колонки `31 | * | 29` (третья → 0 в свёрнутом, `:518`); контейнер `Border MinHeight=40 Padding=6 CornerRadius=13 Background=#F4171A20`, тень `Black BlurRadius=14 ShadowDepth=4 Opacity=0.42`; **ширина 270 раскрыт / 43 свёрнут** (`:516`); z-index: раскрытый 1200 при фокусе, иначе 1000; свёрнутый 0 (`:519`).

Раскрытие/сворачивание: `MouseEnter` (`:551-554`) раскрывает только если ни в одном другом чипе нет клавиатурного фокуса (`HasFocusedChipOtherThan`, `Comments.cs:13-14`); `MouseLeave` (`:555`) → `Finish()` если нет фокуса; клик по бейджу (`:556`) → фокус в поле + раскрыть; `GotKeyboardFocus` (`:481,:550`) → выбрать аннотацию + раскрыть; `LostKeyboardFocus` (`:558`) → отложенно `Finish()`, если не под мышью и без фокуса; `PreviewKeyDown` (`:559-565`) Enter без модификаторов = `Finish()` + фокус на канву, Shift+Enter = перевод строки. `Expand(true)` (`:507-513`) сворачивает остальные чипы (`CollapseOtherChips`, `Comments.cs:16-23`, пропуская чипы с фокусом). Клик вне слоя чипов: `xaml.cs:231` → `FinishExpandedChipIfOutside` (`Comments.cs:25-39`).

`Finish()` (`:523-546`): если текст пуст и это не Text-аннотация → чип удаляется из словарей и `ChipLayer`; для Comment удаляется и сама аннотация (снимается выделение); иначе `Expand(false)`.

Автораскладка `FindChipPlacement` (`Comments.cs:41-75`): `gap = 6`, клампинг в рабочую область монитора с отступом 8; если предпочтительная позиция свободна — она; иначе спираль по кольцам `ring = 1..14`, шаг X `(size.Width+6)*ring`, Y `(Max(40,size.Height)+6)*ring`, порядок смещений: вниз, вправо, влево, вверх, затем 4 диагонали; занятость по инфлейту на 6. `RepositionChips` (`xaml.cs:586-621`): раскрытый чип первым, остальные в порядке аннотаций; высота раскрытого `Max(90, ActualHeight)`, свёрнутого 40; предпочтительная точка `(_cropRect.Left + bounds.Left, _cropRect.Top + bounds.Bottom + 8)`; раскрытый сохраняет текущую позицию.

`MoveLinkedComments` (`Comments.cs:77-95`, из `OnAnnotationChanged` `:429`): для каждой заметки с `ParentAnnotationId`: родителя нет → связь снимается; иначе bounding-box родителя в `_lastSnapshot` vs сейчас; изменился → точки заметки через `ResizeGeometry.Map(point, oldBounds, newBounds)`, при нулевых старых размерах простой сдвиг `parent.Points[0] − before.Points[0]`; клампинг в размеры изображения.

Legacy: `xaml.cs:60-64` при открытии разметки существующего снимка непустой `_capture.Note` превращается в аннотацию `Comment`, `Points = [(24,24),(32,32)]`, `_capture.Note` очищается.

Нумерация: только непустые заметки, источник `CaptureLabels.ForNotedAnnotations`; `RefreshLabels` (`:571-584`): пустая метка отображается `"T"` для Text и `"+"` для остальных. Бейдж на канве (`AnnotationCanvas.cs:383-392`): круг `Max(26, Label.Length*7+12)`, `#2F8CFF`, центр `(anchor.X, anchor.Y − diameter/2 − 3)`, `Segoe UI Variable Text SemiBold 11`, белый.

Text двойным кликом: `xaml.cs:232-238` показывает чип Text-аннотации и фокусирует; `AnnotationCanvas.cs:120` двойной клик выбирает Text. Крестик у Text-чипа: тултип «Закрыть ввод текста», аннотацию не удаляет (`DeleteAnnotationNote`, `:672`).

### 1.4 Редактор: hover-манипуляция

`AnnotationCanvas.cs:417-428` `FindMoveEdge(point)`: только Rectangle/Blur/Conceal; отключён при `Tool == Comment`; кольцо: внешний = bounds `Inflate(6,6)`, внутренний = bounds `Inflate(−Min(6,W/2), −Min(6,H/2))`; попадание = внутри внешнего и вне внутреннего; перебор `Annotations.Reverse()`. `:125-127` ветка выбора/перетаскивания срабатывает, когда `FindMoveEdge` не null, даже при другом активном инструменте; `:128` `hit = handleHit.Annotation ?? FindMoveEdge(point) ?? HitTestAnnotation(imagePoint)`. `:190-196` курсоры: SizeAll для края/пина, SizeNWSE/NESW для углов, иначе Arrow/Cross. Активный инструмент не меняется (`:537-538`).

Меню «…» (`xaml.cs:364-388`): перо P, маркер H, скрыть сплошным X; подсветка `Color.FromRgb(40,75,120)` при активном одном из них, тултип показывает активный (`Appearance.cs:69-70`). Text вернулся в основную панель (XAML `:23` без Collapsed).

Кнопка «+ Снимок» удалена из панели (`OnAddNextClick` остался в коде, `xaml.cs:825`). Следующий захват через горячую клавишу: `EdgeStackWindow.xaml.cs:211` → `OverlayEditorWindow.TryCommitAndRequestNext()` (`:99-105`).

### 1.5 Окно предпросмотра `CapturePreviewWindow` (новое)

`CapturePreviewWindow.xaml` (174) / `.xaml.cs` (428). Открывается кликом по карточке стопки: `EdgeStackWindow.Preview.cs:11-49`.

Окно (`xaml:6-12`): `Width=1100 Height=760 MinWidth=720 MinHeight=500`, `WindowStyle=None`, `ResizeMode=CanResize`, `Background=#101318`, `ShowInTaskbar=True`, `WindowStartupLocation=Manual`; `WindowChrome CaptionHeight=46 ResizeBorderThickness=7 CornerRadius=12`; рамка `WindowShell Background=#F4101318 BorderBrush=#3A4451 BorderThickness=1 CornerRadius=12` (0 в maximized, `xaml.cs:253`).

Позиционирование (`xaml.cs:86-112`): экран владельца (стопки); `CalculatePreviewBounds(workAreaPixels, dpiX, dpiY, out minimumDipSize)`: доступно `(workArea − 32)/dpi`; `minimumDipSize = (Min(720, availW), Min(500, availH))`; размер `Min(1100, availW) × Min(760, availH)` (в пикселях с dpi); центр рабочей области; корректно при отрицательном origin (проба `Rect(-1920,0,1920,1080)` при DPI 1.5, `:360-363`).

Заголовок (`xaml:80-107`): фон `#171B22`, высота 46; слева бейдж `24×24 CornerRadius=12 #2F8CFF` с меткой (`11 Bold White`), «Просмотр снимка» (`#EEF2F8 SemiBold`), «W × H» (`#8F9AAA 11`). Справа: Уменьшить (`IconButton 32×32`, `Path 13×13 Stroke=#DCE3ED 1.6 "M2,6.5 L11,6.5"`, `_zoom/1.2`), `ZoomText` (`Width=43 #B9C3D1 11`, формат `{_zoom:P0}`), Увеличить (`"M2,6.5 L11,6.5 M6.5,2 L6.5,11"`, `×1.2`), «По размеру окна» (`PreviewButton`, рамка `#7AB8FF` при fit иначе `#3A4451`), «100%», Fullscreen (`Path 14×14 "M1,5 L1,1 L5,1 M9,1 L13,1 L13,5 M13,9 L13,13 L9,13 M5,13 L1,13 L1,9"`, тултип «На весь экран»↔«Вернуть размер»), «Разметка» (`Background=#2F8CFF BorderBrush=#2F8CFF SemiBold Margin="7,0,4,0"`, закрывает с `MarkupRequested=true`), Закрыть (`Path 11×11 "M1,1 L10,10 M10,1 L1,10"`). Стили кнопок (`xaml:15-52`): `Height=32 MinWidth=32 Padding="9,0" Margin="2,0" Foreground=#E9EDF4 Background=#242A33 BorderBrush=#3A4451 CornerRadius=8`; hover `#323B48/#657388`, pressed `#1D222A`, фокус-рамка `#7AB8FF`, disabled `Opacity=0.42`; `IconButton Width=32 Padding=8`.

Масштаб (`xaml.cs:218-260`): кнопки ×1.2 / ÷1.2; колесо с Ctrl ×1.12 / ÷1.12 (`:255-260`); ручной зум `[0.1, 4]` (`:231`), fit `[0.05, 4]`; fit = `Min((viewportW−8)/imageW, (viewportH−8)/imageH)`, пересчёт на `SizeChanged` и после maximize; `LayoutTransform → ScaleTransform` внутри `ScrollViewer PanningMode=Both`; подложка `#0A0D11 CornerRadius=10 Margin="12,12,6,12"`.

Клавиатура (`:269-278`): Esc закрыть; F11 fullscreen; Ctrl+0/NumPad0 fit; Ctrl+1/NumPad1 100%; Ctrl+Plus/OemPlus увеличить; Ctrl+Minus/OemMinus уменьшить. `Deactivated → ClosePreview()` (`:288-291`) только после `_canAutoClose = true`, выставляемого на `ApplicationIdle` после `Loaded` (`:67-73`).

Панель комментариев (`xaml:110, 121-170`): колонка 292 px, `Border Margin="6,12,12,12" Padding=12 Background=#171B22 CornerRadius=10`; заголовок «Комментарии» (`#EEF2F8 SemiBold`) + кнопка добавления (`IconButton`, `Path 14×14 "M1,1 L10,1 L10,8 L6,8 L3,11 L3,8 L1,8 Z M12,5 L12,13 M8,9 L16,9"`, тултип «Добавить комментарий»); `CommentList` виртуализированный `ListBox`; пустое состояние `"Нет комментариев"` (`Margin="8,12" #8F9AAA`). Карточка: `Border Margin="0,0,0,9" Padding=9 CornerRadius=10 Background=#202630`; метка (`#7AB8FF 11 SemiBold`) и связь (`#8F9AAA 11`, ellipsis); удаление `28×28 Padding=7 Margin="0,-5,-5,0"` `Path 10×10 Stroke=#BFC8D6`; поле `TextBox MinHeight=54 MaxHeight=150 AcceptsReturn Wrap UpdateSourceTrigger=PropertyChanged`, стиль `Background=#1C222B BorderBrush=#3A4451 Padding="9,7" CornerRadius=8 CaretBrush=#7AB8FF SelectionBrush=#315CF5`, фокус-рамка `#7AB8FF`.

Состав `RebuildComments` (`xaml.cs:114-130`): 1) если `_capture.Note` непустой — запись `Relation = "Комментарий к снимку"`; 2) все аннотации с `Kind == Comment` или непустым `Note`; связь `"К отметке " + AnnotationName(parentId)` при родителе, иначе `"К снимку " + DisplayLabel`. `AnnotationName` (`:140-147`): экспортная метка родителя, иначе `«{DisplayLabel}·{index}»` (порядковый среди не-Comment). Метки через `CaptureLabels.ForNotedAnnotations` (`:132-138`); пустой комментарий показывает `"+"` и не занимает номер.

Добавление (`:149-169`): `AnnotationItem { Kind=Comment, Points=[center, center+(8,8)], Note="" }` (center = центр изображения); пересбор, `QueuePersist`, прокрутка к новой записи и фокус в её TextBox с кареткой в конце. Удаление (`:178-186`): Comment → удалить аннотацию; иная аннотация → очистить `Note`; запись снимка → очистить `_capture.Note`; пересбор, перерендер, `QueuePersist`.

Сохранение: `DispatcherTimer 360 мс` (`:25`); тик перерисовывает картинку и добавляет `_persist()` в цепочку `_persistChain` (`:195-207`); при закрытии `FlushEditsAsync` (`:209-216, 300-310`). `_persist` = `EdgeStackWindow.PersistPreviewChangesAsync` (`Preview.cs:51-56`): обновить список стопки, инвалидировать `_prepared`, сохранить сессию, обновить только свой буфер (`RefreshOwnedClipboardAsync`), без автовставки.

Отрисовка превью (`xaml.cs:76-84`): клонировать аннотации, присвоить экспортные метки, `AnnotationCanvas { ImagePadding = 0 }.RenderAnnotated()`.

Переход в разметку (`Preview.cs:23-38`): `ShowForAsync` → если `true`: скрыть стопку (`HideForCapture`), `OverlayEditorWindow.EditExistingAsync`, результат заменяет элемент в `Captures`, `SaveAndCopyCommittedPackageAsync()`; при успехе и `result.AddNext` → `CaptureLoopAsync()` (`:48`). Пока предпросмотр открыт, карточка `IsSelected = true` (`:17`, снимается в `finally :43`).

Пробы (`xaml.cs:314-365`, `RunPreviewProbe`, из `SmokeTestRunner.cs:79`): пустой комментарий имеет метку `"+"`; после набора текста метка совпадает с экспортной; после удаления первого метки закрывают разрыв; 300 комментариев не обрезаются; границы окна не выходят за рабочую область при отрицательном origin и 150% DPI.

### 1.6 Звук захвата

`src/Snapik.App/CaptureFeedbackSound.cs` (89): `SampleRate=44100`, `TickThrottleMilliseconds=170`, `CaptureSuppressionMilliseconds=400`; ресурсы `Snapik.App.Assets.Audio.camera-shutter.wav` и `camera-dial-click.wav`; один `SoundPlayer` под lock. `Capture(enabled)` (`:22-27`): фиксирует `_lastCaptureTimestamp`, играет затвор; вызов `EdgeStackWindow.xaml.cs:439` сразу после `SaveAndCopyCommittedPackageAsync()` и до автосохранения. `Tick(enabled)` (`:29-39`): игнор если `< 400 мс` после затвора или `< 170 мс` после прошлого тика; вызовы `EdgeStackWindow.Preview.cs:58` (`MouseEnter` карточки), `:60-63` (`PreviewMouseWheel` списка). `Play` (`:61-76`): Stop, Position=0, Load, Play; исключения глотаются. `VerifyWaveHeaders()` (`:41-45, 78-86`): `RIFF`/`WAVE`/`data`, размер RIFF `= len−8`, PCM (1), моно (1), 44100 Гц, 16 бит, data `= len−44`; иначе `InvalidOperationException("Bundled capture feedback is not a valid 44.1 kHz mono PCM WAV stream.")`; вызывается первой строкой smoke. Выключатель: настройка `PlaySounds` (default true).

### 1.7 Стопка `EdgeStackWindow`

`EdgeStackWindow.xaml:100-162`: окно `Width=208 MinHeight=128 MaxHeight=620 SizeToContent=Height Topmost=False ShowActivated=False`; список `MaxHeight=372 Margin="0,7,0,8" Padding="0,0,0,52"`, виртуализация `ScrollUnit=Pixel`; карточка `ThumbCard Height=78 CornerRadius=11 Background=#242A33 BorderBrush=#46505E BorderThickness=1 ClipToBounds`, **`Margin="0,0,0,-48"`** (перекрытие 48 px); hover: `BorderBrush → #718096`, кнопка удаления `Opacity 0→1`, `Margin → "0,4,0,4"` за 180 мс `DecelerationRatio=0.8`; выход → `"0,0,0,-48"` за 160 мс (`:144-150`); клавиатурный фокус — то же без анимации (`:151-154`); `IsSelected` (открыт предпросмотр) — раскрыта, рамка `#7AB8FF` (`:155-158`); z-index hover 20, selected 30 (`:114-117`); миниатюра `Image Stretch=UniformToFill Opacity=0.86`, снизу полоса `Height=26 Background=#E6171A20` с бейджем метки `20×20 CornerRadius=10 #2F8CFF 11 Bold White`, иконкой заметки `Path 10×10 Stroke=#AEB8C7 1.2 "M1,1 L9,1 L9,7 L5,7 L2,9 L2,7 L1,7 Z"` и счётчиком `NoteCount` (`#DCE3ED 11`); кнопка удаления `27×27 Padding=7 Margin="0,5,5,0" Background=#E6171A20`, `Path Stroke=White 1.5`; тонкий скроллбар `StackScrollBar` (`xaml:48-77`): `Width=7 Margin="5,2,0,2"`, thumb `#657083 CornerRadius=4`, hover `#8A96A9`, drag `#7AB8FF`, repeat-кнопки скрыты; обработчики: `MouseEnter → OnCaptureThumbMouseEnter` (тик), `PreviewMouseWheel → OnCaptureListMouseWheel` (тик), клик `OnOpenCaptureClick` (предпросмотр). Блок выбора получателя и ручной вставки скрыт (`xaml:171-183`, Collapsed).

`SetStatus` (`xaml.cs:905-912`): текст в `StatusText` (`11 #FF9B95 Wrap`), видим только при `error=true`, дублируется в `startup.log`.

### 1.8 Настройки

`HotkeySettingsWindow.xaml:19` вкладка «Общие»: `SoundsBox` «Звуки захвата и стопки» (default включено); `:30` вкладка «Сохранение»: `AutoSaveBox` «Автоматически сохранять готовые снимки» `Margin="0,0,0,16"` (default выключено). `.xaml.cs:21-22` свойства `AutoSaveCaptures` (false), `PlaySounds` (true); `:103-104` загрузка; `:160-161` валидация при сохранении: пустой `DirectoryBox.Text` → `InvalidOperationException(UiLanguage.Text("Укажите папку сохранения.", _original.Language))`; `:169-170` запись.

Автосохранение: `EdgeStackWindow.Saving.cs:17-35` `AutoSaveCaptureAsync`: при `AutoSaveCaptures == false` выход; иначе рендер `AnnotationCanvas { Image, Annotations }.RenderAnnotated()` в `LocalImageSave.NewPath(_settings)` в `SaveFormat`/`JpegQuality`, затем `NotifySaved()`; ошибка → статус `«Автосохранение не выполнено: {message}»` (не прерывает захват). Вызов `xaml.cs:440`, сразу после звука. Уведомления (`Saving.cs:10-15`): балун трея 2000 мс, заголовок «Snapik», текст через `UiLanguage.Text`, только при `ShowNotifications`.

### 1.9 Экспорт: `PromptGenerator`, `CaptureLabels`, `WpfExportImageRenderer`

- `CaptureLabels.cs:63-74` `ForIndex` не ограничен 26: bijective base-26 (`A..Z, AA, AB, …`): `value = index+1; while value > 0 { value--; label = (char)('A' + value%26) + label; value /= 26 }`; ошибка только при `index < 0`.
- `PromptGenerator.cs:34-47`: см. раздел 2.2.
- `WpfExportImageRenderer.cs:110-112`: стрелка через `ArrowDrawing.Draw(..., item.ArrowStyle)`. Остальное без изменений: `HeaderHeight=48`, белая шапка, бейдж `Rect(12,8,34,32)` радиус 7 цвет `#172033`, подпись «SNAPIK · СНИМОК» `12 SemiBold #5E687A`, метки-круги `Max(34, Label.Length*9+16)` `#2F8CFF`, `Segoe UI Bold 13 White`. `Kind == Comment` попадает в третий проход (`:39-40`, `drawShape:false`): в экспорте рисуется только бейдж, без геометрии.

### 1.10 Модели Core

- `AnnotationItem.cs:107` `AnnotationKind.Comment` добавлен в конец enum; `:121-122` `Guid? ParentAnnotationId`, `string ArrowStyle = "straight"`.
- `CaptureCropper.cs:55-56` `Comment` пересчитывается через `CropBox` (как Rectangle/Text/Redaction/Blur); `:70-74` после фильтрации: `HashSet` id уцелевших; у уцелевших с `ParentAnnotationId`, указывающим на исчезнувшую отметку, связь снимается (`null`), заметка сохраняется.
- `EditorModels.cs`: `EditorTool.Comment` (`:25-26`), поля `ParentAnnotationId`/`ArrowStyle` (`:41-42`), перенос в `Clone()` (`:66`), `ToCore()` (`:99`), `FromCore()` (`:112`), маппинги (`:81`, `:114`).

## 2. Изменения формата данных

### 2.1 `AnnotationItem`
Сериализация camelCase + enum как строка camelCase, `WriteIndented`. Схема остаётся 1, миграции нет.

| Поле | JSON | Тип | Default | Смысл |
|---|---|---|---|---|
| `AnnotationKind.Comment` | `"comment"` | enum | — | заметка-пин без геометрии |
| `ParentAnnotationId` | `parentAnnotationId` | Guid? | null | GUID родительской отметки; null = к снимку |
| `ArrowStyle` | `arrowStyle` | string | `"straight"` | `straight`/`curved`/`bold`/`wide` |

Пример:
```json
{ "id": "8b1c...", "kind": "comment", "points": [ {"x":0.2,"y":0.2}, {"x":0.21,"y":0.21} ],
  "strokeColor": "#FF3B30", "thickness": 3, "text": "", "note": "коммент два",
  "parentAnnotationId": "3f9a...", "arrowStyle": "straight", "pathSegments": [] }
```

### 2.2 `PromptGenerator`
Единственное изменение: у заметки с существующим и пронумерованным родителем к строке дописывается ` (к области <МЕТКА_РОДИТЕЛЯ>)`. Родитель попадает в суффикс только если у него самого непустой `Note` (то есть есть номер). Грамматика (секции через `"\n\n"`):
```
Общее пожелание:
<GlobalNote>

Снимок <МЕТКА>[ — <Title>].
[Комментарий к снимку:
<Note>]
<МЕТКА><N>: <текст>[ (к области <МЕТКА><M>)]
```
Пример: `Снимок A.\nA1: коммент 1\nA2: коммент два (к области A1)\n\nСнимок B.\nB1: коммент 1`. Тест: `A301: Комментарий 299 (к области A1)`.

### 2.3 `CaptureLabels`
`ForIndex(0..25) → A..Z`, `26 → AA`, `299 → KN`; ошибка только при `index < 0`. `ForAnnotation`, `ForNotedAnnotations` без изменений (Comment без текста номера не получает).

### 2.4 `settings.json`
Новые необязательные ключи: `AutoSaveCaptures` (bool, false), `PlaySounds` (bool, true). Формат ID горячих клавиш не менялся.

### 2.5 `manifest.json`
Структура не менялась; меняется содержимое вложенных аннотаций (2.1) и `PromptText` (2.2). Метки снимков продолжаются после Z.

## 3. Новые строки локализации (`UiLanguage.cs`, порядок файла)

Строки 19-20 (после «Захватывать курсор»):
```
"Звуки захвата и стопки" = "Capture and stack sounds"
"Автоматически сохранять готовые снимки" = "Automatically save completed captures"
"Укажите папку сохранения." = "Choose a save folder."
"Автосохранение не выполнено" = "Auto-save failed"
```
Строки 29-35 (после «Повторить», перед «Сохранить на компьютер»):
```
"Просмотр снимка" = "Capture preview"
"По размеру окна" = "Fit to window"
"Увеличить" = "Zoom in"
"Уменьшить" = "Zoom out"
"На весь экран" = "Full screen"
"Вернуть размер" = "Restore size"
"Разметка" = "Mark up"
"Закрыть просмотр" = "Close preview"
"Комментарии" = "Comments"
"Нет комментариев" = "No comments yet"
"Комментарий к снимку" = "Capture comment"
"К снимку" = "To capture"
"К отметке" = "To annotation"
"Прямая стрелка" = "Straight arrow"
"Изогнутая стрелка" = "Curved arrow"
"Толстая стрелка" = "Bold arrow"
"Широкая стрелка" = "Wide arrow"
"Стиль стрелки" = "Arrow style"
"Добавить комментарий (N)" = "Add comment (N)"
"Закрыть ввод текста" = "Close text editor"
```
Строки 43-45 (в конец):
```
"Снимки сохранены, но вставка не завершена" = "Captures were saved, but pasting did not finish"
"Вставлено: {0} изображений · {1} заметок. Пакет остаётся в буфере, следующий снимок начнёт новую стопку" = "Pasted: {0} images · {1} notes. The package stays on the clipboard, the next capture will start a new stack"
"Пакет вытеснен другим приложением. Сессия сохранена." = "Another app replaced the package. The session was saved."
```
Переиспользованы существующие: «Добавить комментарий», «Удалить комментарий», «Снимок сохранён», «Снимки скопированы».

## 4. Транспорт как машина состояний (HEAD)

### 4.1 Предикат перехвата (`EdgeStackWindow.xaml.cs:77-105`), вызывается синхронно внутри хука
Guard A (не готово): `_sessionResetting`; `!_pasteIntentTransition.IsCompleted`; `_clipboardPublicationGate.CurrentCount == 0`; `_ownedClipboardReceipt is null`; `intent.ClipboardSequenceNumber != receipt.SequenceNumber`; пустой `_ownedClipboardPromptText`; `_prepared is null`. Лог `PasteIntent predicate: state not ready (resetting=…, transitionDone=…, gate=…, ownedSeq=…, intentSeq=…, prompt=…, prepared=…, gesture=…)`.
Guard B: жест не CtrlV/AltV → лог `PasteIntent predicate: gesture {…} not intercepted`.
Guard C: `!target.IsUsable` или HWND/PID не совпали → лог `PasteIntent predicate: target mismatch (...)`.
Решение: `intercept = !foreground.Matches(target, CodexDesktop)`; лог `PasteIntent predicate: intercept=…, gesture=…, process=…, title=…, seq=…`.

### 4.2 Хук и подавление (`WindowsPasteIntentObserver.cs`)
`PasteIntentKeyState.Observe` (`:207-242`): injected — игнор; жест один раз на нажатие (auto-repeat отсекается через `vDown`), только при ровно одном из Ctrl/Alt и без прочих модификаторов (Shift/Win). Publish (`:70-99`): не публикуется при HWND=0, PID=0 или PID == свой; `interceptThisGesture = (CtrlV|AltV) && подписчик && shouldIntercept(intent)`; `ShouldSuppress` вызывается до `handler`. `PasteIntentInterceptionState.ShouldSuppress` (`:171-182`): injected или клавиша ≠ V — никогда; key-up — сброс, не подавляется; key-down при `interceptThisGesture` → `suppressPhysicalVUntilRelease = true`, подавляются первое нажатие и все auto-repeat до отпускания. `Stop()` сбрасывает оба состояния.

### 4.3 `OnPasteIntentObserved` (`xaml.cs:215-236`)
Снимок состояния до I/O; лог `PasteIntent observed: gesture=…, intercepted=…, seq=…, ownedSeq=…, pid=…`. Нет receipt или seq не совпал → `LogClipboardDiagnosticsAsync()` и выход. `promptAtIntent is null` → статус «Не удалось подтвердить содержимое текущего пакета. Сессия сохранена.». Повторная проверка Guard A. `_pasteIntentTransition = Dispatcher.InvokeAsync(CompletePasteIntentAsync)`; все мутирующие операции окна начинаются с `await _pasteIntentTransition`.

### 4.4 `CompletePasteIntentAsync` (`xaml.cs:238-282`), под `_clipboardPublicationGate`
`IsIntercepted` → `CompleteSequentialAsync`, иначе `CompleteAsync` (Codex). Лог `PasteIntent completion: intercepted=…, images=…, status=…, message=…`. Если `_ownedClipboardReceipt != receiptAtIntent` → выход. `CurrentClipboardReceipt` → `_ownedClipboardReceipt`. `CompletedUnverified` → `RepublishPackageForReuseAsync` (без ротации). `!IsIntercepted && NotApplicable` → если пакет актуален → `StartNewSessionAsync()`. Иначе статус «Снимки сохранены, но вставка не завершена: {message}». Исключение → лог `PasteIntent completion failed: {ex}` + статус «Вставка замечена, но новая сессия не создана: {message}».

### 4.5 `CompleteSequentialAsync` (`CodexDesktopPasteCompletionService.cs:121-205`)
Задержки: `DefaultSettlementDelay=500` (Codex), `DefaultImageSettlementDelay=700`, `DefaultAltVImageSettlementDelay=1200` мс; отрицательные → исключение. Guard на входе (`foreground.Capture()` до первого await): не intercepted / жест не CtrlV,AltV / target не usable / HWND,PID ≠ / профиль Codex → `NotApplicable` "Intercepted paste completion applies only to a physical Ctrl+V or Alt+V outside Codex Desktop."; seq ≠ receipt → `StaleIntent` "The paste intent does not refer to Snapik's current package."; нет картинок или пустой prompt → `NothingToDispatch` "The package needs at least one image and prompt text.". `perImageDelay = AltV ? 1200 : 700`; `imageGesture = intent.Gesture`. Цикл: `SetPngGuardedAsync(path[i], expectedSeq)` → `SendGuardedAsync(imageGesture, target, receipt)` (guard перед отпусканием клавиш: `IsCurrentAsync` иначе `ClipboardChanged`; `IsSame(target)` иначе `TargetLost`; отказ → `GuardRejectedResult(status, "image N", receipt)` с текстом "Claude focus changed while the image N paste keys were being released." / "The clipboard changed while the image N paste keys were being released.") → `Task.Delay(perImageDelay)` → повторно `IsCurrentAsync` ("The clipboard changed after image N paste.") и `IsSame` ("Focus changed after image N paste."). Текст: `SetTextGuardedAsync(prompt, seq последней картинки)` → `SendGuardedAsync(CtrlV)` всегда. Успех `CompletedUnverified` "Image and prompt paste shortcuts were dispatched in order; receiver acceptance was not observable.". Исключения: `ClipboardChangedException → ClipboardChanged`; отмена → `Cancelled` "The guarded sequential paste was cancelled."; прочее → `Failed` "The guarded sequential paste failed: {message}"; возвращается `textReceipt ?? currentReceipt`. `CompleteAsync` (Codex) без изменений, кроме guard `intent.IsIntercepted → NotApplicable`.

### 4.6 Многоразовый пакет
`RepublishPackageForReuseAsync` (`xaml.cs:317-344`, внутри той же критической секции): нет receipt/prepared → статус-ошибка «Пакет вытеснен другим приложением. Сессия сохранена.»; успех: `SetPackageGuardedAsync(paths, prompt, current.SequenceNumber)`, обновить receipt/prompt, `_pasteObservedForCurrentPackage = true`, лог `PasteIntent republished package: seq=…, images=…`, статус «Вставлено: {N} изображений · {M} заметок. Пакет остаётся в буфере, следующий снимок начнёт новую стопку» (не ошибка), `StartReceiverEchoWatch`; `ClipboardChangedException` → `CancelReceiverEchoWatch()`, обнулить receipt/prompt, статус-ошибка «Пакет вытеснен…», чужой буфер не трогать.
`EnsureCurrentCaptureSessionAsync` (`:452-484`): первым делом `_pasteObservedForCurrentPackage` → сброс флага, обнулить receipt/prompt, `StartNewSessionAsync()` (буфер не читается); иначе `Captures.Count == 0` → true; иначе receipt актуален → true, нет → обнулить и новая сессия; исключение → статус «Не удалось проверить буфер перед новым снимком: {message}», false. Флаг не сбрасывается импортом/восстановлением (они не вызывают Ensure).

### 4.7 Отзвук получателя
`ClipboardEchoDetector.IsReceiverEcho(snapshot, promptText)` → true только если: prompt непустой; нет `FileDrop`; нет `Bitmap`/`DeviceIndependentBitmap`/`PNG`; есть текст `UnicodeText` или `Text`; после нормализации (вырезать `\[Image #\d+\]`, схлопнуть `\s+` в пробел, Trim) обе непустые и `candidate == prompt` или `candidate.Contains(prompt)`.
Наблюдатель (`xaml.cs:346-417`): `ReceiverEchoWatchWindow = 6 с`, `ReceiverEchoPollInterval = 200 мс`; один активный на пакет; цикл: delay 200; нет receipt → выход; `CaptureAsync` (ошибка → лог `Receiver echo watch: capture failed: {message}`, continue); seq равен → continue; `!IsReceiverEcho` → лог `PasteIntent package displaced by foreign clipboard write`, выход без публикации; эхо → взять гейт, `SetPackageGuardedAsync(paths, prompt, snapshot.Seq)`, лог `PasteIntent re-armed after receiver echo: from seq X to Y`, обновить receipt/prompt, `ClipboardChangedException` → лог displaced и выход; дедлайн += 6 с. `CancelReceiverEchoWatch()` из: `SaveAndCopyCommittedPackageAsync`, `CopyPackageAsync`, `RefreshOwnedClipboardAsync`, `StartNewSessionAsync`, `RepublishPackageForReuseAsync` (при вытеснении), `OnClosing`.

### 4.8 Диагностика `startup.log`
```
PasteIntent predicate: state not ready (resetting=…, transitionDone=…, gate=…, ownedSeq=…, intentSeq=…, prompt=…, prepared=…, gesture=…)
PasteIntent predicate: gesture {G} not intercepted
PasteIntent predicate: target mismatch (usable=…, process=…, hwnd=… vs …, pid=… vs …)
PasteIntent predicate: intercept=…, gesture=…, process=…, title=…, seq=…
PasteIntent observed: gesture=…, intercepted=…, seq=…, ownedSeq=…, pid=…
Clipboard diagnostics: seq=…, owner=…, formats=[…], text=…
Clipboard diagnostics failed: {message}
PasteIntent completion: intercepted=…, images=…, status=…, message=…
PasteIntent completion failed: {exception}
PasteIntent republished package: seq=…, images=…
Receiver echo watch: capture failed: {message}
PasteIntent re-armed after receiver echo: from seq X to Y
PasteIntent package displaced by foreign clipboard write
```
`LogClipboardDiagnosticsAsync`: владелец `"{ProcessName}({pid})"`/`"pid {n}"`/`"none"`; список форматов; текст из `UnicodeText` или `Text`, превью ≤120 символов, `\r`→пробел, `\n`→`|`, `<no text>`.
Статусы UI: успешная вставка + republish → «Вставлено: …»; вытеснен → «Пакет вытеснен другим приложением. Сессия сохранена.» (ошибка); «Снимки сохранены, но вставка не завершена: {message}»; «Не удалось подтвердить содержимое текущего пакета. Сессия сохранена.»; «Вставка замечена, но новая сессия не создана: {message}»; «Не удалось проверить буфер перед новым снимком: {message}»; «Автосохранение не выполнено: {message}».

### 4.9 Контракты (`TransportContracts.cs`)
`IClipboardService.SetPngOnlyGuardedAsync`; `PasteIntentObserved.IsIntercepted` (последний параметр, default false); `CodexPasteCompletionResult.CurrentClipboardReceipt => TextClipboardReceipt`; `ICodexDesktopPasteCompletionService.CompleteSequentialAsync(intent, receipt, images, prompt, ct)` и `CompleteClaudeAsync(...)`; `WindowsPasteIntentObserver(Func<PasteIntentObserved,bool>? shouldIntercept = null)`.

## 5. Тесты (для переноса в XCTest)
Итог на Windows: 90 тестов (14 imaging, 18 core, 58 transport) + smoke.

`ExtendedCommentsTests.cs` (Core, 3): `Labels_extend_beyond_one_alphabet` (0→A, 25→Z, 26→AA, 299→KN); `Hundreds_of_comments_preserve_identity_links_and_arrow_style_in_json` (300 заметок с одним `ParentAnnotationId` + `arrowStyle="curved"` round-trip JSON; prompt содержит `A301: Комментарий 299 (к области A1)`); `Cropping_keeps_comment_but_clears_a_removed_parent_link` (обрезка `(0,0,.5,.5)` выкидывает родителя, сохраняет заметку с `ParentAnnotationId == null` и текстом "Keep").

`ClipboardEchoDetectorTests.cs` (5), эталон `"Снимок A.\r\n  A1: тест1"`: `ReceiverEchoWithImagePlaceholder_IsDetected` (`"[Image #2]Снимок A.\r\n  A1: тест1"`); `ReceiverEchoWithExtraWhitespaceAndCrlf_IsDetected` (`"  Снимок   A.\n\n  A1:   тест1  \r\n"`); `UnrelatedForeignText_IsNotAnEcho`; `ForeignTextWithFiles_IsNotAnEcho`; `ClipboardWithImage_IsNotAnEcho`.

`PasteIntentObserverTests.cs`: новый `InterceptedPhysicalAltV_SuppressesTheGestureAndOwnPhysicalReleaseIsNotInjected`; существующие: `ControlV_IsReportedOnceUntilVIsReleased`, `AltV_IsReportedWithEitherAltKey`, `PlainV_ControlAltV_ExtraModifierV_AndInjectedV_AreIgnored`, `ReleasedModifierDoesNotRemainLatched`, `ResetClearsHeldAndRepeatState`, `InterceptedPhysicalV_SuppressesInitialAndRepeatKeyDownsUntilRelease`, `Interception_NeverSuppressesInjectedOrUnrelatedKeys`.

`CodexDesktopPasteCompletionServiceTests.cs`: `InterceptedCtrlVInArbitraryApp_DispatchesOrderedPngImagesThenImmutableTextViaCtrlV(imageCount)` («GrokBot»); `InterceptedAltVInTerminal_DispatchesOrderedPngImagesViaAltVThenTextViaCtrlV(imageCount)`; `InterceptedCodexDesktopIntent_StaysOnUnobservedCompleteAsyncPath_DoesNotWriteOrInject`; `InterceptedIntent_IsNotAlsoHandledByCodexCompletion`; `FocusLossAfterFirstImagePaste_ReturnsCurrentReceiptAndStopsSequence`; `ClipboardChangeAfterFirstImagePaste_StopsBeforeSecondImageAndText`; `CancellationAfterFirstImagePaste_ReturnsCurrentReceiptWithoutContinuing`; `AltVAndEmptyPrompt_DoNotInject`; `ReusablePackage_RepublishesFullPackageAfterCompletedPasteAndAcceptsNextIntent`; `ReusablePackage_DisplacedByAnotherAppLeavesClipboardUntouched`; прежние Codex-тесты без регрессий. Фейк: `FakeClipboard.SetPackageGuardedAsync` пишет `PACKAGE:<paths>` + `WrittenText`; `ExternalWrite()` инкрементит sequence.

WPF smoke (`SmokeTestRunner.cs`): `CaptureFeedbackSound.VerifyWaveHeaders()`; round-trip настроек с `AutoSaveCaptures=true, PlaySounds=false`; `AnnotationCanvas.VerifyHoverManipulation` (край rectangle/blur движим, угол ресайзабелен при активном другом инструменте; интерьер не ручка; инструмент не меняется; пин-комментарий без ручек и рамки); `CapturePreviewWindow.RunPreviewProbe`; `RunNoteAffordanceProbe` (команда комментария вооружает режим; один клик = один пин и снятие режима; заметка привязывается к выбранной аннотации; открытие второй заметки сворачивает первую (43 vs 270 px) и понижает z-index; чипы не пересекаются; восстановление свёрнутой заметки после Undo сохраняет текст; пустая необязательная заметка рамки удаляет только чип; Text пишет в `Text`; один Undo восстанавливает цвет и толщину).

## 6. Ассеты: аудио
`src/Snapik.App/Assets/Audio/`: `camera-shutter.wav` (30032 байт, ~340 мс, после коммита снимка), `camera-dial-click.wav` (13274 байт, ~150 мс, hover карточки и прокрутка, троттлинг 170 мс, подавление 400 мс после затвора). Оба 44.1 кГц 16-бит PCM моно, CC0. Программного регулятора громкости нет (зашито в записи: затвор −6.3 дБ, детент −4.5 дБ). Описание монтажа и SHA-256 в `src/Snapik.App/Assets/Audio/README.md`. На macOS копировать файлы как есть в бандл.
