// Port of `tests/Snapik.App.Imaging.Tests/SoundVolumeCurveTests.cs`, SPEC-DELTA-5 §3.3.
//
// The three gains are the ones the interface carries: the shutter 0.6, the tick of the strip 0.25
// and the answer of a copy 0.7 (`UiSoundService`).
import XCTest

@testable import SnapikCore

final class SoundVolumeCurveTests: XCTestCase {
    private static let gains: [Double] = [0.6, 0.25, 0.7]

    func test_The_top_of_the_slider_is_the_gain_of_the_sound_itself() {
        XCTAssertEqual(0.6, SoundVolumeCurve.amplitude(volume: 100, gain: 0.6), accuracy: 1e-6)
    }

    /// Half the travel is a quarter of the amplitude, a quarter of it is a sixteenth: that is the
    /// whole point of the square.
    func test_Half_the_travel_is_a_quarter_of_the_amplitude() {
        XCTAssertEqual(0.15, SoundVolumeCurve.amplitude(volume: 50, gain: 0.6), accuracy: 1e-6)
        XCTAssertEqual(0.0375, SoundVolumeCurve.amplitude(volume: 25, gain: 0.6), accuracy: 1e-6)
    }

    func test_Nothing_at_the_bottom_is_silence_whatever_the_gain() {
        XCTAssertEqual(0, SoundVolumeCurve.amplitude(volume: 0, gain: 0.6), accuracy: 1e-6)
        XCTAssertEqual(0, SoundVolumeCurve.amplitude(volume: 0, gain: 0.25), accuracy: 1e-6)
    }

    /// A number out of the range of the slider is a number a hand-edited file holds: it is clamped,
    /// not believed.
    func test_A_volume_outside_the_slider_is_clamped_to_its_ends() {
        XCTAssertEqual(0, SoundVolumeCurve.amplitude(volume: -5, gain: 0.6), accuracy: 1e-6)
        XCTAssertEqual(0.6, SoundVolumeCurve.amplitude(volume: 250, gain: 0.6), accuracy: 1e-6)
    }

    /// Every step of the slider is louder than the one before it, on all three gains: a curve that
    /// dipped anywhere would make the slider feel broken even where the numbers are right.
    func test_The_curve_only_rises() {
        for gain in Self.gains {
            var previous = SoundVolumeCurve.amplitude(volume: 0, gain: gain)
            for volume in 1...100 {
                let current = SoundVolumeCurve.amplitude(volume: volume, gain: gain)
                XCTAssertGreaterThan(current, previous, "\(gain) \(volume)")
                previous = current
            }
            XCTAssertEqual(gain, previous, accuracy: 1e-6)
        }
    }
}
