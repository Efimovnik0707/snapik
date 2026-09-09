// Port of `SmokeTestRunner.cs`, SPEC §8.4.
import AppKit
import Foundation
import SnapBriefCore

/// Minimal `NSApplicationDelegate` driving `--smoke-test` (`main.swift`): `SmokeTestRunner.run`
/// awaits `@MainActor` work (`OverlayEditorController`, `HotkeySettingsWindowController`), which
/// needs a live main run loop pumping `DispatchQueue.main` — a synchronous
/// `DispatchSemaphore.wait()` on the same thread would starve it. So the whole run happens inside
/// a real `NSApplication.run()`, kicked off from `applicationDidFinishLaunching`, exiting the
/// process with the matching code when done.
final class SmokeTestAppDelegate: NSObject, NSApplicationDelegate {
    private let options: CommandLineOptions

    init(options: CommandLineOptions) {
        self.options = options
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            let result = await SmokeTestRunner.run(options: options)
            exit(result ? 0 : 1)
        }
    }
}

enum SmokeTestRunner {
    static func run(options: CommandLineOptions) async -> Bool {
        var report: [String] = []
        var overallSuccess = true

        func check(_ name: String, _ condition: Bool) {
            report.append("\(condition ? "OK" : "FAIL") \(name)")
            overallSuccess = overallSuccess && condition
        }

        let usedExplicitRoot = options.dataDirectory != nil
        let root =
            options.dataDirectory
            ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("SnapBrief", isDirectory: true)
                .appendingPathComponent("smoke-\(SBGuid().digitsLowercase)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let workspace = SessionWorkspace(dataDirectory: root)

        // 1. Settings round-trip with every non-default value (SPEC §8.4 point 2).
        var custom = HotkeySettings(captureId: "custom:6:75", pasteId: HotkeySettings.default.pasteId)
        custom.captureEnabled = false
        custom.fullscreenSaveEnabled = true
        custom.fullscreenSaveId = "custom:4:44"
        custom.rememberRegion = true
        custom.captureCursor = true
        custom.showNotifications = false
        custom.saveFormat = "jpeg"
        custom.jpegQuality = 73
        custom.saveDirectory = root.path
        custom.language = "en"
        let customPath = root.appendingPathComponent("custom-hotkey-smoke.json")
        do {
            try custom.save(path: customPath)
        } catch {
            check("settings save", false)
        }
        let restored = HotkeySettings.load(path: customPath)
        let fullscreenIdentifier = HotkeyIdentifier.parse(restored.fullscreenSaveId)
        check("settings round-trip", restored == custom && fullscreenIdentifier.windowsVirtualKey == 44)

        // 2. Hotkey id parsing/fallback (SPEC §8.4 point 4).
        let printScreen = HotkeyIdentifier.parse("print-screen")
        let pause = HotkeyIdentifier.parse("custom:0:19")
        let fallback = HotkeyIdentifier.parse("custom:999:13")
        check(
            "hotkey id parsing",
            printScreen.windowsVirtualKey == 0x2C && pause.windowsVirtualKey == 0x13
                && pause.label == "Pause / Break" && fallback.id == HotkeyIdentifier.fallback.id)

        // 3. Settings window sizing/translation (point 3) and editor-internal probes for blur
        // preview, resize handles, and the comment-chip affordance (points 6, 9, 10) — the only
        // things that need `OverlayEditorController`'s `@MainActor` test hooks, run over an
        // isolated workspace so they never interact with the fixture created in step 5 below.
        let editorProbeRoot = root.appendingPathComponent("editor-probe", isDirectory: true)
        let editorProbeOptions = CommandLineOptions.parse(arguments: ["--data-dir", editorProbeRoot.path], environment: [:])
        let editorProbe = await MainActor.run { () -> EditorProbeResult in
            var result = EditorProbeResult()

            let probeCoordinator = AppCoordinator(options: editorProbeOptions)
            let settingsController = HotkeySettingsWindowController(coordinator: probeCoordinator)
            result.settingsSizeOk = settingsController.window?.frame.size == NSSize(width: 530, height: 480)
            result.translationOk =
                MacUiText.text("Настройки", language: "en") == "Settings"
                && MacUiText.text("Settings", language: "ru") == "Настройки"

            guard let frame = try? DemoSessionFactory.syntheticDesktopFrame() else { return result }
            let context = EditorWorkspaceContext(
                session: probeCoordinator.workspace.session, sessionDirectory: probeCoordinator.workspace.sessionDirectory,
                assetStore: probeCoordinator.workspace.assetStore, nextCaptureIndex: 0,
                regionPath: probeCoordinator.workspace.regionPath)
            let controller = OverlayEditorController(
                frame: frame, workspace: context, settings: HotkeySettings.default, language: "ru")
            controller.present()

            result.regionSelectionOk = controller.smokeSelectRegion(CGRect(x: 100, y: 100, width: 800, height: 600))
            if result.regionSelectionOk {
                result.blurPreviewOk = controller.smokeVerifyBlurPreview()
                result.resizeHandleOk = controller.smokeRunCaptureResizeProbe()
                result.noteAffordanceOk = controller.smokeRunNoteAffordanceProbe()
                result.rectangleCreationOk =
                    controller.smokeCreateRectangle(CGRect(x: 20, y: 20, width: 200, height: 150), note: "Проверка ручки") != nil
            }
            controller.close()
            return result
        }
        check("settings window 530x480", editorProbe.settingsSizeOk)
        check("settings translation round-trip", editorProbe.translationOk)
        check("editor region selection probe", editorProbe.regionSelectionOk)
        check("editor blur preview differs (point 6)", editorProbe.blurPreviewOk)
        check("editor resize handle probe (point 9)", editorProbe.resizeHandleOk)
        check("editor note affordance probe (point 10)", editorProbe.noteAffordanceOk)
        check("editor rectangle creation", editorProbe.rectangleCreationOk)
        // `editorProbeRoot` lives under `root` and is swept up by the final cleanup below.

        // 4. Three captures 1920x1080 (SPEC §8.4 point 5): A — demo image at 144 DPI with an arrow,
        // B — demo image with a rectangle, C — an 8x8 checkerboard with an opaque redaction *and*
        // a blur region (so point 12's blur/redaction pixel checks below have something to bite
        // into) plus a capture-level note.
        // R4 fix: an asymmetric marker on capture A's top 4 rows (a color that appears nowhere
        // else in the demo image) so the pixel checks in point 12 below can catch a vertical flip
        // that a same-position `pixelsEqual` comparison against the unmarked source could miss.
        let flipMarkerColor = NSColor(hex: "#FF00FF")
        let annotationNotes = ["Увеличить кнопку", "Перенести пункт выше", "Уточнить подпись"]
        var captures: [CaptureItem] = []
        for index in 0..<3 {
            let image: CGImage
            do {
                if index == 2 {
                    image = try makeCheckerboardImage(width: 1920, height: 1080)
                } else if index == 0 {
                    let demoImage = try await DemoSessionFactory.renderDemoImage(index: index, width: 1920, height: 1080)
                    image = try markTopRows(of: demoImage, color: flipMarkerColor)
                } else {
                    image = try await DemoSessionFactory.renderDemoImage(index: index, width: 1920, height: 1080)
                }
            } catch {
                check("capture \(index) render", false)
                continue
            }
            guard let data = ImageCodec.encode(image, format: .png) else {
                check("capture \(index) encode", false)
                continue
            }
            do {
                var capture = try await workspace.addCapture(
                    pngData: data, pixelWidth: image.width, pixelHeight: image.height,
                    dpiX: index == 0 ? 144 : 96, dpiY: index == 0 ? 144 : 96,
                    note: index == 2 ? "Текст обрезается" : nil)
                if index == 2 {
                    // Anchored at the rect's bottom-left corner (points ordered high-Y, low-Y) so
                    // its number label (floated just above the anchor, SPEC §4.5) actually falls
                    // inside the black redaction rectangle — see point 12's label-pixel check.
                    let redaction = AnnotationItem.create(
                        kind: .redaction,
                        points: [NormalizedPoint(0.55, 0.7), NormalizedPoint(0.75, 0.5)],
                        strokeColor: "#315CF5", thickness: 6, note: annotationNotes[2])
                    let blur = AnnotationItem.create(
                        kind: .blur,
                        points: [NormalizedPoint(0.15, 0.15), NormalizedPoint(0.35, 0.35)],
                        strokeColor: "#315CF5", thickness: 6, note: "Данные размыты")
                    capture.annotations.append(redaction)
                    capture.annotations.append(blur)
                } else {
                    let annotation = AnnotationItem.create(
                        kind: index == 1 ? .rectangle : .arrow,
                        points: [NormalizedPoint(0.5, 0.5), NormalizedPoint(0.7, 0.7)],
                        strokeColor: "#315CF5", thickness: 6, note: annotationNotes[index])
                    capture.annotations.append(annotation)
                }
                try workspace.replaceCapture(capture)
                captures.append(capture)
            } catch {
                check("capture \(index) create", false)
            }
        }
        check("captures created", captures.count == 3)

        // 5. PNG/JPEG encode/decode round trip (SPEC §8.4 point 7).
        if let first = captures.first {
            let sourceURL = workspace.sessionDirectory.appendingPathComponent(first.sourceImagePath)
            if let sourceImage = ImageCodec.loadImage(at: sourceURL) {
                let pngOk = ImageCodec.encode(sourceImage, format: .png) != nil
                let jpegData = ImageCodec.encode(sourceImage, format: .jpeg(quality: 73))
                check("png/jpeg round trip", pngOk && jpegData != nil && ImageCodec.decodePNG(ImageCodec.encode(sourceImage, format: .png) ?? Data()) != nil)
            } else {
                check("png/jpeg round trip", false)
            }
        } else {
            check("png/jpeg round trip", false)
        }

        // 6. Export preparation + prompt/note-count/label/pixel checks (SPEC §8.4 points 8, 11, 12).
        var capturedExport: PreparedExport?
        do {
            let export = try await workspace.prepareExport(renderer: ExportImageRenderer())
            capturedExport = export
            let paths = export.imagePathsInOrder()
            check("export produced 3 existing files", paths.count == 3 && paths.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })

            let promptOk =
                export.manifest.promptText.contains("Увеличить кнопку")
                && export.manifest.promptText.contains("Снимок C")
                && export.manifest.promptText.contains("C1: Уточнить подпись")
            check("export prompt text", promptOk)

            // 1 capture note ("Текст обрезается") + 4 annotation notes (arrow, rectangle,
            // redaction, blur).
            check("export note count", export.manifest.noteCount == 5)

            // Point 11: the exported PNG for capture A's first (and only) noted annotation is
            // labeled A1, and its bytes are non-empty.
            if let captureA = captures.first {
                let labeled = CaptureLabels.forNotedAnnotations(captureLabel: "A", capture: captureA)
                let labelOk = labeled.first?.displayLabel == "A1"
                let exportedBytesOk = paths.first.flatMap { FileManager.default.contents(atPath: $0.path) }.map { !$0.isEmpty } ?? false
                check("export label A1 with non-empty bytes", labelOk && exportedBytesOk)
            } else {
                check("export label A1 with non-empty bytes", false)
            }

            // Point 12 (mandatory on macOS): pixel-level checks against the rendered export PNGs.
            if paths.count == 3, captures.count == 3,
                let sourceA = ImageCodec.loadImage(at: workspace.sessionDirectory.appendingPathComponent(captures[0].sourceImagePath)),
                let exportA = ImageCodec.loadImage(at: paths[0]),
                let sourceC = ImageCodec.loadImage(at: workspace.sessionDirectory.appendingPathComponent(captures[2].sourceImagePath)),
                let exportC = ImageCodec.loadImage(at: paths[2])
            {
                check("export dimensions 1920x1128", [exportA, exportC].allSatisfy { $0.width == 1920 && $0.height == 1128 })
                // Content starts right below the 48px header; the far corner is untouched by any
                // annotation on capture A, so it must survive unchanged into the export.
                check("export corner pixel matches source", pixelsEqual(sourceA, ax: 0, ay: 0, exportA, bx: 0, by: 48))
                // R4 fix: direct-color checks against the asymmetric top marker (finding R4) — a
                // vertical flip would either move the marker away from row 48 or leave it visible
                // at the bottom instead of only the top.
                // Diagnostics for the flip-marker checks (printed in the report so CI logs show the
                // actual colours when a check fails).
                report.append("INFO source(0,0)=\(describeColor(colorAt(sourceA, x: 0, y: 0))) source(0,1079)=\(describeColor(colorAt(sourceA, x: 0, y: 1079))) export(0,48)=\(describeColor(colorAt(exportA, x: 0, y: 48))) export(1919,48)=\(describeColor(colorAt(exportA, x: 1919, y: 48))) export(0,1127)=\(describeColor(colorAt(exportA, x: 0, y: 1127))) sourceInfo=\(sourceA.bitsPerPixel)/\(sourceA.bitmapInfo.rawValue)")
                check("export marker row matches marker color", pixelColorMatches(exportA, x: 0, y: 48, color: flipMarkerColor))
                check("export bottom content row is not the marker color", !pixelColorMatches(exportA, x: 0, y: 1127, color: flipMarkerColor))
                // A point well inside the redaction rectangle, away from its number label.
                check("export redaction pixel opaque black", pixelIsApproximatelyBlack(exportC, x: 1300, y: 648))
                // A checkerboard corner inside the blur rectangle: blurring must mix it with its
                // (differently colored) neighbors.
                check("export blur pixel differs from source", pixelsDiffer(sourceC, ax: 480, ay: 270, exportC, bx: 480, by: 318))
                // A point inside both the C1 label's circle and the black redaction rectangle.
                check("export label pixel light over black", pixelIsLight(exportC, x: 1064, y: 783))
            } else {
                check("export pixel checks", false)
            }
        } catch {
            check("export prepare", false)
        }

        // 7. Session rotation leaves old files in place (SPEC §8.4 point 13).
        let previousSessionId = workspace.session.id
        let previousDirectory = workspace.sessionDirectory
        do {
            try await workspace.startNewSession()
            let restartedWorkspace = SessionWorkspace(dataDirectory: root)
            let reloaded = await restartedWorkspace.loadCurrent()
            check(
                "session rotation persists old session",
                workspace.session.id != previousSessionId
                    && reloaded
                    && restartedWorkspace.session.id == workspace.session.id
                    && restartedWorkspace.session.captures.isEmpty
                    && FileManager.default.fileExists(atPath: previousDirectory.appendingPathComponent("session.json").path))
        } catch {
            check("session rotation", false)
        }

        // 8. Result file (SPEC §8.4 point 14).
        let resultPath = root.appendingPathComponent("smoke-test-result.json")
        let resultBody: [String: Any] = [
            "success": overallSuccess,
            "report": report,
            "exportId": capturedExport?.manifest.exportId.description ?? "",
            "captureCount": capturedExport?.manifest.captureCount ?? 0,
            "noteCount": capturedExport?.manifest.noteCount ?? 0,
            "imagePaths": capturedExport?.imagePathsInOrder().map(\.path) ?? [],
            "promptText": capturedExport?.manifest.promptText ?? "",
        ]
        if let data = try? JSONSerialization.data(withJSONObject: resultBody, options: [.prettyPrinted]) {
            try? data.write(to: resultPath)
        }

        for line in report { print(line) }
        print(overallSuccess ? "OK overall" : "FAIL overall")

        if overallSuccess && !usedExplicitRoot {
            try? FileManager.default.removeItem(at: root)
        }

        return overallSuccess
    }

    // MARK: - Editor probe (SPEC §8.4 points 3, 6, 9, 10)

    private struct EditorProbeResult {
        var settingsSizeOk = false
        var translationOk = false
        var regionSelectionOk = false
        var blurPreviewOk = false
        var resizeHandleOk = false
        var noteAffordanceOk = false
        var rectangleCreationOk = false
    }

    // MARK: - Pixel helpers (SPEC §8.4 point 12)

    private static func describeColor(_ color: NSColor?) -> String {
        guard let color else { return "nil" }
        return String(format: "#%02X%02X%02X", Int((color.redComponent * 255).rounded()), Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()))
    }

    private static func colorAt(_ image: CGImage, x: Int, y: Int) -> NSColor? {
        guard x >= 0, y >= 0, x < image.width, y < image.height else { return nil }
        return NSBitmapImageRep(cgImage: image).colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
    }

    private static func pixelIsApproximatelyBlack(_ image: CGImage, x: Int, y: Int) -> Bool {
        guard let color = colorAt(image, x: x, y: y) else { return false }
        return color.redComponent < 0.05 && color.greenComponent < 0.05 && color.blueComponent < 0.05 && color.alphaComponent > 0.9
    }

    private static func pixelIsLight(_ image: CGImage, x: Int, y: Int) -> Bool {
        guard let color = colorAt(image, x: x, y: y) else { return false }
        return (color.redComponent + color.greenComponent + color.blueComponent) > 0.5
    }

    private static func pixelsDiffer(_ a: CGImage, ax: Int, ay: Int, _ b: CGImage, bx: Int, by: Int) -> Bool {
        guard let ca = colorAt(a, x: ax, y: ay), let cb = colorAt(b, x: bx, y: by) else { return false }
        return abs(ca.redComponent - cb.redComponent) > 0.02
            || abs(ca.greenComponent - cb.greenComponent) > 0.02
            || abs(ca.blueComponent - cb.blueComponent) > 0.02
    }

    private static func pixelsEqual(_ a: CGImage, ax: Int, ay: Int, _ b: CGImage, bx: Int, by: Int) -> Bool {
        !pixelsDiffer(a, ax: ax, ay: ay, b, bx: bx, by: by)
    }

    /// R4 fix: direct comparison against a known `NSColor`, used for the flip-marker checks —
    /// unlike `pixelsEqual`/`pixelsDiffer` this doesn't need a second image/coordinate at all.
    private static func pixelColorMatches(_ image: CGImage, x: Int, y: Int, color: NSColor, tolerance: CGFloat = 0.08) -> Bool {
        guard let pixel = colorAt(image, x: x, y: y), let reference = color.usingColorSpace(.deviceRGB) else { return false }
        return abs(pixel.redComponent - reference.redComponent) < tolerance
            && abs(pixel.greenComponent - reference.greenComponent) < tolerance
            && abs(pixel.blueComponent - reference.blueComponent) < tolerance
    }

    /// R4 fix: overwrites `image`'s top 4 rows (top-left-origin sense, matching `colorAt`'s
    /// convention: row 0 is the raw buffer's first row) with `color`, directly in the raw pixel
    /// buffer — deliberately sidesteps any `CGContext.draw(_:in:)` CTM/flip subtlety (see
    /// `AnnotationPainter.draw`'s own "unflip before drawing" comment for how easy that is to get
    /// backwards) since this helper only needs to produce an asymmetric marker for the pixel
    /// checks in point 12 below, not render anything. Assumes `image` is one of this file's own
    /// `CGImageAlphaInfo.premultipliedLast`, no-byte-order-flag, 8-bit-per-component contexts
    /// (`DemoSessionFactory.renderDemoImage`'s output, the only caller) — `[R, G, B, A]` per pixel
    /// in memory, 4 bytes per pixel.
    private static func markTopRows(of image: CGImage, color: NSColor) throws -> CGImage {
        guard
            let provider = image.dataProvider,
            let sourceData = provider.data,
            let rgb = color.usingColorSpace(.deviceRGB)
        else {
            throw SnapBriefError.invalidOperation("SmokeTestRunner: could not read the source bitmap to add the flip marker.")
        }
        let byteCount = CFDataGetLength(sourceData)
        var bytes = [UInt8](repeating: 0, count: byteCount)
        CFDataGetBytes(sourceData, CFRange(location: 0, length: byteCount), &bytes)

        let bytesPerRow = image.bytesPerRow
        let r = UInt8((rgb.redComponent * 255).rounded())
        let g = UInt8((rgb.greenComponent * 255).rounded())
        let b = UInt8((rgb.blueComponent * 255).rounded())
        let markedRows = min(4, image.height)
        for row in 0..<markedRows {
            var offset = row * bytesPerRow
            for _ in 0..<image.width where offset + 3 < byteCount {
                bytes[offset] = r
                bytes[offset + 1] = g
                bytes[offset + 2] = b
                bytes[offset + 3] = 255
                offset += 4
            }
        }

        guard
            let markedProvider = CGDataProvider(data: Data(bytes) as CFData),
            let marked = CGImage(
                width: image.width, height: image.height, bitsPerComponent: image.bitsPerComponent,
                bitsPerPixel: image.bitsPerPixel, bytesPerRow: bytesPerRow,
                space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: image.bitmapInfo,
                provider: markedProvider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else {
            throw SnapBriefError.invalidOperation("SmokeTestRunner: could not rebuild the flip-marked source bitmap.")
        }
        return marked
    }

    /// An `blocksPerSide`x`blocksPerSide` checkerboard, used as capture C's source image (SPEC
    /// §8.4 point 5: "синтетическая шахматка 8x8") — sharp block edges give the blur check
    /// something to visibly mix.
    private static func makeCheckerboardImage(width: Int, height: Int, blocksPerSide: Int = 8) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else {
            throw SnapBriefError.invalidOperation("SmokeTestRunner: could not allocate the checkerboard bitmap context.")
        }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        let blockWidth = CGFloat(width) / CGFloat(blocksPerSide)
        let blockHeight = CGFloat(height) / CGFloat(blocksPerSide)
        let light = NSColor(white: 0.94, alpha: 1).cgColor
        let dark = NSColor(white: 0.12, alpha: 1).cgColor
        for row in 0..<blocksPerSide {
            for col in 0..<blocksPerSide {
                context.setFillColor((row + col) % 2 == 0 ? light : dark)
                context.fill(CGRect(x: CGFloat(col) * blockWidth, y: CGFloat(row) * blockHeight, width: blockWidth, height: blockHeight))
            }
        }
        guard let image = context.makeImage() else {
            throw SnapBriefError.invalidOperation("SmokeTestRunner: could not render the checkerboard bitmap.")
        }
        return image
    }
}
