# План по ТЗ №2, зона B: лента снимков, A6, F1 (лента), D1 (лента), E (заметка)

Код сверялся с HEAD `a9381e6` (1.2.0), все ссылки file:line по нему. Рамка прежняя: просто, в духе Apple, привычные паттерны, настройки не перегружать. Правила `AGENTS.md` действуют: новые строки UI только парой RU/EN в `src/Snapik.App/UiLanguage.cs`, изменения форматов отдельным абзацем «Изменение формата» в `tasks/verification.md`, один коммит на законченную правку, `macos/` не трогать.

Зона этого документа: B1, B2, B3, B4, A6, F1 в части ленты, D1 в части ленты, E как архитектурная заметка. Блок C и D2 (панель комментариев внутри редактора) в этот план не входят, для D2 ниже есть раздел «Контракт для D2».

## 1. Что показал разбор кода

### 1.1. B1: как сессии устроены сейчас

**На диске.** Корень `%LOCALAPPDATA%\Snapik\sessions` (`SessionWorkspace.cs:32`), рядом на уровень выше `settings.json` и `last-region.json` (`:36`, `:43`). Внутри корня:

- `current-session.txt` (`:35`), текстовый указатель с GUID последней сессии;
- `<guid:N>\session.json` (`JsonSessionStore.cs:28`, `:45`);
- `<guid:N>\source\<captureId:N>.png` (`SessionAssetStore.cs:21-24`), оригиналы снимков;
- `<guid:N>\exports\revision-000123-<exportId:N>\` (`FileExportService.cs:32`), готовые пакеты: `01-A.png`, `02-B.png`, `prompt.md`, `manifest.json`;
- `<guid:N>\exports\.staging-*` на время записи.

`TrimExports` (`SessionWorkspace.cs:164-186`) оставляет три последние ревизии **внутри одной сессии** плюс закреплённые (`PinnedExportDirectories`, буфер и подготовленный пакет). Между сессиями не чистит ничего: каждая «Очистить ленту» оставляет прошлый каталог сессии целиком и навсегда. Диагноз ТЗ («файлы копятся без ограничений») подтверждён и он шире, чем «копится последняя сессия»: копятся все.

**`LoadCurrentAsync`** (`SessionWorkspace.cs:56-76`) читает `current-session.txt`, грузит `session.json`, **подменяет `SessionId` рабочего пространства на прочитанный** (`:63`) и возвращает снимки, у которых исходный PNG ещё лежит на месте. Вызов один: `EdgeStackWindow.xaml.cs:192`. Именно поэтому Катя увидела снимок из 1.0.0.

**«Выйти» в трее** (`EdgeStackWindow.xaml.cs:136`) и «Выйти» в «•••» (`:707`) делают одно и то же: `_exiting = true; Close()`. Дальше `OnClosing` (`:1437-1446`): первый заход отменяет закрытие, останавливает таймер, прячет тост, сохраняет сессию (`SaveAsync`), и только потом закрывается по-настоящему. Никакого удаления файлов нет.

**«Очистить ленту»** (иконка корзины `EdgeStackWindow.xaml:94` и пункт меню `:701`) идёт в `ClearStackCoreAsync` (`:1169-1204`): `StartNewSessionAsync` (`SessionWorkspace.cs:117-133`) **сохраняет старую сессию на диск** и создаёт пустую новую, отдаёт буфер (`ReleaseOwnedClipboardCoreAsync`), чистит стек «вернуть удалённый». То есть сегодня «Очистить» это архивирование, а не удаление. Это расхождение ТЗ с кодом стоит назвать прямо: ТЗ пишет «снимки сессии удаляются», а код их аккуратно складывает в архив.

**`--demo`.** `EdgeStackWindow.xaml.cs:73`: при `--demo` и пустом `--data-dir` корень уходит в `%TEMP%\Snapik\demo-<pid>`, и `LoadCurrentAsync` не вызывается вовсе (ветка `:188-189` сеет демо-снимки). Демо-режим B1 не затрагивает, но покажет новую логику выхода, если её не обойти явно.

**Smoke.** `--smoke-test` **не создаёт `EdgeStackWindow` вообще** (`App.xaml.cs:34-51`), `SmokeTestRunner` работает с `SessionWorkspace` напрямую по `SNAPIK_DATA_DIR` или по временному каталогу (`SmokeTestRunner.cs:17-18`). И там есть прямая проверка, которая ломается, если удаление встроить в `StartNewSessionAsync`: `SmokeTestRunner.cs:354-360` требует, чтобы после `StartNewSessionAsync` **старый `session.json` и старый исходный PNG остались на диске**. Вывод для executor: удаление обязано быть отдельным методом, а не побочным эффектом ротации.

**Ключ настроек «больше не спрашивать».** Сейчас такого ключа нет. Предлагаю `ConfirmSessionDiscard` (bool, по умолчанию `true`), формулировка положительная, чтобы старый файл без ключа давал «спрашивать», как и все остальные аддитивные ключи (`StackTopmost`, `ClearStackAfterPaste` и прочие, `HotkeySettingsWindow.xaml.cs:18-48`).

**Старые накопившиеся сессии при первом запуске новой версии: удалять.** Они уже недостижимы (читается только одна, та, на которую указывает `current-session.txt`), новый контракт «сессия живёт один запуск» делает их мусором по определению, а предупреждающий диалог и «Сохранить пакет…» закрывают риск потери. Принято по умолчанию, вопрос Никите ниже.

**Гарантия удаления при аварийном закрытии: чистим при следующем старте.** Это и есть механика: на старте удаляем всё, что лежит в корне сессий, и только потом начинаем свою. Отдельного watchdog не нужно.

**Ctrl+V-детект и чужое копирование ленту не чистят, и это уже так.** Проверено: `StartNewSessionAsync` вызывается ровно из одного места приложения, `EdgeStackWindow.xaml.cs:1178` (`ClearStackCoreAsync`). Ветка «чужое копирование» (`:391-400`, `:465-469`) только отпускает расписку и снимает публикацию. После вставки снимки остаются в ленте с флагом `Sent` (`MarkCapturesSentAsync`, `:1237-1253`), лента чистится только если пользователь сам включил `ClearStackAfterPaste`. Сохранить это поведение: новая логика B1 не должна добавлять удаление ни в один из этих путей.

**Непредвиденное следствие B1, которого в ТЗ нет.** Пакет кладётся в буфер **путями к файлам** (`WindowsClipboardService.cs:220-227`, `CreatePackageDataObject(pngPaths, text)`), а файлы лежат в `exports/revision-*` внутри каталога сессии. Значит после удаления каталога буфер указывает на несуществующие файлы: пользователь вышел из приложения, потом вставил в чат и получил пустоту или ошибку приложения-получателя. Решение принято: перед удалением отдавать буфер тем же `ReleaseOwnedClipboardCoreAsync` (`:1209-1223`), который уже используется при «Очистить»: он проверяет, что в буфере всё ещё наша запись, и только тогда затирает её пустым текстом. Тогда пользователь получает честно пустой буфер, а не сломанную вставку. Это единственное место, где я расширяю ТЗ, и оно вынесено в открытые вопросы.

### 1.2. B2: что мешает диагональному хвату

Сейчас есть только левый край: `Thumb x:Name="WidthGrip"` (`EdgeStackWindow.xaml:220-223`), ширина 6 px, `Margin="10,22,0,22"`, `Cursor="SizeWE"`, шаблон это прозрачный `Border`. Обработчики `OnWidthDragStarted/Delta/Completed` (`EdgeStackWindow.xaml.cs:589-600`), чистая геометрия в `Controls/StripResizeGeometry.cs` (окно 200..380, видимая карточка на 20 px уже за счёт `Margin=10` тени), значение пишется в `StackWidth` (`HotkeySettingsWindow.xaml.cs:30`), читается в `PositionAtEdge` (`:582`).

Высоты как настраиваемой величины **не существует вовсе**, и это главное расхождение с формулировкой ТЗ «меняет ширину и высоту». Окно живёт на `SizeToContent="Height"` (`EdgeStackWindow.xaml:6`) с `MinHeight="128" MaxHeight="620"`, а реальную высоту определяет `MaxHeight="372"` у `CaptureList` (`:105`). Прямое присваивание `Height` при `SizeToContent="Height"` будет затёрто следующим layout-проходом. Значит «тянем вниз» это изменение `CaptureList.MaxHeight`, а высота окна подтягивается сама. Это ровно то, что просит ТЗ («высота карточек не меняется, растёт видимая часть списка»), просто реализуется не через `Window.Height`.

Второе расхождение: курсор. Хват в **левом нижнем** углу тянется по диагонали северо-восток / юго-запад, значит `Cursors.SizeNESW`. `SizeNWSE` это диагональ для левого верхнего и правого нижнего углов, на левом нижнем он будет показывать стрелку не в ту сторону. Беру `SizeNESW`.

Третье: `Window MaxHeight="620"` перекроет любой рост списка выше этого порога, а реальное ограничение это рабочая область монитора, которую лента уже умеет считать (`StackWorkArea`, `:567-575`, с поправкой на DPI второго монитора). `MaxHeight` с окна снимаем, потолок считаем от рабочей области.

Четвёртое: тень `Margin=10` у `Shell` (`:81`) означает, что углы видимой карточки смещены на 10 px внутрь окна, и хват должен лежать поверх угла карточки, то есть `Margin="10,0,0,10"` от левого нижнего угла окна. И `WidthGrip` заканчивается в 22 px от низа, так что перекрытия почти нет, но угловой `Thumb` объявляем **после** `WidthGrip` в `Grid`, чтобы он выигрывал hit-test в полосе перекрытия.

Настройка `StackHeight` нужна: без неё лента после перезапуска возвращается к 372, и пользователь, который растянул её под десять снимков, каждый раз тянет заново. Ширина уже запоминается, асимметрия выглядела бы багом.

### 1.3. B3: тень между карточками, поправка к механике

Диагноз верный: карточки перекрыты на 48 px (`Margin="0,0,0,-48"`, `EdgeStackWindow.xaml:127`), разделены рамкой 1 px `#46505E` (`:128`), и на тёмном фоне это сливается.

Но тень «вниз» в этой раскладке **не будет видна**. В `VirtualizingStackPanel` при равном `Panel.ZIndex` элементы рисуются в порядке индексов, то есть карточка N+1 рисуется поверх карточки N и накрывает её нижние 48 px вместе с любой тенью, направленной вниз. Видимый стык это верхний край карточки N+1, лежащий на карточке N. Значит тень должна падать **вверх**: `DropShadowEffect` с `Direction="90"` (в WPF 0 это вправо, значения растут против часовой стрелки, дефолт 315 это вправо-вниз). Тогда каждая карточка отбрасывает тень на ту, что лежит под ней и нарисована раньше, и стопка читается.

Параметры из ТЗ сохраняются как есть: `BlurRadius="12" ShadowDepth="3" Opacity="0.5"`, меняется только направление. Альтернатива, если Катя настаивает на буквальной тени вниз: развернуть порядок отрисовки через `Panel.ZIndex`, привязанный к убывающему индексу. Это лишнее свойство в UI-модели и лишняя перенумерация, поэтому рекомендую `Direction="90"` и комментарий в XAML.

Производительность: `Effect` на элементе списка заставляет WPF рисовать поддерево через промежуточную поверхность. При лимите в 10 снимков (A6) это ничего не стоит, но связка «B3 без A6» на сотне снимков была бы заметна, так что A6 полезно делать не позже B3.

### 1.4. B4: кнопки шапки действительно без стиля

Подтверждено буквально: три кнопки шапки (`EdgeStackWindow.xaml:94`, `:97`, `:100`) заданы как `Background="Transparent" BorderThickness="0"` **без `Style`**, то есть берут дефолтный шаблон WPF. Его hover это светлая подложка, а иконка остаётся `#BFC8D6`, отсюда ощущение «бледнеет». Крестик карточки (`:148`) 27×27, без скругления (у него вообще нет `CornerRadius`, только `Background="#E6171A20"`), появляется через `Opacity` 0 → 1 в триггерах (`:167`, `:173`).

Тонкость реализации, которую executor обязан учесть: `Path` не наследует `Foreground`. Чтобы hover перекрашивал иконку в белый одним триггером, у каждого `Path` внутри кнопки `Stroke` (а у «•••» `Fill`) нужно заменить литерал на `{Binding Foreground, RelativeSource={RelativeSource AncestorType=Button}}`, а сам `Foreground` менять в стиле.

Вторая тонкость: скругление 8 у кнопок шапки и 12 у круглого крестика 24 px нельзя получить одним стилем с наследованием, потому что `CornerRadius` живёт внутри `ControlTemplate` и `BasedOn` его не переопределяет. Нужны два стиля с общими литералами цветов.

### 1.5. A6: лимита нет нигде

Подтверждено: в `Captures` добавляют четыре места, ни в одном нет верхней границы.

1. Захват: `EdgeStackWindow.xaml.cs:493` внутри цикла `CaptureLoopAsync`.
2. Импорт файлов: `:827`, в цикле по `dialog.FileNames` (мультивыбор включён, `:819`).
3. Импорт из буфера: `:846`.
4. Восстановление удалённого: `:1427` (`Captures.Insert`).

Буквы A..J сами по себе править не надо: `SentCaptureRules.StripLabels` (`Snapik.Core/Exporting/SentCaptureRules.cs:14-24`) раздаёт буквы только неотправленным снимкам, а `CaptureLabels.ForIndex` умеет и AA, AB. При потолке в 10 снимков в ленте неотправленных максимум 10, то есть дальше J буква не уйдёт никогда, никаких правок в Core по буквам не требуется. В Core стоит положить только саму константу, чтобы Mac и тесты брали одно число.

### 1.6. F1: где именно двойной звук

Диагноз верный, но ссылка `:496` косвенная. `EdgeStackWindow.xaml.cs:496-497`:

```
496:  var copied = await SaveAndCopyCommittedPackageAsync();
497:  UiSoundService.Capture(_settings);
```

Строка 496 сама звук не играет: внутри `SaveAndCopyCommittedPackageAsync` на `:647` вызывается `NotifyCopied()`, а он в `EdgeStackWindow.Saving.cs:11-15` первым делом делает `UiSoundService.Copied(_settings)` (`notify-soft-040`, гейн 0.7, `UiSoundService.cs:22`). Затем `:497` играет затвор (`shutter-2-050s`, гейн 1.0, `:20`). Отсюда два звука подряд.

Кто ещё зовёт `NotifyCopied`: `CopyPackageAsync` (`:870`, явное «Копировать пакет») и `RefreshOwnedClipboardCoreAsync` (`:1294`, то есть импорт, реордер, восстановление, удаление, пометка отправленных). После правки звук должен остаться только у явного «Копировать пакет», а баллон-уведомление «Снимки скопированы» сохраняется во всех.

Заодно видно, что затвор сегодня звучит **после** ожидания записи в буфер, то есть с задержкой в сотню миллисекунд от момента, когда снимок уже готов. Строку `:497` стоит поднять выше `:496`.

### 1.7. D1: что держит `CapturePreviewWindow` и чего в ТЗ нет

Диагноз верный: клик по карточке ведёт в `CapturePreviewWindow` (`EdgeStackWindow.Preview.cs:28-29`), и только кнопка «Разметка» (`CapturePreviewWindow.xaml:107`, обработчик `CapturePreviewWindow.xaml.cs:284`) открывает `OverlayEditorWindow`. Но удалить файл целиком нельзя вслепую, потому что:

**В конце `CapturePreviewWindow.xaml.cs` (строки 429-433) лежит `UiTextExtension`** — та самая markup-extension, через которую во **всех** XAML работает `{local:UiText ...}`. Удаление файла без переноса этого класса ломает сборку всего приложения. Класс надо перенести в `UiLanguage.cs`, это самая важная деталь D1.

**Что из логики просмотра реально надо сохранить, а что уже есть в редакторе:**

- Восстановление объектов из `session.json`: **переносить нечего**, редактор уже делает это сам. `EditExistingAsync` (`OverlayEditorWindow.xaml.cs:105-113`) кладёт в окно `existing.DeepClone()` (`:69`), со всеми `Annotations` (Kind, Points, Color, Thickness, Shape, Fill, ArrowStyle, Note, ParentAnnotationId, NoteOffset). Просмотр объекты только рисовал (`RenderPreview`, `CapturePreviewWindow.xaml.cs:77-85`).
- Legacy-комментарий снимка (`capture.Note`): редактор переносит его в независимую заметку `EditorTool.Comment` в конструкторе (`OverlayEditorWindow.xaml.cs:71-75`). Просмотр делал то же самое иначе, через `CommentEntry.ForCapture`. Ничего не теряется.
- Кроп: целиком в редакторе (`CaptureCropper`), в просмотре его не было.
- Повторный экспорт после правки: уже в ленте, `EdgeStackWindow.Preview.cs:48` вызывает `SaveAndCopyCommittedPackageAsync()`. Сохраняется дословно.
- Снятие флага `Sent` при правке: сегодня в двух местах. `EdgeStackWindow.Preview.cs:44` (после редактора) и `:65` в `PersistPreviewChangesAsync` (после правки комментариев прямо в просмотре). Второе исчезает вместе с просмотром, и это правильно: после D1 любая правка идёт через редактор, значит остаётся один путь. `PersistPreviewChangesAsync` удаляется целиком.
- Нумерация и подписи комментариев (`CommentEntry`, `RefreshCommentLabels`, `AnnotationName`, `CapturePreviewWindow.xaml.cs:115-148`): это **контракт для D2**, см. раздел 4.

**Три обработчика XAML живут в `EdgeStackWindow.Preview.cs` и нужны после удаления файла:** `OnOpenCaptureClick` (переписывается), `OnCaptureThumbMouseEnter` (`:73`, звук наведения) и `OnCaptureListMouseWheel` (`:75`). Их надо перенести в `EdgeStackWindow.xaml.cs` рядом с остальными обработчиками списка (около `:1397`), и только потом удалять файл.

**Smoke сломается:** `SmokeTestRunner.cs:241-248` строит `CapturePreviewWindow.RunPreviewProbe` (`CapturePreviewWindow.xaml.cs:318-370`). Пробник проверял: метки комментариев совпадают с экспортными (`CaptureLabels.ForNotedAnnotations`), пустая заметка показывает «+», после удаления нумерация закрывает дыру, список выдерживает 300 комментариев, окно просмотра помещается в рабочую область монитора с отрицательным origin при 150% DPI. Первые четыре проверки должны переехать в пробник D2 (панель комментариев в редакторе), пятая умирает вместе с окном (редактор полноэкранный, ему эта геометрия не нужна).

**Строки `UiLanguage.cs`,** которые становятся мёртвыми и подлежат удалению вместе с окном: «Просмотр снимка», «По размеру окна», «Увеличить», «Уменьшить», «На весь экран», «Вернуть размер», «Разметка», «Закрыть просмотр» (`UiLanguage.cs:37-38`). Остаются и переиспользуются в D2: «Комментарии», «Нет комментариев», «Комментарий к снимку», «К снимку», «К отметке», «Добавить комментарий», «Удалить комментарий» (`:36`, `:39-40`).

`Snapik.App.csproj` перечисляет файлы неявно (глоб SDK, исключён только `MainWindow`), поэтому правок в csproj удаление не требует.

### 1.8. E: что именно ломается при отказе от `AllowsTransparency`

Сегодня лента это `WindowStyle="None" AllowsTransparency="True" Background="Transparent"` (`EdgeStackWindow.xaml:7`), скругление даёт `Shell` (`CornerRadius="16"`, `:81`), тень даёт `DropShadowEffect` внутри `Margin="10"` (`:81-82`). `ThemeService` (`ThemeService.cs:13-50`) сегодня умеет только подменять словарь акцента, темы как словаря не существует: тёмная схема живёт инлайновыми литералами по окнам, а `Themes/SnapikTheme.xaml` описывает **светлую** схему (Paper / Chrome / Ink, `:4-24`), которую никто не применяет к ленте. Это ровно та находка, что была в плане ТЗ №1 (D7 фаза 2), она никуда не делась.

Что нужно для Acrylic и что при этом ломается, по пунктам:

- **API.** `DwmSetWindowAttribute(hwnd, DWMWA_SYSTEMBACKDROP_TYPE = 38, ref int value, sizeof(int))` со значением `DWMSBT_TRANSIENTWINDOW = 3` (акрил) плюс `DWMWA_USE_IMMERSIVE_DARK_MODE = 20` для тёмного варианта. Работает на Windows 11 22621 и новее. На 22000 официального атрибута нет (там был недокументированный `SetWindowCompositionAttribute`), значит порог поддержки лучше ставить по build >= 22621, всё ниже уходит в fallback.
- **`AllowsTransparency` обязан уйти.** Он делает окно layered с per-pixel alpha, и DWM системный backdrop под таким окном не рисует. Менять свойство можно только до создания HWND, то есть в конструкторе после `InitializeComponent()`, не позже `SourceInitialized`.
- **Скругление.** Без `AllowsTransparency` окно это настоящий прямоугольник, `CornerRadius` у `Shell` скругляет только рисунок, но не окно и не backdrop. Нужен `DWMWA_WINDOW_CORNER_PREFERENCE = 33` со значением `DWMWCP_ROUND = 2`; `WindowChrome.CornerRadius` сам по себе закругляет только кастомный chrome и backdrop не подрежет.
- **`Opacity` окна ломается прямо сейчас, и это не описано в ТЗ.** `Window.Opacity < 1` в WPF требует `AllowsTransparency="True"`. Сегодня этим пользуются два места: `Opacity = 0` в конструкторе (`EdgeStackWindow.xaml.cs:121`, снимается в `OnLoaded:175`) и `AnimateStackIn` (`:557-563`), который анимирует `OpacityProperty` самого окна. После отказа от прозрачности оба падают или перестают работать. Правка: анимировать `Opacity` у `Shell`, а не у окна.
- **Тень `Margin=10` исчезает вместе с ручным `DropShadowEffect`:** системная рамка рисует тень сама. Уходит и отступ, а за ним тянется вся геометрия, которая на него завязана: `PositionAtEdge` (`Left = work.Right - Width - 10`, `:583`), поля `WidthGrip` и нового `CornerGrip` (B2), и вся арифметика «видимая карточка на 20 px уже окна» в `StripResizeGeometry` (диапазоны 200..380 против 180..360). Это не «слегка поправить отступы», это пересчёт трёх согласованных констант плюс их тесты.
- **`SizeToContent="Height"`.** Сам по себе без `AllowsTransparency` живёт, но в связке с `WindowChrome` и `GlassFrameThickness="-1"` (который нужен, чтобы backdrop был виден в клиентской области) даёт неустойчивый ремер: об артефактах `SizeToContent` с системным ресайзом уже написано в `tasks/verification.md` (абзац про `WM_NCHITTEST`). Это место требует прототипа на 20 строк до любого планирования.
- **`WDA_EXCLUDEFROMCAPTURE`** (`SetWindowDisplayAffinity(handle, 0x00000011)`, `EdgeStackWindow.xaml.cs:219`). По механике не конфликтует: исключение из захвата это свойство окна, а backdrop считает DWM. Но проверять живьём обязательно, потому что два DWM-эффекта на одном окне это как раз тот класс вещей, которые молча перестают работать.
- **Ресайз левого края через `Thumb`** остаётся рабочим, это обычный элемент WPF. Но `WindowChrome` добавит **системную** полосу ресайза, которая перехватит те же пиксели: нужен `WindowChrome.ResizeBorderThickness="0"`, иначе система и `Thumb` будут драться за курсор. Системным ресайзом `Thumb` не заменить: B2 меняет не высоту окна, а высоту списка, системная рамка так не умеет.
- **Fallback на Windows 10:** оставить текущую конструкцию, `AllowsTransparency="True"` плюс сплошная панель, по ТЗ с прозрачностью 85%. Это значит, что одно и то же окно должно существовать в двух геометриях (с отступом 10 и без), выбираемых до создания HWND.

**Разумно ли делать E до палитр Кати.** Визуальную часть нет, инфраструктурную да, и она большая. Готовить сейчас имеет смысл три вещи, каждую отдельным коммитом и без единого нового цвета в UI:

1. Довести `ThemeService` до фазы 2: вынести оставшиеся тёмные литералы в `Themes/Dark.xaml` по семантическим ключам (Surface, Stroke, TextPrimary и так далее) и сделать тему подменой словаря, ровно как уже сделано с акцентом. Без этого «светлая» и «стекло» не наливаются никакой палитрой в принципе, и работа не зависит от того, какие цвета придут.
2. Добавить в настройки значение `Theme` из набора `dark` / `light` / `system` / `glass` (ключ уже есть, `HotkeySettingsWindow.xaml.cs:47`, сейчас всегда `dark`) и следящий за системой переключатель (`HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize\AppsUseLightTheme` плюс `WM_SETTINGCHANGE`). Вкладку «Вид» при этом не рисовать.
3. Написать `Interop/SystemBackdrop.cs` с P/Invoke и прототип: лента без `AllowsTransparency`, с backdrop, скруглением через DWM и анимацией на `Shell`. Прототип должен ответить на три вопроса до планирования: живёт ли `SizeToContent` рядом с `WindowChrome`, не отваливается ли `WDA_EXCLUDEFROMCAPTURE`, как выглядит акрил под лентой, прижатой к краю экрана.

Отдельно: переключение в «Матовое стекло» и обратно меняет `AllowsTransparency`, которое после создания окна не меняется. Пересоздавать окно ленты дорого (на нём висят горячие клавиши, иконка трея и наблюдатель вставки). Самое простое честное решение в духе Apple: смена этой темы применяется **после перезапуска приложения**, строкой-подсказкой под переключателем. Остальные темы (тёмная, светлая, системная) применяются сразу подменой словаря.

## 2. Решения по пунктам

Размеры S / M / L. Без оценок времени.

| # | Решение | Размер |
|---|---|---|
| B1 | **Сессия живёт один запуск.** Три части. (1) *Старт:* вместо `LoadCurrentAsync` (`EdgeStackWindow.xaml.cs:192`) вызывается новый `SessionWorkspace.PurgePreviousSessionsAsync()`: удаляет из корня сессий каждый подкаталог, чьё имя парсится как GUID в формате `N`, и файл `current-session.txt`; всё остальное в корне (`settings.json`, `last-region.json`, `startup.log` в режиме `--data-dir`) не трогает. Каталог, который не удалился (файл держит чужой процесс), пропускается с записью в `StartupTrace`, следующий старт попробует снова. Это же закрывает и аварийное закрытие, и накопленные старые сессии. `LoadCurrentAsync` и `RestoredGlobalNote`/`RestoredProfileId` становятся мёртвыми: `LoadCurrentAsync` остаётся в `SessionWorkspace` только ради smoke-проверок (`SmokeTestRunner.cs:313`, `:353`), из `EdgeStackWindow` уходит вместе со строками `:192-196`. (2) *Удаление:* новый `SessionWorkspace.DiscardCurrentSessionAsync()` удаляет каталог текущей сессии целиком (`session.json`, `source`, `exports/revision-*`, `.staging-*`) и `current-session.txt`, затем выдаёт новый `SessionId` и обнуляет `_revision`, `_createdAtUtc`, `PinnedExportDirectories`. **Отдельный метод, не внутри `StartNewSessionAsync`:** smoke-проверка `SmokeTestRunner.cs:354-360` требует, чтобы ротация оставляла старую сессию на диске, и она остаётся верной. (3) *Диалог:* новое модальное окно `DiscardSessionWindow` (по образцу `SavePackageWindow`, с `RunDiscardProbe` для smoke), открывается внутри `SuspendTopmost()`. Заголовок «Удалить снимки сессии?», текст «Снимки этой сессии будут удалены. Чтобы сохранить, нажмите «Сохранить пакет…» в меню •••», кнопки «Удалить» (по умолчанию) и «Отмена», галочка «Больше не спрашивать» пишет `ConfirmSessionDiscard = false`. Диалог показывается, если `Captures.Count > 0` **и** `_settings.ConfirmSessionDiscard`; на пустой ленте не показывается никогда. Точки вызова: «Очистить ленту» (`ClearStackFromUserAsync`, `:1225-1231`) и выход (`OnClosing` при `_exiting`, `:1437-1446`). «Очистить ленту» после подтверждения: `ReleaseOwnedClipboardCoreAsync` → `DiscardCurrentSessionAsync` → очистка `Captures`, `_removed`, тоста, `_prepared` → `Renumber` → тост «Лента очищена» (остальное тело `ClearStackCoreAsync` сохраняется, меняется только строка `:1178`). Выход после подтверждения: **не** вызывать `SaveAsync` (он воссоздал бы `session.json`), а отдать буфер, удалить каталог и закрыться. Отмена в диалоге на выходе: `_exiting = false`, `e.Cancel` остаётся `true`, `ShowStackWithoutActivation()`. Автоматический путь `ClearStackAfterPaste` (`:1239`) удаляет молча, без диалога. Системное завершение сеанса (`_exiting == false`) диалога не показывает, лента просто прячется, а файлы уберёт следующий старт. `--demo` не меняется (свой временный корень, свои демо-снимки), но покажет диалог на выходе как обычная лента, и это нормально. Ключ `ConfirmSessionDiscard` (bool, `true`) добавляется в `HotkeySettings` и в проброс `OpenSettings` не попадает: он живёт только через галочку в диалоге, отдельной строки в настройках не появляется (настройки не перегружаем). | L |
| B2 | **Диагональный хват в левом нижнем углу.** Новый `Thumb x:Name="CornerGrip"` в том же `Grid`, что и `WidthGrip`, **после него** (чтобы выигрывать hit-test в полосе перекрытия): `HorizontalAlignment="Left" VerticalAlignment="Bottom" Width="16" Height="16" Margin="10,0,0,10" Cursor="SizeNESW"`, шаблон прозрачный `Border`, как у `WidthGrip` (`EdgeStackWindow.xaml:222`). `WidthGrip` остаётся без изменений. Ширина считается тем же `StripResizeGeometry.Resize` с тем же зафиксированным правым краем. Высота: меняется **`CaptureList.MaxHeight`**, а не `Window.Height`, потому что `SizeToContent="Height"` затрёт любое присваивание высоты; высота карточки (78) и перекрытие (48) не трогаются. Новая чистая функция `StripResizeGeometry.ResizeListHeight(double listHeight, double delta, double chromeHeight, double top, double workBottom)`: `chromeHeight` это `окно.ActualHeight - список.ActualHeight`, возвращает высоту списка, зажатую в `MinimumListHeight = 180`, `MaximumListHeight = 720` и в `workBottom - top - chromeHeight` (лента растёт вниз, верхний край стоит на месте). Плюс `ClampListHeight(stored, workHeight)` по образцу `ClampWidth`. С окна снимается `MaxHeight="620"` (`EdgeStackWindow.xaml:6`), потолок теперь даёт рабочая область. Обработчики: `OnCornerDragStarted` запоминает `_resizeRightEdge = Left + Width` и `_resizeTop = Top` (по той же причине, что и у ширины: пересчёт на каждом шаге накапливает округление), `OnCornerDragDelta` применяет обе функции, `OnCornerDragCompleted` пишет `MutateSettings(s => s with { StackWidth = Width, StackHeight = CaptureList.MaxHeight })`. `PositionAtEdge` (`:577-585`) перед позиционированием ставит `CaptureList.MaxHeight = StripResizeGeometry.ClampListHeight(_settings.StackHeight, work.Height)`. Новая настройка `StackHeight` (double, по умолчанию 372) нужна: ширина уже запоминается, забывать высоту было бы асимметрично. Новых строк UI нет. | M |
| B3 | **Тень у карточки.** На `Border x:Name="ThumbCard"` (`EdgeStackWindow.xaml:127`) добавляется `<Border.Effect><DropShadowEffect Color="#000000" BlurRadius="12" ShadowDepth="3" Opacity="0.5" Direction="90" /></Border.Effect>`. `Direction="90"` (вверх), а не дефолтные 315 (вниз-вправо): при перекрытии `Margin="0,0,0,-48"` следующая карточка рисуется поверх предыдущей и тень, направленную вниз, полностью закрывает, см. раздел 1.3. Рамка `#46505E` и вся механика перекрытия, hover-анимации и `ZIndex` (`:120-121`, `:165-178`) не трогаются. Новых строк UI нет. Делать не раньше A6 (тень это эффект на каждом элементе списка, и лимит в 10 держит цену). | S |
| B4 | **Единый `IconButton` и круглый крестик.** В `Window.Resources` (`EdgeStackWindow.xaml:9-79`) два новых стиля. `IconButton`: `Width=26 Height=26 Padding=0 Background=Transparent BorderThickness=0 Cursor=Hand Foreground=#D9DEE8`, шаблон это `Border x:Name="Chrome" CornerRadius="8" Background="{TemplateBinding Background}"` с центрированным `ContentPresenter`; триггеры `IsMouseOver` → `Chrome.Background = #29303A` и `Foreground = White`, `IsPressed` → `Chrome.Background = #222932`, `IsKeyboardFocused` → рамка `{DynamicResource FocusBrush}` толщиной 1, `IsEnabled=False` → `Opacity 0.42` (как у `StackButton`, `:21`). `CardCloseButton`: то же, но `Width=24 Height=24`, `CornerRadius="12"`, базовый `Background="#CC0F1218"` (тёмная подложка нужна, крестик лежит на фотографии), hover `#E62A313C`, иконка так же белеет. Отдельный стиль, а не `BasedOn`: `CornerRadius` задан внутри `ControlTemplate` и наследованием не переопределяется. Три кнопки шапки (`:94`, `:97`, `:100`) получают `Style="{StaticResource IconButton}"`, крестик карточки (`:148`) получает `Style="{StaticResource CardCloseButton}"` и теряет локальные `Width/Height/Padding/Background/BorderThickness` (`Opacity="0"` и триггеры `:167`, `:173` остаются). Чтобы иконка перекрашивалась, у всех четырёх `Path` литерал цвета заменяется на `{Binding Foreground, RelativeSource={RelativeSource AncestorType=Button}}`: `Stroke` у корзины (`:95`), крестика шапки (`:101`) и крестика карточки (`:149`), `Fill` у «•••» (`:98`). Колонки шапки (`:86`) выравниваются: `*`, 30, 30, 30 вместо 26/28/24, кнопка 26 центрируется и даёт зазор 4. Новых строк UI нет, тултипы «Очистить ленту», «Ещё», «Свернуть в трей», «Удалить» уже есть в `UiLanguage`. | S |
| A6 | **Не больше 10 снимков.** Константа `public const int MaxStripCaptures = 10;` кладётся в `Snapik.Core/Exporting/SentCaptureRules.cs` (это уже общий с Mac контракт ленты) с комментарием, почему 10: буквы ленты не уходят дальше J. В `EdgeStackWindow` приватный хелпер `private bool StripIsFull(int adding = 1)`, который при переполнении показывает тост `UiLanguage.Text("В ленте максимум 10 снимков. Отправьте или удалите лишние")` и возвращает `true`. Считаются **все** снимки, включая отправленные: они занимают тот же диск и ту же память. Четыре точки. (1) Захват, `CaptureLoopAsync` (`:488-500`): проверка в начале тела `while`, **до** `HideForCapture()`, чтобы одиннадцатое нажатие клавиши не открывало редактор вовсе; при переполнении `addNext = false; continue;`. (2) Импорт файлов (`:815-839`): свободные места `MaxStripCaptures - Captures.Count`; если 0, тост и выход; иначе берутся первые `free` из `dialog.FileNames`, и если список обрезан, вместо тоста «Добавлено снимков: {0}» показывается тост лимита. (3) Импорт из буфера (`:841-851`): проверка сразу после `_pasteIntentTransition`. (4) Восстановление удалённого (`RestoreRemoved`, `:1422-1429`): проверка перед `Insert`, снимок остаётся в стеке `_removed`, чтобы его можно было вернуть после удаления другого. Пара строк UI: «В ленте максимум 10 снимков. Отправьте или удалите лишние» / "The strip holds at most 10 captures. Paste or delete some first." Буквы A..J правок не требуют (`SentCaptureRules.StripLabels` уже раздаёт их только неотправленным). Текст «до 10» в слайде 2 мастера это зона A5, у другого исполнителя. | S |
| F1 (лента) | **Один звук на захват.** Из `NotifyCopied` (`EdgeStackWindow.Saving.cs:11-15`) убирается строка `UiSoundService.Copied(_settings);`, метод оставляет только баллон «Снимки скопированы». Звук возвращается ровно в одно место: `CopyPackageAsync` (`EdgeStackWindow.xaml.cs:856-878`), строкой `UiSoundService.Copied(_settings);` непосредственно перед `NotifyCopied()` на `:870`. Тем самым пути «захват» (`:647`) и «обновление буфера после импорта, реордера, удаления, пометки отправленных» (`:1294`) звучать перестают, а баллон в них остаётся. Дополнительно строка `UiSoundService.Capture(_settings);` (`:497`) поднимается **выше** `var copied = await SaveAndCopyCommittedPackageAsync();` (`:496`): сейчас затвор ждёт записи в буфер и отстаёт от момента захвата. Выбор нового файла затвора, гейн 0.6 и дефолт громкости 60 → 40 делает аналитик звука, здесь только удаление вызова. Новых строк UI нет. | S |
| D1 (лента) | **Клик по карточке открывает редактор.** Порядок работ жёсткий. (1) `UiTextExtension` (`CapturePreviewWindow.xaml.cs:429-433`) переносится в конец `UiLanguage.cs` без изменений: без этого шага проект не собирается, `{local:UiText ...}` используется во всех XAML. (2) `OnCaptureThumbMouseEnter` и `OnCaptureListMouseWheel` (`EdgeStackWindow.Preview.cs:73-78`) переносятся в `EdgeStackWindow.xaml.cs` к обработчикам списка (около `:1397`). (3) `OnOpenCaptureClick` переписывается и тоже переезжает в `EdgeStackWindow.xaml.cs`: тело это текущие строки `EdgeStackWindow.Preview.cs:14-59` **без** блока `SuspendTopmost` с просмотром (`:24-31`), то есть `await _pasteIntentTransition` → проверка `_busy` и `Tag` → `capture.IsSelected = true` → `HideForCapture()` → `index = Captures.IndexOf(capture)` → `labelIndex = Captures.Take(index).Count(o => !o.IsSent)` → `OverlayEditorWindow.EditExistingAsync(...)` → при успехе `result.Capture.IsSent = false`, `Captures[index] = result.Capture`, `Renumber()`, `InvalidatePrepared()`, `requestNext = await SaveAndCopyCommittedPackageAsync() && result.AddNext` → `finally` снимает выделение, `_busy`, возвращает ленту. `SuspendTopmost` больше не нужен: `HideForCapture()` прячет все окна приложения, а редактор полноэкранный. (4) Удаляются три файла: `src/Snapik.App/CapturePreviewWindow.xaml`, `src/Snapik.App/CapturePreviewWindow.xaml.cs`, `src/Snapik.App/EdgeStackWindow.Preview.cs` (вместе с ним `PersistPreviewChangesAsync`). Правок в `Snapik.App.csproj` не требуется, файлы подключены глобом. (5) Из `SmokeTestRunner.cs:241-248` убирается пробник просмотра; проверки меток комментариев переезжают в пробник D2 (см. раздел 4), проверка границ окна (`CalculatePreviewBounds`) умирает вместе с окном. (6) Из `UiLanguage.cs:37-38` удаляются восемь пар: «Просмотр снимка», «По размеру окна», «Увеличить», «Уменьшить», «На весь экран», «Вернуть размер», «Разметка», «Закрыть просмотр». Пары «Комментарии», «Нет комментариев», «Комментарий к снимку», «К снимку», «К отметке», «Добавить комментарий», «Удалить комментарий» **остаются**, их переиспользует D2. Тултип карточки «Открыть снимок» (`EdgeStackWindow.xaml:130`) не меняется, новая строка не нужна. | M |
| E | Сейчас **не реализуем**. Готовим инфраструктуру тремя независимыми коммитами после волны B (подробности в разделе 1.8): фаза 2 `ThemeService` (тёмная схема как словарь `Themes/Dark.xaml`), значения `Theme` = `dark`/`light`/`system`/`glass` плюс слежение за системной темой, `Interop/SystemBackdrop.cs` с P/Invoke и прототип на ленте. Вкладку «Вид», светлую палитру и градиенты не трогаем до палитр Кати. Переключение в «Матовое стекло» и обратно применяется после перезапуска приложения (`AllowsTransparency` не меняется у созданного окна), строкой-подсказкой под переключателем. | L, отложено |

## 3. Файлы по пунктам (матрица параллельной работы)

Пути от корня репозитория. Ни один пункт этой зоны **не трогает** `OverlayEditorWindow*`, `Controls/AnnotationCanvas.cs`, `OnboardingWindow*`, `installer/*`. D1 только вызывает `OverlayEditorWindow.EditExistingAsync`, не правя его.

| # | Файлы |
|---|---|
| B1 | `src/Snapik.App/SessionWorkspace.cs`, `src/Snapik.App/EdgeStackWindow.xaml.cs`, `src/Snapik.App/DiscardSessionWindow.xaml` (новый), `src/Snapik.App/DiscardSessionWindow.xaml.cs` (новый), `src/Snapik.App/HotkeySettingsWindow.xaml.cs` (только запись `HotkeySettings`), `src/Snapik.App/UiLanguage.cs`, `src/Snapik.App/SmokeTestRunner.cs`, `tasks/verification.md` |
| B2 | `src/Snapik.App/EdgeStackWindow.xaml`, `src/Snapik.App/EdgeStackWindow.xaml.cs`, `src/Snapik.App/Controls/StripResizeGeometry.cs`, `src/Snapik.App/HotkeySettingsWindow.xaml.cs` (только запись `HotkeySettings`), `tests/Snapik.App.Imaging.Tests/StripResizeGeometryTests.cs`, `src/Snapik.App/SmokeTestRunner.cs`, `tasks/verification.md` |
| B3 | `src/Snapik.App/EdgeStackWindow.xaml`, `tasks/verification.md` |
| B4 | `src/Snapik.App/EdgeStackWindow.xaml`, `tasks/verification.md` |
| A6 | `src/Snapik.Core/Exporting/SentCaptureRules.cs`, `src/Snapik.App/EdgeStackWindow.xaml.cs`, `src/Snapik.App/UiLanguage.cs`, `tests/Snapik.Core.Tests/SessionModelTests.cs`, `src/Snapik.App/SmokeTestRunner.cs`, `tasks/verification.md` |
| F1 (лента) | `src/Snapik.App/EdgeStackWindow.Saving.cs`, `src/Snapik.App/EdgeStackWindow.xaml.cs`, `tasks/verification.md` |
| D1 (лента) | удаляются `src/Snapik.App/CapturePreviewWindow.xaml`, `src/Snapik.App/CapturePreviewWindow.xaml.cs`, `src/Snapik.App/EdgeStackWindow.Preview.cs`; правятся `src/Snapik.App/UiLanguage.cs`, `src/Snapik.App/EdgeStackWindow.xaml.cs`, `src/Snapik.App/SmokeTestRunner.cs`, `tasks/verification.md` |
| E (подготовка) | `src/Snapik.App/ThemeService.cs`, `src/Snapik.App/Themes/*`, `src/Snapik.App/App.xaml`, `src/Snapik.App/Interop/SystemBackdrop.cs` (новый), позже `EdgeStackWindow.xaml(.cs)` и все окна с тёмными литералами |

**Два потока, между собой не пересекаются, пока не дойдут до B2:**

- Поток 1 (C#): F1 → D1 → B1 → A6. Один и тот же `EdgeStackWindow.xaml.cs`, строго последовательно.
- Поток 2 (XAML ленты): B4 → B3. Один и тот же `EdgeStackWindow.xaml`, последовательно.
- B2 трогает **оба** файла (`EdgeStackWindow.xaml` и `EdgeStackWindow.xaml.cs`), поэтому идёт последним, когда оба потока слились.

## 4. Зависимости и порядок коммитов

Зависимости:

- **D1 раньше B1 и A6.** D1 удаляет файл-партиал `EdgeStackWindow.Preview.cs` и переносит из него обработчики; делать это поверх уже переписанного `OnClosing`/`ClearStack` из B1 значит решать тот же конфликт дважды.
- **A6 раньше B3.** B3 вешает `DropShadowEffect` на каждый элемент списка, лимит в 10 снимков держит цену эффекта.
- **B2 последним в зоне.** Ему нужен `StackHeight` в `HotkeySettings` и правки `PositionAtEdge` в `EdgeStackWindow.xaml.cs`, то есть он пересекается с обоими потоками.
- **E после всего и после палитр Кати.** Фаза 2 `ThemeService` перепишет `EdgeStackWindow.xaml` целиком, поэтому B3 и B4 должны лечь раньше, иначе их литералы придётся вносить дважды.
- B4, B3, F1 ни от чего не зависят и могут начинаться сразу.

Порядок коммитов, по одному на пункт, сообщения по-английски с префиксом `windows:`:

1. `windows: a capture plays a single sound` (F1 в части ленты)
2. `windows: the strip opens the editor and the preview window is gone` (D1)
3. `windows: a session lives for one run and is deleted on exit` (B1)
4. `windows: the strip holds at most ten captures` (A6)
5. `windows: icon buttons in the strip header and a round card close` (B4)
6. `windows: capture cards cast a shadow onto the stack` (B3)
7. `windows: the strip resizes by its bottom-left corner` (B2)

Дальше, отдельной волной и вне этого плана: `windows: dark theme as a resource dictionary`, `windows: theme setting follows the system`, `windows: system backdrop probe`.

## 5. Изменения форматов данных (для синхронизации с Mac)

Каждое попадает отдельным абзацем «Изменение формата» в `tasks/verification.md`.

1. **`settings.json`, `ConfirmSessionDiscard`** (bool, по умолчанию `true`). Аддитивно: старый файл без ключа даёт `true`, то есть диалог спрашивает; новый файл читается старым билдом (лишний ключ игнорируется). Ставится только галочкой «Больше не спрашивать» в диалоге удаления, в окне настроек не показывается. Mac переносит ключ, дефолт и место его записи. Коммит B1.
2. **`settings.json`, `StackHeight`** (double, по умолчанию 372). Аддитивно, как `StackWidth`. Это **максимальная высота списка снимков внутри ленты в пикселях**, а не высота окна: высота окна выводится из неё через `SizeToContent="Height"`. Значение вне 180..720 и не-число клампятся при чтении (`StripResizeGeometry.ClampListHeight`), плюс потолок по рабочей области монитора. Mac переносит ключ, дефолт, диапазон и смысл (высота списка, не окна). Коммит B2.
3. **`session.json` и `manifest.json` не меняются.** Ни одного нового поля, ни одного изменения схемы.
4. **Меняется жизненный цикл каталога сессий, не формат.** Отдельным абзацем, потому что Mac обязан повторить поведение, а не структуру: при старте приложение удаляет из корня сессий все подкаталоги с GUID-именами и `current-session.txt`; при «Очистить ленту» и при выходе удаляется каталог текущей сессии целиком (`session.json`, `source`, `exports`), предварительно отдаётся буфер, если в нём всё ещё наша запись. Восстановление прошлой сессии при старте больше не происходит. Пакет в буфере хранится путями к файлам внутри `exports/revision-*`, поэтому удаление без освобождения буфера оставило бы битую вставку.
5. **Константа ленты:** `SentCaptureRules.MaxStripCaptures = 10`. Формально это не формат данных, но Mac должен взять то же число, иначе две версии разойдутся в том, сколько снимков считается валидной сессией. Коммит A6.

## 6. Тесты и smoke

Что уже есть и на что опираемся: `tests/Snapik.App.Imaging.Tests/StripResizeGeometryTests.cs` (5 фактов по ширине и рабочей области), `tests/Snapik.Core.Tests/PersistenceAndExportTests.cs` и `SessionModelTests.cs` (сессия, prompt, метки), `SmokeTestRunner.cs` (round-trip настроек `:28-63`, пары RU/EN `:176-191`, флаг `Sent` и `StripLabels` `:309-321`, обрезка `exports/revision-*` до трёх `:329-344`, ротация сессии с сохранением старой на диске `:347-360`, пробник просмотра `:241-248`).

Добавить:

- **B1, smoke.** Новая проверка очистки: в корне создаются два каталога с GUID-именами и `current-session.txt`, рядом кладутся `settings.json` и произвольный `keep-me.txt`; после `PurgePreviousSessionsAsync` GUID-каталогов и указателя нет, посторонние файлы на месте. Новая проверка удаления: `AddImageAsync` плюс `PrepareAsync`, затем `DiscardCurrentSessionAsync`, после чего каталог сессии не существует, а `SessionId` сменился. Существующая проверка `:354-360` (ротация оставляет прошлую сессию на диске) **должна остаться зелёной**, это и есть контроль того, что удаление не заехало в `StartNewSessionAsync`.
- **B1, smoke round-trip настроек.** В `customSettings` (`SmokeTestRunner.cs:28-33`) добавляется `ConfirmSessionDiscard = false`, проверяется возврат значения.
- **B1, smoke, язык.** В список пар (`:176-189`) добавляются «Снимки этой сессии будут удалены. Чтобы сохранить, нажмите «Сохранить пакет…» в меню •••» и «Больше не спрашивать».
- **B1, smoke, окно.** `DiscardSessionWindow.RunDiscardProbe` через `WithoutBindingErrors` по образцу `SavePackageWindow.RunSavePackageProbe` (`:150`): окно строится без ошибок привязок, галочка возвращает значение, «Отмена» даёт `false`.
- **B2, юнит-тесты** в `StripResizeGeometryTests.cs`: тяга вниз увеличивает высоту списка и не двигает верхний край; высота упирается в 180 и 720; у нижней границы рабочей области высота ограничивается расстоянием `workBottom - top - chromeHeight`; `ClampListHeight` клампит сохранённое значение, `NaN` даёт 372.
- **B2, smoke.** `StackHeight = 300` в round-trip настроек.
- **A6, юнит-тест** в `SessionModelTests.cs`: `SentCaptureRules.MaxStripCaptures == 10` и `StripLabels` от десяти неотправленных даёт последнюю метку `"J"` (то есть буквы не уходят за J при полной ленте).
- **A6, smoke, язык.** Пара «В ленте максимум 10 снимков. Отправьте или удалите лишние» в список `:176-189`.
- **D1, smoke.** Блок `:241-248` удаляется целиком. Проверки меток комментариев (совпадение с `CaptureLabels.ForNotedAnnotations`, «+» у пустой заметки, закрытие дыры в нумерации после удаления, список из 300 комментариев) переносятся в пробник панели комментариев редактора, который делает D2. Если D2 не готов к моменту D1, проверки временно переносятся в чистый Core-тест над `CaptureLabels.ForNotedAnnotations` (без окна), чтобы не терять покрытие.
- **F1.** Юнит-теста нет (звук это побочный эффект). Проверка ручная, по сценарию «Как проверять» из ТЗ: захват даёт один звук, «Копировать пакет» даёт звук, импорт и удаление звука не дают. Записать в `tasks/verification.md` как «живьём не проверено» до живого прогона.
- **B3, B4.** Автотестов не требуют. Smoke ловит только ошибки привязок, а лента как окно в smoke не строится; после правок обязателен живой просмотр (в `verification.md` строкой «живьём не проверено» до проверки).

Прогон: `scripts/build.ps1` (тесты плюс `--smoke-test`) после каждого коммита.

## 7. Контракт для D2 (панель комментариев внутри редактора)

Что лента передаёт редактору при открытии существующего снимка **сегодня и после D1** (сигнатура не меняется, `OverlayEditorWindow.xaml.cs:105`):

```
EditExistingAsync(SessionWorkspace workspace, CaptureItem capture, int captureIndex)
```

- `capture` это `CaptureItem` целиком: `Id` (Guid, тот же, что в `manifest.images[].captureId`), `Image` (замороженный `BitmapSource`), `SourcePath` (относительный путь `source\<id:N>.png` внутри каталога сессии), `DisplayLabel` (буква ленты), `Note` (legacy-комментарий снимка), `IsSent`, `Annotations` (каждая: `Id`, `Kind`, `Points`, `Color`, `Thickness`, `Shape`, `Fill`, `ArrowStyle`, `Note`, `ParentAnnotationId`, `NoteOffset`, `Label`). Редактор работает с `DeepClone()` (`:69`), оригинал в ленте не мутируется до возврата результата.
- `captureIndex` это позиция снимка среди **неотправленных** (`Captures.Take(index).Count(o => !o.IsSent)`), из него берётся буква.
- Отличить «открыт из ленты» от «новый захват» **не требует новых параметров**: в окне уже есть поле `_isNew` (`:70`, `existing is null`). Панель комментариев показывается при `!_isNew`. Сигнатуру не менять, иначе D1 и D2 конфликтуют.
- Legacy-`Note` снимка редактор уже превращает в независимую заметку `EditorTool.Comment` в конструкторе (`:71-75`), отдельной ветки в панели для него не нужно.
- Лента ждёт обратно `OverlayEditResult` с `Capture` (новый экземпляр), `Cancelled`, `AddNext`. Всё остальное (снятие `Sent`, перенумерация, повторный экспорт, запись сессии) делает лента.
- Нумерация и подписи, которые надо воспроизвести из умирающего просмотра (`CapturePreviewWindow.xaml.cs:115-148`): номер строки берётся из `Snapik.Core.Exporting.CaptureLabels.ForNotedAnnotations(capture.DisplayLabel, capture.ToCore())`, у заметки без текста номера нет и показывается «+», подпись связи это «К отметке <метка родителя>» при непустом `ParentAnnotationId` и «К снимку <буква>» иначе, после удаления заметки нумерация пересчитывается и дыру закрывает. Строки «Комментарии», «Нет комментариев», «Комментарий к снимку», «К снимку», «К отметке», «Добавить комментарий», «Удалить комментарий» остаются в `UiLanguage.cs` специально для этого.

## 8. Открытые вопросы

Блокирующие:

1. **Никите, B1 и буфер.** После выхода PNG пакета удаляются, а в буфере лежат пути к ним. Предлагаю перед удалением отдавать буфер (затирать пустым текстом, если там всё ещё наша запись), иначе пользователь получит сломанную вставку в другом приложении через полчаса после выхода. Альтернатива: не трогать буфер и принять, что такая вставка не сработает. В ТЗ этого случая нет.
2. **Никите, B1 и старые сессии.** Первый запуск новой версии удалит всё, что накопилось в `%LOCALAPPDATA%\Snapik\sessions`, включая снимки, которые пользователь мог считать сохранёнными. Молча или один раз с уведомлением? Предлагаю молча: контракт «сессия живёт один запуск» иначе не читается.
3. **Кате, E.** Подтвердить, что переключение темы «Матовое стекло» применяется после перезапуска приложения (техническое ограничение WPF: `AllowsTransparency` не меняется у созданного окна). Остальные три темы переключаются мгновенно.

Принято по умолчанию, решения не требуют:

- Курсор углового хвата `SizeNESW`, а не `SizeNWSE`: хват в левом нижнем углу тянется по диагонали северо-восток / юго-запад.
- Тень карточки направлена вверх (`Direction="90"`): тень вниз перекрывается следующей карточкой и не видна.
- Диалог удаления не показывается на пустой ленте и не показывается при автоматическом `ClearStackAfterPaste`.
- При системном завершении сеанса диалога нет, лента просто прячется, файлы уберёт следующий старт.
- Лимит в 10 считает и отправленные снимки. Текст тоста из ТЗ («Отправьте или удалите лишние») в редком случае «все 10 отправлены» звучит неточно, но вторую строку ради этого не заводим.
- `ConfirmSessionDiscard` в окно настроек не выносится, живёт только галочкой в диалоге.
- Тултип карточки остаётся «Открыть снимок», новой строки под «открыть в редакторе» не заводим.
- `StackHeight` хранит высоту **списка**, не окна; имя короткое ради простого переноса на Mac, смысл фиксируется комментарием и абзацем «Изменение формата».
