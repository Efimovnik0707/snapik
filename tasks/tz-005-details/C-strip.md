# План по ТЗ №4 (раунд tz-005): дорожка C — лента

Пункты: C1, C2, C3, C4, C5, C6, C7, C9, лента-часть C8, плюс A7 (лента после «Начать»/«Пропустить»).

Зона: `EdgeStackWindow.xaml(.cs)`, `EdgeStackWindow.Saving.cs`, `Controls/StripResizeGeometry.cs`, `SessionWorkspace.cs`, `WpfExportImageRenderer.cs`, `HotkeySettingsWindow.xaml(.cs)` (только название клавиши).

Общие файлы: `UiLanguage.cs`, `SmokeTestRunner.cs`, `EditorModels.cs`, `src/Snapik.Core/Models/CaptureItem.cs`, `tests/`, `tasks/verification.md`.

Не моё: редактор широкой картинки и импорта (масштаб, подпись сверху справа) — дорожка D; палитры и токены тем — дорожка B; мастер — дорожка A.

Код сверен с `a2f72e1` (1.4.0), все `file:line` по нему. Правила `AGENTS.md`: строки UI только парой RU/EN в `UiLanguage.cs`, `macos/` не трогать, изменение формата — отдельным абзацем в `tasks/verification.md`, один коммит на законченную правку, `scripts/build.ps1` зелёный.

---

## 0. Где ТЗ не сходится с кодом

1. **C6 против C4 и эталона: 20 px поля под тень несовместимы с окном 224.** ТЗ требует поле под тень окна 20 px (C6) и ширину окна 224 (C4). Эталон `reference-png/04` в подписи даёт «окно 224 · панель 204 · паддинг 10 · карточка 168», C6 отдельно требует «карточка 168 при ширине списка 184». Арифметика: 204 = 224 − 2×10, то есть все нарисованные числа посчитаны при поле 10, а не 20. При поле 20 и окне 224 панель равна 184, список 164, карточка 148 — эталон рушится. Разбор и предложение — §C6.
2. **C1: «ItemsControl» — это `ListBox`.** `EdgeStackWindow.xaml:168` — `ListBox`, а не голый `ItemsControl`. Менять тип не надо: `ListBox` даёт контейнеры с фокусом (`IsKeyboardFocusWithin`, `:286`) и шаблон `ScrollViewer` со скроллбаром C2. Убирается не контрол, а `AlternationCount`, `Panel.ZIndex` и виртуализация.
3. **C1: `Items.Refresh()` сам по себе индексы не ломает.** По коду `ItemContainerGenerator` (dotnet/wpf, `ItemContainerGenerator.cs`, `RemoveAllInternal(saveRecycleQueue: false)` → `ResetRecyclableContainers()`) `Refresh()` сбрасывает очередь ресайклинга и заново раздаёт `AlternationIndex`. Причина другая и она подтверждается — §C1.
4. **C1 не назвал вторую половину поломки: анимация `Margin` побеждает сеттер.** `EnterActions` наведения анимируют `ThumbCard.Margin` (`:283`) с `FillBehavior=HoldEnd` по умолчанию. По приоритету значений WPF (animations = 2, style/template triggers = 6-7) удержанное значение навсегда выше `<Setter Property="Margin">` из триггеров `IsKeyboardFocusWithin` (`:287`) и `IsSelected` (`:291`). То есть после первого наведения выделение и фокус перестают двигать карточку вообще — это видно и без редактора.
5. **C9: «ошибка показывается в ленте, а не только в логе» уже так.** `ImportFileAsync` пишет `SetStatus(..., true)` со списком неудач (`EdgeStackWindow.xaml.cs:1070`). Новая работа здесь не нужна, нужен только фикс декодера.
6. **C7: постоянный `SetWindowDisplayAffinity` стоит ровно в одном месте и только на ленте** (`EdgeStackWindow.xaml.cs:244`). Ни редактор, ни оверлей захвата, ни настройки его не ставят: их от своего снимка спасает `HideForCapture` (`:612`). Значит удаление строки 244 ничего не ломает и «страховка на время `HideForCapture`» не нужна — окно в этот момент скрыто.
7. **C2: `#FFFFFF` 28 %/45 % у ползунка ломает светлую тему.** Сейчас ползунок берёт `TextFaintBrush`/`TextMutedBrush` (`:116-118`), то есть подстраивается под палитру. Захардкоженный белый на `dawn` (`Themes/Palettes/Dawn.xaml`, фон `#FFF4EC → #F1ECFF`) станет невидимым. Нужен токен — стык с дорожкой B, §8.
8. **C3: подсказка «Нажми ⟨клавиша⟩» не покрывает выключенную клавишу.** Клавиша захвата может быть выключена (`CaptureEnabled`), и подставлять в текст нечего. Нужны две строки, §C3.
9. **C8: эталонная подпись редактора без числа мониторов.** Текст ТЗ требует «весь экран · 2 монитора · 3840×1125», `reference-html/05` рисует «весь экран · 3840×1125». Состав подписи — дорожка D; модель отдаёт число мониторов в любом случае (§C8-модель).
10. Мелочи в адресах: `Hide()` на старте — `:200`, а не `:199`; `StripDepthConverter` — `:1851`, а не `:1850`. На решения не влияет.

---

## 1. Решения по пунктам

### C1. Порядок карточек, подпись сверху, возврат из редактора

**Диагноз подтверждён, механизм уточнён.** `AlternationIndex` раздаётся не по индексу элемента в данных, а по цепочке уже реализованных контейнеров: `ItemContainerGenerator.SetAlternationIndex` шагает к предыдущему *реализованному* блоку и берёт `prev + 1`, а если такого блока нет — seed `−1`, то есть первый реализованный контейнер получает 0, каким бы ни был его номер в списке. При прокрученной ленте (26 снимков, C6-сценарий Кати) первым реализуется снимок из середины, он получает 0, а при прокрутке назад верхний снимок получает 0 второй раз. Два `Panel.ZIndex = 0` — и порядок отрисовки падает на порядок детей, тени ложатся не в те швы. Виртуализация выключена в требовании ТЗ по делу.

Вторая половина — §0.4: удержанная анимация `Margin`. При `VirtualizationMode="Recycling"` контейнер отдаётся другому снимку без очистки свойств (`UnlinkContainerFromItem` чистит только привязку к данным), поэтому анимированный `Margin="0,4,8,4"` от прошлого наведения уезжает на чужую карточку.

Третья — прокрутка. `Items.Refresh()` даёт `Reset`, `ScrollViewer` сбрасывает `VerticalOffset` в 0. Refresh зовётся трижды на один клик по карточке: `Renumber()` (`:1353`) и дважды в `OnOpenCaptureClick` (`:1687`, `:1714`).

**Решение.**

1. Убрать все три `Items.Refresh()` и заставить модель уведомлять. В `EditorModels.cs`: `DisplayLabel` (`:198`) становится свойством с `OnPropertyChanged`; сеттер `Note` (`:200-204`) дополнительно шлёт `OnPropertyChanged(nameof(NoteCount))`; в конструкторе `CaptureItem` подписка `Annotations.CollectionChanged += (_, _) => OnPropertyChanged(nameof(NoteCount))`. `Captures[index] = result.Capture` (`:1704`) даёт `Replace`, а не `Reset`: перегенерируется один контейнер, прокрутка на месте. Это и есть требование «положение прокрутки такое же, как до открытия».
   Запасной вариант, если уведомления окажутся дороже: оставить `Refresh()`, но обернуть его сохранением `ScrollViewer.VerticalOffset` и восстановлением через `Dispatcher.BeginInvoke(DispatcherPriority.Loaded, ...)`. Менее чисто, порядок при этом всё равно чинится пунктом 2.
2. Новый `ListBox` (`EdgeStackWindow.xaml:168-174`), полностью:

```xml
<ListBox x:Name="CaptureList" Grid.Row="1" ItemsSource="{Binding Captures}" AllowDrop="True"
         Height="372" Margin="0,7,0,8" Padding="8,14,8,52"
         Background="Transparent" BorderThickness="0" SelectionMode="Single"
         ScrollViewer.VerticalScrollBarVisibility="Auto"
         ScrollViewer.HorizontalScrollBarVisibility="Disabled" ScrollViewer.CanContentScroll="False"
         VirtualizingPanel.IsVirtualizing="False"
         PreviewMouseLeftButtonDown="OnCaptureListMouseDown" PreviewMouseMove="OnCaptureListMouseMove"
         PreviewMouseWheel="OnCaptureListMouseWheel" Drop="OnCaptureListDrop">
```

   Ушли: `AlternationCount` (и `xmlns:core`, если больше нигде не нужен), `VirtualizationMode`, `ScrollUnit`. `CanContentScroll="False"` — обязательное следствие обычного `StackPanel`: при `True` прокрутка идёт целыми элементами и отрицательные поля карточек считаются неверно.
3. `ItemsPanel`: `<ItemsPanelTemplate><StackPanel /></ItemsPanelTemplate>` вместо `VirtualizingStackPanel` (`:211`).
4. `ItemContainerStyle` (`:212-231`): убрать сеттер `Panel.ZIndex` (`:224`) и оба триггера (`:228-229`) вместе с `StripDepthConverter` (`EdgeStackWindow.xaml.cs:1851`, ресурс `:11`). Порядок детей `StackPanel` = порядок данных, последний ребёнок рисуется поверх; `Captures.Add` кладёт новый в конец — новый поверх старого, как требует C1 и как нарисовано в `reference-html/04` (`z-index` там возрастает: 1, 2, 3).
5. Карточка: `Margin="0,0,8,-48"` и `Height="78"` остаются (шаг 30, перекрытие 48). Тень (`:243`) — `<DropShadowEffect Color="#000000" BlurRadius="16" ShadowDepth="6" Opacity="0.35" Direction="90" />`. `Direction=90` в WPF — вверх, то есть на соседа, который теперь сверху; комментарий `:237-242` про `270` переписать.
6. Полоса подписи (`:248`): `VerticalAlignment="Top"`, высота 26, фон `#E6171A20` — остальное без изменений. Скругление верхних углов даёт `ClipToBounds="True"` родителя (`:236`).
7. Анимации наведения (`:283-284`): либо оставить только на `EnterActions`/`ExitActions` и снять конфликт, заменив сеттеры `Margin` в триггерах `IsKeyboardFocusWithin` (`:287`) и `IsSelected` (`:291`) на такие же `BeginStoryboard`, либо убрать анимацию и поставить обычный `Setter Property="Margin" Value="0,4,8,4"` во всех трёх триггерах. **Рекомендую второе:** виртуализации больше нет, поднимать карточку на 4 px без анимации незаметно, а одинаковый уровень приоритета у трёх триггеров снимает §0.4 целиком и не требует ручной очистки анимаций.

### C2. Скроллбар

Убрать триггер `IsMouseOver` шаблона `ScrollViewer` со сторибордами ширины (`EdgeStackWindow.xaml:200-205`) целиком: ширина 4 всегда (`:195`). Реакция только на наведение на саму полосу — это уже есть в `StackScrollBar` (`:117-119`), меняются только кисти. Полоса `Margin="0,2,1,2"` остаётся, она попадает в правое поле карточки (8 px) и ширину списка не трогает — по коду это так, живьём проверяется на 26 снимках (F6).

Кисти ползунка: `Grip` (`:116`) — `{DynamicResource ScrollThumbBrush}`, при наведении `{DynamicResource ScrollThumbHoverBrush}`, при перетаскивании оставить `FocusBrush`. `CornerRadius="2"` уже стоит. Значения токенов — §8.

### C3. Пустая лента

Блок пустого состояния рядом со списком, в той же `Grid.Row="1"`:

```xml
<Border x:Name="EmptyHint" Grid.Row="1" Height="92" Margin="0,7,0,8" Visibility="Collapsed">
    <TextBlock x:Name="EmptyHintText" HorizontalAlignment="Center" VerticalAlignment="Center"
               TextAlignment="Center" TextWrapping="Wrap" Margin="10,0"
               FontSize="12" LineHeight="17" Foreground="{DynamicResource TextMutedBrush}" />
</Border>
```

Числа сняты с `reference-html/04`: блок 92, поля `7 0 8 0`, 12/17, `#8F9AAA` = `TextMutedBrush`.

Метод `UpdateEmptyState()` зовётся из `Renumber()` (`EdgeStackWindow.xaml.cs:1349`):

```csharp
var empty = Captures.Count == 0;
CaptureList.Visibility = empty ? Visibility.Collapsed : Visibility.Visible;
EmptyHint.Visibility = empty ? Visibility.Visible : Visibility.Collapsed;
CornerGrip.Visibility = empty || _capsuleMode ? Visibility.Collapsed : Visibility.Visible;
EmptyHintText.Text = _settings.CaptureEnabled
    ? string.Format(UiLanguage.Text("Нажми {0} или «Новый снимок»"), HotkeyLabelParts.Describe(_settings.CaptureGesture))
    : UiLanguage.Text("Нажми «Новый снимок»");
```

Сочетание с `StackHeight`: `PositionAtEdge` (`:738`) продолжает писать `CaptureList.Height` всегда — у свёрнутого списка она в лейаут не идёт, и первый же снимок разворачивает ленту ровно на сохранённую высоту. Ручку ширины (`WidthGrip`) оставляем: ширина у пустой ленты осмысленна, ТЗ запрещает только угол. Высота пустого окна: 20 + 10 + 28 + 7 + 92 + 8 + 36 + 10 + 20 = 231, панель 191 — совпадает с вариантом 1 эталона. `MinHeight="128"` (`:7`) не мешает.

### C4. Ширина и шапка

- `StripResizeGeometry`: `DefaultWidth` и `MinimumWidth` — §C6, там же арифметика.
- Кнопки шапки: в стиле `IconButton` (`EdgeStackWindow.xaml:32`) `Width`/`Height` 22 вместо 26; колонки шапки (`:141`) — четыре по 22 вместо четырёх по 30. Итого 88 из 184, на заголовок 96. Иконки 12×13, 14×3, 10×10, 10×10 в 22 помещаются, `CornerRadius="8"` оставить.
- **Риск:** «● Snapik 26» при двузначном счётчике ≈ 102 px > 96. Поставить `TextTrimming="CharacterEllipsis"` на `TextBlock` «Snapik» (`:144`) и уменьшить `Padding` счётчика (`:145`) с `6,2` до `5,2`. Проверить глазами на 26 снимках (F6).
- Кламп сохранённой ширины: `ClampWidth` уже поднимает снизу до `MinimumWidth` (`StripResizeGeometry.cs:53`) — сохранённые 208 подтянутся сами, отдельного кода не надо.

### C5. Перетаскивание за любое свободное место

`Shell` (`:134`) уже залит `SurfaceBrush`, то есть участвует в hit-test. Достаточно:

- на `Shell` добавить `MouseLeftButtonDown="OnShellMouseDown"`;
- шапке (`:138`) дать `Background="Transparent"` и снять с неё собственный `MouseLeftButtonDown="OnHeaderMouseDown"` — событие всплывёт до `Shell`;
- `OnHeaderMouseDown` (`:1672`) переименовать в `OnShellMouseDown` и защитить: `if (e.LeftButton != MouseButtonState.Pressed || e.ClickCount > 1) return; DragMove();`.

Нажатие забирают себе, как и сейчас: кнопки шапки и «Новый снимок» (`Button` помечает событие обработанным), карточки (`ListBoxItem` обрабатывает `MouseLeftButtonDown` при выборе), `WidthGrip` и `CornerGrip` (`Thumb`, объявлены в `Grid` после `Shell`, выигрывают hit-test), скроллбар. Пустое место списка `ListBox` сам не обрабатывает, событие всплывает до `Shell` — «промежутки между карточками» тянут, как просит ТЗ. `PreviewMouseLeftButtonDown="OnCaptureListMouseDown"` (`:173`) только запоминает точку и не помечает событие — не мешает.

Курсор: `Shell` курсора не задаёт, остаётся стрелка. `Cursor="Hand"` есть только у `Capsule` (`:338`) и у кнопок — их не трогаем.

### C6. Поля под тень

**Противоречие (§0.1) и предложение.** Правило C6 — поле ≥ радиус размытия + сдвиг. У окна `BlurRadius="24" ShadowDepth="5"` → 12 + 5 = 17 → поле 20. Нарисованная панель 204, список 184, карточка 168. Значит окно = 204 + 2×20 = **244**, а не 224. Цифра 224 в C4 и в подписи эталона получена при старом поле 10.

Рекомендую взять за истину то, что пользователь видит (панель 204 / карточка 168), и сделать:

```csharp
internal const double ShadowMargin = 20;          // Shell Margin, Capsule Margin, поле под тень
internal const double MinimumPanelWidth = 204;    // видимая панель
internal const double MinimumWidth = MinimumPanelWidth + 2 * ShadowMargin;  // 244
internal const double DefaultWidth = MinimumWidth;                          // 244
internal const double EdgeGap = 0;                 // было 10: зазор до края экрана теперь даёт ShadowMargin
internal const double EstimatedChromeHeight = 160; // было 140: вертикальный хром вырос на 20
```

Видимый зазор ленты до края экрана остаётся прежним (был 10 поля + 10 `EdgeGap`, стал 20 поля + 0). `PositionAtEdge` (`:742`), `ExpandFromCapsule` (`:687`), `PositionCapsuleAtEdge` (`:696`) формулу не меняют — меняются константы. Если Никита решит держать окно 244 и зазор 30, достаточно вернуть `EdgeGap = 10`; это развилка на одну строку, вынес в §9.

Дальше по XAML:

- `Shell Margin="10"` → `"20"` (`:134`). Тень окна (`:135`) без изменений.
- `Capsule Margin="10"` → `"20"` (`:337`): у неё `BlurRadius="18" ShadowDepth="4"` → 9 + 4 = 13, 20 с запасом, и `PositionCapsuleAtEdge` считает от `ActualWidth`, так что формула сходится сама.
- `WidthGrip Margin="10,22,0,22"` → `"20,22,0,22"` (`:356`), `CornerGrip Margin="10,0,0,10"` → `"20,0,0,20"` (`:367`) — ручки сидят на видимом крае панели.
- `CaptureList Padding="0,0,0,52"` → `"8,14,8,52"` (`:168`). Список 184, паддинг 8+8, карточка 168 при `Margin="0,0,8,0"`… **внимание:** у карточки уже есть правое поле 8 (`:235`) под скроллбар. С `Padding="8,14,8,52"` полная ширина под карточку = 184 − 16 = 168, и правое поле карточки 8 отняло бы ещё 8 → 160. Поэтому вместе с паддингом списка правое поле карточки убрать: `Margin="0,0,0,-48"`, а при наведении/выделении — `"0,4,0,4"` (было `"0,4,8,4"`). Скроллбар живёт в правых 8 px паддинга списка, карточку не трогает — ровно то, что требует C2.
- Тени только у карточки и у окна: полоса подписи (`:248`), бейдж (`:250`), `DeleteButton` (`:263`) эффектов не имеют — проверено, менять нечего.

### C7. Прятаться только от своих снимков

Удалить `_ = SetWindowDisplayAffinity(handle, 0x00000011);` (`EdgeStackWindow.xaml.cs:244`) и саму декларацию `DllImport` (`:1842-1843`), если она больше нигде не нужна (по grep — нигде). `HideForCapture` (`:612-618`) остаётся как есть: он прячет все окна кроме редактора, ждёт кадр рендера и `DwmFlush()`, то есть ленты в нашем снимке нет физически. Ставить временный флаг на время `HideForCapture` не нужно и вредно: окно в этот момент скрыто, а лишний `SetWindowDisplayAffinity` на слоёное окно с `AllowsTransparency` даёт лишнюю перерисовку.

Проверка: Win+Shift+S и Print Screen видят ленту (F8).

### C8 (лента-часть). Снимок всего экрана ложится в ленту

**Редактор сразу или в ленту — предлагаю в ленту, без редактора.** Обоснование: эталон `reference-png/05` разбит на три шага, шаг 2 прямо назван «Клик по карточке»; ТЗ говорит «ложится в ленту как обычный снимок» и отдельно «клик по карточке открывает редактор»; клавиша «весь экран» — жест «схвати всё прямо сейчас», и полноэкранный редактор поверх картинки 3840×1125 его смысл убивает; текущий `SaveFullscreenAsync` тоже работает без единого клика. Редактор области открывается сразу по другой причине — там пользователь и так уже в модальном выделении.

**Что делает обычный путь после захвата области** (`CaptureLoopAsync`, `:535-570`): `HideForCapture()` → `OverlayEditorWindow.CaptureNewAsync` (внутри неё `_workspace.AddImageAsync`, `OverlayEditorWindow.Save.cs:85`) → `Captures.Add` → `Renumber()` → `NoteStripGrowth()` → `InvalidatePrepared()` → `UiSoundService.Capture` → `SaveAndCopyCommittedPackageAsync()` → `AutoSaveCaptureAsync(capture)`.

`SaveFullscreenAsync` (`EdgeStackWindow.Saving.cs:39-57`) переписывается на тот же хвост, минус редактор:

```csharp
private async Task CaptureFullscreenAsync()
{
    await _pasteIntentTransition;
    if (CaptureIsBlockedByADialog("fullscreen capture")) return;
    if (_busy) return;
    if (StripIsFull()) return;
    _busy = true;
    try
    {
        HideForCapture();
        await Task.Delay(120);
        var frame = CaptureOverlay.CaptureDesktopFrame(_settings.CaptureCursor);
        var capture = await _workspace.AddImageAsync(frame.Image);
        capture.Kind = CaptureKind.Fullscreen;
        capture.Title = FullscreenTitle;                                   // "весь экран", не через UiLanguage
        capture.MonitorCount = WinForms.Screen.AllScreens.Length;
        Captures.Add(capture);
        Renumber(); NoteStripGrowth(); InvalidatePrepared();
        UiSoundService.Capture(_settings);
        await SaveAndCopyCommittedPackageAsync();
        await AutoSaveCaptureAsync(capture);
    }
    catch (Exception ex) { SetStatus($"{UiLanguage.Text("Не удалось снять экран")}: {ex.Message}", true); }
    finally { _busy = false; ShowStackWithoutActivation(); }
}
```

Точка вызова — `OnHotkey` (`:284`, `e.Id == "fullscreen-save"`), id клавиши не меняем (это формат настроек).

**Последствие:** прямая запись в папку (`LocalImageSave.WriteAsync`, `Saving.cs:52`) уходит, файл теперь пишет `AutoSaveCaptureAsync`. При выключенном «Автоматически сохранять готовые снимки» снимок экрана в папку больше не падает. Это ровно то, что просит ТЗ («в папку он попадает автосохранением, как все остальные»), и это же оправдывает переименование клавиши.

**Чип «экран» на карточке.** В полосе подписи (`:248-260`), справа, `HorizontalAlignment="Right"` в отдельной колонке `Grid` или через `DockPanel`; числа с `reference-html/05`: высота 16, `CornerRadius="8"`, `Padding="6,0"`, зазор 4, фон `#1FFFFFFF` (белый 12 %), шрифт 11 (в эталоне 10 при 11-м соседнем — берём 11 к соседям), цвет `#DCE3ED`. Иконка монитора 11×10, `viewBox 0 0 12 11`, `Data="M1,1 L11,1 L11,8 L1,8 Z M4,10 L8,10 M6,8 L6,10"`, `Stroke="#DCE3ED" StrokeThickness="1.3" StrokeLineJoin="Round"`. Видимость — `Collapsed` по умолчанию, `DataTrigger Binding="{Binding Kind}" Value="Fullscreen"` → `Visible`. Глиф сверить с Segoe Fluent Icons по правилу D2 (это дорожка D, но чип мой — при расхождении беру глиф из Fluent).

**Широкая миниатюра.** `Image Stretch="UniformToFill"` (`:247`) режет 3840×1125 (3.41) в коробке 168×78 (2.15) по бокам, а эталон показывает оба монитора целиком. Тем же `DataTrigger` по `Kind=Fullscreen` ставить `Stretch="Uniform"`.

**`prompt.md`.** Отдельного кода не нужно: `PromptGenerator` уже пишет `Снимок {буква} — {Title}.` (`src/Snapik.Core/Exporting/PromptGenerator.cs:31-37`). При `Title = "весь экран"` получается «Снимок C — весь экран.», при `Title = "IMG_0512.png"` — «Снимок D — IMG_0512.png.», дальше комментарии как обычно. Импорт заполняет `Title = Path.GetFileName(path)` в `ImportFileAsync` (`:1060`) и `Kind = CaptureKind.Import`.

**Название клавиши.** `HotkeySettingsWindow.xaml:43` и `:44`: «Скриншот всего экрана в папку» → «Снимок всего экрана». Пара в `UiLanguage.cs:47` и строка проверки в `SmokeTestRunner.cs:339` — заменить, старую пару удалить. Чип «Предложить: Print Screen» и выключенное по умолчанию состояние не трогаем.

### C8 (модель). Вид снимка — кандидат на «Изменение формата»

Что нужно редактору (дорожка D) и что откуда берётся:

| Данные | Где живут | Новое? |
|---|---|---|
| вид снимка (область / весь экран / импорт) | `CaptureKind Kind` | да |
| исходный размер | `PixelWidth`/`PixelHeight` (`Core/Models/CaptureItem.cs:8-9`), в приложении `Image.PixelWidth/PixelHeight` | нет |
| число мониторов | `int MonitorCount` | да |
| имя файла / подпись | `string Title` (`Core/Models/CaptureItem.cs:12`) | поле есть, но не заполняется |

`Title` уже есть в формате и уже уходит в `prompt.md`, но `EditorModels.cs:239` кладёт туда `string.Empty`, а `FromCore` (`:248`) его не читает. Использовать его, а не заводить второе поле под имя файла.

**Абзац «Изменение формата» (черновик для `tasks/verification.md`):**

> **Изменение формата (session.json, prompt.md).** У `CaptureItem` в `Snapik.Core` появляются два поля-`init` со значениями по умолчанию, рядом с существующим `Sent`: `CaptureKind Kind` (enum `Region` | `Fullscreen` | `Import`, по умолчанию `Region`, в JSON строкой camelCase: `"region"`, `"fullscreen"`, `"import"`) и `int MonitorCount` (по умолчанию 0 — «неизвестно»; заполняется только у `Fullscreen` числом мониторов на момент снимка). Поля-`init`, а не параметры конструктора: старые `session.json` без `kind`/`monitorCount` читаются как `Region`/0, `SchemaVersion` остаётся 1, миграция не нужна. Заодно начинает использоваться давно существующее поле `title`: у снимка всего экрана туда пишется литерал `весь экран`, у импорта — имя файла (`IMG_0512.png`), у снимка области оно остаётся пустым. `title` кладёт и читает `CaptureItem.ToCore`/`FromCore` в `EditorModels.cs` (раньше писался `string.Empty` и не читался). Следствие для `prompt.md`: снимок всего экрана и импортированный файл теперь дают строку «Снимок C — весь экран.» / «Снимок D — IMG_0512.png.» даже без комментариев, тогда как раньше снимок без заметок в текст не попадал вовсе (`PromptGenerator.cs:26`). Литерал `весь экран` пишется по-русски всегда и через `UiLanguage` не проходит: `prompt.md` русский целиком. `SessionValidation` новые поля не проверяет; `MonitorCount < 0` при чтении приводится к 0. Mac переносит: `CaptureItem` в `SnapikCore/Models/CaptureItem.swift`, кодирование в `SnapikJson.swift`, заполнение title/kind в местах добавления снимка.

Приложение: в `EditorModels.cs` у `CaptureItem` появляются `Kind`, `MonitorCount`, `Title` (все с `OnPropertyChanged` — чип и подпись на них смотрят); все три обязаны попасть в `DeepClone()` (`:223-230`), `Snapshot()`/`Restore()` (`:221`, `:254-262`, а значит и в `record CaptureSnapshot`, `:268`), `ToCore()`, `FromCore()`. Правило «новое поле модели обязано попасть в клон» — из `tasks/tz-002-plan.md` п. 19.

### C9. «Импортировать файл» падает

**Диагноз подтверждён.** `SessionWorkspace.LoadBitmap` (`:274-293`) возвращает `decoder.Frames[0]`, то есть `BitmapFrameDecode`. `Freeze()` на кадре не отвязывает его от декодера: декодер остаётся `DispatcherObject` с привязкой к UI-потоку, а `BitmapFrame.Create(frozenSource)` внутри `EncodePngAsync` (`:157-171`, `Task.Run`) лезет за метаданными и превью в этот самый декодер. Отсюда «The calling thread cannot access this object because a different thread owns it». Путь ровно один: `ImportFileAsync:1060` → `AddImageAsync:139-147` → `EncodePngAsync`.

**Код:**

```csharp
public static BitmapSource LoadBitmap(string path)
{
    using var stream = File.OpenRead(path);
    try
    {
        var decoder = BitmapDecoder.Create(stream, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad);
        if (decoder.Frames.Count == 0) throw new NotSupportedException(UiLanguage.Text("Формат не поддерживается системой"));
        // Копия, а не кадр: кадр декодера тянет за собой сам декодер, а тот принадлежит UI-потоку,
        // и Freeze() этого не снимает. EncodePngAsync кодирует в пуле, и BitmapFrame.Create там
        // лезет в метаданные кадра — это и есть падение импорта в 1.4.0.
        var copy = new WriteableBitmap(decoder.Frames[0]);
        copy.Freeze();
        return copy;
    }
    catch (Exception ex) when (ex is NotSupportedException or FileFormatException)
    {
        throw new InvalidOperationException(UiLanguage.Text("Формат не поддерживается системой"), ex);
    }
}
```

`WriteableBitmap(BitmapSource)` копирует пиксели в собственный буфер и палитру, ссылки на декодер не держит; `using var stream` закрывает поток до возврата, `BitmapCacheOption.OnLoad` это разрешает.

Ту же правку сделать в `WpfExportImageRenderer.LoadBitmap` (`:51-58`) — там тот же кадр, и `RenderAsync` уже сегодня зовётся из `FileExportService` вне UI-потока.

### A7. Лента после «Начать» и «Пропустить»

`ShowStackWithoutActivation()` **есть**: `EdgeStackWindow.xaml.cs:620`, `private`; публичная обёртка `RevealStack()` — `:635`. Вызывать её.

Мастер открывается из `OnLoaded` (`:209-210`) синхронно через `ShowDialog` (`ShowOnboarding`, `:1172-1215`), лента к этому моменту скрыта (`Hide()`, `:200`), а `PositionAtEdge()` (`:223`) только считает геометрию и `Show()` не делает. Ветка `howToOnly` выходит раньше (`:1186`) — трей не трогаем.

Правка: в `OnLoaded` запомнить факт показа мастера и после `PositionAtEdge()` (`:223`) позвать `ShowStackWithoutActivation()`, а не сразу после `ShowDialog` — иначе лента мелькнёт до восстановления сессии и `ShowStackWithoutActivation` отработает дважды. Различать «Начать» и «Пропустить» не надо: ТЗ требует ленту в обоих случаях, а `OnboardingWindow` и так закрывается одинаково (`_closedByButton`, `:34`). Для пункта E2 («Пройти знакомство заново», дорожка E) `ShowOnboarding()` зовётся из настроек, где лента уже видна — там дополнительный вызов безвреден, но лучше сделать `ShowOnboarding` возвращающим `bool wizardShown` и решать на стороне вызывающего.

---

## 2. Строки RU/EN для `UiLanguage.cs`

| RU | EN | Где |
|---|---|---|
| `Нажми {0} или «Новый снимок»` | `Press {0} or "New capture"` | C3, пустая лента |
| `Нажми «Новый снимок»` | `Press "New capture"` | C3, клавиша выключена |
| `экран` | `screen` | C8, чип карточки |
| `Снимок всего экрана` | `Whole-screen capture` | C8, название клавиши |
| `Не удалось снять экран` | `The screen could not be captured` | C8, ошибка |

Удалить: `Скриншот всего экрана в папку` / `Save the whole screen to a folder` (`UiLanguage.cs:47`, `SmokeTestRunner.cs:339`), `Не удалось сохранить экран` (`Saving.cs:55`, сейчас вообще без пары — заодно чиним). Литерал `весь экран` в `Title` — данные, в таблицу не идёт.

---

## 3. Тесты

Только на новую логику, UI-тестов не пишем.

`tests/Snapik.App.Imaging.Tests/StripResizeGeometryTests.cs`:

1. `The_panel_keeps_its_width_when_the_shadow_field_grows` — `MinimumWidth - 2 * ShadowMargin == MinimumPanelWidth` (244 − 40 = 204) и `DefaultWidth == MinimumWidth`.
2. `A_width_saved_by_an_older_version_is_lifted_to_the_minimum` — `ClampWidth(208, 1920) == 244`, `ClampWidth(400, 1920) == 400`.
3. `The_card_fits_the_list` — вспомогательный `CardWidth(windowWidth) = windowWidth − 2*ShadowMargin − 2*ShellPadding − 2*ListPadding`: при 244 даёт 168.
4. Существующие тесты `WidthFromStart`/`ListHeightFromStart` перечитать: они написаны на числах 260/1920 и от констант не зависят, кроме `MinimumWidth` в `[InlineData]` (`:18`) — там `nameof`-ссылка на константу, менять не надо.

`tests/Snapik.Core.Tests/` (новый файл `CaptureKindTests.cs` или строки в существующий):

5. `An_old_session_without_a_kind_reads_as_a_region` — десериализовать JSON снимка без `kind`/`monitorCount`, ожидать `CaptureKind.Region` и `0`.
6. `The_kind_round_trips_as_a_camel_case_string` — сериализовать `Fullscreen` → `"fullscreen"`, прочитать назад.
7. `A_screen_capture_names_itself_in_the_prompt` — `PromptGenerator` на снимке с `Title = "весь экран"` и без заметок даёт строку `Снимок A — весь экран.`; на снимке с пустым `Title` и без заметок — пустой результат (регресс на `PromptGenerator.cs:26`).

`tests/Snapik.App.Imaging.Tests/` (копирование битмапа, C9):

8. `An_imported_frame_encodes_on_a_background_thread` — записать временный PNG и JPG, `SessionWorkspace.LoadBitmap`, затем `await Task.Run(() => { var e = new PngBitmapEncoder(); e.Frames.Add(BitmapFrame.Create(loaded)); e.Save(Stream.Null); })` — раньше кидало `InvalidOperationException`. Тест ставится в STA-проект `Snapik.App.Imaging.Tests`, там уже есть WPF-зависимости.
9. `A_copied_frame_keeps_its_size_and_is_frozen` — размеры и `IsFrozen` совпадают с исходником.

---

## 4. Smoke (`SmokeTestRunner.cs`)

- `:339` — заменить пару строк названия клавиши.
- `:33` — `StackWidth = 240` в тестовых настройках меньше нового минимума 244; заменить на 260, иначе проверка «ширина сохраняется» будет молча ловить кламп.
- Добавить шаг: снимок с `Kind = Fullscreen`, `Title = "весь экран"`, `MonitorCount = 2` проходит `PrepareAsync` и даёт в `prompt.md` строку «Снимок A — весь экран.» (рядом с `VerifyLineStyleReachesThePngAsync`, `:1138`).
- Добавить шаг: `SessionWorkspace.LoadBitmap` + `AddImageAsync` на настоящем файле с диска (сейчас `:496` только декодирует, `:769` идёт от `CreateDemoBitmap` и мимо бага).

---

## 5. Файлы зоны C

`src/Snapik.App/EdgeStackWindow.xaml`, `EdgeStackWindow.xaml.cs`, `EdgeStackWindow.Saving.cs`, `Controls/StripResizeGeometry.cs`, `SessionWorkspace.cs`, `WpfExportImageRenderer.cs`, `HotkeySettingsWindow.xaml` (+`.xaml.cs`, только текст названия клавиши).

Общие с другими дорожками: `UiLanguage.cs` (все дорожки дописывают строки в свои места таблицы, конфликт мержа не по одной строке), `SmokeTestRunner.cs`, `EditorModels.cs` (дорожка D правит `AnnotationItem`, я — `CaptureItem`; разные классы одного файла), `src/Snapik.Core/Models/CaptureItem.cs` (только я), `Themes/Palettes/*.xaml` (токены ползунка — дорожка B), `tests/`, `tasks/verification.md`. `App.xaml.cs` не трогаю.

---

## 6. Общий фундамент до параллельной работы

Три коммита одним заходом, до того как дорожки C и D разойдутся:

1. **Модель вида снимка.** `CaptureKind` + `Kind` + `MonitorCount` в `Core/Models/CaptureItem.cs`, проброс `Kind`/`MonitorCount`/`Title` в `EditorModels.cs` (`ToCore`, `FromCore`, `DeepClone`, `Snapshot`, `Restore`, `CaptureSnapshot`), тесты 5-7, абзац «Изменение формата» в `tasks/verification.md`. Без этого дорожка D не может ни нарисовать подпись, ни выбрать режим масштаба.
2. **Фикс `LoadBitmap`.** `SessionWorkspace.cs:274-293` и `WpfExportImageRenderer.cs:51-58`, тесты 8-9. Без него импорт не открывается ни в чьей ветке.
3. **Константы `StripResizeGeometry`.** `ShadowMargin`, `MinimumPanelWidth`, новые `MinimumWidth`/`DefaultWidth`/`EdgeGap`/`EstimatedChromeHeight`, тесты 1-3. Дорожка D берёт из них поля под тень для поповеров редактора (C6 распространяется и на них).

Остальное (C1, C2, C3, C4, C5, C7, C8-лента, A7) живёт внутри `EdgeStackWindow.*` и параллелится свободно.

---

## 7. Риски

- **C1, отключённая виртуализация.** 26 карточек с `DropShadowEffect` каждая — 26 живых эффектов вместо ~8. `DropShadowEffect` на GPU дешёвый, но замерить прокрутку на 125 % в приёмке (F6).
- **C1, `CanContentScroll="False".`** Прокрутка становится попиксельной; `OnCaptureListMouseDown`/`MouseMove` (`:1712-1725`) используют `e.GetPosition(CaptureList)` — координаты те же, перетаскивание карточек не ломается, но проверить перенос карточки при прокрученном списке.
- **C4.** Заголовок «Snapik 26» на границе 96 px, см. §C4.
- **C6.** Смена `MinimumWidth` с 200 на 244 сдвигает ленту у всех, кто тянул её вручную; сохранённая ширина поднимется, панель при этом станет на 20 px уже, чем была. Ожидаемо, но Катя это заметит — назвать в письме.
- **C8.** Снимок экрана перестаёт писаться в папку при выключенном автосохранении (§C8).
- **C9.** `WriteableBitmap(BitmapSource)` для индексированных форматов (GIF, 8-битный BMP) держит палитру — проверить импортом GIF и 8-битного PNG в приёмке (F10).

---

## 8. Точки стыка

**С дорожкой B (палитры).** Нужны два токена в каждой из шести палитр: `ScrollThumbBrush` и `ScrollThumbHoverBrush`. Для пяти тёмных — `#47FFFFFF` (белый 28 %) и `#73FFFFFF` (45 %), как требует C2. Для `dawn` — тот же процент от `#000000`: `#47000000` и `#73000000`. Пока токенов нет, `StackScrollBar` продолжает брать `TextFaintBrush`/`TextMutedBrush` и ничего не ломает.

**С дорожкой D (редактор).** Контракт: `CaptureItem.Kind` (`Region`/`Fullscreen`/`Import`), `CaptureItem.MonitorCount`, `CaptureItem.Title`, размер из `Image.PixelWidth/PixelHeight`. Редактор открывается существующим `OverlayEditorWindow.EditExistingAsync(_workspace, capture, labelIndex)` (`:1690`) — сигнатуру не меняю; если D нужен вид снимка, он читает его у `capture`, а не через новый параметр. Состав подписи («весь экран · 2 монитора · 3840×1125» против эталонного «весь экран · 3840×1125», §0.9) — решение D.

**С дорожкой A (мастер).** A7 трогает `OnLoaded` (`:205-230`) и `ShowOnboarding` (`:1172-1215`) — те же методы правит A по пунктам A1-A6 только внутри `OnboardingWindow.*`. Пересечение одно: если A сделает `ShowOnboarding` возвращающим результат ради E2, договориться о сигнатуре заранее.

---

## 9. Открытые вопросы для Никиты

1. **Окно 244 вместо 224** (§C6): берём панель 204 и поле 20, или оставляем окно 224 и сокращаем тень окна до `BlurRadius 16 / ShadowDepth 3` (поле 10 тогда хватает, но тень заметно жёстче)? Рекомендую первое.
2. **Зазор до края экрана**: `EdgeGap = 0` (видимый зазор остаётся 20, как сейчас) или `EdgeGap = 10` (станет 30)? Рекомендую 0.
3. **Литерал `весь экран` в `session.json`** (§C8-модель): согласны, что `Title` остаётся русским всегда, раз `prompt.md` русский целиком?

---

## 10. Перенос на macOS

Зеркалить после того, как Windows-часть закоммичена (`macos/SYNC.md`, диффом от очередного `mac-sync-base-N`).

**Core (`macos/Sources/SnapikCore/`):**
- `Models/CaptureItem.swift` — `enum CaptureKind { case region, fullscreen, `import` }` (raw values `"region"`, `"fullscreen"`, `"import"`), поля `kind` (default `.region`), `monitorCount` (default 0); `title` начинает заполняться.
- `Serialization/SnapikJson.swift` — декодирование с `decodeIfPresent` и дефолтами, чтобы старые `session.json` читались; ключи camelCase, как на Windows.
- `Exporting/PromptGenerator.swift` — кода не меняет, но получает новое поведение через `title`; тест на «Снимок A — весь экран.» перенести.
- `Models/SessionValidation.swift` — новые поля не валидирует, `monitorCount < 0` → 0.

**`macos/Sources/SnapikMac/Stack/`:**
- `StackMetrics.swift` — `width` 208 → 244, добавить `shadowMargin = 20`, `panelWidth = 204`, `cardWidth = 168`, `listPadding = (8, 14, 8, 52)`, `edgeGap = 0`; `cardHeight 78`, `cardOverlap 48`, `cardStep 30`, `listMaxHeight 372` без изменений.
- `EdgeStackContentView.swift` — порядок карточек (новая поверх старой: на AppKit это порядок `subviews`, последняя рисуется сверху; аналог снятия `Panel.ZIndex`), полоса подписи наверх карточки, тень карточки вверх (`shadowOffset` с положительным `height` в координатах AppKit), пустая лента 92 px с подсказкой, чип «экран» по `kind == .fullscreen`, широкая миниатюра (`.resizeAspect` вместо `.resizeAspectFill`).
- `ThumbnailCardView.swift` — чип, полоса сверху, тень, снятие правого поля 8 в пользу паддинга списка.
- `EdgeStackWindowController.swift` — поле под тень 20 в позиционировании у края, перетаскивание окна за любое свободное место панели (`isMovableByWindowBackground` или `mouseDown` → `performDrag`), пустая лента без ручки угла, показ ленты после мастера.
- `App/WindowCaptureExclusion.swift` — прямого аналога C7 нет: на macOS исключение из захвата делается через `sharingType`; решение «прячемся только от своих снимков» переносится как снятие постоянного исключения, а не как отдельный флаг.
- Импорт (C9) аналога не имеет: у `CGImageSource` нет привязки к потоку, переносится только заполнение `title`/`kind` в точке импорта и снимка экрана.
