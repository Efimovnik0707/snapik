# План по ТЗ №4 Кати (тест 1.4.0, 15.09.2026)

## 0. Статус и входы

Работа не начата. База: `master` = `ab3a764`, код на уровне `a2f72e1` (1.4.0), сверху только документы раунда (`5e4f8e5` передача ТЗ и разборы A-C, `ab3a764` разбор D). Все ссылки file:line в плане и в разборах даны по `a2f72e1`. Цель раунда: установщик 1.5.0.

Нумерация файлов: ТЗ называется «№4» (четвёртый документ от Кати), в репозитории это пятый раунд работ, поэтому план, разборы и заметки дорожек носят префикс `tz-005`.

Входы:

- ТЗ: `tasks/handoff-005/TZ-004-v140-test.md`, эталоны `tasks/handoff-005/reference-png/01…07` и `reference-html/*.html`, мастерская (ссылка в шапке ТЗ).
- Разборы кода: `tasks/tz-005-details/A-onboarding.md` (A1-A7, E2, UI-часть A5), `B-themes-accents.md` (B1, B2, B3, словари A5, E1), `C-strip.md` (C1-C9, лента-часть C8, A7), `D-editor.md` (D1, D2, D3, редактор-часть C8).
- Формат плана по образцу `tasks/tz-004-plan.md`.

Этот план держит решения, порядок и границы. Числа, координаты, полные списки мест правки и тела методов остаются в разборах; ссылки вида `A §3.2` ведут туда. Исполнителю читать свой раздел плана, раздел 3 целиком и названные параграфы своего разбора; разборы целиком читать не нужно.

Правила `AGENTS.md` действуют: коммиты в `master` этого репозитория, сообщение по-английски с префиксом `windows:`, один коммит на законченную правку, `macos/` и `.github/workflows/macos-build.yml` не трогать, новые строки интерфейса только парой RU/EN в `UiLanguage.cs`, любое изменение формата данных отдельным абзацем «Изменение формата», `MainWindow.xaml` не возвращать. Перед каждым коммитом `scripts/build.ps1` зелёный, иначе коммит не считается законченным.

Правило `CLAUDE.md` про граф связей действует для каждой задачи: перед правкой метода, свойства или ресурса исполнитель гоняет `trace_call_path` inbound и кладёт всех callers в список задачи, перед коммитом гоняет `detect_changes` по своей ветке и сверяет blast radius с тем, что тестировал. Субагент зовёт граф из Bash:

```
"C:/Users/tomat/.local/bin/codebase-memory-mcp.exe" cli trace_call_path '{"function_name": "ShowStackWithoutActivation", "direction": "inbound", "depth": 3}'
"C:/Users/tomat/.local/bin/codebase-memory-mcp.exe" cli detect_changes '{"scope": "branch", "base_branch": "master", "depth": 3}'
```

## 1. Что показал разбор кода

Шестнадцать мест, где картина шире диагноза ТЗ или причина другая. Это меняет объём и порядок.

1. **Пять тем из шести уже стоят в коде побайтно** (`dark`, `night`, `sunset`, `sea`, `dawn`), угол 160° уже выражен как `EndPoint="0.35,1"`. Вся работа B1 это удаление `Light.xaml`, переподпись карточки и миграция настроек, перекрашивать нечего (`B §1.1`, `§2.2`).
2. **«Стекло» расходится между эталонами.** `02-themes-applied.html` рисует старую матовую панель с `backdrop-filter`, градиент B есть только в `03`. Побеждает текст B2 и эталон 03; `ElevatedBrush` берётся 10 %, а 14 % из эталона 02 это `HoverBrush` (`B §1.2, §1.3`).
3. **C6 против C4 арифметически несовместимы.** Поле под тень 20 px и окно 224 дают панель 184 и карточку 148, а эталон `reference-png/04` подписан «панель 204 · карточка 168», то есть посчитан при поле 10. Развилка 1 (`C §0.1`, `§C6`).
4. **C1: индексы ломает не `Items.Refresh()`.** `AlternationIndex` раздаётся по цепочке уже реализованных контейнеров, а не по номеру в данных: при прокрученной ленте первый реализованный контейнер получает 0, каким бы ни был его номер. Плюс вторая половина, которой в ТЗ нет: удержанная анимация `Margin` от наведения (`FillBehavior=HoldEnd`, приоритет 2) навсегда побеждает сеттеры триггеров `IsSelected` и `IsKeyboardFocusWithin`, то есть выделение перестаёт двигать карточку после первого же наведения. Третья: `Refresh()` даёт `Reset` и сбрасывает прокрутку в 0, и зовётся трижды на один клик по карточке (`C §0.3, §0.4, §C1`).
5. **C1: «ItemsControl» это `ListBox`.** Тип не меняется, убираются `AlternationCount`, `Panel.ZIndex` и виртуализация (`C §0.2`).
6. **C2: белый ползунок 28/45 % ломает светлую тему.** Сейчас ползунок берёт `TextFaintBrush`, на `dawn` захардкоженный белый станет невидимым. Нужны токены в палитрах (`C §0.7`, `§8`).
7. **C7: `SetWindowDisplayAffinity` стоит ровно в одной строке и только на ленте.** Страховка «ставить флаг на время `HideForCapture`» не нужна и вредна: окно в этот момент уже скрыто (`C §0.6`, `§C7`).
8. **C9: «ошибка показывается в ленте» уже так** (`ImportFileAsync` пишет `SetStatus(..., true)`). Новая работа только в самом декодере (`C §0.5`).
9. **A1: окно настроек на `WindowChrome` не переходило,** оно layered (`AllowsTransparency="True"`), DWM его углы не скругляет в принципе и второго контура там нет. Для настроек пункт снимается (`A §1.1`).
10. **A2: обещанный снап не появится.** `ResizeMode="CanMinimize"` не снапится Windows. Требование A2 (тянуть за верхний пояс) выполняется, обещание про Win+стрелки снимается. Плюс в поясе 48 px лежат две кнопки ровно там, где `WindowChrome` держит невидимые aero-кнопки: нужен `UseAeroCaptionButtons="False"`, одного `IsHitTestVisibleInChrome` мало (`A §1.2, §1.3`).
11. **A4: «стрелка сдвигает на 116 px» не дефект,** а кламп, который доводит последнюю карточку до полной видимости; требования «шаг ровно 142» и «последняя карточка целиком» несовместимы ни при каком числе карточек. Настоящий дефект другой: галерея открывается прокрученной к выбранной теме (`BringSelectedCardIntoView`) (`A §1.5`).
12. **A6: 120 px обрежет слайд 4.** Строка подписи это 32 px при одной строке текста и 50 при двух, вторая строка слайда 4 переносится и в RU, и в EN, блок уже сейчас около 136. Нужно 140, при этом запас до скроллбара остаётся 3 px (`A §1.7`, `§A6`). Развилка 6.
13. **E2 сегодня не работает вообще:** `WriteOnboarding` в ветке `merge` пишет только `CaptureId`, `Language` и `OnboardingVersion`, то есть тема и акцент из мастера теряются на любом запуске поверх читаемого `settings.json`. Плюс «Пропустить» возвращает тему и акцент, но не язык (`A §1.8, §1.9`).
14. **D1 шире, чем описано.** Цвет отбрасывается не только у кружков панели, но и у всего поповера, спектра, HEX и пипетки (условие `HasColor(tool)` в одной точке присвоения); при инструменте «Комментарий» кнопка цвета вообще выключена. Мест `HasOutline` не восемь, а 27, включая Core, тесты и smoke. Миграция старой отметки `Redaction` завязана на `HasOutline` и обязана поменяться в том же коммите. Альфа полупрозрачной заливки расходится в трёх местах (`0x40`, `0x59`, `#59D9DEE8`) (`D §0.1, §0.2, §0.4, §0.5, §0.6`).
15. **D1: бейдж комментария сегодня красится акцентом,** а не цветом отметки. «Бейдж красится активным цветом» это новое поведение, а не восстановление сломанного (`D §0.3`). Развилка 4.
16. **C8-редактор заметно меньше, чем читается из ТЗ.** Вписывание по ширине и по высоте уже двустороннее и уже работает, а координаты отметок уже хранятся в пикселях исходника и переводятся в экран через одну переменную `_imageRect`. Режим 1:1 это подмена способа вычисления `_imageRect`, а не пересчёт разметки. Нет только подписи, переключателя, самого режима 1:1 и жестов (`D §0.11`, `§1.3`, `§5.1-5.2`).

## 2. Решения по развилкам

Приняты оркестратором 15.09.2026, Никита может развернуть любое.

| # | Развилка | Решение |
|---|---|---|
| 1 | C6 против C4: окно 224 или 244 | **Истина это то, что видит пользователь:** видимая панель 204 и карточка 168 из эталона. `ShadowMargin = 20`, `DefaultWidth = MinimumWidth = 244`, `EdgeGap = 0` (видимый зазор у края экрана остаётся 20 px, как сейчас: было поле 10 плюс зазор 10). Сохранённая пользователем `StackWidth` клампится снизу до 244 существующим `ClampWidth`, отдельного кода не нужно |
| 2 | Вид снимка в `session.json` | **Enum по-английски:** `region` / `fullscreen` / `import`, никаких русских литералов как ключей и как данных. `Title` заполняется только у импорта (имя файла); у снимка всего экрана он остаётся пустым, а подпись «весь экран» строится из `Kind`: в интерфейсе через `UiLanguage`, в `prompt.md` русским литералом внутри `PromptGenerator` (он и так русский целиком). Старые файлы без поля читаются как `region` |
| 3 | C8: редактор сразу или в ленту | **В ленту без редактора**, редактор по клику на карточку. Эталон `reference-png/05` разбит на три шага со вторым «Клик по карточке»; клавиша «весь экран» это жест «схвати всё прямо сейчас», полноэкранный редактор поверх 3840×1125 его смысл убивает (`C §C8`) |
| 4 | D1: бейдж комментария | **Остаётся акцентным**, активным цветом не красится: нумерация отметок это единая система, а не свойство конкретной рамки. Вынесено вопросом Кате (§9) |
| 5 | D3: нажатие по отметке своего типа | **Вариант Б** (`D §4.3`): нутро пустой рамки остаётся свободным (рамка внутри рамки возможна), полоса захвата по кромке расширяется с 6 до 10 px, захват комментария идёт по якорю, бейджу и пилюле |
| 6 | A6: высота блока подписей | **140, не 120.** 120 обрезает слайд 4 (`A §1.7`). Запас до появления скроллбара 3 px, больше 140 брать нельзя |
| 7 | A3: шаг 4 обрезан снизу | **Воспроизведение не требуется.** Делаем пересчёт `MaxHeight` в DPI монитора показа по формуле `A §A3` (масштаб берётся у монитора под курсором, позиция задаётся в физических пикселях, `OnDpiChanged` один раз довыравнивает) и пункт снимаем |
| 8 | C8-редактор: объём | **Минимальный вариант** `D §5.6`: подпись, переключатель «вписать ↔ 1:1», `ViewScale`/`ViewOffset`, колесо, Shift+колесо, Ctrl+колесо. Панорама пробелом делается тем же смещением `ViewOffset` и входит в задачу последней строкой; если она не укладывается в тот же механизм, уходит в «на потом» с записью в `tasks/tz-005-notes-D.md` |
| 9 | G2 ТЗ (панель задач) и B3 («настоящее стекло») | **На потом**, в план не входят. B3 зафиксирован в §10 условиями `B §4` |
| 10 | Число мониторов в подписи редактора | **Строка без склонения:** `мониторов: {0}` = `monitors: {0}`. Это снимает развилку `D §6` (две русские формы не могут делить одно английское значение, смоук держит инвариант уникальности). Если Катя хочет «2 монитора», добавляются две пары с разными английскими значениями, это правка одной строки плюс helper |
| 11 | E1, сегмент палитры «Своя» | **Остаётся фильтром ряда.** Убирать его значит терять сохранённый выбор у тех, кто уже на «Своей», ради строки, которая всё равно нужна редактору; развязка спектра и пипетки от режима делается в `Appearance.cs:320` в обоих случаях (`B §6.2`) |
| 12 | Миграция `light → dark` | **Вариант Б, явная миграция** (`B §2.4`): `SettingsMigration` получает правило темы, `CurrentVersion` 1 → 2, и **каждое правило получает свой порог**: `SoundVolume` спрашивает `storedVersion < 1`, тема `storedVersion < 2`. Без этого подъём версии второй раз прогонит правило громкости и молча уведёт на 40 тех, кто сам выставил 60 |

Отступления от разборов, зафиксированные здесь же:

- `C §C8` предлагал писать в `Title` русский литерал «весь экран». Решение 2 это отменяет: `Title` у снимка всего экрана пустой, подпись строится из `Kind`. Константа `FullscreenTitle` не заводится.
- `D §5.3` называл поля `CaptureSource`, `MonitorCount`, `SourceFileName`. Контракт раздела 3 фиксирует `CaptureKind Kind`, `int MonitorCount` и существующее `string Title` вместо третьего поля.
- `C §9` вопрос 3 («согласны, что `Title` остаётся русским») снят решением 2.
- `D §11` вопрос 3 (склонение) закрыт решением 10, вопрос 5 (`SettingsVersion` от удаления полей) закрыт: версия растёт не от удаления, а от миграции темы (решение 12).
- Волна 0 несёт удаление `HasOutline` **целиком**, а не только Core-часть: поле читают `AnnotationCanvas`, `WpfExportImageRenderer`, `Appearance.cs`, `HotkeySettings`, smoke и два теста, и разделить это на два коммита нельзя, сборка будет красной между ними.

## 3. Контракт волны 0

Всё, что дорожки A, C и D получают готовым. Имена типов, свойств, ключей ресурсов, констант и строк после волны 0 не меняются. Занятость имён проверена (`search_graph` и grep по `src` и `tests`): свободны все, кроме отмеченных.

**Core, вид снимка.** Новый `src/SnapBrief.Core/Models/CaptureKind.cs`:

```csharp
public enum CaptureKind { Region, Fullscreen, Import }
```

В `src/SnapBrief.Core/Models/CaptureItem.cs` рядом с существующим `Sent`:

```csharp
public CaptureKind Kind { get; init; } = CaptureKind.Region;
public int MonitorCount { get; init; }      // 0 = неизвестно; заполняется только у Fullscreen
```

Поля-`init`, а не параметры позиционного конструктора: старые `session.json` без `kind` и `monitorCount` читаются как `Region` и `0`, `SchemaVersion` остаётся 1. Отдельный конвертер не нужен, `SnapBriefJson.Options` уже держит `JsonStringEnumConverter(JsonNamingPolicy.CamelCase)`, то есть `Fullscreen` пишется как `"fullscreen"`. `Title` (позиционный параметр записи, существует) получает смысл: имя файла у `Import`, пустая строка у `Region` и `Fullscreen`.

**Core, подпись в `prompt.md`.** `PromptGenerator.Generate` получает частный статический метод:

```csharp
private static string? KindTitle(CaptureKind kind) => kind == CaptureKind.Fullscreen ? "весь экран" : null;
```

Условие пропуска снимка без содержимого (`PromptGenerator.cs:26`) и строка заголовка считают `capture.Title` пустым только тогда, когда пуст и `KindTitle(capture.Kind)`. Итог: «Снимок C — весь экран.» и «Снимок D — IMG_0512.png.».

**Приложение, `EditorModels.cs`, класс `CaptureItem`.** Свойства `Kind`, `MonitorCount`, `Title` с `OnPropertyChanged` (на них смотрят чип карточки и подпись редактора). Все три обязаны попасть в `DeepClone()` (`:223-230`), `Snapshot()`/`Restore()` (`:221`, `:254-262`) и в `record CaptureSnapshot` (`:268`), в `ToCore()`/`FromCore()` (`:232-252`) и в ручной перенос при обрезке (`Resize.cs:176-178`, там уже переносятся `DisplayLabel` и `IsSelected`).

**Core, старая рамка.** В `AnnotationItem.cs:74` поле `HasOutline` заменяется на

```csharp
[JsonPropertyName("hasOutline")]
[JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
public bool? LegacyHasOutline { get; init; }
```

`JsonPropertyName` обязателен: camelCase-политика сама дала бы `legacyHasOutline`. Правило чтения в `EditorModels.FromCore` (`:143-152`) дословно по `D §2.4`: `kind == Rectangle && LegacyHasOutline == false` читается как `Fill = Solid`, `FillColor = FillColor ?? StrokeColor`; старая `Redaction` читается как чёрная сплошная, как и раньше; во всех прочих случаях поле игнорируется.

**Правило контура.** В `Controls/AnnotationCanvas.cs`, рядом с `ShapeFillBrush` и `HasOpaqueFill`:

```csharp
internal static Color? OutlineColorOf(AnnotationFill fill, Color color, Color? fillColor) => fill switch
{
    AnnotationFill.Blur => null,
    AnnotationFill.Solid or AnnotationFill.Translucent => fillColor ?? color,
    _ => color
};
```

Две точки применения: `AnnotationCanvas.cs:743-744` и `WpfExportImageRenderer.cs:124-126`. Таблица «заливка → контур → внутри» в `D §2.7`; альфа полупрозрачной сводится к `0x40` в трёх местах (`AnnotationCanvas.cs:734` остаётся, `Appearance.cs:371` и `OverlayEditorWindow.xaml:413` приводятся).

**`Controls/StripResizeGeometry.cs`.** Константы (имена `EdgeGap` и `EstimatedChromeHeight` существуют, меняются значения; остальные новые):

```csharp
internal const double ShadowMargin = 20;                                   // Shell Margin, Capsule Margin, поля ручек
internal const double MinimumPanelWidth = 204;                             // видимая панель
internal const double MinimumWidth = MinimumPanelWidth + 2 * ShadowMargin; // 244, было 200
internal const double DefaultWidth = MinimumWidth;                         // 244, было 208
internal const double EdgeGap = 0;                                         // было 10
internal const double EstimatedChromeHeight = 160;                         // было 140
```

`ClampWidth`, `WidthFromStart`, `ClampListHeight`, `ListHeightFromStart` и `ToDeviceIndependent` сигнатур не меняют. Вспомогательная функция для тестов и для дорожки D (поля под тень поповеров): `internal static double CardWidth(double windowWidth)` = `windowWidth - 2*ShadowMargin - 2*ShellPadding - 2*ListPadding`, при 244 даёт 168.

**Токены палитр.** Два новых ключа во **всех шести** словарях `Themes/Palettes/*.xaml` (иначе `DynamicResource` разрешится под одной темой и не разрешится под другой, это ловит существующая проверка совпадения наборов ключей `SmokeTestRunner.cs:184-188`):

`ScrollThumbBrush`, `ScrollThumbHoverBrush`. Значения: пять тёмных тем `#47FFFFFF` и `#73FFFFFF` (белый 28 % и 45 %), `dawn` `#47000000` и `#73000000`.

**Темы.** `Themes/Palettes/Light.xaml` удаляется (файл, csproj не трогается: `Page` подхватываются SDK по умолчанию). `Glass.xaml` переписывается целиком по таблице `B §3.1`, `SurfaceBrush` это `LinearGradientBrush StartPoint="0,0" EndPoint="0.6,1"` с тремя стопами `#5F5C8C` / `#7E5878` / `#58627A`, `SurfaceBarBrush` тот же градиент при `EndPoint="1,0"`. `ThemeService.Themes` (`:19`) теряет `"light"`.

**Акценты.** Четыре новых словаря `Themes/Accents/{Rose,Cyan,RoseViolet,CyanBlue}.xaml`, по 8 ключей как у существующих, значения из `B §5.2`. Порядок `ThemeService.Accents` (`:22-23`):

```
["blue", "teal", "violet", "coral", "rose", "cyan",
 "blue-violet", "orange-rose", "green-cyan", "amber-pink", "rose-violet", "cyan-blue"]
```

Признак градиента вместо имени, в `ThemeService`:

```csharp
internal static bool IsGradientAccent(string? accentId) => LoadAccent(accentId)["AccentBrush"] is GradientBrush;
```

**Оконные помощники.** Новый `src/SnapBrief.App/DwmWindowCorners.cs` с двумя статическими классами (`A §A1`, `§A3`):

- `internal static bool DwmWindowCorners.Round(IntPtr hwnd)`: `DwmSetWindowAttribute(hwnd, 33, ref 2, 4) == 0`, в `try/catch (DllNotFoundException or EntryPointNotFoundException)` → `false`. Версию Windows числом не проверяем: на Windows 10 атрибут возвращает `E_INVALIDARG`, и это ровно то поведение, которое требует ТЗ.
- `internal static double MonitorMetrics.Scale(int x, int y)`: `MonitorFromPoint` плюс `GetDpiForMonitor(MDT_EFFECTIVE_DPI)`, при любом ненулевом HRESULT `1.0`. Приватный дубль `MonitorFromPoint` в `Controls/ScreenColorPicker.cs:109` остаётся как есть, пипетку не трогаем.

Чистая арифметика для теста, в `OnboardingWindow.xaml.cs` рядом с существующей `MinimumUsefulHeight` (`:111`, имя занято, переиспользуем):

```csharp
internal static double UsefulHeight(double workAreaDevice, double scale, double minimum)
```

**Шрифт иконок.** В `App.xaml`, в корне `ResourceDictionary` (не в `MergedDictionaries`):

```xml
<FontFamily x:Key="IconFont">Segoe Fluent Icons, Segoe MDL2 Assets</FontFamily>
```

WPF подставляет следующее семейство поглифно, это покрывает Windows 10. Единственное исключение `PortraitBlur` (`EABE`), которого нет ни в одном из двух семейств на Windows 10: для размытия глиф не берём, остаётся нынешний `Path` (`D §3.4`).

**Контракт между A и C по E2.** `HotkeySettingsWindow` получает `internal bool OnboardingRequested { get; private set; }` (ставит дорожка A обработчиком ссылки), читает его дорожка C в `EdgeStackWindow.OpenSettings()`. Свойство объявляется в волне 0 пустым (`= false`), чтобы обе ветки собирались независимо от порядка слияния.

**Строки.** Все новые пары RU/EN попадают в `UiLanguage.cs` в волне 0, полный список в §6. В волне 1 файл не трогает никто.

## 4. Задачи по волнам

Размер: S правка в одном файле, M файл целиком или два связанных, L новая подсистема или рискованная переделка. Оценок времени нет.

У каждой задачи обязателен шаг «граф»: `trace_call_path` inbound по каждому правящемуся методу, свойству и ресурсу до правки, `detect_changes` по ветке до коммита.

### Волна 0: фундамент (один executor, на `master`, последовательно)

Критический путь: пока волна 0 не в `master`, дорожки не стартуют. Всё, что нужно одной дорожке, из волны 0 вынесено; здесь только то, что либо служит контрактом двум и более дорожкам, либо физически неделимо.

| # | Решение | Размер | Файлы | Тесты и smoke | Что не должно сломаться | Критерий готовности | Коммит |
|---|---|---|---|---|---|---|---|
| W0-1 | Все новые пары RU/EN по §6, удаление пар, которые осиротеют в W0-6 и W0-9; языковая таблица smoke приведена к новому составу | S | `UiLanguage.cs`, `SmokeTestRunner.cs:336-354` | смоук-инвариант «две русские строки не делят один английский перевод» (`:1020-1022`) зелёный | существующие 300+ пар, обратный перевод поиском по значению | `grep -o '\["[^"]*"\]' UiLanguage.cs \| sort \| uniq -d` пуст, `scripts/build.ps1` зелёный | `windows: the strings of the 1.5.0 round` |
| W0-2 | Модель вида снимка: `CaptureKind`, `Kind`, `MonitorCount` в Core, смысл `Title`, `KindTitle` в `PromptGenerator`, проброс трёх значений через `EditorModels.CaptureItem` (`ToCore`, `FromCore`, `DeepClone`, `Snapshot`, `Restore`, `CaptureSnapshot`) и `Resize.cs:176-178` | M | `Core/Models/CaptureKind.cs` (новый), `Core/Models/CaptureItem.cs`, `Core/Exporting/PromptGenerator.cs`, `EditorModels.cs`, `OverlayEditorWindow.Resize.cs` | `tests/SnapBrief.Core.Tests`: старая сессия без `kind` читается как `Region`/`0`; `Fullscreen` round-trip как `"fullscreen"`; `PromptGenerator` на `Kind=Fullscreen` без заметок даёт «Снимок A — весь экран.», на `Region` с пустым `Title` даёт пустой результат | чтение старых `session.json`, `SchemaVersion` 1, поведение «снимок без заметок в текст не попадает» для `Region`, обрезка снимка не теряет подпись | три теста зелёные, `prompt.md` демо-сессии не изменился для обычных снимков | `windows: a capture knows what kind it is` |
| W0-3 | `HasOutline` → `LegacyHasOutline` в Core, правило чтения в `FromCore`, `OutlineColorOf` и его две точки применения, удаление поля во всех 27 местах (`D §2.3`), удаление четырёх полей настроек (`AnnotationOutline`, `AnnotationShape`, `AnnotationFill`, `AnnotationFillColor`) вместе с чтением и записью, сведение альфы полупрозрачной к `0x40` | L | `Core/Models/AnnotationItem.cs`, `EditorModels.cs`, `Controls/AnnotationCanvas.cs`, `WpfExportImageRenderer.cs`, `OverlayEditorWindow.xaml` (`:310-315`, `:413`), `.xaml.cs` (`:56, 85, 364, 1008`), `.Appearance.cs`, `HotkeySettingsWindow.xaml.cs:65-71`, `SmokeTestRunner.cs`, `tests/` | `D §7` пункты 1-3: чтение `hasOutline=false` у прямоугольника, свой `fillColor` сохраняется, `hasOutline=true` и отсутствие поля читаются как `Fill=None`, стрелка с `hasOutline=false` не трогается; записанный 1.5.0 `session.json` не содержит подстроки `hasOutline` (проверять по тексту файла); `VerifyLegacyRedactionReadsAsAFilledRegion` переписан | экспорт PNG (контур и заливка на своих местах у всех четырёх видов заливки), размытие без контура, порядок слоёв (непрозрачная заливка последней), чтение сессий 1.2.x с `redaction` | `scripts/build.ps1` зелёный, `grep -rn "HasOutline" src tests` даёт только `LegacyHasOutline` | `windows: the outline follows the fill instead of a flag` |
| W0-4 | Фикс `LoadBitmap` в обоих местах: копия кадра через `new WriteableBitmap(frame)` с `Freeze()`, декодер закрывается до возврата (C9) | S | `SessionWorkspace.cs:274-293`, `WpfExportImageRenderer.cs:51-58` | `tests/SnapBrief.App.Imaging.Tests`: кадр, прочитанный `LoadBitmap`, кодируется в `Task.Run` без `InvalidOperationException` (раньше кидало); копия сохраняет размеры и `IsFrozen` | импорт PNG и JPG, экспорт PNG из `FileExportService` (он и так идёт вне UI-потока), сообщение об ошибке формата | два теста зелёные, импорт PNG и JPG с диска добавляет карточку | `windows: an imported frame leaves its decoder behind` |
| W0-5 | Константы `StripResizeGeometry` по §3 плюс `CardWidth`, правка `SmokeTestRunner.cs:33` (`StackWidth = 240` меньше нового минимума, заменить на 260) | S | `Controls/StripResizeGeometry.cs`, `SmokeTestRunner.cs:33`, `tests/SnapBrief.App.Imaging.Tests/StripResizeGeometryTests.cs` | `C §3` пункты 1-3: `MinimumWidth - 2*ShadowMargin == MinimumPanelWidth`, `DefaultWidth == MinimumWidth`, `ClampWidth(208, 1920) == 244` и `ClampWidth(400, 1920) == 400`, `CardWidth(244) == 168` | существующие тесты `WidthFromStart`/`ListHeightFromStart` (они на числах 260/1920 и от констант не зависят, кроме `nameof`-ссылки на `MinimumWidth`), `VerifyStripIsBoundedByItsMonitor` | тесты зелёные, smoke не ловит кламп молча | `windows: the strip keeps its panel at 204` |
| W0-6 | Блок B, темы: удаление `Light.xaml`, переписанный `Glass.xaml`, два токена ползунка во все шесть палитр, `ThemeService.Themes` без `light`, `ThemeNames`/`Backdrop` в `AppearancePicker.xaml.cs` (`:31`, `:215`), комментарии «семь палитр» в шести файлах и в `SmokeTestRunner.cs:841` | M | `Themes/Palettes/*.xaml`, `ThemeService.cs:19`, `Controls/AppearancePicker.xaml.cs:29-33, 213-222`, `SmokeTestRunner.cs` | smoke `B §8` п. 1 и 4: `Themes.Count == 6`, `Themes` без `"light"`, `NormalizeTheme("light") == "dark"`; `Apply("glass", …)` даёт `SurfaceBrush` с тремя стопами и `SurfaceBarBrush` с `EndPoint=(1,0)` | совпадение наборов ключей всех палитр (`:184-194`), фолбэк неизвестной темы (`:206-208`), хром ленты по всем палитрам (`:846-862`), проверка `sea` (`:200-205`), градиент в капсуле и поповерах | пять оставшихся тем выглядят как в 1.4.0, «Стекло» это градиент B | `windows: six themes and the glass gradient` |
| W0-7 | Блок B, акценты: четыре новых словаря, порядок из §3, `IsGradientAccent`, `AccentNames` в `AppearancePicker.xaml.cs:38-43`, комментарий `ThemeService.cs:20-21` | M | `Themes/Accents/{Rose,Cyan,RoseViolet,CyanBlue}.xaml` (новые), `ThemeService.cs:22-23`, `Controls/AppearancePicker.xaml.cs:38-43`, `SmokeTestRunner.cs` | smoke `B §8` п. 2, 3, 5: `Accents.Count == 12` и порядок один в один; первые шесть `IsGradientAccent == false`, последние шесть `true`; у каждого градиентного `AccentFlatColor` равен первому стопу (существующая проверка `:179-183` расширяется с одного акцента на шесть) | совпадение наборов ключей акцентов, заморозка акцента по всем акцентам (`:215-221`), `AccentPalette.Flat` и экспорт PNG, `AppearancePicker.RunProbe` (считает по `Accents.Count`) | двенадцать кружков, градиентная кнопка «Готово» на каждом из шести градиентов | `windows: twelve accents, six of them gradients` |
| W0-8 | Блок B, миграция: правило темы в `SettingsMigration`, `CurrentVersion` 1 → 2, **порог у каждого правила по своей версии** (`SoundVolume` → `storedVersion < 1`, `Theme` → `storedVersion < 2`), подключение в `HotkeySettings.Migrate` | S | `SettingsMigration.cs`, `HotkeySettingsWindow.xaml.cs:114-121, 187-196`, `tests/SnapBrief.App.Imaging.Tests/SettingsMigrationTests.cs` | `light` при версии 0 и 1 → `dark`; `sea` не трогается; `light` при версии 2 не трогается; **громкость 60 при версии 1 остаётся 60** (регресс порога) | звук у тех, кто менял громкость; чтение файла без `SettingsVersion`; запись файла назад один раз | четыре теста зелёные, файл с `"Theme":"light"` после запуска несёт `"dark"` и `SettingsVersion: 2` | `windows: the light theme migrates into the dark one` |
| W0-9 | Переименование клавиши «Снимок всего экрана» во всех четырёх местах (`B §6.1`) | S | `HotkeySettingsWindow.xaml:43, 44`, `UiLanguage.cs:47` (пара заменяется, не добавляется), `SmokeTestRunner.cs:339` | языковая таблица smoke проверяет новую пару, не старую | `FullscreenSaveId` и id клавиши `fullscreen-save` (формат настроек, не трогаются), галочка `FullscreenEnabledBox` и чип «Предложить», выключенное по умолчанию состояние | `grep -rn "Скриншот всего экрана" src` пуст | `windows: the whole-screen key gets its new name` |
| W0-10 | `DwmWindowCorners.cs` (`Round` плюс `MonitorMetrics.Scale`), `UsefulHeight` рядом с `MinimumUsefulHeight`, ресурс `IconFont` в `App.xaml`, объявление `OnboardingRequested` в `HotkeySettingsWindow` | S | `DwmWindowCorners.cs` (новый), `OnboardingWindow.xaml.cs`, `App.xaml`, `HotkeySettingsWindow.xaml.cs` | smoke: три случая `UsefulHeight` (100 %, 125 %, крошечный монитор упирается в минимум) | старт приложения, `RunOnboardingProbe` на окне без handle, разрешение ресурсов темы и акцента в `App.xaml` | сборка зелёная, `IconFont` резолвится из редактора и из ленты | `windows: the window helpers and the icon font` |
| W0-11 | Заметки волны: `tasks/tz-005-notes-0.md`, включая абзацы «Изменение формата» по §7 (пункты 1-4) | S | `tasks/tz-005-notes-0.md` (новый) | нет | нет | четыре абзаца «Изменение формата» написаны дословно, их переносит волна 2 | `windows: the notes of wave 0 for TZ-004` |

### Волна 1: три executor'а параллельно, каждый в своём worktree и своей ветке от коммита волны 0

Деление по файловым зонам. Между дорожками синхронизации нет, чужие ветки не мержатся, `git checkout`, `git restore`, `git reset` по чужим файлам не делаются. `UiLanguage.cs` не трогает никто: все строки в волне 0. Если дорожка обнаружит пропущенную строку, она дописывает пару **в конец таблицы** и называет её в своих заметках (правило слияния в §5).

#### Дорожка A: мастер и настройки

Зона: `OnboardingWindow.xaml(.cs)`, `Controls/AppearancePicker.xaml(.cs)`, `Controls/HowToSlides.xaml(.cs)`, `HotkeySettingsWindow.xaml(.cs)`.

Порядок коммитов: A1, A2, A3, A4, A5-UI, A6, E2.

| # | Пункты ТЗ | Решение | Размер | Файлы | Тесты и smoke | Что не должно сломаться | Критерий готовности | Коммит |
|---|---|---|---|---|---|---|---|---|
| A-1 | A1 | Скругление отдаётся DWM (`DwmWindowCorners.Round` из `OnSourceInitialized`, результат в `Trace`), внутренний `Border` теряет обводку и скругление (`BorderThickness="0" CornerRadius="0"`), комментарий `:5-7` переписывается. Окно настроек не трогается (`A §1.1`). Фолбэк, если `ResizeMode="CanMinimize"` оставит окно без `WS_THICKFRAME` и DWM промолчит: вернуть скругление внутреннему `Border` и отказаться от DWM, записать в заметки | S | `OnboardingWindow.xaml:104`, `.xaml.cs:93` | нового теста нет (P/Invoke в headless не проверяется), проверка живая, F1 | `RunOnboardingProbe` на окне без handle, фон окна `SurfaceBrush` под всеми шестью темами | на Windows 11 один контур, `startup.log` несёт строку `Onboarding corners: rounded=` | `windows: the wizard lets DWM round its corners` |
| A-2 | A2 | `WindowChrome CaptionHeight="48" UseAeroCaptionButtons="False"`, обеим кнопкам `IsHitTestVisibleInChrome="True"`, `OnHeaderDrag` удаляется (`A §A2`). Обещание про снап из ТЗ снимается (`A §1.2`) | S | `OnboardingWindow.xaml:9, 109, 112, 115`, `.xaml.cs:420` | `ResolveTriggerBindings` и `RunOnboardingProbe` на `WindowChrome` не смотрят, новой логики нет | кнопки «—» и «×» нажимаются, содержимое шагов (начинается с y=62) в пояс не попадает | окно тянется за верхний пояс целиком, включая поля и углы | `windows: the whole top belt of the wizard drags it` |
| A-3 | A3 | Пересчёт `MaxHeight` и центра в DPI монитора показа по формуле `A §A3`: `MonitorMetrics.Scale` у монитора под курсором, позиция через `SetWindowPos` в физических пикселях, однократный `OnDpiChanged` с флагом `_placed`, `Trace` с монитором, масштабом, `MaxHeight` и высотой | M | `OnboardingWindow.xaml.cs:93-108` | smoke: три случая `UsefulHeight` (объявлена в W0-10) | `WindowStartupLocation="Manual"`, открытие на одном мониторе, кламп на 1366×768 | на смешанном DPI окно открывается на мониторе под курсором целиком, `startup.log` несёт строку `Onboarding placement:` | `windows: the wizard measures the monitor it opens on` |
| A-4 | A4 | Шесть карточек (список ведёт волна 0), `BringSelectedCardIntoView` снимается целиком (`:236-244`, `:292-298`), галерея всегда открывается на первой карточке, рамка на выбранной. Колесо: `PreviewMouseWheel` → `PageBy(±1)` с `e.Handled = true` (иначе колесо уходит в `ScrollViewer` мастера). Тачпад: `WM_MOUSEHWHEEL` через `HwndSource.AddHook`, гейт по `Gallery.IsMouseOver`, хук снимается в `Unloaded` (`A §A4`) | M | `Controls/AppearancePicker.xaml:82-87`, `.xaml.cs:236-298` | `RunProbe`: текст исключения про «семь карточек» переписан на шесть; `PageByWheel(int)` двигает `_firstCard` на 1 и упирается в `LastPage`; установка `SelectedTheme` на последнюю тему при `_firstCard == 0` галерею не двигает | шевроны `PageBy`/`MarkChevrons`, гашение на концах (opacity 0.42), выбор карточки мышью, вкладка «Вид» в настройках (контрол один, поведение теперь одинаковое в обоих местах) | колесо и горизонтальный жест листают галерею и не прокручивают окно мастера, последняя карточка видна целиком | `windows: the theme gallery listens to the wheel` |
| A-5 | A5 | Ряд из 12 кружков: `AccentNames` дополнен волной 0, разделитель ставится **по признаку** `IsGradientAccent` с флагом «уже поставлен», `Divider().Margin` `4,0,14,0` → `4,0,4,0` (ряд 455 px в 520) | S | `Controls/AppearancePicker.xaml.cs:183-206` | `RunProbe`: разделитель ровно один и стоит непосредственно перед первым кружком, чей акцент градиентный (ловит будущую перестановку ряда и словарь с неожиданной кистью) | счётчик кружков по `Accents.Count` (`:339`), стиль `AccentDot` (28 px, шаг 10), активный кружок с белой обводкой | 12 кружков, разделитель после шестого, ряд помещается в шаг | `windows: the accent row splits by gradient, not by name` |
| A-6 | A6 | `Grid` на `HowToSlides.xaml:915` получает `Height="140"` с комментарием-расчётом, четырём внутренним `StackPanel` добавляется `VerticalAlignment="Top"`. `ScrollViewer` мастера не трогается: скроллбар уходит потому, что содержимое перестало вылезать (`A §A6`) | S | `Controls/HowToSlides.xaml:915-1005` | `RunSlidesProbe`: цикл по слайдам прогоняется дважды, для `ru` и для `en`, и требует `_captions[index].DesiredSize.Height <= 140` после `UpdateLayout()` с именем языка и номером слайда в исключении | тексты подписей, анимации (`Opacity` и `TranslateTransform`, на раскладку не влияют), ряд точек, стрелки Left/Right | точки стоят на одном месте на всех четырёх слайдах, скроллбара нет ни на одном | `windows: the slide captions keep one height` |
| A-7 | E2 | Ссылка «Пройти знакомство заново» внизу вкладки «Общие» (стиль повторяет `StepSkipLink`), обработчик ставит `OnboardingRequested = true` и `DialogResult = false` (несохранённые правки диалога отбрасываются, `Closed` возвращает тему открытия). Плюс правка мастера: `_openedLanguage` рядом с `_openedTheme`/`_openedAccent`, и `SkipSetup` возвращает язык, с которым мастер открылся (`A §E2`). Сторону ленты (`WriteOnboarding`, `OpenSettings`) делает дорожка C | M | `HotkeySettingsWindow.xaml` (после `:38`), `.xaml.cs`, `OnboardingWindow.xaml.cs:30-31, 59, 401-414` | smoke: `OnRunOnboarding` ставит `OnboardingRequested = true`, `DialogResult` в `false`, `Result` остаётся `null`; пара строк «Пройти знакомство заново» в языковой таблице (добавлена в W0-1) | сохранение настроек по «Сохранить», возврат темы по «Отмена» (`:369`), поведение мастера при первом запуске, пункт трея «Как пользоваться» | ссылка открывает полный мастер с текущими значениями; «Пропустить» не меняет язык | `windows: the settings can run the tour again` |

#### Дорожка C: лента

Зона: `EdgeStackWindow.xaml`, `EdgeStackWindow.xaml.cs`, `EdgeStackWindow.Saving.cs`, `SessionWorkspace.cs`.

Порядок коммитов: C7, C2, C1, C6, C4, C3, C5, C8, A7 и E2-сторона ленты.

| # | Пункты ТЗ | Решение | Размер | Файлы | Тесты и smoke | Что не должно сломаться | Критерий готовности | Коммит |
|---|---|---|---|---|---|---|---|---|
| C-1 | C7 | Удалить `SetWindowDisplayAffinity(handle, 0x11)` (`:244`) и `DllImport` (`:1842-1843`). Временный флаг на время `HideForCapture` не ставить: окно в этот момент скрыто, а лишний вызов на слоёное окно даёт лишнюю перерисовку (`C §C7`) | S | `EdgeStackWindow.xaml.cs:244, 1842-1843` | нет (проверка живая, F8) | `HideForCapture` (`:612-618`) прячет все окна, ждёт кадр и `DwmFlush()`: ленты в нашем снимке нет физически | Win+Shift+S и Print Screen видят ленту, наш снимок её не содержит | `windows: the strip hides only from our own captures` |
| C-2 | C2 | Триггер `IsMouseOver` шаблона `ScrollViewer` со сторибордами ширины (`:200-205`) убирается целиком, ширина 4 всегда. Кисти `Grip`: `ScrollThumbBrush`, при наведении `ScrollThumbHoverBrush` (токены из волны 0), при перетаскивании `FocusBrush` | S | `EdgeStackWindow.xaml:194-205, 116-119` | нет | реакция на наведение на саму полосу (`StackScrollBar :117-119`), `CornerRadius="2"`, положение полосы в правом поле | полоса 4 px не меняется при наведении на список, видна на всех шести темах | `windows: the strip scrollbar stops breathing` |
| C-3 | C1 | Три механизма сразу (`C §C1`): все три `Items.Refresh()` убираются, модель уведомляет сама (`DisplayLabel` становится свойством с `OnPropertyChanged`, сеттер `Note` шлёт `NoteCount`, конструктор подписывается на `Annotations.CollectionChanged`); `ListBox` теряет `AlternationCount`, `VirtualizationMode` и `ScrollUnit`, получает `VirtualizingPanel.IsVirtualizing="False"` и `CanContentScroll="False"`, `ItemsPanel` становится обычным `StackPanel`; из `ItemContainerStyle` уходят сеттер `Panel.ZIndex`, оба триггера и `StripDepthConverter` (`:1851`, ресурс `:11`); полоса подписи переезжает наверх (`VerticalAlignment="Top"`); тень карточки `BlurRadius 16 / ShadowDepth 6 / Opacity 0.35 / Direction 90`; анимации наведения заменяются обычными сеттерами `Margin` во всех трёх триггерах (снимает конфликт приоритетов) | L | `EdgeStackWindow.xaml:11, 168-231, 236-296`, `.xaml.cs:1353, 1687, 1704, 1714, 1851`, `EditorModels.cs` (только `CaptureItem.DisplayLabel`/`Note`/`NoteCount`) | нового юнит-теста нет (UI); smoke: существующие пробы ленты зелёные | прокрутка (положение сохраняется при возврате из редактора), перетаскивание карточек (`OnCaptureListMouseDown`/`MouseMove` берут `e.GetPosition(CaptureList)`), выделение и клавиатурный фокус карточки, удаление и «вернуть удалённый», буквы A..Z, счётчик заметок на карточке | C поверх B поверх A, полоса с буквой сверху каждой, после возврата из редактора порядок, тени и прокрутка те же | `windows: the newest capture lies on top` |
| C-4 | C6 | Поля под тень: `Shell Margin` 10 → 20, `Capsule Margin` 10 → 20, `WidthGrip` и `CornerGrip` на видимый край панели, `CaptureList Padding` `0,0,0,52` → `8,14,8,52`, правое поле карточки 8 убирается в пользу паддинга списка (`Margin="0,0,0,-48"`, при наведении `0,4,0,4`). Константы уже в волне 0, `PositionAtEdge`, `ExpandFromCapsule` и `PositionCapsuleAtEdge` формулу не меняют (`C §C6`) | M | `EdgeStackWindow.xaml:134, 168, 235, 283-296, 337, 356, 367` | тесты геометрии в волне 0; smoke `VerifyStripIsBoundedByItsMonitor` | видимый зазор до края экрана (20 px, как сейчас), позиционирование капсулы, растягивание за угол и за левую ручку, `MinHeight="128"` | тень не срезана ни у окна, ни у первой карточки, карточка 168 при панели 204 | `windows: the shadows get their 20 px` |
| C-5 | C4 | Кнопки шапки 22 px (стиль `IconButton`), четыре колонки шапки по 22, `TextTrimming="CharacterEllipsis"` на «SnapBrief», `Padding` счётчика `6,2` → `5,2` (`C §C4`) | S | `EdgeStackWindow.xaml:32, 141, 144, 145` | нет | иконки 12×13, 14×3, 10×10 внутри 22 px, `CornerRadius="8"`, попадание мыши по кнопкам | «● SnapBrief 26» помещается в 96 px, четыре кнопки без зазоров | `windows: the strip header fits its four buttons` |
| C-6 | C3 | Блок `EmptyHint` (92 px, 12/17, `TextMutedBrush`) в той же `Grid.Row="1"`, метод `UpdateEmptyState()` из `Renumber()`: список и ручка угла прячутся, подсказка показывается, текст выбирается по `CaptureEnabled` (две строки, вторая для выключенной клавиши). `PositionAtEdge` продолжает писать `CaptureList.Height`, первый снимок разворачивает ленту на сохранённую высоту (`C §C3`) | M | `EdgeStackWindow.xaml` (новый блок), `.xaml.cs:1349` | нет | ручка ширины у пустой ленты (ширина осмысленна, ТЗ запрещает только угол), рост ленты с первым снимком, `StackHeight` | высота пустого окна 231, панель 191, подсказка в две строки по центру | `windows: an empty strip is a small strip` |
| C-7 | C5 | `DragMove` по нажатию на любое свободное место `Shell`: обработчик переезжает с шапки на `Shell`, шапка получает `Background="Transparent"`, `OnHeaderMouseDown` переименовывается в `OnShellMouseDown` и защищается проверкой `e.LeftButton` и `e.ClickCount > 1` (`C §C5`) | S | `EdgeStackWindow.xaml:134, 138`, `.xaml.cs:1672` | нет | кнопки, карточки, `WidthGrip`, `CornerGrip` и скроллбар забирают нажатие себе; `PreviewMouseLeftButtonDown="OnCaptureListMouseDown"` не помечает событие и не мешает; курсор остаётся стрелкой | лента тянется за пустое место шапки, за паддинги и за промежутки между карточками | `windows: the strip drags by any free spot` |
| C-8 | C8 (лента) | `SaveFullscreenAsync` переписывается в `CaptureFullscreenAsync` по хвосту обычного захвата (`C §C8`): `AddImageAsync` → `Kind = Fullscreen`, `MonitorCount = Screen.AllScreens.Length` → `Captures.Add` → `Renumber`/`NoteStripGrowth`/`InvalidatePrepared` → звук → `SaveAndCopyCommittedPackageAsync` → `AutoSaveCaptureAsync`. Прямая запись в папку уходит. Чип «экран» справа в полосе подписи по `DataTrigger Binding="{Binding Kind}" Value="Fullscreen"`, глиф `TVMonitor` `E7F4` из `IconFont`; тем же триггером миниатюра переходит на `Stretch="Uniform"`. Импорт заполняет `Title` именем файла и `Kind = Import`, его чип глиф `Page` `E7C3`. Заодно иконки ленты по таблице `D §3.3` переводятся на `IconFont` (корзина `E74D`, три точки `E712`, свернуть `E921`, закрыть `E8BB`, комментарий `E90A`, камера `E722`); стрелка вверх (`:316`) не трогается, имя глифа не подтверждено | L | `EdgeStackWindow.Saving.cs:39-57`, `EdgeStackWindow.xaml:150-161, 247-260, 301, 344`, `.xaml.cs:284, 1060` | smoke: снимок с `Kind = Fullscreen`, `MonitorCount = 2` проходит `PrepareAsync` и даёт в `prompt.md` «Снимок A — весь экран.»; `SessionWorkspace.LoadBitmap` плюс `AddImageAsync` на настоящем файле с диска | id клавиши `fullscreen-save` и поле `FullscreenSaveId` (формат), автосохранение, Ctrl+V пакет, `StripIsFull`, всплывашка трея | снимок всего экрана ложится в ленту карточкой с чипом и уходит в Ctrl+V; импорт даёт свой чип и подпись | `windows: the whole screen lands in the strip` |
| C-9 | A7, E2 | Лента после мастера: в `OnLoaded` запомнить факт показа и после `PositionAtEdge()` (`:223`) позвать `ShowStackWithoutActivation()` (не сразу после `ShowDialog`, иначе мелькнёт пустая лента до восстановления сессии). Плюс сторона ленты для E2: `WriteOnboarding` в ветке `merge` начинает писать `Theme` и `AccentId`, `OpenSettings()` после `ShowDialog` смотрит `dialog.OnboardingRequested` и зовёт `ShowOnboarding()` внутри `try` (`A §E2`, `C §A7`) | S | `EdgeStackWindow.xaml.cs:194-228, 1246-1254, 1336` | smoke: запись `HotkeySettings` с темой `sea` и чтение назад сохраняют `Theme` и `AccentId` | ветка `howToOnly` из трея (лента там уже видна), демо и smoke (`ShouldShowOnboarding` там `false`), однократная перерегистрация клавиш в `finally` | после «Начать» и после «Пропустить» появляется пустая компактная лента; тема, выбранная в мастере, доживает до следующего запуска | `windows: the strip shows itself after the tour` |

#### Дорожка D: редактор

Зона: `OverlayEditorWindow.xaml(.cs)`, `.Appearance.cs`, `.Toolbar.cs`, `.Resize.cs`, `Controls/AnnotationCanvas.cs`, `Controls/ScreenColorPicker.cs`, `WpfExportImageRenderer.cs`.

Порядок коммитов: D1, D3, D2-иконка, D2-лупа, C8-редактор.

| # | Пункты ТЗ | Решение | Размер | Файлы | Тесты и smoke | Что не должно сломаться | Критерий готовности | Коммит |
|---|---|---|---|---|---|---|---|---|
| D-1 | D1 | Один активный цвет (`D §2.1`): понятие `HasColor` уходит, цвет принимается при любом инструменте, `AppearanceButton.IsEnabled` и `ColorDots.IsEnabled` всегда `true`, `PanelPaintsFill` удаляется, `ApplyQuickColor` сводится к обычному присвоению, `mainColor` становится просто цветом. Заливка остаётся свойством фигуры со своим цветом (`D §2.2`); `_activeShape`, `_activeFill`, `_activeFillColor` больше не читаются из настроек (поля удалены в волне 0), каждый снимок начинается с «контур, без заливки, прямоугольник». Спектр и пипетка видны в каждой палитре, автозапоминание цвета снимается, вместо него кнопка «+» 34×34 третьей колонкой рядом с HEX, `RememberCustomColor` перестаёт выходить при чужой активной палитре (`D §2.6`) | L | `OverlayEditorWindow.Appearance.cs:37, 120-128, 256-262, 318-341, 363, 378-429, 471-506, 549-558, 660-684`, `.xaml:296-309, 400-424`, `.xaml.cs:45, 55, 82-85` | `PanelChecks`: блок `:361-371` заменён на четыре проверки (цвет, выбранный при инструменте «Комментарий», доезжает до `Surface.ActiveColor` и достаётся следующей рамке; кружок панели показывает активный цвет, а не заливку; спектр и пипетка видны при каждой из трёх палитр; «+» кладёт активный цвет в ряд «Своей»); `RunCustomPaletteProbe` переписан | запоминание между снимками цвета, толщины, палитры и карандаша/маркера; ряд из 12 слотов «Своей» и его переживание перезапуска; HEX в обе стороны; выделенная фигура меняет цвет контура, не теряя цвет заливки | выбрать цвет при «Комментарии», потом рамку: рамка того цвета; три рамки (без заливки, сплошная, размытие) выглядят как в таблице `D §2.7` | `windows: one active colour for every tool` |
| D-2 | D3 | Порядок нажатия при активном «Комментарии» (`D §4.1`): из `FindLeaderAnchor` уходит `Tool == Select`, из `FindMoveHandle` уходит `Tool == Comment`, вместо этого `IsMoveHandle` при `Tool == Comment` отвечает только за отметки `Kind == Comment` (иначе булавку нельзя поставить поверх нарисованной рамки), из ворот `:225` уходит `Tool != EditorTool.Comment`. Курсор: с `movablePin` снимается `Tool == Select`. Плюс вариант Б для остальных инструментов (`D §4.3`, решение 5): при `item.Kind == Tool` полоса захвата расширяется с 6 до 10 px, нутро пустой рамки остаётся свободным | M | `Controls/AnnotationCanvas.cs:213-228, 341-362, 771-788, 790-827` | `VerifyGestureRules` дополняется сценарием D3: при инструменте «Комментарий» нажатие точно по бейджу не создаёт второй отметки, выделяет первую, и `Tool` остаётся `Comment`; то же для якоря (у отметки должен быть `Label`). `VerifyHoverManipulation`: при `Tool == Comment` `FindMoveHandle` над кромкой рамки даёт `null`, над бейджем даёт комментарий | ластик, двойной клик (открывает заметку), углы изменения размера, рисование рамки внутри рамки, захват стрелки за линию и пера за штрих, пилюля (её нажатие перехватывает `ChipLayer` и до холста не доходит) | два комментария подряд, первый двигается за бейдж и за якорь без переключения инструмента | `windows: the comment tool grabs what is already there` |
| D-3 | D2 | Иконка пипетки: глиф `Eyedropper` `EF3C` из `IconFont` вместо косого карандаша. Аудит иконок редактора по таблице `D §3.3`: карандаш `ED63`, маркер `ED64`, текст `E8D2`, ластик `E75C`, обрезка `E7A8`, комментарий `E90A`, undo `E7A7`, redo `E7A6`, сохранить `E74E`, крестики `E8BB`. Три позиции остаются своими рисунками (указатель, прямоугольник, диагональная стрелка): системного глифа нет вовсе, решение записывается в заметки. Размытие тоже остаётся `Path`: `PortraitBlur` `EABE` есть только в Segoe Fluent Icons, на Windows 10 дал бы пустой квадрат | M | `OverlayEditorWindow.xaml:15-16, 168, 213-226, 257, 273-308`, `.xaml.cs:1355` | нет (визуальная правка), сверка с эталонами глазами | размеры кнопок панели и её укладка на 125 %, `PanelChecks` на ширину панели | ни одной придуманной иконки там, где есть системный глиф | `windows: the editor icons come from the system font` |
| D-4 | D2 | Лупа пипетки (`D §3.2`): капсула у курсора, `Image` 128×128 из `CroppedBitmap` 16×16 при `NearestNeighbor` (увеличение 8×), сетка через 8 DIU, центральный пиксель с двойной обводкой, HEX под лупой, зеркалирование у края рабочей области. Источник лупы это один раз замороженный `BitmapSource`, а не `System.Drawing.Bitmap` (256 `GetPixel` на каждое движение мыши дороговато). Координаты из двух источников намеренно: положение из события WPF, вырезка из `GetCursorPos` | M | `Controls/ScreenColorPicker.cs` | нет; в приёмку записать поведение на мониторе 125 % (лупа физически крупнее, это правильно) | Esc отменяет (`:44`), клик берёт цвет (`:43`), живой предпросмотр отметки под курсором (`:42`), работа на втором мониторе (оверлей накрывает виртуальный экран) | лупа читается на белом и на чёрном, HEX совпадает с взятым цветом | `windows: the eyedropper shows what it is about to take` |
| D-5 | C8 (редактор) | `ViewScale` (`double?`, `null` это «вписать») и `ViewOffset` (`Vector`) на `AnnotationCanvas`, `_imageRect` в режиме масштаба считается от них с зажимом смещения (`D §5.4`). Подпись вида снимка в правом верхнем углу `_cropRect` из `Kind`, `MonitorCount` и `Image.PixelWidth/PixelHeight`. Переключатель «По ширине · 35 %» ↔ «1:1» справа от панели, показывается только при `fitScale < 1`; `PlaceToolbar` получает сумму ширин, иначе у правого края экрана переключатель уедет за границу (`D §0.12`). Жесты: колесо (вертикаль), Shift+колесо (горизонталь), Ctrl+колесо (масштаб ×1.1 за щелчок, зажат снизу `fitScale`, сверху 1.0, точка под курсором остаётся на месте), пробел плюс мышь (панорама тем же `ViewOffset`; решение 8: режется первой, если не укладывается). В 1:1 холст получает `NearestNeighbor`, иначе шов между мониторами размажется. Пилюли, чей бейдж вне `_cropRect`, прячутся; ручки границ снимка прячутся, пока `ViewScale is not null` | L | `Controls/AnnotationCanvas.cs:153, 935-942` и жесты, `OverlayEditorWindow.xaml`, `.xaml.cs:871-889, 1482, 1540, 1549-1561, 1762`, `.Toolbar.cs:9-31`, `.Resize.cs:103-124` | новые юнит-тесты на чистые функции (`D §7` п. 4-5): `EditorGeometry.Fit(imageW, imageH, boxW, boxH)` даёт `(scale, boundBy)` на трёх случаях; `EditorGeometry.ClampOffset` не выпускает край картинки внутрь окна просмотра, центрирует короткую ось и оставляет точку под курсором на месте после Ctrl+колеса (допуск 0.5 px). Smoke: на снимке 3840×1125 переключатель виден и подписан «По ширине», после `ViewScale = 1` пилюля отметки у правого края спрятана | координаты отметок (все одиннадцать мест холста считают от `_imageRect`), `RenderAnnotated()` и экспорт (от экранного масштаба не зависят), затемнение вокруг снимка, обрезка, место панели комментариев, обычный снимок области (переключателя не видно) | широкая картинка вписывается по ширине, вертикальная по высоте, 1:1 прокручивается, шов на месте и без артефактов | `windows: the editor scales what does not fit` |

### Волна 2: сведение (один executor, на `master`, после слияния A, C и D по одному)

| # | Решение | Размер | Файлы | Критерий готовности |
|---|---|---|---|---|
| W2-1 | Сводный раздел в `tasks/verification.md`: слияние `tz-005-notes-0/A/C/D.md`, все абзацы «Изменение формата» из §7 в одном месте, строка «живьём не проверено» там, где проверка была только глазами | S | `tasks/verification.md` | ни один абзац «Изменение формата» из §7 не потерян |
| W2-2 | Сводные заметки раунда `tasks/tz-005-notes.md` и обновление индекса графа связей: `cli index_repository '{"repo_path": "<корень репо>"}'` | S | `tasks/tz-005-notes.md`, индекс графа | `search_graph` находит `CaptureKind`, `OutlineColorOf`, `IsGradientAccent` |
| W2-3 | Версия 1.4.0 → 1.5.0 и сборка установщика | S | `src/SnapBrief.App/SnapBrief.App.csproj`, `installer/` | `artifacts/installer/SnapBrief-Setup-1.5.0.exe` собран |
| W2-4 | Одно код-ревью по всему диапазону `5e4f8e5..HEAD` отдельным субагентом со свежим контекстом против ТЗ и этого плана, с проверкой inbound-callers через граф (`trace_call_path` по каждому изменённому публичному методу), затем один фикс-коммит с обязательными находками | M | по результату | `scripts/build.ps1` зелёный после фикс-коммита |

Волна 2 идёт параллельно с ревью: W2-1..W2-3 не ждут его, фикс-коммит ложится сверху.

## 5. Общие файлы и правила слияния

Порядок слияния: **A → C → D**, по одному, после каждого `scripts/build.ps1 -OutputDirectory $env:LOCALAPPDATA\Temp\snapbrief-candidate-tz005` зелёный. Обоснование порядка: C читает `HotkeySettingsWindow.OnboardingRequested`, которое ставит A (само свойство объявлено в волне 0, поэтому ветки собираются в любом порядке, но осмысленный результат даёт только A перед C); C несёт самую крупную структурную переделку, и чем раньше она в `master`, тем больше прогонов проходит поверх неё; D замкнута в файлах редактора и ложится последней без риска для ленты.

| Файл | Кто пишет | Правило |
|---|---|---|
| `UiLanguage.cs` | только волна 0 | В волне 1 файл закрыт. Если дорожка обнаружит пропущенную пару, она дописывает её **в конец таблицы** (не рядом с родственными: конец даёт три соседние строки вместо трёх врезок в разные места) и называет пару в своих заметках. После каждого merge: `grep -o '\["[^"]*"\]' src/SnapBrief.App/UiLanguage.cs \| sort \| uniq -d` пуст, и смоук-инвариант уникальности английских значений (`SmokeTestRunner.cs:1020-1022`) зелёный |
| `SmokeTestRunner.cs` | все | Новые проверки только **отдельными методами в конце файла**, без врезок в чужие блоки. Зоны существующих методов: волна 0 правит `:33`, `:174`, `:179-221`, `:336-354`, `:841`, `VerifyLegacyRedactionReadsAsAFilledRegion`; A владеет `RunOnboardingProbe`, `VerifyWizardTranslations`, `VerifySlideKeysStayInsideTheWizard`, `VerifyHowToOnlyWizard`; C владеет `VerifyStripIsBoundedByItsMonitor`, `VerifyTheStripChromeFollowsTheTheme`; D владеет пробами редактора (`PanelChecks` живёт в `OverlayEditorWindow.xaml.cs`, это её собственный файл). Единственная общая точка это список вызовов в `Run`: три соседние строки, конфликт разводится глазами |
| `Controls/AppearancePicker.xaml(.cs)` | волна 0 и A | Волна 0 правит только данные: `ThemeNames`, `AccentNames`, `Backdrop`, комментарии. Дальше файл целиком у A, включая `RunProbe` |
| `HotkeySettingsWindow.xaml(.cs)` | волна 0 и A | Волна 0 правит название клавиши (`:43-44`), `Migrate` и объявляет `OnboardingRequested`. Дальше файл у A. Дорожка C в файл не заходит, она только читает свойство |
| `EdgeStackWindow.xaml(.cs)`, `.Saving.cs` | только C | Включая A7, сторону ленты для E2 и замену иконок ленты на `IconFont`. Дорожка A в файл не заходит |
| `EditorModels.cs` | волна 0, затем C | Волна 0 кладёт `Kind`/`MonitorCount`/`Title` и убирает `HasOutline`. В волне 1 сюда заходит только C (уведомления `DisplayLabel`/`NoteCount` в задаче C-3). D после волны 0 в файл не заходит |
| `WpfExportImageRenderer.cs` | волна 0, затем D | Волна 0 правит `LoadBitmap` и точку применения `OutlineColorOf`, дальше файл у D |
| `Themes/**` | только волна 0 | Дорожки палитры и акценты не трогают |
| `tests/` | все | Новые тесты только отдельными файлами или отдельными методами в конце существующего класса |
| `tasks/verification.md` | никто из дорожек | Каждая пишет в свой `tasks/tz-005-notes-<A\|C\|D>.md`. Волна 0 пишет `tz-005-notes-0.md`. Сводит волна 2 |

Что грепать после каждого слияния (в C# прямой дубль имени с той же сигнатурой ломает сборку, поэтому опасны именно те дубли, которые компилятор пропускает молча):

1. Дубли ключей `UiLanguage`: `grep -o '\["[^"]*"\]' src/SnapBrief.App/UiLanguage.cs | sort | uniq -d`.
2. Дубли английских значений: держит смоук, но после merge прогнать его первым же.
3. Дубли ключей ресурсов внутри одного словаря: `grep -rho 'x:Key="[^"]*"' src/SnapBrief.App/Themes/Palettes/*.xaml | sort | uniq -d` по каждому файлу отдельно; между словарём палитры и `SnapBriefTheme.xaml` дубль молча перекрывает тему, это ловит существующая проверка совпадения наборов ключей.
4. Двойные `Setter` на одно свойство в одном стиле (последний выигрывает молча) и двойные `BeginStoryboard` на один `Margin`: после слияния C прочитать `ItemContainerStyle` целиком глазами, это ровно то место, где раунд ТЗ №3 уже ломался.
5. Одноимённые методы с разными сигнатурами в partial-классах `OverlayEditorWindow.*.cs`: `grep -rhoP 'private (static )?(async )?[\w<>?\[\], ]+ \K\w+(?=\()' src/SnapBrief.App/OverlayEditorWindow*.cs | sort | uniq -d` (перегрузки собираются, но два обработчика одного жеста в разных файлах дают двойную обработку).

Ожидаемые места ручного разрешения конфликтов ровно три: `SmokeTestRunner.Run` (список вызовов), `tests/` (соседние файлы) и `EdgeStackWindow.xaml` внутри дорожки C (одна ветка, конфликта нет, но задачи C-3, C-4 и C-8 правят соседние строки: коммиты идут в заданном порядке, не параллельно).

## 6. Строки RU/EN

Все пары кладёт волна 0 (W0-1), кроме пары названия клавиши: она заменяется вместе со своими четырьмя местами в W0-9. Ключ русский, значение английское, значения уникальны. Сверено с существующей таблицей `UiLanguage.cs`.

**Добавить (16 пар):**

| RU | EN | Кому |
|---|---|---|
| `Светлая · Рассвет` | `Light · Dawn` | A4, B1 |
| `розовый` | `rose` | A5 |
| `бирюзовый` | `cyan` | A5 |
| `розово-фиолетовый` | `rose to violet` | A5 |
| `бирюзово-синий` | `cyan to blue` | A5 |
| `Пройти знакомство заново` | `Take the tour again` | E2 |
| `Снимок всего экрана` | `Capture the whole screen` | C8, E1 (в W0-9) |
| `Нажми {0} или «Новый снимок»` | `Press {0} or "New capture"` | C3 |
| `Нажми «Новый снимок»` | `Press "New capture"` | C3, клавиша выключена |
| `экран` | `screen` | C8, чип карточки |
| `импорт` | `import` | C8, чип карточки и подпись редактора |
| `Не удалось снять экран` | `The screen could not be captured` | C8, ошибка |
| `весь экран` | `whole screen` | C8, подпись редактора |
| `мониторов: {0}` | `monitors: {0}` | C8, подпись редактора (решение 10) |
| `По ширине · {0} %` | `Fit width · {0} %` | C8, переключатель |
| `По высоте · {0} %` | `Fit height · {0} %` | C8, переключатель |
| `Добавить цвет в свою палитру` | `Add the colour to my palette` | D1, кнопка «+» |

**Удалить (5 пар):**

| RU | Где было | Когда |
|---|---|---|
| `Светлая` (`:40`) | карточка темы `light` | W0-6, вместе с темой |
| `Рассвет` (`:41`) | карточка `dawn`, остаётся без потребителя | W0-6 |
| `Скриншот всего экрана в папку` (`:47`) | четыре места названия клавиши | W0-9 |
| `Показывать рамку` (`:77`) | переключатель `OutlineSegment` | W0-3 |
| `Рамка` (`:77`) | заголовок блока `OverlayEditorWindow.xaml:310`, единственный потребитель, проверено грепом | W0-3 |

`Контур` (`:76`) остаётся: это подпись сегмента заливки (`OverlayEditorWindow.xaml:406`). `1:1` одинаково в обоих языках и в таблицу не идёт. Литерал `весь экран` внутри `PromptGenerator` это данные `prompt.md` и через `UiLanguage` не проходит. Строка `Не удалось сохранить экран` живёт литералом в `Saving.cs:55` без пары и уходит вместе с переписанным методом.

## 7. Изменения формата

Абзацы пишутся в заметки волн и дорожек, волна 2 переносит их в `tasks/verification.md`. Mac синхронизирует по ним (`AGENTS.md`, правило 4).

| # | Что | Где | Кто пишет абзац |
|---|---|---|---|
| 1 | `CaptureItem` получает `kind` (`"region"` / `"fullscreen"` / `"import"`, по умолчанию `region`) и `monitorCount` (по умолчанию 0, заполняется только у `fullscreen`). Оба поля-`init`, старые файлы читаются без миграции, `SchemaVersion` остаётся 1. Заодно начинает использоваться давно существующее `title`: у импорта туда пишется имя файла, у снимка всего экрана и у снимка области оно остаётся пустым, а подпись «весь экран» строится из `kind`. Следствие для `prompt.md`: снимок всего экрана и импортированный файл дают строку «Снимок C — весь экран.» / «Снимок D — IMG_0512.png.» даже без комментариев, тогда как раньше снимок без заметок в текст не попадал вовсе. `SessionValidation` новые поля не проверяет, `monitorCount < 0` при чтении приводится к 0 | `session.json`, `prompt.md` | волна 0 (W0-2), черновик `C §C8-модель` с поправкой решения 2 |
| 2 | `hasOutline` выведено из обращения: с 1.5.0 не пишется вообще, а при чтении означает миграцию. Правило: `kind == "rectangle"` и `hasOutline == false` читается как «сплошная заливка одним цветом» (`fill = solid`, `fillColor` из записанного `fillColor`, иначе из `strokeColor`); во всех прочих случаях поле игнорируется; старая `redaction` читается как раньше (чёрная сплошная). Назад совместимости нет: сессия, записанная 1.5.0, в 1.4.0 откроется с контуром у отметок, которые его не имели | `session.json` | волна 0 (W0-3), дословно `D §2.4` |
| 3 | Четыре поля файла настроек (`annotationOutline`, `annotationShape`, `annotationFill`, `annotationFillColor`) выведены из обращения: больше не пишутся и не читаются, старые значения игнорируются и исчезают при первой перезаписи. Каждый снимок начинается с «контур, без заливки, прямоугольник». Между снимками запоминаются только цвет, толщина, размер шрифта, палитра, ряд «Своей» и карандаш/маркер | `settings.json` | волна 0 (W0-3) |
| 4 | `SettingsVersion` 1 → 2. Новое правило: тема `light` при версии меньше 2 читается как `dark` (карточка «Светлая» ушла, `Рассвет` и есть светлая тема). Одновременно каждое правило миграции получает свой порог вместо общего: правило громкости спрашивает `storedVersion < 1`, правило темы `storedVersion < 2`, иначе подъём версии второй раз прогнал бы правило громкости по файлам версии 1. Файл переписывается один раз при чтении | `settings.json` | волна 0 (W0-8), обоснование `B §2.4` |
| 5 | Ширина ленты: `MinimumWidth` 200 → 244, `DefaultWidth` 208 → 244. Состав полей не меняется, меняется трактовка: сохранённая пользователем `StackWidth` меньше 244 поднимается до 244 при чтении, а видимая панель при этом становится на 20 px уже, чем была (поле ушло под тень). Видимый зазор до края экрана остаётся 20 px | `settings.json` (значение), `StripResizeGeometry` (контракт) | волна 0 (W0-5) |
| 6 | Четыре новых акцента (`rose`, `cyan`, `rose-violet`, `cyan-blue`) и шесть тем вместо семи. `AccentId` и `Theme` остаются строками, состав допустимых значений меняется; неизвестное значение по-прежнему гаснет в `blue` и `dark` | словари `Themes/**`, `settings.json` | волна 0 (W0-6, W0-7) |
| 7 | Снимок всего экрана перестаёт писаться прямо в папку: теперь он идёт в ленту и попадает в папку автосохранением, как все остальные. При выключенном «Автоматически сохранять готовые снимки» файл в папку больше не падает. Id клавиши `fullscreen-save` и поле `FullscreenSaveId` не меняются, меняется только название в настройках | поведение, не схема | дорожка C (C-8) |

## 8. Проверка

**Автоматически, перед каждым коммитом:** `scripts/build.ps1` (238 тестов плюс `--smoke-test`). Перед каждым слиянием и после него: `scripts/build.ps1 -OutputDirectory $env:LOCALAPPDATA\Temp\snapbrief-candidate-tz005`.

Чек-лист F ТЗ, на 100 % и на 125 %. Пометка «авто» означает, что пункт покрыт тестом или smoke-пробой и на экране только подтверждается; «живьём» означает, что автоматической проверки нет вовсе.

| # | Пункт F | Чем покрыт |
|---|---|---|
| 1 | Чистая учётка, мастер по центру, углы без второго контура, тянется за верхний пояс, «—» сворачивает | **живьём.** DWM и `WindowChrome` в headless не проверяются; косвенно есть `startup.log` со строкой `Onboarding corners: rounded=` |
| 2 | Шаг 4: 6 карточек, стрелки и колесо до «Светлая · Рассвет» целиком, 12 акцентов, клик перекрашивает окно, низ шага виден | **авто частично.** Состав тем и акцентов, разделитель по признаку, шаг колеса и снятое `BringSelectedCardIntoView` в `RunProbe`; перекраска на экране и видимость низа шага живьём |
| 3 | Шаг 5: четыре слайда, точки на месте, скроллбара нет | **авто.** `RunSlidesProbe` меряет высоту блока подписей на обоих языках; появление скроллбара живьём |
| 4 | «Начать» даёт пустую компактную ленту | **живьём.** Показ окна в headless не проверяется, есть строка в `startup.log` |
| 5 | Три снимка: C поверх B поверх A, полоса с буквой сверху, тени в каждом шве, тень окна не срезана | **живьём.** Порядок отрисовки в `StackPanel` детерминирован кодом, но тени и швы проверяются только глазами |
| 6 | 26 снимков: скроллбар 4 px, не меняется при наведении на список; открыть снимок из середины и вернуться, порядок, тени и прокрутка те же | **живьём.** Отдельно замерить плавность прокрутки на 125 % (виртуализация выключена, 26 живых `DropShadowEffect`) |
| 7 | Лента тянется за пустое место шапки и за поля | **живьём** |
| 8 | Win+Shift+S снимает ленту | **живьём** |
| 9 | Клавиша «весь экран» на двух мониторах: карточка с чипом, редактор по ширине, «1:1» прокручивается, уходит в Ctrl+V | **авто частично.** Строка `prompt.md`, наличие переключателя и подпись «По ширине» в smoke; два монитора, шов и прокрутка живьём |
| 10 | «Импортировать файл…» с PNG и JPG, вертикальный файл по высоте | **авто.** Два теста на копию кадра и кодирование в пуле плюс smoke на реальном файле; отдельно проверить GIF и 8-битный PNG (палитра в `WriteableBitmap`, `C §7`) |
| 11 | Редактор: цвет при «Комментарии», три рамки с разной заливкой, два комментария подряд с перетаскиванием за бейдж и за якорь | **авто частично.** `PanelChecks`, `VerifyGestureRules` и `VerifyHoverManipulation`; вид контура на экране живьём |
| 12 | Шесть тем на ленте, в редакторе и в мастере; «Стекло» это градиент B | **авто частично.** Наборы ключей, стопы «Стекла» и хром ленты по всем палитрам в smoke; сам вид живьём, включая градиент в капсуле (44 px против 420 у ленты: весь трёхстоповый переход помещается в капсулу) |
| 13 | Настройки → «Пройти знакомство заново» открывает полный мастер с текущими значениями | **авто частично.** Свойство и `DialogResult` в smoke; открытие мастера живьём |

Отдельно на 125 %: `scripts/build.ps1` при системном масштабе 125 % (проба панели редактора по построению даёт одинаковый результат на любом масштабе, но сам прогон при 125 % с прошлого раунда так и не делался), растягивание ленты за угол и за левую ручку до упора и обратно, лупа пипетки, укладка панели разметки вместе с новым переключателем масштаба и открытой панелью комментариев.

Живая приёмка обязательна до передачи сборки: в прошлом раунде весь диапазон прошёл автоматически, и половина пунктов этого ТЗ это то, что видно за первые десять минут живого прогона.

## 9. Открытые вопросы

**Кате:**

1. **Бейдж комментария и активный цвет** (решение 4). ТЗ перечисляет бейдж среди того, что красится активным цветом; в коде он всегда акцентный, и на экране, и в экспортном PNG. Оставляем акцентным (нумерация это единая система) или красим? Если красить, это правка `AnnotationCanvas` и `WpfExportImageRenderer` в дорожке D, S.
2. **Число мониторов в подписи** (решение 10). Сейчас будет «весь экран · мониторов: 2 · 3840×1125». Если нужна форма «2 монитора», добавляются две пары строк с разными английскими значениями и правило выбора формы.
3. **Скриншот шага 4 с обрезанным низом** (G1 ТЗ). Пункт снят решением 7 (расчёт исправлен вслепую). Скриншот всё равно нужен, чтобы подтвердить, что дело было именно в смешанном DPI, а не в чём-то ещё.
4. **Снимок всего экрана при выключенном автосохранении** (§7 п. 7). Теперь он не падает в папку вовсе. Это следует из ТЗ («в папку он попадает автосохранением, как все остальные»), но меняет привычку тех, кто пользовался клавишей именно ради файла в папке.

**Никите:**

5. **Окно ленты 244 вместо 224** (решение 1). Видимая панель остаётся 204 и карточка 168, то есть на экране ничего не уменьшается, но у всех, кто тянул ленту руками, сохранённая ширина поднимется до 244. Альтернатива: оставить окно 224 и сократить тень до `BlurRadius 16 / ShadowDepth 3` (тень заметно жёстче).
6. **`ResizeMode="CanMinimize"` у мастера** (`A §1.2`). Пока он стоит, Win+стрелки и снап-раскладки мастеру недоступны, а `DWMWCP_ROUND` может тихо ничего не сделать, если окно останется без `WS_THICKFRAME`. Менять режим не предлагаю: разметка шагов рассчитана на 620 и поедет.
7. **Галерея тем открывается на первой карточке и в настройках тоже** (`A §1.5`, риск). ТЗ формулирует требование для шага 4, но контрол один; расхождение поведения между двумя местами было бы хуже. Отмечено как осознанное.
8. **AUMID и уже закреплённые ярлыки** (вопрос с прошлого раунда). Проверяется при живой приёмке обновления поверх 1.4.0.
9. **Живая проверка установщика** тянется с круга ТЗ №2 и снова входит в приёмку. Если чистой учётки под рукой нет, пункт снова останется неподтверждённым.

## 10. На потом

- **Настоящее стекло (B3).** Условия зафиксированы в `B §4`: снять `AllowsTransparency` у ленты, настроек, `CaptureOverlay`, `DiscardSessionWindow` и `SavePackageWindow`, отдать скругление и тень DWM, перетрясти `StripResizeGeometry` вместе с полями под тень. Отдельным раундом после того, как C1-C7 устоялись; на Windows 10 размытия нет, нужен фолбэк на градиент B. Тема `glass` при этом остаётся обычной палитрой: acrylic это свойство окна, а не токен, словарь §3 переживёт переход. Эталон `reference-html/06-acrylic-later.html`.
- **Закрепление на панели задач (G2 ТЗ).** Решение 9, в раунд не входит.
- **Панорама пробелом в редакторе**, если решение 8 упрётся в механизм смещения.
- **Масштаб выше 100 % в редакторе.** Ctrl+колесо зажато сверху 1:1, потому что переключатель обещает ровно два состояния (`D §11` п. 4).
- **Темизация оставшихся окон**: `CaptureOverlay`, `SavePackageWindow`, `DiscardSessionWindow`. Показываются секундами, ждут своего раунда.
- **Глиф размытия.** `PortraitBlur` `EABE` есть только в Segoe Fluent Icons; на Windows 10 он дал бы пустой квадрат, поэтому остаётся `Path`. Вернуться, когда Windows 10 уйдёт из поддержки (`SupportedOSPlatformVersion` 10.0.17763).
- **Глиф «стрелка вверх»** в ленте (`EdgeStackWindow.xaml:316`): имя не подтверждено, замена отложена до сверки (`D §3.3`).
- **Синхронизация macOS-порта** по §7 и по абзацам «Изменение формата»: шесть палитр с 14 токенами плюс два новых токена ползунка, двенадцать акцентов с правилами `B §5.1`, миграция `light → dark` и `SettingsVersion = 2`, `CaptureKind`/`MonitorCount`/`title`, правило чтения `hasOutline`, `OutlineColorOf`, порядок hit-test комментария, `ViewScale`/`ViewOffset`, геометрия ленты (`StackMetrics`: 244, поле 20, панель 204, карточка 168, `edgeGap` 0), порядок карточек и полоса подписи сверху, снятие постоянного исключения из захвата. Детали переноса в `A §Перенос`, `B §10`, `C §10`, `D §10`.
