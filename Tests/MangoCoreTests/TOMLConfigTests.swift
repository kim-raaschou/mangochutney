import XCTest
@testable import Mango
@testable import Port

final class TOMLConfigTests: MangoTestCase {
    func parse(_ text: String, name: String = "t.toml") -> ParsedConfig {
        ConfigParser.parse(text: text, baseDirectory: nil, fileName: name)
    }

    func testConfAndTomlGiveTheSameConfig() {
        let conf = """
        var=term,foot
        env=QT_IM_MODULE,fcitx
        gap_inner_horizontal=7
        focus_color=0x201b14ff
        animation_curve_open=0.46,1.0,0.29,1
        circle_layout=tile,scroller,monocle
        sloppy_focus=1
        exec_once=waybar
        exec_once=swaybg -i wall.png
        bind=Alt,Return,spawn,$term
        bind=SUPER+SHIFT,Left,move_client,left
        bindl=CTRL,comma,spawn,brightness.sh down
        bindc=SUPER,r,spawn_shell,config-check.sh
        bindc=SUPER,r,reload_config
        key_mode=resize
        bind=SUPER,Left,resizewin,-10,0
        key_mode=default
        mousebind=SUPER,btn_left,moveresize,curmove
        axisbind=SUPER,UP,viewtoleft_have_client
        gesturebind=none,left,3,focusdir,left
        window_rule=is_floating:1,width:800,height:900,app_id:mpv
        tag_rule=id:1,layout_name:tile
        """
        let toml = """
        [var]
        term = "foot"

        [env]
        "QT_IM_MODULE" = "fcitx"

        [global]
        gap_inner_horizontal = 7
        focus_color = 0x201b14ff
        animation_curve_open = [0.46, 1.0, 0.29, 1]
        circle_layout = ["tile", "scroller", "monocle"]
        sloppy_focus = true
        exec_once = ["waybar", "swaybg -i wall.png"]

        [bind.default]
        "Alt+Return" = "spawn,$term"
        "SUPER+SHIFT+Left" = "move_client,left"

        [bind.default.lock]
        "CTRL+comma" = "spawn,brightness.sh down"

        [bind.default.conflict]
        "SUPER+r" = [
          "spawn_shell,config-check.sh",
          "reload_config"
        ]

        [bind.resize]
        "SUPER+Left" = "resizewin,-10,0"

        [mousebind.default]
        "SUPER+btn_left" = "moveresize,curmove"

        [axisbind.default]
        "SUPER+UP" = "viewtoleft_have_client"

        [gesturebind.default]
        "none+left+3" = "focusdir,left"

        [[rule.window_rule]]
        is_floating = 1
        width = 800
        height = 900
        app_id = "mpv"

        [[rule.tag_rule]]
        id = 1
        layout_name = "tile"
        """
        let a = parse(conf, name: "t.conf"), b = parse(toml)
        XCTAssertEqual(a.errors, [])
        XCTAssertEqual(b.errors, [])
        let x = a.config, y = b.config
        XCTAssertEqual(x.keyBindings, y.keyBindings)
        XCTAssertEqual(x.keyBindings.count, 6)
        XCTAssertEqual(x.mouseBindings, y.mouseBindings)
        XCTAssertEqual(x.axisBindings, y.axisBindings)
        XCTAssertEqual(x.gestureBindings, y.gestureBindings)
        XCTAssertEqual(x.windowRules, y.windowRules)
        XCTAssertEqual(x.tagRules, y.tagRules)
        XCTAssertEqual(x.envVars.map { "\($0)=\($1)" }, y.envVars.map { "\($0)=\($1)" })
        XCTAssertEqual(x.execOnce, y.execOnce)
        XCTAssertEqual(x.gappih, y.gappih)
        XCTAssertEqual(x.focuscolor, y.focuscolor)
        XCTAssertEqual(x.animationCurveOpen, y.animationCurveOpen)
        XCTAssertEqual(x.circleLayout, y.circleLayout)
        XCTAssertEqual(x.sloppyfocus, y.sloppyfocus)
        XCTAssertTrue(y.sloppyfocus, "true maps to 1")
        XCTAssertEqual(y.keyBindings.first { $0.mode == "resize" }?.dispatch.name, "resizewin")
        XCTAssertEqual(y.keyBindings.first { $0.keyName == "Return" }?.dispatch.args, ["foot"], "$term expanded")
    }

    static var mangoRoot: String {
        ProcessInfo.processInfo.environment["MANGO_SOURCES"] ?? NSHomeDirectory() + "/sources/mango"
    }

    func testMangoDocsExamplesLoadWithoutErrors() throws {
        let path = Self.mangoRoot + "/docs/configuration/toml.md"
        try XCTSkipUnless(FileManager.default.fileExists(atPath: path), "no mango checkout")
        let md = try String(contentsOfFile: path, encoding: .utf8).replacingOccurrences(of: "\r\n", with: "\n")
        var blocks: [String] = []
        var current: [Substring]?
        for line in md.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("```toml") { current = []; continue }
            if line.hasPrefix("```"), let c = current { blocks.append(c.joined(separator: "\n")); current = nil; continue }
            current?.append(line)
        }
        XCTAssertGreaterThanOrEqual(blocks.count, 6)
        for (i, block) in blocks.enumerated() where !block.contains("source") {
            XCTAssertEqual(parse(block).errors.map(\.message), [], "block \(i + 1)")
        }
    }

    func testMangoAuthorsTomlConfigLoads() throws {
        let root = ProcessInfo.processInfo.environment["MANGO_CONFIG_SOURCES"] ?? NSHomeDirectory() + "/sources/mango-config"
        let url = URL(fileURLWithPath: root + "/config.toml")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path), "no mango-config checkout (toml branch)")
        let parsed = ConfigParser.parseConfig(fileAt: url)
        XCTAssertEqual(parsed.errors.map(\.description), [])
        XCTAssertEqual(parsed.sourcedFiles.count, 8, "config.toml and the seven files it sources")
        XCTAssertGreaterThan(parsed.config.keyBindings.count, 80)
        XCTAssertGreaterThan(parsed.config.windowRules.count, 20)
        XCTAssertFalse(parsed.config.envVars.isEmpty)
    }

    func testFormatFollowsExtensionThenFirstCharacter() {
        XCTAssertEqual(ConfigParser.detectConfigFormat(fileName: "a.toml", text: "x=1"), .toml)
        XCTAssertEqual(ConfigParser.detectConfigFormat(fileName: "a.TOML", text: "x=1"), .toml)
        XCTAssertEqual(ConfigParser.detectConfigFormat(fileName: "a.conf", text: "[global]"), .conf)
        XCTAssertEqual(ConfigParser.detectConfigFormat(fileName: "config", text: "# comment\n\n  [global]\n"), .toml)
        XCTAssertEqual(ConfigParser.detectConfigFormat(fileName: "config", text: "# [not this]\nborder_px=2\n"), .conf)
        XCTAssertEqual(ConfigParser.detectConfigFormat(fileName: "config", text: ""), .conf)
    }

    func testDefaultConfigIsConfThenToml() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("mango-home-\(UUID().uuidString)")
        let dir = home.appendingPathComponent(".config/mango")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let previous = getenv("HOME").map { String(cString: $0) }
        setenv("HOME", home.path, 1)
        defer {
            if let previous { setenv("HOME", previous, 1) } else { unsetenv("HOME") }
            try? FileManager.default.removeItem(at: home)
        }
        XCTAssertEqual(ConfigParser.defaultConfigURL().lastPathComponent, "config.conf", "neither: conf")
        try "[global]\n".write(to: dir.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        XCTAssertEqual(ConfigParser.defaultConfigURL().lastPathComponent, "config.toml", "only toml")
        try "border_px=1\n".write(to: dir.appendingPathComponent("config.conf"), atomically: true, encoding: .utf8)
        XCTAssertEqual(ConfigParser.defaultConfigURL().lastPathComponent, "config.conf", "both: conf wins")
    }

    func testTomlSourcedFromConfAndConfFromToml() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mango-toml-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "source=./b.toml\nborder_px=3\n".write(to: dir.appendingPathComponent("a.conf"), atomically: true, encoding: .utf8)
        try "[global]\ngap_inner_vertical = 9\nsource = \"./c.conf\"\n".write(to: dir.appendingPathComponent("b.toml"), atomically: true, encoding: .utf8)
        try "gap_outer_vertical=11\n".write(to: dir.appendingPathComponent("c.conf"), atomically: true, encoding: .utf8)
        let p = ConfigParser.parseConfig(fileAt: dir.appendingPathComponent("a.conf"))
        XCTAssertEqual(p.errors, [])
        XCTAssertEqual(p.config.borderpx, 3)
        XCTAssertEqual(p.config.gappiv, 9)
        XCTAssertEqual(p.config.gappov, 11)
    }

    func testScalars() {
        typealias S = ParserState
        XCTAssertEqual(S.tomlScalar(#""a\tb\"c\\d\x""#, mapBool: true), "a\tb\"c\\d\\x", "known escapes, unknown kept")
        XCTAssertEqual(S.tomlScalar(#"'C:\path'"#, mapBool: true), #"C:\path"#, "literal string")
        XCTAssertEqual(S.tomlScalar("true", mapBool: true), "1")
        XCTAssertEqual(S.tomlScalar("false", mapBool: true), "0")
        XCTAssertEqual(S.tomlScalar("true", mapBool: false), "true", "env/var keep the word")
        XCTAssertEqual(S.tomlScalar(" 0x201b14ff ", mapBool: true), "0x201b14ff")
    }

    func testArraysAndContinuedStatements() {
        typealias S = ParserState
        XCTAssertEqual(S.tomlForeachArrayElement(#"["a, b", 'c', [1, 2], 3]"#), [#""a, b""#, " 'c'", " [1, 2]", " 3"])
        XCTAssertEqual(S.tomlForeachArrayElement("[1, 2,]"), ["1", " 2", ""])
        XCTAssertFalse(S.tomlStatementComplete("source = ["))
        XCTAssertFalse(S.tomlStatementComplete(#"x = "a ]"#))
        XCTAssertTrue(S.tomlStatementComplete(#"x = "a ] b""#))
        XCTAssertTrue(S.tomlStatementComplete("[bind.default]"))
        XCTAssertEqual(S.removeTomlComment(#"x = "a # b" # c"#), #"x = "a # b" "#)
        XCTAssertEqual(S.removeTomlComment(#"x = 'it''s' # c"#), #"x = 'it''s' "#)
    }

    func testBindKeys() {
        typealias S = ParserState
        XCTAssertEqual(S.tomlBindPrefix(base: "bind", combo: "SUPER+SHIFT+Return"), "SUPER+SHIFT,Return,")
        XCTAssertEqual(S.tomlBindPrefix(base: "bind", combo: "XF86AudioMute"), "none,XF86AudioMute,")
        XCTAssertEqual(S.tomlBindPrefix(base: "gesturebind", combo: "none+left+3"), "none,left,3,")
        XCTAssertNil(S.tomlBindPrefix(base: "gesturebind", combo: "left+3"))
        XCTAssertEqual(S.tomlBindPrefix(base: "switchbind", combo: "fold"), "fold,")
        let p = parse("""
        [keybind.default.release.pass]
        "SUPER+a" = "spawn,x"
        [bind.default.sym]
        "SUPER+b" = "spawn,y"
        """)
        XCTAssertEqual(p.errors, [])
        XCTAssertEqual(p.config.keyBindings.map(\.flags), [[.release, .passthrough], [.keysym]])
    }

    func testKeyModeOfABindSectionEndsWithTheSection() {
        let p = parse("""
        [bind.resize]
        "SUPER+Left" = "resizewin,-10,0"
        [global]
        bind = "SUPER,q,killclient"
        """)
        XCTAssertEqual(p.errors, [])
        XCTAssertEqual(p.config.keyBindings.map(\.mode), ["resize", "default"])
    }

    func testErrorsLikeMango() {
        let p = parse("""
        [bind]
        "SUPER+a" = "spawn,x"
        [bind.default.fast]
        "SUPER+b" = "spawn,y"
        [rule.window]
        app_id = "x"
        [nonsense]
        a = 1
        [global]
        just text
        """)
        XCTAssertEqual(p.errors.map(\.message.plain), [
            "Bind keymode is required, e.g. [bind.default]",
            "Unknown bind flag: fast",
            "Unknown toml rule type: window",
            "Unknown toml section: nonsense",
            "Invalid toml line format: just text",
        ])
        XCTAssertEqual(p.errors.map(\.line), [1, 3, 5, 7, 10])
        XCTAssertTrue(p.config.keyBindings.isEmpty, "skipped sections add nothing")
    }

    func testRuleErrorsPointAtTheSection() {
        let p = parse("""
        [[rule.window_rule]]
        app_id = "x"
        no_such_field = 1
        """)
        XCTAssertEqual(p.errors.map(\.line), [1])
        XCTAssertEqual(p.errors.first?.message.plain, "Unknown window rule option:no_such_field")
    }

    func testUnknownOptionIsReportedWithItsLine() {
        let p = parse("[global]\nborder_px = 2\nborder_pxx = 3\n")
        XCTAssertEqual(p.errors.map(\.description.plain), ["t.toml:3: Unknown keyword: border_pxx"])
    }
}
