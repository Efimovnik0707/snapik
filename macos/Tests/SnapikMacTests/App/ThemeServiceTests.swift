// Covers `Theme.swift` and `AccentPalette.swift`, SPEC-DELTA-3 §7 W0-5 and
// `tasks/tz-005-details/B-themes-accents.md` §2, §3, §5. Windows keeps these facts in its smoke run
// (`SmokeTestRunner.cs:184-215`), where the palettes are resource dictionaries and a missing key can
// only be found by comparing key sets; here a palette is a struct, so the set is the same by
// construction and what is left to check is the list, the fallback and the values.
import AppKit
import XCTest

@testable import SnapikMac

final class ThemeServiceTests: XCTestCase {
    func test_There_are_six_themes_and_the_light_one_is_not_among_them() {
        XCTAssertEqual(["dark", "glass", "night", "sunset", "sea", "dawn"], ThemeService.themes)
    }

    func test_A_theme_nothing_answers_to_is_read_as_the_dark_one() {
        XCTAssertEqual("dark", ThemeService.normalizeTheme("light"))
        XCTAssertEqual("dark", ThemeService.normalizeTheme("LIGHT"))
        XCTAssertEqual("dark", ThemeService.normalizeTheme("nothing-like-a-theme"))
        XCTAssertEqual("dark", ThemeService.normalizeTheme(nil))
        XCTAssertEqual("dark", ThemeService.palette("light").id)
        // The ones that do answer are read as themselves, whatever case they are written in.
        XCTAssertEqual("sea", ThemeService.normalizeTheme("Sea"))
        XCTAssertEqual("dawn", ThemeService.palette("dawn").id)
    }

    func test_Every_palette_carries_the_surface_the_reference_gives_it() {
        XCTAssertEqual(.solid(NSColor(hex: "#F2171A20")), ThemeService.palette("dark").surface)
        XCTAssertFalse(ThemeService.palette("dark").surface.isGradient)

        for gradientTheme in ["glass", "night", "sunset", "sea", "dawn"] {
            XCTAssertTrue(
                ThemeService.palette(gradientTheme).surface.isGradient,
                "\(gradientTheme) paints its surface with a run of colours")
            XCTAssertTrue(ThemeService.palette(gradientTheme).surfaceBar.isGradient)
            XCTAssertNotNil(ThemeService.palette(gradientTheme).surface.nsGradient())
        }

        // [ТЗ№4 B2] "Стекло" is the three-stop gradient B, not the translucent grey of 1.4.0.
        guard case .gradient(let stops, _, let end) = ThemeService.palette("glass").surface else {
            return XCTFail("the glass surface must be a gradient")
        }
        XCTAssertEqual(3, stops.count)
        XCTAssertEqual(NSColor(hex: "#5F5C8C"), stops[0].colour)
        XCTAssertEqual(0.55, stops[1].offset)
        XCTAssertEqual(NSColor(hex: "#58627A"), stops[2].colour)
        XCTAssertEqual(CGPoint(x: 0.6, y: 1), end)
        XCTAssertEqual(0.35, ThemeService.palette("glass").shadowOpacity)

        // The dawn palette is the light one of the round: dark text over a pale surface.
        XCTAssertEqual(NSColor(hex: "#172033"), ThemeService.palette("dawn").text)
        XCTAssertEqual(NSColor(hex: "#B42318"), ThemeService.palette("dawn").danger)
    }

    func test_There_are_twelve_accents_and_the_last_six_of_them_run() {
        XCTAssertEqual(
            [
                "blue", "teal", "violet", "coral", "rose", "cyan",
                "blue-violet", "orange-rose", "green-cyan", "amber-pink", "rose-violet", "cyan-blue",
            ], ThemeService.accents)

        let gradient = ThemeService.accents.filter { ThemeService.isGradientAccent($0) }
        XCTAssertEqual(
            ["blue-violet", "orange-rose", "green-cyan", "amber-pink", "rose-violet", "cyan-blue"],
            gradient)
        // The divider of the row stands in front of the first accent that runs, whatever it is called.
        XCTAssertEqual(6, ThemeService.accents.firstIndex { ThemeService.isGradientAccent($0) })
    }

    func test_An_accent_nothing_answers_to_is_read_as_the_blue_one() {
        XCTAssertEqual("blue", ThemeService.normalizeAccent("neon"))
        XCTAssertEqual("blue", ThemeService.normalizeAccent(nil))
        XCTAssertEqual("blue", ThemeService.accent("neon").id)
        XCTAssertEqual("rose-violet", ThemeService.normalizeAccent("Rose-Violet"))
    }

    func test_A_gradient_accent_still_gives_one_colour_and_it_is_the_first_stop() {
        for accentId in ThemeService.accents {
            let accent = ThemeService.accent(accentId)
            XCTAssertEqual(
                accent.brush.flat, accent.flat, "\(accentId) must flatten to its own first stop")
            XCTAssertEqual(
                accent.flat.withAlphaComponent(0x55 / 255.0), accent.soft,
                "\(accentId) softens its first stop")
        }

        let roseViolet = ThemeService.accent("rose-violet")
        XCTAssertEqual(NSColor(hex: "#FF5C8A"), roseViolet.flat)
        guard case .gradient(let stops, _, let end) = roseViolet.brush else {
            return XCTFail("rose-violet must be a gradient")
        }
        XCTAssertEqual([NSColor(hex: "#FF5C8A"), NSColor(hex: "#AF81FF")], stops.map(\.colour))
        XCTAssertEqual(CGPoint(x: 1, y: 1), end)
        XCTAssertEqual(NSColor(hex: "#E39AD6"), roseViolet.focus)
    }

    func test_The_palette_of_the_application_follows_what_was_applied() {
        defer { ThemeService.apply(theme: nil, accent: nil) }

        ThemeService.apply(theme: "light", accent: "cyan-blue")
        XCTAssertEqual("dark", ThemeService.currentTheme)
        XCTAssertEqual("cyan-blue", ThemeService.currentAccent)
        XCTAssertEqual(NSColor(hex: "#22C1C3"), AccentPalette.flat)
        XCTAssertTrue(AccentPalette.brush.isGradient)
        XCTAssertEqual(AccentPalette.flat.withAlphaComponent(0.5), AccentPalette.wash(alpha: 0.5))

        ThemeService.apply(theme: "sea", accent: "violet")
        XCTAssertEqual("sea", ThemeService.currentTheme)
        XCTAssertEqual(NSColor(hex: "#AF81FF"), AccentPalette.flat)
        XCTAssertFalse(AccentPalette.brush.isGradient)
    }
}
