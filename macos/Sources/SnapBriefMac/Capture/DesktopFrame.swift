// Port of `CaptureOverlay.xaml.cs:178` (`DesktopFrame` record), SPEC §1.2 п.4, §9.5.
import CoreGraphics

/// Snapshot of the entire virtual desktop, already collapsed into one bitmap.
///
/// `left`/`top`/`pixelWidth`/`pixelHeight` describe the frame in the flipped, top-left-origin,
/// Y-down pixel coordinate system defined by `ScreenGeometry` (SPEC §9.5) — the macOS analogue
/// of Windows' `GetSystemMetrics(76..79)` virtual-desktop rectangle. Because the mac port always
/// composes the frame starting at the union rectangle's own origin, `left`/`top` are always `0`
/// here (unlike Windows, where they can be negative); every downstream formula in SPEC §1/§2/§6
/// treats them generically and does not depend on that.
public struct DesktopFrame {
    public let image: CGImage
    public let left: Int
    public let top: Int
    public let pixelWidth: Int
    public let pixelHeight: Int
    /// Pixels per point used to compose `image` (SPEC §9.5 "Решение Q4": the maximum
    /// `backingScaleFactor` across all attached screens).
    public let scale: CGFloat

    public init(image: CGImage, left: Int, top: Int, pixelWidth: Int, pixelHeight: Int, scale: CGFloat) {
        self.image = image
        self.left = left
        self.top = top
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.scale = scale
    }
}
