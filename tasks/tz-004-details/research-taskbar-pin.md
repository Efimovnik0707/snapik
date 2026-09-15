# Ресёрч: программное закрепление на панели задач (шаг 3 мастера, ТЗ №3 Кати B3)

Дата: 14.09.2026. Источник: researcher-субагент по веб-источникам, на живой машине ничего не проверялось.

## 1. IPinnedList3: GUID, vtable, Modify

- **CLSID_TaskbandPin** `{90AA3A4E-1CBA-4233-B8BB-535773D48449}`, **IID_IPinnedList3** `{0DD79AE2-D156-45D4-9EEB-3B549769E940}` (три независимых источника: Mozilla, geelaw, Inno Setup thread).
- Предки: IPinnedList (Vista) `{C3C6EB6D-C837-4EAE-B172-5FEC52A2A4FD}`, IPinnedList «6.1» (Win7, IPinnedList2) `{BBD20037-BC0E-42F1-913F-E2936BB0EA0C}` (https://www.geoffchappell.com/studies/windows/shell/shell32/interfaces/ipinnedlist.htm).
- Порядок vtable IPinnedList3 после IUnknown: EnumObjects(3), GetPinnableInfo(4), IsPinnable(5), Resolve(6), LegacyModify(7), GetChangeCount(8), IsPinned(9), GetPinnedItem(10), GetAppIDForPinnedItem(11), ItemChangeNotify(12), UpdateForRemovedItemsAsNecessary(13), PinShellLink(14), GetPinnedItemForAppID(15), **Modify(16)**. Источники: https://github.com/adamecr/AppSwitcherBar/blob/master/net.adamec.ui.AppSwitcherBar/Win32/NativeInterfaces/IPinnedList3.cs, https://github.com/vhanla/W1nDro1d/blob/main/TaskbarPinner.pas, https://searchfox.org/mozilla-central/source/other-licenses/nsis/Contrib/PinToTaskbar/PinToTaskbar.cpp.
- `HRESULT Modify(PCIDLIST_ABSOLUTE unpin, PCIDLIST_ABSOLUTE pin, PINNEDLISTMODIFYCALLER caller)`: первый PIDL для открепления (NULL если не нужно), второй для закрепления.
- caller: Explorer = 4 (PLMC_EXPLORER), EdgeHTML = 28, Edge Chromium = 34, RuntimeBroker = 32 (https://geelaw.blog/entries/msedge-pins/). Mozilla шлёт `INT_MAX`, чтобы не подделывать чужую телеметрию.
- Другие реализации: https://github.com/woznet/TaskBarPin (PowerShell), https://github.com/0x546F6D/pttb_-_Pin_To_TaskBar (C, инъекция в Progman, как syspin).

### Поломки по версиям Windows

- Win10 1607 / KB3093266: Microsoft намеренно сломала verb-путь, не COM (https://pinto10blog.wordpress.com/2016/09/10/pinto10/).
- Поздние Win10 и промежуточные Win11: COM-вызов показывает toast-подтверждение вместо тихого пина (https://firefox-source-docs.mozilla.org/widget/windows/shell/pin-to-taskbar.html).
- **Начиная со сборки 10.0.26052 и в Win11 24H2 (26100) IPinnedList3 молча перестал закреплять: HRESULT S_OK, пина нет** (Mozilla bug 1879975, https://bugzilla.mozilla.org/show_bug.cgi?id=1879975). Firefox 127 перешёл на WinRT `TaskbarManager` с LAF-токеном. То же: https://techcommunity.microsoft.com/discussions/windows11/windows-11-24h2-start-menu-and-taskbar-pinning-feature-malfunction/4488052.
- **Win10 22H2 и Win11 23H2 (22631): работает.** **Win11 24H2/25H2 (26100, 26200): не работает.** Машина Никиты: Windows 11 Home 10.0.26200.

## 2. Вызов из C# (.NET 10, без пакетов)

WPF UI-поток уже STA, отдельный `CoInitialize` не нужен. `ILCreateFromPathW` → `Activator.CreateInstance(Type.GetTypeFromCLSID(CLSID_TaskbandPin))` → cast к `IPinnedList3` → `Modify(IntPtr.Zero, pidl, 4)` → `ILFree`. Explorer-контекст не требуется (Edge и NSIS-плагин Mozilla зовут из своего процесса; инъекция в Progman у syspin нужна была для verb-пути). Передавать **путь к `.lnk`** из меню «Пуск» (Inno Setup его создаёт), не к `.exe`: у ярлыка есть AUMID и правильная группировка окна.

```csharp
static class Pin {
    [ComImport, Guid("0DD79AE2-D156-45D4-9EEB-3B549769E940"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPinnedList3 {
        [PreserveSig] int EnumObjects(out IntPtr ppv);
        [PreserveSig] int GetPinnableInfo(IntPtr pidl, uint f, uint g, IntPtr a, IntPtr b);
        [PreserveSig] int IsPinnable(IntPtr dataObject, int flag);
        [PreserveSig] int Resolve(IntPtr hwnd, uint flags, IntPtr pidl, out IntPtr resolved);
        [PreserveSig] int LegacyModify(IntPtr from, IntPtr to);
        [PreserveSig] int GetChangeCount(out int count);
        [PreserveSig] int IsPinned(IntPtr pidl);
        [PreserveSig] int GetPinnedItem(IntPtr pidl, out IntPtr pinned);
        [PreserveSig] int GetAppIDForPinnedItem(IntPtr pidl, IntPtr appId);
        [PreserveSig] int ItemChangeNotify(IntPtr from, IntPtr to);
        [PreserveSig] int UpdateForRemovedItemsAsNecessary();
        [PreserveSig] int PinShellLink(ushort us, IntPtr link);
        [PreserveSig] int GetPinnedItemForAppID(ushort appId, out IntPtr pidl);
        [PreserveSig] int Modify(IntPtr unpin, IntPtr pin, int caller); // vtable 16
    }
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)] static extern IntPtr ILCreateFromPathW(string p);
    [DllImport("shell32.dll")] static extern void ILFree(IntPtr pidl);
    static readonly Guid CLSID_TaskbandPin = new("90AA3A4E-1CBA-4233-B8BB-535773D48449");

    public static bool PinLnk(string lnkPath) {                  // вызывать из STA-потока WPF
        IntPtr pidl = ILCreateFromPathW(lnkPath);
        if (pidl == IntPtr.Zero) return false;
        object? o = null;
        try {
            o = Activator.CreateInstance(Type.GetTypeFromCLSID(CLSID_TaskbandPin)!);
            return ((IPinnedList3)o!).Modify(IntPtr.Zero, pidl, 4) >= 0;   // 4 = PLMC_EXPLORER
        } catch { return false; }
        finally { if (o != null) Marshal.ReleaseComObject(o); ILFree(pidl); }
    }
}
```

`HRESULT == S_OK` на 24H2 возвращается и когда пина не произошло, поэтому результат проверять только по п.4.

## 3. Verb «taskbarpin» через Shell.Application

Удалён из перечисления с Win10 1607 намеренно, verb локализован (ru-RU «Закрепить на панели задач»), в Win11 через `InvokeVerb` не выполняется. В продукт не брать. (https://www.joseespitia.com/2016/05/13/how-to-programmatically-pin-icons-in-windows-10/)

## 4. Проверка результата

- Надёжный критерий: файл `%APPDATA%\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\<Имя>.lnk`, создаётся синхронно при успешном пине. Практика: снять список файлов до вызова, после вызова поллинг ~200 мс до 3 с (тайминг по опыту, не по спеке).
- Реестр `HKCU\...\Explorer\Taskband` (`Favorites`, `FavoritesResolve`) как критерий не годится: explorer пишет лениво, часто при перезапуске (https://www.winhelponline.com/blog/backup-pinned-taskbar-shortcuts-restore/).
- Если `User Pinned\TaskBar` оказался файлом, а не папкой, пин молча не работает (https://github.com/Atlas-OS/Atlas/issues/1299).

## 5. Политика NoPinningToTaskbar

DWORD `NoPinningToTaskbar = 1` в `HKCU\Software\Policies\Microsoft\Windows\Explorer` или `HKLM\SOFTWARE\Policies\Microsoft\Windows\Explorer`. Читать оба куста до показа кнопки; при 1 сразу инструкция. WinRT-эквивалент: `TaskbarManager.GetDefault().IsPinningAllowed` (https://learn.microsoft.com/en-us/windows/apps/develop/windows-integration/pin-to-taskbar).

## 6. macOS Dock (для будущей синхронизации порта)

`defaults write com.apple.dock persistent-apps -array-add '<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>/Applications/Snapik.app</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>'` затем `killall Dock`. Проверка: `defaults read com.apple.dock persistent-apps | grep -c "Snapik.app"` после `killall Dock` (иначе cfprefsd отдаёт кэш). Под MDM перекрывается профилем. (https://gist.github.com/kamui545/c810eccf6281b33a53e094484247f5e8)

## Пробелы

- Нет первоисточника Microsoft о блокировке IPinnedList3 на 24H2; вывод по Mozilla bug 1879975 и жалобам.
- Не проверено, работает ли `Windows.UI.Shell.TaskbarManager` (LAF) для unpackaged .NET-приложения без sparse-пакета; док требует запись в Start и AUMID, кейс Inno Setup не описан. На 26100.7705+/26200.7705+ LAF-токен якобы не нужен.
- Значения caller кроме 4 и INT_MAX от одного автора (Gee Law).

## Рекомендация ресёрчера

1. IPinnedList3 как основной путь только для сборок < 26052 (Win10 22H2, Win11 до 23H2), caller = 4, путь к `.lnk` из меню «Пуск».
2. Верифицировать по появлению `.lnk` в `User Pinned\TaskBar` (HRESULT врёт), таймаут ~3 с.
3. Для сборки ≥ 26100 пробовать `Windows.UI.Shell.TaskbarManager` (`IsPinningAllowed`, `IsCurrentAppPinnedAsync`, `RequestPinCurrentAppAsync`) — не проверено для unpackaged.
4. Перед показом кнопки читать `NoPinningToTaskbar` в HKCU и HKLM; при 1 сразу инструкция.
5. Фолбэк при любом провале: инструкция из трёх строк (по ТЗ). Verb «taskbarpin» не использовать.

---

# Часть 2. WinRT `TaskbarManager` для unpackaged-приложения (24H2+)

## Итог
Unpackaged WPF/.NET 10 может вызывать `Windows.UI.Shell.TaskbarManager` на 24H2/25H2. Microsoft публикует C++-сэмпл для приложения без package identity, а с KB5074105 (сборки 26100.7705 / 26200.7705, 29.01.2026) требование LAF-токена снято (https://learn.microsoft.com/en-us/windows/apps/develop/windows-integration/pin-to-taskbar). Машина Никиты: 10.0.26200.9445, токен не нужен. Обязательное условие: у процесса задан явный AUMID (`SetCurrentProcessExplicitAppUserModelID`) и в меню «Пуск» лежит `.lnk` с тем же `System.AppUserModel.ID`, видимый в `shell:appsfolder`.

## Факты
- До KB5074105 нужен `TryUnlockFeature("com.microsoft.windows.taskbar.pin", token, attestation)`; наличие seed-значения в `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel\LimitedAccessFeatures\com.microsoft.windows.taskbar.pin` показывает, нужен ли токен.
- Условия на момент вызова, иначе запрос молча отклоняется без исключения: приложение в foreground, запись в меню «Пуск», включены системные уведомления. `IsPinningAllowed` предсказывает исход. Из инсталлятора вызывать нельзя («Don't use installers to call the API»).
- Официальный unpackaged-сэмпл: https://github.com/microsoft/Windows-classic-samples/tree/main/Samples/TaskbarManager/CppUnpackagedDesktopTaskbarPin (`SetCurrentProcessExplicitAppUserModelID` в `App.xaml.cpp:49`, ярлык в `FOLDERID_Programs` с `PKEY_AppUserModel_ID` в `MainWindow.xaml.cpp:133-153`).
- Firefox (`nsWindowsShellService.cpp`, `PinShortcutToTaskbarImpl`, `PollAppsFolderForShortcut`): до 15 с поллит `shell:appsfolder` в поисках ярлыка с нужным AUMID (создание ярлыка и его появление в виртуальной папке это гонка), при неуспехе фолбэк на `IPinnedList3`.
- Система показывает свой диалог «Закрепить?», обойти нельзя, это by design. При уже закреплённом приложении метод возвращает `true` без диалога. Вызов не с UI-потока кидает исключение.
- `RequestPinSecondaryTileAsync` требует package identity, для unpackaged не годится. `IPinnedList3` с другим caller, syspin, pttb: рабочих обходов после 26052 не найдено (в issues pttb нет отчётов по 26100+).

## Вызов из .NET 10
Пакет `Microsoft.Windows.SDK.Contracts` не нужен, достаточно версионного TFM (CsWinRT projection встроен). Ревизия `.1` в TFM (например `26100.1`) подтягивает CsWinRT 3.0 preview вместо 2.x (https://github.com/dotnet/sdk/issues/51867), брать `.0`.

```xml
<TargetFramework>net10.0-windows10.0.26100.0</TargetFramework>
<SupportedOSPlatformVersion>10.0.17763.0</SupportedOSPlatformVersion>
```
```csharp
// один раз при старте процесса, до создания окон:
SetCurrentProcessExplicitAppUserModelID("YesWorkflow.Snapik");
// по клику пользователя, на UI-потоке, окно активно:
var tb = Windows.UI.Shell.TaskbarManager.GetDefault();
if (tb.IsSupported && tb.IsPinningAllowed && !await tb.IsCurrentAppPinnedAsync())
    bool pinned = await tb.RequestPinCurrentAppAsync();   // системный диалог «Закрепить?»
```
Гейт: номер сборки ОС ≥ 26100.7705 плюс try/catch вокруг `GetDefault()`.

## Проверка результата
`await tb.IsCurrentAppPinnedAsync()` после запроса плюс `.lnk` в `%APPDATA%\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar` (папка жива на 26200.9445, там же подпапка `Tombstones` для откреплённых). Предусловие: ярлык в Пуске отдаёт `PKEY_AppUserModel_ID`, равный AUMID процесса.

## Пробелы
- Нет публичного подтверждения третьих лиц, что unpackaged-приложение без токена реально получает `IsPinningAllowed == true` на ≥ 26100.7705; нужен собственный smoke на машине Никиты.
- Влияние явного AUMID на существующие ярлыки уже установленных версий (1.3.2 без AUMID): при обновлении Inno перезапишет `.lnk`, старый пин пользователя может «раздвоиться» (гипотеза, проверить).

## Рекомендация (сводная по двум частям)
1. Сборка ≥ 26100.7705: `TaskbarManager.RequestPinCurrentAppAsync` (Inno ставит `.lnk` с `System.AppUserModel.ID`, приложение зовёт `SetCurrentProcessExplicitAppUserModelID` с той же строкой; перед вызовом дождаться ярлыка в `shell:appsfolder`).
2. Сборка < 26052 (Win10 22H2, Win11 до 23H2): `IPinnedList3`, caller 4, PIDL ярлыка из «Пуска», проверка по `.lnk` в `User Pinned\TaskBar`.
3. Между 26052 и 26100.7705 и при любом отказе: инструкция из трёх строк (по ТЗ).
4. `NoPinningToTaskbar` в HKCU/HKLM = 1: сразу инструкция.
