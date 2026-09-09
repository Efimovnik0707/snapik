// Port of `CapturePreviewWindow.xaml.cs:98-112` (`CalculatePreviewBounds`), coverage for
// `PreviewGeometry.previewBounds`/`fitZoom`, SPEC-DELTA-2 §1.5, SPEC-DELTA-2B §D/§F.
import CoreGraphics
import XCTest

@testable import SnapBriefMac

final class PreviewGeometryTests: XCTestCase {
    func test_previewBounds_capsAtMaximumSizeAndCenters() {
        let workArea = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let result = PreviewGeometry.previewBounds(workArea: workArea)

        XCTAssertEqual(result.frame.width, 1100, accuracy: 0.001)
        XCTAssertEqual(result.frame.height, 760, accuracy: 0.001)
        XCTAssertEqual(result.frame.midX, workArea.midX, accuracy: 0.001)
        XCTAssertEqual(result.frame.midY, workArea.midY, accuracy: 0.001)
        XCTAssertEqual(result.minSize.width, 720, accuracy: 0.001)
        XCTAssertEqual(result.minSize.height, 500, accuracy: 0.001)
    }

    func test_previewBounds_shrinksToFitSmallWorkArea() {
        let workArea = CGRect(x: 0, y: 0, width: 700, height: 450)
        let result = PreviewGeometry.previewBounds(workArea: workArea)

        // (700 - 32) = 668, (450 - 32) = 418: both below their respective caps.
        XCTAssertEqual(result.frame.width, 668, accuracy: 0.001)
        XCTAssertEqual(result.frame.height, 418, accuracy: 0.001)
        XCTAssertEqual(result.minSize.width, 668, accuracy: 0.001)
        XCTAssertEqual(result.minSize.height, 418, accuracy: 0.001)
    }

    /// Port of the Windows probe's DPI-1.5 negative-origin case (`CapturePreviewWindow.xaml.cs:360-363`):
    /// the computed frame must stay entirely within a work area whose origin is negative (the
    /// stack's monitor sitting to the left of the primary display).
    func test_previewBounds_staysWithinNegativeOriginWorkArea() {
        let workArea = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let result = PreviewGeometry.previewBounds(workArea: workArea)

        XCTAssertGreaterThanOrEqual(result.frame.minX, workArea.minX)
        XCTAssertGreaterThanOrEqual(result.frame.minY, workArea.minY)
        XCTAssertLessThanOrEqual(result.frame.maxX, workArea.maxX)
        XCTAssertLessThanOrEqual(result.frame.maxY, workArea.maxY)
    }

    func test_fitZoom_matchesTighterAxisAndClamps() {
        // Image much wider than the viewport: width-limited.
        let wide = PreviewGeometry.fitZoom(viewport: CGSize(width: 108, height: 1000), image: CGSize(width: 200, height: 100))
        XCTAssertEqual(wide, 0.5, accuracy: 0.001)

        // Degenerate viewport: falls back to 1 rather than a garbage value.
        let degenerate = PreviewGeometry.fitZoom(viewport: CGSize(width: 4, height: 4), image: CGSize(width: 200, height: 100))
        XCTAssertEqual(degenerate, 1)

        // A tiny image in a huge viewport clamps to the 4x ceiling.
        let clamped = PreviewGeometry.fitZoom(viewport: CGSize(width: 4000, height: 4000), image: CGSize(width: 10, height: 10))
        XCTAssertEqual(clamped, 4)
    }
}
