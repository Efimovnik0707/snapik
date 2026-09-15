// Port of `tests/Snapik.App.Imaging.Tests/ColorConversionTests.cs`, SPEC-DELTA-3 §6.
import XCTest

@testable import SnapikCore

final class ColorConversionTests: XCTestCase {
    /// The corners of the cube, a grey, a black and a white: what the spectrum has to give back
    /// unchanged after a colour was read out of it and written into it again.
    func test_A_colour_survives_the_way_there_and_back() {
        let colours: [(UInt8, UInt8, UInt8)] = [
            (0xFF, 0x00, 0x00), (0x00, 0xFF, 0x00), (0x00, 0x00, 0xFF),
            (0xFF, 0xFF, 0x00), (0x00, 0xFF, 0xFF), (0xFF, 0x00, 0xFF),
            (0x2F, 0x8C, 0xFF), (0xFF, 0x3B, 0x30), (0x8E, 0x8E, 0x93),
            (0x00, 0x00, 0x00), (0xFF, 0xFF, 0xFF), (0x01, 0x02, 0x03),
        ]
        for (red, green, blue) in colours {
            let colour = RgbColor(red: red, green: green, blue: blue)
            let hsv = ColorConversion.rgbToHsv(colour)
            XCTAssertEqual(
                colour,
                ColorConversion.hsvToRgb(hue: hsv.hue, saturation: hsv.saturation, value: hsv.value))
        }
    }

    /// Grey has no hue and black has neither hue nor saturation: they are read as such, and putting
    /// them back gives the same grey whatever hue the slider is standing on.
    func test_A_colour_without_a_hue_is_the_same_on_every_hue() {
        for (red, green, blue) in [(UInt8(0x80), UInt8(0x80), UInt8(0x80)), (UInt8(0), UInt8(0), UInt8(0))] {
            let colour = RgbColor(red: red, green: green, blue: blue)
            let hsv = ColorConversion.rgbToHsv(colour)
            XCTAssertEqual(0, hsv.saturation)
            for hue in [0.0, 90, 210, 359] {
                XCTAssertEqual(
                    colour, ColorConversion.hsvToRgb(hue: hue, saturation: hsv.saturation, value: hsv.value))
            }
        }
    }

    /// A hue outside the circle is the same hue one turn further: the marker of the spectrum is
    /// allowed to run off both ends of the strip.
    func test_A_hue_outside_the_circle_wraps_around() {
        XCTAssertEqual(
            ColorConversion.hsvToRgb(hue: 0, saturation: 1, value: 1),
            ColorConversion.hsvToRgb(hue: 360, saturation: 1, value: 1))
        XCTAssertEqual(
            ColorConversion.hsvToRgb(hue: 330, saturation: 1, value: 1),
            ColorConversion.hsvToRgb(hue: -30, saturation: 1, value: 1))
    }

    /// What the six corners of the circle are, so that a broken sector cannot pass as a round trip.
    func test_The_corners_of_the_circle_are_the_pure_colours() {
        let corners: [(Double, UInt8, UInt8, UInt8)] = [
            (0, 0xFF, 0x00, 0x00),
            (60, 0xFF, 0xFF, 0x00),
            (120, 0x00, 0xFF, 0x00),
            (180, 0x00, 0xFF, 0xFF),
            (240, 0x00, 0x00, 0xFF),
            (300, 0xFF, 0x00, 0xFF),
        ]
        for (hue, red, green, blue) in corners {
            XCTAssertEqual(
                RgbColor(red: red, green: green, blue: blue),
                ColorConversion.hsvToRgb(hue: hue, saturation: 1, value: 1),
                "\(hue)")
        }
    }
}
