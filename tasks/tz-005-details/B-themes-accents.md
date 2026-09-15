# Дорожка B: темы и акценты (ТЗ №4, пункты B1, B2, B3, A5, E1)

База: `master` = `a2f72e1` (1.4.0). Все `file:line` по этому коммиту. Код не менялся, это разбор.

Входы: `tasks/handoff-005/TZ-004-v140-test.md` (побеждает при расхождении), эталоны `reference-html/01-step4-v2.html`, `02-themes-applied.html`, `03-glass-gradients-A-B-C.html`, `reference-png/01`, `02`, `03`, контракт волны 0 (`tasks/tz-004-plan.md`, раздел 3), формат разбора по `tasks/tz-004-details/B-appearance-settings.md`.

Зона: словари `Themes/Palettes/*`, `Themes/Accents/*`, `ThemeService.cs`, строки тем и акцентов в `UiLanguage.cs`, все smoke-проверки тем и акцентов в `SmokeTestRunner.cs`. UI ряда акцентов и галереи в `AppearancePicker` разбирает аналитик A; редактор цвета (D1) — аналитик D.

---

## 1. Где ТЗ не сходится с кодом

1. **Значения пяти тем из таблицы B1 уже стоят в коде.** `dark`, `night`, `sunset`, `sea`, `dawn` совпадают с таблицей побайтно: `Dark.xaml:9-24` (`#F2171A20` = `#171A20` 95 %, линия `#46505E`, карточка `#242A33`, текст `#EEF2F8`), `Night.xaml:9-25` (`#1F2A4A → #2A1F4A`, линия `#408C96FF` = 25 %, карточка `#14FFFFFF` = 8 %), `Sunset.xaml:9-25`, `Sea.xaml:9-25`, `Dawn.xaml:9-25` (`#FFF4EC → #F1ECFF`, линия `#14000000` = 8 %, карточка `#FFFFFF`, текст `#172033`). Угол 160° уже выражен как `StartPoint="0,0" EndPoint="0.35,1"`. **Реальная работа B1 — удалить `Light.xaml`, вынуть `light` из списка, переподписать карточку и мигрировать настройки; перекрашивать нечего.**
2. **Эталоны 02 и 03 расходятся по «Стеклу».** В `02-themes-applied.html` панель «Стекло» — старая матовая `rgba(118,126,146,0.66)` с `backdrop-filter: blur(44px)`; градиент B есть только в `03-glass-gradients-A-B-C.html`. Побеждает текст B2 и эталон 03.
3. **`ElevatedBrush` «Стекла»: 10 % в B2 и в эталоне 03, 14 % в эталоне 02.** 14 % — это значение `HoverBrush` из того же списка B2. Берём B2: `ElevatedBrush` 10 %, `HoverBrush` 14 %.
4. **B1 обещает, что `Backdrop` (`AppearancePicker.xaml.cs:213-222`) остаётся «без изменений».** Не выйдет: `:215` — `"light" or "dawn" =>`, ветку надо сократить до `"dawn"`. Рисунок карточки при этом действительно не меняется.
5. **A5 ссылается на волну 0: «`AccentColor` у градиентных акцентов тоже равен первому стопу, его кастуют в `Color` в `HotkeySettingsWindow.xaml.cs:324`».** На HEAD `AccentColor` снаружи словарей акцента **никто не читает** (grep по `src` без `Themes/Accents` пуст): кружки акцента переехали в `AppearancePicker`, рендереры ходят через `AccentPalette.Flat` (`AccentPalette.cs:26-27`, ключ `AccentFlatColor`). Ключ всё равно обязан быть во всех словарях — его держит проверка совпадения наборов ключей (`SmokeTestRunner.cs:184-188`), — но причина в ТЗ устарела.
6. **Разделитель ряда акцентов.** A5 говорит «ставится перед `blue-violet`, `AppearancePicker.xaml.cs:187-189`». Точнее: комментарий `:187`, само условие `:188` (`if (accent == "blue-violet")`), `Divider()` — `:201-206`.
7. **E1 называет клавишу «Снимок всего экрана», в коде её нет.** Текущая строка — `"Скриншот всего экрана в папку"`: `UiLanguage.cs:47`, `HotkeySettingsWindow.xaml:43` (`Content`), `:44` (`AutomationProperties.Name`), плюс пара в языковой таблице smoke `SmokeTestRunner.cs:339`. Четыре места, не одно.
8. **Комментарии про «семь палитр» и «четыре из восьми акцентов» устаревают вместе с правкой.** `SmokeTestRunner.cs:174`, `:841`, шапка каждого из шести оставшихся `Themes/Palettes/*.xaml:4`, комментарий галереи `AppearancePicker.xaml:82`, комментарий и текст исключения `AppearancePicker.xaml.cs:359-362` («Seven cards of 132 must not fit into 520»). Проверка переживает шесть карточек (6 × 142 > 520), врёт только сообщение.

---

## 2. B1. Шесть тем

### 2.1. Что лежит на HEAD

Семь словарей, по 14 ключей в каждом, порядок галереи задаёт `ThemeService.Themes` (`ThemeService.cs:19`):

| id | файл | вид `SurfaceBrush` | в 1.5.0 |
|---|---|---|---|
| `dark` | `Themes/Palettes/Dark.xaml` | `SolidColorBrush` | без изменений |
| `light` | `Themes/Palettes/Light.xaml` | `SolidColorBrush` | **удалить файл** |
| `glass` | `Themes/Palettes/Glass.xaml` | `SolidColorBrush` | переписать целиком, см. §3 |
| `night` | `Themes/Palettes/Night.xaml` | `LinearGradientBrush` | без изменений |
| `sunset` | `Themes/Palettes/Sunset.xaml` | `LinearGradientBrush` | без изменений |
| `sea` | `Themes/Palettes/Sea.xaml` | `LinearGradientBrush` | без изменений |
| `dawn` | `Themes/Palettes/Dawn.xaml` | `LinearGradientBrush` | подпись карточки |

Ключи (одинаковые во всех семи): `SurfaceBrush`, `SurfaceBarBrush`, `SurfaceLineBrush`, `ElevatedBrush`, `ElevatedLineBrush`, `HoverBrush`, `PressedBrush`, `DividerBrush`, `TextBrush`, `TextMutedBrush`, `TextFaintBrush`, `ShadowColor`, `ShadowOpacity`, `DangerBrush`.

`Page`-элементы WPF подхватываются SDK по умолчанию (в `Snapik.App.csproj` нет ни одного явного `<Page Include>` для палитр, `:32` только исключает `MainWindow.xaml`), поэтому удаление `Light.xaml` — это удаление файла, csproj не трогается.

### 2.2. Полная таблица значений шести тем

Все значения уже в коде, кроме столбца `glass` (§3). «Предложено» — там, где эталона нет и значение сохраняется как есть.

| ключ | dark | night | sunset | sea | dawn |
|---|---|---|---|---|---|
| `SurfaceBrush` | `#F2171A20` | град. `#1F2A4A → #2A1F4A` | град. `#3D2436 → #4A2A22` | град. `#163A44 → #1B3A2C` | град. `#FFF4EC → #F1ECFF` |
| `SurfaceBarBrush` | `#F2171A20` | тот же, `0,0 → 1,0` | тот же, `0,0 → 1,0` | тот же, `0,0 → 1,0` | тот же, `0,0 → 1,0` |
| `SurfaceLineBrush` | `#46505E` | `#408C96FF` | `#40FFA078` | `#4050DCC8` | `#14000000` |
| `ElevatedBrush` | `#242A33` | `#14FFFFFF` | `#14FFFFFF` | `#14FFFFFF` | `#FFFFFF` |
| `ElevatedLineBrush` | `#46505E` | `#408C96FF` | `#40FFA078` | `#4050DCC8` | `#E3E7ED` |
| `HoverBrush` | `#2A3240` | `#1FFFFFFF` | `#1FFFFFFF` | `#1FFFFFFF` | `#0D000000` |
| `PressedBrush` | `#20262F` | `#2EFFFFFF` | `#2EFFFFFF` | `#2EFFFFFF` | `#17000000` |
| `DividerBrush` | `#3A424E` | `#4D8C96FF` | `#4DFFA078` | `#4D50DCC8` | `#14000000` |
| `TextBrush` | `#EEF2F8` | `#EEF2F8` | `#EEF2F8` | `#EEF2F8` | `#172033` |
| `TextMutedBrush` | `#8F9AAA` | `#C6CEDA` | `#C6CEDA` | `#C6CEDA` | `#5E687A` |
| `TextFaintBrush` | `#6F7A8A` | `#A9B4C2` | `#A9B4C2` | `#A9B4C2` | `#8A93A3` |
| `ShadowColor` | `#000000` | `#000000` | `#000000` | `#000000` | `#000000` |
| `ShadowOpacity` | `0.4` | `0.45` | `0.45` | `0.45` | `0.15` |
| `DangerBrush` | `#FF6B6B` | `#FF6B6B` | `#FF6B6B` | `#FF6B6B` | `#B42318` |

Сверка с эталоном `02-themes-applied.html` (панели по темам): `dark` панель `rgba(23,26,32,0.95)` / линия `#46505E` / чип `#242A33` / текст чипа `#8F9AAA`; `night` `linear-gradient(160deg,#1F2A4A,#2A1F4A)` / `rgba(140,150,255,0.25)` / `rgba(255,255,255,0.08)` / `#C6CEDA`; `sunset` `#3D2436→#4A2A22` / `rgba(255,160,120,0.25)`; `sea` `#163A44→#1B3A2C` / `rgba(80,220,200,0.25)`; `dawn` `#FFF4EC→#F1ECFF` / `rgba(0,0,0,0.08)` / чип `#FFFFFF` / `#5E687A`. Тень панели везде `rgba(0,0,0,.32)`; это не токен, а `BlurRadius`/`ShadowDepth` в разметке, `ShadowOpacity` остаётся как в коде — **предложено**.

`HoverBrush`, `PressedBrush`, `ElevatedLineBrush`, `TextFaintBrush`, `DangerBrush` в эталоне 02 не показаны (миниатюры снимков внутри панели нарисованы одним набором `#242A33` / `#46505E` / `#E9EDF2` во всех шести темах и токенами темы не являются) — **предложено: оставить как в коде**.

### 2.3. Карточка «Светлая · Рассвет»

Подпись строится из `ThemeNames` (`AppearancePicker.xaml.cs:29-33`): `["dawn"] = "Рассвет"` → `"Светлая · Рассвет"`, строку `["light"] = "Светлая"` из словаря убрать. Пара в `UiLanguage.cs:40` (`["Светлая"] = "Light"`) заменяется на `["Светлая · Рассвет"] = "Light · Dawn"`, старая `["Рассвет"] = "Dawn"` (`:41`) остаётся без потребителя — удалить.

### 2.4. Миграция `light → dark`

Куда бьёт старое значение:

- `EdgeStackWindow.xaml.cs:100` — `ThemeService.Apply(_settings.Theme, _settings.AccentId)` на старте; `Apply` → `NormalizeTheme` (`ThemeService.cs:46, 61-62`) и `LoadTheme` (`:35`).
- `HotkeySettingsWindow.xaml.cs:354` — `ThemeService.NormalizeTheme(settings.Theme)`.
- `OnboardingWindow.xaml.cs:69, 71` — `_openedTheme = settings.Theme` сырым, дальше `Appearance.SelectedTheme = settings.Theme`; сеттер нормализует (`AppearancePicker.xaml.cs:69`), возврат при «Пропустить» (`OnboardingWindow.xaml.cs:411`) идёт через `Apply` и тоже нормализуется.

**Вариант А (ничего не делать).** Как только `light` уходит из `Themes` (`ThemeService.cs:19`), `NormalizeTheme` гасит его в `DefaultTheme = "dark"` (`:17, 61-62`) во всех трёх точках. В `settings.json` строка `"Theme": "light"` остаётся до первого сохранения, потом `OnSave` пишет уже нормализованное `SelectedTheme` (`HotkeySettingsWindow.xaml.cs:525`). Правок нуль, формат не трогается.

**Вариант Б (явная миграция).** `SettingsMigration` (`SettingsMigration.cs`) + `HotkeySettings.Migrate` (`HotkeySettingsWindow.xaml.cs:114-121`): новое правило `Theme(int storedVersion, string storedTheme) => storedVersion < 2 && storedTheme == "light" ? "dark" : storedTheme`, `CurrentVersion = 2`. `LoadAndMigrate` (`:187-196`) запишет файл обратно один раз.

**Ловушка варианта Б.** Правило громкости привязано не к своему порогу, а к общему: `SoundVolume` (`SettingsMigration.cs:23-24`) спрашивает `NeedsMigration(storedVersion)`, то есть `storedVersion < CurrentVersion`. Поднять `CurrentVersion` до 2 — значит второй раз прогнать правило громкости по файлам версии 1 и молча увести на 40 тех, кто после первой миграции сам выставил 60. Перед добавлением темы каждое правило обязано проверять свой порог: `SoundVolume` → `storedVersion < 1`, `Theme` → `storedVersion < 2`.

Смена `SettingsVersion` — изменение формата, значит абзац «Изменение формата» в `tasks/verification.md` (AGENTS.md, правило 4) и синхронная правка Mac-порта.

**Рекомендация:** вариант Б — он чинит заодно порог правила громкости и оставляет в файле то, что на экране. Вариант А допустим, если раунд не хочет трогать `SettingsVersion`.

**Тест.** Только для варианта Б и только юнит-тест в `tests/Snapik.App.Imaging.Tests/SettingsMigrationTests.cs` (файл линкуется исходником, WPF не нужен): `light` при версии 0 и 1 → `dark`; `sea` не трогается; `light` при версии 2 не трогается; и отдельно — громкость 60 при версии 1 остаётся 60. Вариант А тестировать нечем: поведение уже покрыто smoke `SmokeTestRunner.cs:206-208` («тема, на которую ничто не отзывается, гаснет в тёмную»).

### 2.5. Где ещё в коде `light` и список тем по имени

| место | что там | правка |
|---|---|---|
| `ThemeService.cs:19` | `["dark", "light", "glass", …]` | убрать `"light"` |
| `AppearancePicker.xaml.cs:31` | `["light"] = "Светлая"` в `ThemeNames` | убрать; `["dawn"]` → `"Светлая · Рассвет"` |
| `AppearancePicker.xaml.cs:215` | `"light" or "dawn" =>` в `Backdrop` | `"dawn" =>` |
| `UiLanguage.cs:40-41` | `["Светлая"]`, `["Рассвет"]` | заменить на `["Светлая · Рассвет"]` |
| `Themes/Palettes/Light.xaml` | весь файл | удалить |
| `Themes/Palettes/*.xaml:4` (6 файлов) | «One of the seven palettes» | шесть |
| `SmokeTestRunner.cs:841` | «under all seven palettes» | шесть |
| `AppearancePicker.xaml:82`, `.xaml.cs:359-362` | «seven cards of 132» | шесть |

`HowToSlides.xaml` / `.xaml.cs` тем по имени не знают (grep по `dark|light|glass|night|sunset|sea|dawn` пуст) — слайды красятся токенами. В `tests/` тем и акцентов нет вообще (grep по трём тест-проектам пуст), вся проверка живёт в smoke.

---

## 3. B2. «Стекло» = матовый градиент B

### 3.1. Словарь целиком

`Themes/Palettes/Glass.xaml`, все 14 ключей.

```xml
<LinearGradientBrush x:Key="SurfaceBrush" StartPoint="0,0" EndPoint="0.6,1">
    <GradientStop Offset="0"    Color="#5F5C8C" />
    <GradientStop Offset="0.55" Color="#7E5878" />
    <GradientStop Offset="1"    Color="#58627A" />
</LinearGradientBrush>
<LinearGradientBrush x:Key="SurfaceBarBrush" StartPoint="0,0" EndPoint="1,0">
    <GradientStop Offset="0"    Color="#5F5C8C" />
    <GradientStop Offset="0.55" Color="#7E5878" />
    <GradientStop Offset="1"    Color="#58627A" />
</LinearGradientBrush>
```

| ключ | было (`Glass.xaml`) | стало | источник |
|---|---|---|---|
| `SurfaceBrush` | `#8C3C4254` (`:9`) | градиент выше | B2, `03…html` (`linear-gradient(150deg,#5F5C8C 0%,#7E5878 55%,#58627A 100%)`) |
| `SurfaceBarBrush` | `#8C3C4254` (`:10`) | тот же градиент, `0,0 → 1,0` | B2 |
| `SurfaceLineBrush` | `#38FFFFFF` (`:11`) | `#38FFFFFF` (22 %) | без изменений, эталон 03 `rgba(255,255,255,0.22)` |
| `ElevatedBrush` | `#24FFFFFF` (`:12`) | `#1AFFFFFF` (10 %) | B2, эталон 03 `rgba(255,255,255,0.10)` |
| `ElevatedLineBrush` | `#38FFFFFF` (`:13`) | `#38FFFFFF` (22 %) | без изменений |
| `HoverBrush` | `#1FFFFFFF` (`:14`) | `#24FFFFFF` (14 %) | B2 |
| `PressedBrush` | `#33FFFFFF` (`:15`) | `#33FFFFFF` (20 %) | без изменений |
| `DividerBrush` | `#40FFFFFF` (`:16`) | `#3DFFFFFF` (24 %) | B2 |
| `TextBrush` | `#EEF2F8` (`:17`) | `#EEF2F8` | без изменений |
| `TextMutedBrush` | `#C6CEDA` (`:18`) | `#DDD6E6` | B2, эталон 03 |
| `TextFaintBrush` | `#A9B4C2` (`:19`) | `#C5BFD3` | B2 |
| `ShadowColor` | `#000000` (`:20`) | `#000000` | без изменений |
| `ShadowOpacity` | `0.3` (`:21`) | `0.35` | B2 |
| `DangerBrush` | `#FF6B6B` (`:22`) | `#FF6B6B` | **предложено** (в B2 не назван) |

Угол: CSS `150deg` → вектор `(sin150, −cos150) = (0.5, 0.866)`, отношение `0.577` ≈ `EndPoint="0.6,1"` из ТЗ. Остальные градиентные темы держат 160° как `0.35,1` — то же правило, другой угол.

`SurfaceBarBrush` горизонтально: три стопа те же, `StartPoint="0,0" EndPoint="1,0"`, ровно как у `Night` / `Sunset` / `Sea` / `Dawn` (`Night.xaml:13-16`), только стопов три вместо двух. Единственный потребитель — панель редактора `OverlayEditorWindow.xaml:192`. Эталона для горизонтальной полосы нет — **предложено по аналогии**.

Комментарий шапки (`Glass.xaml:8`) сейчас говорит «translucent grey panel… real acrylic is a separate step» — переписать под градиент B и сослаться на B3.

### 3.2. Где градиентный `SurfaceBrush` может упасть

Проверено grep'ом `as SolidColorBrush`, `(SolidColorBrush)`, `.Color` по ресурсам темы, `Resources[` и `FindResource(` по `src`:

- **Кастов ресурсов темы в `SolidColorBrush` нет ни одного.** Единственное вхождение `(SolidColorBrush)` во всём `src` — `OverlayEditorWindow.xaml.cs:364`, и это `window.ColorSwatch.Fill` (цвет отметки, не токен темы).
- **`.Color` ни на одном браше темы не читается.** `AccentPalette.cs:26-27` берёт `AccentFlatColor`, это `Color`, а не браш, и к теме отношения не имеет.
- `AppearancePicker.xaml.cs:163` — `palette["SurfaceBrush"] as Brush` через `Frozen` (`:226-231`, `CloneCurrentValue()`), градиент переживает.
- `AppearancePicker.xaml.cs:356` (`RunProbe`) — `is not LinearGradientBrush` после применения `sea`; от смены «Стекла» не зависит.
- `SmokeTestRunner.cs:201-205` — то же для `sea`. `:207` — `is not SolidColorBrush` после `Apply("nothing-like-a-theme")`, то есть по фолбэку `dark`, который остаётся сплошным. Обе живут.
- `SmokeTestRunner.cs:866-882` — тень оболочки ленты через `XamlReader.Parse`; `:876` сравнивает `shell.Background` с ресурсом по ссылке, `:881` требует `LinearGradientBrush` после цикла, заканчивающегося на `sea`. Живёт.
- **Экспорт PNG** (`FileExportService.cs`, `Snapik.Core`) токенов темы не читает вообще — grep по `Surface|Elevated|Shadow` пуст. Рендер берёт только акцент через `AccentPalette`. Падать нечему.

Что поменяется по виду, а не упадёт:

- **Капсула** `EdgeStackWindow.xaml:337-338` красится `SurfaceBrush` и имеет 44 px по высоте против ~420 у ленты. `LinearGradientBrush` в WPF относителен границам элемента (`MappingMode="RelativeToBoundingBox"` по умолчанию), поэтому в капсуле уместится весь трёхстоповый переход, а не его кусок. У `Night` / `Sea` / `Sunset` / `Dawn` это уже так с 1.4.0 — поведение не новое, но на «Стекле» разница заметнее: три стопа вместо двух. Проверять глазами по пункту 12 чек-листа F.
- **Поповеры редактора** (`OverlayEditorWindow.xaml:261, 282, 322, 354, 377, 401`) и тултипы (`EdgeStackWindow.xaml:67`) — то же самое, каждый со своим градиентом по своим границам.
- **`Window.Background`** через базовый стиль `Themes/SnapikTheme.xaml:13` и явно у `OnboardingWindow.xaml:3` — градиент по границам окна, как на `dawn` сегодня.
- **`ContextMenu`** `Themes/SnapikTheme.xaml:141` — то же.

Отдельно: **смоук не ловит подмену `SurfaceBrush` сплошным** ни в одной теме, кроме `sea` и фолбэка. Добавить проверку по §8.

---

## 4. B3. Настоящее стекло — зафиксировать на потом

Ничего не делать в этом раунде. Фиксируется как есть, чтобы не всплыло:

- Acrylic (`DwmSetWindowAttribute(DWMWA_SYSTEMBACKDROP_TYPE)`) требует снять `AllowsTransparency="True"` у ленты (`EdgeStackWindow.xaml:7`), настроек (`HotkeySettingsWindow.xaml:3`), `CaptureOverlay.xaml:4`, `DiscardSessionWindow.xaml:3`, `SavePackageWindow.xaml:3` (мастер `OnboardingWindow.xaml:3` уже `False`); скругление и тень уходят к DWM, а поля под тень зашиты в `Controls/StripResizeGeometry`. Интеропа `DwmSetWindowAttribute` в репозитории нет ни строки.
- Эталон, каким это должно быть: `reference-html/06-acrylic-later.html`.
- Условие: отдельный раунд после того, как C1–C7 устоялись. На Windows 10 размытия нет, нужен фолбэк на градиент B.
- Тема `glass` при этом остаётся обычной палитрой: acrylic — свойство окна, а не токен, и словарь §3 переживёт переход.

---

## 5. A5. Двенадцать акцентов

### 5.1. Что лежит на HEAD

Восемь словарей `Themes/Accents/{Blue,Teal,Violet,Coral,BlueViolet,OrangeRose,GreenCyan,AmberPink}.xaml`, по 8 ключей: `AccentColor`, `AccentFlatColor`, `AccentBrush`, `AccentHoverBrush`, `AccentPressedBrush`, `AccentSoftBrush`, `AccentTextBrush`, `FocusBrush`. Порядок — `ThemeService.Accents` (`ThemeService.cs:22-23`). Имя файла выводится из id (`ThemeService.cs:68-69`, `rose-violet` → `RoseViolet.xaml`).

Правила значений, по которым построены восемь существующих (проверено арифметикой на всех восьми):

- `AccentHoverBrush` = каждый стоп × 0.88, `AccentPressedBrush` = × 0.78 (округление к ближайшему).
- `AccentSoftBrush` = `#55` + первый стоп.
- `AccentTextBrush` = `FocusBrush`. У сплошных — акцент, сдвинутый на 37 % к белому; у градиентных — середина двух стопов, сдвинутая на 30 % к белому.
- `AccentColor` = `AccentFlatColor` = первый стоп. У градиентных `AccentBrush` — `LinearGradientBrush StartPoint="0,0" EndPoint="1,1"` (135°).

### 5.2. Четыре новых словаря

**`Themes/Accents/Rose.xaml`** (id `rose`, «розовый», `#FF5C8A`): `AccentColor` / `AccentFlatColor` `#FF5C8A`; `AccentBrush` — `SolidColorBrush Color="{StaticResource AccentColor}"`; `AccentHoverBrush` `#E05179`; `AccentPressedBrush` `#C7486C`; `AccentSoftBrush` `#55FF5C8A`; `AccentTextBrush` / `FocusBrush` `#FF98B5`.

**`Themes/Accents/Cyan.xaml`** (id `cyan`, «бирюзовый», `#22C1C3`): `#22C1C3`; hover `#1EAAAC`; pressed `#1B9798`; soft `#5522C1C3`; text / focus `#74D8D9`.

**`Themes/Accents/RoseViolet.xaml`** (id `rose-violet`, «розово-фиолетовый», `#FF5C8A → #AF81FF`): `AccentColor` / `AccentFlatColor` `#FF5C8A`; `AccentBrush` — градиент `0,0 → 1,1`, стопы `#FF5C8A` / `#AF81FF`; hover `#E05179` / `#9A72E0`; pressed `#C7486C` / `#8865C7`; soft `#55FF5C8A`; text / focus `#E39AD6`.

**`Themes/Accents/CyanBlue.xaml`** (id `cyan-blue`, «бирюзово-синий», `#22C1C3 → #2F8CFF`): `AccentColor` / `AccentFlatColor` `#22C1C3`; стопы `#22C1C3` / `#2F8CFF`; hover `#1EAAAC` / `#297BE0`; pressed `#1B9798` / `#256DC7`; soft `#5522C1C3`; text / focus `#69C1EA`.

`AccentColor`, стопы и `AccentFlatColor` — из таблицы A5 и `reference-html/01-step4-v2.html` (кружки 28 px, `linear-gradient(135deg, …)`). Hover, pressed, soft, text / focus — **предложено по правилам §5.1**, эталон их не показывает.

### 5.3. Порядок в `ThemeService`

`ThemeService.cs:22-23` — ровно порядок ряда из A5 и `reference-png/01`:

```
["blue", "teal", "violet", "coral", "rose", "cyan",
 "blue-violet", "orange-rose", "green-cyan", "amber-pink", "rose-violet", "cyan-blue"]
```

Комментарий `:20-21` («Four solid accents and four gradients») переписать на шесть и шесть.

### 5.4. Признак «градиентный» вместо имени

Сейчас разделитель ставится по строке: `AppearancePicker.xaml.cs:188` — `if (accent == "blue-violet")`. С новым порядком строка остаётся верной случайно, и при следующей перестановке ряда сломается молча.

Признак уже существует в самих данных: `AccentBrush` градиентного акцента — `GradientBrush`, сплошного — `SolidColorBrush`. Предложение: в `ThemeService`

```csharp
internal static bool IsGradientAccent(string? accentId) =>
    LoadAccent(accentId)["AccentBrush"] is GradientBrush;
```

и в `BuildAccentRow` (`AppearancePicker.xaml.cs:183-199`) разделитель ставится перед первым акцентом, у которого признак `true` (с флагом «уже поставлен», чтобы он был один). Словарь там и так загружается (`:193`), лишнего чтения не появляется.

Почему не поле в модели: `Accents` сегодня `IReadOnlyList<string>` и читается в пяти местах (`ThemeService.cs:65`, `AppearancePicker.xaml.cs:185, 339`, `SmokeTestRunner.cs:185, 215`); замена на запись ради одного булева поля тянет все пять и рискует разъехаться со словарём. Словарь — единственный источник истины, производный признак его не продублирует. Сам ряд (12 кружков 28 px, шаг 10, ширина 455 в 520) — зона аналитика A; отсюда только признак и порядок.

### 5.5. `AccentFlatColor`

По смыслу без изменений: у новых сплошных равен `AccentColor`, у новых градиентных — первый стоп. Читает его только `AccentPalette.Flat` (`AccentPalette.cs:26-27`), дальше `AccentPalette.Wash` (`:40-45`) и экспорт PNG. Ключ `AccentColor` держим во всех двенадцати словарях ради проверки совпадения наборов ключей (`SmokeTestRunner.cs:184-188`), даже при том, что снаружи его никто не читает (§1.5).

---

## 6. E1. Мелочи настроек

### 6.1. Название клавиши «Снимок всего экрана»

Текущий ключ — `"Скриншот всего экрана в папку"`:

| место | что |
|---|---|
| `UiLanguage.cs:47` | пара `["Скриншот всего экрана в папку"] = "Save the whole screen to a folder"` |
| `HotkeySettingsWindow.xaml:43` | `Content` галочки `FullscreenEnabledBox` (литерал, не `UiText`) |
| `HotkeySettingsWindow.xaml:44` | `AutomationProperties.Name="{local:UiText Скриншот всего экрана в папку}"` |
| `SmokeTestRunner.cs:339` | пара в языковой таблице smoke |

Новое: `["Снимок всего экрана"] = "Capture the whole screen"` — «в папку» уходит вместе с поведением (C8 кладёт снимок в ленту, а не в папку). Правятся все четыре места одной правкой; пару в smoke заменить, а не добавить, иначе таблица проверит несуществующую строку.

### 6.2. Сегмент палитры без «Своя»

Что это в настройках сейчас: `AppearancePicker.xaml:101-103` — три `RadioButton` `standard` / `pastel` / `custom`, подписи в `ApplyLanguage` (`AppearancePicker.xaml.cs:125-127`), разбор в сеттере `SelectedPalette` (`:96`), строка видна только при `ShowPaletteRow = true` (`:109-113`), то есть в настройках и не в мастере. Значение уезжает в `HotkeySettings.AnnotationPalette` (`HotkeySettingsWindow.xaml.cs:56, 358, 525`).

ТЗ (E1 + D1) требует, чтобы «Своя» перестала быть режимом, от которого зависят спектр и пипетка. Развилка из E1: либо убрать третий сегмент, либо оставить его как фильтр ряда.

**Формат не меняется ни в одном из вариантов.** `AnnotationPalette` остаётся строкой, `"custom"` остаётся допустимым значением (`OverlayEditorWindow.Appearance.cs:65, 74-76, 717` — `ParseAnnotationPalette` гасит неизвестное в `standard`), `CustomPaletteColors` живёт своей жизнью.

**Если сегмент убирают:** `AppearancePicker.xaml:103` и `AppearancePicker.xaml.cs:102, 127` уходят; `:96` становится `value is "pastel" ? value : "standard"`; строку `["Своя"]` в `UiLanguage.cs` **не удалять**, её держит редактор (`OverlayEditorWindow.xaml:291`, `OverlayEditorWindow.Appearance.cs:65, 81`). Старый файл с `AnnotationPalette: "custom"` при следующем сохранении настроек станет `"standard"`: сеттер `SelectedPalette` гасит неизвестное, а `OnSave` пишет то, что в контроле (`HotkeySettingsWindow.xaml.cs:525`) — молчаливая потеря выбора. Smoke `SmokeTestRunner.cs:271-273` проверяет только `pastel` и переживёт; `:97, 113-116` — про редактор, не про настройки.

**Если сегмент оставляют фильтром:** в настройках не меняется ничего, вся работа уезжает в редактор (`OverlayEditorWindow.Appearance.cs:320` — `var own = _activePalette.Id == "custom"`, от которого сейчас зависит видимость спектра и пипетки), а это зона аналитика D.

**Рекомендация:** оставить сегмент фильтром. Убирать его — значит терять сохранённый выбор у тех, кто уже на «Своей», ради строки, которая всё равно нужна редактору; а развязка спектра и пипетки от режима делается в `Appearance.cs:320` в обоих случаях.

---

## 7. Строки `UiLanguage.cs`

Удалить: `["Светлая"] = "Light"` (`:40`), `["Рассвет"] = "Dawn"` (`:41`).

Добавить (RU → EN):

| RU | EN |
|---|---|
| `Светлая · Рассвет` | `Light · Dawn` |
| `розовый` | `rose` |
| `бирюзовый` | `cyan` |
| `розово-фиолетовый` | `rose to violet` |
| `бирюзово-синий` | `cyan to blue` |
| `Снимок всего экрана` | `Capture the whole screen` |

Названия акцентов в `AccentNames` (`AppearancePicker.xaml.cs:38-43`) дополняются теми же четырьмя ключами; форма EN («X to Y») взята у существующих градиентов (`UiLanguage.cs:38-39`).

---

## 8. Тесты и smoke

Только на новую логику; старое не дублировать.

**Юнит-тест** — `tests/Snapik.App.Imaging.Tests/SettingsMigrationTests.cs`, только при варианте Б (§2.4): `light` при версии 0 и 1 → `dark`; известная тема не трогается; `light` при версии 2 не трогается; громкость 60 при версии 1 остаётся 60 (регресс порога).

**Smoke, `SmokeTestRunner.cs`:**

1. `Themes.Count == 6`, `Themes` не содержит `"light"`, `NormalizeTheme("light") == "dark"`. Рядом с `:192-194`.
2. `Accents.Count == 12` и порядок один в один со списком §5.3. Рядом с `:184-188`.
3. Признак градиента: первые шесть акцентов `IsGradientAccent == false`, последние шесть `true` — это и есть проверка, что разделитель встанет ровно один раз и на своём месте. Рядом с `:215-221`.
4. `Apply("glass", …)` → `SurfaceBrush is LinearGradientBrush` с тремя стопами `#5F5C8C` / `#7E5878` / `#58627A` и `SurfaceBarBrush` с теми же тремя стопами и `EndPoint = (1,0)`. По образцу проверки `sea` (`:200-205`).
5. У каждого градиентного акцента `AccentFlatColor` равен первому стопу `AccentBrush`: существующая проверка (`:179-183`) прогоняет только `blue-violet`, расширить на все шесть.
6. Языковая таблица `:339`: заменить пару `"Скриншот всего экрана в папку"` на `"Снимок всего экрана"`.
7. Подстроятся сами, править не надо: `AppearancePicker.RunProbe` (`AppearancePicker.xaml.cs:338-340`, считает по `Themes.Count` / `Accents.Count`), совпадение наборов ключей палитр и акцентов (`SmokeTestRunner.cs:184-194`), фолбэк неизвестной темы (`:206-208`), заморозка акцента по всем акцентам (`:215-221`), хром ленты по всем палитрам (`:846-862`).

Текст исключения `AppearancePicker.xaml.cs:362` («Seven cards of 132…») переписать на шесть — проверка верная, сообщение врёт.

---

## 9. Файлы зоны B

Только мои:

- `src/Snapik.App/Themes/Palettes/Light.xaml` — удалить
- `src/Snapik.App/Themes/Palettes/Glass.xaml` — переписать
- `src/Snapik.App/Themes/Palettes/{Dark,Night,Sunset,Sea,Dawn}.xaml` — только комментарий в шапке (`:4`)
- `src/Snapik.App/Themes/Accents/{Rose,Cyan,RoseViolet,CyanBlue}.xaml` — новые
- `src/Snapik.App/SettingsMigration.cs` — правило темы и порог правила громкости (вариант Б)
- `tests/Snapik.App.Imaging.Tests/SettingsMigrationTests.cs` — тест миграции (вариант Б)

Общие с другими дорожками (координировать, чтобы не разъехались при merge):

| файл | моё | чужое |
|---|---|---|
| `ThemeService.cs` | `Themes` (`:19`), `Accents` (`:22-23`), `IsGradientAccent`, комментарии | дорожки A и D сюда не пишут |
| `Controls/AppearancePicker.xaml.cs` | `ThemeNames` (`:29-33`), `AccentNames` (`:38-43`), `Backdrop` (`:215`), признак градиента в `BuildAccentRow` (`:183-199`) | **A**: геометрия галереи и ряда, `CardStep`, шевроны, `RunProbe` |
| `Controls/AppearancePicker.xaml` | — | **A**: ширины, `AccentDot` (`:52-57`), `ThemeCard` (`:32-33`), комментарий (`:82`); **D / E1**: сегмент `CustomPalette` (`:103`) |
| `UiLanguage.cs` | шесть строк §7 | **A**, **C**, **D**: свои строки |
| `SmokeTestRunner.cs` | проверки §8 (1–6), комментарии `:174`, `:841` | **A**: мастер и галерея; **C**: лента; **D**: редактор |
| `HotkeySettingsWindow.xaml` / `.xaml.cs` | `:43-44` (название клавиши), `Migrate` (`:114-121`) при варианте Б | **E2**: «Пройти знакомство заново»; **D**: сегмент палитры |
| `tasks/verification.md` | абзац «Изменение формата» при варианте Б | все дорожки |

---

## 10. Перенос на macOS

Mac-порт стоит на `mac-sync-base-1` и тем не знает вовсе: `macos/Sources/SnapikMac/App/Theme.swift` (67 строк) — это два плоских перечисления `LightTheme` и `DarkPalette`, собранные из литералов старой разметки Windows; `ThemeService`, словарей палитр и акцентов там нет, ключей `theme` / `accentId` в `macos/Sources/SnapikMac/Settings/*.swift` нет (grep пуст). Тем и акцентов Mac не догнал ещё с прошлого раунда, зеркалить придётся всё сразу.

Что должно уехать при ближайшей синхронизации:

1. **Шесть палитр, 14 токенов в каждой** — таблица §2.2 плюс «Стекло» §3.1. Идентификаторы `dark`, `glass`, `night`, `sunset`, `sea`, `dawn` — те же строки, они лежат в общем файле настроек.
2. **Правило градиента:** WPF `StartPoint` / `EndPoint` в относительных координатах (`0,0 → 0.35,1` для 160°, `0,0 → 0.6,1` для 150°, `0,0 → 1,0` для горизонтальной полосы) → `NSGradient` / `CAGradientLayer` с тем же направлением; три стопа «Стекла» с офсетами `0 / 0.55 / 1`.
3. **Двенадцать акцентов** — значения §5.2 и правила §5.1 (первый стоп как `AccentFlatColor`, 135° у градиентных, hover ×0.88, pressed ×0.78, soft `#55` + первый стоп, текст +37 % / +30 % к белому) и **порядок** §5.3: по нему рисуется ряд и ставится разделитель.
4. **Признак «градиентный», а не имя** — то же правило: разделитель перед первым акцентом, чей браш градиент.
5. **Миграция `light → dark`** и, при варианте Б, `SettingsVersion = 2` с порогом каждого правила по своей версии. Это изменение формата: Mac обязан читать и писать ту же версию, иначе файл будет мигрировать туда-сюда между платформами (AGENTS.md, правило 4).
6. **Строки §7** — в `macos/Sources/SnapikCore/Settings/UiLanguage.swift` в том же порядке (`macos/SYNC.md`, правило 5), включая «Светлая · Рассвет» и «Снимок всего экрана».
7. **B3 (acrylic)** на Mac не переносится: `NSVisualEffectView` там есть искони, но решение о настоящем стекле отложено на обеих платформах, и до него «Стекло» — обычная палитра градиента B.
