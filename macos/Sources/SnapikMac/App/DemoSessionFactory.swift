// Port of `SeedDemoAsync` (`EdgeStackWindow.xaml.cs:690-708`) and
// `SessionWorkspace.CreateDemoBitmap` (`SessionWorkspace.cs:157-177`), SPEC §1.19.
import AppKit
import SnapikCore

@MainActor
enum DemoSessionFactory {
    /// Port of `SeedDemoAsync`: three synthetic 1280x720 captures labeled A/B/C — A gets a
    /// rectangle annotation, B an arrow, both noted; C gets a capture-level note only. Also sets
    /// the (UI-hidden, but still persisted) legacy global note.
    static func seedDemoSession(in workspace: SessionWorkspace) async throws {
        for index in 0..<3 {
            let image = try renderDemoImage(index: index)
            guard let data = ImageCodec.encode(image, format: .png) else {
                throw SnapikError.invalidData("Could not encode demo capture \(index).")
            }

            var capture = try await workspace.addCapture(
                pngData: data,
                pixelWidth: image.width,
                pixelHeight: image.height,
                note: index == 2 ? "Текст обрезается" : nil)

            if index < 2 {
                let annotation = AnnotationItem.create(
                    kind: index == 0 ? .rectangle : .arrow,
                    points: [
                        NormalizedPoint(650.0 / 1280.0, 360.0 / 720.0),
                        NormalizedPoint(980.0 / 1280.0, 520.0 / 720.0),
                    ],
                    strokeColor: "#2F8CFF",
                    thickness: 4,
                    note: index == 0 ? "Увеличить кнопку" : "Перенести пункт выше",
                    arrowStyle: index == 1 ? "curved" : "straight")
                capture.annotations.append(annotation)
                if index == 0 {
                    // SPEC-DELTA-2B.md §F: seed one linked comment (SPEC-DELTA-2.md §1.3) tied to
                    // capture A's rectangle annotation, so the demo session exercises the new
                    // comment/arrow-style fields end to end.
                    let comment = AnnotationItem.create(
                        kind: .comment,
                        points: [
                            NormalizedPoint(650.0 / 1280.0 + 0.02, 360.0 / 720.0 + 0.02),
                            NormalizedPoint(650.0 / 1280.0 + 0.03, 360.0 / 720.0 + 0.03),
                        ],
                        note: "Уточнить размер",
                        parentAnnotationId: annotation.id)
                    capture.annotations.append(comment)
                }
                try workspace.replaceCapture(capture)
            }
        }

        try workspace.updateGlobalNote("Сохранить цвета")
        try await workspace.save()
    }

    /// Port of `CreateDemoBitmap`: background `#F5F7FA`, a white "window" inset by 52/48, a header
    /// bar `#E8EDF6`, a blue accent rectangle that shifts per index, and title/body text. Segoe UI
    /// is replaced by the system font (SPEC §1.19, §9.12).
    static func renderDemoImage(index: Int, width: Int = 1280, height: Int = 720) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else {
            // Finding 25: this path is reachable from `--smoke-test` (`SmokeTestRunner.swift`),
            // where a `fatalError` would crash the whole process instead of failing one check.
            throw SnapikError.invalidOperation("DemoSessionFactory: could not allocate the demo image bitmap context.")
        }

        // Flip so all drawing below can use top-left-origin coordinates, matching the WPF source.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        context.setFillColor(NSColor(hex: "#F5F7FA").cgColor)
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))

        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 52, y: 48, width: CGFloat(width - 104), height: CGFloat(height - 96)))

        context.setFillColor(NSColor(hex: "#E8EDF6").cgColor)
        context.fill(CGRect(x: 52, y: 48, width: CGFloat(width - 104), height: 56))

        context.setFillColor(NSColor(hex: "#315CF5").cgColor)
        let blueX = 860 - index * 35
        let blueY = 540 - index * 28
        context.fill(CGRect(x: CGFloat(blueX), y: CGFloat(blueY), width: 230, height: 62))

        // CHECK-API: NSGraphicsContext(cgContext:flipped:) bridging for NSString drawing into an
        // offscreen bitmap context; not verified against a real compiler.
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)

        let letterScalar = UnicodeScalar(UInt8(65 + index))
        let title = "Тестовый экран \(Character(letterScalar))"
        (title as NSString).draw(
            at: CGPoint(x: 100, y: 150),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 31),
                .foregroundColor: NSColor(hex: "#172033"),
            ])

        let body = "Проверка Snapik: отдельный снимок и связанная заметка."
        (body as NSString).draw(
            at: CGPoint(x: 100, y: 215),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 20),
                .foregroundColor: NSColor(hex: "#5E687A"),
            ])

        guard let image = context.makeImage() else {
            throw SnapikError.invalidOperation("DemoSessionFactory: could not render the demo image.")
        }
        return image
    }

    /// `--demo-screenshot <dir>` (CI helper, CONTRACTS "Shell"): in addition to the stack window
    /// `AppCoordinator.start()` already reveals, show the editor overlay (over a synthetic desktop
    /// frame — never a real screen capture) and the settings window, then dump a PNG of every own
    /// window to `directory` twice (2 s and 5 s after showing, matching the external CI script's
    /// full-desktop `screencapture` at 3 s/6 s) before terminating at 8 s.
    static func runScreenshotFlow(to directory: URL, coordinator: AppCoordinator) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        presentDemoOverlay(coordinator: coordinator)
        coordinator.stackWindow?.openSettings()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            captureWindowScreenshots(to: directory)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                captureWindowScreenshots(to: directory)
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    // CI-only flow: the demo session is disposable, so skip the forced-save
                    // terminate path and end the process directly.
                    exit(0)
                }
            }
        }
    }

    /// Presents `OverlayEditorController` the same way `AppCoordinator.beginOverlayCapture()`
    /// does, but over a synthetic gradient frame instead of a real screen capture — `--demo`/
    /// `--demo-screenshot` must never touch `ScreenCaptureKit`/`CGRequestScreenCaptureAccess`
    /// (SPEC §9.1, CONTRACTS.md "Shell").
    private static func presentDemoOverlay(coordinator: AppCoordinator) {
        // Finding 25: `syntheticDesktopFrame()` now throws instead of crashing the process; this
        // CI-only convenience path simply skips presenting the overlay on failure.
        guard let frame = try? syntheticDesktopFrame() else { return }
        let context = EditorWorkspaceContext(
            session: coordinator.workspace.session, sessionDirectory: coordinator.workspace.sessionDirectory,
            assetStore: coordinator.workspace.assetStore, nextCaptureIndex: coordinator.workspace.session.captures.count,
            regionPath: coordinator.workspace.regionPath)
        let controller = OverlayEditorController(
            frame: frame, workspace: context, settings: coordinator.settings, language: coordinator.language)
        controller.delegate = coordinator
        coordinator.overlay = controller
        controller.present()
    }

    /// A gradient `CGImage` sized to the (points-space) virtual desktop, standing in for a real
    /// `DesktopFrame` capture — no `ScreenCaptureKit`/`CGDisplayCreateImage` call involved. Not
    /// `private`: also used by `App/SmokeTestRunner.swift` to drive the editor test hooks (SPEC
    /// §8.4 points 6, 9, 10) without a real screen capture.
    static func syntheticDesktopFrame() throws -> DesktopFrame {
        let scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 1
        let pointsRect = ScreenGeometry.globalPointsRect
        let width = max(1, Int((pointsRect.width * scale).rounded()))
        let height = max(1, Int((pointsRect.height * scale).rounded()))

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
            let gradient = CGGradient(
                colorsSpace: colorSpace,
                colors: [NSColor(hex: "#1B2635").cgColor, NSColor(hex: "#3A4B66").cgColor] as CFArray,
                locations: [0, 1])
        else {
            // Finding 25: reachable from `--smoke-test`; a `fatalError` here would crash the
            // whole process instead of failing one check.
            throw SnapikError.invalidOperation("DemoSessionFactory: could not allocate the synthetic demo desktop bitmap.")
        }
        context.drawLinearGradient(
            gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: CGFloat(width), y: CGFloat(height)), options: [])

        guard let image = context.makeImage() else {
            throw SnapikError.invalidOperation("DemoSessionFactory: could not render the synthetic demo desktop bitmap.")
        }
        return DesktopFrame(image: image, left: 0, top: 0, pixelWidth: width, pixelHeight: height, scale: scale)
    }

    private static func captureWindowScreenshots(to directory: URL) {
        for window in NSApplication.shared.windows where window.isVisible {
            // `sharingType == .none` (SPEC §9.8: `EdgeStackPanel`/`OverlayWindow` are deliberately
            // excluded from *other* apps' screen captures) makes the window server hand back a
            // blank image to *any* capture consumer, including our own `CGWindowListCreateImage`
            // call below run by the very process that owns the window. Only for this CI-only
            // dump, briefly allow capture, then restore the real runtime value right after.
            let originalSharing = window.sharingType
            if originalSharing == .none { window.sharingType = .readOnly }
            defer { if originalSharing == .none { window.sharingType = originalSharing } }

            // CHECK-API: `.boundsIgnoreFraming` option name transcribed from
            // `CGWindowImageOption`; verify against the current SDK.
            guard
                let image = CGWindowListCreateImage(
                    .null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming])
            else { continue }
            guard let data = ImageCodec.encode(image, format: .png) else { continue }
            let safeName = (window.title.isEmpty ? "window-\(window.windowNumber)" : window.title)
                .replacingOccurrences(of: "/", with: "-")
            let destination = directory.appendingPathComponent("window-\(safeName).png")
            try? data.write(to: destination)
        }
    }
}
