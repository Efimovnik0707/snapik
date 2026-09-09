// Port of `SeedDemoAsync` (`EdgeStackWindow.xaml.cs:690-708`) and
// `SessionWorkspace.CreateDemoBitmap` (`SessionWorkspace.cs:157-177`), SPEC §1.19.
import AppKit
import SnapBriefCore

enum DemoSessionFactory {
    /// Port of `SeedDemoAsync`: three synthetic 1280x720 captures labeled A/B/C — A gets a
    /// rectangle annotation, B an arrow, both noted; C gets a capture-level note only. Also sets
    /// the (UI-hidden, but still persisted) legacy global note.
    static func seedDemoSession(in workspace: SessionWorkspace) async throws {
        for index in 0..<3 {
            let image = renderDemoImage(index: index)
            guard let data = ImageCodec.encode(image, format: .png) else {
                throw SnapBriefError.invalidData("Could not encode demo capture \(index).")
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
                    note: index == 0 ? "Увеличить кнопку" : "Перенести пункт выше")
                capture.annotations.append(annotation)
                try workspace.replaceCapture(capture)
            }
        }

        try workspace.updateGlobalNote("Сохранить цвета")
        try await workspace.save()
    }

    /// Port of `CreateDemoBitmap`: background `#F5F7FA`, a white "window" inset by 52/48, a header
    /// bar `#E8EDF6`, a blue accent rectangle that shifts per index, and title/body text. Segoe UI
    /// is replaced by the system font (SPEC §1.19, §9.12).
    static func renderDemoImage(index: Int, width: Int = 1280, height: Int = 720) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else {
            fatalError("Could not allocate demo image bitmap context.")
        }

        // Flip so all drawing below can use top-left-origin coordinates, matching the WPF source.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        context.setFillColor(NSColor(hex: "#F5F7FA").cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 52, y: 48, width: width - 104, height: height - 96))

        context.setFillColor(NSColor(hex: "#E8EDF6").cgColor)
        context.fill(CGRect(x: 52, y: 48, width: width - 104, height: 56))

        context.setFillColor(NSColor(hex: "#315CF5").cgColor)
        let blueX = 860 - index * 35
        let blueY = 540 - index * 28
        context.fill(CGRect(x: blueX, y: blueY, width: 230, height: 62))

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

        let body = "Проверка SnapBrief: отдельный снимок и связанная заметка."
        (body as NSString).draw(
            at: CGPoint(x: 100, y: 215),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 20),
                .foregroundColor: NSColor(hex: "#5E687A"),
            ])

        guard let image = context.makeImage() else {
            fatalError("Could not render demo image.")
        }
        return image
    }

    /// `--demo-screenshot <dir>` (CI helper, CONTRACTS "Shell"): after the caller has shown the
    /// stack/overlay, dump a PNG of every own window to `directory`, then terminate the app.
    static func runScreenshotFlow(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            captureWindowScreenshots(to: directory)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private static func captureWindowScreenshots(to directory: URL) {
        for window in NSApplication.shared.windows where window.isVisible {
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
