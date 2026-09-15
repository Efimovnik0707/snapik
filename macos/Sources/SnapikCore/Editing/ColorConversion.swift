// Port of `src/Snapik.App/Imaging/ColorConversion.cs`, SPEC-DELTA-3 §1.4 E-17.
import Foundation

/// A colour as three channels, 0..255. Core is Foundation-only (it compiles on Windows too), so the
/// conversion answers in plain numbers; the Mac target turns them into an `NSColor`.
public struct RgbColor: Equatable, Sendable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

/// The colour a spectrum is picked in and the colour a mark is painted with, converted both ways.
/// Hue is degrees (0..360, 360 is the same red as 0), saturation and brightness are 0..1. Pure
/// functions with no picker behind them: the round trip is what the tests hold on to.
public enum ColorConversion {
    public static func hsvToRgb(hue: Double, saturation: Double, value: Double) -> RgbColor {
        let s = min(max(saturation, 0), 1)
        let v = min(max(value, 0), 1)
        // A hue outside the circle is the same hue one turn further: -30 is 330, and 360 is 0.
        let h = hue.isNaN ? 0 : ((hue.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360)
        let sector = Int((h / 60).rounded(.down)) % 6
        let offset = h / 60 - (h / 60).rounded(.down)
        let maximum = v
        let minimum = v * (1 - s)
        let falling = v * (1 - s * offset)
        let rising = v * (1 - s * (1 - offset))
        let components: (Double, Double, Double)
        switch sector {
        case 0: components = (maximum, rising, minimum)
        case 1: components = (falling, maximum, minimum)
        case 2: components = (minimum, maximum, rising)
        case 3: components = (minimum, falling, maximum)
        case 4: components = (rising, minimum, maximum)
        default: components = (maximum, minimum, falling)
        }
        return RgbColor(
            red: channel(components.0), green: channel(components.1), blue: channel(components.2))
    }

    public static func rgbToHsv(_ color: RgbColor) -> (hue: Double, saturation: Double, value: Double) {
        let r = Double(color.red) / 255
        let g = Double(color.green) / 255
        let b = Double(color.blue) / 255
        let maximum = max(r, max(g, b))
        let minimum = min(r, min(g, b))
        let span = maximum - minimum
        // Grey has no hue of its own: it keeps the one it was being dragged through, and the caller
        // is the one holding that. Zero is what a colour read on its own answers with.
        let hue: Double
        if span == 0 {
            hue = 0
        } else if maximum == r {
            hue = 60 * (((g - b) / span + 6).truncatingRemainder(dividingBy: 6))
        } else if maximum == g {
            hue = 60 * ((b - r) / span + 2)
        } else {
            hue = 60 * ((r - g) / span + 4)
        }
        return (hue, maximum == 0 ? 0 : span / maximum, maximum)
    }

    /// `Math.Round(double)` rounds a midpoint to the even neighbour; Swift's bare `rounded()` rounds
    /// it away from zero. The explicit rule keeps both builds on the same byte.
    private static func channel(_ value: Double) -> UInt8 {
        UInt8(min(max((value * 255).rounded(.toNearestOrEven), 0), 255))
    }
}
