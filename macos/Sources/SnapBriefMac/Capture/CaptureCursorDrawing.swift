// Port of `src/SnapBrief.App/CaptureCursorDrawing.cs`, SPEC §1.2 п.4, §1.16.
import AppKit
import CoreGraphics

/// Draws the current system cursor into a composed `DesktopFrame` bitmap, accounting for its
/// hotspot, mirroring the Windows `GetCursorInfo` + `DrawIconEx` path.
///
/// ScreenCaptureKit's own cursor overlay is intentionally left off (`SCStreamConfiguration
/// .showsCursor = false`, see `ScreenCaptureService`) so this drawing step is the single source
/// of the cursor in the frame, exactly like on Windows, and only runs when capture-with-cursor
/// is enabled (SPEC §1.16).
public enum CaptureCursorDrawing {
    /// Draws `NSCursor.current`'s image at `NSEvent.mouseLocation`, converted into `frame`'s
    /// pixel space via `ScreenGeometry`, and offset by the cursor's own hotspot (which AppKit
    /// expresses relative to the cursor image's top-left corner, matching `frame`'s Y-down
    /// convention). `ctx` is expected to already be set up so `(0,0)` is `frame`'s top-left
    /// corner and Y grows downward, matching every other pixel calculation in this port.
    public static func draw(into ctx: CGContext, frame: DesktopFrame) {
        let cursor = NSCursor.current
        let cursorImage = cursor.image
        guard cursorImage.size.width > 0, cursorImage.size.height > 0 else { return }
        guard let cgImage = cursorImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        let mouseLocationPoints = NSEvent.mouseLocation
        let topLeftFramePixels = ScreenGeometry.framePixels(fromScreenPoint: mouseLocationPoints, frame: frame)
        let hotSpotPixels = CGPoint(x: cursor.hotSpot.x * frame.scale, y: cursor.hotSpot.y * frame.scale)
        let sizePixels = CGSize(width: cursorImage.size.width * frame.scale, height: cursorImage.size.height * frame.scale)

        let origin = CGPoint(x: topLeftFramePixels.x - hotSpotPixels.x, y: topLeftFramePixels.y - hotSpotPixels.y)

        // `ctx` is the Y-flipped desktop context (top-left origin); unflip locally so the cursor
        // bitmap is not mirrored (same rule as `ScreenCaptureService.draw(_:ofScreen:...)`).
        ctx.saveGState()
        ctx.translateBy(x: origin.x, y: origin.y + sizePixels.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(cgImage, in: CGRect(origin: .zero, size: sizePixels))
        ctx.restoreGState()
    }
}
