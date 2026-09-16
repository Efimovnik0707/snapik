// Port of `tests/Snapik.Core.Tests/CaptureKindTests.cs`, SPEC-DELTA-4 §2.1, §6.
import Foundation
import XCTest

@testable import SnapikCore

final class CaptureKindTests: XCTestCase {
    private static let start = ISO8601Precise.makeUTC(
        year: 2026, month: 9, day: 15, hour: 12, minute: 0, second: 0)

    func test_A_capture_written_before_the_kind_existed_reads_as_a_region() throws {
        let legacy = """
            {
              "id": "7f3b6f2a-0b3a-4f5c-9e1d-2a6c8b4d1e05",
              "sourceImagePath": "source/capture.png",
              "pixelWidth": 1920,
              "pixelHeight": 1080,
              "dpiX": 96,
              "dpiY": 96,
              "title": "",
              "note": "",
              "annotations": [],
              "monitorCount": -4
            }
            """

        let capture = try SnapikJson.decoder.decode(
            CaptureItem.self, from: Data(legacy.utf8))

        XCTAssertEqual(.region, capture.kind)
        // A missing field and a negative one from a foreign file end in the same place, so nothing
        // downstream has to ask whether the number makes sense.
        XCTAssertEqual(0, capture.monitorCount)
    }

    func test_A_whole_screen_capture_keeps_its_kind_through_the_file() throws {
        var capture = CaptureItem.create(
            sourceImagePath: "source/screen.png", pixelWidth: 3840, pixelHeight: 1125)
        capture.kind = .fullscreen
        capture.monitorCount = 2

        let json = try SnapikJson.encoder.encode(capture)
        let restored = try SnapikJson.decoder.decode(CaptureItem.self, from: json)
        let written = try XCTUnwrap(
            JSONSerialization.jsonObject(with: json) as? [String: Any])

        XCTAssertEqual("fullscreen", written["kind"] as? String)
        XCTAssertEqual(.fullscreen, restored.kind)
        XCTAssertEqual(2, restored.monitorCount)
    }

    /// The clamp holds for a number set in memory too, not only for one read from a file.
    func test_A_count_of_monitors_below_zero_is_not_a_count() {
        var capture = CaptureItem.create(
            sourceImagePath: "source/screen.png", pixelWidth: 3840, pixelHeight: 1125)
        capture.monitorCount = -4

        XCTAssertEqual(0, capture.monitorCount)
    }

    func test_The_kind_of_a_capture_speaks_for_it_in_the_prompt() throws {
        var fullscreen = CaptureItem.create(
            sourceImagePath: "source/screen.png", pixelWidth: 3840, pixelHeight: 1125)
        fullscreen.kind = .fullscreen
        let region = CaptureItem.create(
            sourceImagePath: "source/region.png", pixelWidth: 800, pixelHeight: 600)
        let generator = PromptGenerator()

        let withFullscreen = try generator.generate(
            SessionOperations.addCapture(
                SnapikSession.create(nowUtc: Self.start), capture: fullscreen, nowUtc: Self.start))
        let withRegion = try generator.generate(
            SessionOperations.addCapture(
                SnapikSession.create(nowUtc: Self.start), capture: region, nowUtc: Self.start))

        XCTAssertEqual("Снимок A — весь экран.", withFullscreen)
        XCTAssertEqual("", withRegion)
    }

    /// An imported capture speaks through the name of the file it came from; the kind adds no word
    /// of its own to `prompt.md` (`PromptGenerator.cs:66`).
    func test_An_imported_capture_speaks_through_the_name_of_its_file() throws {
        var imported = CaptureItem.create(
            sourceImagePath: "source/import.png", pixelWidth: 800, pixelHeight: 600,
            title: "IMG_0512.png")
        imported.kind = .import

        let prompt = try PromptGenerator().generate(
            SessionOperations.addCapture(
                SnapikSession.create(nowUtc: Self.start), capture: imported, nowUtc: Self.start))

        XCTAssertEqual("Снимок A — IMG_0512.png.", prompt)
    }
}
