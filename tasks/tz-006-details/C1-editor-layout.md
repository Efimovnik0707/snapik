# Дорожка C1: геометрия редактора и панель (ТЗ №5, пункты C1, C2, C6)

Зона: размещение снимка, размещение и укладка панели, перетаскивание панели, уголки-варианты.
Содержимое блока свойств (C3), модель объектов (C4) и комментарии (C5) — у второго аналитика.
Все `файл:строка` по `master` `802343d` (`src/` на состоянии `d84fbb0`), пути от `src/Snapik.App/`.

## 0. Где ТЗ не сходится с кодом

1. **C6 уже сделан.** ТЗ: «На панели уголок ▾ есть у стрелки… на эталоне такие же у рамки и у карандаша». В коде уголки есть у всех трёх и одним стилем `OverlayToolChevron` (`OverlayEditorWindow.xaml:212` рамка, `:216` стрелка, `:222` карандаш; обработчики `Shapes.cs:69`, `Arrows.cs:36`, `Shapes.cs:106`). Появились до переименования (`3208bd9`), то есть были в 1.5.0. Работы по C6 нет — есть проверка, что перекладка панели под C3 их не потеряет.
2. **Коробка 78/72 живёт в двух местах, ТЗ называет одно.** `OverlayEditorWindow.xaml.cs:966-968` (в `OnLoaded`, не в `EditExistingAsync`: та — `:135-143`) и второй раз `:1105-1108` в `SetupEditor`, как запасной расчёт для окна, которое ещё не разложено. Убирать обе, иначе коробка переживёт правку в пути «обрезка → `SetupEditor`».
3. **Строки в ТЗ сдвинуты на два-три.** Учёт переключателя в `PositionToolbar` — `:1741-1746`, не `:1741-1744`. `SyncScaleSwitch` `:1677-1688`, `OnFitScaleClick` `:1691-1696`, `OnOneToOneScaleClick` `:1698-1708`, `OnSurfaceViewChanged` `:1712-1717`. `Toolbar.MaxWidth` — `:1735`, совпадает.
4. **Ctrl+колесо из вписанного состояния сейчас не работает вообще.** `AnnotationCanvas.OnMouseWheel` (`Controls/AnnotationCanvas.cs:1039-1042`) выходит, пока `ViewScale is null`, то есть пока снимок вписан. Единственный вход в 1:1 в 1.5.0 — правый сегмент переключателя (`OnOneToOneScaleClick`). Если убрать переключатель и не тронуть колесо, пункт приёмки F.9 («весь экран двух мониторов — вписан, Ctrl+колесо даёт 1:1») станет невыполнимым. Это главный скрытый пункт C1.
5. **Панель — уже `WrapPanel`** (`OverlayEditorWindow.xaml:205`) и уже переносится по `MaxWidth`. Но переносится она по месту, а не по смыслу: ТЗ и эталон требуют «инструменты и кнопки справа в первой строке, свойства во второй». `WrapPanel` так не умеет — нужна другая разметка (раздел 2).
6. **Арифметика эталона не сходится на 32 px.** `reference-html/04-editor-small.html`: «ширины 829 не хватает». По коду свободная ширина при открытой панели комментариев = 1093 − 280 − 16 = **797** (`OverlayEditorWindow.Comments.cs:13-22`), минус поля 8+8 = 781. На вывод «две строки» это не влияет, но в тестах брать 797, а не 829.
7. **Оговорка ТЗ «снимок сразу после захвата — как сейчас, на своём месте 1:1» уже выполняется** и через новую функцию не идёт: свежий снимок берёт `_cropRect` из выделения пользователя (`OnWindowMouseDown`/`OnWindowMouseUp`), `OnLoaded` для него выходит на `if (_capture is null) { RestoreLastRegion(); return; }` (`:958`).

## 1. C1: снимок открывается 1:1, если влезает

### 1.1. Что убирается

| Что | Где | Inbound (`trace_call_path`) |
|---|---|---|
| `ScaleSwitch`, `FitSegment`, `FitSegmentText`, `OneToOneSegment` | `xaml:291-300` | только код ниже |
| `SyncScaleSwitch` | `xaml.cs:1677-1688` | `OnFitScaleClick`, `OnOneToOneScaleClick`, `OnSurfaceViewChanged`, `SetupEditor` → далее `OnLoaded`, `OnCropRequested`, `OnWindowMouseUp` и семь smoke-проб |
| `OnFitScaleClick`, `OnOneToOneScaleClick` | `xaml.cs:1691-1708` | только XAML и `RunEditorScaleProbe:546` |
| учёт переключателя в `PositionToolbar` | `xaml.cs:1741-1746` | — |
| `_fitBox` | `xaml.cs:70`, `:519`, `:968`, `:1105-1108`, `:1680` | — |
| `FitBound`, `FitResult` | `Controls/EditorGeometry.cs:7-10` | `Fit` и три теста |

`OnSurfaceViewChanged` (`:1712-1717`) **остаётся**: он держит ручки границ снимка и пилюли при смене масштаба, просто перестаёт звать `SyncScaleSwitch`. `SegmentButton` (`xaml:94-108`) **не удалять**: на нём палитры, толщина, стиль линии.

`FitBound`/`FitResult` существовали ради подписи «По ширине · N %». Подписи нет — `Fit` возвращает `double`. Это ломает три теста (раздел 5).

### 1.2. Новая чистая функция

В `Controls/EditorGeometry.cs`, рядом с `Fit`/`ClampOffset`/`ZoomAround`:

```csharp
/// <summary>
/// Место снимка в рабочей области: снимок стоит 1:1, если помещается в неё вместе с панелью
/// под ним, иначе вписывается по ширине или по высоте. Прямоугольник — в единицах окна,
/// поэтому «1:1» здесь не режим холста, а размер прямоугольника, равный размеру картинки:
/// ViewScale остаётся null, и весь холст считает по-старому.
/// </summary>
internal static Rect PlaceCapture(Size image, Rect work, Size panel, double gap = 10, double margin = 8)
{
    var boxWidth  = Math.Max(1, work.Width  - margin * 2);
    var boxHeight = Math.Max(1, work.Height - margin * 2 - panel.Height - gap);
    var scale = image.Width <= boxWidth && image.Height <= boxHeight
        ? 1
        : Fit(image.Width, image.Height, boxWidth, boxHeight);
    var size = new Size(image.Width * scale, image.Height * scale);
    return new Rect(
        work.Left + (work.Width - size.Width) / 2,
        Math.Max(work.Top + margin, work.Top + (work.Height - panel.Height - gap - size.Height) / 2),
        size.Width, size.Height);
}
```

Решение, которое экономит половину дорожки: **режим 1:1 не вводится**. `_cropRect` делается размером с картинку, холст вписывает картинку в свои же границы, `FitRect` даёт ровно 1, `Surface.ViewScale` остаётся `null`. Значит ручки границ снимка (`Resize.cs:103-124`, видны только при `ViewScale is null`), пилюли, обрезка и жесты работают как при обычном снимке области, и ни одна из одиннадцати точек холста не меняется. Режим `ViewScale is not null` остаётся только для Ctrl+колеса на большом снимке.

### 1.3. Куда она включается

- `OnLoaded` (`xaml.cs:959-974`): вместо `maxWidth/maxHeight` 78/72 и `_fitBox` — измерить панель (раздел 2.3), затем `_cropRect = EditorGeometry.PlaceCapture(imageSize, work, panelSize)`. `work` уже считается через `WithoutCommentsStrip`, это не трогать.
- `SetupEditor` (`xaml.cs:1104-1111`): блок `if (_fitBox.IsEmpty)` и вызов `SyncScaleSwitch()` убрать целиком.

### 1.4. Ctrl+колесо: вход в 1:1 из вписанного

`Controls/AnnotationCanvas.cs:1039-1058`. Сейчас:

```csharp
if (Image is null || ViewScale is not { } scale) return;
```

Нужно: при зажатом Ctrl и `ViewScale is null` затравить масштаб текущим вписанным и дальше идти по существующей ветке.

```csharp
if (Image is null) return;
if (ViewScale is null && !Keyboard.Modifiers.HasFlag(ModifierKeys.Control)) return;
var scale = ViewScale ?? FitScale;   // FitScale — ровно тот масштаб, что показан, скачка нет
```

`FitScale` (`:93-97`) считается от `ActualWidth - ImagePadding * 2`, а `ImagePadding` у `Surface` равен 0 (`xaml:140`), так что затравка совпадает с картинкой на экране до пикселя. Дальше всё уже написано: шаг ×1.1, потолок 1, пол `FitScale`, возврат в `ViewScale = null` при достижении пола, `ZoomAround` держит точку под курсором.

Колесо без модификаторов и Shift+колесо при вписанном снимке по-прежнему ничего не делают — прокручивать нечего. Пробел с мышью (`:225`, `:399`) тоже остаётся при `ViewScale is not null`.

### 1.5. Что остаётся нетронутым

Подпись вида снимка (`ShotKindChip`, `SyncShotKind`, `PositionShotKind` `xaml.cs:1640-1672`) — ТЗ требует оставить. `_capture.Kind`, `MonitorCount`, `Title` не трогаются.

## 2. C2: укладка, позиция, перетаскивание

### 2.1. Свободная ширина

Единственный источник — `LayoutWorkArea()` (`Comments.cs:18`), то есть рабочая область монитора минус полоса панели комментариев (`WithoutCommentsStrip`, `:20-22`, 280 + 16). Поля по 8 с каждой стороны уже заложены в `PlaceToolbar`. Свободная ширина для панели = `work.Width - 16`, нижний пол 380 оставить (`xaml.cs:1735`).

### 2.2. Разметка панели: контракт для аналитика C3/C4/C5

`WrapPanel` заменяется на `Grid` из двух строк и четырёх колонок. Ни один существующий элемент не переименовывается — меняется только их родитель и место в сетке; `PlacementTarget` у поповеров (`AppearancePopup`, `ThicknessPopup`, `LineStylePopup`, `ShortcutSheetPopup`) остаются рабочими, потому что привязаны по `ElementName`.

```xml
<Border x:Name="Toolbar" Visibility="Collapsed" HorizontalAlignment="Left" VerticalAlignment="Top"
        Padding="7" CornerRadius="16" Background="{DynamicResource SurfaceBarBrush}">
  <Border.Effect>…как сейчас…</Border.Effect>
  <!-- Background="Transparent": фон и промежутки ловят нажатие и тянут панель, кнопки
       забирают нажатие раньше — тот же приём, что у ленты (EdgeStackWindow.xaml:136). -->
  <Grid x:Name="ToolbarBody" Background="Transparent"
        MouseLeftButtonDown="OnToolbarMouseDown" MouseMove="OnToolbarMouseMove"
        MouseLeftButtonUp="OnToolbarMouseUp">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="Auto"/>  <!-- 0 инструменты -->
      <ColumnDefinition Width="Auto"/>  <!-- 1 свойства в одну строку -->
      <ColumnDefinition Width="*"/>     <!-- 2 свободное место: оно же ручка для перетаскивания -->
      <ColumnDefinition Width="Auto"/>  <!-- 3 кнопки справа -->
    </Grid.ColumnDefinitions>

    <StackPanel x:Name="ToolbarTools" Grid.Row="0" Grid.Column="0" Orientation="Horizontal">
      <!-- SelectTool, RectangleTool+ShapeMenuButton, ArrowTool+ArrowMenuButton,
           PenTool+PenMenuButton, TextTool, EraserTool, BlurTool, CropTool,
           CommentToolButton, ShortcutSheetButton (+ его Popup) — как сейчас, порядок из эталона 01 -->
    </StackPanel>

    <StackPanel x:Name="ToolbarProperties" Grid.Row="0" Grid.Column="1" Orientation="Horizontal"
                MinWidth="{StaticResource ToolbarPropertiesWidth}">
      <!-- ЗОНА C3: ColorDots, AppearanceButton, ThicknessButton, LineStyleButton,
           FillButton, FontSizeButton — и то, во что он их превратит (две капсулы) -->
    </StackPanel>

    <StackPanel x:Name="ToolbarActions" Grid.Row="0" Grid.Column="3" Orientation="Horizontal">
      <!-- разделитель, UndoButton, RedoButton, SaveImageButton, DoneButton -->
    </StackPanel>
  </Grid>
</Border>
```

Граница между аналитиками, по именам:

- **Мои:** `Toolbar`, `ToolbarBody` (сетка, строки, колонки, фон-ручка), `ToolbarTools`, `ToolbarActions`, `Grid.Row`/`Grid.Column`/`Grid.ColumnSpan` у `ToolbarProperties`, `Toolbar.MaxWidth`, `Toolbar.Margin`, `PositionToolbar`, `PlaceToolbar`, `ToolbarLayout`.
- **Его:** всё **внутри** `ToolbarProperties` (две капсулы, поповеры, включение/выключение по инструменту), плюс содержимое `ToolbarTools`, если C3 меняет набор кнопок. Уголки ▾ (`ShapeMenuButton`, `ArrowMenuButton`, `PenMenuButton`) остаются в `ToolbarTools` и стиле `OverlayToolChevron` — C6 этим и закрыт.
- **Что он обязан мне дать:** у `ToolbarProperties` постоянная ширина (`MinWidth`, ресурс `ToolbarPropertiesWidth`, считанная по самому длинному инструменту — рамке). Это требование ТЗ C3 («блок одной ширины у всех инструментов, панель не прыгает») и одновременно условие того, что моё измерение стабильно: иначе решение «одна строка или две» будет меняться от инструмента в руке.

### 2.3. Чистая функция укладки

Новый файл `Controls/ToolbarLayout.cs`, без зависимостей от WPF кроме `System.Windows.Size` (тест-проект уже линкует такие: `EditorGeometry.cs`, `ResizeGeometry.cs`).

```csharp
internal enum ToolbarRows { One, Two }
internal readonly record struct ToolbarShape(ToolbarRows Rows, Size Size);

/// <summary>
/// Сколько строк займёт панель и какого она будет размера. Одна строка — инструменты,
/// свойства, свободный промежуток и кнопки справа; две — инструменты и кнопки в первой,
/// свойства во второй. Меряется по трём блокам, а не по готовой панели: место снимка
/// считается до того, как панель разложена, и оба счёта должны совпасть.
/// </summary>
internal static ToolbarShape Measure(Size tools, Size properties, Size actions, double freeWidth,
                                     double padding = 14, double gap = 12, double rowGap = 7)
{
    var row = Math.Max(Math.Max(tools.Height, properties.Height), actions.Height);
    var oneRow = padding + tools.Width + properties.Width + gap + actions.Width;
    if (oneRow <= freeWidth) return new ToolbarShape(ToolbarRows.One, new Size(oneRow, padding + row));
    var twoRow = padding + Math.Max(tools.Width + gap + actions.Width, properties.Width);
    return new ToolbarShape(ToolbarRows.Two, new Size(Math.Min(twoRow, Math.Max(freeWidth, 380)),
                                                      padding + row * 2 + rowGap));
}
```

`PositionToolbar` переписывается так:

1. `var work = LayoutWorkArea(); var free = Math.Max(380, work.Width - 16);`
2. Обнулить `Toolbar.Margin` перед измерением и вернуть после (см. риск 2), `Toolbar.MaxWidth = free`.
3. Измерить три блока (`ToolbarTools.Measure(∞)`, и т. д. — `DesiredSize`), позвать `ToolbarLayout.Measure`.
4. Применить строки: `Grid.SetRow/SetColumn/SetColumnSpan(ToolbarProperties, …)`, `Margin = 0,7,0,0` во второй строке и `0` в первой.
5. `Toolbar.UpdateLayout()`; позиция — `PlaceToolbar(_cropRect, work, shape.Size, notes, mayOverlap)`, если панель не оттащена рукой; иначе `Toolbar.Margin = ClampToolbar(_toolbarUserPosition.Value, work)`.

`OnLoaded` зовёт шаги 1-4 (без 5) до расчёта `_cropRect`, чтобы отдать `shape.Size` в `PlaceCapture`. Панель на этот момент `Collapsed` (`xaml:198`) и меряется в ноль — перед измерением выставить `Toolbar.Visibility = Visible` (`SetupEditor` делает это на `:1100`; в `OnLoaded` это надо сделать раньше).

### 2.4. Приоритет позиций

`OverlayEditorWindow.Toolbar.cs:12-31`. Порядок кандидатов (под → над → справа → слева) и обход пилюль не менять. Меняется только запасная ветка `:24-30`:

```csharp
internal static Rect PlaceToolbar(Rect crop, Rect work, Size size, Rect[] notes, bool mayOverlap)
```

- `mayOverlap == false` и ни один кандидат не подошёл → вернуть прижатый к низу рабочей области прямоугольник (`work.Bottom - size.Height - 8`), **не** внутрь снимка.
- `mayOverlap == true` → нынешняя ветка со снимком без изменений.

Вызов: `mayOverlap = _capture?.Kind == CaptureKind.Fullscreen || _isNew`. `_isNew` — свежее выделение: пользователь мог протянуть рамку на весь экран, снаружи места нет, и это тот же случай, что весь экран. Для снимка из ленты `mayOverlap` всегда `false`, и ветка недостижима по построению: `PlaceCapture` уже зарезервировала `panel.Height + gap` под картинкой. Это и есть утверждение, которое проверяет smoke.

### 2.5. Перетаскивание

Поля окна (живут до закрытия редактора, сбрасывать не надо — окно одно на снимок, «новый снимок — снова под картинкой» выполняется само):

```csharp
private Point? _toolbarUserPosition;   // левый верх панели, в единицах окна
private Point _toolbarDragOrigin;      // где нажали
private Vector _toolbarDragStart;      // где стояла панель в момент нажатия
```

- `OnToolbarMouseDown`: `if (e.LeftButton != Pressed || e.ClickCount > 1) return;` дальше запомнить origin/start и `ToolbarBody.CaptureMouse()`. Ровно `EdgeStackWindow.OnShellMouseDown` (`:1727-1731`), но без `DragMove()`: `DragMove` двигает окно, а редактор — полноэкранное окно поверх рабочего стола, двигать его нельзя. Кнопки, уголки ▾ и разделители нажатие не пропускают, потому что `ButtonBase` помечает `MouseLeftButtonDown` обработанным; до `ToolbarBody` доходят только фон, `Padding` панели и свободная колонка 2.
- `OnToolbarMouseMove`: при захваченной мыши `_toolbarUserPosition = Clamp(_toolbarDragStart + (e.GetPosition(this) - _toolbarDragOrigin))`, где `Clamp` держит панель внутри `LayoutWorkArea()` с полем 8, и сразу `Toolbar.Margin = new Thickness(pos.X, pos.Y, 0, 0)`.
- `OnToolbarMouseUp`: `ToolbarBody.ReleaseMouseCapture()`.
- `PositionToolbar`: если `_toolbarUserPosition is { } p` — только пере-зажать `p` (рабочая область могла сузиться при открытии панели комментариев) и не звать `PlaceToolbar`.

Хранится **абсолютная точка**, а не смещение от расчётного места: при переключении между одной и двумя строками якорь меняется, и смещение уехало бы.

## 3. C6: уголки-варианты

Делать нечего, кроме сохранения при перекладке. Состояние на HEAD: три кнопки одного стиля `OverlayToolChevron` (`xaml:87-101`), формы рамки — `BuildShapeMenu` (`Shapes.cs:46-67`, прямоугольник / скруглённый / овал, общая с размытием), наконечник стрелки — `BuildArrowMenu` (`Arrows.cs:14-34`), карандаш/маркер — `BuildPencilMenu` (`Shapes.cs:92-104`). Долгое нажатие на самой кнопке открывает то же меню (`AttachLongPress`, `Shapes.cs:108-121`).

В приёмку: после перекладки панели на сетку все три уголка на месте, меню открываются у своей кнопки (`OpenToolMenu` привязывается к `PlacementTarget`), долгое нажатие работает. Одна строка в smoke-пробе панели.

## 4. Строки RU/EN

- **Убрать** пару `["По ширине · {0} %"] = "Fit width · {0} %"` и `["По высоте · {0} %"] = "Fit height · {0} %"` (`UiLanguage.cs:196`) и обе строки из таблицы проверки переводов (`SmokeTestRunner.cs:346`).
- **Добавить** одну пару для доступности ручки: `["Панель разметки"] = "Markup panel"` — `AutomationProperties.Name` на `ToolbarBody`, чтобы UIA видело, за что панель тянут. Больше новых подписей ни C1, ни C2, ни C6 не вводят (эталон 04 подписей на панели не рисует).

## 5. Тесты

`tests/Snapik.App.Imaging.Tests/`. В `.csproj` добавить `<Compile Include="..\..\src\Snapik.App\Controls\ToolbarLayout.cs" Link="ToolbarLayout.cs" />` рядом с `EditorGeometry.cs`.

**`EditorGeometryTests.cs`, что с существующими.** `Fit` теряет `FitResult`, поэтому:
- `A_capture_of_two_monitors_is_fitted_by_its_width` и `A_tall_imported_file_is_fitted_by_its_height` — оставить, но проверять только число (`0.312`, `0.247`); утверждение про сторону уходит вместе с подписью, которой больше нет.
- `A_capture_that_fits_as_it_is_has_nothing_to_switch_between` — переименовать в `A_capture_smaller_than_the_box_is_not_scaled` и оставить `Assert.Equal(1, …)`; «переключаться» больше не с чем.
- Три теста про `ClampOffset`/`ZoomAround` не трогать: это и есть механика Ctrl+колеса, которая остаётся, и её вход из вписанного состояния она же и держит.

**Новые, `PlaceCapture`** (рабочая область 1536×824 — 1920×1080 при 125 %, панель одной строкой 50, двумя 94):
1. `1420×700` → 1:1: ширина 1420 ≤ 1520, высота 700 ≤ 824−16−50−10=748. Ровно случай Кати: в 1.5.0 коробка 78/72 давала 85 %.
2. `1420×900` → вписан по высоте, масштаб 748/900.
3. `3840×1125` (весь экран двух мониторов) → вписан по ширине, масштаб 1520/3840.
4. Тот же `1420×700`, но панель двумя строками (высота 94) → уже не 1:1, высота коробки 704… 700 ≤ 704, всё ещё 1:1; взять `1420×720` для честной границы: с одной строкой 1:1, с двумя — вписан.
5. С открытой панелью комментариев: `work` = `WithoutCommentsStrip(1093×576, true)` = 797×576 → снимок 900 px шириной вписывается, не 1:1.
6. Прямоугольник всегда внутри `work` с полем ≥ 8 и с местом `panel.Height + gap` под ним.

**Новые, `ToolbarLayout.Measure`:**
1. Свободная ширина 1077 (1093−16, без панели комментариев) и блоки из эталона → одна строка.
2. Свободная ширина 781 (797−16, с панелью комментариев) → две строки, высота = две строки плюс `rowGap`.
3. Ширина двухстрочной панели не больше свободной.
4. Результат не зависит от инструмента: при неизменной `properties.Width` число строк одно и то же (это тест на контракт с C3).

**`PlaceToolbar` (уже без WPF, `Toolbar.cs`, но не линкуется в тест-проект — сейчас проверяется только smoke'ом).** Предложение: линковать `OverlayEditorWindow.Toolbar.cs` нельзя (это `partial class` окна). Вынести `PlaceToolbar` в `Controls/ToolbarLayout.cs` статическим методом рядом с `Measure` и линковать вместе с ним: тогда проверяются тестом, а не только smoke, три вещи — приоритет позиций, что при `mayOverlap == false` результат не пересекает `crop`, и что при `true` внутрь снимка панель попасть может.

**Smoke (`SmokeTestRunner.cs:455-461`).**
- `RunEditorScaleProbe` (`xaml.cs:500-566`) → переименовать в `RunEditorViewProbe`. Убрать `:519` (`_fitBox`), `:523-526` и `:553-554` (утверждения о переключателе), `:546` (`OnOneToOneScaleClick`). Оставить подпись вида снимка (`:528-533`), проверку ручек (`:555-557`) и пилюли за краем (`:558-561`) — в 1:1 они входят теперь через `Surface.ViewScale = 1` напрямую. Добавить: из вписанного состояния Ctrl+колесо даёт `ViewScale is not null` и `≤ 1` (регрессия на пункт 0.4), и `PlaceCapture` для снимка 1420×700 в области 1536×824 даёт прямоугольник ровно 1420×700.
- `RunPanelProbe` (`xaml.cs:410-492`). Переписать блок `:445-460`: вместо «`WrapPanel` перенёсся» — «при свободной ширине 781 `Grid.GetRow(ToolbarProperties) == 1`, при 1077 — `0`, и ширина панели одинакова при пяти инструментах». Блок `:466-484` (панель кладётся внутрь трёх рабочих областей) оставить, добавив четвёртое утверждение: `!placement.IntersectsWith(window._cropRect)` при `mayOverlap: false`. Добавить перетаскивание: нажатие на `ToolbarBody` в свободной колонке, `MouseMove`, отпускание → `Toolbar.Margin` изменился, и следующий `PositionToolbar()` его не сбросил.
- Строку «Настройки языка» (`:346`) почистить от двух пар.

## 6. Что не должно сломаться

| Что | Почему цело |
|---|---|
| Пилюли комментариев и их место при масштабе | `RepositionChips` (`xaml.cs:1482`) и `GetBadgeCenter` считают от `_cropRect` и `Surface`; `_cropRect` по-прежнему задаётся один раз до `SetupEditor`, только другой формулой. Ветка «спрятать пилюлю за краем» остаётся и проверяется smoke'ом |
| Лупа пипетки | `ScreenColorPicker`, `ColorSpectrum` — вне зоны, не трогаются |
| Экспорт и автосохранение | `WpfExportImageRenderer` рисует из `RenderAnnotated()` в пикселях картинки, `_cropRect` и `ViewScale` туда не входят |
| Обрезка и ручки границ снимка | `OnCropRequested` → `SetupEditor` → `PositionToolbar`; `UpdateCaptureHandles` (`Resize.cs:103-124`) прячет ручки при `ViewScale is not null` — правило то же, вход в масштаб теперь только через Ctrl+колесо |
| Панель комментариев справа | `LayoutWorkArea`/`WithoutCommentsStrip` остаются единственным источником свободной ширины и теперь питают и снимок, и панель |
| Поповеры цвета, толщины, стиля, шпаргалка | Привязаны по `ElementName`, переезд в сетку их не трогает; `SegmentButton` не удалять |
| Smoke целиком | `RunAsync` зовёт семь проб редактора (`SmokeTestRunner.cs:455-461`), все они идут через `SetupEditor` → `PositionToolbar` |

## 7. Риски

1. **Порядок «померить панель → положить снимок → положить панель».** Раньше `_cropRect` считался первым. Теперь `OnLoaded` обязан измерить панель до него, а панель на этот момент `Collapsed` и меряется в ноль. Ошибка тихая: снимок займёт всю рабочую область, панель ляжет на него. Лечится выставлением `Visibility` до `Measure`; в smoke проверяется на окне, которое никогда не показывали.
2. **`Toolbar.Margin` входит в `DesiredSize`.** Про это уже написан комментарий в пробе (`xaml.cs:415-421`) и это уже баг: `PositionToolbar` меряет панель с тем `Margin`, который поставил в прошлый раз. С перетаскиванием отступ станет большим и постоянным, и арифметика перевернётся. `PositionToolbar` обязан обнулять `Margin` перед измерением и ставить его в конце.
3. **Затравка Ctrl+колеса.** `FitScale` считает от `ActualWidth - ImagePadding * 2`; у `Surface` `ImagePadding="0"` (`xaml:140`), но по умолчанию у контрола 28 (`AnnotationCanvas.cs:67`). Если кто-то вернёт отступ, при первом щелчке Ctrl картинка прыгнет. Прибить комментарием на месте затравки.
4. **Две инициализации `_fitBox`.** Убрать обе (0.2), иначе коробка 78/72 переживёт правку в пути обрезки.
5. **Перетаскивание против нажатий на холсте.** `ToolbarBody` захватывает мышь; пока захват держится, `Surface` нажатий не видит. Обязательно отпускать захват и в `MouseLeftButtonUp`, и в `LostMouseCapture`, иначе одно неудачное нажатие вешает рисование до закрытия редактора.
6. **Граница с C3 по ширине блока свойств.** Если `ToolbarProperties` окажется резиновым, число строк начнёт скакать от инструмента в руке и панель будет прыгать под курсором. Тест 4 раздела 5 ловит именно это; договорённость о `MinWidth` — в контракте 2.2.

## 8. Что идёт в общий фундамент

- `Controls/EditorGeometry.PlaceCapture` и `Controls/ToolbarLayout` (`Measure` + переехавший туда `PlaceToolbar`) — чистые, без WPF-зависимостей кроме `Size`/`Rect`, линкуются в `Snapik.App.Imaging.Tests` точечно (тест-проект не ссылается на `Snapik.App`).
- `LayoutWorkArea()` как единственный ответ на «сколько места на экране»: C5 нужен тот же прямоугольник, чтобы знать, куда можно вынести бейдж за границу снимка, а C3 — чтобы поповеры не уезжали за край.
- Контейнерный контракт панели (`ToolbarTools` / `ToolbarProperties` / `ToolbarActions` + `ToolbarBody` как ручка) — им пользуются C3 и C6.
- Приём «тянем за свободное место, кнопки забирают нажатие раньше» — второе применение `EdgeStackWindow.OnShellMouseDown` (`:1727-1731`); имеет смысл описать его один раз в `tasks/verification.md`, чтобы Mac переносил оба места одинаково.

## 9. Перенос на macOS

`AGENTS.md` пункт 2: Windows-исполнитель `macos/` не трогает, перенос идёт отдельным проходом по diff. Что переносить:

- `macos/Sources/SnapikMac/Editor/EditorScaleSwitchView.swift` держит **два** класса: `EditorScaleSwitchView` (`:9-93`) и `EditorShotKindView` (`:95-141`). Переключатель удаляется, подпись вида снимка остаётся — файл не удалять, а разрезать: `EditorShotKindView.swift` отдельным файлом, остаток выбросить. Сейчас имя файла врёт, и удаление «файла переключателя» унесёт подпись.
- `OverlayEditorController+Scale.swift` (124 строки): половина про переключатель (`:13-18`) уходит, половина про подпись (`:19-72`) остаётся. Файл переименовать в `+CaptureView.swift`.
- `OverlayEditorController.swift:163` (`scaleSwitchView`) — убрать; `:164` (`shotKindView`) — оставить.
- `OverlayEditorController+SmokeTest.swift:410-444` — снять guard по `scaleSwitchView`, утверждения про подпись (`:441-444`) сохранить.
- `macos/Sources/SnapikMac/Editor/EditorGeometry.swift` получает порт `PlaceCapture`, `EditorToolbarView.swift` — две строки и перетаскивание. На маке рабочая область — `NSScreen.visibleFrame`, а не `WorkingArea`, и начало координат снизу: формула `PlaceCapture` от этого не зависит (она на `Rect`), но `top` придётся считать зеркально — это единственное место, где порт не дословный.
- Запись для Mac-прохода положить в `tasks/verification.md` абзацем, как требует `AGENTS.md` пункт 5.
