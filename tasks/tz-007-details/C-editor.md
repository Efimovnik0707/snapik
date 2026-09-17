# C · Редактор (C1 линия и точка комментария, C2 форма у размытия)

Разбор по `master` `6b06f7e`, код на коммите `1df53ce` (версия 1.6.1). Пути от `src/Snapik.App/`, если не сказано иначе. ТЗ: `tasks/handoff-007/TZ-006-v160-test.md`, раздел C. Свидетельства: `tasks/handoff-007/evidence/comment-leader-x5.png`, `export-leader-x3.png`, `session-comment-points.json`.

Все ссылки ТЗ даны по `dea725a`; после него вошли `53c921d`, `a3861c7`, `1df53ce`. `AnnotationCanvas.cs` вырос на 59 строк (`VerifyScalingRules` и `ApplyScalingMode`), `OverlayEditorWindow.xaml.cs` на 32, `OverlayEditorWindow.Appearance.cs` на 15. Ниже все адреса пересчитаны на HEAD; расхождения с ТЗ перечислены в §0.

Соседние дорожки: лента (B) и настройки (A, D) у других аналитиков. Здесь только C1 и C2 плюс стыки, перечисленные в §3.

---

## 0. Где картина шире или причина другая, чем в ТЗ

### 0.1. Вторую точку нельзя просто перестать дописывать: комментарий исчезнет при обрезке

ТЗ предлагает развилку: «либо не дописывать вторую точку вовсе, либо `TryLeader` для комментария получает точку». Первый путь ломает обрезку.

Черновик любой отметки рождается с **двумя** точками (`Controls/AnnotationCanvas.cs:398`, `Points = [_gestureStart.Value, _gestureStart.Value]`), и у комментария вторая точка при перетаскивании не двигается: тянут `NoteOffset`, а не `Points[1]` (`:486-494`). То есть «не дописывать» означает не «одна точка», а «две совпадающие». Дальше:

* `CaptureCropper` обрезает комментарий через `CropBox` (`src/Snapik.Core/Editing/CaptureCropper.cs:55-61`), а `CropBox` возвращает пустой массив, если `right - left <= Epsilon || bottom - top <= Epsilon` (`:123-126`, `Epsilon = 1e-12`, `:21`). Пустой массив означает `removed` (`:63-66`): **комментарий с двумя совпадающими точками удаляется при любой обрезке снимка.** Квадрат 8 × 8 сегодня ровно это и предотвращает.
* `HitTestAnnotation` (`Controls/AnnotationCanvas.cs:756-773`) расширяет `BoundsOf` на `max(8, Thickness/2 + 4)`. Через него идут `grabbed`/`under` в `OnMouseLeftButtonDown` (`:296-297`), то есть двойной клик «открыть пилюлю» (`AnnotationRules.PressTarget.Activate`, `:325-328`) и запасной захват. С вырожденным прямоугольником зона сжимается примерно вдвое.
* `RepositionChips` кладёт пилюлю непереставленного комментария под его прямоугольник (`OverlayEditorWindow.xaml.cs:1783`, `:1813` `annotationBounds.Bottom + 8`), `UpdateNoteButton` ставит кнопку «заметка» справа от него (`:1515-1517`). Сдвиг на 8 px, мелочь, но видимая.

Что **не** зависит от второй точки: `GestureHasSize` для комментария всегда `true` (`Controls/AnnotationCanvas.cs:959`), ручек размера у комментария нет (`:950` `HasResizeHandles`), перемещение идёт через `_badgeDrag`/`_anchorDrag` (`:330-357`), а не через `_originalBounds`, `SessionValidation` требует только непустой список точек (`src/Snapik.Core/Models/SessionValidation.cs:52`), `PromptGenerator` точек комментария не читает вовсе (`src/Snapik.Core/Exporting/PromptGenerator.cs:22-58`), `MoveLinkedComments` в коде больше нет.

**Рекомендация: идти вторым путём и только им.** Вторая точка остаётся в модели как прямоугольник комментария (обрезка, хит-тест, двойной клик, раскладка пилюль), а из расчёта линии выводится явно: для `Kind == Comment` выноска считается от `Points[0]`, а не от `BoundsOf`. Строку `OverlayEditorWindow.xaml.cs:1431` не трогать, дописать к ней комментарий «зачем», чтобы её не сняли в следующем раунде.

Это не только «меньше правок». Обратная совместимость делает второй путь обязательным в любом случае: в сессиях Кати у комментариев уже лежат две точки с разницей 8 px (`evidence/session-comment-points.json`, три комментария снимка A). Если поправить только запись новых комментариев, её старые сессии откроются со старой кривой линией. Значит правило «линия от точки» должно жить в отрисовке, а не в создании.

### 0.2. Рисовальщиков выноски не два, а три

ТЗ говорит про экран и экспорт. Третий путь: `AnnotationCanvas.RenderAnnotated()` (`Controls/AnnotationCanvas.cs:716-735`), тот же `DrawAnnotation`, но с `includeSelection: false` и в пиксельных координатах снимка. Через него идут **«Сохранить на компьютер»** из редактора (`OverlayEditorWindow.Save.cs:48`) и сохранение снимка из ленты (`EdgeStackWindow.Saving.cs:27`).

Сегодня там выноска рисуется (из `BoundsOf`), а точка нет: условие точки требует `includeSelection` (`:844`). Если починить только линию, файл, сохранённый на диск, получит линию, обрывающуюся в воздухе, ровно как жалоба Кати по экспорту. Правку условия точки (`includeSelection &&` убрать, оставив `includeSelection` только на увеличении радиуса при наведении) считать частью C1. Одна строка, зато «Сохранить на компьютер» и «в чат» дают одну картинку.

### 0.3. Точка в экспорте: размер, цвета, поля

* Масштаб. `ExportLeaderThickness` (`Imaging/NoteBadgeGeometry.cs:40-41`) это `max(1, ExportDiameter/ScreenDiameter)`. Для однобуквенного номера `ScreenDiameter = max(26, 19) = 26`, `ExportDiameter = max(34, 25) = 34`, отношение ≈ 1.31. Радиус точки в экспорте ≈ 6.5 px, белая обводка ≈ 2 px. Отношение стоит вынести в отдельный `ExportScale(label)` и выразить через него и толщину линии, и радиус точки, и обводку, чтобы три числа не разъехались.
* Цвета. На экране точка это `AccentPalette.Brush` с белым пером 1.5 (`Controls/AnnotationCanvas.cs:848`). В экспорте `AccentPalette.Brush` уже используется для бейджа (`WpfExportImageRenderer.cs:176`), так что «акцент плюс белая обводка» берётся один в один.
* «Только у комментариев с `NoteOffset`». В экспорте выноска уже обёрнута в `if (item.NoteOffset is not null)` (`WpfExportImageRenderer.cs:180`), точка ставится внутрь того же блока плюс проверка `item.Kind == AnnotationKind.Comment`. Отдельного условия писать не надо.
* `ExportMargins` (`Imaging/NoteBadgeGeometry.cs:66-87`) считает поле только по бейджам. Точка сидит на `Points[0]`, а якорь при перетаскивании клампится в снимок (`Controls/AnnotationCanvas.cs:425`, `ClampToImage`), поэтому точка всегда внутри снимка и за лист выйти может максимум на ~6.5 px, если якорь стоит вплотную к краю. Клипа в экспорте нет (`WpfExportImageRenderer.RenderAsync`, `:52-70`), лист режет только по своей границе. **Рекомендация: `ExportMargins` не трогать.** Она покрыта девятью тестами (`tests/Snapik.App.Imaging.Tests/NoteBadgeGeometryTests.cs`), задаёт байты экспорта и переносится на Mac; ради полукруга в углу менять её невыгодно. Записать как известное ограничение.

### 0.4. C2: почему капсула переключает инструмент и что значит «форма одна»

* Переключение. `BuildShapeMenu` при выборе формы делает `SelectToolMode(EditorTool.Rectangle)`, если выделенная отметка не рамка и не блюр (`OverlayEditorWindow.Shapes.cs:64`). С размытием в руке и пустым выделением условие срабатывает, `SelectToolMode` ставит `Surface.Tool = Rectangle` и снимает выделение (`OverlayEditorWindow.xaml.cs:1397-1406`). Это и есть «размытие из руки уходит». У **выделенного** блюра этой ветки нет: форма применяется на месте, инструмент не меняется.
* «Форма одна» уже сделана, но хранится в двух местах. Читается всегда с рамки: `ActiveShape => AppearanceOf(EditorTool.Rectangle).Shape` (`OverlayEditorWindow.Appearance.cs:104`), новый блюр берёт её из `Surface.ActiveShape` (`Controls/AnnotationCanvas.cs:388`). Пишется в обе записи сразу: `_tools[Rectangle]` и `_tools[Blur]` (`OverlayEditorWindow.Appearance.cs:394-397`), и обе попадают в `settings.json` через `ToolAppearanceStore` (`ToolAppearance.cs:87-102`, ключи всех шести инструментов). «Не раздваивать» я читаю как «не заводить отдельную форму у размытия», а не «снять зеркало»: зеркало держит `toolAppearance.blur.shape` в файле согласованным, снятие оставит там протухшее значение, которое прочитает Mac. **Рекомендация: зеркало оставить, комментарий у `:392-393` расширить.**
* `SecondCapsule.None` сегодня объявлен (`ToolAppearance.cs:158`), но не выдаётся ни одним инструментом и нигде не обработан. `SyncAppearance` для `None` уйдёт в `default` и покажет «Толщина» и «4 px» (`OverlayEditorWindow.Appearance.cs:251-264`), `OnLineCapsuleClick` откроет поповер толщины (`:511-519`). Значит C2 это не одна строка в `InspectorViewOf`, а ещё и ветка `None` в `SyncAppearance`.

### 0.5. Формат данных: не меняется

* `session.json`: у комментария по-прежнему две точки (рекомендация §0.1), `noteOffset` как был. Ничего нового не пишется и не снимается.
* `settings.json`: `toolAppearance.blur.shape` продолжает писаться (§0.4). Ключи прежние.
* Абзац «Изменение формата» по правилу 4 `AGENTS.md` **не нужен**. Нужны две строки в `tasks/verification.md` по правилу 5, потому что Mac-порт переносит поведение: (1) выноска комментария идёт от центра `Points[0]`, обрывается на ободе точки радиуса 5 (в экспорте 5 × масштаб) и на ободе бейджа, `Points[1]` в расчёте не участвует и остаётся только как прямоугольник для обрезки и хит-теста; (2) у размытия блока свойств нет совсем, форма берётся у рамки.

### 0.6. Адреса ТЗ, которые не сходятся

| В ТЗ (`dea725a`) | На HEAD | Что на самом деле |
|---|---|---|
| `OverlayEditorWindow.xaml.cs:1401` | `:1431` | запись `Points[1] = Points[0] + (8, 8)` |
| `AnnotationCanvas.cs:778-783` | `:831-837` | выноска на экране |
| `AnnotationCanvas.cs:791-796` | `:844-849` | точка на экране |
| `AnnotationCanvas.cs:930-931` | `:983-984` | `AnchorRadius = 5`, `AnchorHoverRadius = 7` |
| `AnnotationCanvas.cs:335` | `:388` | блюр берёт `ActiveShape` у черновика |
| `OverlayEditorWindow.Appearance.cs:496-505` | `:511-520` | `OnLineCapsuleClick` |
| `OverlayEditorWindow.xaml.cs:1005, 1035` | `:1035`, `:1065` | пробы с комментарием из двух точек |
| `AnnotationCanvas.cs:1287` | **адрес неверный** | на `dea725a` это `if (annotations.Count(...) != 2)`, проверка числа булавок. Булавки там ставятся жестом, то есть с двумя **совпадающими** точками, править нечего. Литеральные две точки с `+8` лежат в `VerifyHoverManipulation`, на HEAD `Controls/AnnotationCanvas.cs:1449-1453` |

`NoteBadgeGeometry.cs:40-41`, `:94-106`, `OverlayEditorWindow.Appearance.cs:104`, `OverlayEditorWindow.Shapes.cs:49-67`, `ToolAppearance.cs:179`, `WpfExportImageRenderer.cs:180-187`, `OverlayEditorWindow.xaml:310` совпали с ТЗ без сдвига.

Проверки, которые ТЗ не называет, а они существуют и упадут или должны быть дописаны: смоук-проба экспорта переставленного бейджа (`SmokeTestRunner.cs:467-493`), `tests/Snapik.App.Imaging.Tests/ToolAppearanceTests.cs:32` (ожидает `Blur → SecondCapsule.Shape`), проба ширины блока по инструментам (`OverlayEditorWindow.xaml.cs:472-480`).

---

## 1. C1 · Линия комментария от центра точки, точка в экспорте

### 1.1. Причина

`DrawAnnotation` ведёт выноску от прямоугольника отметки, одинаково для всех видов:

```
Controls/AnnotationCanvas.cs:831-837
  if (item.NoteOffset is not null)
  {
      var badgeBounds = BoundsOf(item);
      var outline = new Rect(Map(badgeBounds.TopLeft), Map(badgeBounds.BottomRight));
      if (NoteBadgeGeometry.TryLeader(outline, badge, out var from, out var to))
          dc.DrawLine(new Pen(badgeBrush, 1), from, to);
  }
```

`TryLeader` берёт `from` как ближайшую к бейджу точку прямоугольника (`Imaging/NoteBadgeGeometry.cs:96-98`, `Math.Clamp` по обеим осям). Для комментария прямоугольник это квадрат 8 × 8 от `Points[0]` до `Points[1]` (`OverlayEditorWindow.xaml.cs:1431`), поэтому при бейдже справа-сверху линия начинается в правом верхнем углу квадрата, то есть на 8 px правее центра точки и на её высоте. Ровно это видно на `evidence/comment-leader-x5.png`.

В экспорте то же самое, `outline` собирается из всех точек отметки (`WpfExportImageRenderer.cs:182-185`), результат тот же квадрат. Точка в экспорт не попадает вовсе: её условие требует `includeSelection` (`Controls/AnnotationCanvas.cs:844`), а экспорт рисует своим кодом, где точки нет. `evidence/export-leader-x3.png`: у A1 линия обрывается в воздухе, у A3 (без `NoteOffset`) нет ни линии, ни точки, и это правильно.

### 1.2. Варианты и рекомендация

**Вариант A (рекомендуемый).** `TryLeader` получает необязательный отступ от начала, а вызывающие для комментария передают вырожденный прямоугольник в точке `Points[0]` и радиус точки.

```csharp
// Imaging/NoteBadgeGeometry.cs
internal static bool TryLeader(Rect bounds, NoteBadge badge, out Point from, out Point to, double fromRadius = 0)
```

Внутри после нормализации направления: `if (length <= badge.Radius + fromRadius + 1) return false; from += direction * fromRadius;`. Вырожденный `new Rect(anchor, anchor)` даёт `from == anchor` без единой ветки «если комментарий» внутри геометрии, а `fromRadius` убирает линию из кружка.

Плюсы: одна сигнатура на всех трёх рисовальщиков, рамки и стрелки продолжают звать её с `fromRadius = 0` и вести линию от контура, старые сессии с квадратом 8 × 8 рисуются по-новому, потому что правило живёт в отрисовке.

**Вариант B.** Отдельная перегрузка `TryLeader(Point anchor, double anchorRadius, NoteBadge badge, out …)`. Читается чуть яснее, но дублирует шесть строк расчёта и даёт две точки правки при следующем изменении. Хуже.

**Вариант C (отвергнут).** Снять `Points[1] = Points[0] + (8, 8)` и считать выноску от `BoundsOf`, который станет точкой. См. §0.1: комментарий будет удаляться при обрезке, а старые сессии Кати останутся кривыми. Если Никита всё же захочет одноточечный комментарий, это тянет правку `CaptureCropper` в `Snapik.Core` (общий с Mac) и абзац «Изменение формата». Не рекомендую.

### 1.3. Точные места правки

1. **`Imaging/NoteBadgeGeometry.cs:40-41`.** Ввести `internal static double ExportScale(string label) => Math.Max(1, ExportDiameter(label) / ScreenDiameter(label));` и переписать `ExportLeaderThickness` как `ExportScale(label)`. Смысл прежний, теперь одно число на толщину линии, радиус точки и её обводку.
2. **`Imaging/NoteBadgeGeometry.cs:43`, `:45`.** `ScreenDiameter` и `ExportDiameter` сделать `internal` (нужны тесту на масштаб точки) либо оставить приватными и проверять масштаб только через `ExportScale`. Второе достаточно, менять видимость не обязательно.
3. **`Imaging/NoteBadgeGeometry.cs` рядом с `:90`.** Константа радиуса точки: `internal const double AnchorRadius = 5;`. Сейчас 5 живёт приватной константой в холсте (`Controls/AnnotationCanvas.cs:983`). Файл геометрии существует именно затем, чтобы экран и экспорт сходились, число должно лежать там.
4. **`Imaging/NoteBadgeGeometry.cs:94-106`.** Добавить параметр `double fromRadius = 0` и учесть его, как в §1.2. Комментарий над методом дополнить: «у комментария начало это центр его точки, а не угол прямоугольника».
5. **`Controls/AnnotationCanvas.cs:983`.** `AnchorRadius` заменить на ссылку `NoteBadgeGeometry.AnchorRadius`, `AnchorHoverRadius = 7` оставить на месте (это только наведение).
6. **`Controls/AnnotationCanvas.cs:831-837`.** Развилка по виду отметки:

   ```csharp
   var comment = item.Kind == EditorTool.Comment;
   var anchor = Map(item.Points[0]);
   var outline = comment
       ? new Rect(anchor, anchor)
       : new Rect(Map(BoundsOf(item).TopLeft), Map(BoundsOf(item).BottomRight));
   if (NoteBadgeGeometry.TryLeader(outline, badge, out var from, out var to,
           comment ? NoteBadgeGeometry.AnchorRadius : 0))
       dc.DrawLine(new Pen(badgeBrush, 1), from, to);
   ```

   Радиус точки на экране не масштабируется вместе с картинкой (она рисуется константой 5 при любом `ViewScale`, `:847-848`), поэтому и отступ константный. В `RenderAnnotated` масштаб равен 1, там 5 это 5 пикселей снимка, что совпадает с бейджем, который там тоже рисуется экранного размера (`BadgeOf(item, pixelRect)`).
7. **`Controls/AnnotationCanvas.cs:844`.** Убрать `includeSelection &&` из условия точки, оставив его на радиусе наведения: `var radius = includeSelection && _anchorHover == item.Id ? AnchorHoverRadius : NoteBadgeGeometry.AnchorRadius;`. Обоснование в §0.2. Комментарий `:839-843` переписать: «кружок без номера ничего не объясняет» больше не действует, эталон ТЗ №5 требует точку в картинке.
8. **`WpfExportImageRenderer.cs:180-188`.** Внутри блока `NoteOffset is not null`:

   ```csharp
   var scale = NoteBadgeGeometry.ExportScale(displayLabel);
   var anchor = new Point(origin.X + item.Points[0].X * width, origin.Y + item.Points[0].Y * height);
   var comment = item.Kind == AnnotationKind.Comment;
   var outline = comment ? new Rect(anchor, anchor) : /* прежний расчёт по всем точкам */;
   if (NoteBadgeGeometry.TryLeader(outline, badge, out var from, out var to,
           comment ? NoteBadgeGeometry.AnchorRadius * scale : 0))
       dc.DrawLine(new Pen(badgeBrush, NoteBadgeGeometry.ExportLeaderThickness(displayLabel)), from, to);
   if (comment)
       dc.DrawEllipse(badgeBrush, new Pen(Brushes.White, 1.5 * scale), anchor,
           NoteBadgeGeometry.AnchorRadius * scale, NoteBadgeGeometry.AnchorRadius * scale);
   ```

   Точка после линии, как на экране, чтобы линия не выступала поверх кружка. `anchor` тут повторяет расчёт `ExportBadge` (`:207`); можно вынести его в маленький локальный метод, чтобы два места не разъехались.
9. **`OverlayEditorWindow.xaml.cs:1428-1431`.** Код не менять, дописать к строке `:1431` объяснение: вторая точка это прямоугольник комментария для обрезки (`CaptureCropper.CropBox`), хит-теста и раскладки пилюль, в расчёт выноски она не входит начиная с 1.7.0.

Чего **не** трогать: `ExportMargins` (§0.3), `ExportBadge`, `BoundsOf`, `Create`, всё, что касается рамок и стрелок. Толщина выноски на экране остаётся 1 px, в экспорте `ExportLeaderThickness`, как сейчас.

### 1.4. Связи по графу

`TryLeader`, inbound, глубина 3:

```
hop 1: DrawAnnotation
hop 2: OnRender, RenderAnnotated
hop 3: NoteAffordanceChecks, OnRender, VerifyCaptionIsTheSameSizeOnScreenAndInExport
```

Граф склеивает два одноимённых `DrawAnnotation` (холст и экспортный рисовальщик) в один узел, поэтому `WpfExportImageRenderer.RenderAsync` в выдаче не виден; grep подтверждает второй вызов: `WpfExportImageRenderer.cs:186`. Итого вызывающих ровно три, и все три правятся: экран (`OnRender`, `Controls/AnnotationCanvas.cs:248`), файл на диск (`RenderAnnotated`, `:728`), картинка в чат (`WpfExportImageRenderer.cs:69`). Что может сломаться: у рамки и стрелки линия обязана остаться от контура, поэтому `fromRadius` для них должен быть строго 0, а `outline` строго прежним.

`ExportLeaderThickness`, inbound: граф отдаёт 0 узлов (метод виден только как вызывающий `ExportDiameter`), grep даёт один вызов, `WpfExportImageRenderer.cs:187`. Переименование внутренностей безопасно.

`ExportDiameter`, inbound: `Export`, `ExportLeaderThickness`, `ExportMargins`, дальше тесты `NoteBadgeGeometryTests`. `ScreenDiameter`, inbound: `ExportLeaderThickness`, `Screen`, дальше `BadgeOf`. Введение `ExportScale` в этот список ничего не добавляет: оно встаёт между `ExportLeaderThickness` и парой диаметров.

`BoundsOf`, inbound, глубина 2:

```
hop 1: ApplyBlurAnnotations, BeginGesture, DrawAnnotation, EndGesture, GetDisplayBounds, HitTestAnnotation
hop 2: BeginGesture, EraseTarget, FindResizeHandle, IsMoveHandle, NoteAffordanceChecks, OnMouseLeftButtonDown,
       OnMouseLeftButtonUp, OnRender, RenderAnnotated, RepositionChips, RunToolMemoryProbe, UpdateNoteButton,
       VerifyBlurCache, VerifyGestureRules, VerifyHoverManipulation, VerifyTextMarkGeometry
```

Именно этот список делает вариант C дорогим: прямоугольник комментария читают перетаскивание, стирание, раскладка пилюль, кнопка «заметка» и четыре пробы. Рекомендуемый вариант A `BoundsOf` не меняет и из `DrawAnnotation` для комментария просто перестаёт его звать, остальные вызывающие видят прежние числа.

`BadgeOf`, inbound: `DrawAnnotation`, `GetBadgeCenter`, `GetBadgeRadius`, `IsMoveHandle`; дальше `FindMoveHandle`, `RepositionChips`, `RunEditorViewProbe`, `VerifyGestureRules`, `VerifyHoverManipulation`. Не трогаем: бейдж остаётся концом линии, как был.

`ExportBadge`, inbound: `DrawAnnotation` (экспортный) и `RunAsync` смоука. Не трогаем.

`MarginsOf`/`ExportMargins`, inbound: `RenderAsync`, `SmokeTestRunner.RunAsync` (`:478`) и девять тестов. Не трогаем осознанно (§0.3).

Чтение `Points` комментария вне холста: `WpfExportImageRenderer.cs:33` (только `Points[0]`), `:207` (только `Points[0]`), `CaptureCropper.cs:55-69` (обе точки), `SessionValidation.cs:52-62` (обе, только диапазон). `PromptGenerator` точек не читает. Mac-порт читает тот же `session.json`; формат не меняется (§0.5).

### 1.5. Тесты

Обновить:

* `Controls/AnnotationCanvas.cs:1449-1453` (`VerifyHoverManipulation`), комментарий с литеральными точками `[At(.48,.18), At+8]`. Оставить как есть: это проверка захвата за бейдж и отсутствия ручек, прямоугольник 8 × 8 в ней осмыслен и останется в модели. Никакой правки не требуется, ТЗ адресует её ошибочно (§0.6).
* `OverlayEditorWindow.xaml.cs:1035`, `:1065` (`NoteAffordanceChecks`), комментарии из двух точек с `+8`. Тоже остаются: они воспроизводят то, что пишет `OnAnnotationCreated`. Если по ходу правки решено заводить точки через `OnAnnotationCreated`, а не литералом, правка косметическая.
* `tests/Snapik.App.Imaging.Tests/NoteBadgeGeometryTests.cs`. Файл сейчас проверяет только поля экспорта; `TryLeader` не покрыт ничем.

Добавить, все в `NoteBadgeGeometryTests`:

1. `Выноска рамки начинается на её контуре`: прямоугольник 100 × 60, бейдж справа-сверху, `fromRadius = 0`, `from` лежит на границе прямоугольника (регрессия на «рамки и стрелки не менять»).
2. `Выноска комментария начинается на ободе точки`: вырожденный `Rect(anchor, anchor)`, `fromRadius = 5`, расстояние от `anchor` до `from` равно 5, направление совпадает с направлением на центр бейджа.
3. `Выноска кончается на ободе бейджа`: `(badge.Center - to).Length == badge.Radius`.
4. `Короткая выноска не рисуется`: бейдж ближе, чем `badge.Radius + fromRadius + 1`, `TryLeader` возвращает `false` (иначе линия вывернется наизнанку у комментария, чей бейдж почти на точке).
5. `Точка экспорта крупнее экранной ровно во столько же, во сколько бейдж`: `ExportScale("1")` даёт то же число, что `ExportLeaderThickness("1")`, и оно больше 1.

Смоук: расширить готовую пробу экспорта `SmokeTestRunner.cs:467-493`. Она уже рендерит `RunNoteAffordanceProbe` в PNG и проверяет цвет пикселя в центре переставленного бейджа (`PixelAt`, `:490-492`). Дописать той же меркой: пиксель в центре `Points[0]` переставленного комментария, пересчитанный в координаты листа через `CaptureOrigin(noteProbeMargin)`, должен быть акцентным, а пиксель в 5 × `ExportScale` + 2 px от центра по нормали к бейджу белым (обводка). Плюс негативная проверка: у комментария без `NoteOffset` (`session-comment-points.json` показывает, что такие бывают) в центре точки лежит пиксель снимка, а не акцент.

Ручная проверка, которой ТЗ не просит, а стоит: «Сохранить на компьютер» (`OverlayEditorWindow.Save.cs:48`) даёт тот же кадр, что Ctrl+V (§0.2).

### 1.6. Риски

* **Вырожденный `Rect` и `Math.Clamp`.** `Rect(anchor, anchor)` имеет нулевую ширину, `Clamp(x, left, right)` при `left == right` вернёт `left`. Проверено по коду, ветки с `Rect.Empty` в `TryLeader` нет, но `Rect.Empty` (у отметки без точек) даёт `Left = +∞`, `Right = −∞`, и `Math.Clamp` на таком диапазоне бросает. Сегодня это недостижимо: `DrawAnnotation` выходит при `Points.Count == 0` (`Controls/AnnotationCanvas.cs:777`). Ветку комментария писать через `Points[0]` напрямую, не через `BoundsOf`, чтобы этот путь не появился.
* **Комментарий, чей бейдж почти на точке.** `EndGesture` обнуляет `NoteOffset` короче порога жеста (`Controls/AnnotationCanvas.cs:601-605`), так что ни линии, ни точки не будет. Но `NoteOffset` можно оставить маленьким, дотащив пилюлю обратно (`DragNoteTo`). Тогда `TryLeader` вернёт `false` (линии нет), а точка нарисуется под бейджем. На экране так и сегодня; в экспорте появится кружок под бейджем. Допустимо, но проверить глазами.
* **Точка у края снимка.** §0.3, срежется по границе листа. Известное ограничение.
* **Толщина выноски в `RenderAnnotated`.** Там перо жёсткое, 1 px на полноразмерном снимке, то есть волосок (в экспорте оно масштабируется через `ExportLeaderThickness`). Это уже так и есть, C1 не делает хуже, но раз в «Сохранить на компьютер» теперь появится точка, несоответствие станет заметнее. В объём C1 не брать, записать отдельным наблюдением.
* **Порядок отрисовки.** Точка рисуется в проходе меток (`drawShape: false`, `Controls/AnnotationCanvas.cs:248`, `WpfExportImageRenderer.cs:68-69`), то есть поверх всех фигур. Это то, что нужно: точка на закрашенной рамке останется видна.

---

## 2. C2 · Форма у размытия

### 2.1. Причина

`InspectorViewOf(Blur)` отдаёт `SecondCapsule.Shape` (`ToolAppearance.cs:179`). `OnLineCapsuleClick` по `Shape` открывает `BuildShapeMenu(LineCapsule)` (`OverlayEditorWindow.Appearance.cs:517`), а пункт меню при пустом выделении делает `SelectToolMode(EditorTool.Rectangle)` (`OverlayEditorWindow.Shapes.cs:64`), что ставит `Surface.Tool = Rectangle` и снимает выделение (`OverlayEditorWindow.xaml.cs:1397-1406`). С точки зрения Кати: выбрала форму у размытия, размытие пропало из руки.

Смысла в капсуле нет и без этого: форма у размытия и так общая с рамкой, читается только с рамки (`OverlayEditorWindow.Appearance.cs:104`) и подставляется новому блюру в черновике (`Controls/AnnotationCanvas.cs:388`).

### 2.2. Решение

Один вариант, ровно по решению Кати: `Blur → SecondCapsule.None`, вторая капсула для `None` прячется, обе капсулы у размытия отсутствуют, блок остаётся своей фиксированной ширины.

Альтернатива «оставить капсулу, но не звать `SelectToolMode` при инструменте `Blur`» решает жалобу и оставляет управление формой на месте, но противоречит прямому решению Кати («капсулу убрать») и оставляет два места, где форма редактируется. Не предлагать.

### 2.3. Точные места правки

1. **`ToolAppearance.cs:179`.** `EditorTool.Blur => new(false, false, SecondCapsule.None, true)`. Комментарий `:178` переписать: «у размытия нет ни цвета, ни своих свойств: форму оно берёт у рамки, блок пуст».
2. **`OverlayEditorWindow.Appearance.cs:249-268`.** Первой строкой блока второй капсулы: `LineCapsule.Visibility = view.Second == SecondCapsule.None ? Visibility.Hidden : Visibility.Visible;`. Именно `Hidden`, как у `ColorCapsule` (`:233`), чтобы блок держал ширину; её всё равно фиксирует ресурс `ToolbarPropertiesWidth` (`OverlayEditorWindow.xaml.cs:475`), но одинаковое поведение двух капсул читается проще. Остальные строки блока для `None` попадут в `default` и выставят «Толщина» и «4 px» невидимой кнопке; это безвредно, но подпись лучше дополнить веткой `SecondCapsule.None => string.Empty` в `LineCapsuleValue` (`:259-264`), чтобы отладка не показывала чужой текст.
3. **`OverlayEditorWindow.Appearance.cs:511-520`.** В `OnLineCapsuleClick` добавить `case SecondCapsule.None: return;` перед `default`. Кнопка скрыта, но `default` сейчас открывает поповер толщины у инструмента без обводки; лучше не оставлять достижимую по ошибке ветку.
4. **`OverlayEditorWindow.Appearance.cs:387-398`.** Условие записи формы `tool is EditorTool.Rectangle or EditorTool.Blur` сузить до `tool == EditorTool.Rectangle`. Иначе после правки 1 к выделенному блюру форма всё ещё придёт через шеврон рамки (`ShapeMenuButton`, `OverlayEditorWindow.xaml:229` → `OnShapeMenuClick` → `BuildShapeMenu`), а ТЗ говорит «у выделенного блюра форму тоже не меняем». Зеркало `_tools[Blur]` в ветке «ничего не выделено» (`:396`) оставить (§0.4).
5. **`OverlayEditorWindow.Shapes.cs:53` и `:64`.** `is { Kind: EditorTool.Rectangle or EditorTool.Blur }` в обоих местах сузить до `is { Kind: EditorTool.Rectangle }`. `:53` определяет, какая галочка стоит в меню, `:64` определяет, переключать ли инструмент. После сужения выбор формы при выделенном блюре ведёт себя как при любом другом чужом выделении: переключает на рамку. Это то же «ожидаемое» поведение, которое ТЗ оставляет для рамки с любым другим инструментом в руке.

   Оговорка для Никиты: пункт 5 это единственное место, где C2 меняет поведение **выделенного** блюра, а не размытия в руке. Если решить, что шеврон рамки при выделенном блюре пусть и дальше молча меняет форму блюра (инструмент он при этом не переключает, жалобы Кати это не касается), то пункты 4 и 5 можно не делать, и C2 сведётся к трём правкам. Я рекомендую делать: «форма редактируется в одном месте и принадлежит рамке» проще объяснить и проще перенести на Mac.
6. **`Controls/AnnotationCanvas.cs:388`.** Не трогать: блюр берёт `ActiveShape`, это и есть «размытие рисуется формой, выбранной у фигуры».
7. **`OverlayEditorWindow.xaml:294-301`.** Разметку не трогать: видимость ставится из кода.

### 2.4. Связи по графу

`InspectorViewOf`, inbound, глубина 2:

```
hop 1: ApplyAppearance, OnLineCapsuleClick, OpenFillFromSquare, SyncAppearance,
       The_properties_block_shows_what_the_tool_has
hop 2: ApplyAppearance, ApplyAppearanceNow, ApplyPickedColor, BuildFillPalette, CommitAppearanceEdit,
       NoteAffordanceChecks, OnAnnotationChanged, OnColorCapsuleClick, OnFillClick, OnFontSizeChanged,
       OnFontSizePresetClick, OnLineStylePresetClick, …
```

Разбор по вызывающим первого уровня:

* `SyncAppearance` (`OverlayEditorWindow.Appearance.cs:214`): правится, пункт 2. Сломаться может ширина блока и подписи; ширину держит фиксированный ресурс, проба `OverlayEditorWindow.xaml.cs:472-480` её и стережёт.
* `ApplyAppearance` (`:368`): читает `view.Stroke`, `view.Second == Line`, `view.FillSwatch`, `view.Second == FontSize`. У блюра `Stroke` и `FillSwatch` уже `false`, `Second` меняется с `Shape` на `None`, то есть ни одна из этих проверок не становится истиннее. Ветка формы стоит на `tool`, а не на `view`, её правим отдельно (пункт 4).
* `OnLineCapsuleClick` (`:513-514`): правится, пункт 3.
* `OpenFillFromSquare` (`:494`): читает только `FillSwatch`, у блюра он `false` как был. Не затронуто.
* `The_properties_block_shows_what_the_tool_has` (`tests/Snapik.App.Imaging.Tests/ToolAppearanceTests.cs:20-42`): упадёт, правится, см. §2.5.

`BuildShapeMenu`, inbound: `OnLineCapsuleClick` (уходит после правки), `OnShapeMenuClick` (шеврон рамки, остаётся), `OverlayEditorWindow` (конструктор, длинное нажатие на кнопке рамки, `OverlayEditorWindow.xaml.cs:99`), `RunShortcutHintProbe` (`:180-191`, проверяет, что меню ставит `ActiveShape = Ellipse`; вызов идёт от `ShapeMenuButton`, то есть уцелеет).

`SelectToolMode`, inbound: `OnCommentClick`, `OnWindowKeyDown`, `OpenFillFromSquare`, плюс пробы `NoteAffordanceChecks`, `PanelChecks`, `RunShortcutHintProbe`, `RunToolMemoryProbe`, `TextMarkChecks`. Сам метод не меняем, снимаем один из путей к нему (из меню формы при выделенном блюре).

`ApplyAppearance`, inbound: одиннадцать вызывающих, все поповеры и пресеты панели. Правка пункта 4 касается только аргумента `shape`, который приходит ровно из `BuildShapeMenu` (`OverlayEditorWindow.Shapes.cs:65`). Проверено grep: других вызовов с `shape:` нет.

`ActiveShape`: граф по свойству не отвечает (узлов 0, это property, а не Method). Grep: читается в `SyncSurfaceDefaults` (`OverlayEditorWindow.Appearance.cs:112`), `SyncAppearance` (`:225`), `ApplyAppearance` (`:394`), `BuildShapeMenu` (`OverlayEditorWindow.Shapes.cs:53`) и в пробе `OverlayEditorWindow.xaml.cs:191`. Ни одно из мест не меняется.

`ToolAppearanceStore.Tools` (`ToolAppearance.cs:59-63`) продолжает включать `Blur`, запись `shape` в `settings.json` сохраняется. Mac читает файл как раньше.

### 2.5. Тесты

Обновить:

* `tests/Snapik.App.Imaging.Tests/ToolAppearanceTests.cs:32`: `[EditorTool.Blur] = new(false, false, SecondCapsule.None, true)`, комментарий рядом поправить.
* `tests/Snapik.App.Imaging.Tests/ToolAppearanceTests.cs:104` (запись `[EditorTool.Blur] = new() { Shape = Ellipse }` в тесте круга «прочитали, записали»): оставить. Форма у блюра в файле остаётся, §0.4.

Добавить:

* В `ToolAppearanceTests`: `С размытием в руке вторая капсула не показывает ничего` (`InspectorViewOf(Blur).Second == SecondCapsule.None`) и `Форма читается только у рамки` (запись формы в `_tools[Blur]` не влияет на то, что видит блок; проверяется через `InspectorViewOf`, чистые правила, окна не надо).
* В смоук-пробу панели (`OverlayEditorWindow.xaml.cs`, рядом с `:472-480`, где уже перебираются инструменты, среди них `Blur`): после `SelectToolMode(EditorTool.Blur)` проверить `ColorCapsule.Visibility == Hidden`, `LineCapsule.Visibility == Hidden`, `ToolbarProperties.Width` неизменна, и главное `Surface.Tool == EditorTool.Blur` после клика по пункту меню формы у шеврона рамки не проверять, потому что этого пути больше нет. Вместо него: с блюром в руке вызвать `OnShapeMenuClick(ShapeMenuButton, …)` и убедиться, что инструмент стал `Rectangle` (это разрешённое поведение шеврона рамки) и что `Surface.ActiveShape` изменилась.
* Проба «форма доезжает до блюра»: поставить форму `Ellipse` у рамки, взять размытие, нарисовать жестом через `AnnotationCanvas.UpdateGesture`, убедиться, что у созданной отметки `Shape == Ellipse` (сегодня это покрыто только косвенно, через `RunShortcutHintProbe`).

Существующая проба `OverlayEditorWindow.xaml.cs:410-411` (у комментария обе капсулы выключены) продолжает работать: у комментария `Enabled = false`, `Second` остаётся `Line`, видимость мы меняем только для `None`.

### 2.6. Риски

* **`Hidden` против `Collapsed`.** Блок свойств это горизонтальный `StackPanel` фиксированной ширины; `Collapsed` у `LineCapsule` схлопнет зазор и сдвинет то, что справа. `Hidden` держит место. Выбрать `Hidden`, проверить на 125 % (ТЗ F.10 смотрит именно на это).
* **Пустой блок у размытия.** У блюра исчезают обе капсулы, блок становится визуально пустым прямоугольником фиксированной ширины. Это ровно то, о чём решение Кати («блок для размытия пустой»), но глазами стоит подтвердить, что пустота не читается как поломка панели.
* **Горячие клавиши формы.** Отдельного шортката формы в `EditorShortcuts` нет (grep по `Shape` даёт только меню и чевроны), так что скрытая капсула не оставляет висячего пути через клавиатуру. Если дорожка A или D добавит шорткат, он должен уважать `InspectorViewOf`.
* **Длинное нажатие на кнопке рамки** (`OverlayEditorWindow.xaml.cs:99`) открывает то же меню формы. С блюром в руке оно, как и шеврон, переключит на рамку. Это прежнее и ожидаемое поведение кнопки рамки, менять не надо, но в живом прогоне по F.10 проверить, что Катя не назовёт это той же поломкой.

---

## 3. Пересечения с другими дорожками

### 3.1. Файлы дорожки C

Меняются: `Imaging/NoteBadgeGeometry.cs`, `Controls/AnnotationCanvas.cs`, `WpfExportImageRenderer.cs`, `ToolAppearance.cs`, `OverlayEditorWindow.Appearance.cs`, `OverlayEditorWindow.Shapes.cs`, `tests/Snapik.App.Imaging.Tests/NoteBadgeGeometryTests.cs`, `tests/Snapik.App.Imaging.Tests/ToolAppearanceTests.cs`, `SmokeTestRunner.cs`, `OverlayEditorWindow.xaml.cs` (только пробы и комментарий у `:1431`), `tasks/verification.md`.

Не меняются: `OverlayEditorWindow.xaml`, `EditorShortcuts.cs`, `OverlayEditorWindow.Save.cs`, `EdgeStackWindow*`, `src/Snapik.Core/**`, `macos/**`.

### 3.2. Стык с дорожкой B (B4, копия одного снимка)

* **`WpfExportImageRenderer`.** B4 переиспользует его целиком (`RenderAsync`), новых правок в файле не планирует, а C1 правит `DrawAnnotation` (`:174-193`). Конфликта слияния нет, но есть зависимость по смыслу: если B4 соберут и примут раньше C1, кнопка «Копировать» отгрузит в чат картинку без точки, и приёмка F.7/F.8 пройдёт на кадре, который F.9 потом забракует. Порядок: C1 в экспорте раньше B4, либо B4 принимает картинку уже с точкой.
* **`OverlayEditorWindow.xaml:310`.** B4 ставит кнопку «Копировать» рядом с `SaveImageButton`. C1 и C2 в этот файл не пишут. Конфликта нет.
* **`OverlayEditorWindow.Save.cs`.** B4 работает рядом (`OnSaveImageClick`, `:14-54`). C1 не правит файл, но меняет поведение `Surface.RenderAnnotated()` (`:48`), которое B4 может взять за образец «как выглядит один снимок». Сказать исполнителю B4 явно: буфер собирается экспортным рисовальщиком (ТЗ B4.3), а не `RenderAnnotated`, иначе в чат уедет кадр без шапки и без поля.
* **`SmokeTestRunner.cs`.** И C1 (проба экспорта, `:467-493`), и B4 (проба копии одного снимка) будут дописывать в один файл. Конфликт слияния вероятен, но текстовый: разные участки, разрешается вручную. Если дорожки идут в worktree, `SmokeTestRunner.cs` стоит заранее назвать «файл общего доступа».
* **`EditorShortcuts.cs`** (Ctrl+Shift+C) — только B, C не касается.

### 3.3. Стык с дорожкой A+D (D2, палитра «Неон» в настройках)

* **`OverlayEditorWindow.Appearance.cs`.** D2 берёт источник списка палитр (`:55` и окрестности, `PaletteSet`), C2 правит `:249-268`, `:387-398`, `:511-520`. Участки разные, между ними сотни строк, автослияние почти наверняка пройдёт. Риск средний, а не нулевой, потому что оба исполнителя будут менять один файл в одном раунде.
* **`ToolAppearance.cs`.** D2 её, скорее всего, не трогает (палитра живёт в `HotkeySettings.AnnotationPalette`, а не в `ToolAppearance`), но если решат тащить палитру через `ToolAppearanceStore`, пересечение будет прямым. Проверить на старте дорожки A+D.
* **`tests/Snapik.App.Imaging.Tests/ToolAppearanceTests.cs`.** C2 правит `:32`, D2 может дописывать свои факты в конец. Конфликт маловероятен.

### 3.4. Что вынести в волну 0 (общий фундамент на `master` до дорожек)

1. **`Imaging/NoteBadgeGeometry.cs`: `ExportScale`, `AnchorRadius`, параметр `fromRadius` у `TryLeader` (с поведением по умолчанию, то есть без изменения картинки) плюс пять новых тестов `TryLeader`.** Чистая геометрия, ни одной строки UI, обратно совместима: пока никто не передаёт `fromRadius`, все три рисовальщика рисуют как раньше. Зато сигнатура, на которой стоят экран, «Сохранить на компьютер» и экспорт, становится окончательной до того, как B4 начнёт трогать экспортный путь.
2. **`SyncAppearance`: ветка `SecondCapsule.None` (видимость `LineCapsule`) и `case None: return;` в `OnLineCapsuleClick`.** Две строки в `OverlayEditorWindow.Appearance.cs`, файле, который будет трогать и A+D. Поведение не меняется, пока `InspectorViewOf` никому не отдаёт `None`. Снимает с C2 один конфликтный участок и делает саму правку C2 однострочной.

Всё остальное (рисование точки, правка условия `includeSelection`, сужение условий формы) оставить внутри дорожки C: эти правки видны на экране и должны приниматься вместе.

По правилу worktree: перед спавном дорожек `git push origin master` с волной 0, иначе ветки отпочкуются от состояния без неё.

---

## 4. Соответствие приёмке F.9, F.10 и G

**F.9.** «Комментарий: нажал-потянул → линия от центра точки до обода бейджа, на экране касается точки; тянуть точку → линия следует; Ctrl+V → в картинке точка и линия до неё».

* «Линия от центра точки до обода бейджа» — §1.3 пункты 4, 6, 8. Формально линия идёт не от центра, а от обода точки (радиус 5), как и требует сам ТЗ строкой ниже; «от центра» относится к направлению, а не к первому пикселю.
* «Касается точки» — обеспечивается тем, что начало ровно на ободе, без зазора. Перо линии 1 px, перо обводки точки 1.5 px, стык будет плотным.
* «Тянуть точку → линия следует» — уже работает: `_anchorDrag` двигает `Points` и компенсирует `NoteOffset` (`Controls/AnnotationCanvas.cs:423-433`), а выноска пересчитывается каждый `OnRender`. После правки начало линии считается от `Points[0]`, то есть следует ещё точнее, чем сейчас.
* «Ctrl+V → точка и линия» — §1.3 пункт 8, плюс смоук §1.5.
* **Пробел в F.9:** не проверяется «Сохранить на компьютер», который C1 тоже меняет (§0.2). Предложить Никите добавить в F.9 один шаг: после Ctrl+V сохранить тот же снимок в файл и открыть, точка и линия на месте.
* **Второй пробел:** F.9 не проверяет комментарий **без** `NoteOffset` (бейдж на месте). По требованию C1.2 там точки быть не должно. На `evidence/export-leader-x3.png` это A3. Предложить шаг: поставить комментарий кликом, не таща бейдж, Ctrl+V, у этого номера ни точки, ни линии.
* **Третий пробел:** F.9 не проверяет старую сессию. Обратная совместимость (§0.1) это главный аргумент за выбранное решение, и её стоит проверить: открыть сессию Кати из свидетельства (комментарии с двумя точками, разница 8 px), линия должна идти от точки, а не от угла квадрата.

**F.10.** «Рамка с овалом → размытие: блока формы у размытия нет, блюр овальный; выбрать у рамки прямоугольник → размытие прямоугольное; инструмент при этом не переключается».

* «Блока формы нет» — §2.3 пункты 1, 2.
* «Блюр овальный, форма берётся у рамки» — поведение уже такое (`Controls/AnnotationCanvas.cs:388`), правки не требует, но сценарий проверит, что правка 1 его не сломала.
* «Инструмент не переключается» — после правки пути к `SelectToolMode` из капсулы больше нет, потому что капсулы нет. Формулировку в F.10 стоит уточнить: инструмент не переключается **потому, что нечего нажать**; шеврон формы у рамки переключает на рамку, и это ожидаемо (последний абзац C2 в ТЗ).
* **Пробел в F.10:** не проверяется выделенный блюр. По ТЗ у него блок такой же пустой. Предложить шаг: нарисовать блюр, выбрать его «Выбором», блок пуст, ни обводки, ни формы.

**G.** Открытых вопросов по C в разделе G нет. Ближайший смежный — G «B4: форматы буфера для одного снимка должны совпадать с пакетом»; он касается C только через общий `WpfExportImageRenderer` (§3.2): один и тот же рисовальщик обязан дать одинаковую картинку в пакете и в копии одного снимка, и точка комментария должна быть в обеих.

Открытые вопросы, которые этот разбор добавляет (решать Никите):

1. Сужать ли условия формы до одной рамки (§2.3, пункт 5) или оставить шеврону рамки право менять форму выделенного блюра.
2. Добавлять ли в F.9 шаги про «Сохранить на компьютер», про комментарий без `NoteOffset` и про старую сессию.
3. Считать ли ограничение «точка у самого края снимка срезается листом экспорта» приемлемым (§0.3).
