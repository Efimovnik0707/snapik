# C2 · Модель редактора (C3 инспектор, C4 одна модель объектов, C5 комментарий)

Разбор по `master` `d84fbb0`, пути от `src/Snapik.App/` если не сказано иначе. Эталоны: `tasks/handoff-006/reference-png/01-redaktor-panel-inspektor.png`, `02-kommentariy-tochka-liniya-beydzh.png`, разметка `reference-html/01-editor-inspector.html`, `02-comment-gesture.html`.

Соседняя зона: укладка панели, две строки, перетаскивание и уголки (C1, C2, C6) — у другого аналитика. Здесь только содержимое блока свойств, модель объектов и комментарий.

## 0. Где ТЗ не сходится с кодом

1. C3 ссылается на `OverlayEditorWindow.Appearance.cs:364-372` за `_activeColor` и `_activeFillColor` — сами поля живут в `OverlayEditorWindow.xaml.cs:45` и `:57`, а `:364-372` это тело `ApplyAppearance`, где правило «один цвет на всё» и записано. Диагноз верный, адрес полей другой.
2. «Палитры как сейчас (стандартная / пастель / **неон** / своя)» — в коде три палитры (`Appearance.cs:56-67`), «неон» убрана в tz-004 и заменена «своей». Разметка эталона 01 показывает **четыре** сегмента: `Стандартная | Пастель | Неон | Своя`. Открытый вопрос, см. §1.7.
3. `SaveAppearanceDefaults` указан как `:650-681`; фактически `:650-670`, дальше идут парсеры `:672-684`. Мелочь, но исполнителю нужен точный адрес.
4. «Толщина 2/4/6/8» в поповере обводки — в коде пресеты зависят от инструмента: у маркера свои `8/12/16/24` и свой диапазон `4…48` (`Appearance.cs:24-26, :36, :98-99`). Эталон 01, кадр «Маркер», показывает `20 px`, то есть свою шкалу маркер сохраняет. Не противоречие, но записать явно: `2/4/6/8` — про рамку, стрелку, линию и карандаш.
5. Правило 6 («рамка помнит заливку и между снимками») прямо отменяет комментарий `Appearance.cs:646-649`: сегодня фигура, заливка и её цвет **не** сохраняются, каждый снимок начинается с контурной рамки. Это осознанный разворот, а не баг.
6. «У стрелки ещё наконечник в уголке кнопки» — уголок висит на кнопке инструмента (`ArrowMenuButton`, `xaml:216`), это зона C1. В блоке свойств наконечника нет ни в одном из семи кадров эталона.
7. C4: «Текст правится двойным кликом (`:249-253`)» — `AnnotationCanvas.cs:249-254` это общая ветка двойного клика для **любой** отметки (`AnnotationActivated`), разделение на текст и пилюлю происходит в `xaml.cs:1275-1277`.
8. C4: `FindResizeHandle` сегодня отвечает за углы **любой** отметки при любом инструменте кроме «Комментария» (`AnnotationCanvas.cs:622-628`), а не только выделенной. Новый порядок это сужает, и старое поведение придётся снимать намеренно.
9. C5: «`ClampToImage` для бейджа снять» — снимать нечего. Бейдж **не двигается по холсту вообще**: единственный путь правки `NoteOffset` — перетаскивание пилюли в слое чипов (`xaml.cs:1341-1362`, `BeginNoteDrag`/`DragNoteTo`/`EndNoteDrag`), и там клампа нет. `ClampToImage` (`AnnotationCanvas.cs:985`) участвует в переносе якоря (`:342-346`) и в переносе выделенного (`:354`). Значит задача не «снять клампинг», а «завести перетаскивание бейджа за сам бейдж», см. §3.1.
10. C5: «бейдж не выходит за снимок» — по горизонтали его сегодня ничто не держит; за границы он не выходит по двум другим причинам: экспорт обрезан размером снимка (`WpfExportImageRenderer.cs:43`), а на экране пилюля прячется, когда бейдж уехал за кадр **при своём масштабе** (`xaml.cs:1590`). Плюс кламп сверху под заголовок: `ExportBadge` зовёт `NoteBadgeGeometry.Export(..., HeaderHeight + 2)` (`WpfExportImageRenderer.cs:181`).
11. C5: снятие привязки — `ParentAnnotationId` держит не только `MoveLinkedComments`. На него смотрят подпись строки в панели комментариев (`Comments.cs:73-82`, «К отметке A2» / «К снимку A») и `prompt.md` (`src/Snapik.Core/Exporting/PromptGenerator.cs:53-58`, «(к области A2)»). В ТЗ этого нет; поле остаётся в формате, см. §3.5.
12. C4: «нажатие на чужой объект начинает новый» — верно (`AnnotationCanvas.cs:273`), но с оговоркой: булавка комментария и сейчас перехватывает нажатие «Выбором» и «Комментарием» (`FindLeaderAnchor:859`, `IsMoveHandle:881`), а другими инструментами — нет.

---

## 1. C3 · Панель как инспектор

### 1.1 Диагноз

Панель сегодня — набор независимых кнопок над **одним** набором активных значений: `_activeColor`, `_activeThickness`, `_activeHighlightThickness`, `_activeFontSize`, `_activeShape`, `_activeFill`, `_activeFillColor`, `_activeLineStyle` (`xaml.cs:45-58`). `ApplyAppearance` (`Appearance.cs:359-391`) пишет правку и в активное значение, и в выделенную отметку сразу, а «можно ли» решают предикаты по инструменту `HasStroke`/`HasShape`/`HasFill`/`HasFontSize`/`HasLineStyle` (`:39-49`). Из-за одного набора цвет, взятый с «Комментарием» в руке, достаётся следующей рамке (D-1 ТЗ №4) — ровно то, что Катя назвала «криво».

Пять точек быстрого цвета (`ColorDots`, `BuildColorDots` `:209-229`) и шесть отдельных кнопок (`AppearanceButton`, `ThicknessButton`, `LineStyleButton`, `FillButton`, `FontSizeButton`, `xaml:238-261`) занимают ширину, которая меняется от инструмента к инструменту через `IsEnabled`, но ширина каждой кнопки фиксирована, поэтому панель не прыгает — прыгает смысл.

### 1.2 Решение: `ToolAppearance`

Новый файл `ToolAppearance.cs` (зона C2), запись без поведения:

```csharp
internal sealed record ToolAppearance
{
    internal Color Color { get; init; } = OverlayEditorWindow.DefaultAnnotationColor;
    internal double Thickness { get; init; } = OverlayEditorWindow.DefaultAnnotationThickness;
    internal AnnotationLineStyle LineStyle { get; init; } = AnnotationLineStyle.Solid;
    internal AnnotationFill Fill { get; init; } = AnnotationFill.None;
    // null = «как обводка»: та же семантика, что у AnnotationItem.FillColor и session.json.
    internal Color? FillColor { get; init; }
    internal double FontSize { get; init; } = TextMarkMetrics.DefaultFontSize;
    internal string ArrowStyle { get; init; } = "straight";
    internal AnnotationShape Shape { get; init; } = AnnotationShape.Rectangle;
}
```

Хранилище в окне вместо восьми полей: `private readonly Dictionary<EditorTool, ToolAppearance> _tools`, ключи `Rectangle`, `Arrow`, `Pen`, `Highlight`, `Text`, `Blur`. `Select`, `Eraser`, `Crop`, `Comment` ключей не имеют — у них нет свойств.

Общее между инструментами ровно одно и по эталону: **форма** у рамки и размытия («форма общая с рамкой», кадр 6). Держим её в записи `Rectangle`; `Blur` читает и пишет `_tools[Rectangle].Shape`. Палитра (`_activePalette`, `_customColors`) и режим карандаша (`_activePencil`) остаются общими: это состояние панели, а не свойство отметки.

### 1.3 Контракт блока свойств (граница с C1)

C1 владеет контейнером панели, её строками, перетаскиванием и уголками. Я владею содержимым блока и пятью поповерами. Граница по именам элементов в `OverlayEditorWindow.xaml`:

| Имя | Что это | Размеры из эталона |
|---|---|---|
| `PropertiesBlock` | `StackPanel Orientation=Horizontal`, **`Width="176"`** фиксировано, `Margin="0"`, между двумя разделителями C1 | 176 × 36, зазор между капсулами 6 |
| `ColorCapsule` | `Button`, открывает поповер обводки | H 36, `Padding="10,0"`, `CornerRadius=9`, фон `#0DFFFFFF`, внутренний зазор 7 |
| `StrokeDot` | `Ellipse` внутри `ColorCapsule`, цвет обводки | 18 × 18, обводка `#D9DEE8` 1 px |
| `FillSquare` | `Border` внутри `ColorCapsule`, цвет заливки | 18 × 18, `CornerRadius=4`, рамка `#D9DEE8` 1 px |
| `FillSquareNone` | `Path` — косая черта в квадрате, когда заливки нет | `#FF5C5C`, 1.6 px |
| `FillSquareBlur` | `Rectangle` с кистью `BlurFillPreview` (ресурс уже есть, `xaml:353`) | по квадрату |
| `LineCapsule` | `Button`, вторая капсула; открывает поповер толщины/линии, размера или формы — по инструменту | H 36, те же отступы |
| `LineCapsuleGlyph` | `TextBlock` слева в капсуле: `A` для текста, глиф формы для размытия; скрыт у штриховых | 14 × 12 у формы |
| `LineCapsuleValue` | `TextBlock`: `4 px` / `20 pt` / `Скруглённый` | 12 px, `#EEF2F8` |
| `LineCapsuleSample` | `Line` — образец штриха, толщина и пунктир как у отметки | 22 × 6, `#D9DEE8` |
| `LineCapsuleChevron` | `Path` — уголок «есть поповер» | 9 × 5 |

Выключенное состояние (кадр 7): обе капсулы `IsEnabled=false`, `Opacity=0.28`, место держат. Разделители `1 × 22`, `Margin="7,0"`, `#3A424E` — элементы C1.

Уходят из `xaml`: `ColorDots`, `AppearanceButton`+`ColorSwatch`, `ThicknessButton`, `LineStyleButton`+`LineStyleGlyph`, `FillButton`+`FillButtonPreview`+`FillButtonLabel`, `FontSizeButton`. Вместе с ними `BuildColorDots` (`Appearance.cs:209-229`) и поле `Quick` записи `PaletteSet` (`:54`) — быстрый ряд переезжает в поповер, где двенадцать образцов и так есть. `PaletteSet.Quick` в `settings.json` не пишется, снятие поля формата не меняет.

Поповеры остаются пятью, но открываются двумя кнопками: `ColorCapsule` → `AppearancePopup`, `LineCapsule` → `ThicknessPopup` | `FontSizePopup` | форма (меню C1, `OnShapeMenuClick`), `FillSquare` → `FillPopup`. `LineStylePopup` сливается в `ThicknessPopup`: эталон показывает в поповере обводки и толщину, и «сплошная/пунктир» одним блоком.

### 1.4 Что показывать: чистые правила

```csharp
internal enum SecondCapsule { None, Line, FontSize, Shape }

internal readonly record struct InspectorView(bool Stroke, bool FillSwatch, SecondCapsule Second, bool Enabled);

internal static InspectorView InspectorViewOf(EditorTool tool) => tool switch
{
    EditorTool.Rectangle => new(true,  true,  SecondCapsule.Line,     true),
    EditorTool.Arrow     => new(true,  false, SecondCapsule.Line,     true),
    EditorTool.Pen       => new(true,  false, SecondCapsule.Line,     true),
    // Маркер: цвет и толщина, стиля линии нет (StrokePattern.Participates его не берёт).
    EditorTool.Highlight => new(true,  false, SecondCapsule.Line,     true),
    EditorTool.Text      => new(true,  false, SecondCapsule.FontSize, true),
    // Размытие: только форма, цвета нет — капсула цветов скрыта, не выключена.
    EditorTool.Blur      => new(false, false, SecondCapsule.Shape,    true),
    _                    => new(true,  true,  SecondCapsule.Line,     false)
};
```

Правило «чей инструмент» одно на весь блок:

```csharp
internal static EditorTool InspectedTool(AnnotationItem? selected, EditorTool armed) => selected?.Kind ?? armed;
```

`SyncAppearance` (`Appearance.cs:231-357`) переписывается по этой паре: берёт `InspectedTool`, вызывает `InspectorViewOf`, значения читает из выделенной отметки, а если её нет — из `_tools[armed]`. `Surface.Active*` всегда заполняются из `_tools[Surface.Tool]` (правило «следующая отметка рисуется настройками инструмента в руке», как сегодня делает `:244`).

### 1.5 Куда уходит правка

```csharp
// Правило 2 ТЗ: выделено — в отметку, не выделено — в инструмент.
private void ApplyAppearance(...)
{
    var selected = Surface.SelectedAnnotation;
    var tool = InspectedTool(selected, Surface.Tool);
    if (selected is not null) { /* писать в selected, _appearanceChanged = true */ }
    else { _tools[tool] = _tools[tool] with { ... }; _appearanceDefaultsChanged = true; SyncSurfaceDefaults(); }
}
```

Проверка «можно ли» остаётся за `InspectorViewOf(tool)`, а не за пятью предикатами: `HasStroke`/`HasShape`/`HasFill`/`HasFontSize`/`HasLineStyle` (`:39-49`) сводятся к полям `InspectorView` и удаляются. `HasLineStyle` делегирует `Imaging.StrokePattern.Participates` — оставить вызов внутри `InspectorViewOf`, чтобы правило «маркер без пунктира» жило в одном месте (его же читают рендереры).

Правило 5 (заливка включилась — цвет сначала как обводка): `FillColor` остаётся `null` до первой явной правки цвета заливки, `null` рисуется как `Color`. Ничего специально копировать не нужно, но при выборе `Solid`/`Translucent` панель показывает в `FillSquare` цвет обводки — это делает `SyncAppearance` через `fillColor ?? color`, как сейчас `:245`.

### 1.6 Обводка и заливка врозь: `OutlineColorOf`

Сегодня (`AnnotationCanvas.cs:810-815`) заливка красит обводку: `Solid`/`Translucent` → `fillColor ?? color`. Решение Кати это отменяет. Новая версия:

```csharp
// Обводка всегда своего цвета; размытая область обводки не имеет вовсе.
internal static Color? OutlineColorOf(AnnotationFill fill, Color color) =>
    fill == AnnotationFill.Blur ? null : color;
```

Параметр `fillColor` уходит — это **изменение контракта волны 0 ТЗ №4** (`tasks/tz-005-plan.md` §3), перед правкой прогнать `trace_call_path` inbound по `OutlineColorOf`. Две точки применения: `AnnotationCanvas.cs:826-828` и `WpfExportImageRenderer.cs:127-130`. Кисть внутренности по-прежнему `ShapeFillBrush(item.FillColor ?? item.Color, item.Fill)`.

`AnnotationItem` (`EditorModels.cs:44-63`) и Core-`AnnotationItem` (`src/Snapik.Core/Models/AnnotationItem.cs:48-85`) **менять не нужно**: `Color`/`StrokeColor`, `FillColor`, `Fill`, `LineStyle`, `Thickness`, `Shape`, `FontSize` уже раздельные поля, `session.json` уже их пишет. Правило чтения старой рамки (`LegacyHasOutline`, `:73-79`) не трогаем.

Побочное следствие, которое надо признать вслух: снимок 1.5.0 с `Fill=Solid`, `FillColor=#0000FF`, `StrokeColor=#FF3B30` рисовался с синей обводкой, теперь нарисуется с красной. Это решение Кати, а не регресс; формат от этого не меняется, меняется чтение.

### 1.7 Палитра «неон» — открытый вопрос

Код: три палитры (`Appearance.cs:56-67`), три сегмента (`xaml:310-312`), `PaletteRow Columns="3"`. Эталон 01 (и HTML, и PNG) показывает четыре: `Стандартная | Пастель | Неон | Своя`. «Неон» был убран в tz-004 намеренно, чтобы освободить место «своей».

Предложение: вернуть «неон» четвёртым набором, `PaletteRow Columns="4"`, `ParseAnnotationPalette` уже падает на стандартную для неизвестного `id` (`:683-684`), значит откат безопасен и в обе стороны. Цвета набора в ТЗ не заданы — **нужно решение Никиты**: взять двенадцать из архива tz-004 или собрать новые. Ключ `AnnotationPalette` строковый, формата не меняет.

### 1.8 Изменение формата `settings.json`

Файл читается `HotkeySettingsWindow.xaml.cs:141-175` (`TryRead`), пишется `:197-212` (`Save`), мигрируется `:108-116` (`Migrate`).

**Изменение формата.** Появляется один новый ключ `ToolAppearance` — словарь «инструмент → его настройки»:

```json
"toolAppearance": {
  "rectangle": { "color": "#34C759", "thickness": 4, "lineStyle": "dashed",
                 "fill": "translucent", "fillColor": "#FF3B30", "shape": "rounded" },
  "arrow":     { "color": "#007AFF", "thickness": 4, "lineStyle": "dashed", "arrowStyle": "straight" },
  "pen":       { "color": "#FF3B30", "thickness": 4, "lineStyle": "solid" },
  "highlight": { "color": "#FFCC00", "thickness": 16 },
  "text":      { "color": "#FFFFFF", "fontSize": 20 }
}
```

Ключи словаря — имена `EditorTool` в camelCase, как их уже пишет `SnapikJson.Options` для перечислений; неизвестный ключ при чтении молча пропускается, чтобы файл из более новой сборки не ронял старую. Прежние общие ключи `AnnotationColor`, `AnnotationThickness`, `AnnotationHighlightThickness`, `AnnotationFontSize` **остаются в записи и продолжают писаться**: `AnnotationColor` и `AnnotationThickness` зеркалят рамку, `AnnotationHighlightThickness` — маркер, `AnnotationFontSize` — текст. Так файл, записанный этой сборкой, полностью читается 1.5.0 и установка «поверх» в обе стороны не теряет настроек. При чтении: если `ToolAppearance` отсутствует или пуст, каждый инструмент получает старые общие значения (цвет и толщину — все, толщину маркера — маркер, размер — текст), то есть файл 1.5.0 открывается ровно так, как выглядел. `SettingsVersion` не поднимается: миграция здесь по отсутствию ключа, значения старых ключей не переписываются, и `Migrate` (`:108`) не трогаем — иначе `LoadAndMigrate` начнёт переписывать файл на каждом старте. `AnnotationPalette`, `AnnotationPencil`, `CustomPaletteColors` остаются как есть.

Чтение и запись — в отдельном статическом классе `ToolAppearanceStore` (тот же файл `ToolAppearance.cs`):

```csharp
internal static Dictionary<EditorTool, ToolAppearance> Read(HotkeySettings settings);
internal static HotkeySettings Write(HotkeySettings settings, IReadOnlyDictionary<EditorTool, ToolAppearance> tools);
```

`SaveAppearanceDefaults` (`Appearance.cs:650-670`) становится трёхстрочным: `TryLoad` → `ToolAppearanceStore.Write` → `Save`. Комментарий `:646-649` («фигура, заливка и её цвет не сохраняются») переписывается: теперь сохраняются, это правило 6.

### 1.9 Что меняется (список)

- `ToolAppearance.cs` — новый: запись + `ToolAppearanceStore` + `InspectorView`/`InspectorViewOf`/`InspectedTool`.
- `OverlayEditorWindow.xaml.cs:45-58` — восемь активных полей → `_tools`; `:82-87` — чтение настроек через `ToolAppearanceStore.Read`; `:1087-1093` — `Surface.Active*` из `_tools[Surface.Tool]`.
- `Appearance.cs` — `:39-49` предикаты удалить; `:209-229` `BuildColorDots` удалить; `:231-357` `SyncAppearance` переписать; `:359-391` `ApplyAppearance` переписать по §1.5; `:650-670` `SaveAppearanceDefaults` переписать; `:98-117` `ThicknessPresetsFor`/`ActiveThicknessFor`/`SetActiveThickness` свернуть в работу со словарём.
- `AnnotationCanvas.cs:810-815` — `OutlineColorOf`; `:826-828` и `WpfExportImageRenderer.cs:127-130` — вызовы.
- `OverlayEditorWindow.xaml:235-261` — блок свойств по §1.3; `:302-345` `AppearancePopup` принимает толщину и стиль линии; `:374-395` `LineStylePopup` удалить.
- `UiLanguage.cs` — новые строки, см. §1.10.

### 1.10 Строки RU/EN

Новые ключи в `UiLanguage.English`: `["Обводка"] = "Stroke"`, `["Цвет обводки"] = "Stroke color"`, `["Скруглённый"] = "Rounded"`, `["Нет"] = "None"`, `["Полупрозрачно"] = "Translucent"`, `["Размытие"] = "Blur"`. Если «неон» возвращается — `["Неон"] = "Neon"`. Уже есть и переиспользуются: `Цвет`, `Цвет заливки`, `Заливка`, `Толщина`, `Линия`, `Сплошная`, `Пунктир`, `Точки`, `Стандартная`, `Пастель`, `Своя`, `Прямоугольник`, `Овал`, `Размер` (`UiLanguage.cs:65-82`).

### 1.11 Тесты (только новая логика)

Чистые функции, без окна:

1. `InspectorViewOf` — таблица по семи кадрам эталона: рамка `(true,true,Line,true)`, стрелка/линия/карандаш `(true,false,Line,true)`, маркер `(true,false,Line,true)`, текст `(true,false,FontSize,true)`, размытие `(false,false,Shape,true)`, комментарий/ластик/обрезка `Enabled=false`.
2. `InspectedTool` — выделена стрелка при рамке в руке → `Arrow`; ничего не выделено → инструмент в руке.
3. `ToolAppearanceStore.Read` — файл без `ToolAppearance`: все инструменты получают `AnnotationColor` и `AnnotationThickness`, маркер — `AnnotationHighlightThickness`, текст — `AnnotationFontSize`.
4. `ToolAppearanceStore.Read` — файл с `ToolAppearance`: старые ключи игнорируются, неизвестный инструмент в словаре пропускается без исключения.
5. `Write`→`Read` — круговой прогон по четырём инструментам сценария Кати, плюс проверка, что `AnnotationColor`/`AnnotationThickness` в записанном файле зеркалят рамку.
6. `OutlineColorOf` — `None`→`color`, `Solid`→`color`, `Translucent`→`color`, `Blur`→`null`; заливка не красит обводку ни в одном случае.

### 1.12 Smoke: обязательный тест правила 6

Новый `OverlayEditorWindow.RunToolMemoryProbe(CaptureItem source)` рядом с `RunPanelProbe` (`xaml.cs:270-291`), вызов из `SmokeTestRunner.cs` около `:458` тем же `WithoutBindingErrors("The memory of each tool", …)`. Сценарий — дословно Катин:

1. Рамка: обводка `#34C759`, заливка `Translucent`, цвет заливки `#FF3B30`, толщина 4.
2. Стрелка: цвет `#007AFF`, `LineStyle=Dashed`.
3. Текст: цвет `#FFFFFF`, размер 20.
4. Маркер: цвет `#FFCC00`.
5. Снова рамка: `_tools[Rectangle]` отдаёт зелёную обводку, полупрозрачную красную заливку и 4 px; `StrokeDot.Fill`, `FillSquare` и `LineCapsuleValue` показывают их же; `Surface.ActiveColor/ActiveFill/ActiveFillColor/ActiveThickness` совпадают.
6. Жестом рисуется рамка — у созданной отметки те же `Color`, `Fill`, `FillColor`, `Thickness`.
7. Окно закрывается (`FlushAppearanceDefaults` пишет файл), над **тем же** `SessionWorkspace` открывается второе окно на новом снимке — п. 5 повторяется целиком.

Проба держит свой временный workspace, как `RunPanelProbe` (`:273-274`), и удаляет его в `finally`. `PanelChecks` (`xaml.cs:292-…`) правится под новые имена элементов: `ThicknessButton.Content` → `LineCapsuleValue.Text`, `ColorDots` из проверки палитры уходит (`:300-302`), остаются двенадцать образцов `ColorPalette`.

---

## 2. C4 · Одна модель объектов

### 2.1 Диагноз

`AnnotationCanvas.BeginGesture` (`:221-319`): панорама → ластик → двойной клик → якорь выноски → ручки → **`if (Tool == EditorTool.Select || handleHit.Annotation is not null || FindMoveHandle(point) is not null)`** (`:273`) → иначе черновик. Ключевое слово здесь `Tool == EditorTool.Select`: попасть в выделение чужого объекта другим инструментом можно только через `FindMoveHandle`, а он для «не своего вида» даёт полосу 6 px по контуру (`:909`), для «своего вида» 10 px, и внутренность пустой рамки оставляет свободной (`:914-917`). Текст спасает `HasInteriorGrab` (`:925-926`), но только если нажатие вообще дошло до `FindMoveHandle` — а с рисующим инструментом в руке оно доходит, так что текст ловится; не ловилось у Кати из-за 6 px по краю на мелком тексте и из-за того, что двойной клик по тексту требует попадания в `HitTestAnnotation` c инфляцией `Math.Max(8, Thickness/2+4)` (`:641`) при `Thickness` текста, равной толщине пера.

### 2.2 Новый порядок нажатия

Чистая функция для теста, рядом с `BeginGesture`:

```csharp
internal enum PressTarget { Pan, Erase, CropDraft, Activate, CommentAnchor, ResizeHandle, Object, Empty }

internal static PressTarget PressTargetOf(EditorTool tool, bool panning, int clickCount,
    bool onAnchor, bool onSelectedHandle, bool onObject, bool activatable) =>
        panning                                  ? PressTarget.Pan
      : tool == EditorTool.Eraser                ? PressTarget.Erase
      // Обрезка не объектный инструмент: рамка обрезки тянется поверх чего угодно.
      : tool == EditorTool.Crop                  ? PressTarget.CropDraft
      : clickCount == 2 && activatable           ? PressTarget.Activate
      : onAnchor                                 ? PressTarget.CommentAnchor
      : onSelectedHandle                         ? PressTarget.ResizeHandle
      : onObject                                 ? PressTarget.Object
      :                                            PressTarget.Empty;
```

`activatable` — отметка под курсором это `Text` или `Comment` (правило «двойной клик по тексту/комментарию — правка»); по рамке или стрелке двойной клик = два одиночных, то есть просто выделение.

Что меняется в источниках сигналов:

- `FindLeaderAnchor` (`:857-863`) — снять условие `Tool is not (Select or Comment)`: якорь отвечает любому инструменту.
- `FindResizeHandle` (`:610-630`) — снять исключение для `Comment` (`:615`) и снять цикл по всем отметкам (`:622-628`): углы отвечают **только у выделенной**. Это и есть «ручки выделенного» из ТЗ.
- `IsMoveHandle` (`:876-920`) — снять `Tool == EditorTool.Comment` (`:881`) и правило «того же вида»: `var reach = item.Kind == Tool ? 10 : 6;` (`:909`) → `const double Reach = 8;` для всех. Внутренность пустой рамки остаётся свободной (`:913-917`), `HasInteriorGrab` (`:925-926`) без изменений — на нём держится «текст тянется за любое место».
- Ветка `:273` заменяется на `PressTarget.Object`: `var hit = FindMoveHandle(point) ?? HitTestAnnotation(imagePoint)` для **любого** инструмента.
- `PressTarget.Empty`: `Select(null)` и черновик, как сегодня (`:296-318`).

### 2.3 Порог перетаскивания и клик

Сегодня любое движение мыши в состоянии `_manipulating` ставит `_manipulationChanged = true` (`:377`), и клик по объекту с дрожанием руки на 1 px пишет запись истории. Ввести гейт, как у якоря (`:343-344`):

```csharp
if (!_manipulationMoved && (current - _gestureStart.Value).Length * scale < GestureThreshold) return;
_manipulationMoved = true;
```

`GestureThreshold = 4` (`:837`) уже измеряется на экране — та же константа. Сбрасывать `_manipulationMoved` в `BeginGesture` и в `OnLostMouseCapture` (`:501-519`) рядом с `_manipulationChanged`.

Создание новых отметок жестом уже подчиняется тому же порогу через `GestureHasSize` (`:839-847`) — это правило 4 ТЗ, оно работает и менять его не надо. Исключение там же: `Comment` и `Text` ставятся одиночным кликом.

### 2.4 Текст

`HasResizeHandles` (`:833`) уже исключает `Text` и `Comment` — углов у текста нет, и это правильно. `HasInteriorGrab` уже включает `Text`. После §2.2 остаётся один пробел: `HitTestAnnotation` (`:631-646`) инфлирует границы на `Math.Max(8, Thickness/2 + 4)`, а у текста `Thickness` к размеру букв отношения не имеет (размер живёт в `FontSize`, `EditorModels.cs:66`). Для `Text` брать инфляцию 4 px без вклада толщины — иначе текст 12 px ловится полосой 8 px вокруг и перекрывает соседей.

### 2.5 Что правится в smoke

- `VerifyGestureRules` (`AnnotationCanvas.cs:1080-…`): проверки «клик в пустоту только снимает выделение» и «два пикселя дрожи не становятся отметкой» остаются. Добавить: с «Рамкой» в руке клик по существующей рамке **выделяет** её и не создаёт второй; перетаскивание за контур переносит её и пишет **одну** запись истории; клик по ней же без движения записи не пишет. Блок про «Комментарий» (`:1176-…`) переписать: нажатие рядом с углом выделенной рамки при «Комментарии» теперь попадает в угол (углы отвечают всем), поэтому точку для новой булавки в пробе брать заведомо вдали от выделенного.
- `VerifyHoverManipulation` (`:1244-1341`): утверждения `interiorGrabs` (`:1328-1335`) и вся арифметика «того же вида 10 px» пересчитываются под единый `Reach = 8`. Проверки «стрелка берётся за линию, а не рядом» (`:1278-1280`) и «булавка берётся за бейдж» (`:1297-1299`) остаются.
- Новый тест на `PressTargetOf` — таблица восьми входов, без канвы.

### 2.6 Что не должно сломаться

Рисование новых отметок жестом в пустоте (правило 4 и `GestureHasSize`); ластик — он отвечает первым и берёт `FindMoveHandle ?? HitTestAnnotation` (`:427-428`), новый единый `Reach` только делает его предсказуемее; размытие как инструмент (`Blur` рисуется черновиком, кэш `_blurCache` при переносе `:990-992`); обрезка — вынесена из объектной модели явно (`CropDraft`), иначе рамку обрезки нельзя было бы протянуть поверх отметок; undo/redo — записи пишет `AnnotationChanged` (`:456`, `:468`), число записей на жест не меняется; панорама пробелом (`:224-230`).

Отдельно: после §2.2 рисовать **внутри** залитой рамки или поверх текста станет нельзя — нажатие выделит их. Это прямое следствие правила 1 ТЗ и стандарт Figma/Preview. Смягчение: внутренность **пустой** рамки остаётся свободной, как и сейчас.

---

## 3. C5 · Комментарий: точка, линия, бейдж

### 3.1 Перетаскивание бейджа по холсту (сейчас его нет)

`IsMoveHandle` для `Comment` отвечает по бейджу (`:886-887`), но ветка `_manipulating` двигает `Points` (`:368-374`), то есть тянет **точку вместе с бейджем**. Нужна третья ветка жеста рядом с `_anchorDrag`:

- `_badgeDrag` — нажали на бейдж комментария: запоминаем `NoteOffset` (может быть `null`) и точку начала в координатах снимка.
- В `UpdateGesture`: `NoteOffset = (origin ?? default) + (ToImage(displayPoint) - start)` — **без `ClampToImage`**. Порог 4 px как у якоря (`:343`).
- В `EndGesture`: одна запись истории, как у `_anchorDrag` (`:447-459`).

Точка при этом стоит: `Points` не трогаем. Кадр 2 эталона.

Якорь (`_anchorDrag`, `:258-268`, `:340-351`) остаётся как есть: тянет точку, компенсирует `NoteOffset`, бейдж стоит — кадр 4, ТЗ подтверждает «уже так». `ClampToImage` там **сохраняется** (`:342`, `:346`): точка за снимок не уходит. Порядок опроса: якорь спрашивается раньше бейджа, поэтому при `NoteOffset == null`, когда они совпадают, выигрывает якорь и уезжает всё вместе — это ожидаемое «не сдвинутый комментарий переносится целиком».

Ещё две точки, где бейдж не должен клампиться: `:354` (`_manipulating`) и `:369-370` (клампинг дельты по границам снимка) — для `Comment` ветка `_manipulating` вообще не должна включаться после введения `_badgeDrag`; и `:385` (`ClampToImage` черновика) — см. §3.2.

Существующее перетаскивание пилюли (`xaml.cs:1341-1362`) остаётся вторым способом и тоже теряет клампинг (его там и нет). `RepositionChips` (`xaml.cs:1586-1605`) прячет пилюлю только при своём масштабе — бейдж на затемнённом фоне рядом со снимком пилюлю не теряет.

### 3.2 Постановка жестом «нажал — потянул»

`Comment` сейчас ставится черновиком (`:298-316`), `GestureHasSize` для него всегда `true` (`:842`), а `Points[1]` дописывается уже в окне (`xaml.cs:1247`). Новое: пока черновик комментария тянут, править не `Points[1]`, а `NoteOffset`:

```csharp
if (_draft.Kind == EditorTool.Comment)
    _draft.NoteOffset = ToImage(displayPoint) - _gestureStart.Value;   // без ClampToImage
else if (_draft.Kind is Pen or Highlight) …
```

На отпускании: смещение короче `GestureThreshold` → `NoteOffset = null` (клик без движения, бейдж на точке, кадр 1). Точка — там, где нажали, и она уже прошла `ClampToImage` в `BeginGesture`.

### 3.3 Пилюля: наведение, двойной клик, Esc

- Наведение над бейджем — раскрывает пилюлю. Сигнал уже есть: `UpdateCursor` знает, что под курсором булавка (`:417`); нужен обратный вызов в окно, которое держит `_expandedChipId` (`xaml.cs:61`) и разворачивает чип через `_chipExpanders` (`Comments.cs`, `ActivateCommentRow`).
- Двойной клик — `PressTarget.Activate` (§2.2) → `AnnotationActivated` → `xaml.cs:1275-1277`, для `Comment` разворачивает пилюлю. Уже работает, после §2.2 срабатывает с любым инструментом.
- Esc — добавить шаг в `NextEscapeStep` (`Appearance.cs:602-608`): `Popover → ExpandedNote → Comment → Selection → Capture`. Сейчас развёрнутая пилюля не в списке, и Esc над ней снимает выделение.
- Клик мимо — `_outsideClickConsumed` (`xaml.cs:997`) уже гасит первый клик при развёрнутой пилюле, менять не надо.

### 3.4 Экспорт с полем

Сегодня холст экспорта — ровно `image.PixelWidth × (image.PixelHeight + HeaderHeight)` (`WpfExportImageRenderer.cs:28-43`), а бейдж дополнительно прижимается к низу заголовка (`NoteBadgeGeometry.Export(..., HeaderHeight + 2)`, `:181`). Вынесенный за снимок бейдж срезается.

Чистая функция рядом с `NoteBadgeGeometry` (`Imaging/NoteBadgeGeometry.cs`):

```csharp
internal readonly record struct ExportMargin(int Left, int Top, int Right, int Bottom)
{
    internal static readonly ExportMargin None = default;
    internal bool IsEmpty => Left == 0 && Top == 0 && Right == 0 && Bottom == 0;
}

/// <summary>Поле вокруг снимка, чтобы поместились вынесенные бейджи. Минимум 0 с каждой стороны.</summary>
internal static ExportMargin ExportMargins(
    IEnumerable<(NormalizedPoint Anchor, NormalizedPoint? Offset, string Label)> badges,
    int width, int height);
```

Считает: центр бейджа `= (Anchor.X * width + (Offset?.X ?? 0) * width, Anchor.Y * height + (Offset?.Y ?? 0) * height)`, радиус — `ExportDiameter(Label) / 2` (`NoteBadgeGeometry.cs:35`), к каждой стороне `Padding = 8`. `Left = max(0, ceil(-min(центр.X - r - 8)))`, `Right = max(0, ceil(max(центр.X + r + 8) - width))`, `Top`/`Bottom` так же по вертикали, **в координатах снимка**, без `HeaderHeight`. Комментарии без номера (`Label` пуст, то есть без текста заметки) в расчёт не входят — у них нет бейджа в экспорте (`WpfExportImageRenderer.cs:145`).

Рендер: холст `HeaderHeight + Top + height + Bottom` на `Left + width + Right`; заголовок белый во всю новую ширину (`:28`); поле залито `#2A3140` — одним прямоугольником под всё, поверх него заголовок и снимок; снимок в `new Rect(Left, HeaderHeight + Top, width, height)`; каждый `P(…)` получает те же сдвиги, то есть `offsetX = Left`, `offsetY = HeaderHeight + Top` вместо нынешнего `offsetY = HeaderHeight`. `HeaderHeight = 48` не трогаем. Кламп `HeaderHeight + 2` в `ExportBadge` (`:181`) **снимается**: он существовал только чтобы бейдж не влез в заголовок, а теперь между заголовком и снимком есть поле, куда бейджу и положено уйти. Без вынесенных бейджей `ExportMargins` даёт `None`, и картинка байт в байт как сегодня.

Один рендерер обслуживает и «в чат», и сохранение пакета (`src/Snapik.Infrastructure/Exporting/FileExportService.cs:55`), отдельной ветки для чата нет и заводить не надо.

Тесты `ExportMargins`: пустой список → `None`; бейдж без `Offset` → `None`; бейдж внутри снимка → `None`; `Offset.X = -0.1` при `width = 1000` → `Left = 100 + r + 8`, остальные 0; `Offset.X = +0.1` у якоря справа → только `Right`; отрицательный `Offset.Y` → только `Top`; два бейджа в разные стороны → оба поля; бейдж без номера не влияет; длинная подпись даёт больший радиус, чем короткая (через `ExportDiameter`).

### 3.5 Снятие привязки

Удаляются: `MoveLinkedComments` (`Comments.cs:179-197`), её вызов в `OnAnnotationChanged` (`xaml.cs:1576`), поле `_commentParentId` (`xaml.cs:60`), присвоение при создании (`xaml.cs:1245-1246`) и запоминание родителя в `OnCommentClick` (`xaml.cs:1763`). Комментарий становится самостоятельным объектом и при переносе рамки не двигается.

**Изменение формата.** Поле `ParentAnnotationId` (`src/Snapik.Core/Models/AnnotationItem.cs:57`, `EditorModels.cs:47`) **остаётся и продолжает читаться**, но этой сборкой больше не пишется — тот же приём, что у `LegacyHasOutline` (`:73-79`). Сессия 1.5.0, открытая заново, сохраняет подпись «К отметке A2» в панели комментариев (`Comments.cs:73-82`) и пометку «(к области A2)» в `prompt.md` (`PromptGenerator.cs:53-58`); у новых комментариев подпись всегда «К снимку A». `SchemaVersion` не меняется, ключ `parentAnnotationId` из старых файлов читается как раньше, в новых файлах его просто нет. Очистку повисшей ссылки при обрезке (`src/Snapik.Core/Editing/CaptureCropper.cs:75-76`) и валидацию оставить: они защищают чужой файл. Проба `xaml.cs:875`, которая проверяет `comment.ParentAnnotationId == workingAnnotation.Id`, снимается.

### 3.6 Что не должно сломаться

Нумерация (`CaptureLabels.ForNotedAnnotations`) — бейджи считаются по порядку отметок с заметкой и от привязки не зависели; номера акцентом (`AccentPalette.Brush`, `:701`, `:147`) — правило 7 ТЗ, не трогаем. Обрезка переносит `NoteOffset` в долях новой рамки (`CaptureCropper.cs:81-85`) — после снятия клампа смещение может стать больше единицы, это допустимо, `SessionValidation.cs:73` проверяет не диапазон, а наличие. `Resize.cs:174` пересчитывает `NoteOffset` при смене размера снимка — остаётся. Экспорт без комментариев — проверяется существующим `VerifyCaptionIsTheSameSizeOnScreenAndInExport` (`SmokeTestRunner.cs:664`), размеры PNG там сравниваются, тест поймает случайный сдвиг.

Smoke: `RunNoteAffordanceProbe` (`xaml.cs:808`) дополняется вынесенным за границу бейджем, и в `SmokeTestRunner.cs:471-477` пиксель бейджа берётся уже с учётом `ExportMargins` — сейчас координата считается от `48` напрямую (`:473`).

---

## 4. Границы, фундамент, риски

### 4.1 Файлы

**Моя зона (C2) целиком:** `ToolAppearance.cs` (новый), `OverlayEditorWindow.Appearance.cs`, `OverlayEditorWindow.Comments.cs`, `Controls/AnnotationCanvas.cs`, `Imaging/NoteBadgeGeometry.cs`, `WpfExportImageRenderer.cs`.

**`OverlayEditorWindow.xaml` — делится с аналитиком C1 по именам элементов.** Моё: `PropertiesBlock` и всё внутри него, `AppearancePopup`, `ThicknessPopup`, `FillPopup`, `FontSizePopup` (и удаление `LineStylePopup`). C1: `Toolbar` и его строки, разделители, `SelectTool`…`CropTool`, `CommentToolButton`, `ShapeMenuButton`/`ArrowMenuButton`/`PenMenuButton`, `UndoButton`/`RedoButton`/`SaveImageButton`/`DoneButton`, `ShortcutSheetPopup`, `ScaleSwitch`.

**`OverlayEditorWindow.xaml.cs` — делится с C1.** Моё: `:45-58` (активные поля), `:82-87`, `:1087-1093`, `:1214-1280` (`SelectToolMode`, `OnAnnotationCreated`, `OnSelectionChanged`, `OnAnnotationActivated`), `:1341-1362` (перетаскивание пилюли), `:270-460` (`RunPanelProbe`/`PanelChecks` и новая проба памяти). C1: `PositionToolbar`, `LayoutWorkArea`, `RepositionChips` в части укладки.

**Общее с другими:** `UiLanguage.cs` — только дописывание строк в `English`, существующие не трогаю. `SmokeTestRunner.cs` — только добавление вызовов около `:435-477`. `EditorModels.cs` — новых полей не завожу, но `Text.cs` и `Shapes.cs` читаются на предмет `ActiveFontSize`/`ActiveShape`. Core: `AnnotationItem.cs`, `SessionValidation.cs`, `CaptureCropper.cs`, `PromptGenerator.cs`, `ExportContracts.cs` — **не меняются**, только читаются. `HotkeySettingsWindow.xaml.cs` — новый ключ `ToolAppearance` в записи и `AppearanceTab.SelectedPalette` (`:359`, `:537`), если «неон» возвращается.

### 4.2 Что в общий фундамент (волна 0)

1. `ToolAppearance` + `ToolAppearanceStore.Read/Write` + новый ключ `settings.json` + тесты §1.11 (3-5). На них стоит и панель C2, и, отдельным заходом, порт на macOS.
2. `InspectorView` / `InspectorViewOf` / `InspectedTool` + тесты §1.11 (1-2) — их имена зовёт разметка C1 при сборке блока.
3. `OutlineColorOf(AnnotationFill, Color)` — меняется сигнатура из контракта волны 0 ТЗ №4, затрагивает два рендерера, поэтому правится один раз и до всего остального.
4. `ExportMargin` / `ExportMargins` + тесты §3.4 — читает экспорт, читает smoke, читает порт.
5. `PressTargetOf` — до правок `BeginGesture`, чтобы smoke C4 писался против функции, а не против канвы.

Изменений в `AnnotationItem` (ни в App-, ни в Core-версии) не требуется: все нужные поля уже раздельны.

### 4.3 Риски

- **Рисовать поверх объектов станет нельзя** (§2.6). Самый заметный сдвиг привычки; проверять на живой приёмке отдельным шагом «нарисовать стрелку поверх залитой рамки» и решить, достаточно ли «Выбора» + перетаскивания.
- **Старые снимки перекрасятся**: залитая рамка 1.5.0 сменит цвет обводки с цвета заливки на цвет отметки (§1.6). Формат цел, картинка другая.
- **Три источника правды по цвету** на время перехода: `_tools`, `Surface.Active*` и `AnnotationItem`. Синхронизация только через `SyncAppearance`/`ApplyAppearance`; любое место, которое пишет `Surface.Active*` мимо них (`xaml.cs:1087-1093`), обязано читать `_tools[Surface.Tool]`.
- **Экспортное поле ломает координаты** у всех, кто считает от `HeaderHeight` напрямую: `SmokeTestRunner.cs:473`, `ExportBadge`, будущие пробы. Ввести одно свойство «где начинается снимок в экспорте» и считать от него.
- **Кламп точки против отсутствия клампа бейджа** легко перепутать: в `UpdateGesture` четыре места с `ClampToImage` (`:342`, `:346`, `:354`, `:385`), и только два первых остаются для комментария.
- **Палитра «неон»** не решена (§1.7); четвёртый сегмент меняет ширину поповера, а это уже касается укладки C1.

### 4.4 Перенос на macOS

Порт только что получил модель «одним цветом» (D1) — её придётся откатывать в ту же сторону, что и Windows:

- `macos/Sources/SnapikMac/Editor/EditorAppearanceModel.swift:127-135` — `outlineColor(fill:color:fillColor:)` теряет `fillColor` ровно как §1.6; вызов `AnnotationCanvasView+Drawing.swift:113-117` и экспортный рендерер правятся вместе.
- `EditorAppearanceModel.swift` — завести словарь `[EditorTool: ToolAppearance]`, зеркало §1.2, и чтение/запись того же ключа `toolAppearance` в общем `settings.json` (файл общий, формат обязан совпасть до буквы, включая camelCase имён инструментов и `null` как «цвет заливки = обводка»).
- `EditorToolbarView.swift` — две капсулы вместо кнопок, таблица `InspectorViewOf` дословно; `EditorPopovers.swift:439-550` — поповер заливки уже отдельный, поповер обводки принимает толщину и стиль.
- `AnnotationCanvasView.swift:31-354` — `activeColor`/`activeFillColor` заменяются чтением из словаря по инструменту; порядок нажатия §2.2.
- Комментарии: перетаскивание бейджа без клампа, постановка жестом, поле экспорта `#2A3140` и та же `ExportMargins`; снятие привязки и правило «`parentAnnotationId` читаем, не пишем» (`EditorModels.swift:235-237` уже держит похожий приём для старой рамки).
- `macos/SYNC.md` пополняется строкой про новый ключ настроек: файл один на две платформы, и сборка, которая ключ не знает, обязана продолжать читать старые общие ключи.
