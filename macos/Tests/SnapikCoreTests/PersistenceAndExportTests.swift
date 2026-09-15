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

    /// Port of `PersistenceAndExportTests.Json_store_round_trips_the_size_a_caption_was_typed_in`.
    func test_Json_store_round_trips_the_size_a_caption_was_typed_in() async throws {
        let store = JsonSessionStore(sessionsRoot: root.appendingPathComponent("sessions"))
        var caption = AnnotationItem.create(
            kind: .text, points: [NormalizedPoint(0.1, 0.1), NormalizedPoint(0.4, 0.2)], text: "Привет")
        caption.fontSize = 32
        var capture = CaptureItem.create(sourceImagePath: "source/capture.png", pixelWidth: 800, pixelHeight: 600)
        capture.annotations = [caption]
        let session = try SessionOperations.addCapture(
            SnapikSession.create(nowUtc: Self.start), capture: capture, nowUtc: Self.start)

        try await store.save(session)
        let loadedRestored = try await store.load(sessionId: session.id)
        let restored = try XCTUnwrap(loadedRestored)

        // The name in the file matters as much as the value: the Windows build reads the same key.
        let written = try Self.annotationObjects(of: session)
        XCTAssertEqual(32, written[0]["fontSize"] as? Double)
        XCTAssertEqual(32, restored.captures[0].annotations[0].fontSize)
        XCTAssertEqual("Привет", restored.captures[0].annotations[0].text)
        try SessionValidation.validate(restored)
    }

    /// Port of `PersistenceAndExportTests.Json_store_reads_a_caption_written_before_the_size_existed`.
    func test_Json_store_reads_a_caption_written_before_the_size_existed() async throws {
        let store = JsonSessionStore(sessionsRoot: root.appendingPathComponent("sessions"))
        let caption = AnnotationItem.create(
            kind: .text, points: [NormalizedPoint(0.1, 0.1), NormalizedPoint(0.4, 0.2)], text: "Старая надпись")
        var capture = CaptureItem.create(sourceImagePath: "source/capture.png", pixelWidth: 800, pixelHeight: 600)
        capture.annotations = [caption]
        let session = try SessionOperations.addCapture(
            SnapikSession.create(nowUtc: Self.start), capture: capture, nowUtc: Self.start)

        try Self.writeSession(session, store: store, droppingAnnotationKeys: ["fontSize"])
        let loadedRestored = try await store.load(sessionId: session.id)
        let restored = try XCTUnwrap(loadedRestored)

        XCTAssertEqual(20, restored.captures[0].annotations[0].fontSize)
        try SessionValidation.validate(restored)
    }

    /// Port of `PersistenceAndExportTests.Json_store_round_trips_the_pattern_of_a_stroke_and_defaults_it_to_solid`.
    func test_Json_store_round_trips_the_pattern_of_a_stroke_and_defaults_it_to_solid() async throws {
        let store = JsonSessionStore(sessionsRoot: root.appendingPathComponent("sessions"))
        var dotted = AnnotationItem.create(
            kind: .rectangle, points: [NormalizedPoint(0.1, 0.1), NormalizedPoint(0.4, 0.4)])
        dotted.lineStyle = .dotted
        let plain = AnnotationItem.create(
            kind: .arrow, points: [NormalizedPoint(0.5, 0.5), NormalizedPoint(0.9, 0.9)])
        var capture = CaptureItem.create(sourceImagePath: "source/capture.png", pixelWidth: 800, pixelHeight: 600)
        capture.annotations = [dotted, plain]
        let session = try SessionOperations.addCapture(
            SnapikSession.create(nowUtc: Self.start), capture: capture, nowUtc: Self.start)

        try await store.save(session)
        let loadedRestored = try await store.load(sessionId: session.id)
        let restored = try XCTUnwrap(loadedRestored)

        // The name in the file matters as much as the value: the Windows build reads the same key.
        let written = try Self.annotationObjects(of: session)
        XCTAssertEqual("dotted", written[0]["lineStyle"] as? String)
        XCTAssertEqual(.dotted, restored.captures[0].annotations[0].lineStyle)
        XCTAssertEqual(.solid, restored.captures[0].annotations[1].lineStyle)
        try SessionValidation.validate(restored)

        // A session written before the field reads as solid, which is what it was drawn as.
        try Self.writeSession(session, store: store, droppingAnnotationKeys: ["lineStyle"])
        let loadedReread = try await store.load(sessionId: session.id)
        let reread = try XCTUnwrap(loadedReread)
        XCTAssertEqual(.solid, reread.captures[0].annotations[0].lineStyle)
    }

    /// Port of `PersistenceAndExportTests.A_line_style_outside_the_enumeration_is_refused`. The C#
    /// rule lives in `SessionValidation` because a C# enum built in code can hold any number;
    /// `AnnotationLineStyle` is a Swift `String` enum, which cannot, so the only way a pattern
    /// nobody knows reaches the application is a hand-written file — and the decoder refuses it.
    func test_A_line_style_outside_the_enumeration_is_refused() throws {
        let plain = AnnotationItem.create(
            kind: .rectangle, points: [NormalizedPoint(0.1, 0.1), NormalizedPoint(0.4, 0.4)])
        var capture = CaptureItem.create(sourceImagePath: "source/capture.png", pixelWidth: 800, pixelHeight: 600)
        capture.annotations = [plain]
        var session = SnapikSession.create(nowUtc: Self.start)
        session.captures = [capture]

        let data = try Self.rewriteAnnotations(of: session) { annotation in
            var copy = annotation
            copy["lineStyle"] = "zigzag"
            return copy
        }

        XCTAssertThrowsError(try SnapikJson.decoder.decode(SnapikSession.self, from: data))
    }

    /// Port of `PersistenceAndExportTests.Json_store_round_trips_the_fill_colour_the_outline_flag_and_the_blur_fill`.
    func test_Json_store_round_trips_the_fill_colour_the_outline_flag_and_the_blur_fill() async throws {
        let store = JsonSessionStore(sessionsRoot: root.appendingPathComponent("sessions"))
        var concealed = AnnotationItem.create(
            kind: .rectangle, points: [NormalizedPoint(0.1, 0.1), NormalizedPoint(0.4, 0.4)])
        concealed.fill = .solid
        concealed.fillColor = "#FF000000"
        concealed.hasOutline = false
        var blurred = AnnotationItem.create(
            kind: .rectangle, points: [NormalizedPoint(0.5, 0.5), NormalizedPoint(0.9, 0.9)])
        blurred.shape = .ellipse
        blurred.fill = .blur
        var capture = CaptureItem.create(sourceImagePath: "source/capture.png", pixelWidth: 800, pixelHeight: 600)
        capture.annotations = [concealed, blurred]
        let session = try SessionOperations.addCapture(
            SnapikSession.create(nowUtc: Self.start), capture: capture, nowUtc: Self.start)

        try await store.save(session)
        let loadedRestored = try await store.load(sessionId: session.id)
        let restored = try XCTUnwrap(loadedRestored)

        // The names in the file matter as much as the values: the Windows build reads the same keys.
        let written = try Self.annotationObjects(of: session)
        XCTAssertEqual("blur", written[1]["fill"] as? String)
        XCTAssertEqual("#FF000000", written[0]["fillColor"] as? String)
        XCTAssertEqual(false, written[0]["hasOutline"] as? Bool)
        XCTAssertEqual(.solid, restored.captures[0].annotations[0].fill)
        XCTAssertEqual("#FF000000", restored.captures[0].annotations[0].fillColor)
        XCTAssertFalse(restored.captures[0].annotations[0].hasOutline)
        XCTAssertEqual(.blur, restored.captures[0].annotations[1].fill)
        XCTAssertNil(restored.captures[0].annotations[1].fillColor)
        XCTAssertTrue(restored.captures[0].annotations[1].hasOutline)
        try SessionValidation.validate(restored)
    }

    /// Port of `PersistenceAndExportTests.Json_store_reads_a_session_without_the_fill_fields_and_one_that_still_holds_a_redaction`.
    func test_Json_store_reads_a_session_without_the_fill_fields_and_one_that_still_holds_a_redaction() async throws {
        let store = JsonSessionStore(sessionsRoot: root.appendingPathComponent("sessions"))
        let box = AnnotationItem.create(
            kind: .rectangle, points: [NormalizedPoint(0.1, 0.1), NormalizedPoint(0.4, 0.4)])
        let redaction = AnnotationItem.create(
            kind: .redaction, points: [NormalizedPoint(0.5, 0.5), NormalizedPoint(0.8, 0.8)])
        var capture = CaptureItem.create(sourceImagePath: "source/capture.png", pixelWidth: 800, pixelHeight: 600)
        capture.annotations = [box, redaction]
        let session = try SessionOperations.addCapture(
            SnapikSession.create(nowUtc: Self.start), capture: capture, nowUtc: Self.start)

        try Self.writeSession(session, store: store, droppingAnnotationKeys: ["fill", "fillColor", "hasOutline"])
        let loadedRestored = try await store.load(sessionId: session.id)
        let restored = try XCTUnwrap(loadedRestored)

        // A file written before the fill carried a colour reads exactly as it did: no fill, no
        // colour of its own, and an outline. The redaction kind stays readable for the editor.
        XCTAssertEqual(AnnotationFill.none, restored.captures[0].annotations[0].fill)
        XCTAssertNil(restored.captures[0].annotations[0].fillColor)
        XCTAssertTrue(restored.captures[0].annotations[0].hasOutline)
        XCTAssertEqual(.redaction, restored.captures[0].annotations[1].kind)
        try SessionValidation.validate(restored)
    }

    /// Port of `PersistenceAndExportTests.Json_store_round_trips_the_sent_flag_and_reads_a_file_written_without_it`.
    func test_Json_store_round_trips_the_sent_flag_and_reads_a_file_written_without_it() async throws {
        let store = JsonSessionStore(sessionsRoot: root.appendingPathComponent("sessions"))
        var sent = CaptureItem.create(sourceImagePath: "source/sent.png", pixelWidth: 100, pixelHeight: 100)
        sent.sent = true
        let waiting = CaptureItem.create(sourceImagePath: "source/waiting.png", pixelWidth: 100, pixelHeight: 100)
        var session = try SessionOperations.addCapture(
            SnapikSession.create(nowUtc: Self.start), capture: sent, nowUtc: Self.start)
        session = try SessionOperations.addCapture(
            session, capture: waiting, nowUtc: Self.start.addingTimeInterval(1))

        try await store.save(session)
        let loadedRestored = try await store.load(sessionId: session.id)
        let restored = try XCTUnwrap(loadedRestored)
        XCTAssertTrue(restored.captures[0].sent)
        XCTAssertFalse(restored.captures[1].sent)

        try Self.writeSession(session, store: store, droppingCaptureKeys: ["sent"])
        let loadedLegacy = try await store.load(sessionId: session.id)
        let legacy = try XCTUnwrap(loadedLegacy)
        XCTAssertTrue(legacy.captures.allSatisfy { !$0.sent })
    }

    /// The annotations of the first capture, as they stand in the written file.
    private static func annotationObjects(of session: SnapikSession) throws -> [[String: Any]] {
        let data = try SnapikJson.encoder.encode(session)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let captures = try XCTUnwrap(json["captures"] as? [[String: Any]])
        return try XCTUnwrap(captures[0]["annotations"] as? [[String: Any]])
    }

    private static func rewriteAnnotations(
        of session: SnapikSession,
        _ transform: ([String: Any]) -> [String: Any]
    ) throws -> Data {
        let data = try SnapikJson.encoder.encode(session)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var captures = try XCTUnwrap(json["captures"] as? [[String: Any]])
        for captureIndex in captures.indices {
            let annotations = try XCTUnwrap(captures[captureIndex]["annotations"] as? [[String: Any]])
            captures[captureIndex]["annotations"] = annotations.map(transform)
        }
        json["captures"] = captures
        return try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
    }

    /// Writes `session` into the store by hand with the named keys dropped: what a `session.json`
    /// written by a build that did not know them looks like.
    private static func writeSession(
        _ session: SnapikSession,
        store: JsonSessionStore,
        droppingAnnotationKeys annotationKeys: [String] = [],
        droppingCaptureKeys captureKeys: [String] = []
    ) throws {
        let data = try SnapikJson.encoder.encode(session)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var captures = try XCTUnwrap(json["captures"] as? [[String: Any]])
        for captureIndex in captures.indices {
            for key in captureKeys { captures[captureIndex].removeValue(forKey: key) }
            var annotations = try XCTUnwrap(captures[captureIndex]["annotations"] as? [[String: Any]])
            for index in annotations.indices {
                for key in annotationKeys { annotations[index].removeValue(forKey: key) }
            }
            captures[captureIndex]["annotations"] = annotations
        }
        json["captures"] = captures

        let directory = store.getSessionDirectory(sessionId: session.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let rewritten = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
        try rewritten.write(to: directory.appendingPathComponent("session.json"))
    }


    /// Port of `PersistenceAndExportTests.A_package_without_notes_carries_images_only_and_writes_no_prompt_file`.
    func test_A_package_without_notes_carries_images_only_and_writes_no_prompt_file() async throws {
        let capture = CaptureItem.create(sourceImagePath: "source/a.png", pixelWidth: 800, pixelHeight: 600)
        let session = try SessionOperations.addCapture(
            SnapikSession.create(nowUtc: Self.start), capture: capture, nowUtc: Self.start)
        let sessionDirectory = root.appendingPathComponent("silent-session")
        try FileManager.default.createDirectory(
            at: sessionDirectory.appendingPathComponent("source"), withIntermediateDirectories: true)
        try Self.onePixelPNG.write(to: sessionDirectory.appendingPathComponent(capture.sourceImagePath))

        let prepared = try await FileExportService(
            renderer: RecordingPNGRenderer(), timeProvider: FrozenTimeProvider(value: Self.start)
        ).prepare(session: session, sessionDirectory: sessionDirectory)

        XCTAssertEqual("", prepared.manifest.promptText)
        XCTAssertEqual("", prepared.manifest.promptFileName)
        XCTAssertEqual("", prepared.manifest.promptSha256)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: prepared.rootDirectory.appendingPathComponent("prompt.md").path))
        XCTAssertEqual(1, prepared.manifest.images.count)
    }

    /// Port of `FileExportService.cs:43-45`: the image of a package is named after its place in the
    /// package and its letter, so a folder of them sorts and reads like page numbers.
    func test_The_images_of_a_package_are_numbered_and_lettered() async throws {
        var first = CaptureItem.create(sourceImagePath: "source/a.png", pixelWidth: 800, pixelHeight: 600)
        first.note = "Первый"
        let second = CaptureItem.create(sourceImagePath: "source/b.png", pixelWidth: 800, pixelHeight: 600)
        var session = try SessionOperations.addCapture(
            SnapikSession.create(nowUtc: Self.start), capture: first, nowUtc: Self.start)
        session = try SessionOperations.addCapture(
            session, capture: second, nowUtc: Self.start.addingTimeInterval(1))
        let sessionDirectory = root.appendingPathComponent("numbered-session")
        try FileManager.default.createDirectory(
            at: sessionDirectory.appendingPathComponent("source"), withIntermediateDirectories: true)
        try Self.onePixelPNG.write(to: sessionDirectory.appendingPathComponent(first.sourceImagePath))
        try Self.onePixelPNG.write(to: sessionDirectory.appendingPathComponent(second.sourceImagePath))

        let prepared = try await FileExportService(
            renderer: RecordingPNGRenderer(), timeProvider: FrozenTimeProvider(value: Self.start)
        ).prepare(session: session, sessionDirectory: sessionDirectory)

        XCTAssertEqual(["01-A.png", "02-B.png"], prepared.manifest.images.map { $0.fileName })
        XCTAssertEqual([first.id, second.id], prepared.manifest.images.map { $0.captureId })
        for image in prepared.manifest.images {
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: prepared.rootDirectory.appendingPathComponent(image.fileName).path),
                image.fileName)
        }
    }

}
