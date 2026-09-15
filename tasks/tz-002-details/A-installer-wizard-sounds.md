# План по ТЗ №2: §0, блок A (A1–A5), блок F, блок G, установщик

Зона: `installer/Snapik.iss`, `OnboardingWindow.xaml(.cs)`, `UiLanguage.cs`, `UiSoundService.cs`, `Assets/Audio/*`, `SmokeTestRunner.cs`, дефолт громкости. **A6 не мой** (аналитик ленты). Код сверялся с HEAD `a9381e6`, все ссылки file:line по нему. Правила `AGENTS.md` действуют: строки UI только через `UiLanguage.cs`, абзац «Изменение формата» в `tasks/verification.md` в момент коммита, один коммит на законченную правку, `macos/` не трогать.

Рамка ТЗ сохраняется: просто, в духе Apple, привычные паттерны, настройки не перегружать. Аудитория EU/Spain/Ukraine, два языка интерфейса: русский и английский.

---

## 1. Что показал разбор кода

Диагнозы ТЗ верны в шести пунктах из восьми. В четырёх местах картина другая, и три из них меняют решение, а не только объём.

1. **`ShowLanguageDialog=no` в установщике мало, и сам по себе он даст новый баг.** Директивы `ShowLanguageDialog` в `installer/Snapik.iss` вообще нет: диалог показывается по умолчанию Inno, потому что языков в `[Languages]` два (`:45-47`). Но отключение диалога включает автовыбор по локали, а при автовыборе Inno берёт язык, чей `LanguageID` совпал с UI-локалью пользователя, и **при отсутствии совпадения падает на первый язык списка**. Первым сейчас идёт `russian` (`:46`). То есть на испанской, немецкой, украинской системе установщик молча станет русским. Порядок нужно перевернуть (`english` первым), иначе §0 ухудшает ровно ту аудиторию, ради которой затевался. Это не «правка одной строки», как читается ТЗ, а «две строки и порядок».

2. **Убрать задачу `autostart` из установщика нельзя одной правкой `[Tasks]`: потеряется очистка при удалении.** Задача живёт в двух местах: `[Tasks]` (`:51-52`) и `[Registry]` (`:63`, `Flags: uninsdeletevalue; Tasks: autostart`). Именно флаг `uninsdeletevalue` сегодня стирает значение `HKCU\...\Run\Snapik` при деинсталляции. Приложение пишет в **тот же** ключ и то же имя значения (`WindowsStartupService.cs:9-10,24`). Если просто удалить обе строки, то у пользователя, включившего автозапуск в мастере (`OnboardingWindow.xaml:97`), после удаления программы останется висячая запись `Run` на несуществующий exe. Нужна безусловная чистка в `[UninstallRun]`.

3. **§0 и A3 противоречат друг другу по языковым карточкам.** A3 требует «карточки уменьшить до высоты около 56, шрифт 14, как обычные сегменты» (`OnboardingWindow.xaml:80-87`, стиль `LanguageCard` `:8-24`), а §0 требует карточек вообще не иметь: «первый экран мастера „Добро пожаловать“ с уже выбранным языком и маленьким переключателем в углу, не отдельный шаг с двумя большими карточками». §0 написано позже и по сути: побеждает оно. Стиль `LanguageCard` удаляется целиком, пункт A3 про карточки становится беспредметным, «56 и 14» переезжают на сегменты переключателя в шапке (там уместнее 26 px, см. решение A3). Это надо зафиксировать, иначе исполнитель сделает и то и другое.

4. **F1: два звука есть, но виноват не тот файл, и замена по ТЗ сделает захват громче, а не тише.** Строка `EdgeStackWindow.xaml.cs:496` это не «копирование в буфер играет notify-soft», а `await SaveAndCopyCommittedPackageAsync()`, внутри которого `NotifyCopied()` (`:647`) → `UiSoundService.Copied` (`EdgeStackWindow.Saving.cs:13`). Замер (ffmpeg volumedetect, mean/max по файлу):

   | Файл | mean | max | длительность |
   |---|---|---|---|
   | `shutter-2-050s.mp3` (сейчас, гейн 1.0) | −37.3 dB | −8.3 dB | 0.496 с |
   | `notify-soft-040.mp3` (второй звук, гейн 0.7) | — | −5.1 dB | 1.071 с |
   | кандидат `kauasilbershlachparodes-chutter-click-494024` | −31.1 dB | −5.9 dB | 0.392 с |
   | кандидат `freesound_community-iphone-camera-capture-6448` | −29.1 dB | −7.0 dB | 0.624 с |

   Нынешний затвор объективно **самый тихий** из всех камерных кандидатов, оба предложенных ТЗ громче по средней энергии на 6–8 dB. «Громко» пришло от наложения второго звука: `notify-soft-040` длиннее вдвое и на 3 dB горячее по пику. Поэтому замену файла делаем (тембр это вкусовое решение Кати, замерами не проверяется), но **только вместе с гейном 0.6 и дефолтом громкости 40**, иначе выйдет громче нынешнего. Арифметика: сейчас 60 × 1.0 = 0.60 линейно, станет 40 × 0.6 = 0.24, это −8 dB, и с учётом +6 dB более горячего файла итог примерно −2 dB к сегодняшнему. Если Катя хочет «заметно тише», нужен гейн 0.45 (см. открытый вопрос 3).

5. **«Скопировано» звучит гораздо шире, чем «при захвате».** `NotifyCopied()` вызывается из трёх мест: `SaveAndCopyCommittedPackageAsync` (`:647`, то есть при каждом захвате и при редактировании снимка из ленты, `EdgeStackWindow.Preview.cs:48`), `CopyPackageAsync` (`:870`, явное «Копировать пакет») и `RefreshOwnedClipboardCoreAsync` (`:1294`, дефолт `notifyCopied: true`), а последний зовут удаление снимка (`:523`), импорт файла (`:835`), вставка из буфера (`:849`), тик таймера сохранения (`:1138`), реордер (`:1419`) и восстановление (`:1428`). То есть звук «скопировано» сегодня играет ещё и на удалении, импорте, перетаскивании карточки и просто по таймеру. Требование ТЗ «звучит только при явном „Копировать пакет“» закрывается разделением звука и балуна (см. F1), без флипа `notifyCopied`: балун трогать не надо, Катя на него не жаловалась.

6. **Дефолт громкости 60 → 40 сам по себе ничего не изменит для тех, кто уже ставил 1.2.0.** `HotkeySettings` это record, сохраняемый целиком (`HotkeySettingsWindow.xaml.cs:104`, `JsonSerializer.Serialize(this)`), поэтому в `settings.json` у Кати уже лежит явное `"SoundVolume": 60`. Новый дефолт увидят только чистые учётки. Нужна разовая миграция (см. F1 и раздел 5).

7. **Мелочи, которые ТЗ не упоминает, но исполнитель об них споткнётся.** (а) `SmokeTestRunner.cs:50-52` прямо утверждает `LanguageForCulture("uk") == "ru"` и `("be") == "ru"` — §0 это ломает, smoke упадёт. (б) `OnboardingWindow.RunOnboardingProbe` (`:251-269`) проходит все 4 шага и требует, чтобы в английском режиме нигде не осталось кириллицы, а `WizardStrings` (`:273-289`) исключает из обхода ровно элемент `LanguageRow` (`:279`) — после §0 этот элемент исчезнет, и исключение надо перевесить на новый переключатель, иначе smoke упадёт на слове «Русский». (в) Storyboard-бухгалтерия мастера рассчитана ровно на один Storyboard (`_hint`, `_hintApplied`, `OnClosed` `:74-85`): под четыре слайда её надо переписать на список, иначе анимации останутся висеть на закрытом окне. (г) Кнопки «Назад» и «Далее» **уже** одной высоты 34 (`SnapikTheme.xaml:41`, `MinHeight`); «слишком большие» они из-за горизонтального `Padding="15,8"` у `PrimaryButton` (`:69`) и из-за того, что три кнопки мастера переопределяют `Padding="0"` (`OnboardingWindow.xaml:74,103`) и выглядят ссылками. Правим ширину и единый стиль, а не высоту.

8. **Провенанс звуков (открытый вопрос 8 из tz-001-plan) закрывается без Кати.** Файлы в `tasks/handoff-002/sounds/` побайтово совпадают с `tasks/handoff-001/sounds/` и с тем, что уже лежит в `Assets/Audio/` (сверено по md5). Имена несут автора и id, этого хватает для README:

   | Файл в проекте | Оригинал | Источник |
   |---|---|---|
   | `shutter-2-050s.mp3` (удаляется) | `kauasilbershlachparodes-shutter-click-2-494026` | Pixabay, автор kauasilbershlachparodes, id 494026 |
   | `shutter-1-039s.mp3` (новый) | `kauasilbershlachparodes-chutter-click-494024` | Pixabay, автор kauasilbershlachparodes, id 494024 |
   | `click-tiny-005s.mp3` | `denielcz-immersivecontrol-button-click-sound-463065` | Pixabay, автор denielcz, id 463065 |
   | `notify-soft-040.mp3` | `universfield-new-notification-040-493469` | Pixabay, автор Universfield, id 493469 |

   Лицензия по `tasks/handoff-002/sounds/SOUNDS.md`: Pixabay Content License / CC0. Точный URL страницы звука Pixabay не выводится из имени файла машинно, поэтому в README пишем автора, id и шаблон поиска `https://pixabay.com/sound-effects/search/<id>/` — этого достаточно, чтобы формулировка «источник не задокументирован» из `Assets/Audio/README.md:8-10` ушла.

---

## 2. Решения по пунктам

Размеры: S / M / L. Без оценок времени.

### §0 и блок A

| # | Решение | Размер |
|---|---|---|
| **§0-инст** | В `[Setup]` добавить `ShowLanguageDialog=no`. В `[Languages]` переставить строки: `english` (`compiler:Default.isl`) первым, `russian` (`compiler:Languages\Russian.isl`) вторым — это единственная защита от «испанская система → русский установщик», см. п.1 разбора. Ничего больше в установщике по языку не трогать: `LanguageDetectionMethod` остаётся дефолтным (`uilanguage`), `UsePreviousLanguage` тоже. Третий язык (испанский) не заводить: интерфейс приложения двуязычный, установщик должен совпадать. | S |
| **§0-прил** | `OnboardingWindow.xaml.cs:95-96`: `LanguageForCulture` становится `twoLetterIsoLanguageName == "ru" ? "ru" : "en"`. Комментарий `:94` переписать («русская система даёт русский, любая другая английский»). `SuggestedLanguage` (`:99-102`) не меняется. `SmokeTestRunner.cs:50-52` переписать на новое правило: `("ru")=="ru"`, `("uk")=="en"`, `("be")=="en"`, `("es")=="en"`, `("en")=="en"`. | S |
| **A1** | Шаг 1 перестаёт быть «Выберите язык» и становится «Добро пожаловать». Механика: <br>• Удалить стиль `LanguageCard` (`OnboardingWindow.xaml:8-24`) и обе карточки (`:83-86`) вместе с `LanguageRow`.<br>• В шапке (`:72-77`) слева от крестика поставить капсулу-переключатель `x:Name="LanguageToggle"`: `Border` `CornerRadius="8"`, `Background="#21262F"`, `BorderBrush="#39424F"`, `BorderThickness="1"`, `Padding="2"`, внутри `StackPanel Orientation="Horizontal"` с двумя `RadioButton` стиля `LanguageSegment` (`RussianSegment`, `EnglishSegment`), `GroupName="OnboardingLanguage"`, Content `"Русский"` и `"English"`.<br>• Стиль `LanguageSegment` (RadioButton): `Height=26`, `MinWidth=74`, `FontSize=12`, `Padding="12,0"`, `Cursor=Hand`, `FocusVisualStyle={x:Null}`, шаблон = `Border x:Name="Seg" CornerRadius="6" Background="Transparent"` + центрированный `ContentPresenter`; триггеры: `IsMouseOver` → `Background="#2A3240"`, `IsChecked` → `Background={DynamicResource AccentSoftBrush}` и `Foreground="#FFFFFF"`, `IsKeyboardFocused` → `BorderBrush={DynamicResource FocusBrush}`.<br>• Содержимое шага 1: заголовок «Добро пожаловать» (стиль `StepTitle`), подзаголовок «Snapik делает скриншот по твоей клавише и кладёт его в чат с ИИ вместе с комментариями.» (стиль `StepSubtitle`), под ним компактная векторная схема «клавиша → снимок → чат» (три `Border`/`Path` в `Viewbox`, тот же приём, что в A4; без анимации, анимация живёт на шаге 4).<br>• Подписки `RussianCard.Checked`/`EnglishCard.Checked` (`.xaml.cs:59-62`) переименовать на сегменты, логика `SelectLanguage` (`:118-122`) не меняется.<br>• В `WizardStrings` (`.xaml.cs:279`) заменить исключение `window.LanguageRow` на `window.LanguageToggle` — имена языков литеральны в обоих режимах и под кириллическую проверку попадать не должны.<br>• Заголовок окна «Знакомство со Snapik» (`:73`) удалить: после A3 единственный заголовок 21 px это заголовок шага, два таких в одном окне конкурируют.<br>Новые строки: `"Добро пожаловать"` / `"Welcome"`, `"Snapik делает скриншот по твоей клавише и кладёт его в чат с ИИ вместе с комментариями."` / `"Snapik takes a screenshot on your own shortcut and puts it into an AI chat together with your comments."`, `"Язык интерфейса"` / `"Interface language"` (ToolTip + `AutomationProperties.Name` капсулы). Удалить из `UiLanguage.cs`: `"Выберите язык"` (`:99`), `"Интерфейс и подсказки будут на этом языке."` (`:100`), `"Знакомство со Snapik"` (`:97`). | M |
| **A2** | Установщик: удалить обе строки `[Tasks] autostart` (`Snapik.iss:51-52`) и запись `[Registry]` (`:63`). Вместо неё добавить безусловную чистку при деинсталляции (см. п.2 разбора):<br>`Filename: "reg.exe"; Parameters: "delete ""HKCU\Software\Microsoft\Windows\CurrentVersion\Run"" /v Snapik /f"; Flags: runhidden; RunOnceId: "DropAutostart"` в `[UninstallRun]` рядом с существующим `taskkill` (`:68-69`).<br>Обоснование выбора: `[Registry]` с `ValueType: none; Flags: deletevalue uninsdeletevalue` не годится — он стёр бы автозапуск и при обычной установке поверх, то есть отключал бы настройку пользователя на каждом апдейте.<br>В приложении ничего не меняется: `StartupBox` (`OnboardingWindow.xaml:97`) и пункт трея (`EdgeStackWindow.xaml.cs:137`) уже единственный путь. | S |
| **A3** | Единый шаблон экрана мастера как набор локальных стилей в `OnboardingWindow.xaml` → `Window.Resources` (глобальный `SnapikTheme.xaml` не трогать: он светлый, мастер тёмный, и общий `IconButton` из B4 делает владелец блока B):<br>• `StepPanel` (`TargetType="StackPanel"`): `Width=360`, `HorizontalAlignment=Center`, `VerticalAlignment=Top`, `Margin="0,4,0,0"`. Применяется к `Step1..Step4`.<br>• `StepTitle` (`TextBlock`): `FontSize=21`, `FontWeight=SemiBold`, `Foreground="#EEF2F8"`, `TextWrapping=Wrap`, `Margin="0,0,0,6"`. Заменяет `FontSize="16"` на `:81, :90, :96, :107`.<br>• `StepSubtitle` (`TextBlock`): `FontSize=13`, `Foreground="#8F9AAA"`, `TextWrapping=Wrap`, `Margin="0,0,0,20"`. Заменяет `:82, :91` и ставится там, где подзаголовка не было (шаги 3 и 4).<br>• `StepBodyText` (`TextBlock`): `FontSize=13`, `Foreground="#EEF2F8"`, `TextWrapping=Wrap`, `Margin="0,0,0,10"`. Для `:101-102`.<br>• `WizardButton` (`Button`, `BasedOn={StaticResource BaseButton}`): `Height=34`, `MinHeight=34`, `MinWidth=96`, `Padding="14,0"`, `FontSize=13`, `Foreground="#EEF2F8"`, `controls:ButtonChrome.HoverBackground="#2A3240"`, `PressedBackground="#20262F"`. Убирает повтор атрибутов на `:74, :103, :149`.<br>• `WizardPrimaryButton` (`Button`, `BasedOn={StaticResource PrimaryButton}`): `Height=34`, `MinHeight=34`, `MinWidth=96`, `Padding="14,0"`, `FontSize=13`. Для `NextButton` (`:150`) и `StartButton` (`:151`) вместо голого `PrimaryButton` с `Padding="15,8"`.<br>• `WizardIconButton` (`Button`, `BasedOn={StaticResource BaseButton}`): `Width=28`, `Height=28`, `MinHeight=28`, `MinWidth=28`, `Padding=0`. Для крестика (`:74`) и для шевронов слайдов из A5.<br>• `LanguageSegment` — см. A1.<br>Один фон для всех шагов: корневой `Border Background="#171B22"` (`:69`) остаётся единственным; у рамки шага 4 (`:108`) `Background="#12161D"` меняется на `Transparent`, рамка `#2A3240` остаётся.<br>Контент шириной 360 и по центру: рамка-иллюстрация шага 4 заворачивается в `<Viewbox Stretch="Uniform" Width="360" Height="144">`, внутри остаётся авторская сетка `Canvas 500×200` без пересчёта координат (это же правило наследуют все четыре слайда A5).<br>Что удалить: стиль `LanguageCard` (в A1), `Padding="0"` у крестика (переезжает в `WizardIconButton`), `Foreground="White"` у `BackButton` (`:149`, переезжает в стиль).<br>Строк UI не добавляет. | M |
| **A4** | Кнопку `ShortcutButton` (`OnboardingWindow.xaml:103`), обработчик `OnShowShortcut` (`.xaml.cs:219-230`) и метод `ShortcutPath()` (`.xaml.cs:235-247`) удалить целиком: других пользователей у них нет (проверено grep по `src`, `tests`, `scripts`). Из `UiLanguage.cs:108` удалить пару `"Показать ярлык"` и пару `"Не удалось открыть папку с ярлыком"`.<br>Вместо кнопки — **векторная схема без растровых ассетов**, тем же приёмом, что HintCanvas: `Viewbox Width=360 Height=132` → `Canvas Width=360 Height=132`, всё фигурами, ноль файлов:<br>1. Панель задач: `Rectangle Canvas.Left=0 Canvas.Top=108 Width=360 Height=24 RadiusX=6 RadiusY=6 Fill="#1B212B"` и поверх три `Rectangle 14×14 RadiusX=3 Fill="#2C3746"` (иконки соседних приложений) на `Canvas.Left=` 118, 140, 162, `Canvas.Top=113`.<br>2. Кнопка «Пуск»: четыре `Rectangle 7×7 RadiusX=1.5 Fill="#8F9AAA"` в квадрат 2×2 с зазором 3 px, левый верхний на `Canvas.Left=14 Canvas.Top=113`.<br>3. Меню Пуск: `Border Canvas.Left=8 Canvas.Top=8 Width=176 Height=96 CornerRadius=10 Background="#1B212B" BorderBrush="#33404F" BorderThickness=1`, внутри `StackPanel Margin="12,10,0,0"` с тремя строками: `Rectangle 96×7 RadiusX=3 Fill="#2C3746"`, затем выделенная строка Snapik — `Border Height=22 CornerRadius=5 Background={DynamicResource AccentSoftBrush}` с `Ellipse 10×10 Fill={DynamicResource AccentBrush}` и `Rectangle 70×7 RadiusX=3 Fill="#8F9AAA"`, затем ещё `Rectangle 82×7`.<br>4. Контекстное меню правой кнопки: `Border Canvas.Left=150 Canvas.Top=34 Width=184 Height=70 CornerRadius=8 Background="#222A35" BorderBrush="#3A4553" BorderThickness=1`, три строки по 20 px; вторая (подсвеченная) — `Border CornerRadius=4 Background="#2E3A49"` с иконкой булавки и подписью «Закрепить на панели задач» (`FontSize=10`, `Foreground="#EEF2F8"`).<br>5. Булавка (единственная «настоящая» иконка), `Path Width=11 Height=13 Stretch=Uniform Fill="#EEF2F8"`, данные: `M3,0 L9,0 L8,1.6 L8,5 L11,7.6 L11,8.8 L6.6,8.8 L6.6,13 L5.4,13 L5.4,8.8 L1,8.8 L1,7.6 L4,5 L4,1.6 Z`.<br>6. Курсор с меткой правой кнопки: `Path Canvas.Left=142 Canvas.Top=52 Fill="#EEF2F8" Stroke="#171B22" StrokeThickness=1 Data="M0,0 L0,13 L3.2,10 L5.2,14 L7.2,13 L5.2,9.2 L9.4,9.2 Z"` и рядом `Ellipse 9×9 Fill={DynamicResource AccentBrush} Opacity=0.9` как «правый клик».<br>7. Подпись под схемой — существующий текст `:101` стилем `StepBodyText`, строка `:102` остаётся приглушённой.<br>Новые строки: `"Закрепить на панели задач"` / `"Pin to taskbar"` (подпись внутри схемы), `"Пуск"` / `"Start"` (не рисуем текстом, если схема без него читается — принято по умолчанию: не рисовать, оставить четыре квадрата, узнаваемо и не требует перевода). Заголовок шага `"Запуск и панель задач"` (`:96`) остаётся. | M |
| **A5** | Четыре слайда вместо одного. Механика и файлы:<br>**Вынести в отдельный контрол** `src/Snapik.App/Controls/HowToSlides.xaml(.cs)` (новый `UserControl`). Причина: четыре `Canvas` и четыре `Storyboard` в `OnboardingWindow.xaml` раздувают файл, который в этом же наборе коммитов правят A1, A3 и A4; отдельный контрол снимает конфликт и позволяет переиспользовать слайды из трея. Публичный API: `void ShowSlide(int index)`, `void Start()`, `void Stop()`, `void ApplyLanguage(string language)`, `int Slide { get; }`, `string KeyLabel { set; }` (подпись клавиши в слайде 1).<br>**Общая сетка:** каждый слайд это `Canvas Width=500 Height=200` внутри `Viewbox Stretch=Uniform Width=360 Height=144` (см. A3), четыре слайда лежат в одной `Grid`, видим один. Один `Border` рамки на всех: `Background=Transparent`, `BorderBrush="#2A3240"`, `CornerRadius=12`.<br>**Такт 1.2 с на фазу, 4 фазы = 4.8 с на слайд, `RepeatBehavior="1x"`, по `Completed` переход на следующий слайд по кругу.** Ручной переход перезапускает часы текущего слайда.<br>**Слайд 1 (существующий, переносится как есть)** из `OnboardingWindow.xaml:27-67` (Storyboard `HintLoop`) и `:109-134` (`HintCanvas`) вместе с четырьмя подписями `:137-140`. Ничего не перерисовывать.<br>**Слайд 2 «Пачка снимков».** Фигуры: слева окно-макет (`Border 230×140 CornerRadius=8 Background="#1B212B" BorderBrush="#33404F"`, две серые полосы текста, как в слайде 1), справа лента — колонка из четырёх `Border 104×44 CornerRadius=8 Background="#222A35" BorderBrush="#3A4553"` с перекрытием 14 px (`Canvas.Top` 30, 60, 90, 120; `Canvas.Left=340`), у каждой бейдж-буква `Border 18×18 CornerRadius=9 Background={DynamicResource AccentBrush}` с `A`,`B`,`C`,`D`; внизу слева капсула клавиши (копия `HintKey`).<br>Фаза 1 (0.0–1.2): капсула клавиши мигает (Opacity 0.4→1 за 0.2 с, ScaleY 1→0.8→1), карточка A прилетает: `TranslateTransform` X −90→0, Y 24→0 и Opacity 0→1 за 0.35 с начиная с 0.15 с, `CubicEase EaseOut`.<br>Фаза 2 (1.2–2.4): то же для B со сдвигом +1.2 с.<br>Фаза 3 (2.4–3.6): то же для C и D (D на 3.0 с), появляется счётчик `Border` с текстом «10» приглушённо (Opacity 0→0.7) — визуальный намёк на потолок из A6.<br>Фаза 4 (3.6–4.8): капсула «Ctrl + V» (Opacity 0→1 на 3.7 с), стрелка `Path` от ленты к окну чата (Opacity 0→1 на 3.8 с), чат-окно светлеет 0.35→1, все четыре карточки получают галочку `Path` (Opacity 0→1) и уходят в Opacity 0.45.<br>Подписи: «Снимок» · «Ещё снимок» · «До 10 снимков в ленте» · «Один Ctrl+V отправляет все».<br>**Слайд 3 «Комментарии к отметкам».** Фигуры: окно-макет по центру (`Border 300×150`), внутри рамка-выделение, пилюля, справа узкое окно чата (`Border 120×150`).<br>Фаза 1: `Rectangle HintFrame` растёт Width 0→104, Height 0→46 за 0.6 с, `Stroke={DynamicResource AccentBrush}`, `StrokeThickness=2`.<br>Фаза 2 (1.2): бейдж `Ellipse 20×20 Fill={DynamicResource AccentBrush}` с цифрой «1» появляется в углу рамки, `ScaleTransform` 0.7→1 с `BackEase EaseOut`, Opacity 0→1 за 0.25 с.<br>Фаза 3 (2.4): пилюля `Border CornerRadius=9 Background={DynamicResource AccentSoftBrush}` разворачивается Width 24→150 за 0.4 с, внутри «набирается текст» — `Rectangle` Width 0→96 за 0.5 с и мигающая каретка `Rectangle 1×10` (`RepeatBehavior` на фазе, Opacity 1↔0 по 0.4 с).<br>Фаза 4 (3.6): в окне чата появляются две строки — `Ellipse 12×12` с «1» и `Rectangle 84×6`, Opacity 0→1 со сдвигом 0.15 с между ними.<br>Подписи: «Обведи место» · «Поставь отметку» · «Напиши, что не так» · «В чат уходит текст с номерами».<br>**Слайд 4 «Лента живёт».** Фигуры: колонка из трёх карточек (как в слайде 2, `Canvas.Left=200`), сверху иконка корзины `Path`, справа мини-чат.<br>Фаза 1: три карточки видимы и яркие (Opacity 1), ничего не движется.<br>Фаза 2 (1.2): у двух верхних появляется галочка и Opacity падает 1→0.45 за 0.3 с.<br>Фаза 3 (2.4): четвёртая карточка прилетает сверху (Y −40→0, Opacity 0→1) яркой.<br>Фаза 4 (3.6): корзина подсвечивается (`Stroke` → `AccentBrush`, ScaleX/Y 1→1.15→1), все карточки уезжают вверх на −24 px и гаснут до 0 за 0.45 с.<br>Подписи: «Снимки остаются в ленте» · «Отправленные помечены» · «Новый снимок снова яркий» · «„Очистить“, когда закончил».<br>**Пагинация:** под подписью `StackPanel Orientation=Horizontal HorizontalAlignment=Center Margin="0,10,0,0"` с четырьмя `Ellipse 7×7 Margin="4,0"`, неактивная `Fill="#46505E"`, активная `Fill={DynamicResource AccentBrush}`; каждая точка обёрнута в кликабельный `Button` стиля `WizardIconButton` размером 16×16 с `ToolTip` «Слайд {N}». Смена точки — `ColorAnimation` 150 мс.<br>**Навигация:** шевроны `‹` `›` стилем `WizardIconButton` по краям рамки (`Path` данные `M6,1 L1,6 L6,11` и зеркально); клавиши Left/Right на окне мастера, когда виден шаг 4; авто-переход по завершении Storyboard.<br>**Переиспользование из трея.** `EdgeStackWindow.xaml.cs:133` (пункт «Как пользоваться») сейчас зовёт `ShowOnboarding()`, который открывает весь мастер с языком и клавишей. Меняем на `ShowOnboarding(howToOnly: true)`: в этом режиме `OnboardingWindow` показывает только шаг 4, прячет `LanguageToggle`, `BackButton` и `NextButton`, а `StartButton` получает подпись «Готово»; `StepText` («Шаг N из 4») скрывается, вместо него точки. `TryApply` в этом режиме не вызывается ни разу, `MarkPassed` отрабатывает как обычно. Конструктор: `OnboardingWindow(HotkeySettings settings, bool howToOnly = false)`.<br>**Бухгалтерия Storyboard.** Поля `_hint`, `_hintRunning`, `_hintApplied` (`OnboardingWindow.xaml.cs:26,29,30`) и их обработка в `ShowStep` (`:138-139`) и `OnClosed` (`:76-82`) переезжают в `HowToSlides` и становятся массивом: контрол держит `Storyboard[] _slides` и `int _applied` (битовую маску), в `Stop()` делает `Stop(this)` и `Remove(this)` каждому применённому. `OnboardingWindow.OnClosed` зовёт `HowTo.Stop()`.<br>**Версия мастера.** `OnboardingWindow.CurrentVersion` (`:23`) 1 → 2: мастер переделан целиком, и тестировщики, уже прошедшие версию 1, должны увидеть новый один раз. Поднять именно в этом коммите, последнем по мастеру.<br>Новые строки (12 подписей слайдов 2–4 + навигация) перечислены в разделе 3. | L |

### Блок F

| # | Решение | Размер |
|---|---|---|
| **F1** | Четыре независимые правки, один коммит.<br>**(1) Один звук на захват.** Из `NotifyCopied()` (`EdgeStackWindow.Saving.cs:11-15`) убрать строку `UiSoundService.Copied(_settings);` — метод остаётся балуном. Рядом добавить `private void NotifyCopiedAloud() { UiSoundService.Copied(_settings); NotifyCopied(); }`. Единственный вызов `NotifyCopiedAloud()` — в `CopyPackageAsync` (`EdgeStackWindow.xaml.cs:870`). Остальные пять путей (`:647`, `:1294` и его шесть вызывающих) остаются без звука и с прежним балуном. Флаг `notifyCopied` (`:1264,:1294`) **не трогать**: после этой правки он управляет только уведомлением, поведение которого менять не просили.<br>**(2) Затвор в момент захвата.** `UiSoundService.Capture(_settings)` (`EdgeStackWindow.xaml.cs:497`) переставить со строки после `await SaveAndCopyCommittedPackageAsync()` на строку сразу после `Captures.Add(result.Capture);` (`:493`). Сейчас звук ждёт похода в буфер обмена и приходит с задержкой. Правка в две строки; если владелец блока B (A6, B1) правит ровно этот цикл, её можно отдать ему или отложить — на остальное она не влияет.<br>**(3) Новый файл затвора.** Взять `tasks/handoff-002/sounds/kauasilbershlachparodes-chutter-click-494024.mp3`, положить в `src/Snapik.App/Assets/Audio/` под именем **`shutter-1-039s.mp3`** (конвенция «имя-длительность» из существующих файлов; 0.392 с). Побайтово, без перекодирования. Удалить `Assets/Audio/shutter-2-050s.mp3`. В `UiSoundService.cs:17` `ShutterFile = "shutter-1-039s.mp3"`, `:20` гейн `1.0 → 0.6`. `csproj` править не надо: `Content Include="Assets\Audio\*.mp3"` (`Snapik.App.csproj:25`) это шаблон. `VerifyAssets()` (`:56-72`) подхватывает новое имя автоматически через константы.<br>Почему этот кандидат, а не `freesound_community-iphone-camera-capture-6448`: он на 2 dB тише по средней энергии, вдвое короче (0.392 с против 0.624 с) и **умещается в окно подавления тиков** `SoundThrottle.CaptureSuppressionMilliseconds = 400` (`SoundThrottle.cs:14`); 0.624-секундный файл это окно перерастает, и тик наведения на карточку вернётся поверх хвоста затвора — ровно тот дефект, ради которого окно вводили.<br>**(4) Дефолт громкости и миграция.** `HotkeySettingsWindow.xaml.cs:27`: `SoundVolume` дефолт `60 → 40`. Плюс новое поле `public int SettingsVersion { get; init; }` (дефолт 0) и константа `public const int CurrentSettingsVersion = 1;` там же. В `EdgeStackWindow.OnLoaded` (`EdgeStackWindow.xaml.cs:168-184`), сразу после `Topmost = _settings.StackTopmost;` (`:172`) и до `UiSoundService.Preload()` (`:173`):<br>`if (File.Exists(_settingsPath) && _settings.SettingsVersion < HotkeySettings.CurrentSettingsVersion) MutateSettings(stored => stored with { SoundVolume = stored.SoundVolume == 60 ? 40 : stored.SoundVolume, SettingsVersion = HotkeySettings.CurrentSettingsVersion });`<br>Через существующий `MutateSettings` (`:715-731`), чтобы запись шла тем же безопасным путём. Правило «только если ровно 60» бережёт того, кто двигал ползунок; тот, кто осознанно выбрал 60, получит 40 один раз и вернёт обратно навсегда (версия уже записана). Без записи на диск миграция повторялась бы при каждом старте.<br>Smoke: `SmokeTestRunner.cs:28-37` дополняется `SettingsVersion = HotkeySettings.CurrentSettingsVersion` в наборе нестандартных значений, чтобы round-trip покрыл и это поле. | M |
| **F2** | `src/Snapik.App/Assets/Audio/README.md` переписать по таблице из п.8 разбора: для каждого из трёх файлов автор Pixabay, id, шаблон страницы `https://pixabay.com/sound-effects/search/<id>/`, имя оригинала в `tasks/handoff-002/sounds/`. Абзац «Provenance is incomplete» (`:8-10`) удалить. Таблицу (`:16-20`) обновить: новая строка `shutter-1-039s.mp3` с гейном 0.6, размером 12 538 B и свежим SHA-256, строку `shutter-2-050s.mp3` убрать, у остальных двух гейны и размеры не меняются. Добавить абзац про замер громкости (mean/max из п.4 разбора) как обоснование гейна 0.6, чтобы следующий раз не мерили заново. Ссылку на источник набора сменить с `handoff-001` на `handoff-002/sounds/SOUNDS.md`. | S |

### Блок G: ответы зафиксированы

| Вопрос | Ответ Кати | Что требует действий |
|---|---|---|
| B8, EN-название ленты | **Capture strip** | Ничего. Уже в коде: `UiLanguage.cs:49` `["Snapik — Лента снимков"] = "Snapik — Capture strip"`, smoke проверяет пару (`SmokeTestRunner.cs:188`). Закрыт. |
| C5, стикеры | **эмодзи-ассеты Twemoji**, не векторные штампы | Действие есть, но **вне ТЗ №2**: в ТЗ №2 буквы C5 заняты другим пунктом («Скрыть сплошным» = фигура с заливкой). Это ответ на C5 из ТЗ №1, который так и не реализован. Нужна отдельная задача: 12–16 PNG Twemoji 128 px, `AnnotationKind.Sticker`, рендер в обоих рендерерах, атрибуция CC-BY 4.0 в README ассетов, `CaptureCropper.cs:58`. Формат `session.json` меняется совместимо только вперёд. Вынесено в открытый вопрос 1. |
| C6, WebP при сохранении | **не делать**, подтверждено | Ничего, текущее состояние и есть «не делать». Закрыт. |
| B2, «Сохранить пакет…» | **вся лента** | Ничего. Уже так: `CopyPackageAsync` и `SavePackageAsAsync` берут `Captures` целиком, комментарий `EdgeStackWindow.xaml.cs:852-854` это фиксирует. Закрыт. |
| B2, отмена у «Очистить» | **без отмены**, диалог с галочкой | Действие у владельца блока B (пункт B1 ТЗ №2). Моей зоны не касается. |
| C1, пилюля | **двигать бейдж и рисовать выноску**, подтверждено | Ничего. Реализовано, `noteOffset` описан в `tasks/verification.md:476`. Закрыт. |
| (F, из tz-001-plan, вопрос 8) | Катя прислала оригиналы с автором и id в именах | Закрывается пунктом F2 без её участия. |

---

## 3. Новые и удаляемые строки UI (все через `UiLanguage.cs`)

Добавить:

| RU | EN | Пункт |
|---|---|---|
| Добро пожаловать | Welcome | A1 |
| Snapik делает скриншот по твоей клавише и кладёт его в чат с ИИ вместе с комментариями. | Snapik takes a screenshot on your own shortcut and puts it into an AI chat together with your comments. | A1 |
| Язык интерфейса | Interface language | A1 |
| Закрепить на панели задач | Pin to taskbar | A4 |
| Снимок | Capture | A5 |
| Ещё снимок | Another capture | A5 |
| До 10 снимков в ленте | Up to 10 captures in the strip | A5 |
| Один Ctrl+V отправляет все | One Ctrl+V sends them all | A5 |
| Обведи место | Frame the spot | A5 |
| Поставь отметку | Drop a marker | A5 |
| Напиши, что не так | Write what is wrong | A5 |
| В чат уходит текст с номерами | The chat gets the text with the numbers | A5 |
| Снимки остаются в ленте | The captures stay in the strip | A5 |
| Отправленные помечены | The sent ones are marked | A5 |
| Новый снимок снова яркий | A new capture is bright again | A5 |
| «Очистить», когда закончил | "Clear" when you are done | A5 |
| Предыдущий слайд | Previous slide | A5 |
| Следующий слайд | Next slide | A5 |
| Слайд {0} из {1} | Slide {0} of {1} | A5 |
| Готово (уже есть, `:29`) | Done | A5, подпись кнопки в режиме «только слайды» |

Удалить: `"Выберите язык"`, `"Интерфейс и подсказки будут на этом языке."`, `"Знакомство со Snapik"` (A1), `"Показать ярлык"`, `"Не удалось открыть папку с ярлыком"` (A4).

Пара `"Снимок"` / `"Capture"` — проверить, что она не конфликтует с существующим `["Захват"] = "Capture"` (`UiLanguage.cs:80`): обратный перевод идёт поиском по значению (`:112`), два русских ключа с одинаковым английским значением сломают путь EN→RU. **Подпись слайда 2 сделать «Первый снимок» / `"The first capture"`**, чтобы коллизии не было. То же правило проверить для остальных новых пар перед коммитом.

---

## 4. Файлы по пунктам (матрица для оркестратора)

| Пункт | Файлы |
|---|---|
| §0-инст + A2-инст | `installer/Snapik.iss` |
| §0-прил | `src/Snapik.App/OnboardingWindow.xaml.cs`, `src/Snapik.App/SmokeTestRunner.cs` |
| A1 | `src/Snapik.App/OnboardingWindow.xaml`, `src/Snapik.App/OnboardingWindow.xaml.cs`, `src/Snapik.App/UiLanguage.cs`, `src/Snapik.App/SmokeTestRunner.cs` |
| A2-прил | нет файлов (в приложении уже всё есть) |
| A3 | `src/Snapik.App/OnboardingWindow.xaml`, `src/Snapik.App/OnboardingWindow.xaml.cs` |
| A4 | `src/Snapik.App/OnboardingWindow.xaml`, `src/Snapik.App/OnboardingWindow.xaml.cs`, `src/Snapik.App/UiLanguage.cs` |
| A5 | `src/Snapik.App/Controls/HowToSlides.xaml` *(новый)*, `src/Snapik.App/Controls/HowToSlides.xaml.cs` *(новый)*, `src/Snapik.App/OnboardingWindow.xaml`, `src/Snapik.App/OnboardingWindow.xaml.cs`, `src/Snapik.App/UiLanguage.cs`, `src/Snapik.App/SmokeTestRunner.cs`, **`src/Snapik.App/EdgeStackWindow.xaml.cs`** (одна строка: `:133`) |
| F1 | `src/Snapik.App/UiSoundService.cs`, `src/Snapik.App/HotkeySettingsWindow.xaml.cs`, `src/Snapik.App/Assets/Audio/shutter-1-039s.mp3` *(новый)*, `src/Snapik.App/Assets/Audio/shutter-2-050s.mp3` *(удаление)*, `src/Snapik.App/SmokeTestRunner.cs`, **`src/Snapik.App/EdgeStackWindow.Saving.cs`** (`:11-15`), **`src/Snapik.App/EdgeStackWindow.xaml.cs`** (`:172-173`, `:493/:497`, `:870`) |
| F2 | `src/Snapik.App/Assets/Audio/README.md` |
| Все | `tasks/verification.md` (по абзацу на коммит; файл дописывается в конец, конфликтов между агентами быть не должно, но два агента не должны коммитить одновременно) |

**Касания вне моей зоны (минимизированы):**
- `EdgeStackWindow.xaml.cs` — три места: A5 меняет одну строку `:133` (замена `ShowOnboarding` на `ShowOnboarding(howToOnly: true)`), F1 меняет `:870` (`NotifyCopied` → `NotifyCopiedAloud`), добавляет одну строку миграции рядом с `:172` и переставляет `:497` на `:493`. Всего пять строк в файле на 1400+ строк, все в разных методах. Владелец блока B (A6, B1–B4) правит `CaptureLoopAsync` (`:480-508`) и `LoadCurrentAsync`-путь — пересекается только правка `:493/:497`. **Рекомендация:** отдать перестановку `:493/:497` владельцу блока B вместе с A6, тогда F1 трогает в этом файле только `:172` и `:870`.
- `EdgeStackWindow.Saving.cs` — только F1, `:11-15`. Блок B этот файл по ТЗ №2 не правит.
- `OverlayEditorWindow*` и `AnnotationCanvas.cs` — **не трогаются ни одним моим пунктом**.
- `UiLanguage.cs` и `SmokeTestRunner.cs` — общие для всех блоков: там правят и C, и D. Это файлы-«таблицы», мержатся легко, но параллельных коммитов в них лучше не допускать.

---

## 5. Зависимости и порядок коммитов

Зависимости:
- §0-инст и A2-инст правят один файл и делаются вместе.
- §0-прил встроено в A1 (одна и та же правка `OnboardingWindow.xaml.cs` и один и тот же smoke-блок).
- A1 → A3: A1 убирает карточки и стиль `LanguageCard`, A3 заводит единый шаблон на то, что осталось. Обратный порядок заставит стилизовать то, что через коммит удалят.
- A3 → A4: иллюстрация A4 верстается сразу под `StepPanel` шириной 360 и `Viewbox`.
- A3 → A5: слайды тоже живут в `Viewbox` 360×144, а шевроны и точки используют `WizardIconButton` из A3.
- A4 → A5 связи нет, но оба правят `OnboardingWindow.xaml`, поэтому идут последовательно.
- F1 → F2: README описывает уже выбранный файл и его SHA-256.
- F и A независимы полностью, кроме `SmokeTestRunner.cs`.

Порядок коммитов (сообщения по-английски, префикс `windows:`):

1. `windows: the installer stops asking about language and startup` — установщик: `ShowLanguageDialog=no`, english первым, удаление задачи `autostart` и `[Registry]`, чистка `Run` в `[UninstallRun]`. Полностью параллелен всему остальному.
2. `windows: the wizard opens on a welcome screen` — §0-прил + A1: правило локали, приветственный шаг, переключатель RU/EN в шапке, удаление карточек, правки smoke.
3. `windows: one layout for every wizard step` — A3.
4. `windows: the wizard shows how to pin Snapik` — A4.
5. `windows: four how-to slides with dots` — A5 + подъём `CurrentVersion` до 2 + пункт трея.
6. `windows: one soft shutter at capture time` — F1 (звук, гейн, дефолт громкости, миграция).
7. `windows: sound provenance in the assets readme` — F2.

Коммиты 1 и 6–7 можно вести параллельно с 2–5 (разные файлы), внутри каждой цепочки порядок строгий. Коммиты 2–5 это одна серийная дорожка одного исполнителя: все четыре правят `OnboardingWindow.xaml`.

---

## 6. Изменения форматов (для синхронизации Mac)

Одно изменение и одно поведенческое.

| Файл | Поле | Пункт |
|---|---|---|
| `settings.json` | `SettingsVersion` int = 0, новый. Версия схемы настроек; `CurrentSettingsVersion = 1`. Аддитивно: старый файл без ключа читается и даёт 0, новый читается старым билдом (лишний ключ игнорируется). | F1 |
| `settings.json` | `SoundVolume` дефолт 60 → 40 (поведение, не схема). Разовая миграция при старте: файл с `SettingsVersion < 1` и `SoundVolume == 60` получает 40 и `SettingsVersion = 1`. Значение, отличное от 60, не трогается. | F1 |
| (мастер) | `OnboardingVersion` схему не меняет; константа `OnboardingWindow.CurrentVersion` 1 → 2, из-за чего мастер один раз показывается всем, кто видел первую версию. Это поведение, не формат. | A5 |

`session.json`, `manifest.json`, `prompt.md` и формат ID горячей клавиши **не меняются** ни одним пунктом моей зоны.

Абзацы «Изменение формата» в `tasks/verification.md` писать в коммитах 5 и 6.

---

## 7. Тесты и smoke

Что уже покрыто: round-trip настроек (`SmokeTestRunner.cs:27-42`), правило показа мастера (`:45-49`), правило языка по локали (`:50-52`), построение и прогон всех шагов мастера с кириллической проверкой EN (`:151-165` через `RunOnboardingProbe`), закрытие мастера без кнопок (`:171-175`), словарь пар RU/EN (`:176-191`), наличие и MP3-заголовок трёх звуков (`:19` → `UiSoundService.VerifyAssets`), троттлинг тиков (`tests/Snapik.App.Imaging.Tests/SoundThrottleTests.cs`). Онбординг и звуки в `tests/` xUnit-тестами не покрыты вообще: вся проверка живёт в smoke, потому что требует WPF-потока.

Добавить:

**Smoke (`SmokeTestRunner.cs`):**
1. `:50-52` переписать под новое правило: `("ru")=="ru"`, `("uk")=="en"`, `("be")=="en"`, `("es")=="en"`, `("en")=="en"` (коммит 2).
2. `:28-37` дополнить `SettingsVersion = HotkeySettings.CurrentSettingsVersion`, чтобы round-trip покрыл новое поле (коммит 6).
3. Новая проверка миграции громкости: записать файл `HotkeySettings.Default with { SoundVolume = 60 }` (то есть `SettingsVersion = 0`), прогнать функцию миграции, убедиться, что стало 40 и `SettingsVersion = 1`; второй файл с `SoundVolume = 75` после миграции остаётся 75. Чтобы это проверялось без окна, вынести правило в `internal static HotkeySettings Migrate(HotkeySettings stored)` рядом с `HotkeySettings` — тогда оно покрывается и обычным xUnit-тестом.
4. Новая проверка дефолта: `HotkeySettings.Default.SoundVolume == 40`.
5. Новая проверка звуков: `VerifyAssets()` уже пройдёт по новому имени, добавить явную проверку, что `shutter-2-050s.mp3` рядом со сборкой **нет** (иначе старый файл переживёт в `bin` и в установщике).
6. Проверка режима «только слайды»: построить `new OnboardingWindow(settings, howToOnly: true)`, убедиться, что `Step1..Step3` скрыты, `Step4` видим, `LanguageToggle`, `BackButton` и `NextButton` скрыты, `StartButton` видим; затем закрыть.
7. Проверка слайдов: на `HowToSlides` вызвать `ShowSlide(i)` для i = 0..3, после каждого `UpdateLayout()`, проверить `Slide == i` и что видим ровно один `Canvas`. Затем `Stop()` и убедиться, что повторный `Stop()` не бросает (это ловит забытый `Remove`).
8. Расширить список пар `:176-189` новыми подписями слайдов (хотя бы по одной с каждого слайда) и парой «Добро пожаловать» / «Welcome».
9. Проверка `RunOnboardingProbe`: исключение из кириллической проверки должно быть перевешено на `LanguageToggle`; сама проверка ловит забытую пару в `UiLanguage` автоматически.
10. Проверка на коллизию обратного перевода: пройти по всему словарю `UiLanguage` и убедиться, что английские значения уникальны (`English.Values.Distinct().Count() == English.Count`). Это ловит риск из раздела 3 и дешевле, чем ловить его глазами.

**xUnit (`tests/Snapik.App.Imaging.Tests/`, проект без WPF-окон):**
11. `SettingsMigrationTests`: три кейса из пункта 3 выше плюс «файл с `SettingsVersion = 1` и `SoundVolume = 60` не трогается».

**Установщик:** автотестов нет и не заводим. Ручная проверка в разделе 9.

---

## 8. Открытые вопросы

Требуют решения, реализовать без них нельзя:

1. **Стикеры (ответ G про Twemoji).** Ответ есть, задачи нет: в ТЗ №2 пункта про стикеры не осталось, а C5 из ТЗ №1 не реализован. Вопрос Никите: делать стикеры в этом раунде отдельной задачей (12–16 PNG Twemoji, лицензия CC-BY 4.0, атрибуция в дистрибутиве, изменение `session.json` совместимое только вперёд) или отложить до следующего ТЗ. Рекомендация: отложить, приоритеты ТЗ №2 до стикеров не доходят.
2. **Установщик после §0: язык самого установщика.** Подтвердить перестановку `english` первым. Последствие, о котором стоит знать: русская система получит русский установщик, испанская, немецкая, украинская — английский, ровно по правилу §0. Если Катя хочет иначе (например, украинская локаль → русский установщик), это правится одной строкой, но противоречит §0. Рекомендация: принять как написано.
3. **Насколько тише должен звучать затвор.** По замерам (раздел 1, п.4) связка «новый файл + гейн 0.6 + громкость 40» даёт примерно −2 dB к тому, что Катя слышала, а не «заметно тише»: основной вклад в «громко» давал второй звук, и он уходит. Если после теста всё равно громко, крутить надо гейн, а не громкость: 0.45 даст ещё −2.5 dB. Вопрос Кате: достаточно ли −2 dB плюс снятие второго звука, или сразу ставить гейн 0.45. Рекомендация: 0.6, замерить на живом тесте.

Принято по умолчанию, вопросов не задаю:
- Иллюстрация A4 статическая, без Storyboard: движение живёт на шаге 4, две анимации в одном мастере спорят.
- Слайды переключаются сами по кругу, ручной клик перезапускает часы текущего слайда.
- Трей «Как пользоваться» открывает только слайды, без языка и клавиши: язык и клавиша есть в настройках.
- `OnboardingWindow.CurrentVersion` поднимается до 2, мастер один раз показывается заново.
- Стиль `WizardIconButton` локальный для мастера; общий `IconButton` для ленты (B4) делает владелец блока B, объединять их в этом раунде не нужно.
- Третий язык в установщике не заводим.
- Файл затвора называется `shutter-1-039s.mp3` по существующей конвенции «имя-длительность».

---

## 9. Как проверять (моя часть приёмочного сценария)

Автоматически: `scripts/build.ps1` (тесты и `--smoke-test`), включая новые проверки из раздела 7.

Вручную на чистой учётке:
1. Испанская или английская локаль Windows: установщик **не спрашивает язык**, интерфейс установщика английский, экранов про автозапуск нет, есть только «куда ставить» и «ярлык на рабочем столе».
2. Русская локаль: установщик русский, тоже без вопроса о языке и без автозапуска.
3. Первый запуск: мастер открывается на «Добро пожаловать», язык уже выбран по системе, в углу переключатель «Русский · English», переключение мгновенно меняет весь мастер.
4. Украинская локаль: мастер открывается на английском (а не на русском, как было в 1.2.0).
5. Все четыре шага в одном стиле: заголовок 21, подзаголовок 13 приглушённый, контент 360 по центру, «Назад» и «Далее» одного размера, один фон.
6. Шаг 3: чекбокс автозапуска, под ним схема «Пуск → правый клик → Закрепить на панели задач», кнопки «Показать ярлык» нет.
7. Шаг 4: четыре слайда, точки внизу, слайды сами сменяются, клик по точке и шеврону переключает, Left/Right работают.
8. Трей → «Как пользоваться»: открываются только слайды, кнопка «Готово».
9. Снимок: **один** звук, короткий; «скопировано» молчит. Удаление снимка, импорт, перетаскивание карточки: звука нет.
10. «•••» → «Копировать пакет»: звук «скопировано» есть.
11. Чистая учётка: громкость в настройках 40. Учётка, обновлённая с 1.2.0, где стояло 60: после первого запуска 40; если до обновления стояло 75 — осталось 75.
12. Деинсталляция после включённого автозапуска: значение `HKCU\Software\Microsoft\Windows\CurrentVersion\Run\Snapik` исчезло.
