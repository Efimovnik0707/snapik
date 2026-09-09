// Port of `LaunchOptions.Parse` argument-handling behavior, SPEC §1.19.
import Foundation
import XCTest
import SnapBriefCore

@testable import SnapBriefMac

final class CommandLineOptionsTests: XCTestCase {
    func test_flags_are_case_insensitive() {
        let options = CommandLineOptions.parse(arguments: ["--DEMO", "--Smoke-Test"], environment: [:])
        XCTAssertTrue(options.demo)
        XCTAssertTrue(options.smokeTest)
    }

    func test_data_dir_takes_the_last_occurrence() {
        let options = CommandLineOptions.parse(
            arguments: ["--data-dir", "/tmp/first", "--data-dir", "/tmp/second"], environment: [:])
        XCTAssertEqual(options.dataDirectory?.path, "/tmp/second")
    }

    func test_environment_variable_used_only_when_flag_absent() {
        let withFlag = CommandLineOptions.parse(
            arguments: ["--data-dir", "/tmp/flag"], environment: ["SNAPBRIEF_DATA_DIR": "/tmp/env"])
        XCTAssertEqual(withFlag.dataDirectory?.path, "/tmp/flag")

        let withoutFlag = CommandLineOptions.parse(arguments: [], environment: ["SNAPBRIEF_DATA_DIR": "/tmp/env"])
        XCTAssertEqual(withoutFlag.dataDirectory?.path, "/tmp/env")
    }

    func test_demo_without_data_dir_synthesizes_a_pid_scoped_temp_directory() {
        let options = CommandLineOptions.parse(arguments: ["--demo"], environment: [:])
        let expectedSuffix = "SnapBrief/demo-\(ProcessInfo.processInfo.processIdentifier)"
        XCTAssertTrue(options.dataDirectory?.path.hasSuffix(expectedSuffix) ?? false)
    }

    func test_no_flags_leaves_data_directory_nil() {
        let options = CommandLineOptions.parse(arguments: [], environment: [:])
        XCTAssertNil(options.dataDirectory)
    }

    func test_demo_screenshot_flag_is_parsed() {
        let options = CommandLineOptions.parse(arguments: ["--demo-screenshot", "/tmp/shots"], environment: [:])
        XCTAssertEqual(options.demoScreenshotDirectory?.path, "/tmp/shots")
    }

    func test_capture_test_flag_is_parsed() {
        let options = CommandLineOptions.parse(arguments: ["--capture-test", "/tmp/frame.png"], environment: [:])
        XCTAssertEqual(options.captureTestPath?.path, "/tmp/frame.png")
    }
}
