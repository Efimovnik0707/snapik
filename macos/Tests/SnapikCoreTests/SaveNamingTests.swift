// Port of `tests/Snapik.App.Imaging.Tests/SaveNamingTests.cs`, SPEC-DELTA-3 §6.
import XCTest

@testable import SnapikCore

final class SaveNamingTests: XCTestCase {
    func test_A_free_name_is_taken_as_it_is() {
        XCTAssertEqual(
            "Snapik-20260912-171827",
            SaveNaming.freeName("Snapik-20260912-171827", taken: { _ in false }))
    }

    func test_A_taken_name_gets_the_next_number() {
        let taken: Set<String> = ["package", "package-2"]

        XCTAssertEqual("package-2", SaveNaming.freeName("package", taken: { $0 == "package" }))
        XCTAssertEqual("package-3", SaveNaming.freeName("package", taken: { taken.contains($0) }))
    }

    func test_A_folder_where_every_name_is_taken_gives_nothing() {
        XCTAssertNil(SaveNaming.freeName("package", taken: { _ in true }))
    }

    func test_The_first_filter_line_starts_with_the_preferred_format() {
        for (saveFormat, expected) in [("png", "*.png;*.jpg;*.jpeg"), ("jpeg", "*.jpg;*.jpeg;*.png")] {
            let filter = SaveNaming.imageFilter(saveFormat: saveFormat, allSupportedCaption: "All supported")
            let parts = filter.split(separator: "|", omittingEmptySubsequences: false).map(String.init)

            XCTAssertEqual("All supported (\(expected))", parts[0])
            XCTAssertEqual(expected, parts[1])
            XCTAssertTrue(filter.hasSuffix("PNG (*.png)|*.png|JPEG (*.jpg;*.jpeg)|*.jpg;*.jpeg"), filter)
        }
    }
}
