# Волна 1, дорожка B (ТЗ №5): лента

База: коммит волны 0 `b589fd8`, ветка `tz-006-B`, worktree `…/snapbrief-wt/B`. План: `tasks/tz-006-plan.md`
§2 (решения 2, 3, 4, 5, 10, 12), §4 «Волна 1, дорожка B», §5; разбор `tasks/tz-006-details/B-strip.md`.
Прогон по требованию Никиты один на всю дорожку: `scripts/build.ps1 -OutputDirectory
$env:LOCALAPPDATA\Temp\snapik-candidate-B`. Промежуточно — `dotnet build Snapik.slnx` и прямые запуски
`Snapik.exe --smoke-test` (проба B-1 обязана была ответить до B-7).

## Что сделано

| # | Что | Коммит |
|---|---|---|
| B-1 | Смоук-проба `VerifyALayeredWindowMinimisesAsync` в `SmokeTestRunner.cs`: окно с теми же `WindowStyle`/`ResizeMode`/`AllowsTransparency`/`SizeToContent`/`ShowActivated`/`ShowInTaskbar`, что у ленты | `44b0f0f` |
| B-2 | Из триггеров `IsMouseOver` и `IsKeyboardFocusWithin` ушли сеттеры `Margin`, триггер `IsSelected` удалён целиком | `74fdbf6` |
| B-3 | `ApplyListHeight()`; `PositionAtEdge` разделён на `PlaceStripInitially()` (из `OnLoaded`) и `EnsureStripPlaced()` (из `ShowStackWithoutActivation`); `ListBox` перешаблонен в голый `ScrollViewer`, шаблон вьюера уехал в `Window.Resources` как `StackScrollViewer`; `Padding="4,14,12,8"`, `ItemsPanel` с `Margin="0,0,0,48"`; доводчик в `OnCornerDragCompleted`; смоук-проба на настоящем `EdgeStackWindow` | `5f2dc23` |
| B-4 | `MinWidth`/`MinHeight` = 0 у `StackScrollBar` и `MinWidth="0"` на полосе; 3 px в покое, 6 по наведению через `BarField`; `Opacity` анимацией, таймер на 1 с; тень карточки `BlurRadius` 16 → 12; проверка `ActualWidth <= 6` на двенадцати карточках | `6696861` |
| B-5 | `ClipToBounds` снят, на внутреннем `Grid` карточки `controls:RoundedClip.Radius="10"` | `539c6ec` |
| B-6 | `_expandedLeft`; `PositionCapsuleAtEdge` → `PositionCapsuleAtStrip` (`CapsuleLeft`); `ExpandFromCapsule` по фиксированному порядку с одним `PlaceWindow(RestoreRect(…))`; `ShowStackWithoutActivation` капсулу не двигает | `3c2ebba` |
| B-7 | `ShowInTaskbar="True"` и `ResizeMode="CanMinimize"` статикой; `OnHideClick` → `WindowState.Minimized`; `SW_SHOWNOACTIVATE` перед `Show()`; лента показывается на старте всегда; `OnClosing` остался `Hide()` | `c92df5d` |

## Проба B-1: зелёная

Layered-окно (`AllowsTransparency="True"`) с `SizeToContent="Height"` и `ResizeMode="CanMinimize"`:

1. `GetWindowLong(GWL_STYLE)` несёт `WS_MINIMIZEBOX` — то есть кнопка панели задач свернёт активную ленту;
2. `WindowState = Minimized` проходит без исключения и состояние держится;
3. `ShowWindow(SW_SHOWNOACTIVATE)` возвращает окно на те же `Left`/`Top` и с той же `ActualHeight`,
   `WindowState` снова `Normal`, лишнего прохода `SizeToContent` не видно.

Запасной ход (`SetWindowPos` из сохранённого прямоугольника) **не понадобился**, B-7 сделан по плану.
Проверено на основном мониторе при 100 %; на 125 % и на втором мониторе — живьём.

## Отступления от плана

- **`if (wizardShown)` в `OnLoaded` убран, а не дополнен ветвью `else`.** По решению 5 лента показывается
  на старте в обоих случаях, то есть обе ветви гейта стали бы одинаковыми, а `wizardShown` — переменной,
  которую никто не читает (`TreatWarningsAsErrors` на такую ругается). Осталась одна строка
  `ShowStackWithoutActivation()` там же, где стояла прежняя, то есть после мастера и после восстановления
  сессии; порядок, ради которого гейт и существовал, сохранён и записан комментарием.
- **`HideStack()` удалён.** После B-7 его единственный вызывающий (`OnHideClick`) сворачивает окно, а
  `HideForCapture` прячет окна сам, не через `HideStack` (план говорит обратное — в коде `HideForCapture`
  обходит `Application.Current.Windows` и зовёт `Hide()` у каждого). Приватный метод без вызывающих —
  мусор, убран тем же коммитом. `HideToastNow()` из него переехал в `OnHideClick`.
- **`ExpandFromCapsule` сохранил строку `CaptureList.Height = ListHeightForCount(Captures.Count,
  _expandedListHeight)`** (как в `B §B5.3`), хотя §4 плана перечисляет только `UpdateEmptyState()`. Без неё
  потолок при развороте брался бы из настроек, а не из того, что было у ленты до капсулы, и поле
  `_expandedListHeight` осталось бы без читателей. Фиксированный порядок плана не нарушен: строка стоит
  между `Width` и `UpdateLayout()`.
- **Наведение на поле полосы зажигает её анимацией** (`FadeStripScrollBar(1, 90)` в `MouseEnter`), а не
  только останавливает таймер. Сеттера `Opacity` в триггере по-прежнему нет, спорить анимации не с чем:
  триггер держит только ширину 3 → 6. Без этого наведение на уже погасшую полосу не показывало бы ничего.
- **Смоук-пробы держат приложение живым.** `ShutdownMode` по умолчанию `OnLastWindowClose`, и закрытие
  окна пробы (и в B-1, и в пробе ленты) завершало смоук-процесс досрочно: код выхода 0, а
  `smoke-test-result.json` не появлялся. Обе пробы на время своей работы ставят
  `ShutdownMode.OnExplicitShutdown` и возвращают прежний. Это же ждёт любую дорожку, которая покажет окно.
- **Проба ленты поднимает по окну на случай.** Список, перезаполненный на месте (5 → 12), сохраняет старый
  `ExtentHeight` (198): контейнеры новых карточек в оторванном от `PresentationSource` дереве не
  пересобираются даже после `InvalidateMeasure` + `UpdateLayout`. Каждый случай меряется на своём
  `EdgeStackWindow`; сам список меряется и раскладывается напрямую (184 px — ширина окна без поля под тень
  и без паддинга панели), потому что у окна без хэндла разметки нет вовсе.
- **Пара `["Свернуть в трей"] = "Hide to tray"` в `UiLanguage.cs` осталась без потребителей** (кнопка
  шапки теперь «Свернуть»). `UiLanguage.cs` в волне 1 закрыт, пара не тронута — снять её волне 2, если
  она никому не понадобится.

## Что проверять живьём (автоматикой не покрыто)

1. Полоса: в покое её нет, при колесе 3 px, гаснет через секунду, по наведению 6 px и тянется; второй,
   тусклой полосы нет (авто держит только `ActualWidth <= 6`).
2. Рост списка: 2 → 130, 5 → 220 (без прокрутки), 12 → 372; окно идёт за списком без рывка при удалении и
   восстановлении снимка.
3. Доводчик ручки угла: пока тянешь — список идёт за рукой, отпустил — сел на высоту содержимого, потолок
   остался натянутым (решение 2, Кате отдельной строкой).
4. Капсула у границы двух мониторов: встаёт на правый верхний угол ленты, разворот возвращает ленту в те
   же `Left`/`Top`, монитор не меняется; и то же для ленты, оттащенной от края.
5. Клик по иконке панели задач: первый показывает, второй сворачивает совсем, клавиша снимка возвращает
   ленту без кражи фокуса.
6. Линия под иконкой с первой секунды запуска — и после мастера, и без него.
7. Скруглённые углы миниатюры (клип `RoundedClip` на экране ни разу не проверялся) и тень карточки с
   `BlurRadius="12"`.
8. Перетаскивание порядка карточек после смены правого паддинга на 12 и перешаблонивания списка.

## Изменение формата

Нет. `settings.json` и `session.json` дорожка B не трогает; `StackHeight` пишется как прежде, но читается
как потолок (это уже записано в `tz-006-notes-0.md`).
