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
    func testANegativeWindowRuleFlagIsUnset() {
        let r = EngineRig()
        r.server.config.windowRules = parse("""
        window_rule=app_id:test,is_floating:1
        window_rule=app_id:test,is_floating:-1,no_border:-1
        """).config.windowRules
        XCTAssertNil(r.server.config.windowRules[1].isfloating)
        let c = r.window(910_001)
        _ = r.server.clientSetRules(c)
        XCTAssertTrue(c.isfloating, "the second rule leaves the first one's value")
        XCTAssertFalse(c.noBorder)
    }

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
        r.monitor.parseTagrule(config: r.server.config, clients: [])
        XCTAssertFalse(r.monitor.pertag[2].noRenderBorder, "the later id:2 rule writes its default 0")
        XCTAssertFalse(r.monitor.pertag[2].openAsFloating)
        XCTAssertFalse(r.monitor.pertag[2].noHide)
        XCTAssertTrue(r.monitor.pertag[1].noHide, "id:* is the last rule for tag 1")
        XCTAssertFalse(r.monitor.pertag[3].noHide, "-1 clamps to 0")
    }

    func testAnEmptyAppIdOrTitleMatchesEveryWindow() {
        let rules = parse("""
        window_rule=is_floating:1,title:
        window_rule=is_floating:1,app_id:
        """).config.windowRules
        XCTAssertEqual(rules.count, 2)
        for rule in rules {
            XCTAssertTrue(rule.isWindowRuleMatches(appId: "com.example", appName: "Example", title: "Anything"))
        }
    }

    func testAZeroTagRuleProportionIsSkipped() {
        let r = EngineRig()
        r.server.config.tagRules = parse("""
        tag_rule=id:1,scroller_default_proportion:0,scroller_default_proportion_single:0
        tag_rule=id:2,scroller_default_proportion:0.5
        """).config.tagRules
        r.monitor.parseTagrule(config: r.server.config, clients: [])
        XCTAssertEqual(r.monitor.pertag[1].settings.scrollerDefaultProportion, CGFloat(r.server.config.scrollerDefaultProportion))
        XCTAssertEqual(r.monitor.pertag[1].settings.scrollerDefaultProportionSingle,
                       CGFloat(r.server.config.scrollerDefaultProportionSingle))
        XCTAssertEqual(r.monitor.pertag[2].settings.scrollerDefaultProportion, 0.5)
    }

    func testAZeroRuleProportionLeavesAnEarlierOne() {
        let r = EngineRig()
        r.server.config.windowRules = parse("""
        window_rule=app_id:test,scroller_proportion:0.5,scroller_proportion_single:0.6
        window_rule=app_id:test,scroller_proportion:0,scroller_proportion_single:-0.5
        """).config.windowRules
        let c = r.window(910_002)
        r.server.applyRuleProperties(c, r.server.config.windowRules[0])
        r.server.applyRuleProperties(c, r.server.config.windowRules[1])
        XCTAssertEqual(c.scrollerProportion, 0.5)
        XCTAssertEqual(c.scrollerProportionSingle, 0.6)
        XCTAssertTrue(c.iscustomScrollerProportion)
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
        XCTAssertEqual(r.server.config.windowRules.last?.appId, "x")
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

    func testKeyModeIsTakenAsGivenAndCutAt27() {
        let empty = parse("key_mode= \nbind=SUPER,a,quit").config
        XCTAssertEqual(empty.keyBindings.first?.mode, "", "an empty key_mode is the mode \"\"")
        let long = parse("key_mode=abcdefghijklmnopqrstuvwxyz0123\nbind=SUPER,a,quit").config
        XCTAssertEqual(long.keyBindings.first?.mode, "abcdefghijklmnopqrstuvwxyz0")

        let r = EngineRig()
        _ = r.server.dispatch(Dispatch(name: "setkeymode", args: ["abcdefghijklmnopqrstuvwxyz0123"]), target: nil)
        XCTAssertEqual(r.server.keyMode, "abcdefghijklmnopqrstuvwxyz0")
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
        XCTAssertEqual(c.errors, [], c.errors.map(\.description).joined(separator: "\n"))
        XCTAssertEqual(c.config.envVars.first?.0, "A")
        XCTAssertEqual(c.config.execOnce, ["echo hi"])
        XCTAssertEqual(c.config.mouseBindings.count, 1)
        XCTAssertEqual(c.config.axisBindings.count, 1)
        XCTAssertEqual(c.config.gestureBindings.count, 1)
        XCTAssertEqual(c.config.keyBindings.count, 1, "mango's regex ^bind[s|l|r|p|c]*$ takes the bar")
        XCTAssertEqual(parse("execx=echo").errors.map(\.message.plain), ["Unknown keyword: execx"],
                       "exec is matched whole (strncmp with 9)")
    }

    func testATomlMousebindSectionTakesFlags() {
        let p = parse("""
        [mousebind.default.sym]
        "SUPER+btn_left" = "moveresize,curmove"
        """, name: "t.toml")
        XCTAssertEqual(p.errors, [], p.errors.map(\.description).joined(separator: "\n"))
        XCTAssertEqual(p.config.mouseBindings.count, 1)
    }

    func testEveryErrorOfALineIsPrintedThenOneIndex() {
        let p = parse("bind=FOO,nosuchkey_x,nosuchdispatch")
        XCTAssertEqual(p.errors.map(\.message.plain),
                       ["Unknown key: nosuchkey_x", "Unknown modifier: FOO", "Unknown dispatch in bind: nosuchdispatch"])
        XCTAssertEqual(p.errors.map(\.reportsLine), [false, false, true])

        let rule = parse("window_rule=app_id:x,foo:1,bar:2")
        XCTAssertEqual(rule.errors.map(\.reportsLine), [false, true])
        XCTAssertEqual(rule.config.windowRules.count, 1)

        let code = parse("bind=code:999+SUPER,a,quit")
        XCTAssertEqual(code.config.keyBindings.count, 1, "the binding is made")
        XCTAssertEqual(code.errors.map(\.message.plain), ["unknown modifier keycode: code:999"])
        XCTAssertEqual(code.errors.map(\.reportsLine), [false], "parse_option returns true: no [Index]")
    }

    func testAMissingSourceIsOneMessageWithoutIndex() {
        let p = parse("source=/nonexistent/mango-missing.conf\nborder_px=2")
        XCTAssertEqual(p.errors.map(\.message.plain), ["Failed to open config file: /nonexistent/mango-missing.conf"])
        XCTAssertEqual(p.errors.map(\.reportsLine), [false])
        XCTAssertEqual(p.config.borderpx, 2)
    }

    func testASourcedDirectoryReadsAsNothing() throws {
        let dir = try makeTempDir()
        let p = parse("source=\(dir.path)")
        XCTAssertEqual(p.errors, [])
    }

    func testAnEmptyKeyIsAnUnknownKeyword() {
        XCTAssertEqual(parse(" =x").errors.map(\.message.plain), ["Unknown keyword: "])
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

    func testParseButtonCodeForms() {
        var errors: [String] = []
        XCTAssertNil(parseButton("code:abc") { errors.append($0) })
        XCTAssertNil(parseButton("code:-1") { errors.append($0) })
        XCTAssertEqual(errors.map(\.plain), ["Invalid code format: code:abc", "Invalid code format: code:-1"])
        XCTAssertEqual(parseButton("code:272"), .left)
        XCTAssertEqual(parseButton("code:+273"), .right)
    }

    func testParseColorIsStrtol() {
        XCTAssertNil(parseColor("0x"))
        XCTAssertNil(parseColor("-1"))
        XCTAssertEqual(parseColor("+ff"), RGBA(r: 0, g: 0, b: 0, a: 1))
        XCTAssertEqual(parseColor("-2"), RGBA(r: 1, g: 1, b: 1, a: 254.0 / 255))
        XCTAssertNil(parseColor("0xzz"))
    }

    func testSimpleBindingConflictsGoByTheFirstBinding() {
        let p = parse("""
        mousebind=SUPER,btn_left,killclient
        mousebind=SUPER,btn_right,killclient
        mousebind=SUPER,btn_right,killclient
        mousebind=SUPER,btn_left,killclient
        """)
        XCTAssertEqual(p.errors.map(\.line), [4, 3], "pairs (1, 4) then (2, 3), as check_simple_binding_conflicts")
    }
}
