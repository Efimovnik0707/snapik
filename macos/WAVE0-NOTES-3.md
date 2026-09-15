# Заметки волны 0 синхронизации №3 для исполнителей волны 1

Ветка `mac-sync-3-ci`, поверх master `1c7d727` (Snapik). CI зелёный на `cababaa`.

## Core, `Sources/SnapikCore/Settings/HotkeySettings.swift`
- 23 новых `var` (PascalCase `CodingKeys`, `decodeIfPresent` с дефолтами). `stackWidth`/`stackHeight` = `StripResizeGeometry.defaultWidth`/`.defaultListHeight`, `soundVolume` = `SettingsMigration.defaultSoundVolume`, `customPaletteColors: [String]`.
- API: `defaultFullscreenSaveId`, `maxCustomPaletteColors = 12`, `currentSettingsVersion`, `packageDirectory()`, `migrate(_:)`, `loadAndMigrate(path:)`, `find(_:fallbackId:)` (через `HotkeyRules.parseCustom`).
- `loadAndMigrate` ещё НЕ подключён на старте: `AppCoordinator.init` зовёт `workspace.preferences` (чистое чтение). Подключение — волна 2 (`AppCoordinator`). Пока битый id лечится только в памяти.
- Объекты настроек для round-trip строить от `.default`, не двухаргументным init (иначе `settingsVersion = 0` и миграция на чтении).
- Клампы разметки (1..16, 4..48, 8..96) живут в редакторе, не в настройках (порция B).

## Core, `UiLanguage.swift`
- 300 пар в порядке Windows, `englishPairs` internal. Сгенерирован скриптом, при расхождении с `src/Snapik.App/UiLanguage.cs` перегенерировать, не патчить руками.
- 18 устаревших пар оставлены в помеченном хвостовом блоке: их ещё читают `Settings/**`, `Editor/EditorStrings.swift`, `Stack/**`, `StatusStrings.swift`. Каждая порция волны 1 убирает свои чтения и свои пары.
- Строки «Запускать с Windows» и подсказка с `C:\Users\Public\Pictures` перенесены дословно; порция C решает macOS-формулировку через пару RU/EN.
- «Снимок всего экрана» = `Whole-screen capture`.

## Shell, `Sources/SnapikMac/App/Theme.swift`, `App/AccentPalette.swift`
- `enum ThemeBrush { solid(NSColor) | gradient([ThemeGradientStop], start:, end:) }` с `.flat`, `.isGradient`, `.nsGradient()`; точки в WPF-единичном квадрате, y вниз.
- `struct ThemePalette`: 14 токенов (`surface, surfaceBar, surfaceLine, elevated, elevatedLine, hover, pressed, divider, text, textMuted, textFaint, shadowColour, shadowOpacity, danger`).
- `enum ThemeService`: `themes` (6: dark, glass, night, sunset, sea, dawn), `accents` (12), `normalizeTheme` (`light` → `dark`), `normalizeAccent`, `palette(_:)`, `accent(_:)`, `isGradientAccent(_:)`, `apply(theme:accent:)`, `currentTheme`/`currentAccent`.
- `struct AccentTokens { id, flat, brush, hover, pressed, soft, text, focus, isGradient }`; `AccentPalette.wash(alpha:)` берёт 0…1.
- `DarkPalette` не тронут (24 обращения в `Stack/**`, `Settings/**`): порции A и C переводят свои обращения на `ThemeService.palette`. `LightTheme` удалён. Разделитель в ряду акцентов — по `isGradient`.

## Preview
- `Sources/SnapikMac/Preview/**` и его тесты удалены; `AppCoordinator.openCapture` — единственный вход в разметку; `persistPreviewChanges` нет; проба `preview probe` убрана из smoke.
- Код зума (`NSScrollView.magnification`, Cmd+колесо) в ветке `mac-preview-zoom-stash` (`PreviewImageScrollView.swift`), пригодится порции B для редактора с масштабом после Windows 1.5.0.

## Тесты
- Дописаны `SnapikCoreTests/SettingsMigrationTests.swift`, `SerializationCyrillicTests.swift`; новый `SnapikMacTests/App/ThemeServiceTests.swift`. Новых тестовых целей нет и не заводить.
