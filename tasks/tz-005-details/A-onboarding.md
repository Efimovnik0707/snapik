# Дорожка A, онбординг (ТЗ №4: A1, A2, A3, A4, A6, A7, E2 и UI-часть A5)

База: `master` = `a2f72e1` (1.4.0), все file:line по этому коммиту. Эталоны: `tasks/handoff-005/reference-png/01`, `tasks/handoff-005/reference-html/01-step4-v2.html`, `01b-step4-v2-gallery-end.html`.

Границы. Словари `Themes/Accents/*.xaml`, `Themes/Palettes/*.xaml`, `ThemeService.Themes`/`ThemeService.Accents` и smoke на состав акцентов ведёт дорожка B. Здесь только ряд и галерея как контролы плюс те словари имён, что физически лежат в `AppearancePicker.xaml.cs`. Главное окно ленты ведёт дорожка C, здесь только точка вызова.

---

## Где ТЗ не сходится с кодом

1. **A1, окно настроек.** ТЗ: «то же для окна настроек, если оно тоже перешло на `WindowChrome`». Не перешло. `HotkeySettingsWindow.xaml:3` держит `WindowStyle="None" AllowsTransparency="True" Background="Transparent"`, блока `WindowChrome.WindowChrome` в файле нет. Это layered-окно, DWM его углы не скругляет в принципе, и второго контура там нет: скруглённый `Border` (`HotkeySettingsWindow.xaml:10`) и есть вся видимая рамка. Для настроек пункт снимается, DWM туда не идёт.
2. **A2, снап.** ТЗ: «заодно окно получит Win+стрелки и снап-раскладки Windows 11». Не получит: `OnboardingWindow.xaml:3` задаёт `ResizeMode="CanMinimize"`, Windows не снапит окно, которое нельзя менять в размере. `CaptionHeight` даёт перетаскивание, системное меню по правому клику и двойной клик (при `CanMinimize` он ничего не делает). Само требование A2 выполняется, обещание про снап снимается. Менять `ResizeMode` не предлагаю: разметка шагов рассчитана на 620 и поедет.
3. **A2, перехват кликов (ответ на вопрос задания).** В поясе 48 px лежат `MinimizeButton` (`OnboardingWindow.xaml:112`) и `SkipButton` (`:115`), оба в правом верхнем углу, ровно там, где `WindowChrome` по умолчанию держит невидимые aero-кнопки (`UseAeroCaptionButtons` по умолчанию `True`). Одного `IsHitTestVisibleInChrome` мало, нужно ещё `UseAeroCaptionButtons="False"`. Содержимое шагов в пояс не попадает: контент начинается на y = 20 (padding) + 28 (шапка) + 14 (margin) = 62.
4. **A3, знак ошибки.** Механизм ТЗ назвало верно (`OnboardingWindow.xaml.cs:98-101`: рабочая область берётся у монитора под курсором, `TransformFromDevice` у монитора, где окно создано), но следствие двустороннее. Курсор на 125 %, окно создано на 100 %: `MaxHeight` выходит больше нужного, окно не клампится и вылезает за рабочую область. Курсор на 100 %, окно создано на 125 %: `MaxHeight` меньше нужного, `Height=600` клампится, появляется скролл и низ шага уезжает. Второе и есть картинка Кати. Дополнительно в том же масштабе считаются `Left`/`Top` (`:104-105`), поэтому окно может уехать на соседний монитор, что совпадает с её «возможно, на другом мониторе».
5. **A4, «стрелка сдвигает на 116 px и гаснет».** Арифметика верна, но это не дефект, а кламп в `PageBy`/`OnGalleryScrolled` (`AppearancePicker.xaml.cs:264-288`), который специально доводит последнюю карточку до полной видимости. С шестью карточками последний шаг тоже 116 px: viewport 452 (520 − 26 − 26 − 16 полей), extent 6 × 142 = 852, `ScrollableWidth` = 400, `LastPage` = 3, шаги 0 → 142 → 284 → 400. Требования «шаг ровно 142» и «последняя карточка целиком» одновременно невыполнимы ни при каком числе карточек; выполняем второе, первое для всех шагов кроме последнего. Реальный дефект, который видела Катя, другой: галерея открывается прокрученной к выбранной теме, это `BringSelectedCardIntoView` (`:243`, `:292-298`).
6. **A5, разделитель.** Сейчас он по имени (`AppearancePicker.xaml.cs:188`), признак для замены уже есть: у градиентных акцентов `AccentBrush` это `LinearGradientBrush` (`Themes/Accents/BlueViolet.xaml:13`), у сплошных `SolidColorBrush` (`Blue.xaml:10`). Плюс ширина: нынешние отступы дают 465 px, а не 455 из ТЗ; расхождение в `Divider()` (`:203`), у него `Margin="4,0,14,0"`, а в эталоне `01b` разделитель имеет по 4 px с обеих сторон.
7. **A6, 120 px не хватает.** Строка подписи это max(кружок 22, текст) плюс нижний отступ 10 (`HowToSlides.xaml:25-38`), то есть 32 при одной строке текста и 50 при двух, у последней строки отступа нет. Колонка текста 446 px (480 − 22 − 12), и вторая строка слайда 4 переносится и в RU, и в EN (`UiLanguage.cs:181`), так что блок слайда 4 уже сейчас ≈ 136 px. Фиксация на 120 обрежет слайд 4. Нужная величина 140, обоснование в A6.
8. **E2, тема не сохраняется вообще.** `WriteOnboarding` в ветке `merge` (`EdgeStackWindow.xaml.cs:1246-1254`) пишет только `CaptureId`, `Language`, `OnboardingVersion`. `Theme` и `AccentId`, которые мастер кладёт в `Candidate` (`OnboardingWindow.xaml.cs:293-298`), теряются на любом запуске поверх читаемого `settings.json`. Для E2, где файл есть всегда, это ломает требование «Начать записывает то, что пользователь поменял» целиком. В диалоге настроек тот же набор полей пишется правильно (`EdgeStackWindow.xaml.cs:1310`).
9. **E2, «Пропустить» трогает язык.** `SkipSetup` (`OnboardingWindow.xaml.cs:401-414`) возвращает тему и акцент, но не язык, а `Candidate` уносит `_language`. Переключение языка на шаге 1 записывается и при «Пропустить».

---

## A1. Углы окна

Решение: скругление отдаём DWM, внутренний контур убираем всегда. Версию Windows не проверяем числом, проверяем результатом вызова: на Windows 10 атрибут 33 возвращает `E_INVALIDARG`, окно остаётся прямоугольным, и это ровно то, что требует ТЗ для Windows 10.

Изменения:

- Новый файл `src/SnapBrief.App/DwmWindowCorners.cs`, `internal static class DwmWindowCorners`:
  - `[DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);`
  - `internal static bool Round(IntPtr hwnd)`: `var preference = 2; return DwmSetWindowAttribute(hwnd, 33, ref preference, sizeof(int)) == 0;` внутри `try/catch (DllNotFoundException or EntryPointNotFoundException)` → `false`.
  - Констант `DWMWA_WINDOW_CORNER_PREFERENCE = 33`, `DWMWCP_ROUND = 2` держать именованными в этом же файле.
- `OnboardingWindow.xaml.cs:93` `OnSourceInitialized`: после `base.OnSourceInitialized(e)` вызвать `DwmWindowCorners.Round(new WindowInteropHelper(this).Handle)` и результат отдать в `Trace?.Invoke($"Onboarding corners: rounded={...}")`.
- `OnboardingWindow.xaml:104`: у корневого `Border` убрать `BorderBrush`, поставить `BorderThickness="0" CornerRadius="0"`. `Background="{DynamicResource SurfaceBrush}"` и `Padding="24,20,24,24"` оставить.
- Комментарий `OnboardingWindow.xaml:5-7` переписать под то, что теперь правда.

Проверка номера сборки. `Environment.OSVersion.Version.Build` на .NET 10 идёт через `RtlGetVersion` и отдаёт настоящие 22000+/26200 даже без секции `<compatibility><supportedOS>` в `app.manifest` (её там нет, см. `src/SnapBrief.App/app.manifest`). То есть проверка работала бы, но она лишняя: HRESULT вызова информативнее и не врёт на будущих сборках. Если номер всё же понадобится для лога, брать `Environment.OSVersion.Version.Build`, а не Win32 `GetVersionEx`, который без манифеста отдаёт 6.2.

Окно настроек: не трогаем (см. пункт 1 расхождений).

Строки RU/EN: нет.

Smoke: `OnboardingWindow.RunOnboardingProbe` (`:428`) работает на окне без handle, `Round` там не вызывается. Нового теста не нужно (P/Invoke к DWM в headless-прогоне не проверяется), проверка живая, пункт F1 чек-листа.

Риски. DWM скругляет окно верхнего уровня с рамкой; при `WindowStyle="None"` плюс `WindowChrome` рамка формально есть, но связка `ResizeMode="CanMinimize"` + `WindowChrome` может оставить окно без `WS_THICKFRAME`, и тогда `DWMWCP_ROUND` тихо ничего не сделает. Проверять первым делом живьём на Windows 11. Фолбэк, если так: вернуть скругление внутреннему `Border` и отказаться от DWM полностью (одно скругление вместо двух, тень системная не появится).

---

## A2. Зона перетаскивания

Изменения в `OnboardingWindow.xaml`:

- `:9` → `<WindowChrome CaptionHeight="48" GlassFrameThickness="0" ResizeBorderThickness="0" CornerRadius="0" UseAeroCaptionButtons="False"/>`.
- `:109`: убрать `MouseLeftButtonDown="OnHeaderDrag"`, `Background="Transparent"` и `Height="28"` оставить.
- `:112` и `:115`: добавить `WindowChrome.IsHitTestVisibleInChrome="True"` обеим кнопкам.
- `OnboardingWindow.xaml.cs:420`: удалить `OnHeaderDrag`.

Что внутри пояса. Только эти две кнопки и `TextBlock "SnapBrief"` (`:110`), текст кликов не ловит и должен остаться частью заголовка. Ничего из содержимого шагов в первые 48 px не попадает (контент начинается с y = 62).

Строки RU/EN: нет.

Smoke: `ResolveTriggerBindings` и `RunOnboardingProbe` на `WindowChrome` не смотрят, ломаться нечему. Новой логики нет, теста не добавляем.

Риски. `CaptionHeight > 0` включает системное меню по правому клику в поясе (это штатно) и `Alt+Space`. Двойной клик при `CanMinimize` ничего не делает. Если после правки кнопка «—» перестанет нажиматься, значит `UseAeroCaptionButtons` не выставлен.

---

## A3. Шаг 4 обрезан снизу

Приоритет низкий, воспроизводится только на смешанном DPI. Делаем расчёт корректным и оставляем след в логе, чтобы следующий отчёт Кати можно было прочитать.

Формула. Масштаб брать у того монитора, где окно будет показано, а не у того, где создано, и позицию задавать в физических пикселях, потому что `Left`/`Top` в WPF трактуются в DPI текущего монитора окна, а он ещё не тот.

```
// вместо OnboardingWindow.xaml.cs:98-105
var screen  = WinForms.Screen.FromPoint(WinForms.Cursor.Position);
var work    = screen.WorkingArea;                       // физические px целевого монитора
var scale   = MonitorMetrics.Scale(work.Left, work.Top); // GetDpiForMonitor(MDT_EFFECTIVE_DPI) / 96.0, при ошибке 1.0
MaxHeight   = Math.Max(MinimumUsefulHeight, work.Height / scale - 40);
var height  = Math.Min(Height, MaxHeight);              // DIU целевого монитора
var deviceW = (int)Math.Round(Width  * scale);
var deviceH = (int)Math.Round(height * scale);
SetWindowPos(handle, IntPtr.Zero,
             work.Left + (work.Width  - deviceW) / 2,
             work.Top  + (work.Height - deviceH) / 2,
             0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
```

- `MonitorMetrics` кладём в тот же файл, что и `DwmWindowCorners` (см. «Общий фундамент»): `MonitorFromPoint(point, MONITOR_DEFAULTTONEAREST=2)` плюс `GetDpiForMonitor(hmon, 0, out dpiX, out _)` из `Shcore.dll`, `scale = dpiX / 96.0`, при любом ненулевом HRESULT возвращать `1.0`. Готовый `MonitorFromPoint` уже объявлен приватно в `Controls/ScreenColorPicker.cs:109`, дублировать объявление в новом файле нормально, трогать пипетку не надо.
- После `SetWindowPos` Windows пришлёт `WM_DPICHANGED`, WPF пересчитает окно по предложенному прямоугольнику и центр сдвинется на пару пикселей. Поэтому добавить `protected override void OnDpiChanged(DpiScale oldDpi, DpiScale newDpi)`: один раз (флаг `_placed`) пересчитать `MaxHeight` и центр уже по `VisualTreeHelper.GetDpi(this)`, дальше не реагировать.
- В `catch` (`:107`) и в успешную ветку писать `Trace?.Invoke($"Onboarding placement: monitor={work}, scale={scale}, MaxHeight={MaxHeight}, height={height}")`. Это то, по чему пункт можно будет снять или подтвердить по `startup.log`.

Строки RU/EN: нет.

Smoke: новая логика это `MonitorMetrics.Scale`, но она целиком P/Invoke, проверять в headless нечего. Добавить в `SmokeTestRunner` одну проверку чистой арифметики, вынеся её в `internal static double UsefulHeight(double workAreaDevice, double scale, double minimum)` (`workAreaDevice / scale - 40`, не ниже `minimum`): три случая (100 %, 125 %, крошечный монитор → `MinimumUsefulHeight`).

Риски. При двух мониторах `SetWindowPos` до первого показа иногда гасит `WindowStartupLocation`; у нас он и так `Manual` (`:4`), конфликта нет. Если `GetDpiForMonitor` недоступен (Windows 8.0 и ниже, у нас пол 10.0.17763, то есть невозможно), `scale = 1.0` даёт нынешнее поведение.

---

## A4. Галерея тем: 6 карточек, прокрутка до конца

Список тем (id, порядок, значения) берётся из B1 как данность, здесь только контрол.

Изменения в `AppearancePicker.xaml.cs`:

- `ThemeNames` (`:29-33`): убрать `["light"]`, заменить `["dawn"] = "Рассвет"` на `["dawn"] = "Светлая · Рассвет"`. Остальные пять как есть. Порядок карточек задаёт `ThemeService.Themes`, это B.
- `MarkSelectedCard` (`:236-244`): убрать вызов `BringSelectedCardIntoView()`. Метод `:292-298` удалить целиком. Галерея всегда открывается на первой карточке, рамка на выбранной остаётся, где бы карточка ни стояла.
- Комментарий `AppearancePicker.xaml:82-83` («семь карточек») переписать под шесть.

Колесо мыши (`PreviewMouseWheel`):

- `AppearancePicker.xaml:84`: добавить `PreviewMouseWheel="OnGalleryWheel"` на `ScrollViewer x:Name="Gallery"`.
- В code-behind:

```
private void OnGalleryWheel(object sender, MouseWheelEventArgs e)
{
    if (e.Delta == 0) return;
    PageBy(e.Delta > 0 ? -1 : 1);
    e.Handled = true;   // иначе колесо уходит в ScrollViewer мастера, OnboardingWindow.xaml:123
}
```

`e.Handled = true` в `Preview`-фазе и есть ответ на «колесо над галереей не прокручивает окно мастера»: без него `ScrollViewer` галереи с выключенной вертикальной прокруткой пробрасывает событие наверх.

Горизонтальный жест тачпада (`WM_MOUSEHWHEEL`, `0x020E`):

```
private const int WM_MOUSEHWHEEL = 0x020E;
private HwndSource? _source;

// в конструкторе, после ApplyLanguage
Loaded   += (_, _) => { _source ??= PresentationSource.FromVisual(this) as HwndSource; _source?.AddHook(OnWindowMessage); };
Unloaded += (_, _) => { _source?.RemoveHook(OnWindowMessage); _source = null; };

private IntPtr OnWindowMessage(IntPtr hwnd, int message, IntPtr wParam, IntPtr lParam, ref bool handled)
{
    if (message != WM_MOUSEHWHEEL || !Gallery.IsMouseOver) return IntPtr.Zero;
    var delta = (short)((wParam.ToInt64() >> 16) & 0xFFFF);   // HIWORD, знаковое
    if (delta == 0) return IntPtr.Zero;
    PageBy(delta > 0 ? 1 : -1);                               // вправо = вперёд, знак обратный обычному колесу
    handled = true;
    return IntPtr.Zero;
}
```

- Хук вешается на `HwndSource` окна, в котором контрол сейчас живёт; `AppearancePicker` встречается дважды (мастер и вкладка «Вид»), каждый экземпляр держит свой. `Loaded`/`Unloaded` в WPF приходят парами и повторно, отсюда `??=` и снятие хука.
- Гейт по `Gallery.IsMouseOver`, а не по координатам из `lParam`: WPF ведёт `IsMouseOver` сам, и это единственное, что нужно, чтобы жест над рядом акцентов или над примером не листал галерею. Ограничение: `WM_MOUSEHWHEEL` Windows шлёт окну с фокусом, поэтому жест над неактивным окном не сработает. Это приемлемо, у мастера фокус всегда есть.

Стрелки: `PageBy` (`:264`) и `MarkChevrons` (`:273`) не трогаем, гашение на концах по `opacity 0.42` уже даёт `Chevron`-стиль (`AppearancePicker.xaml:25`).

Строки RU/EN, добавить в `UiLanguage.cs`: `["Светлая · Рассвет"] = "Light · Dawn"`. Убрать `["Светлая"] = "Light"` нельзя вслепую, эта пара может использоваться ещё где-то; удаление ведёт B вместе с темой `light`.

Smoke: `AppearancePicker.RunProbe` (`:330-400`).

- `:361-362` («Seven cards of 132 must not fit into 520») оставить по смыслу, текст исключения переписать на шесть; условие `ScrollableWidth > 0` при шести карточках выполняется (852 против 452).
- Добавить: после `PageBy(-N)` эмулировать колесо через новый `internal void PageByWheel(int notches) => PageBy(notches)` (обёртка нужна только затем, чтобы не конструировать `MouseWheelEventArgs` без `MouseDevice`) и проверить, что `_firstCard` вырос на 1 и упёрся в `LastPage`.
- Добавить: `picker.SelectedTheme = <последняя тема>` при `_firstCard == 0` не двигает галерею (`_firstCard` остаётся 0), а рамка стоит на выбранной карточке. Это фиксация снятого `BringSelectedCardIntoView`.

Риски. Снятие `BringSelectedCardIntoView` меняет и вкладку «Вид»: там галерея тоже будет открываться на первой карточке. ТЗ формулирует требование для шага 4, но контрол один, и расхождение поведения между двумя местами было бы хуже. Отмечаю как осознанное.

---

## A5 (UI-часть). Ряд из 12 акцентов

Словари `Themes/Accents/Rose.xaml`, `Cyan.xaml`, `RoseViolet.xaml`, `CyanBlue.xaml` и порядок в `ThemeService.Accents` делает B. Здесь ряд.

Изменения в `AppearancePicker.xaml.cs`:

- `AccentNames` (`:38-43`) дополнить: `["rose"] = "розовый"`, `["cyan"] = "бирюзовый"`, `["rose-violet"] = "розово-фиолетовый"`, `["cyan-blue"] = "бирюзово-синий"`. Порядок в словаре роли не играет, ряд строится по `ThemeService.Accents`.
- `BuildAccentRow` (`:183-199`): условие `if (accent == "blue-violet")` заменить на признак. Кисть уже читается строкой ниже, поэтому:

```
var brush = Frozen(ThemeService.LoadAccent(accent)["AccentBrush"] as Brush);
if (brush is not SolidColorBrush && !dividerPlaced) { AccentRow.Children.Add(Divider()); dividerPlaced = true; }
```

  `bool dividerPlaced` локальная переменная метода. Признак «не `SolidColorBrush`» работает, потому что у всех градиентных акцентов `AccentBrush` это `LinearGradientBrush` (`Themes/Accents/BlueViolet.xaml:13`), а у сплошных `SolidColorBrush` (`Blue.xaml:10`).
- `Divider()` (`:203`): `Margin` с `4,0,14,0` на `4,0,4,0`. После этого ряд занимает 12 × 28 + 11 × 10 + 1 = 455 px (эталон `01b`), при ширине шага 520 помещается с запасом 65.
- Размер кружка 28 и шаг 10 уже заданы стилем `AccentDot` (`AppearancePicker.xaml:52-55`), менять нечего.

Строки RU/EN, добавить в `UiLanguage.cs`: `["розовый"] = "rose"`, `["бирюзовый"] = "cyan"`, `["розово-фиолетовый"] = "rose to violet"`, `["бирюзово-синий"] = "cyan to blue"`. Формат «X to Y» повторяет уже принятый для градиентов (`UiLanguage.cs:38-39`).

Smoke: счётчик `AccentRow.Children.OfType<RadioButton>().Count() != ThemeService.Accents.Count` (`AppearancePicker.xaml.cs:339`) уже покрывает 12 кружков и не считает разделитель. Добавить свою проверку: разделитель ровно один и стоит непосредственно перед первым кружком, чья кисть не `SolidColorBrush`. Проверки на состав словарей акцентов ведёт B.

Риски. Если B заведёт градиентный акцент, у которого `AccentBrush` окажется `RadialGradientBrush` или `SolidColorBrush`, признак сломается молча. Smoke-проверка выше это ловит.

---

## A6. Шаг 5: слайд 3 прыгает

Контейнер. Все четыре блока подписей лежат в одном `Grid` (`HowToSlides.xaml:915`, `<Grid Margin="0,0,0,2">`), внутри него `SlideCaptions1` (`:916`), `SlideCaptions2` (`:936`), `SlideCaptions3` (`:962`), `SlideCaptions4` (`:982`). `Grid` берёт высоту видимого потомка, три остальных `Collapsed` (`HowToSlides.xaml.cs:113-114`), поэтому высота гуляет от слайда к слайду, а ряд точек (`:1011-1024`) стоит следом в том же внешнем `StackPanel` и едет за ним.

Фиксированную высоту получает **один** элемент, `Grid` на `:915`. Внутренние `StackPanel` высоту не получают, им добавляется `VerticalAlignment="Top"`, чтобы строки шли сверху, а не растягивались.

Число. Не 120, а **140**. Счёт по стилям (`HowToSlides.xaml:25-38`): кружок 22, текст 14/20, `CaptionRow` даёт нижний отступ 10, у последней строки слайда отступа нет. Колонка текста 446 px (ширина контрола 480 на `:383`, минус кружок 22 и `Margin="12,0,0,0"` у `CaptionText`). Слайд 4: строка 1 = 32, строка 2 переносится на две строки и в RU, и в EN (`UiLanguage.cs:181`) = 50, строка 3 = 32, строка 4 = 22, итого 136. 120 из ТЗ обрезало бы слайд 4.

Высота шага при 140 (то, из-за чего скроллбар не появится): заголовок и подзаголовок 30 + 4 + 21 + 12 = 67, сцена 210 + 14 = 224, подписи 140 + 2 = 142, ряд точек 30. Сумма 463. Доступно в `ScrollViewer` мастера 466 = 600 − 44 (padding `:104`) − 42 (шапка 28 + margin 14) − 48 (низ: margin 14 + кнопка 34). Запас 3 px. Больше 140 брать нельзя.

Изменения:

- `HowToSlides.xaml:915`: `<Grid Height="140" Margin="0,0,0,2">`. Число вынести в комментарий с расчётом выше.
- `:916`, `:936`, `:962`, `:982`: добавить `VerticalAlignment="Top"`.
- `ScrollViewer` мастера (`OnboardingWindow.xaml:123`) не трогать: `VerticalScrollBarVisibility="Auto"` остаётся страховкой для маленьких экранов (комментарий `:121-122`), скроллбар уходит потому, что содержимое перестало вылезать, а не потому, что его запретили.
- Тексты подписей не трогаются, анимации (`Storyboard`, `:44` и далее) тоже: они меняют `Opacity` и `TranslateTransform`, на раскладку не влияют.

Строки RU/EN: нет.

Smoke: в `HowToSlides.RunSlidesProbe` (`HowToSlides.xaml.cs:219-244`) цикл по слайдам уже есть и меряет контрол на 480 × 620. Добавить внутрь цикла, и прогнать цикл дважды, для `ApplyLanguage("ru")` и `ApplyLanguage("en")`: `_captions[index].DesiredSize.Height <= 140` после `UpdateLayout()`, иначе исключение с именем языка и номером слайда. Это ровно та проверка, которая ловит новый перенос строки в будущем переводе.

Риски. Если B сменит тему на светлую и шрифтовые метрики поедут (они не поедут, размер и `LineHeight` заданы явно), проверка выше упадёт в smoke, а не у Кати.

---

## A7. После «Начать» лента появляется сама

Подтверждено: `EdgeStackWindow.xaml.cs:200` прячет ленту, `:209-210` открывают мастера, `:223` вызывает `PositionAtEdge()` без `Show()`. Из трея (`:159`) поведение меняться не должно, там лента уже видна.

Что вызывает мастер: **ничего**. Мастер закрывается сам, `ShowDialog()` (`:1186` для слайдов, `:1206` для полного) возвращает управление, и показывает ленту вызывающая сторона. Это покрывает и «Начать», и «Пропустить», и крестик, и Alt+F4 одной строкой, потому что все они ведут в `Close()`.

Метод ленты: **существующий `ShowStackWithoutActivation()`** (`:620-634`). Он уже делает всё нужное: `Renumber()`, `PositionAtEdge()` или `PositionCapsuleAtEdge()`, `Show()`, `SetWindowPos` без активации, `AnimateStackIn()`. Новый метод не нужен, и на C3 («пустая лента компактная») это не влияет: компактность пустой ленты это её собственная раскладка, дорожка C.

Изменение в `EdgeStackWindow.xaml.cs`, `OnLoaded` (`:194-228`):

```
var wizardShown = false;
if (OnboardingWindow.ShouldShowOnboarding(File.Exists(_settingsPath), _settings, _options.Demo || _options.SmokeTest))
{ ShowOnboarding(); wizardShown = true; }
...
Renumber();
PositionAtEdge();
if (wizardShown) ShowStackWithoutActivation();   // после восстановления сессии, а не до: иначе мигнёт пустой лентой
```

Ставить после `PositionAtEdge()` (`:223`), внутри того же `try`. Демо и smoke не задеты: `ShouldShowOnboarding` там возвращает `false` (`:209`).

Строки RU/EN: нет.

Smoke: показ окна в headless-прогоне не проверяется, новой чистой логики нет. Проверка живая, пункт F4 чек-листа. В `startup.log` след уже есть (`:1174`, «Onboarding opens»), добавить к нему строку «Strip shown after onboarding».

Риски. Конфликт слияния с дорожкой C гарантирован: `OnLoaded` и `ShowStackWithoutActivation` в её зоне. Сливать A7 после C1/C3.

---

## E2. «Пройти знакомство заново»

Где вкладка. `HotkeySettingsWindow.xaml:20-39`, `TabItem Header="Общие"`, внутри один `StackPanel Margin="0,10,0,0"`; последний элемент это ряд сегментов языка (`:35-38`). Ссылка встаёт после него.

Как открывается мастер. `EdgeStackWindow.ShowOnboarding(bool howToOnly = false)` (`:1172`), приватный метод ленты; для полного мастера ветка `:1190-1214`. Настройки открываются из `OpenSettings()` (`:1272`) модально, `ShowDialog()` на `:1336`. Два модальных окна одно поверх другого не городим: ссылка закрывает настройки и просит ленту открыть мастера.

Изменения:

- `HotkeySettingsWindow.xaml`, после `:38`: `<TextBlock x:Name="RunOnboardingLink" Text="Пройти знакомство заново" FontSize="12" Foreground="{DynamicResource TextFaintBrush}" Cursor="Hand" Margin="0,18,0,0" MouseLeftButtonDown="OnRunOnboarding"/>`. Стиль повторяет `StepSkipLink` мастера (`OnboardingWindow.xaml:29-32`), отдельного стиля не заводим.
- `HotkeySettingsWindow.xaml.cs`: свойство `internal bool OnboardingRequested { get; private set; }` и обработчик `private void OnRunOnboarding(object sender, MouseButtonEventArgs e) { OnboardingRequested = true; DialogResult = false; }`. `DialogResult = false`, а не `true`: несохранённые правки диалога отбрасываются, и `Closed`-обработчик (`:369`) при `Result is null` вернёт тему, с которой окно открылось. Мастер дальше читает файл с диска и получает согласованное состояние.
- `EdgeStackWindow.xaml.cs`, `OpenSettings()`, после `:1336` (`saved = dialog.ShowDialog()`): `if (dialog.OnboardingRequested) ShowOnboarding();`. Внутри `try`, чтобы `finally` (`:1339-1343`) перерегистрировал клавиши один раз в конце.

Текущие значения в мастере. Отдельной передачи не нужно, конструктор `OnboardingWindow` уже берёт всё из `HotkeySettings`, который `ShowOnboarding` читает с диска (`:1197`): язык (`:59`, `SuggestedLanguage`), клавиша (`:61`), тема и акцент (`:71-72`), автозапуск из реестра (`:77`, `LoadStartupState`). `OnboardingVersion` в файле уже равен `CurrentVersion`, на открытие это не влияет, `Candidate` (`:296`) всё равно проставляет его заново.

Что делает «Пропустить». `OnSkip` (`:385`) → `SkipSetup` (`:401`) → возврат темы и акцента и `Apply(_appliedCaptureId)`. Чтобы выполнялось «ничего не трогает», нужны две правки:

1. **Тема сохраняется при «Начать».** `EdgeStackWindow.WriteOnboarding` (`:1246-1254`), в ветку `merge` добавить `Theme = candidate.Theme, AccentId = candidate.AccentId`. Без этого E2 не работает вообще (расхождение 8).
2. **Язык не сохраняется при «Пропустить».** В `OnboardingWindow` завести `private readonly string _openedLanguage` рядом с `_openedTheme`/`_openedAccent` (`:30-31`), заполнять в конструкторе после `:59`, и в `SkipSetup` (`:401-414`) перед `Apply(_appliedCaptureId)` вызывать `if (_language != _openedLanguage) ApplyLanguage(_openedLanguage);`. Тогда `Candidate` унесёт язык, с которым мастер открылся.

Про пункт 2 есть развилка на первом запуске: там `_openedLanguage` это догадка по локали, и возврат к ней при «Пропустить» правильный (сейчас записывается то же самое значение, поведение не меняется). Отдельный флаг «мастер открыт повторно» не нужен.

Строки RU/EN, добавить в `UiLanguage.cs`: `["Пройти знакомство заново"] = "Take the tour again"`.

Дубля в меню трея не делаем, там остаётся «Как пользоваться» (`EdgeStackWindow.xaml.cs:159`).

Smoke:

- `HotkeySettingsWindow` probe (`:544` и далее): проверить, что `OnRunOnboarding` ставит `OnboardingRequested = true`, `DialogResult` в `false` и `Result` остаётся `null`.
- Новый чистый тест на `WriteOnboarding`-слияние сделать нечем (метод приватный и ходит в файл), поэтому проверка в `SmokeTestRunner` там же, где уже гоняется цикл сохранения настроек (`:40-46`): записать `HotkeySettings` с темой `sea`, прочитать назад, убедиться, что `Theme`/`AccentId` дожили. Если такой проверки в блоке нет, добавить.
- Проверка пары строк: добавить `("Пройти знакомство заново", "Take the tour again")` в список `SmokeTestRunner.cs:336-354`.

Риски. Ссылка «Пройти знакомство заново» отбрасывает несохранённые правки диалога без предупреждения. Считаю это приемлемым (ссылка внизу вкладки, не кнопка рядом с «Сохранить»), но это решение, а не данность.

---

## Файлы

Меняет дорожка A:

| Файл | Пункты |
|---|---|
| `src/SnapBrief.App/DwmWindowCorners.cs` (новый) | A1, A3 |
| `src/SnapBrief.App/OnboardingWindow.xaml` | A1, A2 |
| `src/SnapBrief.App/OnboardingWindow.xaml.cs` | A1, A2, A3, E2 |
| `src/SnapBrief.App/Controls/AppearancePicker.xaml` | A4 |
| `src/SnapBrief.App/Controls/AppearancePicker.xaml.cs` | A4, A5 |
| `src/SnapBrief.App/Controls/HowToSlides.xaml` | A6 |
| `src/SnapBrief.App/Controls/HowToSlides.xaml.cs` | A6 (smoke) |
| `src/SnapBrief.App/HotkeySettingsWindow.xaml` | E2 |
| `src/SnapBrief.App/HotkeySettingsWindow.xaml.cs` | E2 |

Общие файлы, конфликты слияния:

- `UiLanguage.cs`: A строки `Светлая · Рассвет`, `розовый`, `бирюзовый`, `розово-фиолетовый`, `бирюзово-синий`, `Пройти знакомство заново`. B убирает `Светлая` вместе с темой `light`. C и D свои строки. Разные строки одного словаря, конфликт текстовый, разводится вручную.
- `SmokeTestRunner.cs`: A правки в блоке мастера (`:287-326`), новые пары строк (`:336-354`), арифметика `UsefulHeight`. B проверки акцентов и тем (`:173-222`). C лента. Конфликтуют почти наверняка.
- `AppearancePicker.xaml.cs` и `RunProbe` в нём: A ведёт контрол, но `RunProbe` (`:330-400`) проверяет и число тем, и число акцентов, то есть данные B. Договорённость: файл ведёт A, B присылает точные ожидания счётчиков и сам их не правит.
- `EdgeStackWindow.xaml.cs`: A трогает `OnLoaded` (`:194-228`), `ShowOnboarding` (`:1172`), `WriteOnboarding` (`:1246`), `OpenSettings` (`:1272`). C трогает всё остальное в этом файле. Сливать A после C.
- `ThemeService.cs`: A не трогает.
- `App.xaml.cs`: A не трогает. `ShowExistingMainWindow` (`:80-84`) уже зовёт `RevealStack()`, для A7 этого достаточно.

---

## Общий фундамент до параллельной работы

Один файл, один коммит, до того как дорожки разойдутся:

**`src/SnapBrief.App/DwmWindowCorners.cs`** с двумя статическими классами: `DwmWindowCorners.Round(IntPtr hwnd) : bool` (A1) и `MonitorMetrics.Scale(int x, int y) : double` (A3). Оба чистый P/Invoke без зависимостей от остального кода.

Хотя A1 сейчас применяется только к мастеру (окно настроек layered, см. расхождение 1), помещать вызов прямо в `OnboardingWindow` не стоит: B3 «настоящее стекло» отдельным раундом снимет `AllowsTransparency` у ленты, капсулы, редактора и настроек, и все четыре окна придут за тем же вызовом. Файл заводится сразу, чтобы потом не переносить.

Больше ничего фундаментального дорожке A не нужно: A7 обходится существующим `ShowStackWithoutActivation()`, A4 и A5 живут внутри `AppearancePicker`, A6 внутри `HowToSlides`.

Порядок слияния: фундамент → B (словари тем и акцентов, `ThemeService`) → A (галерея и ряд опираются на список B) → C (лента) → A7 поверх C.

---

## Перенос на macOS

Имеет смысл перенести:

- **Мастер целиком**: пять шагов, фиксированная высота блока подписей на шаге 5 (A6), поведение «после Начать показать ленту» (A7). Логика раскладки от платформы не зависит.
- **Галерея тем на 6 карточек** (A4): прокрутка по одной карточке, гашение стрелок на концах, открытие на первой карточке. Колесо и горизонтальный жест на Mac приходят обычным `scrollWheel` с `deltaX`/`deltaY` в одном событии, `WM_MOUSEHWHEEL` не нужен, `NSScrollView` листает горизонтально сам.
- **Ряд из 12 акцентов** (A5): разделитель по признаку «кисть не сплошная», ширина 455, шаг 10.
- **«Пройти знакомство заново»** (E2) и обе правки под ним: сохранение темы при «Начать» и невмешательство «Пропустить» в язык. Это логика настроек, не платформа.
- Новые строки `UiLanguage.cs`: таблица переносится один в один (`AGENTS.md`, правило 3).

Не переносится:

- **A1 целиком**: `DwmSetWindowAttribute`, `DWMWA_WINDOW_CORNER_PREFERENCE`, ветка Windows 10. На macOS скругление и тень даёт сама система для `NSWindow` с `titlebarAppearsTransparent`, рисовать внутренний контур не нужно и сейчас.
- **A2 целиком**: `WindowChrome`, `CaptionHeight`, `IsHitTestVisibleInChrome`, `UseAeroCaptionButtons`. Эквивалент на Mac это стандартный titlebar плюс `isMovableByWindowBackground`, отдельная задача порта, не перенос этого диффа.
- **A3**: `GetDpiForMonitor`, `SetWindowPos`, `WM_DPICHANGED`. У macOS backing scale и `NSScreen.visibleFrame` в точках, смешанного DPI в этом виде нет; переносится только требование «окно открывается на экране под курсором и не выше его рабочей области».
