# SPEC-DELTA-2B: дизайн редактора, предпросмотра, стопки, звука, настроек, тестов (разделы B–F)

## 0. Сквозные контракты (дописать в `CONTRACTS.md`, все исполнители пишут против них)
```swift
// Core (B)
public enum AnnotationKind { …; case comment }                       // JSON "comment"
public struct AnnotationItem { public var parentAnnotationId: SBGuid?; public var arrowStyle: String /* "straight" */ }
public struct HotkeySettings { public var autoSaveCaptures: Bool /* false */; public var playSounds: Bool /* true */ }
// Shell → Preview (D)
final class CapturePreviewWindowController {
    init(capture: CaptureItem, image: CGImage, displayLabel: String, language: String, playSounds: Bool,
         persist: @escaping (CaptureItem) async -> Void)
    func present(on screen: NSScreen?, completion: @escaping (_ markupRequested: Bool) -> Void)
}
enum CapturePreviewProbe { static func run(image: CGImage) throws }
// Shell → Stack (E1)
struct StackCaptureRow { let id: SBGuid; let label: String; let thumbnail: NSImage?; let noteCount: Int }
extension EdgeStackWindowController { func setSelectedCapture(_ id: SBGuid?) }
// Shell (звук), вызывается из Stack/ и App/
enum CaptureFeedbackSound { static func capture(enabled: Bool); static func tick(enabled: Bool); static func verifyWaveHeaders() throws }
// Editor → Shell (smoke)
extension AnnotationCanvasView { static func smokeVerifyHoverManipulation(image: CGImage) -> Bool }
extension OverlayEditorController { func smokeRunNoteAffordanceProbe() -> Bool /* one-shot comment */ }
// Imaging (editor-зона), используется автосохранением
enum ArrowDrawing { static func draw(in ctx: CGContext, from: CGPoint, to: CGPoint, color: CGColor, thickness: CGFloat, style: String) }
```

## B. Core-модель (`Sources/SnapikCore`)
| Файл | Изменение |
|---|---|
| `Models/AnnotationItem.swift:4-12` | `case comment` в конец `AnnotationKind` (rawValue `"comment"`). |
| `AnnotationItem.swift:36-127` | Поля `parentAnnotationId: SBGuid?`, `arrowStyle: String = "straight"`; `CodingKeys` `parentAnnotationId`, `arrowStyle`; `init(from:)` — `decodeIfPresent` (nil / `"straight"`); `encode(to:)` — `encode(parentAnnotationId)` (Optional кодирует `null`), `encode(arrowStyle)`. `create(...)` получает `parentAnnotationId: SBGuid? = nil, arrowStyle: String = "straight"`. Memberwise `init` — новые параметры в конце с дефолтами. |
| `Exporting/CaptureLabels.swift` | `forIndex`: `guard index >= 0`; `value = index+1; while value > 0 { value -= 1; label = Character(65 + value%26) + label; value /= 26 }` (`Int`, не `UInt8`). |
| `Exporting/PromptGenerator.swift` | `labeled = forNotedAnnotations(...)`; `labelsById`; после `"\(label): \(note)"` — если `parentAnnotationId` и есть метка родителя → `" (к области \(parentLabel))"`. |
| `Editing/CaptureCropper.swift` | `case .rectangle, .text, .redaction, .blur, .comment:` → `cropBox`. После цикла: `ids = Set(retained.map(\.id))`; у `retained` с `parentAnnotationId ∉ ids` → `nil`. |
| `Settings/HotkeySettings.swift` | `autoSaveCaptures = false`, `playSounds = true`; ключи `"AutoSaveCaptures"`, `"PlaySounds"`. Обязательно свой `init(from:)` с `decodeIfPresent` для всех полей (иначе старый `settings.json` тихо вернёт `.default`). |
| `Settings/UiLanguage.swift` | 27 пар в порядке `UiLanguage.cs` (Часть 1 §3): 4 после «Захватывать курсор»; блок предпросмотра/комментариев/стрелок после «Повторить» перед «Сохранить на компьютер»; 3 статусные в конец. Mac-only 5 пар оставить на месте. Обратный поиск зависит от порядка — не переставлять существующие. |
| `Models/SessionValidation.swift` | Ничего. |
Тесты: `Tests/SnapikCoreTests/ExtendedCommentsTests.swift` — порт `ExtendedCommentsTests.cs` (метки после Z; 300 заметок round-trip через `SnapikJson.encoder/decoder` с `parentAnnotationId`+`arrowStyle="curved"`, prompt содержит `"A301: Комментарий 299 (к области A1)"`; crop снимает связь, заметка "Keep" остаётся).

## C. Редактор (`Sources/SnapikMac/Editor` + `Imaging`)
**C1. `Imaging/ArrowDrawing.swift` (новый)**
```swift
enum ArrowDrawing {
    static func draw(in ctx: CGContext, from start: CGPoint, to end: CGPoint, color: CGColor, thickness: CGFloat, style: String)
    static func sampleImage(style: String, size: NSSize = NSSize(width: 64, height: 28)) -> NSImage  // NSImage(size:flipped:drawingHandler:), белый, thickness 2, (4,24)→(60,8)
}
```
`lineWidth = thickness * (bold ? 2 : 1)`; curved: `control = (mid.x − vec.y·0.25, mid.y + vec.x·0.25)`, `ctx.addQuadCurve(to:control:)`, `direction = control − end`; `size = min(len·0.7, max(10, lineWidth·3.2))`, `halfWidth = size·(wide ? 0.85 : 0.45)`; `setLineCap(.round)`, `setLineJoin(.round)`; `guard length >= 0.01`.
- `Imaging/AnnotationPainter.swift`: `.arrow` → `ArrowDrawing.draw(..., style: item.arrowStyle)`, удалить `drawArrowHead`; `drawShape`: `.comment` → ничего (бейдж рисует фаза 3). `ExportImageRenderer.swift` без изменений.

**C2. `Editor/EditorModels.swift`**: `EditorTool` `case comment = "N"`; `isOnToolbar`: `.text → true`, `.comment → false`. `EditorAnnotation`: `parentAnnotationId: SBGuid?`, `arrowStyle = "straight"`; `clone`, `toCore`, `fromCore` (`case .comment`), `coreKind`. `EditorGeometry.gestureHasSize`: `comment`/`text` → true. `+Appearance.swift hasColor`: `.comment → false`.

**C3. `Editor/EditorGeometry.swift`** — чистые функции:
```swift
static func findChipPlacement(preferred: CGPoint, size: CGSize, work: CGRect, occupied: [CGRect]) -> CGRect   // gap 6, clamp 8, 14 колец, 8 смещений (вниз, вправо, влево, вверх, 4 диагонали)
static func findMoveEdge(displayBounds: CGRect, point: CGPoint) -> Bool   // outer = inset(-6), inner = inset(min(6,w/2), min(6,h/2))
static func linkedCommentPoints(_ points: [CGPoint], oldParent: CGRect, newParent: CGRect, parentDelta: CGPoint, imageSize: CGSize) -> [CGPoint]
```
Удалить `positionChip`/`positionContextNoteButton`.

**C4. `Editor/AnnotationCanvasView.swift`**: `activeArrowStyle = "straight"`; draft получает `arrowStyle`. `mouseDown`: (1) `clickCount == 2` и hit `.text` → select, return; (2) `tool != .comment && (tool == .select || handleHit != nil || findMoveEdge(point) != nil)`; `hit = handleHit ?? findMoveEdge ?? hitTestAnnotation`; (3) `.comment` — draft `[start,start]`. `findResizeHandle`: пропускать `.comment`. Новый `findMoveEdge(_:) -> EditorAnnotation?` (rectangle/blur/conceal; nil при `.comment`). `mouseMoved`: курсор `handle ? .crosshair : (moveEdge || (select && hit comment)) ? .openHand : select ? .arrow : .crosshair`. `static func smokeVerifyHoverManipulation(image:) -> Bool` (view 480×300, край движим/угол ресайзабелен при чужом инструменте, интерьер не ручка, инструмент не меняется, comment без ручек). `+Drawing.swift`: `.arrow` → `ArrowDrawing.draw`; удалить `drawArrowHead`; `.comment: break`; outline только если `kind != .comment`.

**C5. `EditorToolbarView.swift`**: порядок Select, Rectangle, Arrow, **ArrowOptions (23 px, шеврон `M1,1 L4.5,4 L8,1`, 9×5, 1.5)**, **Text (в панели)**, Blur, Crop, Appearance, •••, Comment, |, Undo, Redo, Save, Done. Убрать `addCaptureButton` и `EditorStrings.addCapture`. `arrowOptionsButton` (icon-init `iconNativeSize: 9`, ширина 23). `commentButton.activeBackground = tool == .comment ? #284B78 : nil`; tooltip «Добавить комментарий (N)». `sizeToFitContent`: `place(arrowOptionsButton, width: 23)` после arrow.

**C6. `OverlayEditorController+Editing.swift`**: `showMoreToolsMenu` только Pen/Highlight/Conceal; `extraTools` без `.text`. Новый `showArrowStyleMenu()`: `NSMenu`, 4 `NSMenuItem` с `image = ArrowDrawing.sampleImage(style:)`, `state = .on` для текущего, target-прокси `ArrowStyleMenuTarget` (`representedObject = style`); действие: выбранная стрелка → `history.pushWithoutClearingRedo(snapshotState())`, `clearRedo()`, `arrow.arrowStyle = style`, `lastSnapshot = snapshotState()`, `needsDisplay`; иначе `selectTool(.arrow)`; затем `canvas.activeArrowStyle = style`, `syncAppearance()`. `wireToolbarActions`: убрать addCapture, добавить arrowOptions.

**C7. Чипы (`+Chips.swift`, `CommentChipView.swift`)**
- Состояние: `commentParentId: SBGuid?`, `expandedChipId: SBGuid?`; удалить `contextNoteButtonView`, файл `ContextNoteButtonView.swift`, `updateContextNoteAffordance`/`ensureContextNoteButton` и вызовы.
- `commentButtonClicked()` → `commentParentId = selected.kind == .comment ? selected.parentAnnotationId : selected?.id; selectTool(.comment)`. Клавиша N (`+Keys.swift`): `if tool == .comment { commentButtonClicked() } else { selectTool(tool) }`.
- `annotationCreated`: `.comment` → `parentAnnotationId = commentParentId; commentParentId = nil; points[1] = (min(W, p0.x+8), min(H, p0.y+8)); selectTool(.select)`; `pushHistory(); refreshLabels()`; для `.rectangle/.text/.comment` → `visibleChipIds.insert; addChip(focus: true)`.
- `annotationChanged`: сначала `moveLinkedComments()` (по `lastSnapshot`, `ResizeGeometry.map`).
- `refreshLabels`: бейдж = `label.isEmpty ? (kind == .text ? "T" : "+") : label`.
- `rebuildChips`: `visibleChipIds` ∪= id всех с непустой заметкой; все свёрнуты.
- `addChip`: `CommentChipView(annotationId:isTextInput:note:)`; колбэки `onNoteChanged`, `onCloseClicked → deleteAnnotationNote`, `onFocusGained → select + expand(true)`, `onHoverEntered → if !hasFocusedChipOtherThan(id) expand(true)`, `onHoverExited → if !chip.isEditing finish()`, `onBadgeClicked → focus + expand`, `onCommit (Enter) → finish(); makeFirstResponder(canvas)`, `onFocusLost → DispatchQueue.main.async { if !isEditing && !isHovered finish() }`.
- `expandChip(id, expanded)`: свернуть остальные (кроме с фокусом), `expandedChipId`, `chip.setExpanded` (270/43; Text-чип при сворачивании `isHidden`), z-order через `sortSubviews` (не removeFromSuperview), `repositionChips()`, `positionToolbar()`.
- `finishChip(id)`: не text и заметка пуста → снять чип, для `.comment` удалить аннотацию + deselect, `lastSnapshot = snapshotState()`, refresh/reposition; иначе `expand(false)`.
- `deleteAnnotationNote`: `.comment` → удалить аннотацию; `!= .text` → `note = ""`.
- `repositionChips`: раскрытый первым, остальные по индексу; размер `(chip.width, expanded ? max(90, preferredHeight) : 40)`; раскрытый сохраняет позицию; `findChipPlacement(preferred: (crop.minX+bounds.minX, crop.minY+bounds.maxY+8), …, occupied)`.
- Клик вне чипов: `OverlayWindow.sendEvent` для `.leftMouseDown` → `onMouseDown?(event)`; контроллер: hit view не потомок `chipViews[expandedChipId]` → `finishChip`. Дабл-клик по text-аннотации → показать/сфокусировать её чип.
- Новый `ChipLayerView: NSView` (flipped, `hitTest` → nil вне сабвью) — хост чипов в `OverlayContentView`.
- `CommentChipView`: `expandedWidth = 270`, `collapsedWidth = 43`; `isExpanded`, `isEditing { window?.firstResponder === textView }`, `isHovered`; tracking area; `AnnotationBadgeView` кликабелен; при свёрнутом только бейдж.
- `EditorTextView` (`+Keys.swift`): `onCommit`; keyCode 36/76 без модификаторов → `onCommit`, с Shift → `insertNewline(nil)`.
- Legacy note в `presentExisting`: `capture.note` непуст → `EditorAnnotation(kind: .comment, points: [(24,24),(32,32)], note:)`, `note = ""`.
- `restoreState` → `rebuildChips` (все свёрнуты, текст сохранён).

**C8. Smoke-хуки `+SmokeTest.swift`**: `smokeRunNoteAffordanceProbe` по `xaml.cs:107-202` (стрелка → select → `commentButtonClicked()` → tool == .comment → `smokeCreateComment(at:)` → tool == .select, 1 чип, parent == arrow.id, текст → note; второй комментарий → первый 43, второй 270, порядок, `!frames.intersects`; `deleteAnnotationNote`; пустой прямоугольник → `finishChip` удаляет только чип; Text → `text`; один Undo восстанавливает цвет/толщину) + `smokeVerifyHoverManipulation`.
Строки `EditorStrings.swift`: `addCommentWithKey`, `arrowStyle`, `arrowStraight/Curved/Bold/Wide`; убрать `addCapture`.

## D. Окно предпросмотра (`Sources/SnapikMac/Preview/`, новая папка)
- `PreviewGeometry.swift`: `previewBounds(workArea: CGRect) -> (frame: CGRect, minSize: CGSize)` (width = min(1100, wa.w−32), height = min(760, wa.h−32), центр; min = (min(720,…), min(500,…))); `fitZoom(viewport:image:) = clamp(min((w−8)/W,(h−8)/H), .05, 4)`.
- `PreviewCommentsModel.swift` (без UI): `capture`, `displayLabel`, `entries: [PreviewCommentEntry]`, `rebuild()`, `refreshLabels()`, `addComment() -> PreviewCommentEntry`, `delete(_:)`, `setText(_:for:)`; `PreviewCommentEntry { id: UUID; annotationId: SBGuid?; label; relation; text }`. Логика: список = снимок-комментарий (если `hasContent(note)`) + все `kind == .comment || hasContent(note)`; связь `"К отметке " + annotationName(parent)` / `"К снимку " + label`; `annotationName`: метка из `forNotedAnnotations`, иначе `"\(label)·\(index среди не-comment + 1)"`; пустой → `"+"`; новый пин центр `(0.5,0.5)`, `(0.5+8/W, 0.5+8/H)` clamp; удаление: comment → remove, иначе `note = ""` / `capture.note = ""`.
- `PreviewRenderer.swift`: `render(capture:image:displayLabel:) -> CGImage?` через `AnnotationPainter.draw(showLabels, labelFor из CaptureLabels, sourceImage, labelStyle: .screen)`.
- `PreviewImageScrollView.swift`: `NSScrollView` (`allowsMagnification`, `minMagnification 0.05`, `maxMagnification 4`), `scrollWheel` с `.command` → `setMagnification(mag * (deltaY > 0 ? 1.12 : 1/1.12), centeredAt:)`; documentView — flipped `NSView` с CGImage, `frame = W×H` точек; `onViewportResized`.
- `PreviewCommentEntryView.swift`: карточка `#202630`, r=10, padding 9: метка (`#7AB8FF`, 11 semibold) + связь (`#8F9AAA`, 11), удаление 28×28, `NSTextView` в `NSScrollView` (54…150, bg `#1C222B`, border `#3A4451`/focus `#7AB8FF`, r=8); `onTextChanged`, `onDelete`.
- `PreviewCommentsPanelView.swift`: 292 px, bg `#171B22`, r=10, padding 12: «Комментарии» + кнопка добавить (32×32, иконка `M1,1 L10,1 L10,8 L6,8 L3,11 L3,8 L1,8 Z M12,5 L12,13 M8,9 L16,9`), `NSScrollView` с flipped-стеком, «Нет комментариев»; `reload(entries:)`, `scrollToLast + focus`.
- `PreviewHeaderView.swift`: 46 px, bg `#171B22`: бейдж 24 (`#2F8CFF`, 11 bold), «Просмотр снимка» (semibold `#EEF2F8`), `"W × H"` (`#8F9AAA` 11), справа: −, zoom% (43 px, `#B9C3D1` 11), +, «По размеру окна» (рамка `#7AB8FF` при fit), «100%», fullscreen, «Разметка» (`#2F8CFF`, semibold), закрыть. Кнопки 32 high, bg `#242A33`, border `#3A4451`, r=8, hover `#323B48`/`#657388`; `mouseDown` на пустой области → `window.performDrag(with:)`.
- `CapturePreviewWindowController.swift` (`NSWindowController, NSWindowDelegate`): окно `styleMask: [.titled, .fullSizeContentView, .resizable, .closable, .miniaturizable]`, `titlebarAppearsTransparent`, `titleVisibility = .hidden`, стандартные кнопки скрыты, `isMovableByWindowBackground = false`, `backgroundColor = #101318`, `minSize`; позиция по `previewBounds((screen ?? NSScreen.screens.first).visibleFrame)`; показ: запомнить `previousFrontmostApplication`, `NSApp.activate(ignoringOtherApps: true)`, `makeKeyAndOrderFront`; через `asyncAfter(0.4)` → `updateFitZoom()`, `canAutoClose = true`; `windowDidResignKey` → `if canAutoClose && !closing { closePreview() }`; закрытие → `flushEdits()` → `completion(markupRequested)` → `previousFrontmostApplication?.activate` (если не markup). Зум ×1.2, `[0.1, 4]`, fit; fullscreen: `setFrame(screen.visibleFrame)` ↔ сохранённый; клавиши в `PreviewWindow.sendEvent`: Esc (53), F11 (103) или Cmd+Ctrl+F, Cmd+0/1/=/−/+; дебаунс `Timer 0.36 s` → перерендер + `persistChain = Task { await previous; await persist(model.capture) }`.
- `CapturePreviewProbe.swift`: `run(image:) throws` — пустой «+», метка после ввода = последняя из `forNotedAnnotations`, удаление сдвигает метки, 300 записей, `previewBounds(workArea: (-1920,0,1920,1080))` внутри области. XCTest `Tests/SnapikMacTests/Preview/PreviewModelTests.swift`, `PreviewGeometryTests.swift`.
Строки через `MacUiText.text`.

**Интеграция в shell (`App/AppCoordinator.swift`, зона core-shell)**: `openCapture(id)` → загрузить изображение, `stackWindow.setSelectedCapture(id)`, `isBusy = true`, `CapturePreviewWindowController(persist: { [weak self] updated in await self?.persistPreviewChanges(updated) })`, `present(on: stackWindow?.window?.screen) { markup in setSelectedCapture(nil); isBusy = false; if markup { Task { await self.openCaptureForMarkup(id) } } }`. `openCaptureForMarkup` = нынешнее тело (hide → frame → `presentExisting`). `persistPreviewChanges(_ capture)`: guard сессия содержит id; `workspace.replaceCapture`; `stackWindow.invalidateThumbnail(id)`; `refresh()`; `invalidatePrepared()`; `if await save() { await refreshOwnedClipboard() }`.

## E. Стопка, звук, автосохранение, настройки
**E1. Карточки-гармошка (`Stack/`, исполнитель preview)**: `Stack/StackMetrics.swift` (`width 208`, `cardHeight 78`, `cardOverlap 48` (шаг 30), `expandedMargin 4`, `listMaxHeight 372`, `listBottomPadding 52`, `expandIn 0.18`, `expandOut 0.16`, `selectedBorder #7AB8FF`, `hoverBorder #718096`, `cardBorder #46505E`, `cornerRadius 11`). `ThumbnailCardView`: высота 78, r=11; полоса 26 (`#E6171A20`) — бейдж 20 + иконка заметки 10×10 (`M1,1 L9,1 L9,7 L5,7 L2,9 L2,7 L1,7 Z`, `#AEB8C7` 1.2) + `noteCount` (`#DCE3ED`, 11); `isSelected`, `isHovered`; `onHoverChanged`; `mouseEntered` → `CaptureFeedbackSound.tick(enabled:)`; удаление opacity 1 при hover/selected; `configure(id:label:image:noteCount:)`. `EdgeStackContentView.layoutCards` аккордеон: `y = 0; expanded = hover||selected; top = expanded ? y+4 : y; frame = (0, top, w, 78); y = expanded ? top+78+4 : top+30`; документ `y + 52`; z-порядок `sortSubviews` (hover 20, selected 30); анимация `NSAnimationContext` 0.18/0.16 easeOut; `listHeight = min(372, contentHeight)`; drag-reorder по `cardViews.firstIndex { $0.frame.contains(point) }`; `TickingScrollView: NSScrollView { scrollWheel → onScroll?() }`; `setSelectedCapture(id)`; `reload(rows:)` с `noteCount`. `EdgeStackWindowController.refresh()`: `noteCount = annotations.filter{hasContent(note)}.count + (hasContent(note) ? 1 : 0)`; ширина 208.

**E2. Звук (`App/CaptureFeedbackSound.swift`, исполнитель shell)**: ресурсы `Sources/SnapikMac/Resources/Audio/camera-shutter.wav`, `camera-dial-click.wav` (копия из `src/Snapik.App/Assets/Audio/`; README в `macos/Resources/AUDIO-README.md`). `Package.swift`: `.executableTarget(..., resources: [.copy("Resources/Audio/camera-shutter.wav"), .copy("Resources/Audio/camera-dial-click.wav")])`. `project.yml`: `.wav` из `sources` попадают в Copy Bundle Resources (плоско `Contents/Resources/*.wav`); `excludes: ["Resources/**/*.md"]`. Загрузка: `Bundle.main.url(forResource:withExtension:)`, затем `#if SWIFT_PACKAGE Bundle.module.url(...) #endif`. Плеер `NSSound(data:)`; `play()`: `stop(); play()`. Троттлинг по `DispatchTime.now().uptimeNanoseconds`: `capture(enabled)` фиксирует время; `tick(enabled)` — 400 мс после затвора и 170 мс между тиками. `verifyWaveHeaders() throws`: `RIFF`/`WAVE`/`data` @0/8/36, `UInt32 LE @4 == count−8`, `Int16 @20 == 1`, `@22 == 1`, `UInt32 @24 == 44100`, `Int16 @34 == 16`, `UInt32 @40 == count−44` (`loadUnaligned`). Вызов: `AppCoordinator+OverlayEditorDelegate.swift` ветка `appendCapture` после `saveAndCopyCommittedPackage`: `CaptureFeedbackSound.capture(enabled: settings.playSounds)`, затем `await autoSave(committed)`.

**E3. Автосохранение (`App/AutoSaveService.swift`)**: `save(capture:displayLabel:sessionDirectory:settings:) throws -> URL`: `ImageCodec.loadImage`, flipped `CGContext`, `AnnotationPainter.draw(showLabels: true, labelFor, sourceImage, labelStyle: .screen)`, `FastSaveService.newPath` + `ImageCodec.encode/writeAtomically`. В координаторе: `guard settings.autoSaveCaptures`; успех → `if settings.showNotifications { notify("Снимок сохранён") }`; ошибка → статус «Автосохранение не выполнено: …».

**E4. Настройки (`Settings/`)**: `SettingsTabViews.swift`: `soundsBox` после `captureCursorBox`, `autoSaveBox` первым на «Сохранение»; `HotkeySettingsWindowController.swift`: высота 520; `populateFields`, `buildCandidateSettings` — два флага; `saveClicked`: `guard !directory.trimmed.isEmpty else { showError("Укажите папку сохранения.") }`, `saveDirectory = expandingTildeInPath → standardizedFileURL.path`.

## F. Тесты и smoke
- Core: `ExtendedCommentsTests.swift`.
- Mac: `Tests/SnapikMacTests/Preview/PreviewGeometryTests.swift`, `PreviewModelTests.swift`; `Tests/SnapikMacTests/Editor/EditorGeometryChipTests.swift` (`findChipPlacement` без пересечений, `findMoveEdge`); `Tests/SnapikMacTests/Imaging/ArrowDrawingTests.swift` (4 стиля в 200×100 → непрозрачные пиксели у конца; curved ≠ straight); `Tests/SnapikMacTests/App/CaptureFeedbackSoundTests.swift` (`verifyWaveHeaders` не бросает; `HotkeySettings` decode без новых ключей → дефолты).
- `App/SmokeTestRunner.swift`: `custom.autoSaveCaptures = true; custom.playSounds = false`; проверка `"wav headers"`; `530x520`; `check("hover manipulation", AnnotationCanvasView.smokeVerifyHoverManipulation(image:))`, `check("preview probe", (try? CapturePreviewProbe.run(image:)) != nil)`; `noteAffordanceOk` в новом смысле.
- `DemoSessionFactory.seedDemoSession`: добавить одной аннотации связанный `comment` и `arrowStyle: "curved"`.

## Разбиение (папки не пересекаются)
| Исполнитель | Папки | Задачи |
|---|---|---|
| core-shell | `Sources/SnapikCore/{Models,Editing,Exporting,Settings}`, `Tests/SnapikCoreTests/ExtendedCommentsTests.swift`, `Sources/SnapikMac/App/**` (кроме файлов транспорта: `AppCoordinator+PasteIntent.swift`, `PasteInterceptPredicate.swift`, `AsyncGate.swift`), `Sources/SnapikMac/Settings/**`, `Sources/SnapikMac/Resources/**`, `Tests/SnapikMacTests/App/**` (кроме `PasteInterceptPredicateTests.swift`), `Package.swift`, `project.yml`, `CONTRACTS.md` | B, E2–E4, интеграция D в `AppCoordinator.openCapture`, smoke, demo-сид |
| transport | `Sources/SnapikCore/Transport/**`, `Tests/SnapikCoreTests/Transport/**`, `Sources/SnapikMac/Transport/**`, `Tests/SnapikMacTests/Transport/**`, новые `App/AppCoordinator+PasteIntent.swift`, `App/PasteInterceptPredicate.swift`, `App/AsyncGate.swift`, `Tests/SnapikMacTests/App/PasteInterceptPredicateTests.swift`; правки `App/AppCoordinator.swift` и `+Package.swift` только в точках §4 (согласовано с core-shell: transport делает эти правки, core-shell не трогает `handlePasteIntent`/`completePasteIntent`/`ensureCurrentCaptureSession`/`startNewSession`) | A |
| editor | `Sources/SnapikMac/Editor/**`, `Sources/SnapikMac/Imaging/**`, `Tests/SnapikMacTests/{Editor,Imaging}/**` | C |
| preview | `Sources/SnapikMac/Preview/**`, `Sources/SnapikMac/Stack/**`, `Tests/SnapikMacTests/Preview/**` | D, E1 |

## Риски компиляции (проверять дважды)
1. Новые case `AnnotationKind`/`EditorTool` ломают exhaustive `switch` (`EditorModels.swift`, `+Drawing.swift`, `+Appearance.swift`, `isOnToolbar`, `CaptureCropper.swift`). 2. `HotkeySettings` без `decodeIfPresent` → тихая регрессия. 3. `Bundle.module` только под `#if SWIFT_PACKAGE`; `resources:` пути должны существовать. 4. `NSImage(size:flipped:drawingHandler:)` → `(NSRect) -> Bool`. 5. `NSMenuItem.image` + `state = .on`. 6. z-order чипов через `sortSubviews`. 7. `NSCursor.openHand`. 8. `setMagnification(_:centeredAt:)` в координатах documentView. 9. Окно предпросмотра `.titled + .fullSizeContentView`. 10. Shift+Enter перехватывать в `keyDown` по keyCode. 11. `Timer.scheduledTimer` invalidate при закрытии. 12. `loadUnaligned` (Swift 5.7+). 13. Smoke `530x520` синхронно с окном.
