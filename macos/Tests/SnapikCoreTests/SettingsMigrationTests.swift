// Port of `tests/Snapik.App.Imaging.Tests/SettingsMigrationTests.cs`, SPEC-DELTA-3 §2.2, §6.
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
}
