# План по ТЗ №5 (раунд tz-006): дорожка B — лента

Пункты: B1 (карточки не разворачиваются), B2 (список растёт по содержимому), B3 (полоса прокрутки overlay и «вторая полоса»), B4 (клип миниатюры по радиусу), B5 (капсула на месте), B6 (лента — окно на панели задач).

Зона: `src/Snapik.App/EdgeStackWindow.xaml(.cs)`, `src/Snapik.App/Controls/StripResizeGeometry.cs`, новый `src/Snapik.App/Controls/RoundedClip.cs`.

Общие файлы: `UiLanguage.cs`, `SmokeTestRunner.cs`, `App.xaml.cs`, `tests/Snapik.App.Imaging.Tests/StripResizeGeometryTests.cs`, `tasks/verification.md`. `SingleInstanceActivation.cs` — только чтение, правок не требует.

Не моё: мастер и закреп (A1, A2), редактор целиком (C1–C6), палитры тем (кроме того, что `ScrollThumbBrush`/`ScrollThumbHoverBrush` уже есть во всех шести и трогать их не надо).

Код сверен с `d84fbb0`; `git diff d84fbb0 HEAD -- src/` пуст, значит `file:line` совпадают и с HEAD. Правила `AGENTS.md`: строки UI только парой RU/EN в `UiLanguage.cs`, `macos/` не трогать, один коммит на законченную правку, `scripts/build.ps1` зелёный.

---

## 0. Где ТЗ не сходится с кодом

1. **B3: второй полосы не существует. Полоса одна, и она шириной 17 DIP вместо 4.** Разбор пикселей `evidence/kate-strip-1.5.0-five-captures.png` (масштаб подтверждён: бейдж карточки 20 DIP = 25 px, значит 125 %): светлая накладка занимает `x = 258…278` (21 px = 16,8 DIP), прижата к правому краю списка, высота пропорциональна прокрутке, углы скруглены на 2 DIP. Заливка — ровно одна альфа: на тёмной карточке 26 → 90, на панели 122 → 159, обе дают α = 0,28 = `#47` — это `ScrollThumbBrush` (`Themes/Palettes/Glass.xaml:30`), то есть `Grip` нашего `Thumb` (`EdgeStackWindow.xaml:115`). Карточка кончается за 8 DIP до правого края списка (`Padding="8,14,8,52"`, `:169`), поэтому последние ~9 DIP ползунка лежат **на карточках**: их Катя и прочитала как «тусклую вторую полосу», а часть над панелью — как «узкую яркую». Двух элементов там нет: между `x = 258` и `x = 278` альфа постоянна, наложения двух полупрозрачных слоёв (было бы α ≈ 0,48) нигде нет.
2. **Причина ширины найдена и проверена, живой прогон для неё не нужен.** `Width="4"` у `PART_VerticalScrollBar` (`:198`) проигрывает `MinWidth = 17`, который приходит из **дефолтной темы** `ScrollBar` и который `StackScrollBar` не перекрывает. Прогон той же разметки через `XamlReader.Parse` + `UpdateLayout` (скрипт в TEMP задачи): `ActualWidth = 17` при `Width = 4`; `DependencyPropertyHelper.GetValueSource(bar, MinWidthProperty).BaseValueSource = DefaultStyle`, `bar.MinWidth = 17`. Не помогают: `MaxWidth="4"`, `<Setter Property="Width" Value="4">` в стиле, присваивание `Width` из кода, обёртка в `Grid Width="12"` (полоса вылезает влево за пределы обёртки). Помогает **только** `MinWidth="0"` — на элементе или сеттером в `StackScrollBar`: обе формы дали `ActualWidth = 4`, `x = правый край − 4 − 1`. Остальное в `:184-206` работает как задумано: контент не сужается (`PART_ScrollContentPresenter` = полная ширина), полоса действительно лежит поверх.
3. **B2: формула ТЗ верна, но текущий нижний паддинг 52 не «лишние пустые 52 px», а попытка дать место выступу — и она не работает.** Карточка несёт `Margin="0,0,0,-48"` (`:224`), поэтому `StackPanel` считает высоту как `30·n`, а последняя карточка рисуется на 48 px ниже этой высоты и обрезается презентером. Замеры того же прогона: при `Padding="8,14,8,52"`, высоте списка 220 и 5 карточках `Extent = 150`, `Viewport = 152`, `ScrollableHeight = 0` — прокрутки нет, а низ последней карточки уходит на **46 px за видимую область**. При 12 карточках и высоте 372 — за 104 px. То есть «обрезка» из README к свидетельству Кати — это не B4 и не B3, а вот это. Лечится не паддингом, а тем, что выступ надо отдать в `Extent`: `<StackPanel Margin="0,0,0,48"/>` в `ItemsPanel`. С ним и с `Padding="8,14,8,8"` тот же прогон даёт `Extent = 14 + 30·(n−1) + 78 + 8` один в один с числами эталона (2 → 108 + хром, 5 → 198 + хром, 12 → 408 > 348 = прокрутка).
4. **Мешают ещё 2 px, которых нет в разметке.** Дефолтный шаблон `ListBox` заворачивает `ScrollViewer` в `Border x:Name="Bd"` с захардкоженным `Padding="1"` (наш `BorderThickness="0"` его не снимает). В прогоне `ScrollViewer` стоит на `x=1, y=1` и на 2 px меньше списка. Из-за этих 2 px «влезающий» список всё равно получает `ScrollableHeight = 2` и **показывает полосу там, где прокрутки нет**. Формула ТЗ (130 / 220 / 372) сходится только при нулевом хроме, поэтому `ListBox` надо перешаблонить в голый `ScrollViewer` — см. §B2.4. Побочная польза: `ScrollViewer` перестаёт быть неявным стилем и вопрос «доходит ли implicit style внутрь шаблона» снимается совсем.
5. **B5: `Left` не просто «не восстанавливается», он вообще нигде не сохраняется.** `CollapseToCapsule` кладёт в поля `_expandedWidth`, `_expandedListHeight`, `_expandedTop`, `_expandedMinHeight` (`:665-668`) — `Left` среди них нет. То есть «разворот возвращает ленту в прежний `Left`» требует нового поля, а не только порядка вызовов.
6. **B5 шире, чем написано: к краю прыгает не только капсула.** `ShowStackWithoutActivation` зовёт `PositionAtEdge()` (`:634`), а тот на каждом показе переписывает `Left`, `Top`, `Width` и `CaptureList.Height` (`:738-752`). Лента, оттащенная за пояс (`OnShellMouseDown` → `DragMove`, `:1730`), возвращается к краю после **любого** нового снимка, а не только после капсулы. Входов в `ShowStackWithoutActivation` семь (`CaptureLoopAsync`, `OnOpenCaptureClick`, `PasteAsync`, `OnClosing`, `RevealStack`, трей, `OnLoaded`). Без разделения «поставить в первый раз» / «просто показать» B2 тоже не закрыть: `PositionAtEdge` затирает высоту, посчитанную по содержимому.
7. **B6 против «Свернуть в трей».** `OnHideClick` → `HideStack()` → `Hide()` (`:640-647`) и запасной путь `OnClosing` (`:1851`) убирают окно из панели задач вместе с линией. Пока лента прячется в трей, требование «пока Snapik работает, под иконкой линия» не выполняется. Нужно решение (§B6.2), ТЗ его не называет.
8. **B6: линии не будет до первого показа ленты.** `OnLoaded` делает `Hide()` (`:200`), а `ShowStackWithoutActivation` зовётся только после мастера (`:232`) или после первого снимка. На втором и последующих запусках между стартом и первым снимком окна нет — и линии нет. ТЗ этого не оговаривает, см. §B6.5.
9. **B1: адрес `:1745` верен, но `IsSelected` больше нигде не читается.** `capture.IsSelected` ставится только в `OnOpenCaptureClick` (`:1745`, снимается `:1771`) и читается только триггером `:315-318`. Убрав триггер, свойство можно оставить как есть — оно в `CaptureItem.DeepClone` (`EditorModels.cs:265`) и в формате не участвует.
10. **B4: `ClipToBounds` тут вообще ни при чём.** `Border` в WPF не режет содержимое по `CornerRadius` ни при каком `ClipToBounds` — `ClipToBounds` даёт прямоугольник. Формулировка ТЗ «содержимое режется прямоугольником» описывает штатное поведение, а не сбой; чинится это только явным `Clip` или маской (§B4).

---

## 1. Решения по пунктам

### B1. Наведение, фокус и выбор не трогают геометрию карточки

**Решение.** В `DataTemplate.Triggers` (`EdgeStackWindow.xaml:306-318`):

- из триггера `IsMouseOver` (`:306-310`) убрать `<Setter TargetName="ThumbCard" Property="Margin" Value="0,4,0,4" />` (`:309`); оставить `BorderBrush="#718096"` и `DeleteButton.Opacity=1`;
- из триггера `IsKeyboardFocusWithin` (`:311-314`) убрать сеттер `Margin` (`:312`); оставить `DeleteButton.Opacity=1` — клавиатура должна показывать крестик;
- триггер `IsSelected` (`:315-318`) убрать целиком: и `Margin`, и `BorderBrush="{DynamicResource FocusBrush}"`. После возврата из редактора карточка выглядит как все — это и есть требование.

Сдвиг на 4 px не возвращаем ни в каком виде: на эталоне `reference-png/03` карточки лежат ровно, перекрытие 48 не меняется. Если Никита захочет его вернуть — только `RenderTransform` (`TranslateTransform Y="-4"`), он не участвует в `Measure` и не ломает ни `Extent`, ни формулу B2.

Комментарий `:301-305` (про анимации и `FillBehavior.HoldEnd`) переписать: анимаций там уже нет, а причина, по которой три триггера жили сеттерами, исчезает вместе с сеттерами.

`capture.IsSelected` в `OnOpenCaptureClick` оставить: ставится/снимается симметрично, ничего не красит.

**Побочный эффект, который надо знать.** Именно разворот делал ленту Кати прокручиваемой на пяти снимках: `Extent` с двумя развёрнутыми карточками ≈ 200 DIP вместо 150. После B1 пять карточек в 220 не прокручиваются вовсе, и полоса из B3 в её сценарии больше не появится.

### B2. Список растёт по содержимому

**Формула (эталон `reference-png/03`, левая часть).** `14 + (n − 1)·30 + 78 + 8`, потолок — сохранённая `StackHeight` (по умолчанию `DefaultListHeight = 372`). Проверка: 2 → 130, 5 → 220, 12 → 430 → 372. Пустая лента — подсказка 92 (`EmptyHint`, `:330`), как сейчас.

**1. Чистая функция в `Controls/StripResizeGeometry.cs`.** Рядом с `DefaultListHeight` (`:50`):

```csharp
internal const double EmptyListHeight = 92;   // the hint instead of the list
internal const double ListTopPadding = 14;
internal const double ListBottomPadding = 8;
internal const double CardHeight = 78;
internal const double CardStep = 30;          // CardHeight - CardOverlap(48)

/// The height the capture list wants for <paramref name="count"/> cards, and the ceiling the
/// corner grip has written into the settings. The grip sets the ceiling, not the height: a list
/// with two cards is 130 tall whatever the settings say, and it stops growing at the ceiling.
internal static double ListHeightForCount(int count, double cap)
{
    if (count <= 0) return EmptyListHeight;
    var content = ListTopPadding + (count - 1) * CardStep + CardHeight + ListBottomPadding;
    var ceiling = double.IsFinite(cap) && cap > 0 ? cap : DefaultListHeight;
    return Math.Min(content, ceiling);
}
```

`MinimumListHeight = 180` (`:49`) остаётся **только** полом для сохранённого значения в `ClampListHeight`; к росту по содержимому он не применяется — иначе один снимок дал бы 180 вместо 100.

**2. Точка применения в `EdgeStackWindow.xaml.cs`.** Новый метод рядом с `PositionAtEdge`:

```csharp
private void ApplyListHeight()
{
    if (CaptureList is null) return;
    var cap = Controls.StripResizeGeometry.ClampListHeight(
        _settings.StackHeight, StackWorkArea().Height, StackChromeHeight());
    CaptureList.Height = Controls.StripResizeGeometry.ListHeightForCount(Captures.Count, cap);
}
```

Звать из `UpdateEmptyState()` (`:1398`) — он уже висит на `Renumber()` и через него на всех двенадцати входах, меняющих состав ленты (`CaptureLoopAsync`, `ImportFileAsync`, `ImportClipboardAsync`, `OnCaptureListDrop`, `OnRemoveCaptureClick`, `RestoreRemoved`, `ClearStackCoreAsync`, `MarkCapturesSentAsync`, `OnOpenCaptureClick`, `ExpandFromCapsule`, `OnLoaded`, `ShowStackWithoutActivation` — проверено `trace_call_path`). Отдельных вызовов добавлять не нужно.

**3. `PositionAtEdge` перестаёт задавать высоту.** Строку `:748` (`CaptureList.Height = ClampListHeight(...)`) заменить на `ApplyListHeight();`. Окно на `SizeToContent="Height"` (`:6`) следует за списком само — это уже так и есть, менять нечего. `MinHeight="128"` (`:6`) оставить: пустая лента 92 + хром больше 128 не даёт схлопнуться.

**4. `ListBox` перешаблонить (§0.4).** В `EdgeStackWindow.xaml` внутрь `ListBox` добавить

```xml
<ListBox.Template>
    <ControlTemplate TargetType="ListBox">
        <!-- Bare, without the Bd border of the default template: that one carries a hardcoded
             Padding="1" which BorderThickness="0" does not remove, and those two pixels made a
             list that fits scrollable by two pixels — a bar where there is nothing to scroll. -->
        <ScrollViewer Focusable="False" Padding="{TemplateBinding Padding}"
                      CanContentScroll="{TemplateBinding ScrollViewer.CanContentScroll}"
                      VerticalScrollBarVisibility="{TemplateBinding ScrollViewer.VerticalScrollBarVisibility}"
                      HorizontalScrollBarVisibility="Disabled"
                      Template="{StaticResource StackScrollViewer}">
            <ItemsPresenter />
        </ScrollViewer>
    </ControlTemplate>
</ListBox.Template>
```

Шаблон `ScrollViewer` (`:184-206`) переезжает из неявного стиля в именованный `ControlTemplate x:Key="StackScrollViewer"` в `Window.Resources`; неявный `<Style TargetType="ScrollViewer">` (`:184-206`) и `<Style TargetType="ScrollBar" BasedOn=...>` (`:176`) из `ListBox.Resources` убираются, полоса получает `Style="{StaticResource StackScrollBar}"` прямо в шаблоне. Всё становится явным, ни одного неявного стиля внутри чужого шаблона не остаётся.

**5. Паддинг и выступ.** `Padding="8,14,8,52"` → `Padding="8,14,8,8"` (`:169`); `ItemsPanel` (`:213`) → `<ItemsPanelTemplate><StackPanel Margin="0,0,0,48" /></ItemsPanelTemplate>`. Сорок восемь — это выступ последней карточки за высоту `StackPanel` (отрицательный `Margin` карточки, `:224`); отданные в `Margin` панели, они попадают в `Extent`, и низ последней карточки перестаёт обрезаться. Правое поле под полосу — 12 вместо 8 (§B3), то есть итог `Padding="8,14,12,8"`; карточка сужается на 4 px, `StripResizeGeometry.CardWidth` (`:39-40`) поправить на `- ListPaddingLeft - ListPaddingRight`.

**6. Ручка угла задаёт потолок.** `OnCornerDragDelta` (`:812-828`) оставить как есть: во время перетаскивания список идёт за указателем, иначе короткая лента не двигается вовсе (об этом комментарий `StripResizeGeometry.cs:44-48`). В `OnCornerDragCompleted` (`:830-836`) после сохранения `StackHeight` добавить `ApplyListHeight();` — список садится обратно на высоту содержимого, а потолок остаётся тем, что натянули. Это видимый «доводчик» на отпускании; так и задумано, в `verification.md` записать отдельной строкой.

### B3. Полоса прокрутки

**1. Ширина (корень «второй полосы»).** В `StackScrollBar` (`:103-130`) добавить к сеттерам `<Setter Property="MinWidth" Value="0" />` и `<Setter Property="MinHeight" Value="0" />`, и на самой полосе в шаблоне `ScrollViewer` поставить `MinWidth="0"`. Оба способа проверены прогоном по отдельности; ставим оба — если шаблон когда-нибудь применят к полосе без нашего стиля, ширина всё равно не разъедется. `Width` в покое — 3 (эталон), при наведении 6.

**2. Поле 12 px и тени.** Правый паддинг списка 12 (§B2.5). Полоса `HorizontalAlignment="Right" Margin="0,2,2,2"`, ширина 3 → правый край полосы стоит в 2 px от края списка, левый — в 7 px от края карточки. Тень карточки (`:229`, `BlurRadius="16"`, `Direction="90"`) расходится вбок на `BlurRadius / 2 = 8` px — то есть впритык. Уменьшить `BlurRadius` до 12 (вбок 6 px, зазор 1 px до полосы); вверх, куда тень и делается, 12 хватает — шов между карточками 30 px. Если Никита захочет сохранить нынешнюю мягкость шва, вариант без компромисса — снять `DropShadowEffect` и нарисовать шов градиентным `Border` по верхней кромке карточки: тогда вбок не расходится ничего и с карточек уходит по одному bitmap-эффекту на штуку.

**3. Поведение overlay.** Полоса живёт по `ComputedVerticalScrollBarVisibility` (как сейчас), видимость — через `Opacity`:

- в шаблон `ScrollViewer` полосу завернуть в `<Grid x:Name="BarField" Width="12" HorizontalAlignment="Right" Background="Transparent">` — это зона наведения и она целиком лежит в паддинге списка, карточек не отнимает;
- `Opacity="0"` в покое; в code-behind `EdgeStackWindow.xaml.cs` подписка `CaptureList.AddHandler(ScrollViewer.ScrollChangedEvent, new ScrollChangedEventHandler(OnStripScrolled))` в `OnSourceInitialized`;
- `OnStripScrolled`: если `e.VerticalChange != 0` — `FadeBar(1, 90 мс)` и перезапуск `DispatcherTimer _scrollBarTimer` на 1 с; по тику — `FadeBar(0, 160 мс)`;
- наведение на `BarField` держит полосу: `Trigger IsMouseOver` на `BarField` → `Opacity=1` у полосы и `Width=6` у неё же; на `MouseEnter` останавливать таймер, на `MouseLeave` — перезапускать. Триггер и анимация на разных свойствах, конфликта приоритетов (урок C1 из tz-005) нет; `Opacity` в триггере ставится сеттером, а сториборд гасит — чтобы они не спорили, гасить через `BeginAnimation(OpacityProperty, ...)` на самой полосе, а держать наведением через `_scrollBarTimer.Stop()`, без сеттера `Opacity` в триггере. Ширину 3 → 6 оставить сеттером триггера;
- перетаскивание грипа и листание кликом по дорожке уже работают: `PART_VerticalScrollBar` и `RepeatButton`-ы с `Opacity="0"` остаются кликабельными (`Opacity` не убирает хит-тест);
- PgUp/PgDn проходят через штатную навигацию `ListBox` и дают `ScrollChanged` — отдельного кода не надо.

Кисти: `ScrollThumbBrush` / `ScrollThumbHoverBrush` / `FocusBrush` при `IsDragging` (`:115-118`) остаются, палитры не трогаем.

### B4. Клип миниатюры по радиусу 11

`ClipToBounds="True"` (`:225`) снять — он бесполезен (§0.10) и заставляет WPF держать промежуточный буфер под `Effect`. Вместо него — прикреплённое свойство `Controls/RoundedClip.cs`:

```csharp
internal static class RoundedClip   // RoundedClip.Radius="10" on the inner Grid
{
    public static readonly DependencyProperty RadiusProperty = DependencyProperty.RegisterAttached(
        "Radius", typeof(double), typeof(RoundedClip), new PropertyMetadata(0d, OnRadiusChanged));
    // On SizeChanged: element.Clip = new RectangleGeometry(new Rect(size), radius, radius);
}
```

Вешается на внутренний `Grid` карточки (`:230`), радиус 10 = 11 − `BorderThickness="1"`: клип идёт по внутренней кромке рамки, и картинка не наползает на штрих. Сам `Border` с `CornerRadius="11"` остаётся как рамка и фон.

Отдельный класс, а не конвертер с `MultiBinding`: переиспользуется в редакторе и один в один ложится на маковский `layer.cornerRadius + masksToBounds`.

### B5. Капсула появляется на месте ленты и возвращает её туда же

**1. Запоминать прямоугольник целиком.** Новое поле `_expandedLeft` рядом с `_expandedTop` (`:82`); в `CollapseToCapsule` (`:661`) писать `_expandedLeft = Left;` вместе с остальными четырьмя.

**2. Капсула встаёт по правому краю ленты, а не по краю монитора.** `PositionCapsuleAtEdge` (`:703-707`) заменить на `PositionCapsuleAtStrip`:

```csharp
private void PositionCapsuleAtStrip()
{
    UpdateLayout();                       // ActualWidth of the capsule is needed below
    Left = _expandedLeft + _expandedWidth - ActualWidth;
    Top = _expandedTop;                   // Top is already untouched today
}
```

Оба окна несут одно и то же поле под тень 20 px (`StripResizeGeometry.ShadowMargin`), поэтому видимые правые кромки совпадают — «тот же правый верхний угол» эталона. Чистая часть — в `StripResizeGeometry`, тестом закрывается:

```csharp
internal static double CapsuleLeft(double stripLeft, double stripWidth, double capsuleWidth) =>
    stripLeft + stripWidth - capsuleWidth;
```

**3. Разворот — одним `SetWindowPos`, без пересчёта монитора.** `ExpandFromCapsule` (`:682-699`):

```csharp
_capsuleMode = false;
Capsule.Visibility = Visibility.Collapsed;
Shell.Visibility = Visibility.Visible;
WidthGrip.Visibility = Visibility.Visible;
UpdateEmptyState();                      // brings ApplyListHeight with it
SizeToContent = SizeToContent.Manual;    // no layout pass may move the window in between
MinHeight = _expandedMinHeight;
Width = _expandedWidth;
CaptureList.Height = Controls.StripResizeGeometry.ListHeightForCount(Captures.Count, _expandedListHeight);
UpdateLayout();                          // measures the height the strip is about to have
var target = Controls.StripResizeGeometry.RestoreRect(
    new Rect(_expandedLeft, _expandedTop, Width, ActualHeight), StackWorkArea());
var dpi = VisualTreeHelper.GetDpi(this);
_ = SetWindowPos(new WindowInteropHelper(this).Handle, IntPtr.Zero,
    (int)Math.Round(target.X * dpi.DpiScaleX), (int)Math.Round(target.Y * dpi.DpiScaleY),
    (int)Math.Round(target.Width * dpi.DpiScaleX), (int)Math.Round(target.Height * dpi.DpiScaleY),
    0x0014);                             // SWP_NOZORDER | SWP_NOACTIVATE
SizeToContent = SizeToContent.Height;
```

Ключевое: `StackWorkArea()` спрашивается у монитора, на котором стоит **капсула**, то есть у того же, где была лента, и результат используется только как рамка для клампа — новый `Left` из него не выводится. `Screen.FromHandle` до `SetWindowPos` ещё видит капсулу, поэтому промежуточного «окно наполовину на соседнем мониторе» не возникает вовсе.

**4. Кламп только если не влезает** — чистая функция, тест:

```csharp
/// The rectangle the strip had before the capsule, moved back into the working area only when it
/// no longer fits: a strip dragged away from the edge stays where the user left it.
internal static Rect RestoreRect(Rect stored, Rect work)
{
    if (!work.IsEmpty && work.Width > 0 && work.Height > 0 && !work.Contains(stored))
    {
        var x = Math.Min(Math.Max(stored.X, work.Left), Math.Max(work.Left, work.Right - stored.Width));
        var y = Math.Min(Math.Max(stored.Y, work.Top), Math.Max(work.Top, work.Bottom - stored.Height));
        return new Rect(x, y, stored.Width, stored.Height);
    }
    return stored;
}
```

**5. Новый снимок в капсуле не двигает капсулу.** В `ShowStackWithoutActivation` (`:634`) вместо `if (_capsuleMode) PositionCapsuleAtEdge(); else PositionAtEdge();` — `if (!_capsuleMode) EnsureStripPlaced();`. Капсула в этот момент уже стоит на месте, трогать её незачем.

**6. `PositionAtEdge` делится надвое (§0.6).** `PlaceStripInitially()` — нынешнее тело `:738-752` минус строка высоты, зовётся из `OnLoaded` (`:227`) и когда окно ещё ни разу не показывали. `EnsureStripPlaced()` — только `ApplyListHeight()` плюс `RestoreRect` текущего прямоугольника в рабочую область: лента остаётся там, куда её оттащили, и возвращается на экран, если монитор отвалился. Это же чинит «лента прыгает к краю после каждого снимка», о котором ТЗ говорит только применительно к капсуле.

### B6. Лента — окно приложения на панели задач

**1. `ShowInTaskbar="True"`** в `EdgeStackWindow.xaml:8`, статикой в разметке. **Во время работы это свойство не переключать ни при каких условиях:** WPF пересоздаёт HWND, а на нашем HWND висят глобальные горячие клавиши (`WindowsGlobalHotkeyService(handle)`, `:251`), наблюдатель вставки и `SetWindowDisplayAffinity`. `WindowStyle="None"` + `AllowsTransparency="True"` кнопке в панели не мешают: `WS_EX_APPWINDOW` ставится независимо от слоёности окна. `ShowActivated="False"` оставить — он влияет только на первый показ.

**2. «Свернуть совсем» вместо «свернуть в трей» (§0.7).** Четвёртая кнопка шапки (`:161-163`, глиф `E8BB`) меняет смысл: `OnHideClick` → `WindowState = WindowState.Minimized;` вместо `HideStack()`. Тултип и `AutomationProperties.Name` — «Свернуть» / `Minimise`. Путь `OnClosing` (`:1851`, `Hide()`) — туда же `WindowState = Minimized` вместо `Hide()`: иначе «Закрыть окно» из правой кнопки по значку в панели уносит линию. `HideStack()` остаётся только для `HideForCapture` (`:620`), где окно и должно исчезать на время снимка. Пункт трея «Показать ленту» и `RevealStack` работают как раньше.

Оговорка Никите: «Закрыть окно» на панели задач у пользователя читается как «выйти». Если Катя так и прочтёт, альтернатива — оставить `Hide()` на `OnClosing` и признать, что линия при этом гаснет до следующего снимка.

**3. Развернуть из свёрнутого без кражи фокуса.** `Show()` минимизированное окно не восстанавливает. В `ShowStackWithoutActivation` перед `Show()`:

```csharp
if (WindowState == WindowState.Minimized)
    _ = ShowWindow(new WindowInteropHelper(this).EnsureHandle(), 4);  // SW_SHOWNOACTIVATE
```

`WindowState = WindowState.Normal` здесь не годится: он активирует окно и уводит фокус из чужого приложения ровно в тот момент, когда пользователь ждёт вставки. `ShowWindow` с `SW_SHOWNOACTIVATE` восстанавливает и не активирует. Дальше идёт нынешний `SetWindowPos(..., 0x0053)` (`:636`), он же вернёт окно наверх.

**4. Клик по значку на панели задач нам делать нечего.** Оболочка сама шлёт окну активацию, а окну в фокусе — `WM_SYSCOMMAND` `SC_MINIMIZE`. Наша лента почти никогда не в фокусе (её показывают без активации), поэтому первый клик её активирует, второй сворачивает — ровно то, что описано в ТЗ. `Topmost` при `StackTopmost = true` ничего не ломает: свёрнутое topmost-окно держит линию и возвращается на место.

**Проверить живьём (не берусь утверждать по коду):** как `WindowState.Minimized` уживается с `AllowsTransparency="True"` + `SizeToContent="Height"`. Ожидаемое место отказа — восстановление: окно проводит новый проход `SizeToContent` и может уехать по `Top`. Если уедет — восстанавливать через `SetWindowPos` из §B5.3 сразу после `ShowWindow`, прямоугольник брать из полей, записанных перед сворачиванием.

**5. Линия до первого снимка (§0.8).** Два варианта, выбрать Никите: (а) оставить как есть, линия появляется с первым показом ленты, «работает» до этого показывает значок в трее; (б) в `OnLoaded` после восстановления сессии звать `ShowStackWithoutActivation()` всегда, а не только после мастера (`:232`) — линия с первой секунды, но пустая лента на экране у тех, кто привык к тихому старту. Рекомендую (а): она не меняет привычного поведения, а B6 в первую очередь про клик по значку.

**6. Второй экземпляр и остальные окна.** `App.ShowExistingMainWindow` (`App.xaml.cs:84-92`) уже поднимает из `Minimized` и активирует — здесь активация как раз нужна (человек сам запустил приложение), менять нечего; порядок `RevealStack()` → `WindowState = Normal` → `Activate()` рабочий. `SingleInstanceActivation.cs` не трогаем. Редактор (`OverlayEditorWindow.xaml:8`), диалоги и `ScreenColorPicker` — `ShowInTaskbar="False"`, как сейчас; мастер `OnboardingWindow.xaml:4` — `True`, как требует ТЗ. На время мастера кнопок в панели будет две, но лента в этот момент скрыта (`:200`), так что фактически одна.

**7. Капсула — тот же HWND**, значит одна кнопка на панели и в свёрнутом, и в развёрнутом виде, и заголовок окна (`Title`, `:5`, идёт через `UiText`) — это то, что видно в подсказке панели задач. Дополнительно: с `ShowInTaskbar="True"` лента появляется и в Alt+Tab. Это следствие требования, не дефект.

---

## 2. Что в общий фундамент

Делать до пунктов, один раз, остальным дорожкам это не мешает:

1. **`StripResizeGeometry`: `ListHeightForCount`, `CapsuleLeft`, `RestoreRect`** и константы `EmptyListHeight`, `ListTopPadding`, `ListBottomPadding`, `CardHeight`, `CardStep`. Ими живут B2, B5 и B6.
2. **`ApplyListHeight()` + разделение `PositionAtEdge` на `PlaceStripInitially` / `EnsureStripPlaced`.** Без этого B2 затирается на каждом показе, а B5 и B6 не имеют куда встать.
3. **Поле `_expandedLeft` и один `SetWindowPos`-помощник** (`PlaceWindow(Rect)` с переводом в device-пиксели). Нужен B5 и, возможно, B6.4.
4. **Перешаблоненный `ListBox` + именованные `StackScrollViewer` / `StackScrollBar`,** без неявных стилей внутри чужих шаблонов. Нужен B2 (2 px хрома) и B3 (ширина полосы).

---

## 3. Строки RU/EN (`UiLanguage.cs`)

Новых экранных текстов почти нет; пары добавить только для изменившихся подписей:

- `"Свернуть"` → `"Minimise"` (тултип и `AutomationProperties.Name` четвёртой кнопки шапки вместо `"Свернуть в трей"`);
- `"Свернуть в трей"` из таблицы **не** удалять, пока пункт трея её использует — проверить перед удалением поиском по `UiLanguage`.

Остальные подписи ленты (`"Очистить ленту"`, `"Свернуть в капсулу"`, `"Развернуть ленту"`, `"Новый снимок"`, `"Открыть снимок"`, `"Удалить"`) не меняются.

---

## 4. Тесты и smoke

**Модульные (`tests/Snapik.App.Imaging.Tests/StripResizeGeometryTests.cs`), только чистая геометрия:**

- `ListHeightForCount`: `(0, 372) → 92`; `(1, 372) → 100`; `(2, 372) → 130`; `(5, 372) → 220`; `(12, 372) → 372`; `(12, 500) → 430`; `(5, 130) → 130` (потолок ниже содержимого); `cap = NaN → DefaultListHeight`.
- `CapsuleLeft`: `(1600, 244, 180) → 1664`; правые кромки совпадают.
- `RestoreRect`: прямоугольник внутри рабочей области возвращается как есть (в том числе оттащенный от края); прямоугольник, ушедший вправо за `work.Right`, прижимается к `work.Right - Width`; прямоугольник шире рабочей области не уезжает левее `work.Left`.
- `ClampListHeight` — существующие тесты не трогать: функция остаётся, но теперь считает только потолок.

**Smoke (`SmokeTestRunner.cs`), по образцу проверки палитр `:855-885`** — тот же приём с `XamlReader.Parse` в скрытом `Window`. Проверяет ровно те два инварианта, которые сломались в 1.5.0 и которых модульный тест не видит:

1. полоса списка на пяти карточках уже не 17 px: `PART_VerticalScrollBar.ActualWidth <= 6`;
2. список, который влезает, не прокручивается: при `n = 5` и высоте 220 `ScrollViewer.ScrollableHeight == 0`, а низ последней карточки не ниже низа `PART_ScrollContentPresenter`.

Обе величины снимаются `VisualTreeHelper` после `UpdateLayout()`; так они и были измерены при разборе B3, прогон повторяем один в один.

**Живой прогон** (шаги 3–8 раздела F ТЗ): 3 снимка → 190 без прокрутки; 12 → 372, полоса появляется и гаснет, 6 px по наведению, второй полосы нет; углы скруглены; лента у границы мониторов → капсула → разворот на месте; клик по значку показать/свернуть, снимок при свёрнутой ленте.

---

## 5. Что не должно сломаться

- **Прокрутка колесом и грипом.** `PART_VerticalScrollBar` обязан сохранить это имя и в новом шаблоне: `ScrollViewer` подписывается на его `Scroll` по имени, без единой строки кода (комментарий `:181-183`).
- **Выделение и клавиатура по карточкам.** Триггер `IsKeyboardFocusWithin` остаётся, уходит только сеттер `Margin`; `SelectionMode="Single"` и `ItemContainerStyle` с голым `ContentPresenter` (`:214-221`) не трогаем.
- **Перетаскивание порядка.** `OnCaptureListMouseDown/MouseMove/Drop` (`:1776-1790`) считают точку относительно `CaptureList` — смена шаблона `ListBox` и паддинга это не задевает, но проверить живьём после смены правого паддинга на 12.
- **Удаление с восстановлением.** `OnRemoveCaptureClick` → `RestoreRemoved` идут через `Renumber()`, то есть теперь ещё и через `ApplyListHeight` — список должен сжиматься и разжиматься без рывка окна.
- **Ctrl+V и лимит 26.** `StripIsFull` и `NoteStripGrowth` (`:586-600`) не трогаются; при 26 карточках высота упирается в потолок и дальше растёт только `Extent`.
- **Тени.** Тень окна (`Shell`, `:137`, blur 24 / depth 5) и поле 20 px под неё не меняются; меняется только blur карточки.
- **Темы.** Ни один литерал в новый код не заносить: `ScrollThumbBrush`, `ScrollThumbHoverBrush`, `FocusBrush` уже есть во всех шести палитрах. `#718096` у рамки при наведении остаётся как есть — это не регрессия раунда.
- **Капсула на `SizeToContent="WidthAndHeight"`** (`:677-678`): `SizeToContent.Manual` в `ExpandFromCapsule` ставится **до** присваивания `Width`, иначе WPF успевает провести свой проход и сдвинуть окно.

---

## 6. Риски

1. **`WindowState.Minimized` на layered-окне с `SizeToContent`** — единственное место, где я не берусь предсказать поведение по коду. Проверять первым, до всего остального в B6; запасной ход описан в §B6.4.
2. **Пересоздание HWND.** Любая правка, которая тронет `ShowInTaskbar` в рантайме, тихо снимет горячие клавиши. В код-ревью смотреть именно на это.
3. **`ApplyListHeight` внутри `UpdateEmptyState` внутри `Renumber`** — `Renumber` зовётся часто, в том числе из `ShowStackWithoutActivation`. Если окажется, что перезапись `CaptureList.Height` на каждом вызове даёт лишний layout-проход и мигание, ставить высоту только при фактическом изменении (`if (Math.Abs(CaptureList.Height - wanted) > 0.5)`).
4. **Доводчик ручки угла** (§B2.6) — единственное место, где поведение видимо меняется не в сторону эталона, а в сторону формулировки ТЗ. Согласовать с Никитой до реализации.
5. **Правый паддинг 12** сужает карточку на 4 px при ширине окна 244. На эталоне карточка 168 при паддинге 8; если Катя мерила карточку, придётся выбирать между 168 и полем 12. Мой выбор — поле 12, о карточке 164 сказать отдельной строкой.

---

## 7. Файлы

**Зона B:** `src/Snapik.App/EdgeStackWindow.xaml`, `src/Snapik.App/EdgeStackWindow.xaml.cs`, `src/Snapik.App/Controls/StripResizeGeometry.cs`, новый `src/Snapik.App/Controls/RoundedClip.cs`.

**Общие:** `src/Snapik.App/UiLanguage.cs` (§3), `src/Snapik.App/SmokeTestRunner.cs` (§4), `src/Snapik.App/App.xaml.cs` (только читать: `ShowExistingMainWindow` уже делает нужное), `tests/Snapik.App.Imaging.Tests/StripResizeGeometryTests.cs`, `tasks/verification.md`.

**Не трогаем:** `SingleInstanceActivation.cs`, `Themes/Palettes/*.xaml`, `OverlayEditorWindow.*`, `OnboardingWindow.*`, `TaskbarPinService.cs`, `installer/`.

---

## 8. Перенос на macOS

Зеркалить в `macos/Sources/SnapikMac/Stack/`:

- **`StackMetrics.swift`** — `listPaddingBottom` 52 → 8, добавить `listPaddingRight` 12 и функцию `listHeight(forCount:cap:)` с той же формулой `listPaddingTop + (n−1)·cardStep + cardHeight + listPaddingBottom`, и `emptyHintHeight` уже есть (`:60`). `scrollBarWidth` 4 → 3 (6 по наведению).
- **`EdgeStackContentView.swift`** — снять разворот карточки на наведении/фокусе/выборе (порт триггеров `:306-318`) и акцентную рамку выбранной; высота списка по содержимому.
- **`ThumbnailCardView.swift`** — клип по радиусу: на AppKit это `layer.cornerRadius = cardCornerRadius` + `layer.masksToBounds = true` на слое картинки, прикреплённое свойство из B4 не нужно.
- **`EdgeStackWindowController.swift`** — `positionAtEdge()` (`:220`) разделить так же, как `PositionAtEdge`; `collapseToCapsule()` (`:329`) запоминает весь `window.frame`, `expandFromCapsule()` (`:341`) ставит его обратно одним `setFrame(_:display:)` — на AppKit это уже один вызов, отдельного `SetWindowPos` не нужно, но монитор пересчитывать нельзя так же, как на Windows.
- **B3 на маке почти не работа:** overlay-полоса у `NSScroller` штатная — `scrollerStyle = .overlay`, `autohidesScrollers = true`, появление и затухание делает система. Наш таймер на 1 с и ручное гашение не переносить; перенести только ширину поля и то, что тень карточки в него не заходит.
- **B6 на маке уже есть:** обычное `NSApplication` держит иконку в Dock всё время работы, «свернуть совсем» — штатный `miniaturize:`. Переносить нечего, кроме того, что капсула — то же окно (это уже так, `:28`).

Ничего из этого не меняет формат данных: `session.json`, `manifest.json`, `prompt.md` и файл настроек не трогаются. `StackHeight` в настройках меняет смысл — из «высоты списка» становится «потолком высоты списка», но тип и диапазон те же; строку об этом положить в `tasks/verification.md`.
