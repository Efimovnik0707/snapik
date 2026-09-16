# Волна 0 (ТЗ №5): фундамент раунда 1.6.0

База: `master` = `980ee4d` (код 1.5.0 плюс документы раунда), ветка `tz-006-w0`. План:
`tasks/tz-006-plan.md`, §3 «Контракт волны 0» и §4 «Волна 0». По требованию Никиты прогон один на всю
волну, а не на коммит: `scripts/build.ps1 -OutputDirectory $env:LOCALAPPDATA\Temp\snapik-candidate-w0`
зелёный с первого раза. На выходе волны 212 + 38 + 62 = **312 тестов** и `--smoke-test` (на входе было
165 + 38 + 62 = 265). Промежуточно гонялся `dotnet build Snapik.slnx` — четыре раза, без тестов.

## Что сделано

| # | Что | Коммит | Как проверено |
|---|---|---|---|
| W0-0 | `HotkeyChoice` и `HotkeySettings` уехали из `HotkeySettingsWindow.xaml.cs` в `src/Snapik.App/HotkeySettings.cs`; `OutlineColorOf` и новый `PressTarget` — в `src/Snapik.App/Controls/AnnotationRules.cs`; тест-проект получил `ProjectReference` на `Snapik.Windows` и три `<Compile Include>` | `2456fde` | Диффом «вырезал — вставил», тела не тронуты; `git show --stat` показывает перемещение; сборка тест-проекта с новыми ссылками зелёная; в `AnnotationCanvas.cs` тела `OutlineColorOf` не осталось |
| W0-1 | Десять новых пар RU/EN по §6, удаление двух пар переключателя масштаба из `UiLanguage.cs` и из языковой таблицы смоука | `734cf79` | `grep -o '\["[^"]*"\]' UiLanguage.cs \| sort \| uniq -d` пуст; то же по английским значениям пусто; смоук-инвариант «две русские строки не делят один английский перевод» зелёный |
| W0-2 | Константы `StripResizeGeometry` (`EmptyListHeight`, паддинги списка врозь, `CardHeight`/`CardOverlap`/`CardPitch`), `ListHeightForCount`, `CapsuleLeft`, `RestoreRect`, новое тело `CardWidth` | `6c2679a` | Десять новых случаев в `StripResizeGeometryTests`: восемь высот списка (0→92, 1→100, 2→130, 5→220, 12→372, потолок 500→430, потолок 130→130, `NaN`→372), `CapsuleLeft(1600,244,180)→1664`, три случая `RestoreRect`; старый `CardWidth(244)==168` остался зелёным |
| W0-3 | Прикреплённое свойство `Controls/RoundedClip.cs` | `58484c8` | Сборка; тестов нет по плану, вид проверяет B-5 глазами |
| W0-4 | `Fit` вернул `double` и потерял `FitResult`/`FitBound`, появился `PlaceCapture`; новый `Controls/ToolbarLayout.cs` (`Measure` + переехавший `PlaceToolbar` с `mayOverlap`); `OverlayEditorWindow.Toolbar.cs` удалён, три вызывающих перенацелены | `d985156` | Шесть новых случаев `PlaceCapture`, четыре `Measure`, два `PlaceToolbar`; три старых теста `Fit` переписаны на число; `grep -rn "FitResult\|FitBound\|OverlayEditorWindow.Toolbar.cs" src tests` пуст; смоук-проверка «панель не закрывает снимок, когда снаружи есть место» зелёная с `mayOverlap: false` |
| W0-5 | `src/Snapik.App/ToolAppearance.cs` целиком: запись, `ToolAppearanceStore.Read/Write`, `InspectorView`/`EditorInspector`; ключ `toolAppearance` в `HotkeySettings` | `11e8948` | Пять тестов в `ToolAppearanceTests`: таблица `InspectorViewOf` по десяти инструментам, `InspectedTool`, чтение файла без ключа, чтение файла с ключом (неизвестный инструмент пропускается), круг `Write`→`Read` по сценарию Кати с проверкой зеркала `AnnotationColor`/`AnnotationThickness`/`AnnotationHighlightThickness`/`AnnotationFontSize`; смоук-проверка `restoredSettings != customSettings` (равенство записи настроек) зелёная |
| W0-6 | `AnnotationRules.OutlineColorOf` потерял `fillColor`, обе точки применения переписаны | `0482411` | `trace_call_path` inbound перед правкой дал ровно две точки (`AnnotationCanvas.DrawBoxShape`, `WpfExportImageRenderer.RenderAnnotated`); тест на четыре заливки; смоук-проверки экспорта PNG всех заливок зелёные |
| W0-7 | `ExportMargin` и `ExportMargins` в `Imaging/NoteBadgeGeometry.cs` | `a3eb1f6` | Девять тестов в `NoteBadgeGeometryTests`: пустой список, бейдж без `Offset`, бейдж внутри снимка, четыре стороны, два бейджа врозь, комментарий без номера, длинная подпись |
| W0-8 | Тело `AnnotationRules.PressTargetOf` | `f17bddc` | Таблица девяти входов в `AnnotationRulesTests` (панорама, ластик, обрезка поверх объекта, двойной клик по тексту и по рамке, якорь, ручка выделенного, `Conceal` наравне с остальными, пусто) |
| W0-9 | `src/Snapik.App/TaskbarPinLegacy.cs` целиком (COM-обёртки `IShellLink`/`IPersistFile`/`IPropertyStore`/`SHChangeNotify` плюс `ChooseLegacyPin`, `IsOurs`, `ReadShortcut`, `Retarget`, `CarryOverPin`); табуляция в `installer/Snapik.iss:112-113` | `72106e7` | Девять тестов: `ChooseLegacyPin` на пяти наборах, `IsOurs` на четырёх; `cat -A installer/Snapik.iss` на `:112-113` больше не показывает `^I`, путь читается как `{sys}\taskkill.exe` |
| W0-10 | Эти заметки | этот коммит | — |

## Изменение формата

> **Изменение формата (`settings.json`).** Файл получает ключ `toolAppearance` — словарь «инструмент → его
> настройки» (`color`, `thickness`, `lineStyle`, `fill`, `fillColor`, `fontSize`, `arrowStyle`, `shape`;
> имена инструментов camelCase: `rectangle`, `arrow`, `pen`, `highlight`, `text`, `blur`; `null` в
> `fillColor` означает «как обводка»). Прежние общие ключи `AnnotationColor`, `AnnotationThickness`,
> `AnnotationHighlightThickness`, `AnnotationFontSize` **остаются и продолжают писаться** зеркалом рамки,
> маркера и текста, поэтому файл, записанный 1.6.0, полностью читается 1.5.0, и установка в обе стороны
> настроек не теряет. При чтении файла без `toolAppearance` каждый инструмент получает старые общие
> значения, то есть файл 1.5.0 открывается ровно так, как выглядел. Неизвестный инструмент в словаре
> пропускается молча. `SettingsVersion` не поднимается: миграция здесь по отсутствию ключа. Поле
> `PaletteSet.Quick` удалено из кода (дорожка C), в файл оно не писалось. Побочное следствие правила 6:
> рамка теперь помнит фигуру, заливку и её цвет между снимками, тогда как раньше каждый снимок начинался
> с контурной рамки.

> **Изменение формата (`session.json`, `prompt.md`).** `parentAnnotationId` у комментария выведен из
> обращения: с 1.6.0 **не пишется**, но продолжает читаться. Сессия 1.5.0, открытая заново, сохраняет
> подпись «К отметке A2» в панели комментариев и пометку «(к области A2)» в `prompt.md`; у новых
> комментариев подпись всегда «К снимку A», и при переносе рамки комментарий не двигается.
> `SchemaVersion` не меняется, ключ из старых файлов читается как раньше, в новых файлах его просто нет.
> Очистка повисшей ссылки при обрезке (`CaptureCropper.cs:75-76`) и валидация остаются: они защищают
> чужой файл. Тем же приёмом живёт `LegacyHasOutline` с прошлого раунда.

Второй абзац описывает поведение, которое включает дорожка C (снятие записи `ParentAnnotationId`); в
волне 0 кода под него нет, абзац написан здесь, потому что так велит §7 плана.

Отдельно, не формат: **`StackHeight` из «высоты списка» стал «потолком высоты списка»** — `ClampListHeight`
сигнатуры не сменила, но её результат теперь отдаётся в `ListHeightForCount` как потолок. И **старый снимок
с заливкой перекрасится**: `OutlineColorOf` больше не смотрит на `fillColor`, отметка 1.5.0 с
`Fill=Solid`, `FillColor=#0000FF`, `StrokeColor=#FF3B30` нарисуется с красной обводкой.

## Отклонения от контракта и решения на месте

- **`PressTargetOf` объявлен не в W0-0, а в W0-8.** §3 просит положить в `AnnotationRules.cs` сразу и
  `PressTarget`, и `PressTargetOf`, но метод без тела в статическом классе не компилируется, а заглушка
  оставила бы в коде `NotImplementedException`. В W0-0 уехало перечисление `PressTarget`, тело и тест
  пришли в W0-8, как и написано в его строке плана.
- **`InspectorViewOf` не зовёт `StrokePattern.Participates`.** §3 требует свести к нему `HasLineStyle`
  «внутри `InspectorViewOf`», но у `InspectorView` нет поля под «пунктир предлагается»: у маркера
  `Second = Line` (толщина), а `Participates(Highlight) == false`. Таблица `C2 §1.4` и тест §1.11 п. 1
  требуют именно `Line`. Взята таблица; правило «маркер без пунктира» остаётся на
  `StrokePattern.Participates`, как сегодня в `Appearance.cs:49`, и дорожка C зовёт его сама при наполнении
  второй капсулы. Заодно `StrokePattern.cs` не пришлось линковать в тест-проект.
- **Цвет по умолчанию продублирован.** `ToolAppearance.DefaultColor` — та же `#FF3B30`, что и
  `OverlayEditorWindow.DefaultAnnotationColor` (`Appearance.cs:20`), но записана заново: файл линкуется в
  тест-проект, а окно — нет. То же самое сделано с AUMID: `TaskbarPinLegacy.AppUserModelId` повторяет
  `TaskbarPinService.AppUserModelId` (`:26`). Дорожкам A и C: если будете править эти файлы, сведите пары
  к одному источнику (`TaskbarPinService.AppUserModelId = TaskbarPinLegacy.AppUserModelId`).
- **Словарь `toolAppearance` хранится как `Dictionary<string, ToolAppearanceEntry>`, а не как
  `Dictionary<EditorTool, ToolAppearance>`.** `HotkeySettings` — публичная запись, а `ToolAppearance`
  internal, и `System.Text.Json` не пишет internal-типы; плюс ключи-перечисления сериализуются числом.
  `ToolAppearanceEntry` (публичная запись со строками и `[JsonPropertyName]`) даёт ровно тот JSON, что
  описан в §7. Сигнатуры `Read`/`Write` из контракта не изменились.
- **`TryRead` пришлось научить новому ключу.** Словарь, как и массив палитры, сравнивается по ссылке:
  без нормализации пустого словаря к одному экземпляру и без переноса ссылки в вычисление `migrated`
  каждый старт переписывал бы `settings.json`, а смоук-проверка `restoredSettings != customSettings`
  падала бы. Сделано по образцу `KeepPaletteColors` (`KeepToolAppearance`).
- **Ключ в JSON один camelCase среди PascalCase.** Остальные поля `settings.json` пишутся именами
  свойств (`"AnnotationColor"`), а `toolAppearance` — так, как требует §3 и §7. Это осознанная
  несогласованность файла; если Никита предпочтёт единообразие, менять надо одно место (атрибут
  `[JsonPropertyName]`), пока ключ не уехал к пользователям.
- **`SyncScaleSwitch` пережил потерю `FitBound`.** Переключатель масштаба удаляет дорожка C (задача C-1),
  но `Fit` потерял сторону уже сейчас, поэтому подпись сегмента строится единственной оставшейся парой
  «По ширине · {0} %» — а её W0-1 из таблицы удалил, то есть в английском интерфейсе до C-1 подпись
  останется русской. Смоук это переживает: он строит ожидание тем же вызовом `UiLanguage.Text`.
- **`mayOverlap` для `PositionToolbar` взят из `C1 §2.4` дословно:**
  `_capture?.Kind == CaptureKind.Fullscreen || _isNew`. До того, как C-1 включит `PlaceCapture`, снимок из
  ленты на полный экран может увести панель вниз рабочей области вместо наложения на снимок — это и есть
  задуманное поведение, просто раньше срока.
- **`installer/Snapik.iss` правился скриптом на Python, и первый заход добавил файлу BOM.** Замена
  `\t` → `\taskkill` в heredoc съедалась обратной косой; сделано через `chr(9)`/`chr(92)` в файле-скрипте,
  BOM убран, в диффе ровно две строки.
- **`detect_changes` по этому worktree работает только после отдельного `index_repository`** (индекс
  строится по корневому репозиторию). Проиндексирован, blast radius сверен: под правками `Fit`,
  `PlaceToolbar`, `OutlineColorOf`, `ListHeightForCount` и `TryLeader` graph показывает ровно те
  вызывающие, что перечислены в колонке «что не должно сломаться». Проект
  `c-Users-tomat-AppData-Local-Temp-snapbrief-wt-W0` в кэше графа можно удалить после слияния.

## Что нужно знать дорожкам

- **Все адреса `file:line` из плана и разборов сдвинулись** в `HotkeySettingsWindow.xaml.cs` (минус 297
  строк: файл начинается с `HotkeySettingsWindow`), `AnnotationCanvas.cs` (минус 10),
  `OverlayEditorWindow.xaml.cs` (плюс 1) и `UiLanguage.cs`. Искать по имени, а не по номеру строки.
- **A:** `TaskbarPinLegacy.CarryOverPin()` готов и **никем не зовётся** — строку в `App.xaml.cs` после
  `AppDataPaths.CarryOverLegacyData()` и гейт `TurnedOff()` ставит A. `ChooseLegacyPin` возвращает `null`,
  когда наш `Snapik.lnk` уже лежит рядом со старым: это случай «закрепов два», под который в мастере
  нужна запасная строка. `IsOurs(fileName, target, appId, processPath)` ждёт, что `.lnk` прочитан
  `ReadShortcut`; `TaskbarPinService.IsOurShortcut` на него ещё не переведён. Три строки RU/EN для
  мастера уже в `UiLanguage.cs`. Табуляция в установщике починена.
- **B:** `StripResizeGeometry.ListHeightForCount(count, cap)`, `CapsuleLeft`, `RestoreRect`,
  `EmptyListHeight`, `ListTopPadding`, `ListBottomPadding`, `ListPaddingLeft = 4`, `ListPaddingRight = 12`,
  `CardHeight`, `CardOverlap`, `CardPitch` готовы; `ListPadding` удалён, `CardWidth(244)` по-прежнему 168.
  Имя константы шага — `CardPitch`, не `CardStep` (§2 плана). `Controls/RoundedClip.cs` ждёт
  `Controls:RoundedClip.Radius="10"` на внутреннем `Grid` карточки. Пара «Свернуть» = «Minimize» уже есть,
  новой заводить не надо.
- **C:** `EditorGeometry.Fit` теперь возвращает `double`, `PlaceCapture(image, work, panel, gap, margin)`
  готов; `ToolbarLayout.Measure(tools, properties, actions, freeWidth, …)` и
  `ToolbarLayout.PlaceToolbar(crop, work, size, notes, mayOverlap)` лежат в `Controls/ToolbarLayout.cs`,
  `OverlayEditorWindow.Toolbar.cs` удалён. `ScaleSwitch`, `SyncScaleSwitch`, `OnFitScaleClick`,
  `OnOneToOneScaleClick`, `_fitBox` **живы** и удаляются задачей C-1 вместе с их учётом в `PositionToolbar`
  и в смоук-пробе `RunEditorScaleProbe`. `ToolAppearanceStore.Read/Write`, `EditorInspector.InspectorViewOf`
  и `InspectedTool`, `AnnotationRules.PressTargetOf` и `AnnotationRules.OutlineColorOf(fill, color)`
  готовы; `NoteBadgeGeometry.ExportMargins` считает поле, рендерер ещё не тронут. Ресурс
  `ToolbarPropertiesWidth` объявляет C-2, волна 0 его не заводила. Двенадцать цветов «неона» лежат в §3
  плана.

## Живьём не проверено

Прогон был только автоматический (`scripts/build.ps1`), окна на экране не открывались:

- перенацеливание закрепа: COM-часть `TaskbarPinLegacy` (`ReadShortcut`, `Retarget`, `SHChangeNotify`)
  не выполнялась ни разу — ни в тестах, ни в смоуке. Первый запуск её кода будет у дорожки A;
- клип `RoundedClip` на карточке ленты;
- поведение `PlaceCapture` и двухстрочной панели на живом мониторе 1366×768 и на 125 %;
- чтение и запись `toolAppearance` настоящим `settings.json` (в тестах это запись в памяти плюс общий
  round-trip настроек в смоуке).
