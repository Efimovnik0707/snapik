# План по ТЗ №6 (раунд tz-007): дорожка B — лента

Пункты: **B1** (прокрутка к последнему снимку), **B2** (карточки: прозрачная растяжка, раскрытие по наведению, цвета из темы, один радиус), **B3** (угол ленты не схлопывается), **B4** (копия одного снимка: правая кнопка по карточке и кнопка в редакторе).

Зона дорожки: `src/Snapik.App/EdgeStackWindow.xaml`, `EdgeStackWindow.xaml.cs`, `EdgeStackWindow.Saving.cs`, `Controls/StripResizeGeometry.cs`, `HotkeySettings.cs`, `SessionWorkspace.cs`.

Общие файлы (конфликтные, см. §2): `UiLanguage.cs`, `SmokeTestRunner.cs`, `tests/Snapik.App.Imaging.Tests/StripResizeGeometryTests.cs`, `tasks/verification.md`. Только чтение: `WpfExportImageRenderer.cs`, `PromptGenerator.cs`, `FileExportService.cs`, `WindowsClipboardService.cs`, `Themes/Palettes/*.xaml` (по B2.3 правок в палитрах не требуется, см. §0.в).

Не моё: A1 (`HotkeySettingsWindow.xaml`), C1/C2 (`AnnotationCanvas.cs`, `NoteBadgeGeometry.cs`, `OverlayEditorWindow.Appearance.cs`, `OverlayEditorWindow.Shapes.cs`), D1/D2 (`UiSoundService.cs`, `Controls/AppearancePicker.*`). Исключение — одна кнопка в `OverlayEditorWindow.xaml` и одна строка в `EditorShortcuts.cs` по B4.2, см. §2.

**Сверка адресов.** ТЗ ссылается на `dea725a`; после него в `src/` вошли `53c921d`, `a3861c7`, `1df53ce`. `git diff dea725a HEAD -- src/Snapik.App/EdgeStackWindow.xaml.cs` пуст, `EdgeStackWindow.xaml` изменился одним атрибутом (`RenderOptions.BitmapScalingMode` у `ThumbImage`, `:281`) без сдвига строк. Поэтому все адреса ленты из ТЗ действительны на HEAD, кроме двух, которые в ТЗ были округлены: `OnCornerDragDelta` — `:923-940` (в ТЗ `:928-940`), `OnCornerDragCompleted` — `:942-951` (в ТЗ `:941-950`). Адреса редактора (`OverlayEditorWindow.xaml.cs`) после `1df53ce` сдвинулись на +32 строки; из моих пунктов это задевает только B4.2, там адреса ниже даны по HEAD.

---

## 0. Где картина шире или причина другая, чем в ТЗ

### а) B2: раскрытие через `Margin` **можно вернуть как есть** — причина, по которой его сняли в 1.6.0, исчезла в том же раунде

ТЗ предлагает два пути («`RenderTransform`/отрицательный отступ соседей, не трогая Measure» либо «считать высоту по `Captures.Count`»), и открытый вопрос G/B2 говорит: «если раскрытие через Measure всё-таки меняет высоту списка — фиксировать список на `ListHeightForCount(Captures.Count)`». **Второе уже сделано и лежит в коде с 1.6.0.**

`ApplyListHeight` (`EdgeStackWindow.xaml.cs:826-832`) присваивает `CaptureList.Height` явным числом, посчитанным из `Captures.Count` и потолка настроек (`StripResizeGeometry.ListHeightForCount`, `Controls/StripResizeGeometry.cs:67-73`). Панель списка не измеряется вообще. Окно на `SizeToContent="Height"` (`EdgeStackWindow.xaml:7`) следует за этим явным числом, а не за содержимым `StackPanel`. Вызывается `ApplyListHeight` только из `UpdateEmptyState` (`:1515`), `PlaceStripInitially` (`:845`), `EnsureStripPlaced` (`:860`) и `OnCornerDragCompleted` (`:950`) — ни одного пути от наведения мышью (проверено графом, `trace_call_path ApplyListHeight inbound depth 3`: `EnsureStripPlaced`, `OnCornerDragCompleted`, `PlaceStripInitially`, `UpdateEmptyState`, дальше `Renumber`/`ShowStackWithoutActivation`/`ExpandFromCapsule`/`OnLoaded`).

Хронология, почему комментарий `:349-354` («the margin they used to unfold it with is part of Measure») звучит строже, чем есть: в прошлом раунде сеттеры `Margin` сняли коммитом `74fdbf6` (B-2), а `ApplyListHeight` появился **следующим** коммитом `5f2dc23` (B-3) — `tasks/tz-006-notes-B.md:14-15`. То есть запрет писался под ленту, у которой высота ещё зависела от содержимого. Сейчас не зависит.

**Рекомендация: раскрывать честным `Margin` раскрываемой карточки, `-48 → 0`, анимацией `ThicknessAnimation`.** Почему не `RenderTransform` соседей:

1. `RenderTransform` не входит в `Extent` прокрутки. Панель уже несёт `Margin="0,0,0,48"` (`EdgeStackWindow.xaml:252`) ровно под свес последней карточки, и этот запас занят. Сдвиг соседей трансформом на 48 вынес бы низ последней карточки за `Extent`, и требование ТЗ «прокрутка доступна» (B2.2) перестало бы выполняться: прокручивать некуда, `ScrollableHeight` не вырос.
2. `Margin` у одной карточки увеличивает `DesiredSize` панели на 48 → `Extent` растёт на 48 → соседи ниже съезжают в настоящей раскладке ровно на 48 (вариант 1 «раздвигает»), а прокрутка достаёт до низа.
3. Высота списка при этом не меняется — см. выше. Окно тоже: `SizeToContent` меряет внешний `Grid`, в котором у `ListBox` жёсткая `Height`.
4. Эталон подтверждает геометрию: в артборде «Наведение · вариант 1» карточки стоят на `top` 14 / 44 / **74 (наведённая, на своём месте)** / 152 / 182 / 212, то есть у наведённой верх не двигается, а следующие смещены ровно на 48. Это и есть поведение `Margin.Bottom: -48 → 0` в `StackPanel`. Контейнер артборда — `height: 250; overflow: hidden`, и низ F (212+78=290) в нём обрезан: эталон прямо рисует «список не вырос, низ ушёл за край».
5. Высота контейнера эталона 250 совпадает с нашей формулой для шести карточек: `14 + 5·30 + 78 + 8 = 250`. Формула не пересматривается.

**Задержка 150 мс и анимация 120–150 мс в WPF.** `Margin` — это `Thickness`, `DoubleAnimation` по нему невозможна, нужна `ThicknessAnimation`. Задержка делается `BeginTime` у самой анимации (или у `Storyboard`), а отмена — `StopStoryboard`/`RemoveStoryboard` в `ExitActions`:

```xml
<DataTrigger Binding="{Binding IsMouseOver, ElementName=ThumbCard}" Value="True">
    <DataTrigger.EnterActions>
        <BeginStoryboard x:Name="UnfoldCard">
            <Storyboard>
                <!-- BeginTime — это и есть «задержка 150 мс»: пока она не истекла, ничего не
                     нарисовано, а уход курсора снимает сториборд целиком. -->
                <ThicknessAnimation Storyboard.TargetName="ThumbCard" Storyboard.TargetProperty="Margin"
                                    To="0,0,0,0" BeginTime="0:0:0.15" Duration="0:0:0.13"
                                    FillBehavior="HoldEnd">
                    <ThicknessAnimation.EasingFunction><CubicEase EasingMode="EaseOut" /></ThicknessAnimation.EasingFunction>
                </ThicknessAnimation>
            </Storyboard>
        </BeginStoryboard>
    </DataTrigger.EnterActions>
    <DataTrigger.ExitActions>
        <StopStoryboard BeginStoryboardName="UnfoldCard" />
        <BeginStoryboard>
            <Storyboard>
                <ThicknessAnimation Storyboard.TargetName="ThumbCard" Storyboard.TargetProperty="Margin"
                                    To="0,0,0,-48" Duration="0:0:0.13" FillBehavior="HoldEnd" />
            </Storyboard>
        </BeginStoryboard>
    </DataTrigger.ExitActions>
    <Setter TargetName="ThumbCard" Property="BorderBrush" Value="{DynamicResource TextFaintBrush}" />
    <Setter TargetName="DeleteButton" Property="Opacity" Value="1" />
</DataTrigger>
```

**Быстрый проезд курсора.** До `BeginTime` анимация не трогает свойство — `StopStoryboard` в `ExitActions` снимает её, и карточка, мимо которой курсор проехал за 80 мс, не шевельнётся. Складывание без задержки, как требует ТЗ. Отдельно: раскрытие карточки не сдвигает её саму, поэтому курсор после раскрытия остаётся над той же карточкой — колебания «раскрылось → курсор ушёл → сложилось → раскрылось» невозможны. Хит-тест даёт `IsMouseOver` ровно одной карточке (карточки-соседи лежат ниже по z-порядку и в путь попадания не входят), так что двух раскрытых одновременно не бывает.

**Урок tz-005 C1 (сеттер против анимации) здесь не срабатывает**: на `Margin` нет ни одного `Setter`, только две анимации, и они не спорят. Но правило надо соблюсти буквально — `Margin` в сеттерах триггеров не появляться (`BorderBrush` и `Opacity` сеттерами можно, как сейчас).

**По выбору и фокусу не раскрывать (B1 из ТЗ №5 остаётся).** Триггер `IsSelected` в шаблоне удалён в прошлом раунде, возвращать нечего; `IsKeyboardFocusWithin` (`:359-361`) держит только `DeleteButton.Opacity` — анимацию к нему не подвешивать. `capture.IsSelected` ставится и снимается в `OnOpenCaptureClick` (`:1860`, `:1886`) и ничем не читается.

**Цена.** Анимация `Margin` — это раскладка панели на каждом кадре (26 карточек, у каждой `DropShadowEffect`). 130 мс ≈ 8 проходов. На 26 карточках это надо посмотреть живьём; если дёргается — уменьшать не `Margin`, а число карточек в раскладке нечем, и тогда запасной ход только вариант 2 («поверх», `RenderTransform` самой карточки + `Panel.ZIndex`), который Катя не выбрала. Отмечаю как риск, а не как развилку.

### б) B2: плашка в эталоне выше и с тремя стопами, а не «55 % → 0» на 26

ТЗ говорит «растяжка сверху вниз 55 % → 0 высотой 30». В `reference-html` буквально:

```
height: 30px;
background: linear-gradient(180deg, rgba(20,24,30,0.55) 0%, rgba(20,24,30,0.28) 60%, rgba(20,24,30,0) 100%);
```

Три стопа, средний `0.28` на 60 %. И высота 30, а не сегодняшние 26 (`EdgeStackWindow.xaml:286`): плашка занимает всю видимую полосу карточки. Иконка и число в эталоне белые `#FFFFFF` (сейчас `#AEB8C7` и `#DCE3ED`, `:296-297`), у группы `drop-shadow(0 1px 1px rgba(0,0,0,.6))`, у числа дополнительно `text-shadow: 0 1px 2px rgba(0,0,0,.7)`; у кружка буквы `box-shadow: 0 1px 3px rgba(0,0,0,.4)` (сейчас тени нет). Рамка наведённой карточки в эталоне `#9AA6B8`, сейчас `#718096` (`:356`).

### в) B2.3: новые кисти тем **не нужны**, и это снимает правку шести файлов

ТЗ допускает «`ElevatedBrush`, `ElevatedLineBrush` или отдельные `CardBrush`/`CardLineBrush` во всех шести палитрах». Проверено: `Themes/Palettes/Dark.xaml:12-13` — `ElevatedBrush = #242A33`, `ElevatedLineBrush = #46505E`. Это **ровно те две константы**, что зашиты в карточку (`EdgeStackWindow.xaml:263-264`). То есть карточку когда-то покрасили значениями тёмной палитры. Замена на `{DynamicResource ElevatedBrush}` / `{DynamicResource ElevatedLineBrush}` на «Тёмной» не меняет ни пикселя и чинит остальные пять. Ни один `Themes/Palettes/*.xaml` не трогаем; комментарий в шапке `Dawn.xaml:4-6` («каждая палитра несёт одни и те же шестнадцать ключей») подтверждает, что новый ключ обязал бы править все шесть.

Значения для сверки: Glass `#1AFFFFFF` / `#38FFFFFF`, Night и Sea и Sunset `#14FFFFFF` + свой тонированный контур, Dawn `#FFFFFF` / `#E3E7ED`. Эталон «после» рисует `rgba(255,255,255,0.10)` и `rgba(255,255,255,0.22)` — это Glass с точностью до округления.

**Заодно: «фиолетовая тема» из ТЗ и F.4 — это `glass`.** `Themes/Palettes/Glass.xaml:9-13` даёт градиент `#5F5C8C → #7E5878 → #58627A`, тот же, которым нарисован фон ленты в `reference-html`. Проверять B2.3 надо на «Стекло» и на «Светлой · Рассвет».

### г) B2.3: радиусы 11/10 арифметически верны — тёмный уголок не от них

`ThumbCard` — `CornerRadius="11"`, `BorderThickness="1"`, внутренний `Grid` клипован радиусом 10 (`:278`). Внутренний радиус = внешний минус толщина рамки, это правильная пара, и «один радиус 11 и 11» сделает хуже: клип полезет на рамку. Эталонный фрагмент ×4 «после» рисует то же правило (внешний 44 при рамке 4 и внутренний 40), хотя подпись говорит «один радиус».

Причина тёмной кромки на `evidence/strip-corner-x6.png` другая: под скруглением видно `Background="#242A33"` карточки и рамку `#46505E` — обе из тёмной палитры, на «Стекле» они читаются как чёрный укус в углу; сплошная плашка `#E6171A20` (90 %) добавляет к этому ещё 26 px черноты сразу под углом. Лечится пунктами (б) и (в), радиусы оставить 11/10. **Это надо сказать вслух в отчёте Кате**, иначе «один радиус» уйдёт в реализацию и вернётся кромкой другого вида.

Чего я не знаю наверняка: по шестикратному фрагменту нельзя развести вклад рамки и вклад фона попиксельно (я не считал альфы, как в прошлом раунде). Утверждение «кромка — это `#242A33`+`#46505E` на фиолетовом» опирается на совпадение констант с `Dark.xaml`, а не на разбор пикселей. Проверка живьём: на «Стекле» кромки быть не должно после (в) даже без (б).

### д) B3: «ручная высота = высота списка» требует нового ключа, но не требует миграции

Сейчас `OnCornerDragCompleted` (`:942-951`) пишет `StackHeight = CaptureList.Height` и зовёт `ApplyListHeight()`, а тот возвращает `min(содержимое, потолок)` — это и есть «доводчик», который прошлый раунд ввёл сознательно (`tasks/tz-006-notes-B.md:15`) и который Катя видит как поломку.

`StackHeight` (`HotkeySettings.cs:39-46`) читается ровно в одном месте — `ApplyListHeight` (`:830`), пишется ровно в одном — `OnCornerDragCompleted` (`:946`) (проверено `grep -rn "StackHeight" src tests`; третье вхождение — round-trip настроек в `SmokeTestRunner.cs:36`). `SettingsMigration` (`src/Snapik.App/SettingsMigration.cs`) про него ничего не знает и знать не должен: новый ключ аддитивный, дефолт `false` = сегодняшнее поведение.

Вариант «`StackHeight = null` для авто» отвергаю: `double` пришлось бы сделать `double?`, это меняет тип уже записанного ключа, старые файлы читаются, но новый файл старым билдом — уже нет (`null` вместо числа). Флаг рядом безопаснее в обе стороны.

`CollapseToCapsule`/`ExpandFromCapsule` конфликта не дают: поля `_expandedListHeight` на HEAD нет (осталось `_expandedWidth`, `_expandedLeft`, `_expandedTop`, `_expandedMinHeight`, `:85-88`), высота после разворота берётся из `UpdateEmptyState() → ApplyListHeight()` (`:761` и комментарий `:753-760`). С ручным режимом это даст ручную высоту — правильно.

Про двойной клик по ручке: `CornerGrip` — это `Thumb` (`EdgeStackWindow.xaml:447-450`), он забирает мышь в своём обработчике `MouseLeftButtonDown`, поэтому `MouseDoubleClick` до него может не дойти. Рабочий приём — `PreviewMouseLeftButtonDown` с проверкой `e.ClickCount == 2` и `e.Handled = true`; ровно так уже сделан пропуск двойного клика в `OnShellMouseDown` (`:1842-1846`). Живьём не проверял.

### е) B4: буфер и receipt складываются сами, а вот буква не складывается

Хорошая новость: «те же форматы буфера, что у пакета» делается буквально одним вызовом. `WindowsClipboardService.CreatePackageDataObject` (`src/Snapik.Windows/WindowsClipboardService.cs:220-237`) при **одном** пути сам уходит в `CreatePngDataObject` (`:197-205`) и кладёт `PNG` + `DIB` + `Bitmap` + `FileDrop` + `UnicodeText`. То есть `_clipboard.SetPackageGuardedAsync([path], promptText, seq, ct)` — и форматы совпадают с пакетом из одного снимка по построению. Ничего нового в `Snapik.Windows` не нужно.

Receipt тоже складывается: `SetPublished(Published(export))` кладёт в `_published` пакет с одним `CaptureId`; замеченная вставка (`OnPasteIntentObserved:366-392` → `CompletePasteIntentAsync:394-450`) снимает `publishedAtIntent` и передаёт его `CaptureIds` в `MarkCapturesSentAsync` (`:431`, `:438`), а тот помечает только эти id (`:1685-1686`). Значит ✓ получит ровно скопированный снимок — требование B4.4 выполняется без единой правки в цепочке вставки.

Плохая новость — **буква**. `FileExportService.PrepareAsync` раздаёт метки по позиции внутри переданного пакета: `var label = CaptureLabels.ForIndex(index)` (`src/Snapik.Infrastructure/Exporting/FileExportService.cs:42`), и `PromptGenerator` тоже (`src/Snapik.Core/Exporting/PromptGenerator.cs:21`). Пакет из одного снимка — это всегда `A`: файл `01-A.png`, шапка картинки «A» (`WpfExportImageRenderer.DrawCaptureBadge`, `:89-95`), текст «Снимок A. …». Карточка в ленте при этом подписана `B` (`SentCaptureRules.StripLabels`). Требование ТЗ «статус «Снимок B скопирован»» и картинка с буквой `A` в одном действии не сойдутся без правки контрактов экспорта.

Два пути и рекомендация — в §1.B4.

Ещё одно следствие, которого в ТЗ нет: после того как вставку заметят, `MarkCapturesSentAsync` при непустом остатке зовёт `RefreshOwnedClipboardCoreAsync` (`:1695`), и буфер молча становится **полным пакетом из неотправленных**. Это штатное поведение пакета, но применительно к одиночной копии его надо знать: скопировал B, вставил, через доли секунды в буфере лежит пакет из A, C, D…

И третье: ТЗ требует не трогать `_prepared`. Тогда кнопка «Подготовить и вставить в черновик» (`PasteAsync`, `:1013-1040`) продолжит вставлять полный пакет, пока в буфере лежит один снимок. Расхождение осознанное (кнопка вставки — это «отправить всё, что ждёт»), но в `verification.md` его надо записать строкой.

### ж) B4: текст комментариев снимка живёт в `Manifest.PromptText`, отдельного вызова не нужно

`prompt.md` не читается с диска: `FileExportService` кладёт готовый текст в `ExportManifest.PromptText` (`:65`, `:83`), а `PreparedExport.Manifest.PromptText` — то, что уже передаётся в буфер во всех трёх существующих местах (`SaveAndCopyCommittedPackageAsync:996`, `CopyPackageAsync:1237`, `RefreshOwnedClipboardCoreAsync:1735`). Для одного снимка это будет секция `Снимок A. / Комментарий к снимку: / A1: …`. Если у снимка нет ни заголовка, ни заметки, ни помеченных отметок, текст пустой (`PromptGenerator.cs:29-32`), и `CreatePackageDataObject` тогда не кладёт `UnicodeText` вовсе (`:235`) — вставится только картинка. Это правильно и совпадает с пакетом.

### з) B1: `ScrollViewer` достаётся тем же приёмом, что и полоса; «восстановления сессии» в ТЗ нет

Вьюер — нулевой визуальный ребёнок `CaptureList` (шаблон списка перешаблонен в голый `ScrollViewer`, `EdgeStackWindow.xaml:232-242`), способ уже написан в `StripScrollBar()` (`:321-328`): `VisualTreeHelper.GetChild(CaptureList, 0) is ScrollViewer viewer`. Достаточно вынести из него получение вьюера в свой кэшированный метод.

Адрес `:1768` из ТЗ («при восстановлении сессии») указывает не туда: это `SeedDemoAsync` (`:1754-1772`), демо-режим `--demo`. **Сессия в ленту не восстанавливается вообще** — `OnLoaded` (`:224-228`) на обычном запуске зовёт `PurgePreviousSessionsAsync` и стартует с пустой ленты («A session lives for one run»). Так что входов добавления не четыре, а пять, и один из них ТЗ не называет: `CaptureFullscreenAsync` (`src/Snapik.App/EdgeStackWindow.Saving.cs:63`) — снимок всего экрана по отдельной горячей клавише. Полный список `Captures.Add`/`Insert` по `grep -rn "Captures\.Add\|Captures\.Insert" src` (без `MainWindow.xaml.cs`, он исключён из сборки): `:616` (захват), `:1191` (импорт файлов), `:1217` (импорт из буфера), `:1768` (демо), `Saving.cs:63` (весь экран), `:1926` (`RestoreRemoved` — вставка на прежнее место, не в конец), `:1877` (замена после редактора).

Сколько входов показа ленты на самом деле — **не семь, а десять** (`grep -rn "ShowStackWithoutActivation()\|RevealStack()" src`): `App.xaml.cs:91` (второй экземпляр), `Saving.cs:72`, `EdgeStackWindow.xaml.cs:159` (трей «Показать ленту»), `:165` (трей «Настройки»), `:187` (ошибка автозапуска), `:191` (двойной клик по трею), `:237` (`OnLoaded`), `:632` (`CaptureLoopAsync`), `:1038` (`PasteAsync`), `:1888` (`OnOpenCaptureClick`), `:1953` и `:1965` (отменённый выход). Граф (`trace_call_path ShowStackWithoutActivation inbound`) видит семь методов, потому что лямбды трея и `Saving.cs` в рёбра не попали — это тот случай, когда графа мало и нужен `grep` сверху.

---

## 1. Решения по пунктам

### B1. Прокрутка к последнему снимку

**Причина.** Прокрутки нет нигде: единственная работа со `ScrollViewer` ленты — гашение полосы (`OnStripScrolled`, `EdgeStackWindow.xaml.cs:287-293`; `FadeStripScrollBar`, `:313-317`; `StripScrollBar`, `:321-328`). После `Captures.Add` (`:616`) идут `Renumber()` → `UpdateEmptyState()` → `ApplyListHeight()`, высота списка подрастает до потолка 372 и упирается в него на двенадцатой карточке (`StripResizeGeometry.ListHeightForCount`, `:67-73`), дальше `Extent` растёт, `VerticalOffset` остаётся нулём — лента показывает A, а новый снимок под обрезом.

**Решение.**

```csharp
// Рядом со StripScrollBar (:321). Шаблон списка и шаблон вьюера переживают любую карточку,
// поэтому вьюер ищется один раз, как и полоса.
private ScrollViewer? StripScrollViewer()
{
    if (_stripScrollViewer is not null) return _stripScrollViewer;
    if (CaptureList is null || VisualTreeHelper.GetChildrenCount(CaptureList) == 0) return null;
    return _stripScrollViewer = VisualTreeHelper.GetChild(CaptureList, 0) as ScrollViewer;
}

// Низ ленты, а не последняя карточка: контейнер карточки высотой 30 (свес отдан панели
// через её Margin), и ScrollIntoView остановился бы, показав от неё 30 px из 78.
private void ScrollStripToEnd()
{
    if (CaptureList is null || CaptureList.Visibility != Visibility.Visible) return;
    Dispatcher.InvokeAsync(() =>
    {
        CaptureList.UpdateLayout();
        StripScrollViewer()?.ScrollToEnd();
    }, DispatcherPriority.Loaded);
}
```

`StripScrollBar()` (`:321-328`) переписать на `StripScrollViewer()?.Template.FindName(...)`, чтобы поиск вьюера был один.

**Куда звать.** Только в двух видах мест, и ни в коем случае не из `Renumber`/`UpdateEmptyState` — они висят на удалении, переупорядочивании и пометке «отправлено», и прокрутка вниз там неверна (именно такой «общий хук» ломал прошлый раунд):

1. `ShowStackWithoutActivation()` (`:682-699`) — последней строкой, после `AnimateStackIn()`. Это закрывает захват (`:632`), весь экран (`Saving.cs:72`), возврат из редактора (`:1888`), вставку (`:1038`), трей, старт и активацию второго экземпляра. Требование ТЗ «при каждом показе ленты» исполняется буквально.
2. `ImportFileAsync` (`:1209`, после тоста) и `ImportClipboardAsync` (`:1221`) — эти два добавляют в конец при видимой ленте и `ShowStackWithoutActivation` не зовут.

`RestoreRemoved` (`:1918-1928`) не трогаем: он вставляет на прежний индекс, прокрутка вниз показала бы не то, что вернулось.

**Ручная прокрутка.** Между захватами ленту никто не показывает, так что вверх прокрученная лента остаётся прокрученной; вниз она уезжает в момент добавления и в момент показа — ровно как написано в ТЗ.

**Открытый пункт, который надо назвать Никите.** Возврат из редактора (`OnOpenCaptureClick:1888`) тоже уедет вниз, и после правки карточки C в ленте из четырнадцати вы окажетесь у последней, а не у C. ТЗ этого случая не описывает. Дешёвая альтернатива, если решат иначе: в `OnOpenCaptureClick` перед `ShowStackWithoutActivation()` поставить флаг `_scrollTarget = capture` и в `ScrollStripToEnd` при непустом флаге делать `CaptureList.ScrollIntoView(_scrollTarget)`. Я бы не делал в этом раунде.

**Тесты.** В смоук-пробу `RunStripGrowthProbe` (`:2013-2051`), в случай на двенадцать карточек, добавить: после `ScrollToEnd()` у вьюера `Math.Abs(viewer.VerticalOffset - viewer.ScrollableHeight) < 0.5`, и низ последней карточки не ниже низа `PART_ScrollContentPresenter` (проверка уже написана для пяти карточек, `:2029-2033`, её можно переиспользовать функцией). Чистого юнит-теста тут нет: прокрутка живёт в раскладке.

**Связи по графу.** `ShowStackWithoutActivation` inbound (граф + grep, §0.з): десять точек. Что может сломаться в каждой — ничего, кроме позиции прокрутки: метод и так делает `Renumber`, `EnsureStripPlaced`, `Show`, `SetWindowPos`, `UiLanguage.Apply`, `AnimateStackIn`; добавляется одна отложенная операция без побочных эффектов. `StripScrollBar` inbound: `FadeStripScrollBar` (`:313`) и `RunStripGrowthProbe` (`:2041`) — оба продолжат работать после рефакторинга, если `StripScrollViewer()` кэшируется тем же способом. `OnStripScrolled` (`:287`) сработает на нашей прокрутке и на секунду зажжёт полосу — это правильно и ожидаемо.

**Риски.** (1) `DispatcherPriority.Loaded` после `Show()` — если окно в этот момент свёрнуто (`WindowState.Minimized` из `OnHideClick`), раскладки может не быть; `ShowStackWithoutActivation` восстанавливает окно до `Show()` (`:693-695`), так что порядок верный, но проверить живьём на свёрнутой ленте. (2) `ScrollToEnd` на списке, который не прокручивается, — no-op, безопасно. (3) Прокрутка зажигает полосу на секунду при каждом показе ленты — визуальный шум; если мешает, гасить можно, подавив `OnStripScrolled` флагом на время программной прокрутки, но я бы оставил: это обратная связь «лента приехала вниз».

---

### B2. Карточки: плашка прозрачная, раскрытие по наведению, уголок

**Причина.** Всё в `EdgeStackWindow.xaml`: плашка `Background="#E6171A20"` высотой 26 (`:286`) — 90 % непрозрачности на 26 из 30 видимых пикселей; цвета карточки `#242A33` и рамки `#46505E` заданы константами (`:263-264`) вместо кистей темы; раскрытия по наведению нет, от него остались рамка `#718096` и крестик (`:355-358`), а сеттеры `Margin` сняты коммитом `74fdbf6` прошлого раунда по причине, которая больше не действует (§0.а).

**Решение.**

**1. Плашка → растяжка.** `:286` заменить на:

```xml
<!-- Тридцать, а не двадцать шесть: плашка накрывает ровно ту полосу карточки, которая видна
     из-под следующей. Три стопа, как в эталоне: 55 % сверху, 28 % на шестидесяти процентах,
     ноль внизу — снимок читается под буквой, а буква читается на светлом снимке. -->
<Border VerticalAlignment="Top" Height="30">
    <Border.Background>
        <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
            <GradientStop Offset="0" Color="#8C141E1E" />
            <GradientStop Offset="0.6" Color="#47141E1E" />
            <GradientStop Offset="1" Color="#00141E1E" />
        </LinearGradientBrush>
    </Border.Background>
```

Цвет `rgba(20,24,30,·)` = `#14181E`; альфы `0.55 → #8C`, `0.28 → #47`, `0 → #00`. **Внимание:** в WPF прозрачный стоп должен нести тот же RGB (`#00141E1E`), иначе градиент уйдёт через серый.

Иконка и счётчик (`:296-297`): `Foreground="White"`, и на обоих `Effect` тенью. `DropShadowEffect` на `TextBlock` — это ещё два bitmap-эффекта на карточку сверх тени самой карточки; дешевле и ближе к эталону положить под них один общий `DropShadowEffect` на их `StackPanel` (`:288`): `BlurRadius="2" ShadowDepth="1" Direction="270" Opacity="0.6" Color="#000000"`. Кружку буквы (`LabelBadge`, `:289`) — такой же с `BlurRadius="3" Opacity="0.4"`.

`ThumbImage.Opacity="0.86"` (`:281`) ТЗ разрешает оставить; я бы оставил — на светлых снимках она и держит контраст буквы.

**2. Раскрытие.** Триггер `:355-358` заменить на конструкцию из §0.а. Комментарий `:349-354` переписать: причина снята `ApplyListHeight`, высота списка считается по `Captures.Count`, раскрытие меняет только `Extent`.

**3. Цвета и радиус.** `:263-264`: `Background="{DynamicResource ElevatedBrush}"`, `BorderBrush="{DynamicResource ElevatedLineBrush}"`. Рамка наведения (`:356`) — `{DynamicResource TextFaintBrush}` (Dark `#6F7A8A` против сегодняшних `#718096` — разницы не видно; Glass `#C5BFD3`, Sunset/Sea/Night `#A9B4C2`, что совпадает с эталонным `#9AA6B8`; Dawn `#8A93A3` — тёмная рамка на светлой карточке, что верно). Приглушённая рамка отправленного снимка (`:334`, `#333C49`) — тоже константа из тёмной темы; заменить на `{DynamicResource SurfaceLineBrush}`, иначе на «Рассвете» отправленная карточка получит тёмный контур. Радиусы 11 и 10 **не трогать** (§0.г).

`LabelBadge` уже на `{DynamicResource AccentBrush}`, `ScreenChip`/`ImportChip` на `#1FFFFFFF` (полупрозрачный белый — работает на всех тёмных, на «Рассвете» бледнеет; в объём ТЗ не входит, отмечаю).

**4. Что не меняется.** 78 / шаг 30, `ItemsPanel` с `Margin="0,0,0,48"` (`:252`), порядок карточек, тень вверх (`:272`), крестик, `EmptyHint`, формула `ListHeightForCount`.

**Строки UI.** Ни одной новой: всё, что добавляется, — кисти и анимации.

**Тесты.**
- `RunStripGrowthProbe` (`:2013-2051`) — новый третий случай: пять карточек, у третьей `ThumbCard.Margin` выставлен в `0` вручную (без анимации), затем `CaptureList.Height` **по-прежнему 220** и `viewer.ScrollableHeight ≈ 48`. Это буквальная проверка требования «высота списка при этом не меняется». Чтобы достать `ThumbCard` в пробе, нужен спуск по визуальному дереву от `ItemContainerGenerator.ContainerFromIndex(i)` до `Border` с именем `ThumbCard` — в `EdgeStackWindow.xaml.cs` есть только восходящий `FindAncestor` (`:1930-1934`), нисходящий придётся дописать (приватный `static T? FindDescendant<T>(DependencyObject, string name)`).
- Отдельная проверка «раскрытая карточка не смещает саму себя»: верх контейнера третьей карточки до и после равен `14 + 2·30`.
- Юнит-тестов на палитры не добавляю: `SmokeTestRunner.VerifyTheStripChromeFollowsTheTheme` (`:318`) уже проверяет, что хром ленты ходит за темой; если он проверяет только `Shell.Background`, расширить его на `ThumbCard` нельзя — карточки нет без данных. Оставляю живой проверке F.4.

**Связи по графу.** `ApplyListHeight` inbound (depth 3): `EnsureStripPlaced`, `OnCornerDragCompleted`, `PlaceStripInitially`, `UpdateEmptyState` → `Renumber`, `ExpandFromCapsule`, `OnLoaded`, `ShowStackWithoutActivation` → двенадцать точек верхнего уровня. Ни одна не вызывается наведением, поэтому раскрытие в них не попадает — это и есть доказательство, что вопрос G/B2 закрыт. `UiSoundService.Tick` inbound: `OnCaptureListMouseWheel` (`:1850`) и `OnCaptureThumbMouseEnter` (`:1848`) — второй висит на `MouseEnter` того же `ThumbCard` (`EdgeStackWindow.xaml:264`), то есть тик играет **сразу**, а карточка раскрывается через 150 мс. Решить осознанно: либо оставить (тик подтверждает наведение раньше, чем видно движение), либо перенести тик в `EnterActions` сторибордa. Рекомендую оставить — иначе быстрый проезд по ленте станет немым, а он сейчас озвучен.

**Риски.** (1) Производительность анимации `Margin` на 26 карточках с тенями (§0.а). (2) `ScrollableHeight` вырастает на 48 при раскрытии → `ComputedVerticalScrollBarVisibility` становится `Visible` на непрокручиваемой ленте; полоса при этом с `Opacity="0"` (`EdgeStackWindow.xaml:168`) и `OnStripScrolled` её не зажжёт (`e.VerticalChange == 0` при росте `Extent`), но проверить живьём. (3) Раскрытие **последней** карточки: её собственный свес уже компенсирован `Margin` панели, поэтому `Extent` вырастет на 48 «в пустоту». Косметика, но в F.5 это увидят — если мешает, панели давать `Margin="0,0,0,48"` только пока никто не раскрыт, что дороже, чем стоит. (4) Растяжка вместо сплошной плашки на очень светлом снимке: буква белая на `#FF8C42` кружке с тенью — эталон это и рисует, но на «Рассвете» смотреть живьём.

---

### B3. Угол ленты: при отпускании не схлопывать

**Причина.** `OnCornerDragCompleted` (`:942-951`):

```csharp
MutateSettings(stored => stored with { StackWidth = Width, StackHeight = CaptureList.Height });
// The height dragged out is the ceiling, and the list sits back down on what it holds…
ApplyListHeight();
```

`ApplyListHeight` (`:826-832`) считает `ListHeightForCount(Captures.Count, cap)` = `min(содержимое, потолок)` (`StripResizeGeometry.cs:67-73`). При трёх снимках содержимое — 160, растянутая до 310 лента садится на 160 в момент отпускания. Во время перетаскивания лента честно идёт за курсором (`OnCornerDragDelta:923-940`, `ListHeightFromStart:175-182`), поэтому «схлопывание» видно как отдельный рывок.

**Решение (рекомендуемое).** Новый аддитивный ключ `StackHeightManual` (bool, по умолчанию `false`) и одна чистая функция.

1. `HotkeySettings.cs`, рядом с `StackHeight` (`:40-46`):

```csharp
/// <summary>
/// Тянул ли пользователь угол ленты руками. Пока нет — <see cref="StackHeight"/> потолок, и список
/// стоит на высоте своего содержимого; после первого перетаскивания сохранённое число становится
/// высотой списка, и пустое место внизу — это то, что пользователь себе и вытянул.
/// </summary>
public bool StackHeightManual { get; init; }
```

2. `Controls/StripResizeGeometry.cs`, рядом с `ListHeightForCount` (`:67-73`):

```csharp
/// <summary>Высота списка: ручная — это сама сохранённая высота, автоматическая — по содержимому.</summary>
internal static double ListHeight(int count, double stored, bool manual) =>
    manual ? stored : ListHeightForCount(count, stored);
```

`ListHeightForCount` оставить как есть: её зовут и тест `The_list_is_as_tall_as_its_cards_up_to_the_ceiling`, и `ApplyListHeight`.

3. `ApplyListHeight` (`:826-832`):

```csharp
var stored = Controls.StripResizeGeometry.ClampListHeight(
    _settings.StackHeight, StackWorkArea().Height, StackChromeHeight());
CaptureList.Height = Controls.StripResizeGeometry.ListHeight(Captures.Count, stored, _settings.StackHeightManual);
```

4. `OnCornerDragCompleted` (`:946`): `stored with { StackWidth = Width, StackHeight = CaptureList.Height, StackHeightManual = true }`. Строку `ApplyListHeight();` (`:950`) **оставить** — она теперь возвращает ровно то число, которое уже стоит, и заодно применяет клампы по рабочей области; но комментарий `:947-949` переписать: доводчика больше нет.

5. Двойной клик по ручке → обратно в авто. В `EdgeStackWindow.xaml:447` добавить `PreviewMouseLeftButtonDown="OnCornerGripPress"`, в код:

```csharp
// Двойной клик по ручке — стандартный жест «авторазмер». Preview, а не обычное событие: Thumb
// забирает мышь своим MouseLeftButtonDown, и до MouseDoubleClick дело не доходит. Тот же приём,
// что и пропуск двойного клика в OnShellMouseDown.
private void OnCornerGripPress(object sender, MouseButtonEventArgs e)
{
    if (e.ClickCount != 2) return;
    e.Handled = true;
    MutateSettings(stored => stored with { StackHeightManual = false });
    ApplyListHeight();
}
```

Если Никита решит, что жест лишний, — пункт 5 выкинуть целиком, остальное работает: «по содержимому» тогда живёт до первого растягивания, как и написано в ТЗ.

**Что при этом получается.** Растянул до 310 при трёх снимках → отпустил → 310, внизу пусто. Захват → карточек четыре, содержимое 190, высота по-прежнему 310, лента не шевельнулась (F.6). Пятнадцать карточек → содержимое 434 > 310 → прокрутка, высота 310. Пустая лента → `UpdateEmptyState` (`:1517-1518`) прячет список и показывает `EmptyHint` 92, ручная высота не видна и вернётся с первым снимком.

**Границы, которые остаются.** `ClampListHeight` (`:157-164`) держит пол `MinimumListHeight = 180` и потолок «рабочая область минус хром». То есть ручная высота не может быть меньше 180: лента с одним снимком, стянутая вниз до упора, покажет 180 (100 содержимого + 80 пустоты). Это следствие уже существующего пола, не новое; назвать в `verification.md`.

**Строки UI.** Новых нет.

**Тесты.**
- `tests/Snapik.App.Imaging.Tests/StripResizeGeometryTests.cs`, рядом с `[InlineData]`-таблицей `ListHeightForCount` (`:161-170`) — новая теория на `ListHeight`: `(3, 310, manual: true) → 310`; `(3, 310, false) → 160`; `(15, 310, true) → 310`; `(0, 310, true) → 310` (список всё равно скрыт); `(0, 310, false) → 92`.
- `SmokeTestRunner.cs:31-43`: в `customSettings` добавить `StackHeightManual = true`, иначе round-trip (`:46-49`) не проверит новый ключ. Это тот самый общий файл, который правят все дорожки (§2).
- `SettingsMigrationTests.cs` — правки не нужны: рулей миграции не добавляем, `CurrentVersion` остаётся 2.

**Связи по графу.** `ClampListHeight` inbound: `ApplyListHeight` и два теста (`A_stored_list_height_is_clamped_by_the_range_and_by_the_screen`, `A_stored_list_height_leaves_room_for_the_chrome_of_the_window`) — сигнатура не меняется, тесты целы. `ApplyListHeight` inbound — двенадцать путей (см. B2): все получат ручную высоту, что и требуется; отдельно проверить `ExpandFromCapsule` (`:746-772`, высота через `UpdateEmptyState` на `:761`) и `PlaceStripInitially` (`:837-853`, высота до `UpdateLayout` на `:845-848`) — оба уже написаны так, что берут число из `ApplyListHeight`, а не из настроек напрямую. `MutateSettings` inbound: `CompleteOnboarding`, `ConfirmSessionDiscard`, `OnCornerDragCompleted`, `OnWidthDragCompleted`, `OpenSettings`, `SavePackageAsAsync`, `ToggleTopmost`, `WriteOnboarding` — все пишут `stored with {…}` поверх файла на диске, новый ключ ни одним из них не затирается. `RestoreRect` inbound: `EnsureStripPlaced`, `ExpandFromCapsule` — обе меряют `ActualHeight`, который после правки следует за ручной высотой; ничего не ломается.

**Риски.** (1) Двойной клик по `Thumb` через `PreviewMouseLeftButtonDown` живьём не проверен — если не сработает, запасной ход: обработать `MouseDoubleClick` на самом `CornerGrip` и, если и это молчит, отказаться от жеста (ТЗ его не требует). (2) Ручная высота, вытянутая на большом мониторе, на маленьком урезается `ClampListHeight` — и `StackHeightManual` при этом остаётся `true`, то есть лента будет стоять на урезанной высоте, а не «по содержимому». Так и задумано, но это заметно при переносе на второй монитор (у Кати их два) — в F.6 проверить. (3) `StackChromeHeight()` (`:816-820`) считает `ActualHeight - CaptureList.ActualHeight`; на пустой ленте список скрыт и хром равен всему окну, потолок из-за этого занижается. Дефект существует и сейчас, ручной режим его не усугубляет, но при первом снимке после пустой ленты высота пересчитается корректно.

---

### B4. Копировать один снимок

**Причина.** В буфер уходит только пакет: `SaveAndCopyCommittedPackageAsync` (`:975-1009`, все неотправленные при захвате) и `CopyPackageAsync` (`:1227-1250`, вся лента по пункту меню `:1054`). Один снимок со всеми отметками можно только сохранить в файл из редактора (`OverlayEditorWindow.xaml:310` → `OverlayEditorWindow.Save.cs:14-54`), и то другим рендером (`Surface.RenderAnnotated()` — без шапки и поля под бейджи, в отличие от `WpfExportImageRenderer`).

#### B4.0. Общий кусок (волна 0)

Оба входа делают одно и то же, поэтому ядро пишется один раз до расхождения дорожек B и C.

**1. `SessionWorkspace.cs`** — экспорт одного снимка без перезаписи `session.json`. Рядом с `PrepareAsync` (`:203-218`):

```csharp
/// <summary>
/// Пакет из одного снимка: та же отрисовка и тот же текст, что у пакета, но снимок берётся как
/// есть и сессия на диск не переписывается — снимок может быть черновиком редактора, которого в
/// ленте ещё нет. Ревизия не увеличивается: её двигают только настоящие записи сессии.
/// </summary>
public async Task<PreparedExport> ExportSingleAsync(CaptureItem capture, CancellationToken cancellationToken = default)
{
    var session = new SnapikSession(SessionId, SnapikSession.CurrentSchemaVersion, _createdAtUtc,
        DateTimeOffset.UtcNow, _revision, string.Empty, null, [capture.ToCore()]);
    var prepared = await new FileExportService(new WpfExportImageRenderer()).PrepareAsync(session, SessionDirectory, cancellationToken);
    TrimExports(prepared.RootDirectory);
    return prepared;
}
```

Почему не `CreateSnapshot` (`:259-265`): он делает `++_revision`, то есть сдвинул бы счётчик сессии под экспорт, который на диск не ложится. Почему `TrimExports` безопасен (`:225-249`): он держит три последние ревизии плюс всё, на что указывают `PinnedExportDirectories`, а туда `PinExportDirectories` (`:1555-1556`) кладёт каталоги `_published` и `_prepared`; на момент вызова оба ещё старые, значит пакет ленты не сносится.

**2. `EdgeStackWindow.Saving.cs`** — публикация в буфер, рядом с `AutoSaveCaptureAsync` (`:20-38`):

```csharp
/// <summary>
/// Один снимок в буфер: тот же экспорт и те же форматы, что у пакета (SetPackageGuardedAsync с
/// одним путём сам кладёт PNG, DIB, Bitmap, FileDrop и текст). Опубликованным пакетом становится
/// он один, поэтому замеченная вставка пометит ✓ только его. `_prepared` не трогаем: кнопка
/// вставки по-прежнему отправляет всё, что ждёт, и пересоберётся она сама на следующем захвате.
/// </summary>
internal async Task CopySingleCaptureAsync(CaptureItem capture, string label)
{
    await _pasteIntentTransition;
    CancelReceiverEchoWatch();
    await _clipboardPublicationGate.WaitAsync();
    try
    {
        var export = await _workspace.ExportSingleAsync(capture);
        var current = await _clipboard.CaptureAsync(CancellationToken.None);
        _ownedClipboardReceipt = await _clipboard.SetPackageGuardedAsync(
            export.GetImagePathsInOrder(), export.Manifest.PromptText, current.SequenceNumber, CancellationToken.None);
        SetPublished(Published(export));
        UiSoundService.Copied(_settings);
        ShowToast(string.Format(UiLanguage.Text("Снимок {0} скопирован"), label));
    }
    catch (Exception ex) { SetStatus($"{UiLanguage.Text("Не удалось скопировать снимок")}: {ex.Message}", true); }
    finally { _clipboardPublicationGate.Release(); }
}
```

Структура списана с `CopyPackageAsync` (`:1227-1250`) построчно — та же очередь `_pasteIntentTransition`, тот же `CancelReceiverEchoWatch`, тот же гейт, тот же `SetPublished`. Разница в трёх строках: источник экспорта, звук с тостом вместо статуса и отсутствие `_prepared = package`.

Про статусную строку: `SetStatus` (`:1774-1781`) показывает `StatusText` **только при `error = true`** (`:1779`), обычный текст прячется. Значит «Снимок B скопирован» в понимании ТЗ («статус внизу ленты») — это `ShowToast` (`:1785-1799`), а не `SetStatus`; тост живёт 5 секунд и стоит ровно внизу ленты (`EdgeStackWindow.xaml:400-406`). Это расхождение с формулировкой ТЗ, но не с тем, что Катя увидит.

#### B4.1. Правая кнопка по карточке

В `EdgeStackWindow.xaml:223-228` к `ListBox` добавить `PreviewMouseRightButtonUp="OnCaptureListRightClick"`. Обработчик рядом с `OnCaptureListMouseDown` (`:1893`):

```csharp
// Правая кнопка ничего не отнимает у перетаскивания: то висит на PreviewMouseLeftButtonDown
// (OnCaptureListMouseDown/Move), а перетаскивание окна — на левой кнопке панели (OnShellMouseDown).
// Меню строится в коде, как меню «•••»: ContextMenu не в визуальном дереве, и UiLanguage.Apply(this)
// до него не дотянулся бы.
private void OnCaptureListRightClick(object sender, MouseButtonEventArgs e)
{
    if (FindAncestor<ContentPresenter>((DependencyObject)e.OriginalSource)?.Content is not CaptureItem capture) return;
    var menu = new ContextMenu();
    menu.Items.Add(MenuItem("Копировать снимок", async () => await CopySingleCaptureAsync(capture, capture.DisplayLabel)));
    menu.Items.Add(MenuItem("Сохранить снимок…", async () => await SaveSingleCaptureAsAsync(capture)));
    menu.Items.Add(new Separator());
    menu.Items.Add(MenuItem("Удалить", () => RemoveCapture(capture)));
    menu.PlacementTarget = CaptureList;
    UiLanguage.Apply(menu);
    menu.IsOpen = true;
    e.Handled = true;
}
```

`MenuItem(string, Func<Task>)` уже есть (`:1155`), `FindAncestor` — `:1930-1934`, тот же способ добычи `CaptureItem`, что в `OnCaptureListMouseDown` (`:1896`) и `OnCaptureListDrop` (`:1912`).

«Удалить» переиспользует тело `OnRemoveCaptureClick` (`:657-672`), которое сейчас достаёт снимок из `Button.Tag`. Вынести тело в `private async Task RemoveCapture(CaptureItem capture)` и оставить обработчик кнопки однострочником — иначе придётся дублировать `_removed.Push`, `Renumber`, `InvalidatePrepared`, тост «Отменить» и `RefreshOwnedClipboardAsync`.

«Сохранить снимок…» — новый `SaveSingleCaptureAsAsync` в `EdgeStackWindow.Saving.cs`: `SaveFileDialog` под `SuspendTopmost()` (`:1099-1105`) с фильтром `SaveNaming.ImageFilter` и именем `LocalImageSave.NewPath(_settings)`, затем `LocalImageSave.WriteAsync(new AnnotationCanvas { Image = capture.Image, Annotations = capture.Annotations }.RenderAnnotated(), …)` — ровно как `AutoSaveCaptureAsync` (`Saving.cs:25-31`) плюс диалог из `OnSaveImageClick` (`Save.cs:27-48`).

**Осознанная асимметрия, которую надо записать:** «Копировать снимок» кладёт картинку **с шапкой и полем под вынесенные бейджи** (`WpfExportImageRenderer`), «Сохранить снимок…» пишет файл **без шапки** (`AnnotationCanvas.RenderAnnotated`). Так это уже устроено между пакетом и «Сохранить на компьютер» в редакторе; ТЗ формат сохранения не оговаривает, и делать сохранение как экспорт означало бы менять поведение редакторской кнопки заодно. Оставляю как есть, называю в `verification.md`.

#### B4.2. Кнопка в редакторе

`OverlayEditorWindow.xaml`, в `ToolbarActions` между `SaveImageButton` (`:310-312`) и `DoneButton` (`:313`):

```xml
<Button x:Name="CopyImageButton" Style="{StaticResource OverlayButton}" Click="OnCopyImageClick"
        AutomationProperties.Name="{local:UiText Копировать снимок}">
    <TextBlock FontFamily="{StaticResource IconFont}" FontSize="16" Text="&#xE8C8;" />
</Button>
```

`E8C8` — системная глиф-иконка «Copy» в Segoe Fluent/MDL2, соседняя с `E74E` («Save») и `E74D` («Delete»), которые уже используются.

Обработчик — в `OverlayEditorWindow.Save.cs`, рядом с `OnSaveImageClick` (`:14`):

```csharp
private async void OnCopyImageClick(object sender, RoutedEventArgs e)
{
    if (_capture is null || _busyCrop || _captureResizeCorner >= 0 || Surface.IsMouseCaptured) return;
    // Незакрытый ввод текста дописывается ровно как при сохранении: пока текстовое поле открыто,
    // холст эту подпись не рисует, и в буфер уехала бы картинка без слов, которые на экране.
    CommitTextEdit();
    if (Application.Current.MainWindow is EdgeStackWindow stack)
        await stack.CopySingleCaptureAsync(_capture, _capture.DisplayLabel);
}
```

Путь к ленте — тот же, что уже используется на строке `Save.cs:50` (`if (Application.Current.MainWindow is EdgeStackWindow stack) stack.NotifySaved();`); `MainWindow` назначается в `App.xaml.cs:68`.

Ctrl+Shift+C: в `OverlayEditorWindow.xaml.cs` рядом с `:2259` (`Keyboard.Modifiers == ModifierKeys.Control && e.Key == Key.C` → «Готово») добавить ветку `Keyboard.Modifiers == (ModifierKeys.Control | ModifierKeys.Shift) && e.Key == Key.C`. Сравнение строгое (`==`, не `HasFlag`), поэтому Ctrl+Shift+C сегодня **не** попадает в «Готово» — конфликта нет. Симметрично добавить в обработчик поля заметки (`:2201`, там уже есть Ctrl+S). В `EditorShortcuts.Actions` (`src/Snapik.App/EditorShortcuts.cs:36-45`) — строка `("Ctrl+Shift+C", "Копировать снимок")` после `("Ctrl+S", "Сохранить на компьютер")`.

**Случай, которого нет в ТЗ: копия нового, ещё не добавленного снимка.** `CaptureNewAsync` (`OverlayEditorWindow.xaml.cs:116`) открывает редактор до того, как снимок попал в ленту (`Captures.Add` происходит после возврата, `:616`). Копия сработает — экспорт от `_capture` не зависит от ленты — но ✓ ставить будет некуда, а «Готово» сразу после этого перезапишет буфер пакетом (`SaveAndCopyCommittedPackageAsync`, `:623`). Практически полезно, только если после копии снимок отменяют. Поведение приемлемое, но назвать в `verification.md` и в F.8 проверять на **существующем** снимке (`D` из ленты), как F.8 и написан.

#### B4.3. Буква

`FileExportService` раздаёт метки по позиции в переданном пакете (`FileExportService.cs:42`), `PromptGenerator` — тоже (`PromptGenerator.cs:21`). Пакет из одного снимка всегда `A`: `01-A.png`, шапка «A», текст «Снимок A».

**Вариант 1 (рекомендую).** Оставить `A` в картинке и тексте, а букву ленты показывать только в тосте: «Снимок B скопирован». Обоснование: пакет **уже** нумеруется заново, и приложение прямо об этом говорит пользователю — строка «Снимки в пакете нумеруются заново: A, B, C…» (`UiLanguage.cs:101`, окно «Сохранить пакет»). Пакет из одного снимка — предельный случай того же правила, и в чате с одной картинкой буква ни с чем не спорит. Цена: нулевая, контракты экспорта не трогаются.

**Вариант 2.** Протащить смещение метки: `FileExportService.PrepareAsync(session, dir, int labelOffset = 0, ct)` и `PromptGenerator.Generate(session, int labelOffset = 0)`, `ForIndex(index + labelOffset)`. Тогда снимок B даст `01-B.png` и «Снимок B». Цена: меняются `IExportService` (`src/Snapik.Core/Exporting/ExportContracts.cs:43-48`) и генератор `prompt.md` — то есть правило именования файлов пакета и текст, а это ровно то, что `AGENTS.md` правило 4 велит согласовывать с Mac; плюс тесты `PersistenceAndExportTests`, `ExtendedCommentsTests`. За одну строку статуса это дорого.

Решение за Никитой; в разборе иду по варианту 1.

**Строки UI (пары RU/EN в `UiLanguage.cs`).** Проверено `grep` по словарю — все четыре ключа свободны:

```csharp
["Копировать снимок"] = "Copy capture",
["Сохранить снимок…"] = "Save capture…",
["Снимок {0} скопирован"] = "Capture {0} copied",
["Не удалось скопировать снимок"] = "Could not copy the capture",
```

Уже заняты и переиспользуются как есть: `["Удалить"] = "Delete"` (`:85`), `["Сохранить на компьютер"]` (`:83`), `["Копировать пакет"]` (`:96`), `["Изображения"]`/`["Все поддерживаемые"]`/`["Выберите PNG или JPEG."]` (`:112-113`). Новый ключ `["Копировать снимок"]` служит и пункту меню, и `AutomationProperties.Name` кнопки редактора, и строке в `EditorShortcuts.Actions` — один ключ на три места, как принято в файле.

**Тесты.**
- `tests/Snapik.Core.Tests/PersistenceAndExportTests.cs` — новый случай: экспорт сессии из одного снимка с заметкой даёт один `ExportImageEntry` с `FileName == "01-A.png"` и `Manifest.PromptText`, начинающийся с «Снимок A». Это фиксирует вариант 1 явно, чтобы он не «поехал» молча.
- `tests/Snapik.Windows.Tests/` — проверка форматов: `WindowsClipboardService.CreatePackageDataObject([onePng], "текст")` содержит `PNG`, `DIB`, `Bitmap`, `FileDrop`, `UnicodeText`, и ровно те же форматы, что у пакета из одного снимка сегодня. Метод `internal`, в `Snapik.Windows.Tests` уже есть доступ (`ClipboardEchoDetectorTests`), сверить `InternalsVisibleTo`.
- `SmokeTestRunner.cs`: в языковой блок (`:337-343`) добавить пару «Копировать снимок» / «Copy capture» — там уже лежит список строк раунда, которые обязаны ходить в обе стороны.
- Живьём (F.7, F.8): Claude, ChatGPT, Telegram — это открытый вопрос G/B4, автоматикой не закрывается.

**Связи по графу.**
- `SetPackageGuardedAsync` inbound: `CopyPackageAsync`, `SaveAndCopyCommittedPackageAsync`, `RefreshOwnedClipboardCoreAsync`, `RepublishPackageForReuseAsync`, `WatchForReceiverEchoAsync` (все — `EdgeStackWindow.xaml.cs`), `PasteSinglePackageAsync` (`src/Snapik.Windows/PasteCoordinator.cs:49`, восстановление буфера после вставки), `OnCopyPackageClick` (`src/Snapik.App/MainWindow.xaml.cs:394` — файл исключён из сборки), плюс два теста в `Snapik.Windows.Tests`. Добавляется восьмой вызывающий; сигнатуру не трогаем, ничего не ломается.
- `SetPublished` inbound: `CompletePasteIntentAsync`, `CopyPackageAsync`, `RefreshOwnedClipboardCoreAsync`, `ReleaseOwnedClipboardCoreAsync`, `RepublishPackageForReuseAsync`, `SaveAndCopyCommittedPackageAsync`, `WatchForReceiverEchoAsync`. Наш вызов кладёт пакет из одного `CaptureId` — именно это и читает `CompletePasteIntentAsync` (`:431`, `:438`), чтобы пометить ✓.
- `MarkCapturesSentAsync` inbound: только `CompletePasteIntentAsync` ← `OnPasteIntentObserved`. Правок не требует: он помечает по `ids.Contains(capture.Id)` (`:1686`), и множество из одного id отработает без изменений. Побочное: на `:1690-1695` при непустом остатке он перепубликует полный пакет (§0.е).
- `InvalidatePrepared` inbound: девять точек; наш код туда **не** добавляется сознательно (ТЗ B4.4).
- `UiSoundService.Copied` inbound: сейчас только `CopyPackageAsync`; станет два. `NotifyCopied` (`Saving.cs:14`) inbound: `CopyPackageAsync`, `RefreshOwnedClipboardCoreAsync`, `SaveAndCopyCommittedPackageAsync` — для одиночной копии баллон трея **не** зову: у него текст «Снимки скопированы» во множественном числе, и заводить второй баллон ради одной копии сверх ТЗ. Тоста в ленте достаточно.
- `OnCaptureListMouseDown`/`OnCaptureListMouseMove` (`:1893-1905`) — обработчики без вызывающих (граф пуст, это правильно для событий). Оба на `PreviewMouseLeftButtonDown`/`PreviewMouseMove`; правая кнопка их не задевает, `DragDrop.DoDragDrop` (`:1904`) стартует только при `e.LeftButton == MouseButtonState.Pressed`. `OnShellMouseDown` (`:1842`) выходит при `e.LeftButton != Pressed`. Перетаскивание карточек и перетаскивание окна безопасны.
- `TrimExports` — приватный, вызывается из `PrepareAsync` (`SessionWorkspace.cs:216`); добавится второй вызывающий из `ExportSingleAsync`.

**Риски.** (1) Буква `A` в картинке против `B` на карточке (§0.е, решение варианта 1) — самый вероятный источник вопроса от Кати; ответить заранее строкой в `verification.md`. (2) После вставки одиночной копии буфер сам становится полным пакетом — если Катя вставит второй раз в другое окно, придёт пакет, а не снимок; это поведение пакета, но для одиночной копии выглядит неожиданно. (3) `ExportSingleAsync` пишет в `exports/` каталог за каталогом; `TrimExports` держит три последние плюс закреплённые — частые одиночные копии будут вытеснять старые ревизии быстрее. Дефект не новый (то же делает «Копировать пакет»), но частота выше. (4) Редактор для нового снимка (B4.2, выше). (5) `ContextMenu` в ленте и `Topmost`: лента по умолчанию `Topmost` (`:205`), меню трея и «•••» с этим живут (`OnMoreClick:1042-1062`), так что риск низкий, но проверить на 125 % и на втором мониторе.

---

## 2. Пересечения с другими дорожками и разрез по волнам

### Волна 0 (до расхождения B и C)

1. **`SessionWorkspace.ExportSingleAsync`** (`SessionWorkspace.cs`) — экспорт одного снимка без записи сессии.
2. **`EdgeStackWindow.CopySingleCaptureAsync(CaptureItem, string label)`** (`EdgeStackWindow.Saving.cs`) — публикация в буфер, звук, тост, `_published`.
3. **Четыре строки в `UiLanguage.cs`** (B4) — чтобы дорожки не правили словарь в двух ветках одновременно.
4. **Вынос тела `OnRemoveCaptureClick` в `RemoveCapture(CaptureItem)`** — нужен и контекстному меню, и остаётся кнопке.

После волны 0 дорожка C добавляет в редакторе ровно три вещи: кнопку в `OverlayEditorWindow.xaml:306-314`, обработчик `OnCopyImageClick` в `OverlayEditorWindow.Save.cs`, ветку Ctrl+Shift+C в `OverlayEditorWindow.xaml.cs:2201` и `:2256-2259` плюс строку в `EditorShortcuts.cs:36-45`. Дорожка B после волны 0 не заходит в файлы редактора вовсе.

### Конфликты с дорожкой C

- **`WpfExportImageRenderer.cs`**: C1 добавляет точку комментария в экспорт и меняет расчёт линии-выноски (`:180-187` по адресам ТЗ). B4 этот рендерер **вызывает** и не правит — файлового конфликта нет, но поведенческая зависимость есть: одиночная копия унаследует точку и новую выноску автоматически. Порядок слияния безразличен; проверять F.7/F.9 после обеих.
- **`OverlayEditorWindow.xaml`**: B4.2 вставляет кнопку в `ToolbarActions` (`:306-314`). C2 правит блок свойств (капсула формы у размытия) — это `ToolbarProperties`, другой участок того же файла. Конфликт вероятен только при одновременной перенумерации строк; лечится тем, что кнопку добавляет дорожка C (см. разрез выше), а не B.
- **`OverlayEditorWindow.xaml.cs`**: C1 правит `:1401` (вторая точка комментария) и тесты `:1005`, `:1035`; B4.2 — обработчики клавиш в районе `:2201` и `:2256-2259`. Участки разнесены, но файл один.
- **`EditorShortcuts.cs`**: только B4.2. C не трогает.

### Конфликты с дорожкой A+D

- **`UiLanguage.cs`** — общий для всех трёх дорожек (A1 может не добавить ничего, D2 добавит «Неон», B4 добавит четыре ключа). Классический конфликт; лечится волной 0 (пункт 3) или строгим порядком слияния.
- **`SmokeTestRunner.cs`** — B3 правит `customSettings` (`:31-43`), D1 наверняка правит `VerifySoundDefaults` (`:50`) и, возможно, те же `customSettings` (`SoundVolume = 35` уже там). Конфликт в одном литерале объекта — почти гарантирован, править вручную.
- **`HotkeySettings.cs`** — B3 добавляет `StackHeightManual`. D1 по своему описанию миграции не требует («значение в настройках остаётся 0-100»), D2 меняет только допустимые значения `AnnotationPalette` (`:56`) без новой записи. Конфликта по строкам быть не должно, но оба правят один файл.
- **`HotkeySettingsWindow.xaml`** (A1 высота, D1 ползунок, D2 палитра) и **`Controls/AppearancePicker.*`** (A1, D2) — дорожка B не входит совсем.
- **`EdgeStackWindow.xaml.cs`** — B правит его сильнее всех (B1, B3, B4). D1 заходит в `OpenSettings` (`:1443-1458`, `SoundVolume = candidate.SoundVolume` на `:1449`), но это отдельный участок далеко от моих. Отмечаю, чтобы `git merge` не удивил.
- **`tasks/verification.md`** — правят все; писать своим абзацем в конец, не переставляя чужие.

---

## 3. Соответствие приёмке F и открытым вопросам G

| Шаг F | Что закрывает | Чем подтверждается |
|---|---|---|
| **F.3** 12 снимков, последний внизу; прокрутить вверх → следующий захват снова внизу | B1 | Смоук: после `ScrollToEnd` `VerticalOffset == ScrollableHeight` на двенадцати карточках. Живьём: сама «не сбивать ручную прокрутку между захватами» — автоматикой не проверяется, лента между захватами скрыта |
| **F.4** 6 снимков на «Стекле»: плашки прозрачные, снимки видны, кромки нет; на «Рассвете» тоже | B2.1, B2.3 | Только глазами. «Фиолетовая» = тема `glass` (§0.в). Смоука на цвет карточки нет: карточка не существует без данных |
| **F.5** Навести на C → через ~150 мс раскрылась, D–F сдвинулись, лента не выросла; увести → сложилась; быстрый проезд ничего не дёргает; вернуться из редактора → ничего не раскрыто | B2.2, B1 из ТЗ №5 | «Лента не выросла» — смоуком (`CaptureList.Height` 220 при раскрытой третьей карточке, §1.B2). Задержка, анимация, проезд и складывание — живьём |
| **F.6** 3 снимка → угол вниз на 150 → отпустить: осталась; захват → не изменилась; двойной клик → по содержимому | B3 | Юнит-тесты `ListHeight` закрывают арифметику всех трёх состояний. Сам жест угла и двойной клик — живьём |
| **F.7** Правая кнопка по B → «Копировать снимок» → Ctrl+V: один PNG с отметками и полем, текст комментариев B; ✓ только на B; следующий захват → пакет из неотправленных | B4.1, B4.4 | Форматы буфера — тестом на `CreatePackageDataObject`; «✓ только на B» — по коду `MarkCapturesSentAsync` (§0.е), автоматикой не воспроизводится (нужен реальный Ctrl+V в чужое окно). **Расхождение с F.7:** в картинке будет буква `A`, не `B` (§0.е, вариант 1) |
| **F.8** Открыть D в редакторе → «Копировать» / Ctrl+Shift+C → тот же результат | B4.2 | Живьём. На **существующем** снимке; для нового снимка ✓ ставить некуда (§1.B4.2) |

**Открытые вопросы G.**

- **G/B2** («если раскрытие через Measure меняет высоту списка — фиксировать по `Captures.Count`») — **закрыт до начала работ**: `ApplyListHeight` уже считает высоту по `Captures.Count`, панель не меряется (§0.а). Запасной план не понадобится.
- **G/B3** («двойной клик — на усмотрение Никиты») — предлагаю сделать, механика в §1.B3 пункт 5; если откажется, выкидывается одним обработчиком, остальное не зависит.
- **G/B4** («форматы буфера для одного снимка должны совпадать с пакетом; проверить в Claude/ChatGPT/Telegram») — совпадение обеспечено конструктивно: один и тот же `CreatePackageDataObject`, который при одном пути уходит в `CreatePngDataObject` (§0.е). Живая проверка в трёх чатах остаётся, автоматикой не закрывается.
- **G/A1 ТЗ №5** — не моя дорожка.

---

## 4. Изменение формата

**Изменение формата.** В `settings.json` добавляется ключ `StackHeightManual` (bool, по умолчанию `false`) — тянул ли пользователь угол ленты руками. Изменение аддитивное в обе стороны: файл без ключа читается и даёт `false`, то есть прежнее поведение «высота по содержимому, сохранённое число — потолок»; файл с ключом читается старым билдом, лишний ключ игнорируется. Смысл существующего `StackHeight` (double, по умолчанию 372) при `StackHeightManual = false` не меняется — это потолок; при `true` то же число становится высотой списка, к которой по-прежнему применяются пол `MinimumListHeight = 180` и потолок «рабочая область монитора минус хром окна» (`StripResizeGeometry.ClampListHeight`). Правила миграции не добавляются, `SettingsMigration.CurrentVersion` остаётся 2: аккаунты, которые уже тянули угол в 1.6.x, откроются в автоматическом режиме и перейдут в ручной при первом же перетаскивании. Mac переносит ключ, дефолт и обе ветки `ListHeight` синхронно.

`session.json`, `manifest.json`, `prompt.md` и формат ID горячих клавиш дорожкой B не меняются. Отдельно для Mac: `SessionWorkspace.ExportSingleAsync` строит `SnapikSession` из одного снимка **не увеличивая `Revision`** и на диск его не пишет — имя каталога экспорта (`revision-NNNNNN-<guid>`) у одиночной копии повторяет номер последней сохранённой ревизии, что допустимо, потому что имя каталога нигде не разбирается (единственный читатель — `PreparedExport.GetImagePathsInOrder`, он берёт имена файлов из манифеста). Пакет из одного снимка нумеруется буквой `A` по общему правилу «снимки в пакете нумеруются заново», буква карточки ленты в картинку и в текст не попадает.
