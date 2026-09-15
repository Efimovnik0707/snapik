import XCTest

@testable import SnapikCore

/// Port of `tests/Snapik.App.Imaging.Tests/AppDataPathsTests.cs`: the data folder of the name the
/// application shipped under up to 1.4.0 has to survive the rename.
final class SnapikPathsTests: XCTestCase {
    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("snapik-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func test_the_folder_of_the_old_name_becomes_the_folder_of_the_new_one() throws {
        let temp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let legacy = temp.appendingPathComponent("SnapBrief", isDirectory: true)
        let root = temp.appendingPathComponent("Snapik", isDirectory: true)
        try FileManager.default.createDirectory(
            at: legacy.appendingPathComponent("sessions/one", isDirectory: true),
            withIntermediateDirectories: true)
        try "{\"язык\":\"ru\"}".write(
            to: legacy.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)

        SnapikPaths.carryOverLegacyData(from: legacy, to: root)

        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("settings.json"), encoding: .utf8),
            "{\"язык\":\"ru\"}")
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("sessions/one").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
    }

    func test_a_folder_of_the_new_name_is_never_overwritten() throws {
        let temp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let legacy = temp.appendingPathComponent("SnapBrief", isDirectory: true)
        let root = temp.appendingPathComponent("Snapik", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "old".write(
            to: legacy.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
        try "new".write(
            to: root.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)

        SnapikPaths.carryOverLegacyData(from: legacy, to: root)

        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("settings.json"), encoding: .utf8),
            "new")
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path))
    }

    func test_without_a_folder_of_the_old_name_nothing_is_created() throws {
        let temp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let legacy = temp.appendingPathComponent("SnapBrief", isDirectory: true)
        let root = temp.appendingPathComponent("Snapik", isDirectory: true)

        SnapikPaths.carryOverLegacyData(from: legacy, to: root)

        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func test_the_data_root_is_the_parent_of_the_sessions_directory() {
        XCTAssertEqual(
            SnapikPaths.defaultSessionsDirectory().deletingLastPathComponent().path,
            SnapikPaths.defaultDataRoot().path)
        XCTAssertEqual(SnapikPaths.legacyDataRoot().lastPathComponent, "SnapBrief")
        XCTAssertEqual(
            SnapikPaths.legacyDataRoot().deletingLastPathComponent().path,
            SnapikPaths.defaultDataRoot().deletingLastPathComponent().path)
    }
}
