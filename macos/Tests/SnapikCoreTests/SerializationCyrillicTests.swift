import XCTest

@testable import SnapikCore

/// Cyrillic/UTF-8 round-trip coverage for `SnapikJson`, `HotkeySettings`, and `UiLanguage`
/// (not present in the C# suite, added per the port task's cross-platform/Cyrillic-first
/// requirement). The first test below intentionally exercises a Russian string end-to-end, since
/// this app's primary UI language and prompt text are Russian.
final class SerializationCyrillicTests: XCTestCase {
    func test_session_json_round_trips_cyrillic_text_as_utf8() throws {
        let start = ISO8601Precise.makeUTC(year: 2026, month: 9, day: 9, hour: 12, minute: 30, second: 45)
        let note = "Пользователь попросил: «увеличь кнопку входа» — проверь ё, й, э, ъ и эмодзи 🙂"
        var capture = CaptureItem.create(
            sourceImagePath: "source/скриншот.png", pixelWidth: 640, pixelHeight: 480, title: "Экран входа", note: note)
        capture.annotations = [
            AnnotationItem.create(kind: .text, points: [NormalizedPoint(0.1, 0.1)], text: "Заголовок", note: "Комментарий №1")
        ]
        var session = try SessionOperations.addCapture(SnapikSession.create(nowUtc: start), capture: capture, nowUtc: start)
        session.globalNote = "Общее пожелание: сохранить кириллицу без потерь"

        let data = try SnapikJson.encoder.encode(session)

        // The payload must be valid, decodable UTF-8 (not escaped \uXXXX sequences that would
        // still round-trip but would fail a "readable Cyrillic in the raw bytes" expectation).
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.contains("скриншот.png"))
        XCTAssertTrue(text.contains("Экран входа"))
        XCTAssertTrue(text.contains(note))

        let decoded = try SnapikJson.decoder.decode(SnapikSession.self, from: data)
        XCTAssertEqual(session.globalNote, decoded.globalNote)
        XCTAssertEqual(capture.title, decoded.captures[0].title)
        XCTAssertEqual(capture.note, decoded.captures[0].note)
        XCTAssertEqual(capture.sourceImagePath, decoded.captures[0].sourceImagePath)
        XCTAssertEqual("Заголовок", decoded.captures[0].annotations[0].text)
        XCTAssertEqual("Комментарий №1", decoded.captures[0].annotations[0].note)
    }

    func test_prompt_generator_preserves_cyrillic_and_emoji_across_sections() throws {
        let start = ISO8601Precise.makeUTC(year: 2026, month: 9, day: 9, hour: 0, minute: 0, second: 0)
        var capture = CaptureItem.create(sourceImagePath: "source/a.png", pixelWidth: 10, pixelHeight: 10, note: "Комментарий к снимку 🎯")
        capture.annotations = [
            AnnotationItem.create(kind: .arrow, points: [NormalizedPoint(0.1, 0.1), NormalizedPoint(0.2, 0.2)], note: "Сделать шире ↔")
        ]
        var session = try SessionOperations.addCapture(SnapikSession.create(nowUtc: start), capture: capture, nowUtc: start)
        session.globalNote = "Пожелание с юникодом: файл→папка"

        let prompt = try PromptGenerator().generate(session)

        XCTAssertTrue(prompt.contains("Пожелание с юникодом: файл→папка"))
        XCTAssertTrue(prompt.contains("Комментарий к снимку 🎯"))
        XCTAssertTrue(prompt.contains("A1: Сделать шире ↔"))
    }

    func test_hotkey_settings_json_round_trips_cyrillic_save_directory() throws {
        var settings = HotkeySettings.default
        settings.saveDirectory = "/Users/пользователь/Изображения/Snapik"
        settings.language = "ru"

        let data = try JSONEncoder().encode(settings)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.contains("пользователь"))
        // Field names must stay exact PascalCase (no camelCase policy) to match the C# default
        // JsonSerializerOptions used by HotkeySettingsWindow.Save/Load.
        XCTAssertTrue(text.contains("\"SaveDirectory\""))
        XCTAssertTrue(text.contains("\"CaptureId\""))

        let decoded = try JSONDecoder().decode(HotkeySettings.self, from: data)
        XCTAssertEqual(settings, decoded)
    }

    func test_ui_language_looks_up_cyrillic_source_strings_and_translates_round_trip() {
        XCTAssertEqual("Settings", UiLanguage.text("Настройки", language: "en"))
        XCTAssertEqual("Настройки", UiLanguage.text("Settings", language: "ru"))
        XCTAssertEqual("Undo", UiLanguage.text("Отменить", language: "en"))
        // Unknown strings pass through unchanged in both directions.
        XCTAssertEqual("Неизвестная строка", UiLanguage.text("Неизвестная строка", language: "ru"))
    }

    func test_guid_lowercase_and_no_dashes_formats_match_dotnet_conventions() {
        let id = SBGuid()
        XCTAssertEqual(id.description, id.description.lowercased())
        XCTAssertTrue(id.description.contains("-"))
        XCTAssertFalse(id.digitsLowercase.contains("-"))
        XCTAssertEqual(32, id.digitsLowercase.count)
        XCTAssertEqual(id.digitsLowercase, id.digitsLowercase.lowercased())
    }
}
