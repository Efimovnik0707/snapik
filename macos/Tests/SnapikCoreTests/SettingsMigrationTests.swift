// Port of `tests/Snapik.App.Imaging.Tests/SettingsMigrationTests.cs`, SPEC-DELTA-3 §2.2, §6.
import Foundation
import XCTest

@testable import SnapikCore

final class SettingsMigrationTests: XCTestCase {
    func test_A_file_without_a_version_is_migrated_and_a_current_one_is_not() {
        XCTAssertTrue(SettingsMigration.needsMigration(0))
        XCTAssertFalse(SettingsMigration.needsMigration(SettingsMigration.currentVersion))
    }

    func test_The_volume_that_used_to_be_the_default_becomes_the_new_default() {
        XCTAssertEqual(40, SettingsMigration.soundVolume(storedVersion: 0, storedVolume: 60))
        XCTAssertEqual(
            SettingsMigration.defaultSoundVolume,
            SettingsMigration.soundVolume(storedVersion: 0, storedVolume: 60))
    }

    func test_A_volume_the_user_picked_is_left_alone() {
        XCTAssertEqual(75, SettingsMigration.soundVolume(storedVersion: 0, storedVolume: 75))
        XCTAssertEqual(0, SettingsMigration.soundVolume(storedVersion: 0, storedVolume: 0))
        XCTAssertEqual(100, SettingsMigration.soundVolume(storedVersion: 0, storedVolume: 100))
    }

    func test_A_file_that_already_carries_the_version_keeps_even_the_old_default() {
        XCTAssertEqual(
            60,
            SettingsMigration.soundVolume(
                storedVersion: SettingsMigration.currentVersion, storedVolume: 60))
    }

    func test_A_file_written_by_the_previous_sync_keeps_its_keys_and_defaults_the_new_ones() throws {
        let path = try write(
            """
            {
              "CaptureId": "ctrl-shift-s",
              "PasteId": "alt-v",
              "CaptureEnabled": false,
              "FullscreenSaveEnabled": true,
              "FullscreenSaveId": "custom:4:44",
              "ShowNotifications": false,
              "RememberRegion": true,
              "CaptureCursor": true,
              "SaveFormat": "jpg",
              "JpegQuality": 80,
              "SaveDirectory": "/tmp/shots",
              "Language": "en",
              "AutoSaveCaptures": true,
              "PlaySounds": false
            }
            """)

        let settings = HotkeySettings.load(path: path)

        XCTAssertEqual("ctrl-shift-s", settings.captureId)
        XCTAssertEqual("alt-v", settings.pasteId)
        XCTAssertFalse(settings.captureEnabled)
        XCTAssertTrue(settings.fullscreenSaveEnabled)
        XCTAssertEqual("custom:4:44", settings.fullscreenSaveId)
        XCTAssertFalse(settings.showNotifications)
        XCTAssertTrue(settings.rememberRegion)
        XCTAssertTrue(settings.captureCursor)
        XCTAssertEqual("jpg", settings.saveFormat)
        XCTAssertEqual(80, settings.jpegQuality)
        XCTAssertEqual("/tmp/shots", settings.saveDirectory)
        XCTAssertEqual("en", settings.language)
        XCTAssertTrue(settings.autoSaveCaptures)
        XCTAssertFalse(settings.playSounds)

        XCTAssertEqual(SettingsMigration.defaultSoundVolume, settings.soundVolume)
        XCTAssertEqual(224, settings.stackWidth)
        XCTAssertEqual(372, settings.stackHeight)
        XCTAssertTrue(settings.stackTopmost)
        XCTAssertTrue(settings.confirmSessionDiscard)
        XCTAssertEqual("#FF3B30", settings.annotationColor)
        XCTAssertEqual("standard", settings.annotationPalette)
        XCTAssertEqual("rectangle", settings.annotationShape)
        XCTAssertEqual("none", settings.annotationFill)
        XCTAssertTrue(settings.annotationOutline)
        XCTAssertEqual("dark", settings.theme)
        XCTAssertEqual("blue", settings.accentId)
        XCTAssertEqual(0, settings.onboardingVersion)
        XCTAssertEqual([], settings.customPaletteColors)
    }

    func test_Every_key_of_a_filled_file_survives_being_written_and_read_back() throws {
        var written = HotkeySettings.default
        written.soundVolume = 75
        written.stackTopmost = false
        written.stackWidth = 320
        written.stackHeight = 500
        written.clearStackAfterPaste = true
        written.confirmSessionDiscard = false
        written.annotationColor = "#0A84FF"
        written.annotationPalette = "pastel"
        written.annotationPencil = "highlight"
        written.annotationThickness = 6
        written.annotationHighlightThickness = 24
        written.annotationFontSize = 32
        written.annotationShape = "ellipse"
        written.annotationFill = "blur"
        written.annotationFillColor = "#30D158"
        written.annotationOutline = false
        written.packageSaveDirectory = "/tmp/packages"
        written.packageCreateSubfolder = false
        written.onboardingVersion = 3
        written.theme = "sunset"
        written.accentId = "rose-violet"
        written.customPaletteColors = ["#112233", "#445566"]

        let path = try write("{}")
        try written.save(path: path)

        XCTAssertEqual(written, HotkeySettings.load(path: path))
    }

    func test_An_id_that_must_not_be_registered_is_healed_in_the_file_once() throws {
        // A bare arrow and a released modifier, both recorded by an older build.
        let path = try write(
            """
            {"CaptureId": "custom:0:37", "PasteId": "custom:3:16", "SoundVolume": 60}
            """)

        let healed = HotkeySettings.loadAndMigrate(path: path)

        XCTAssertEqual(HotkeySettings.default.captureId, healed.captureId)
        XCTAssertEqual(HotkeySettings.default.pasteId, healed.pasteId)
        XCTAssertEqual(HotkeySettings.defaultFullscreenSaveId, healed.fullscreenSaveId)
        XCTAssertEqual(SettingsMigration.defaultSoundVolume, healed.soundVolume)
        XCTAssertEqual(HotkeySettings.currentSettingsVersion, healed.settingsVersion)

        // Healed in the file and not only in memory: the second read finds nothing left to mend.
        let reread = HotkeySettings.load(path: path)
        XCTAssertEqual(healed, reread)
        XCTAssertEqual(HotkeySettings.default.captureId, reread.captureId)
    }

    func test_A_healthy_file_of_this_version_is_not_written_back() throws {
        let path = try write("{}")
        try HotkeySettings.default.save(path: path)
        // A key nothing knows: it survives a read and disappears the moment the file is rewritten.
        var content = try String(contentsOf: path, encoding: .utf8)
        content = content.replacingOccurrences(of: "{\n", with: "{\n  \"Unknown\" : 1,\n")
        try content.write(to: path, atomically: true, encoding: .utf8)

        XCTAssertEqual(HotkeySettings.default, HotkeySettings.loadAndMigrate(path: path))
        XCTAssertTrue(try String(contentsOf: path, encoding: .utf8).contains("\"Unknown\""))
    }

    func test_The_own_palette_drops_what_cannot_be_painted_and_stops_at_twelve() throws {
        let tooMany = [
            "#000000", "#111111", "#222222", "#333333", "#444444", "#555555", "#666666",
            "#777777", "#888888", "#999999", "#AAAAAA", "#BBBBBB", "#CCCCCC", "#DDDDDD",
            "#EEEEEE",
        ]
        let path = try write(
            """
            {
              "CaptureId": "ctrl-alt-s",
              "PasteId": "ctrl-alt-v",
              "CustomPaletteColors": ["#112233", "red", "#GGHHII", "#445566"]
            }
            """)

        XCTAssertEqual(["#112233", "#445566"], HotkeySettings.load(path: path).customPaletteColors)

        var filled = HotkeySettings.default
        filled.customPaletteColors = tooMany
        let secondPath = try write("{}")
        try filled.save(path: secondPath)
        XCTAssertEqual(
            HotkeySettings.maxCustomPaletteColors,
            HotkeySettings.load(path: secondPath).customPaletteColors.count)
    }

    func test_The_package_falls_back_to_the_folder_single_captures_go_to() {
        var settings = HotkeySettings.default
        settings.saveDirectory = "/tmp/shots"
        XCTAssertEqual("/tmp/shots", settings.packageDirectory())

        settings.packageSaveDirectory = "   "
        XCTAssertEqual("/tmp/shots", settings.packageDirectory())

        settings.packageSaveDirectory = "/tmp/packages"
        XCTAssertEqual("/tmp/packages", settings.packageDirectory())
    }

    private func write(_ content: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("snapik-settings-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("settings.json")
        try content.write(to: path, atomically: true, encoding: .utf8)
        return path
    }
}
