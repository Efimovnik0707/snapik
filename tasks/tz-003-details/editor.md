# План по ТЗ №3: пункты 1, 2, 5, 6 (редактор разметки)

Зона: `src/SnapBrief.App/OverlayEditorWindow.xaml(.cs)` и партиалы `OverlayEditorWindow.*.cs`, `Controls/AnnotationCanvas.cs`, `EditorModels.cs`, `EditorShortcuts.cs`, `WpfExportImageRenderer.cs`, `UiLanguage.cs`, `SmokeTestRunner.cs`, модели в `SnapBrief.Core`. Пункты 3 (лента) и 4 (мастер) не мои.

Код сверялся с HEAD `8868c28` (1.3.0), все ссылки file:line по нему. Незакоммиченные чужие файлы (`site/`, `.impeccable/`, `DESIGN.md`, `SESSION_LOG.md`) и `macos/` не трогались. Правила прежние: строки UI только через `UiLanguage.cs`, изменение формата получает абзац в `tasks/verification.md`, один коммит на законченную правку, проверка через `scripts/build.ps1`.

---

## 1. Что показал разбор кода

### П.1. Клик вне снимка: это прямой откат строки из C2

До ТЗ №2 обработчик отпускания кнопки в окне завершал съёмку: `git show a9381e6:src/SnapBrief.App/OverlayEditorWindow.xaml.cs` строки 390-394, ветка `if (_capture is not null && e.OriginalSource is Image && !_busyCrop && !_cropRect.Contains(...)) { e.Handled = true; Complete(false); }`.

Коммит `02b7ea1` (C2) заменил `Complete(false)` на `ClosePopovers(); Surface.SelectAnnotation(null);`, это сегодняшние `OverlayEditorWindow.xaml.cs:645-653`. В самом плане ТЗ №2 это стояло единственным блокирующим вопросом («Клик мимо снимка перестаёт завершать съёмку», `tasks/tz-002-details/C-editor.md`, раздел 7), решение приняли по умолчанию, Никита его отменил.

Важно, что два правила не конфликтуют и никогда не конфликтовали: они живут в разных обработчиках.

- Клик по пустому месту ВНУТРИ снимка обрабатывает холст: `AnnotationCanvas.BeginGesture` при инструменте «Выбор» делает `Select(null)` (`AnnotationCanvas.cs:199-218`), при рисующем инструменте тоже `Select(null)` и заводит черновик (`:220-239`), который умирает в `GestureHasSize` (`:623-637`), если рука не проехала 4 экранных пикселя. Ни одна строка этого не зависит от оконного обработчика.
- Клик ВНЕ снимка вообще не доходит до холста: `Shade` имеет `IsHitTestVisible="False"` (`xaml:136`), `EditorLayer` это `Canvas` без фона, поэтому `e.OriginalSource` там всегда `DesktopImage` (`xaml:135`), и условие `e.OriginalSource is Image` отделяет «мимо снимка» точно.

То есть возврат `Complete(false)` восстанавливает привычку, ничего не ломая. Два побочных случая надо закрыть явно:

1. Открытый поповер (`AppearancePopup`, `ThicknessPopup`, `ShortcutSheetPopup`) стоит на `StaysOpen="False"`, он сам перехватывает клик мимо себя и закрывается, окно этого клика не видит. Значит первый клик закрывает поповер, второй завершает съёмку, и это правильно.
2. Открытая пилюля комментария и (после пункта 6) открытое поле ввода текста завершаются на MouseDown в `OnWindowMouseDown` (`:622-631`, `FinishExpandedChipIfOutside` в `OverlayEditorWindow.Comments.cs:122-126`). Если не подавить последующий MouseUp, один клик сделает два действия сразу: закончит ввод и свернёт редактор. Нужен флаг «этот клик уже потрачен».

Одиночный клик текста и комментария не ломается: они ставятся внутри снимка, до оконного обработчика дело не доходит, `GestureHasSize` для них возвращает `true` безусловно (`AnnotationCanvas.cs:626`).

### П.2. Заливка не пропала, она спрятана за безымянным кружком и выключена почти всегда

Заливка на месте, в поповере цвета: `xaml:276-297`, секция «Заливка» с четырьмя сегментами (`FillNoneSegment`, `FillSolidSegment`, `FillTranslucentSegment`, `FillBlurSegment`) и кружком «Цвет заливки» (`FillColorButton`, `xaml:279-281`). Причин, почему Никита её не нашёл, три, и все они следствие C5/C6:

1. **Вход безымянный.** Поповер открывает `AppearanceButton` (`xaml:218-220`), это кружок 36×36 с эллипсом внутри и подписью только в тултипе «Цвет и заливка». Раньше заливка жила строкой в меню «•••», где у неё была подпись. Меню убрали в C6, подпись исчезла вместе с ним.
2. **Заголовок поповера врёт.** Первая строка поповера это «Цвет» (`xaml:251`), а заливка лежит ниже двенадцати образцов палитры, поля HEX и секции «Рамка», то есть примерно на 330 px ниже начала. Это ниже сгиба на любой мысленной прокрутке глазом.
3. **Она выключена для всего, кроме «Области».** `HasFill(tool) => tool == EditorTool.Rectangle` (`OverlayEditorWindow.Appearance.cs:28`), и `SyncAppearance` гасит `FillRow`, `FillColorButton`, `OutlineRow` (`Appearance.cs:169, 191, 197`). Если в руке стрелка, карандаш или блюр, секция серая. Проверка Никиты шла после C2, где нажим любым рисующим инструментом снимает выделение (`AnnotationCanvas.cs:222`), так что состояние «нарисовал рамку, кликнул мимо, открыл цвет» даёт выключенную секцию, если в руке был не тот инструмент.

Вывод: чинить надо подачу, а не логику. Логика (`ApplyAppearance` с `fill`/`fillColor`, `Appearance.cs:209-211`, отрисовка `AnnotationCanvas.ShapeFillBrush` и `DrawBoxShape`, `:601-616`, экспорт `WpfExportImageRenderer.cs:119-123`) работает, её трогать не нужно.

Вёрстка панели, под которую надо вписаться: капсулы `OverlayButton` высотой 36, скругление 9, `Margin 2,0`; фиксированная ширина там, где подпись меняется (`ThicknessButton`, `Width="64"`, `xaml:223`, это правило из C1, его проверяет smoke на неизменную ширину панели, `OverlayEditorWindow.xaml.cs:366-380`); поповер это `Border` с `Padding 18`, фоном `#171A20`, рамкой `#394352`, скруглением 14, внутри строки сегментов в `Border Background="#222933" CornerRadius="8" Padding="3"` со стилем `SegmentButton` (`xaml:88-107`).

### П.5. Перо и маркер похожи, потому что полупрозрачный штрих рисуется по отрезку за раз

Маркер уже рисуется шире и прозрачнее пера: `AnnotationCanvas.cs:512-519` даёт `opacity = 0.35` и ширину `thickness * 4`, экспорт даёт альфу 90 и ту же ширину `Thickness * 4` (`WpfExportImageRenderer.cs:102-111`). Но оба рендерера рисуют штрих **отрезками в цикле**: `for (var i = 1; i < segment.Count; i++) dc.DrawLine(pathPen, ...)`. Точки в штрихе кладутся на каждое движение мыши (`AnnotationCanvas.cs:285-288`), то есть плотно, и каждый круглый торец отрезка ложится поверх соседнего. Полупрозрачная краска при таком наложении копится: альфа 0.35, наложенная четыре-пять раз, даёт почти непрозрачную линию. Поэтому маркер на экране и в экспорте выглядит как чуть более широкое перо с рваными краями, ровно как описал Никита.

Остальные отличия маркера от пера сегодня отсутствуют: те же круглые торцы и стыки (`StartLineCap/EndLineCap = Round`, `LineJoin = Round`), та же толщина (`_activeThickness` одна на всё, `OverlayEditorWindow.xaml.cs:47`, `HasStroke` пускает на неё и перо и маркер, `Appearance.cs:24`), та же иконка по смыслу: `PenGlyph` это `M2,14 C5,12 5,8 8,7 M8,7 L13,2 L15,4 L10,9 Z` (`xaml:14`), наклонённый клин, который читается как лезвие, и `HighlightGlyph` это тоже наклонённый четырёхугольник (`xaml:15`).

Общая кнопка «Толщина» на перо действует уже сейчас (`HasStroke(Pen) == true`, значение уезжает в `Surface.ActiveThickness` и в модель, `Appearance.cs:207`), проверять нечего, ломать нечего. Отдельная толщина нужна только маркеру.

Название: `EditorShortcuts.cs:25` держит `new(EditorTool.Pen, Key.P, "Перо")`, а `UiLanguage.cs:31` держит `["Перо"] = "Pen"`. Ключ «Карандаш» в таблице уже есть (`UiLanguage.cs:35`, он используется тултипом шеврона `PenMenuButton`, `xaml:202`).

### П.6. Текст не редактируется, потому что его редактор это пилюля комментария, и она теряется с первого же клика

Как ставится текст сегодня. Одиночный клик по снимку создаёт `AnnotationItem { Kind = Text, Points = [p, p] }` (`AnnotationCanvas.cs:223-238`), `GestureHasSize` пропускает его без размера (`:626`), `EndGesture` добавляет и выделяет (`:348-359`), окно ловит `AnnotationCreated` и открывает **пилюлю комментария** (`OverlayEditorWindow.xaml.cs:857-861` → `AddChip(annotation, focus: true)`). Никакого поля на холсте нет: текст правится в `TextBox` внутри пилюли (`:1008-1017`), которая стоит под отметкой и имеет ширину 270.

Почему это разваливается:

1. **Прямоугольник отметки нулевой.** `BoundsOf` берёт минимум и максимум по `Points` (`AnnotationCanvas.cs:723-730`), а у текста обе точки совпадают. Хит-тест раздувает эту точку на `max(8, Thickness * 2)` (`:489-499`), то есть даёт квадрат 16×16 вокруг якоря, тогда как сами буквы уходят вправо и вниз на десятки пикселей. Двойной клик по слову «Текст» в эту рамку не попадает и уходит в ветку рисования: ставится **новая** отметка «Текст». Это буквально симптом из ТЗ.
2. **Пилюля закрывается от чего угодно.** `Finish()` для текста прячет её совсем (`:1053`, `border.Visibility = Collapsed`), а вызывается она при уходе мыши без фокуса клавиатуры (`:1093`), при потере фокуса полем (`:1117`) и при любом нажатии мыши в окне мимо `ChipLayer` (`:624` → `Comments.cs:122-126`). Первый же клик по снимку убирает единственный вход в правку.
3. **После переоткрытия снимка пилюли у текста нет вовсе.** `RebuildChips` создаёт пилюли только для отметок с непустым `Note` (`:996`), а у текста заполнено `Text`, не `Note`. Значит текст, приехавший из `session.json`, правится только двойным кликом, который по пункту 1 не попадает.
4. **Размер шрифта не хранится и на экране не тот, что в экспорте.** Холст рисует `Math.Max(14, 18 * scale)` (`AnnotationCanvas.cs:538-541`), экспорт рисует `Math.Max(16, item.Thickness * 4.5)` (`WpfExportImageRenderer.cs:125`). В модели (`EditorModels.cs:34-96` и `SnapBrief.Core/Models/AnnotationItem.cs:37-44`) поля размера нет. То есть даже если печатать получится, надпись на экране и в PNG будет разного кегля, а выбирать размер нечем.
5. Смок-проверка на текст не ловит ничего из этого, потому что зовёт `OnAnnotationCreated` напрямую с готовым прямоугольником `[(100,100),(220,160)]` (`OverlayEditorWindow.xaml.cs:582-590`), минуя и жест, и хит-тест.

Клавиатура при этом не мешает: `OnWindowKeyDown` отдаёт все клавиши сфокусированному `TextBox` (`:1414-1418`), так что новое поле ввода на холсте будет печатать сразу.

---

## 2. Решения по пунктам

| # | Решение | Размер |
|---|---|---|
| 1 | Вернуть `Complete(false)` в ветку «клик мимо снимка» `OnWindowMouseUp`, добавить флаг `_outsideClickConsumed`: если тот же клик на MouseDown уже закрыл пилюлю или поле ввода текста, MouseUp съедает себя и редактор не сворачивается. Правила внутри снимка не трогаются вовсе | S |
| 2 | Своя кнопка «Заливка» на панели рядом с «Толщина», фиксированной ширины, с превью текущей заливки; свой поповер `FillPopup` с заголовком «Заливка», четырьмя сегментами (Контур / Сплошная / Полупрозрачная / Размытие) и рядом из двенадцати образцов цвета заливки. Секция «Заливка» уходит из поповера цвета. Кнопка видна всегда; если в руке инструмент без заливки и ничего не выделено, клик по ней сперва вооружает «Область» (так же, как это делает меню фигуры, `Shapes.cs:64`) | M |
| 5 | Перо становится «Карандаш» / «Pencil» (строка, тултип, шпаргалка, меню капсулы), иконка меняется на настоящий карандаш; штрих пера и маркера рисуется одной геометрией вместо цикла отрезков, маркер получает `PushOpacity(0.4)`, квадратные торцы и стыки и свою толщину (`_activeHighlightThickness`, настройка `annotationHighlightThickness`, пресеты 8/12/16/24, ползунок 4..48). Общая кнопка «Толщина» показывает толщину того, что в руке | M |
| 6 | Текст правится инлайновым `TextBox` поверх холста в точке клика: слово «Текст» выделено целиком, Enter завершает, Shift+Enter переносит строку, Esc отменяет (пустой текст удаляет отметку), клик вне поля завершает, двойной клик по надписи открывает правку снова. Прямоугольник текстовой отметки считается по реальным метрикам надписи, поэтому хит-тест, перенос, ластик и выделение начинают по ней работать. Размер шрифта уезжает в модель (`FontSize`), своя кнопка «Размер» на панели в стиле «Толщина» с пресетами 12/16/20/24/32/48 и ползунком, значение помнится в `annotationFontSize`. Пилюля перестаёт быть редактором текста, текст получает обычную заметку, как рамка | L |

### Детали, без которых executor будет гадать

**П.1.** Точный вид ветки после правки (`OverlayEditorWindow.xaml.cs:641-655`):

```csharp
if (_selectionStart is null)
{
    var consumed = _outsideClickConsumed;
    _outsideClickConsumed = false;
    // Клик мимо снимка снова заканчивает разметку. Клик по пустому месту внутри снимка
    // снимает выделение, это делает холст, и сюда он не доходит.
    if (_capture is not null && e.OriginalSource is Image && !_busyCrop && !_cropRect.Contains(e.GetPosition(this)))
    {
        e.Handled = true;
        if (!consumed) { ClosePopovers(); Complete(false); }
    }
    return;
}
```

Флаг ставится в `OnWindowMouseDown` (`:622-631`) до всего остального:

```csharp
var outside = !IsInsideChipLayer(e.OriginalSource as DependencyObject);
_outsideClickConsumed = outside && (_expandedChipId is not null || _editingText is not null);
CommitTextEditIfOutside(e.OriginalSource as DependencyObject);
FinishExpandedChipIfOutside(e.OriginalSource as DependencyObject);
```

`Complete` уже защищён от съёмки посреди жеста: `_busyCrop`, `_captureResizeCorner >= 0`, `Surface.IsMouseCaptured` (`:1401-1403`). Перетаскивание, начатое внутри снимка и отпущенное снаружи, до окна не доходит, потому что мышь захвачена холстом.

**П.2.** Кнопка:

```xml
<Button x:Name="FillButton" Width="96" MinWidth="96" Padding="0" HorizontalContentAlignment="Center"
        Style="{StaticResource OverlayButton}" Click="OnFillButtonClick"
        ToolTip="Заливка" AutomationProperties.Name="{local:UiText Заливка}">
    <StackPanel Orientation="Horizontal">
        <Rectangle x:Name="FillButtonPreview" Width="20" Height="14" RadiusX="2" RadiusY="2"
                   Stroke="#D9DEE8" StrokeThickness="1.5" Margin="0,0,7,0" />
        <TextBlock Text="Заливка" />
    </StackPanel>
</Button>
```

Ширина фиксирована, содержимое никогда не пустеет, значит проверка «панель не меняет ширину от инструмента» (`OverlayEditorWindow.xaml.cs:366-380`) остаётся зелёной. `TextBlock` внутри переводится обычным обходом `UiLanguage.Apply` (`UiLanguage.cs:138`), отдельной логики не нужно. Стоит кнопка сразу после `ThicknessButton` (`xaml:223`).

`FillPopup` копирует раскладку `ThicknessPopup` (`xaml:310-334`): `Width="252"`, заголовок «Заливка» + текущее значение справа, строка из четырёх сегментов (переносится один в один из `xaml:282-296`, имена элементов и обработчик `OnFillClick` сохраняются, поэтому `SyncAppearance` не переписывается), под ней `WrapPanel x:Name="FillPalette"`, который строит новый `BuildFillPalette()` по образцу `BuildColorPalette` (`Appearance.cs:89-102`), только клик зовёт `ApplyAppearance(null, null, fillColor: color)` напрямую.

Из поповера цвета уходит вся секция «Заливка» (`xaml:276-297`). Вместе с ней уходит смысл `_colorTarget`: остаётся один приёмник, рамка. Значит `ColorTarget`, `_colorTarget`, `OnOutlineTargetClick`, `OnFillTargetClick`, кнопки `OutlineColorButton` и `FillColorButton` удаляются, `ApplyPickedColor` сводится к `ApplyAppearance(color, null)` (`Appearance.cs:49-51, 229-233, 256-257`). `MainTarget` и `ApplyQuickColor` **остаются**: пять точек на панели по-прежнему красят то, что видно, то есть заливку у рамки без контура (`Appearance.cs:55-64, 235-239`), это поведение из C5 и оно правильное. В `SyncAppearance` строки про `OutlineColorButton`/`FillColorButton`/`_colorTarget` (`:146, 153, 163-164, 173-175, 197`) заменяются на подсветку выбранного образца в `FillPalette` и на `FillButtonPreview`.

Состояние кнопки:

```csharp
private void OnFillButtonClick(object sender, RoutedEventArgs e)
{
    if (_capture is null) return;
    // Заливка принадлежит области: если в руке другой инструмент и ничего не выделено,
    // кнопка вооружает область, как это делает меню фигуры.
    if (Surface.SelectedAnnotation is null && !HasFill(Surface.Tool)) SelectToolMode(EditorTool.Rectangle);
    OpenFill();
}
```

`FillButton.IsEnabled = Surface.SelectedAnnotation is null || HasFill(Surface.SelectedAnnotation.Kind)`, то есть кнопка гаснет только когда выделена отметка без заливки. `FillButtonPreview` показывает текущий режим: без заливки контур и прозрачная середина, `Solid` сплошная заливка цветом заливки, `Translucent` тот же цвет с альфой 0x59, `Blur` градиент из `xaml:293-296`.

**П.5.** Геометрия иконки карандаша (наклон 45 градусов, остриё влево-вниз, воротник и обжимка, поле 16×16):

```xml
<PathGeometry x:Key="PencilGlyph" Figures="M2.5,13.5 L3.5,10.3 L9.5,4.2 L11.8,6.5 L5.8,12.5 Z M3.5,10.3 L5.8,12.5 M8.5,5.3 L10.7,7.6" />
```

Ключ `PenGlyph` переименовывается в `PencilGlyph` в трёх местах: `xaml:14`, `xaml:200` (`Data="{StaticResource PenGlyph}"`), `SetPencilMode` (`OverlayEditorWindow.xaml.cs:896`). `HighlightGlyph` остаётся как есть: рядом с настоящим карандашом наклонный чекан читается как маркер.

Отрисовка штриха, общая часть для обоих рендереров. Вместо цикла `DrawLine` собирается одна `StreamGeometry` на сегмент и рисуется один раз:

```csharp
internal static Geometry StrokeGeometry(IEnumerable<IReadOnlyList<Point>> segments, Func<Point, Point> map)
{
    var geometry = new StreamGeometry();
    using (var ctx = geometry.Open())
        foreach (var segment in segments.Where(s => s.Count > 1))
        {
            ctx.BeginFigure(map(segment[0]), false, false);
            ctx.PolyLineTo(segment.Skip(1).Select(map).ToArray(), true, false);
        }
    geometry.Freeze();
    return geometry;
}
```

Маркер рисуется так:

```csharp
var pathPen = new Pen(brush, width)
{
    StartLineCap = PenLineCap.Square, EndLineCap = PenLineCap.Square, LineJoin = PenLineJoin.Bevel
};
dc.PushOpacity(HighlightOpacity);   // 0.4
dc.DrawGeometry(null, pathPen, StrokeGeometry(...));
dc.Pop();
```

`PushOpacity` вокруг одной геометрии обязателен: это единственный способ получить ровную прозрачность, альфа в кисти на самопересечениях штриха всё равно копится. Карандаш рисуется той же геометрией, но непрозрачной кистью и круглыми торцами. Константы `HighlightOpacity = 0.4` и сама `StrokeGeometry` живут в `AnnotationCanvas` как `internal static`, `WpfExportImageRenderer` берёт их оттуда, как уже берёт `DrawBoxShape` и `ShapeFillBrush` (`WpfExportImageRenderer.cs:121-122`).

Множитель `* 4` для маркера из обоих рендереров **убирается**: `Thickness` у маркера начинает значить реальную ширину штриха. Это можно себе позволить, потому что сессия живёт один запуск и удаляется на выходе (`5531c42`, `SessionWorkspace.cs:79-98`), старых файлов с маркером в природе не остаётся. Абзац в `verification.md` всё равно нужен.

Своя толщина маркера:

- поле `_activeHighlightThickness` рядом с `_activeThickness` (`OverlayEditorWindow.xaml.cs:47`), читается из `preferences.AnnotationHighlightThickness` (`:71`), пишется в `SaveAppearanceDefaults` (`Appearance.cs:352-362`);
- `ActiveThicknessFor(tool)` и `SetActiveThickness(tool, value)` в `Appearance.cs`, всё, что сейчас читает и пишет `_activeThickness` (`:140, 152, 207`), идёт через них;
- пресеты и диапазон ползунка тоже от инструмента: `ThicknessPresetsFor(tool)` возвращает `[2,4,6,8]` или `[8,12,16,24]`, `StrokeSlider.Minimum/Maximum` в `SyncAppearance` ставятся в 1..16 или 4..48. Четыре сегмента `ThicknessPresetRow` (`xaml:315-329`) перепрограммируются в `SyncAppearance`: `Tag`, `ToolTip`, `AutomationProperties.Name` и высота прямоугольника внутри (`Height = Math.Min(20, value)`, иначе 24 px не влезут в сегмент высотой 30);
- `IsMoveHandle` для пера и маркера (`AnnotationCanvas.cs:663-670`) теряет особый случай `band * 2` и считает полосу захвата как `Math.Max(6, item.Thickness * scale / 2 + 4)` для обоих.

Переименование: `EditorShortcuts.cs:25` становится `new(EditorTool.Pen, Key.P, "Карандаш")`, из `UiLanguage.cs:31` удаляется пара `["Перо"] = "Pen"` (иначе в таблице повиснет мёртвый ключ, а проверка на дубли значений его не прощает при добавлении нового). Клавиша `P` не меняется, `EditorTool.Pen` как имя элемента перечисления не меняется (это внутреннее имя, оно едет в `session.json` как `freehand`, `EditorModels.cs:105`).

**П.6.** Три части: метрики, поле ввода, размер шрифта.

*Метрики.* Новый файл `src/SnapBrief.App/TextMarkMetrics.cs`:

```csharp
internal static class TextMarkMetrics
{
    internal const string FamilyName = "Segoe UI Variable Text";

    internal static Size Measure(string text, double fontSize)
    {
        var formatted = new FormattedText(string.IsNullOrEmpty(text) ? " " : text,
            CultureInfo.CurrentUICulture, FlowDirection.LeftToRight, new Typeface(FamilyName),
            fontSize, Brushes.Black, 1);
        return new Size(Math.Max(fontSize / 2, formatted.WidthIncludingTrailingWhitespace),
                        Math.Max(fontSize, formatted.Height));
    }

    // Вторая точка текстовой отметки это не то, что провела рука, а то, что занимают буквы.
    internal static void Fit(AnnotationItem item)
    {
        if (item.Kind != EditorTool.Text || item.Points.Count == 0) return;
        var size = Measure(item.Text, item.FontSize);
        var anchor = item.Points[0];
        if (item.Points.Count < 2) item.Points.Add(anchor);
        item.Points[1] = new Point(anchor.X + size.Width, anchor.Y + size.Height);
    }
}
```

Измеряется в пикселях изображения с `pixelsPerDip = 1`, ровно как считает экспорт (`WpfExportImageRenderer.cs:173-175`). `Fit` вызывается при создании отметки, при каждом изменении текста, при смене размера шрифта и один раз по всем текстовым отметкам в `SetupEditor` (`OverlayEditorWindow.xaml.cs:722`), чтобы приехавший из сессии текст сразу имел рамку. После этого `BoundsOf`, `HitTestAnnotation`, `FindMoveHandle`, ластик и рамка выделения начинают работать по буквам, а не по точке, без единой правки в них.

`HasResizeHandles` (`AnnotationCanvas.cs:617`) исключает текст: `item.Kind is not (EditorTool.Comment or EditorTool.Text)`. Растягивать надпись углами нельзя, потому что растяжение меняет только `Points`, а кегль живёт отдельно; надпись двигают и правят, размер задаётся кнопкой.

*Поле ввода.* Новый партиал `src/SnapBrief.App/OverlayEditorWindow.Text.cs` и новый слой в разметке между `EditorLayer` и `ChipLayer`:

```xml
<Canvas x:Name="TextLayer" />
```

`TextBox _textEditor` создаётся в конструкторе (`InitializeTextEditor()` рядом с `InitializeNoteButton()`, `:92`), кладётся в `TextLayer`, живёт скрытым. Оформление: `Background="Transparent"`, `BorderThickness=0`, `Padding=0`, `CaretBrush` белый, `SelectionBrush` акцентная, `AcceptsReturn=true`, `TextWrapping=NoWrap`, `FontFamily = TextMarkMetrics.FamilyName`, `MinWidth=24`, ширина авто. Позиция и кегль пересчитываются от снимка: `scale = _cropRect.Width / _capture.Image.PixelWidth`, `FontSize = annotation.FontSize * scale`, `Canvas.SetLeft(_textEditor, _cropRect.Left + annotation.Points[0].X * scale)`, то же по вертикали. Поверх поля надпись самой отметки не рисуется: у холста появляется `public Guid? EditingTextId`, и `DrawAnnotation` пропускает `case EditorTool.Text` для этого идентификатора (`AnnotationCanvas.cs:538-542`), иначе текст двоится.

Жизненный цикл:

- `BeginTextEdit(annotation, selectAll, isNew)` запоминает `_editingText`, `_editingTextBefore = annotation.Text`, `_editingTextIsNew`, `_editingUndoDepth = _undo.Count`, показывает поле и через `Dispatcher.BeginInvoke(..., DispatcherPriority.Input)` делает `Focus()` и `SelectAll()` (или ставит каретку в конец, если `selectAll` ложно);
- `TextChanged` пишет `annotation.Text`, зовёт `TextMarkMetrics.Fit`, `Surface.InvalidateVisual()`;
- `PreviewKeyDown`: `Enter` без модификаторов завершает (`CommitTextEdit()`), `Shift+Enter` пропускается в `TextBox` и даёт перенос строки (это уже описано в шпаргалке, `EditorShortcuts.cs:44`), `Escape` отменяет (`CancelTextEdit()`). Все три помечают событие обработанным, чтобы `OnWindowKeyDown` не завершил съёмку по Enter (`:1421-1427`);
- `LostKeyboardFocus` завершает через `Dispatcher.BeginInvoke`, с защитой от повторного входа флагом `_closingTextEdit`;
- `CommitTextEdit()`: прячет поле, снимает `EditingTextId`, при пустом или пробельном тексте удаляет отметку и, если она была новой и в стопку с тех пор ничего не добавилось (`_undo.Count == _editingUndoDepth`), снимает запись истории, которую положил `OnAnnotationCreated` (`:854`); иначе `_lastSnapshot = SnapshotState()`, `RefreshLabels()`, `Surface.Focus()`;
- `CancelTextEdit()`: для новой отметки то же удаление, для существующей возвращает `_editingTextBefore` и зовёт `Fit`;
- `CommitTextEditIfOutside(source)` возвращает `true`, если поле было открыто и источник клика не оно (нужно для П.1).

Точки входа: `OnAnnotationCreated` для `Kind == Text` вместо `AddChip` зовёт `BeginTextEdit(annotation, selectAll: true, isNew: true)`; `OnAnnotationActivated` (двойной клик, `:875`) для текста зовёт `BeginTextEdit(annotation, selectAll: false, isNew: false)`, для остального остаётся `OpenAnnotationNote`.

Слово по умолчанию идёт через таблицу: `EditorModels.cs:37` меняет `private string _text = "Текст";` на `= string.Empty;`, а `AnnotationCanvas.BeginGesture` при создании черновика текста ставит `Text = UiLanguage.Text("Текст")` (`:224-238`). Иначе в английском интерфейсе вставится русское слово.

Пилюля перестаёт обслуживать текст: из `:857` уходит `EditorTool.Text`, из `AddChip` уходят все ветки `annotation.Kind == EditorTool.Text` (`:1008, 1015, 1029, 1053, 1063`), из `RefreshLabels` уходит значок `"T"` (`:1139`), из `DeleteAnnotationNote` уходит особый случай (`:1246`). Текстовая отметка после этого получает обычную заметку тем же способом, что рамка: выделить и нажать «+». Ключ `["Закрыть ввод текста"]` удаляется из `UiLanguage.cs:48` как осиротевший.

*Размер шрифта.* Кнопка и поповер повторяют «Толщина» один в один:

```xml
<Button x:Name="FontSizeButton" Width="64" MinWidth="64" Padding="0" HorizontalContentAlignment="Center"
        Style="{StaticResource OverlayButton}" Click="OnFontSizeClick"
        ToolTip="Размер" AutomationProperties.Name="{local:UiText Размер}" Content="20 px" />
```

`FontSizePopup` устроен как `ThicknessPopup` (`xaml:310-334`): заголовок «Размер», строка из шести сегментов 12/16/20/24/32/48 (`UniformGrid Columns="6"`, внутри каждого `TextBlock` с числом, а не полоска), ползунок 8..96 с шагом 1, внизу превью «Ag» тем же кеглем и цветом отметки. Кнопка активна, когда в руке текст или выделен текст (`HasFontSize(tool) => tool == EditorTool.Text`), подпись не пустеет никогда, ширина фиксирована, значит проверка ширины панели остаётся зелёной. Клик по пресету или сдвиг ползунка идут через `ApplyAppearance(..., fontSize: value)`, который пишет `_activeFontSize`, `Surface.ActiveFontSize` и выделенную отметку, после чего зовёт `TextMarkMetrics.Fit` и, если поле ввода открыто, пересчитывает его `FontSize`.

Модель: `SnapBrief.Core.Models.AnnotationItem` получает `public double FontSize { get; init; } = 20;` (`AnnotationItem.cs:54-64`, рядом с `Shape`/`Fill`), `EditorModels.AnnotationItem` получает `public double FontSize { get; set; } = 20;`, `Clone()` (`:82-96`), `ToCore` (`:98-126`) и `FromCore` (`:128-163`) его возят. `CaptureCropper` не трогается: он переносит поля через `annotation with { Points = ... }` (`CaptureCropper.cs:69`).

Отрисовка: холст рисует `item.FontSize * scale` (`AnnotationCanvas.cs:538-541`), экспорт рисует `item.FontSize` и тем же семейством `TextMarkMetrics.FamilyName` вместо `Segoe UI` (`WpfExportImageRenderer.cs:125, 171-176`). Начертание в обоих местах одинаковое, `Normal`, а не `SemiBold` как сейчас в экспорте. Цвет берётся из общего цвета отметки (`HasColor` уже пускает текст, `Appearance.cs:23`), отдельного выбора цвета текста не заводим.

---

## 3. Файлы по пунктам

| Пункт | Файлы |
|---|---|
| 1 | `OverlayEditorWindow.xaml.cs` (`:622-631`, `:641-655`, новое поле `_outsideClickConsumed`), `OverlayEditorWindow.Comments.cs` (`IsInsideChipLayer` становится доступным из П.6) |
| 2 | `OverlayEditorWindow.xaml` (`:218-223` панель, `:249-308` поповер цвета, новый `FillPopup`), `OverlayEditorWindow.Appearance.cs` (`:49-64`, `:89-102`, `:128-199`, `:229-257`), `UiLanguage.cs`, `SmokeTestRunner.cs` / `RunShortcutHintProbe` |
| 5 | `OverlayEditorWindow.xaml` (`:14-15` геометрии, `:199-202` капсула, `:310-334` поповер толщины), `Controls/AnnotationCanvas.cs` (`:512-519`, `:663-670`, новый `StrokeGeometry`), `WpfExportImageRenderer.cs` (`:102-111`), `OverlayEditorWindow.Appearance.cs` (`:21-24`, `:128-199`, `:201-215`, `:275-285`, `:345-366`), `OverlayEditorWindow.xaml.cs` (`:47`, `:71`, `:890-901`), `EditorShortcuts.cs` (`:25`), `HotkeySettingsWindow.xaml.cs` (`:52`), `UiLanguage.cs` (`:31`) |
| 6 | Новые `OverlayEditorWindow.Text.cs`, `TextMarkMetrics.cs`; `OverlayEditorWindow.xaml` (новый `TextLayer`, кнопка `FontSizeButton`, `FontSizePopup`), `OverlayEditorWindow.xaml.cs` (`:722`, `:844-861`, `:875-892`, `:987-1128`, `:1139`, `:1246`, `:1411-1427`), `Controls/AnnotationCanvas.cs` (`:222-239`, `:538-542`, `:617`), `EditorModels.cs` (`:34-96`, `:98-163`), `SnapBrief.Core/Models/AnnotationItem.cs`, `WpfExportImageRenderer.cs` (`:125`, `:171-176`), `OverlayEditorWindow.Appearance.cs`, `UiLanguage.cs`, `SmokeTestRunner.cs` |

---

## 4. Порядок коммитов

1. **П.1** `windows: a click beside the capture finishes the shot again`
2. **П.2** `windows: fill gets a button of its own on the panel`
3. **П.5** `windows: the pencil and the highlighter draw apart`
4. **П.6** `windows: text is typed on the capture`

Зависимости:

- П.2 раньше П.5 и П.6: обе следующие правки трогают ту же панель и тот же `SyncAppearance`, и делать это на панели, которую ещё предстоит перекроить, значит переделывать дважды.
- П.5 раньше П.6: П.5 вводит «толщина зависит от инструмента» в `SyncAppearance` и в поповер, П.6 повторяет ту же схему для кегля и должен видеть готовый образец, иначе в панели заведутся две разные механики одного вида.
- П.1 первым, он самый короткий и ни с чем не пересекается, кроме одной строки, которую П.6 потом дополнит вызовом `CommitTextEditIfOutside`.
- Порядок относительно чужих пунктов (3 лента, 4 мастер) безразличен, файлы не пересекаются.

---

## 5. Изменения форматов

Всё аддитивно, файлы прошлых версий читаются. Каждый пункт получает абзац «Изменение формата» в `tasks/verification.md` в момент коммита.

| Файл | Поле | Пункт |
|---|---|---|
| `session.json` | `annotations[].fontSize`: число, по умолчанию 20; отсутствие значит 20. До этой правки кегль текста в экспорте считался от `thickness`, теперь `thickness` у текста не влияет ни на что | 6 |
| | `annotations[].thickness` у `kind: "highlight"` начинает значить реальную ширину штриха, а не четверть её. Сессия, записанная 1.3.0 и прочитанная новой сборкой, нарисовала бы маркер вчетверо тоньше; практического следствия нет, потому что сессия живёт один запуск и удаляется на выходе (`5531c42`) | 5 |
| | `annotations[]` у `kind: "text"`: вторая точка перестаёт быть тем, что провела рука, и становится вычисленным размером надписи. Схема не меняется, меняется смысл значения; старый файл пересчитывается при открытии | 6 |
| `settings.json` | `annotationHighlightThickness`: число, по умолчанию 16, читается с клампом 4..48 | 5 |
| | `annotationFontSize`: число, по умолчанию 20, читается с клампом 8..96 | 6 |

`manifest.json` и `prompt.md` не меняются. `CaptureCropper` новых веток не требует.

---

## 6. Тесты и smoke

`tests/SnapBrief.Core.Tests`:

- round-trip `fontSize` через `session.json`, включая строку в JSON;
- сессия без `fontSize` читается с 20 и проходит `SessionValidation`;
- `CaptureCropperTests`: текстовая отметка с `fontSize` переживает кроп без потери поля.

`tests/SnapBrief.App.Imaging.Tests`:

- новый `TextMarkMetricsTests`: `Measure` даёт ширину больше высоты для «Привет», кириллица и латиница обе меряются, пустая строка даёт непустой размер, `Fit` кладёт вторую точку правее и ниже первой и не двигает первую.

Smoke (`SmokeTestRunner.cs` и пробы в `OverlayEditorWindow.xaml.cs`):

- **П.1**, новая проверка в `RunShortcutHintProbe`: после `window.Surface.SelectAnnotation(id)` вызов `window.OnWindowMouseUp` с источником `DesktopImage` и точкой вне `_cropRect` даёт `Result.Cancelled == false` и заполненный `Result.Capture`; тот же вызов сразу после открытия поля ввода текста не завершает съёмку (флаг съел клик); клик по пустому месту внутри снимка через `Surface.BeginGesture`/`EndGesture` снимает выделение и ничего не создаёт (это уже покрыто `VerifyGestureRules`, `AnnotationCanvas.cs:781+`, проверку не дублировать).
- **П.2**: `FillButton` присутствует в панели, его подпись не пуста ни при одном инструменте, ширина панели по-прежнему одинакова для всех инструментов (существующая проверка `:366-380` дополняется чтением `FillButton.Content`); `FillPopup.Child` добавляется в список панелей, обходимых на кириллицу в английском режиме (`:148`); клик по `FillSolidSegment` при вооружённой стрелке сперва вооружает «Область» и ставит `Surface.ActiveFill == Solid`; образец из `FillPalette` ставит `Surface.ActiveFillColor`.
- **П.5**: `EditorShortcuts.Caption(EditorTool.Pen) == "Pencil (P)"` (существующая строка `:393` ожидает `"Pen (P)"`, её надо поправить); `UiLanguage` больше не знает ключ «Перо»; при вооружённом маркере `ThicknessButton.Content` показывает значение из `annotationHighlightThickness`, а при карандаше из `annotationThickness`, и переключение туда-обратно значения не смешивает; round-trip настройки `annotationHighlightThickness` (значение вне 4..48 клампится); пиксельная проверка на экспортном PNG: штрих маркера поверх белого даёт один и тот же цвет в середине отрезка и в стыке двух отрезков (это и есть проверка, что прозрачность перестала копиться), а штрих карандаша даёт чистый цвет отметки.
- **П.6**: новая проба `RunTextMarkProbe` по образцу `RunCommentsPanelProbe`: одиночный жест `BeginGesture`/`EndGesture` при вооружённом тексте создаёт одну отметку со словом из таблицы («Текст» в русском, «Text» в английском), поле ввода открыто, текст в нём выделен целиком; ввод «Привет» и Enter дают `annotation.Text == "Привет"` и закрытое поле; Esc на свежей отметке удаляет её и не оставляет записи в истории; двойной клик в середину слова (через `BeginGesture(point, clickCount: 2)`) попадает в ту же отметку, а не создаёт вторую (прямая проверка починенного хит-теста); `FontSizeButton` активен только при тексте и не пустеет; кегль отметки совпадает на холсте и в экспорте (сравнение высоты закрашенного столбца пикселей на экспортном PNG с `TextMarkMetrics.Measure`); переоткрытие снимка из ленты (`RebuildChips`) не создаёт пилюлю для текста и не теряет надпись.

Ручной сценарий приёмки, кусок из «Как проверять» ТЗ по моей зоне: снимок, рамка, клик по пустому месту внутри снимка (рамка снята с выделения, ничего не нарисовано), клик вне снимка (редактор свернулся); рамка, «Заливка» → «Цвет 100 %» и другой цвет заливки, видно на снимке и в экспорте; карандаш с толщиной 8 и маркер полупрозрачный широкий, у них разные значения в кнопке «Толщина»; текст: клик, слово «Текст» выделено, печатаю «Привет», Enter, надпись на снимке, размер 24 из выбора размеров, двойной клик по надписи открывает правку.

---

## 7. Принято по умолчанию

Блокирующих вопросов нет, всё ниже решено и переспрашивать не нужно.

- Клик мимо снимка при открытом поповере сначала закрывает поповер и только вторым кликом завершает съёмку. Это поведение самого WPF (`StaysOpen="False"`), ломать его специально не стоит.
- Клик мимо снимка при открытом вводе текста или открытой пилюле завершает ввод и на этом останавливается: один клик делает одно действие.
- Кнопка «Заливка» получает подпись словом, а не только иконку. Панель от этого становится шире примерно на 96 px, но именно безымянный кружок и был причиной пункта 2.
- Выбор цвета заливки переезжает в поповер заливки целиком, из поповера цвета уходят оба кружка-приёмника и вся механика `_colorTarget`. Пять быстрых точек на панели продолжают красить то, что видно (заливку у рамки без контура), это поведение из C5 сохраняется.
- Имена значений перечисления `EditorTool.Pen` и `AnnotationKind.Freehand` не переименовываются вслед за подписью: меняется слово в интерфейсе, а не формат.
- Прозрачность маркера 0.4, торцы и стыки квадратные, толщина по умолчанию 16, пресеты 8/12/16/24, ползунок 4..48.
- Толщина карандаша остаётся общей с рамкой, стрелкой и прочим (`annotationThickness`): Никита просил, чтобы общая кнопка на карандаш действовала, а не чтобы у него была своя шкала.
- Размер шрифта хранится в модели отметки и в настройках, кегль по умолчанию 20, пресеты 12/16/20/24/32/48, ползунок 8..96.
- Shift+Enter в поле текста даёт перенос строки: так уже работает заметка, и это записано в шпаргалке клавиш.
- Пустой текст после завершения удаляет отметку, чтобы клик мимо не оставлял на снимке невидимый объект.
- Текстовая отметка не растягивается углами: её двигают и правят, размер задаётся кнопкой «Размер».
- Цвет текста берётся из общего выбора цвета, отдельного цвета текста не заводим.
