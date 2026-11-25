import XCTest
@testable import Mango
import MangoTestKit

/// mango's src/config/option_defs.c
final class OptionDefsTests: XCTestCase {

    // MARK: set_value_default

    func testNoProportionPresetByDefault() {
        XCTAssertEqual(Config().scrollerProportionPreset, [])
    }

    // MARK: parse_option

    func testTheBarsAreClamped() {
        let c = ConfigParser.parse(text: """
            tab_bar_height=800
            title_message_bar_height=900
            group_bar_button_size=0
            group_bar_button_margin=-5
            """, baseDirectory: nil, fileName: "t").config

        XCTAssertEqual(c.tabBarHeight, 500)
        XCTAssertEqual(c.titleMessageBarHeight, 500)
        XCTAssertEqual(c.groupBarButtonSize, 4)
        XCTAssertEqual(c.groupBarButtonMargin, 0)
    }

    func testACurveTakesFourAndAnUnknownAnimationTypeSlides() {
        let c = ConfigParser.parse(text: """
            animation_curve_open=0.46,1,0.29,0.99,7
            animation_type_open=bounce
            """, baseDirectory: nil, fileName: "t")

        XCTAssertEqual(c.errors.count, 0)
        XCTAssertEqual(c.config.animationCurveOpen, AnimationCurve(bezier: [0.46, 1, 0.29, 0.99]))
        XCTAssertEqual(c.config.animationTypeOpen, .slide)
    }

    func testKeyModeGoesOnTheBindsAfterItAndABadEnvIsRefused() {
        let port = ConfigParser.port
        ConfigParser.port = FakeKeymap()
        defer { ConfigParser.port = port }
        var c = Config()

        XCTAssertTrue(parseOption("key_mode", "resize", to: &c))
        XCTAssertTrue(parseOption("bind", "NONE,h,focusdir,left", to: &c))

        XCTAssertEqual(c.keyBindings.last?.mode, "resize")
        XCTAssertFalse(parseOption("env", "FOO,", to: &c))
    }

    func testJumpLabelsTheProportionPresetAndTheDropColour() {
        var c = Config()
        XCTAssertEqual(c.dropcolor.a, 0x55 / 255.0)

        parseOption("jump_labels", "", to: &c)
        XCTAssertEqual(c.jumpLabels, "")
        parseOption("scroller_proportion_preset", "0.5x, 0.8", to: &c)
        XCTAssertEqual(c.scrollerProportionPreset, [0.5, 0.8])

        XCTAssertFalse(parseOption("scroller_proportion_preset", "a,0.8", to: &c), "not a number")
        XCTAssertEqual(c.scrollerProportionPreset, [], "mango frees the old list first")
    }

    func testABadGlobalKeyBindingDropsTheRule() {
        let port = ConfigParser.port
        ConfigParser.port = FakeKeymap()
        defer { ConfigParser.port = port }

        let c = ConfigParser.parse(text: "window_rule=app_id:foo,is_floating:1,global_key_binding:bogus-a",
                                   baseDirectory: nil, fileName: "t")

        XCTAssertTrue(c.config.windowRules.isEmpty)
        XCTAssertEqual(c.errors.count, 1)
    }

    func testAnEmptyRuleAnimationTypeIsUnset() throws {
        let r = try XCTUnwrap(ConfigParser.parse(text: "window_rule=app_id:x,animation_type_open:", baseDirectory: nil,
                                                 fileName: "t.conf").config.windowRules.first)

        XCTAssertNil(r.animationTypeOpen)
    }

    /// parse_option on one line without a file, as setoption runs it.
    @discardableResult
    private func parseOption(_ key: String, _ value: String, to c: inout Config) -> Bool {
        ConfigParser.parseOption(&c, key, value, 0, baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory()))
    }
}
