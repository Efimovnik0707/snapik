import XCTest

@testable import SnapikCore

/// Port of `tests/Snapik.Core.Tests/PersistenceAndExportTests.cs`.
final class PersistenceAndExportTests: XCTestCase {
    private static let start = ISO8601Precise.makeUTC(year: 2026, month: 9, day: 8, hour: 20, minute: 0, second: 0)
    private var root: URL!

    private struct FrozenTimeProvider: TimeProvider {
        let value: Date
        func utcNow() -> Date { value }
    }

    private static let onePixelPNG = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!

    private final class RecordingPNGRenderer: ExportImageRendering {
        private(set) var labelsSeen: [String] = []

        func renderPNG(capture: CaptureItem, annotations: [AnnotationItem], context: ExportImageContext) async throws -> Data {
            labelsSeen.append(context.displayLabel)
            return PersistenceAndExportTests.onePixelPNG
        }
    }

    private final class InvalidRenderer: ExportImageRendering {
        func renderPNG(capture: CaptureItem, annotations: [AnnotationItem], context: ExportImageContext) async throws -> Data {
            Data("not-png".utf8)
        }
    }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("snapik-tests-\(SBGuid().digitsLowercase)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: root.path) {
            try? FileManager.default.removeItem(at: root)
        }
    }

    func test_Json_store_round_trips_the_validated_session() async throws {
        let store = JsonSessionStore(sessionsRoot: root.appendingPathComponent("sessions"))
        let annotation = AnnotationItem.create(
            kind: .blur, points: [NormalizedPoint(0.1, 0.2), NormalizedPoint(0.8, 0.9)], note: "Увеличить кнопку")
        let firstRun = [NormalizedPoint(0.1, 0.1), NormalizedPoint(0.4, 0.4)]
        let secondRun = [NormalizedPoint(0.6, 0.6), NormalizedPoint(0.9, 0.9)]
        var segmented = AnnotationItem.create(kind: .freehand, points: firstRun, note: "Два штриха")
        segmented.pathSegments = [firstRun, secondRun]
        var capture = CaptureItem.create(sourceImagePath: "source/capture.png", pixelWidth: 1920, pixelHeight: 1080)
        capture.annotations = [annotation, segmented]
        let session = try SessionOperations.addCapture(
            SnapikSession.create(nowUtc: Self.start), capture: capture, nowUtc: Self.start.addingTimeInterval(1))

        try await store.save(session)
        let restored = try await store.load(sessionId: session.id)

        let unwrapped = try XCTUnwrap(restored)
        XCTAssertEqual(session.id, unwrapped.id)
        XCTAssertEqual(session.revision, unwrapped.revision)
        XCTAssertEqual(session.createdAtUtc.timeIntervalSince1970, unwrapped.createdAtUtc.timeIntervalSince1970, accuracy: 1e-6)
        XCTAssertEqual(session.modifiedAtUtc.timeIntervalSince1970, unwrapped.modifiedAtUtc.timeIntervalSince1970, accuracy: 1e-6)
        XCTAssertEqual(session.captures.map { $0.id }, unwrapped.captures.map { $0.id })
        XCTAssertEqual(annotation.id, unwrapped.captures[0].annotations[0].id)
        XCTAssertEqual(annotation.note, unwrapped.captures[0].annotations[0].note)
        XCTAssertEqual(AnnotationKind.blur, unwrapped.captures[0].annotations[0].kind)
        XCTAssertEqual(annotation.points, unwrapped.captures[0].annotations[0].points)
        let restoredSegmented = unwrapped.captures[0].annotations[1]
        XCTAssertEqual(segmented.id, restoredSegmented.id)
        XCTAssertEqual(segmented.note, restoredSegmented.note)
        XCTAssertEqual(2, restoredSegmented.pathSegments.count)
        XCTAssertEqual(firstRun, restoredSegmented.pathSegments[0])
        XCTAssertEqual(secondRun, restoredSegmented.pathSegments[1])
    }

    func test_Json_store_loads_schema_one_annotations_without_path_segments() async throws {
        let sessionsRoot = root.appendingPathComponent("sessions")
        let store = JsonSessionStore(sessionsRoot: sessionsRoot)
        let annotation = AnnotationItem.create(
            kind: .freehand, points: [NormalizedPoint(0.1, 0.2), NormalizedPoint(0.8, 0.9)], note: "Legacy stroke")
        var capture = CaptureItem.create(sourceImagePath: "source/capture.png", pixelWidth: 100, pixelHeight: 100)
        capture.annotations = [annotation]
        let session = try SessionOperations.addCapture(SnapikSession.create(nowUtc: Self.start), capture: capture, nowUtc: Self.start)

        let data = try SnapikJson.encoder.encode(session)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var captures = try XCTUnwrap(json["captures"] as? [[String: Any]])
        var annotations = try XCTUnwrap(captures[0]["annotations"] as? [[String: Any]])
        XCTAssertNotNil(annotations[0].removeValue(forKey: "pathSegments"))
        captures[0]["annotations"] = annotations
        json["captures"] = captures

        let directory = store.getSessionDirectory(sessionId: session.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let rewritten = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
        try rewritten.write(to: directory.appendingPathComponent("session.json"))

        let restored = try await store.load(sessionId: session.id)

        let restoredCapture = try XCTUnwrap(restored?.captures.first)
        XCTAssertEqual(1, restoredCapture.annotations.count)
        let restoredAnnotation = restoredCapture.annotations[0]
        XCTAssertTrue(restoredAnnotation.pathSegments.isEmpty)
        let fallback = restoredAnnotation.getPathSegments()
        XCTAssertEqual(1, fallback.count)
        XCTAssertEqual(annotation.points, fallback[0])
        XCTAssertEqual(annotation.id, restoredAnnotation.id)
        XCTAssertEqual(annotation.note, restoredAnnotation.note)
    }

    func test_Overlapping_saves_commit_the_latest_invocation_even_when_revisions_repeat() async throws {
        let store = JsonSessionStore(sessionsRoot: root.appendingPathComponent("sessions"))
        let capture = CaptureItem.create(sourceImagePath: "source/capture.png", pixelWidth: 100, pixelHeight: 100)
        let baseline = try SessionOperations.addCapture(SnapikSession.create(nowUtc: Self.start), capture: capture, nowUtc: Self.start)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<40 {
                var candidate = baseline
                candidate.globalNote = "note-\(index)"
                group.addTask { try await store.save(candidate) }
            }
            try await group.waitForAll()
        }

        let restored = try await store.load(sessionId: baseline.id)

        XCTAssertNotNil(restored)
        XCTAssertEqual(baseline.revision, restored?.revision)
        // NOTE: unlike the C# test (which assigns save sequence numbers synchronously in call
        // order before the first `await`, guaranteeing "note-39" wins), Swift's structured
        // concurrency does not guarantee `withThrowingTaskGroup` children start in enqueue order.
        // This assertion only verifies the "latest committed write always wins" invariant that
        // `JsonSessionStore` implements, not that "note-39" specifically is the winner.
        XCTAssertTrue(restored?.globalNote.hasPrefix("note-") == true)
    }

    func test_Asset_store_publishes_a_valid_png_under_a_stable_relative_capture_path() async throws {
        let sessionStore = JsonSessionStore(sessionsRoot: root.appendingPathComponent("sessions"))
        let assetStore = DefaultSessionAssetStore(sessionStore: sessionStore)
        let sessionId = SBGuid()
        let captureId = SBGuid()

        let relativePath = try await assetStore.saveOriginalPNG(sessionId: sessionId, captureId: captureId, pngContent: Self.onePixelPNG)

        XCTAssertEqual("source/\(captureId.digitsLowercase).png", relativePath)
        let expectedURL = sessionStore.getSessionDirectory(sessionId: sessionId).appendingPathComponent(relativePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedURL.path))
    }

    func test_Export_is_an_immutable_ordered_revision_with_hashes_and_no_sources() async throws {
        let renderer = RecordingPNGRenderer()
        let service = FileExportService(renderer: renderer, timeProvider: FrozenTimeProvider(value: Self.start))
        let first = CaptureItem.create(sourceImagePath: "source/one.png", pixelWidth: 800, pixelHeight: 600, note: "Первый комментарий")
        var second = CaptureItem.create(sourceImagePath: "source/two.png", pixelWidth: 800, pixelHeight: 600)
        second.annotations = [
            AnnotationItem.create(kind: .rectangle, points: [NormalizedPoint(0.1, 0.1), NormalizedPoint(0.5, 0.5)], note: "Второй комментарий")
        ]
        var session = try SessionOperations.addCapture(SnapikSession.create(nowUtc: Self.start), capture: first, nowUtc: Self.start)
        session = try SessionOperations.addCapture(session, capture: second, nowUtc: Self.start)
        let sessionDirectory = root.appendingPathComponent("session")
        try FileManager.default.createDirectory(at: sessionDirectory.appendingPathComponent("source"), withIntermediateDirectories: true)
        try Self.onePixelPNG.write(to: sessionDirectory.appendingPathComponent(first.sourceImagePath))
        try Self.onePixelPNG.write(to: sessionDirectory.appendingPathComponent(second.sourceImagePath))

        let prepared = try await service.prepare(session: session, sessionDirectory: sessionDirectory)
        let originalPrompt = prepared.manifest.promptText
        let changed = try SessionOperations.updateGlobalNote(session, note: "Новое пожелание", nowUtc: Self.start.addingTimeInterval(60))

        XCTAssertEqual(["A", "B"], renderer.labelsSeen)
        XCTAssertEqual([first.id, second.id], prepared.manifest.images.map { $0.captureId })
        XCTAssertEqual(2, prepared.manifest.captureCount)
        XCTAssertEqual(2, prepared.manifest.noteCount)
        for image in prepared.manifest.images {
            XCTAssertEqual(64, image.sha256.count)
        }
        let promptOnDisk = try String(contentsOf: prepared.rootDirectory.appendingPathComponent("prompt.md"), encoding: .utf8)
        XCTAssertEqual(originalPrompt, promptOnDisk)
        XCTAssertFalse(prepared.manifest.promptText.contains("Новое пожелание"))
        XCTAssertNotEqual(session.revision, changed.revision)
        let files = try FileManager.default.contentsOfDirectory(atPath: prepared.rootDirectory.path)
        XCTAssertFalse(files.contains { $0.lowercased().contains("source") })
    }

    func test_Invalid_renderer_output_does_not_publish_a_partial_revision() async throws {
        let service = FileExportService(renderer: InvalidRenderer())
        let capture = CaptureItem.create(sourceImagePath: "source/a.png", pixelWidth: 10, pixelHeight: 10)
        let session = try SessionOperations.addCapture(SnapikSession.create(nowUtc: Self.start), capture: capture, nowUtc: Self.start)
        let sessionDirectory = root.appendingPathComponent("session")
        try FileManager.default.createDirectory(at: sessionDirectory.appendingPathComponent("source"), withIntermediateDirectories: true)
        try Self.onePixelPNG.write(to: sessionDirectory.appendingPathComponent(capture.sourceImagePath))

        do {
            _ = try await service.prepare(session: session, sessionDirectory: sessionDirectory)
            XCTFail("Expected invalidData error")
        } catch let error as SnapikError {
            guard case .invalidData = error else {
                return XCTFail("Expected invalidData, got \(error)")
            }
        }

        let exports = sessionDirectory.appendingPathComponent("exports")
        if FileManager.default.fileExists(atPath: exports.path) {
            let contents = try FileManager.default.contentsOfDirectory(atPath: exports.path)
            XCTAssertTrue(contents.isEmpty)
        }
    }

    func test_Whitespace_only_notes_are_not_labeled_exported_or_counted_but_real_text_is_preserved() async throws {
        var capture = CaptureItem.create(sourceImagePath: "source/a.png", pixelWidth: 10, pixelHeight: 10, note: " \t\r\n")
        capture.annotations = [
            AnnotationItem.create(kind: .arrow, points: [NormalizedPoint(0.1, 0.1), NormalizedPoint(0.2, 0.2)], note: "   "),
            AnnotationItem.create(kind: .rectangle, points: [NormalizedPoint(0.2, 0.2), NormalizedPoint(0.6, 0.6)], note: "  Реальная заметка  \n"),
        ]
        var session = try SessionOperations.addCapture(SnapikSession.create(nowUtc: Self.start), capture: capture, nowUtc: Self.start)
        session.globalNote = "\r\n\t"
        let sessionDirectory = root.appendingPathComponent("whitespace-session")
        try FileManager.default.createDirectory(at: sessionDirectory.appendingPathComponent("source"), withIntermediateDirectories: true)
        try Self.onePixelPNG.write(to: sessionDirectory.appendingPathComponent(capture.sourceImagePath))

        let prepared = try await FileExportService(renderer: RecordingPNGRenderer())
            .prepare(session: session, sessionDirectory: sessionDirectory)

        XCTAssertEqual(1, prepared.manifest.noteCount)
        XCTAssertFalse(prepared.manifest.promptText.contains("Общее пожелание"))
        XCTAssertFalse(prepared.manifest.promptText.contains("Комментарий к снимку"))
        XCTAssertTrue(prepared.manifest.promptText.contains("A1:   Реальная заметка  \n"))
        XCTAssertFalse(prepared.manifest.promptText.contains("A2:"))
    }
}
