import XCTest
@testable import SnapBriefCore

final class PlaceholderTests: XCTestCase {
    func testSchema() { XCTAssertEqual(SnapBriefCoreInfo.schemaVersion, 1) }
}
