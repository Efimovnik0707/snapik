// Port of `src/Snapik.App/TextMarkMetrics.cs`, SPEC-DELTA-3 §1.1 C-11, §4.
import Foundation

#if canImport(CoreText)
    import CoreText
#endif

/// The box a caption takes, in the pixels of the capture.
public struct TextMarkSize: Equatable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

/// The box of a text mark is the letters themselves and not the point the hand clicked at. Without
/// it the hit test, the eraser, the move handle and the selection all work on a small square beside
/// the word, so a double click on a caption makes a second caption instead of opening the first.
///
/// The family is the system one (`SF Pro Text` through `CTFontCreateUIFontForLanguage(.system,…)`),
/// not the `Segoe UI Variable Text` of the Windows file: the metrics differ, and the invariant is
/// "the box of the canvas and the box of the export renderer agree", not "the same number as on
/// Windows" (SPEC-DELTA-3 §4). The `canImport` guard keeps `SnapikCore` Foundation-only where
/// CoreText does not exist (`CONTRACTS.md`: Core compiles on Windows too); the application and the
/// tests always run on the CoreText side of it.
public enum TextMarkMetrics {
    public static let defaultFontSize: Double = 20
    public static let minimumFontSize: Double = 8
    public static let maximumFontSize: Double = 96
    public static let fontSizePresets: [Double] = [12, 16, 20, 24, 32, 48]

    /// A size out of a settings file or a session written by hand still has to draw: a text layout
    /// throws on anything that is not a positive number.
    public static func clamp(_ fontSize: Double) -> Double {
        fontSize.isFinite ? min(max(fontSize, minimumFontSize), maximumFontSize) : defaultFontSize
    }

    /// Measured in the pixels of the capture, one pixel per point, which is what the export renderer
    /// draws with: the same numbers on screen and in the PNG.
    public static func measure(_ text: String, fontSize: Double) -> TextMarkSize {
        let size = clamp(fontSize)
        let measured = text.isEmpty ? " " : text
        let laid = layout(measured, size: size)
        return TextMarkSize(width: max(size / 2, laid.width), height: max(size, laid.height))
    }

    /// The second point of a text mark is not what the hand drew, it is what the letters take. The
    /// anchor is left where it is; the caller stores the answer as `points[1]`.
    public static func fit(anchor: GeometryPoint, text: String, fontSize: Double) -> GeometryPoint {
        let size = measure(text, fontSize: fontSize)
        return GeometryPoint(anchor.x + size.width, anchor.y + size.height)
    }

    #if canImport(CoreText)
        private static func layout(_ text: String, size: Double) -> (width: Double, height: Double) {
            let font = CTFontCreateUIFontForLanguage(.system, CGFloat(size), nil)
                ?? CTFontCreateWithName("Helvetica" as CFString, CGFloat(size), nil)
            let attributed = NSAttributedString(
                string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
            let line = CTLineCreateWithAttributedString(attributed as CFAttributedString)
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            return (Double(width), Double(ascent + descent + leading))
        }
    #else
        /// Where CoreText does not exist there is no font to ask, so the box is an estimate. It is
        /// never the box the application draws with: the Mac build always takes the branch above.
        private static func layout(_ text: String, size: Double) -> (width: Double, height: Double) {
            (Double(text.count) * size * 0.55, size * 1.25)
        }
    #endif
}
