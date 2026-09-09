// Port of the status/error string templates, SPEC §1.20 "Строки статуса и ошибок".
//
// These are not part of Core's `UiLanguage` dictionary (SPEC: "В словаре локализации их нет; на
// Windows они остаются русскими даже при английском интерфейсе"). Kept verbatim in Russian here,
// matching the documented Windows baseline exactly rather than introducing an undocumented EN
// status table.
import Foundation

enum StatusStrings {
    static func failedToRestoreSession(_ error: String) -> String { "Не удалось восстановить сессию: \(error)" }
    static func captureSetupFailed(_ error: String) -> String { "Захват: \(error)" }
    static func pasteIntentUnavailable(_ error: String) -> String { "Отслеживание вставки недоступно: \(error)" }
    static func hotkeyConflict(_ items: [String]) -> String { "Сочетание занято: \(items.joined(separator: ", "))" }
    static func failedToToggleLaunchAtLogin(_ error: String) -> String { "Не удалось изменить автозапуск: \(error)" }
    static let couldNotConfirmPackageContents = "Не удалось подтвердить содержимое текущего пакета. Сессия сохранена."
    static func capturesSavedButPasteIncomplete(_ message: String) -> String { "Снимки сохранены, но вставка текста не завершена: \(message)" }
    static func pasteObservedButSessionNotStarted(_ error: String) -> String { "Вставка замечена, но новая сессия не создана: \(error)" }
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
