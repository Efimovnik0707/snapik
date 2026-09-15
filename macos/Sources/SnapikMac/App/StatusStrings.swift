// Port of the status/error string templates, SPEC §1.20 "Строки статуса и ошибок".
//
// Most of these are not part of Core's `UiLanguage` dictionary (SPEC: "В словаре локализации их
// нет; на Windows они остаются русскими даже при английском интерфейсе"). Kept verbatim in
// Russian here, matching the documented Windows baseline exactly rather than introducing an
// undocumented EN status table.
//
// Three exceptions (SPEC-DELTA-2 §3 "Строки 43-45"; SPEC-DELTA-2A §4/§6): the reusable-package
// completion/republish/displacement statuses *are* added to `UiLanguage.cs` on Windows, unlike
// every other entry in this file, so they go through `UiLanguage.text(_:language:)` here too.
import Foundation
import SnapikCore

enum StatusStrings {
    static func failedToRestoreSession(_ error: String) -> String { "Не удалось восстановить сессию: \(error)" }
    static func captureSetupFailed(_ error: String) -> String { "Захват: \(error)" }
    static func pasteIntentUnavailable(_ error: String) -> String { "Отслеживание вставки недоступно: \(error)" }
    static func hotkeyConflict(_ items: [String]) -> String { "Сочетание занято: \(items.joined(separator: ", "))" }
    static func failedToToggleLaunchAtLogin(_ error: String) -> String { "Не удалось изменить автозапуск: \(error)" }
    static let couldNotConfirmPackageContents = "Не удалось подтвердить содержимое текущего пакета. Сессия сохранена."
    /// SPEC-DELTA-2 §3/§4.8: "Снимки сохранены, но вставка не завершена" is a `UiLanguage`
    /// dictionary entry (added by core-shell); the `{message}` suffix stays untranslated (a raw
    /// diagnostic string, same as every other `{error}`/`{message}` interpolation in this file).
    static func capturesSavedButPasteIncomplete(_ message: String, language: String) -> String {
        "\(UiLanguage.text("Снимки сохранены, но вставка не завершена", language: language)): \(message)"
    }
    /// SPEC §4.4 (`EdgeStackWindow.xaml.cs:279`, the `catch` block around `CompletePasteIntentAsync`):
    /// raw, untranslated like that catch's `{ex.Message}` interpolation — not a `UiLanguage` entry.
    static func pasteObservedButNoNewSession(_ message: String) -> String {
        "Вставка замечена, но новая сессия не создана: \(message)"
    }
    /// SPEC-DELTA-2 §3/§4.8, SPEC-DELTA-2A §4: shown after `republishPackageForReuse` succeeds.
    /// `{0}`/`{1}` are the Windows-style placeholders `UiLanguage.cs` uses for this entry.
    static func pastedAndRepublished(imageCount: Int, noteCount: Int, language: String) -> String {
        UiLanguage.text(
            "Вставлено: {0} изображений · {1} заметок. Пакет остаётся в буфере, следующий снимок начнёт новую стопку",
            language: language)
            .replacingOccurrences(of: "{0}", with: "\(imageCount)")
            .replacingOccurrences(of: "{1}", with: "\(noteCount)")
    }
    /// SPEC-DELTA-2 §3/§4.8, SPEC-DELTA-2A §4: shown when republishing finds the package already
    /// displaced by another app.
    static func packageDisplaced(language: String) -> String {
        UiLanguage.text("Пакет вытеснен другим приложением. Сессия сохранена.", language: language)
    }
    static func captureNotCompleted(_ error: String) -> String { "Захват не завершён: \(error)" }
    static func couldNotVerifyClipboardBeforeCapture(_ error: String) -> String { "Не удалось проверить буфер перед новым снимком: \(error)" }
    static func couldNotOpenCapture(_ error: String) -> String { "Не удалось открыть снимок: \(error)" }
    static let captureDeleted = "Снимок удалён"
    static let makeACaptureFirst = "Сначала сделайте снимок."
    static let preparingPngAndText = "Готовим PNG и текст…"
    static func prepared(imageCount: Int, noteCount: Int) -> String { "Готово: \(imageCount) изображений · \(noteCount) заметок" }
    static func couldNotPrepare(_ error: String) -> String { "Не удалось подготовить: \(error)" }
    static func capturedButClipboardNotUpdated(_ error: String) -> String {
        "Снимок сохранён, но буфер не обновлён: \(error). Повторите копирование через меню."
    }
    static func pasteStopped(_ error: String) -> String { "Вставка остановлена: \(error)" }
    static func importFailed(fileName: String, error: String) -> String { "\(fileName): \(error)" }
    static func imported(count: Int) -> String { "Добавлено: \(count)" }
    static let clipboardHasNoImage = "В буфере нет изображения."
    static let imageAdded = "Изображение добавлено."
    static let packageCopied = "PNG и текст скопированы. Если получатель выберет один формат, используйте кнопку вставки."
    static let packageSaved = "Пакет сохранён."
    static func couldNotSave(_ error: String) -> String { "Не удалось сохранить: \(error)" }
    static func couldNotStartNewSession(_ error: String) -> String { "Не удалось начать новую сессию: \(error)" }
    static func sessionSavedButClipboardNotUpdated(_ error: String) -> String { "Сессия сохранена, но буфер не обновлён: \(error)" }
    static let orderChanged = "Порядок снимков изменён."
    static let captureRestored = "Снимок восстановлен."
    static func couldNotSaveScreen(_ error: String) -> String { "Не удалось сохранить экран: \(error)" }
    static func couldNotSaveCapture(_ error: String) -> String { "Не удалось сохранить снимок: \(error)" }
    static func couldNotCropCapture(_ error: String) -> String { "Не удалось обрезать снимок: \(error)" }
    static func couldNotResizeCapture(_ error: String) -> String { "Не удалось изменить границы снимка: \(error)" }
    static let choosePngOrJpeg = "Выберите PNG или JPEG."

    // Shell-specific status strings not in the Windows table (TCC permission gaps, SPEC §9.1-9.3).
    static let screenRecordingPermissionMissing = "Захват: нет разрешения на запись экрана"
}
