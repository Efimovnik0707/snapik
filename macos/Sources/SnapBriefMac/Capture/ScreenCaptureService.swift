// Port of `CaptureOverlay.xaml.cs:60-85` (`CaptureDesktopFrame`), SPEC §1.2 п.4, §9.1, §9.5.
import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit
import SnapBriefCore
import os

/// SPEC §1.2 п.4 / §9.1: the macOS replacement for Windows' `GetSystemMetrics`+`CopyFromScreen`
/// desktop snapshot. Screen Recording (`kTCCServiceScreenCapture`) permission is required.
public protocol ScreenCaptureServicing {
    var hasScreenRecordingPermission: Bool { get }
    func requestScreenRecordingPermission()
    func captureDesktop(includeCursor: Bool, completion: @escaping (Result<DesktopFrame, Error>) -> Void)
}

/// Captures every attached `NSScreen` via ScreenCaptureKit (`SCScreenshotManager`, macOS 14+)
/// and composes them into one `DesktopFrame` bitmap at the maximum `backingScaleFactor` among
/// them (SPEC §9.5 "Решение Q4"), falling back to the deprecated `CGDisplayCreateImage` if
/// ScreenCaptureKit fails for any reason (missing permission, transient stream error, ...).
public final class ScreenCaptureService: ScreenCaptureServicing {
    private let log = Logger(subsystem: "live.yesworkflow.snapbrief", category: "capture")

    public init() {}

    public var hasScreenRecordingPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    public func requestScreenRecordingPermission() {
        CGRequestScreenCaptureAccess()
    }

    /// Port of finding 2 (CONTRACTS.md "Shell"/review): `captureDesktopAsync` runs on the
    /// cooperative thread pool, so `completion` is always redispatched onto the main queue here —
    /// every caller (`AppCoordinator`) touches AppKit from it.
    public func captureDesktop(includeCursor: Bool, completion: @escaping (Result<DesktopFrame, Error>) -> Void) {
        Task {
            do {
                let frame = try await captureDesktopAsync(includeCursor: includeCursor)
                DispatchQueue.main.async { completion(.success(frame)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    private func captureDesktopAsync(includeCursor: Bool) async throws -> DesktopFrame {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            throw SnapBriefError.invalidOperation("ScreenCaptureService: no screens are attached.")
        }
        let scale = screens.map(\.backingScaleFactor).max() ?? 1
        let pointsRect = ScreenGeometry.globalPointsRect
        let pixelWidth = max(1, Int((pointsRect.width * scale).rounded()))
        let pixelHeight = max(1, Int((pointsRect.height * scale).rounded()))

        guard
            let composed = CGContext(
                data: nil,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else {
            throw SnapBriefError.invalidOperation("ScreenCaptureService: failed to create the desktop bitmap.")
        }
        // (0,0) is the top-left of the composed desktop and Y grows downward, matching
        // `ScreenGeometry`'s frame space; image drawing below is correctly oriented regardless
        // of this flip (Core Graphics keeps `draw(_:in:)` visually right-side-up under it).
        composed.translateBy(x: 0, y: CGFloat(pixelHeight))
        composed.scaleBy(x: 1, y: -1)

        do {
            try await captureViaScreenCaptureKit(screens: screens, scale: scale, pointsRect: pointsRect, into: composed)
        } catch {
            log.error("ScreenCaptureKit capture failed, falling back to CGDisplayCreateImage: \(String(describing: error))")
            captureViaCGDisplay(screens: screens, scale: scale, pointsRect: pointsRect, into: composed)
        }

        guard let image = composed.makeImage() else {
            throw SnapBriefError.invalidOperation("ScreenCaptureService: failed to rasterize the desktop image.")
        }
        let frame = DesktopFrame(image: image, left: 0, top: 0, pixelWidth: pixelWidth, pixelHeight: pixelHeight, scale: scale)

        guard includeCursor else { return frame }
        CaptureCursorDrawing.draw(into: composed, frame: frame)
        guard let withCursor = composed.makeImage() else { return frame }
        return DesktopFrame(image: withCursor, left: 0, top: 0, pixelWidth: pixelWidth, pixelHeight: pixelHeight, scale: scale)
    }

    /// One `SCContentFilter`/`SCScreenshotManager.captureImage` call per `SCDisplay`, excluding
    /// this process' own windows (SPEC: "исключить собственные окна приложения из захвата").
    private func captureViaScreenCaptureKit(
        screens: [NSScreen], scale: CGFloat, pointsRect: CGRect, into composed: CGContext
    ) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownWindows = content.windows.filter { $0.owningApplication?.processID == ownPID }

        for screen in screens {
            guard let displayID = directDisplayID(of: screen),
                let display = content.displays.first(where: { $0.displayID == displayID })
            else {
                continue
            }
            let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
            let configuration = SCStreamConfiguration()
            configuration.width = max(1, Int((CGFloat(display.width) * scale).rounded()))
            configuration.height = max(1, Int((CGFloat(display.height) * scale).rounded()))
            // We draw the cursor ourselves (`CaptureCursorDrawing`) to match the Windows
            // hotspot-aware path pixel-for-pixel; ScreenCaptureKit's own overlay would double it.
            configuration.showsCursor = false

            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            draw(image, ofScreen: screen, scale: scale, pointsRect: pointsRect, into: composed)
        }
    }

    /// Fallback path (SPEC §9.1) used only when the ScreenCaptureKit path above throws.
    private func captureViaCGDisplay(screens: [NSScreen], scale: CGFloat, pointsRect: CGRect, into composed: CGContext) {
        for screen in screens {
            guard let displayID = directDisplayID(of: screen), let image = CGDisplayCreateImage(displayID) else {
                continue
            }
            draw(image, ofScreen: screen, scale: scale, pointsRect: pointsRect, into: composed)
        }
    }

    private func directDisplayID(of screen: NSScreen) -> CGDirectDisplayID? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }

    /// Places one display's captured image at its position within `composed`, using the same
    /// flip/scale pipeline as `ScreenGeometry` (SPEC §9.5) so every screen lands at the pixel
    /// offset matching `ScreenGeometry.framePixels(fromScreenPoint:frame:)`.
    private func draw(_ image: CGImage, ofScreen screen: NSScreen, scale: CGFloat, pointsRect: CGRect, into composed: CGContext) {
        let topLeftPoints = CGPoint(x: screen.frame.minX - pointsRect.minX, y: pointsRect.maxY - screen.frame.maxY)
        let originPixels = CGPoint(x: topLeftPoints.x * scale, y: topLeftPoints.y * scale)
        let sizePixels = CGSize(width: screen.frame.width * scale, height: screen.frame.height * scale)
        composed.draw(image, in: CGRect(origin: originPixels, size: sizePixels))
    }
}
