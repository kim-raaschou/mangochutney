import XCTest
@testable import Mango
@testable import Port

/// Mango's parse_option, parse_config_line, toml_parse and value_parse, case by case.
@MainActor
final class ConfigParseFidelityTests: MangoTestCase {
    private func parse(_ text: String, name: String = "t.conf") -> ParsedConfig {
        ConfigParser.parse(text: text, baseDirectory: FileManager.default.temporaryDirectory, fileName: name)
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mango-parse-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    // D1: override_config clamps the int-as-bool keys to 0..1, so a negative value is off.
    func testANegativeBoolIsOff() {
        let c = parse("""
        animations=-1
        sloppy_focus=-1
        smart_gaps=2
        animation_fade_in=-1
        tag_carousel=-1
        """).config
        XCTAssertFalse(c.animations)
        XCTAssertFalse(c.sloppyfocus)
        XCTAssertTrue(c.smartgaps)
        XCTAssertFalse(c.animationFadeIn)
        XCTAssertTrue(c.tagCarousel, "override_config does not clamp tag_carousel: -1 is true")
    }

    // D2: a negative window-rule value is mango's unset -1.

    // D3: parse_double_array clears the curve first and fills it until it fails.
    func testABadCurveIsZeroedAndFilledAsFarAsItGoes() {
        let few = parse("animation_curve_move=0.46,1.0,0.29")
        XCTAssertEqual(few.config.animationCurveMove, BezierCurve(x1: 0.46, y1: 1, x2: 0.29, y2: 0))
        XCTAssertEqual(few.errors.map(\.message.plain), ["Failed to parse animation_curve_move: 0.46,1.0,0.29"])

        let bad = parse("animation_curve_open=x")
        XCTAssertEqual(bad.config.animationCurveOpen, BezierCurve(x1: 0, y1: 0, x2: 0, y2: 0))
        XCTAssertEqual(bad.errors.map(\.message.plain),
                       ["Invalid number in array: x", "Failed to parse animation_curve_open: x"])
        XCTAssertEqual(bad.errors.map(\.reportsLine), [false, true], "one [Index] for the line, after its messages")

        let negative = parse("animation_curve_tag=0.1,-1,0.2,0.3")
        XCTAssertEqual(negative.errors.first?.message.plain, "Invalid number in array (must be non-negative): -1")
        XCTAssertEqual(negative.config.animationCurveTag, BezierCurve(x1: 0.1, y1: 0, x2: 0, y2: 0))
    }

    // D4: every matching tag rule writes no_render_border, open_as_floating and no_hide (default 0).
    func testEveryMatchingTagRuleWritesTheThreeFlags() {
        let r = EngineRig()
        r.server.config.tagRules = parse("""
        tag_rule=id:2,no_render_border:1,open_as_floating:1
        tag_rule=id:*,no_hide:1
        tag_rule=id:2,layout_name:scroller
        tag_rule=id:3,no_hide:-1
        """).config.tagRules
        r.server.parseTagrule(r.monitor)
        XCTAssertFalse(r.monitor.pertag.noRenderBorder[2], "the later id:2 rule writes its default 0")
        XCTAssertFalse(r.monitor.pertag.openAsFloating[2])
        XCTAssertFalse(r.monitor.pertag.noHide[2])
        XCTAssertTrue(r.monitor.pertag.noHide[1], "id:* is the last rule for tag 1")
        XCTAssertFalse(r.monitor.pertag.noHide[3], "-1 clamps to 0")
    }

    func testSetoptionIsParseOption() throws {
        let dir = try makeTempDir()
        let extra = dir.appendingPathComponent("extra.conf")
        try "border_px=7\ngap_inner_horizontal=$G\n".write(to: extra, atomically: true, encoding: .utf8)
        let r = EngineRig()
        func setoption(_ args: String...) { _ = r.server.dispatch(Dispatch(name: "setoption", args: args), target: nil) }
        setoption("var", "G,9")
        setoption("source", extra.path)
        XCTAssertEqual(r.server.config.borderpx, 7)
        XCTAssertEqual(r.server.config.gappih, 9, "the var set by setoption expands in the sourced file")
        setoption("source_optional", dir.appendingPathComponent("none.conf").path)
        setoption("tag_rule", "id:2", "layout_name:scroller", "foo:1")
        XCTAssertEqual(r.server.config.tagRules.last?.layoutName, "scroller", "mango keeps a rule with an unknown field")
        setoption("window_rule", "app_id:x", "bogus:1")
        XCTAssertEqual(r.server.config.windowRules.last?.id, "x")
    }

    func testABadPresetOrCircleLayoutEmptiesTheList() {
        let preset = parse("""
        scroller_proportion_preset=0.5,0.8,1.0
        scroller_proportion_preset=0.5,x
        """)
        XCTAssertEqual(preset.config.scrollerProportionPreset, [])
        XCTAssertEqual(parse("scroller_proportion_preset=0.5,,0.8").config.scrollerProportionPreset, [])

        let circle = parse("""
        circle_layout=tile,scroller
        circle_layout=tile,,scroller
        """)
        XCTAssertEqual(circle.config.circleLayout, [])
        XCTAssertEqual(circle.errors.map(\.message.plain), ["Invalid circle_layout format: tile,,scroller"])
        XCTAssertEqual(parse("circle_layout=tile,").config.circleLayout, [])
    }

    func testKeywordsAreMatchedByPrefix() {
        let c = parse("""
        envfoo=A,b
        exec_once_later=echo hi
        mousebindx=SUPER,btn_left,moveresize,curmove
        axisbindx=SUPER,up,viewtoleft
        gesturebindx=none,left,3,focusdir,left
        bind|=SUPER,a,quit
        """)
        // parse_bind_flags reports the bar, and the binding is kept (no [Index])
        XCTAssertEqual(c.errors.map(\.message.plain), ["Unknown bind flag: |"])
        XCTAssertEqual(c.errors.map(\.reportsLine), [false])
        XCTAssertEqual(c.config.envVars.first?.0, "A")
        XCTAssertEqual(c.config.execOnce, ["echo hi"])
        XCTAssertEqual(c.config.mouseBindings.count, 1)
        XCTAssertEqual(c.config.axisBindings.count, 1)
        XCTAssertEqual(c.config.gestureBindings.count, 1)
        XCTAssertEqual(c.config.keyBindings.count, 1, "mango's regex ^bind[s|l|r|p|c]*$ takes the bar")
        XCTAssertEqual(parse("execx=echo").errors.map(\.message.plain), ["Unknown keyword: execx"],
                       "exec is matched whole (strncmp with 9)")
    }

    func testAMissingSourceIsOneMessageWithoutIndex() {
        let p = parse("source=/nonexistent/mango-missing.conf\nborder_px=2")
        XCTAssertEqual(p.errors.map(\.message.plain), ["Failed to open config file: /nonexistent/mango-missing.conf"])
        XCTAssertEqual(p.errors.map(\.reportsLine), [false])
        XCTAssertEqual(p.config.borderpx, 2)
    }

    func testTomlArrayStopsAtTheFirstFailingElement() {
        let p = parse("""
        [bind.default]
        "SUPER+a" = ["spawn,x", "nosuchdispatch", "spawn,y"]
        """, name: "t.toml")
        XCTAssertEqual(p.config.keyBindings.map(\.dispatch.args), [["x"]])
        XCTAssertEqual(p.errors.map(\.reportsLine), [true])
    }

    // not in mango: §6, toml_foreach_array_element ends a string at an escaped quote.
    func testAnEscapedQuoteStaysInsideATomlString() {
        let p = parse(#"exec = ["notify-send \"a, b\""]"#, name: "t.toml")
        XCTAssertEqual(p.config.exec, [#"notify-send "a, b""#])
    }

    // not in mango: §6, toml_section_flush sets the keymode to "" after a rejected bind section.
    func testARejectedTomlBindSectionKeepsTheKeymode() {
        let p = parse("""
        [bind.default.bogus]
        "SUPER+a" = "spawn,x"
        [global]
        bind = "SUPER,b,spawn,y"
        """, name: "t.toml")
        XCTAssertEqual(p.errors.map(\.message.plain), ["Unknown bind flag: bogus"])
        XCTAssertEqual(p.config.keyBindings.map(\.mode), ["default"])
    }

    func testParseColorIsStrtol() {
        XCTAssertNil(parseColor("0x"))
        XCTAssertNil(parseColor("-1"))
        XCTAssertEqual(parseColor("+ff"), RGBA(r: 0, g: 0, b: 0, a: 1))
        XCTAssertEqual(parseColor("-2"), RGBA(r: 1, g: 1, b: 1, a: 254.0 / 255))
        XCTAssertNil(parseColor("0xzz"))
    }

    // mango parse_option checks switchbind, monitor_rule, layer_rule and device_rule as it does every
    // line, though macOS gives none of them an effect

    // mango parse_key with bindsym: a name xkb does not know is NoSymbol, with no message of its own
}
