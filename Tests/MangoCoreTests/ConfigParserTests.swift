import XCTest
@testable import Mango
@testable import Port

final class ConfigParserTests: MangoTestCase {
    private func parse(_ text: String, base: URL? = nil) -> ParsedConfig {
        ConfigParser.parse(text: text, baseDirectory: base ?? FileManager.default.temporaryDirectory,
                           fileName: "test.conf")
    }

    func testEachBarHasItsOwnIconKey() {
        let tab = parse("chutney_tab_bar_decorate_icon=1").config
        XCTAssertTrue(tab.chutneyTabBarDecorateIcon)
        XCTAssertFalse(tab.chutneyGroupBarDecorateIcon, "as mango's tab_bar_ and group_bar_ keys")
        let group = parse("chutney_group_bar_decorate_icon=1").config
        XCTAssertFalse(group.chutneyTabBarDecorateIcon)
        XCTAssertTrue(group.chutneyGroupBarDecorateIcon)
    }

    private var defaultConfigURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/config.conf")
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mango-config-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func outsideKeyBindings(_ text: String) -> [String] {
        var lines = text.components(separatedBy: "\r\n")
        if let keys = lines.firstIndex(of: "# Key Bindings"), let gestures = lines.firstIndex(of: "# Gesture Bindings") {
            lines.removeSubrange(keys..<gestures)
        }
        while let start = lines.firstIndex(where: { $0.hasPrefix("# not mango default:") }),
              let end = lines[start...].firstIndex(of: "# end not mango default") {
            lines.removeSubrange(start...end)
        }
        return lines.filter { !$0.hasPrefix("# Mango Chutney:") }
    }

    func testShippedConfigParsesWithoutErrors() throws {
        let url = defaultConfigURL
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), url.path)
        let parsed = ConfigParser.parseConfig(fileAt: url)
        XCTAssertEqual(parsed.errors, [], parsed.errors.map(\.description).joined(separator: "\n"))
        XCTAssertEqual(parsed.sourcedFiles.first?.path, url.standardizedFileURL.path)

        let text = try String(contentsOf: url, encoding: .utf8)
        let marker = try XCTUnwrap(text.range(of: "\r\n" + ConfigFiles.portMarker), "the port's keys come last")
        let mangoText = String(text[..<marker.lowerBound])
        let stock = URL(fileURLWithPath: (ProcessInfo.processInfo.environment["MANGO_SOURCES"]
            ?? NSHomeDirectory() + "/sources/mango") + "/assets/config.conf")
        if let mangoFile = try? String(contentsOf: stock, encoding: .utf8) {
            XCTAssertEqual(outsideKeyBindings(mangoText), outsideKeyBindings(mangoFile),
                           "mango's own file but for its key bindings: merge mango's changes")
        }
        let mango = parse(mangoText, base: url.deletingLastPathComponent())
        XCTAssertEqual(mango.errors, [])
        let c = mango.config
        XCTAssertEqual(c.keyBindings.count, mangoText.components(separatedBy: "\r\n").filter { $0.hasPrefix("bind=") }.count)
        XCTAssertEqual(c.mouseBindings.count, 2)
        XCTAssertEqual(c.axisBindings.count, 2)
        XCTAssertEqual(c.gestureBindings.count, 8)
        XCTAssertEqual(c.tagRules.count, 9)
        XCTAssertEqual(c.tagRules.first?.layoutName, "tile")
        XCTAssertTrue(c.sloppyfocus, "mango's value")
        XCTAssertEqual([c.animationDurationMove, c.animationDurationOpen, c.animationDurationTag], [500, 400, 350])
        XCTAssertEqual(c.focuscolor, parseColor("0xc9b890ff"))
        XCTAssertFalse(c.chutneyMenuBar)
        XCTAssertFalse(c.chutneyMacOSAppearance, "mango's look unless chutney_macos_appearance is set")
        let reload = c.keyBindings.first { $0.dispatch.name == "reload_config" }
        XCTAssertEqual(reload?.mods, .hyper, "mango's keys on Hyper")
        XCTAssertEqual(reload?.keyName, "r")
        XCTAssertEqual(c.keyBindings.first { $0.dispatch.name == "view" }?.dispatch.args, ["1", "0"], "mango's own arguments")
    }

    func testThePortsNamesCarryItsPrefix() {
        for k in MangoCompat.portExtensionOptions.keys { XCTAssertTrue(k.hasPrefix("chutney_"), k) }
        for d in MangoCompat.portDispatchers { XCTAssertTrue(d.hasPrefix("chutney_"), d) }
        XCTAssertFalse(parse("macos_style=1").errors.isEmpty)
    }

    func testShippedConfigReadsTheMacOSDefaultsLast() throws {
        let parsed = ConfigParser.parseConfig(fileAt: defaultConfigURL)
        XCTAssertEqual(parsed.sourcedFiles.map(\.lastPathComponent), ["config.conf", "chutney_theme.conf", "chutney_menu.conf"])
        let c = parsed.config
        XCTAssertTrue(c.chutneyMenuBar)
        XCTAssertEqual(c.chutneyMenuConfig, "chutney_menu.conf")
        XCTAssertEqual([c.animationDurationMove, c.animationDurationOpen, c.animationDurationTag], [500, 400, 350], "mango's")
        XCTAssertTrue(c.sloppyfocus, "mango's")
        XCTAssertTrue(c.chutneyMacOSAppearance)
        XCTAssertTrue(c.chutneyTabBarDecorateIcon)
        XCTAssertTrue(c.chutneyGroupBarDecorateIcon)
        XCTAssertEqual(c.chutneyHyperModifier, "super+ctrl+alt")
        let hotkeys = c.keyBindings.first { $0.dispatch.name == "chutney_keybindings" }
        XCTAssertEqual(hotkeys?.mods, .hyper, "on the Hyper layer")
        XCTAssertEqual(hotkeys?.keyName, "k")
        XCTAssertEqual(c.xkbRulesOptions, "", "Caps Lock as Hyper is chutney_hyper_key's")
        XCTAssertEqual(c.chutneyHyperKey, "caps_lock")

        let text = try String(contentsOf: defaultConfigURL, encoding: .utf8)
        let port = try XCTUnwrap(text.range(of: ConfigFiles.portMarker))
        for line in text[port.lowerBound...].components(separatedBy: "\r\n") where !line.hasPrefix("#") && line.contains("=") {
            let key = line.prefix { $0 != "=" }
            XCTAssertTrue(key.hasPrefix("chutney_") || key == "source_optional" || key.hasPrefix("bind"),
                          "the port's keys set a mango key: \(line)")
        }
    }

    /// A value's "\r" is trimmed as mango's trim_whitespace does. An empty line of a CRLF file is
    /// "\r\n", which mango does not skip: "Invalid line format" for each. Ours skips it as an empty
    /// line (a mango bug, docs/afvigelser.md §6).
    func testCRLFLineEndings() {
        let parsed = parse("# comment\r\nborder_px=3\r\n\r\nbind=SUPER,a,quit\r\nnope=1\r\njump_labels=\r\n")
        XCTAssertEqual(parsed.config.borderpx, 3)
        XCTAssertEqual(parsed.config.keyBindings.count, 1)
        XCTAssertEqual(parsed.errors.map(\.line), [5], "line 3, the empty one, is skipped")
        XCTAssertEqual(parsed.config.jumpLabels, "", "\"\\r\" is a value in mango's sscanf, trimmed to empty")
    }

    func testValueTooLong() {
        let parsed = parse("jump_labels=" + String(repeating: "A", count: 256))
        XCTAssertEqual(parsed.errors.count, 1)
        XCTAssertTrue(parsed.errors[0].message.contains("exceeds 255 bytes"))
        XCTAssertEqual(parsed.config.jumpLabels, Config().jumpLabels)

        let max = parse("jump_labels=" + String(repeating: "A", count: 255) + "\n")
        XCTAssertEqual(max.errors, [], "the newline is not counted")
        XCTAssertEqual(max.config.jumpLabels.utf8.count, 255)
    }

    /// mango's sscanf("%255[^=]=%255[^\n]") reads no value from "key=" and a newline: Invalid line format.
    func testKeyWithoutValueIsInvalid() {
        let parsed = parse("border_px=\nexec_once=\nborder_px=")
        XCTAssertEqual(parsed.errors.map(\.line), [1, 2, 3])
        XCTAssertTrue(parsed.errors.allSatisfy { $0.message.plain.hasPrefix("Invalid line format") })
        XCTAssertEqual(parsed.config.borderpx, Config().borderpx)
        XCTAssertEqual(parsed.config.execOnce, [])
    }

    /// fgets(line, 512): a longer line is read in pieces of 511 bytes, each a line of its own.
    func testLongLinesAreReadAsFgetsDoes() {
        let long = parse("jump_labels=" + String(repeating: "A", count: 588) + "\nborder_px=3\n")
        XCTAssertEqual(long.errors.map(\.line), [1, 2])
        XCTAssertTrue(long.errors[0].message.contains("exceeds 255 bytes"))
        XCTAssertTrue(long.errors[1].message.plain.hasPrefix("Invalid line format"))
        XCTAssertEqual(long.config.borderpx, 3)

        let line = "border_px=5 #"
        let exact = parse(line + String(repeating: "x", count: 511 - line.utf8.count) + "\nnope\n")
        XCTAssertEqual(exact.config.borderpx, 5)
        XCTAssertEqual(exact.errors.map(\.line), [3], "the newline after 511 bytes is a line of its own")
    }

    /// mango fopen's a source file; one that cannot be read is "Failed to open config file".
    func testUnreadableSourceFails() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("locked.conf")
        try "border_px=7\n".write(to: file, atomically: true, encoding: .utf8)
        chmod(file.path, 0)
        defer { chmod(file.path, 0o600) }
        let parsed = parse("source=\(file.path)\n")
        XCTAssertEqual(parsed.errors.first?.message.plain, "Failed to open config file: \(file.path)")
        XCTAssertEqual(parsed.config.borderpx, Config().borderpx)
        XCTAssertEqual(parse("source_optional=\(file.path)\n").errors, [])
    }

    /// libc's numbers: atoi is glibc's (int)strtol, atof and %f are strtod's (hex floats; inf and nan
    /// are 0, as Swift traps on them), sanitize_string trims what isprint (C locale) refuses, bytes
    /// above ASCII too.
    func testNumbersAreLibcs() {
        XCTAssertEqual(ValueParse.atoi("3000000000"), -1294967296)
        XCTAssertEqual(ValueParse.atoi("99999999999"), 1215752191)
        XCTAssertEqual(ValueParse.atoi("99999999999999999999"), -1, "LONG_MAX as an int")
        XCTAssertEqual(ValueParse.atoi("-99999999999999999999"), 0, "LONG_MIN as an int")
        XCTAssertEqual(ValueParse.atoi(" 12abc"), 12)
        XCTAssertEqual(ValueParse.atof("0x1p3"), 8)
        XCTAssertEqual(ValueParse.atof("inf"), 0)
        XCTAssertEqual(ValueParse.atof("-Infinity"), 0)
        XCTAssertEqual(ValueParse.atof("nan"), 0)
        XCTAssertEqual(ValueParse.atof("1.5x"), 1.5)
        XCTAssertEqual(ValueParse.atof("x"), 0)
        XCTAssertEqual(ValueParse.scanDouble("0x.8"), 0.5)
        XCTAssertNil(ValueParse.scanDouble("x"))
        var v: [Double] = []
        XCTAssertEqual(ValueParse.parseDoubleArray("0x1p-1, 1e0,inf", &v, 4).0, 3)
        XCTAssertEqual(Array(v.prefix(3)), [0.5, 1, 0])
        XCTAssertEqual(ValueParse.parseDoubleArray("1,2x", &v, 4).0, -1)
        XCTAssertEqual(ValueParse.sanitizeString("\u{01}tile\r"), "tile")
        XCTAssertEqual(ValueParse.sanitizeString("scroll\u{E9}"), "scroll", "é is two bytes isprint refuses")
        XCTAssertEqual(ValueParse.sanitizeString(" tile "), " tile ", "a space is printable")
    }

    /// mango's env and resolve_config_path fail without HOME: "HOME environment variable not set."
    func testHomeNotSet() {
        let previous = getenv("HOME").map { String(cString: $0) }
        unsetenv("HOME")
        defer { if let previous { setenv("HOME", previous, 1) } }
        let parsed = parse("env=A,~/x\nsource=~/x.conf\n")
        XCTAssertEqual(parsed.errors.map(\.message), ["HOME environment variable not set.", "HOME environment variable not set."])
        XCTAssertTrue(parsed.config.envVars.isEmpty)
    }

    func testVariables() {
        let parsed = parse("""
        var=gap,7
        var=big,${gap}0
        gap_inner_horizontal=$gap
        gap_outer_horizontal=${big}
        var=mod,SUPER+SHIFT
        bind=$mod,a,spawn,echo $undefined ${alsoundefined} $gap
        var=1bad,x
        """)
        XCTAssertEqual(parsed.config.gappih, 7)
        XCTAssertEqual(parsed.config.gappoh, 70)
        XCTAssertEqual(parsed.config.keyBindings.first?.mods, [.superKey, .shift])
        XCTAssertEqual(parsed.config.keyBindings.first?.dispatch.args, ["echo $undefined ${alsoundefined} 7"])
        XCTAssertEqual(parsed.errors.count, 1)
        XCTAssertEqual(parsed.errors.first?.line, 7)
    }

    func testSourceAndSourceOptional() throws {
        let dir = try makeTempDir()
        try "var=g,11\nborder_px=$g\nbind=SUPER,a,quit\n"
            .write(to: dir.appendingPathComponent("extra.conf"), atomically: true, encoding: .utf8)
        try "unknown_thing=1\n"
            .write(to: dir.appendingPathComponent("bad.conf"), atomically: true, encoding: .utf8)
        let main = dir.appendingPathComponent("config.conf")
        try """
        key_mode=resize
        source=./extra.conf
        gap_inner_vertical=$g
        source_optional=./does-not-exist.conf
        source=./missing.conf
        source=bad.conf
        """.write(to: main, atomically: true, encoding: .utf8)

        let parsed = ConfigParser.parseConfig(fileAt: main)
        XCTAssertEqual(parsed.config.borderpx, 11)
        XCTAssertEqual(parsed.config.gappiv, 11, "variables are shared across sourced files")
        XCTAssertEqual(parsed.config.keyBindings.first?.mode, "resize", "key_mode carries into sourced files")
        XCTAssertEqual(parsed.errors.count, 2, parsed.errors.map(\.description).joined(separator: "\n"))
        XCTAssertEqual(parsed.errors[0].file, main.standardizedFileURL.path)
        XCTAssertEqual(parsed.errors[0].line, 5)
        XCTAssertTrue(parsed.errors[0].message.contains("Failed to open"))
        XCTAssertTrue(parsed.errors[1].file.hasSuffix("bad.conf"))
        XCTAssertEqual(parsed.errors[1].line, 1)
        XCTAssertEqual(parsed.errors[1].message.plain, "Unknown keyword: unknown_thing")
        XCTAssertEqual(parsed.sourcedFiles.map(\.lastPathComponent),
                       ["config.conf", "extra.conf", "does-not-exist.conf", "missing.conf", "bad.conf"])
    }

    func testRecursiveSourceIsReported() throws {
        let dir = try makeTempDir()
        let main = dir.appendingPathComponent("config.conf")
        try "source=./config.conf\nborder_px=2\n".write(to: main, atomically: true, encoding: .utf8)
        let parsed = ConfigParser.parseConfig(fileAt: main)
        XCTAssertEqual(parsed.errors.count, 1)
        XCTAssertEqual(parsed.config.borderpx, 2)
    }

    func testMissingMainFile() {
        let parsed = ConfigParser.parseConfig(fileAt: URL(fileURLWithPath: "/nonexistent/mango/config.conf"))
        XCTAssertEqual(parsed.errors.count, 1)
        XCTAssertEqual(parsed.config.borderpx, Config().borderpx)
    }

    func testDefaultConfigURL() {
        let url = ConfigParser.defaultConfigURL()
        XCTAssertTrue(url.path.hasSuffix("mango/config.conf"))
    }

    func testEnvAndExec() {
        let parsed = parse("""
        env=QT_SCALE,2
        env=MY_PATH,~/bin
        exec=echo reload
        exec_once=echo once
        env=broken
        """)
        XCTAssertEqual(parsed.config.envVars.count, 2)
        XCTAssertEqual(parsed.config.envVars[0].0, "QT_SCALE")
        XCTAssertEqual(parsed.config.envVars[0].1, "2")
        XCTAssertFalse(parsed.config.envVars[1].1.hasPrefix("~"))
        XCTAssertTrue(parsed.config.envVars[1].1.hasSuffix("/bin"))
        XCTAssertEqual(parsed.config.exec, ["echo reload"])
        XCTAssertEqual(parsed.config.execOnce, ["echo once"])
        XCTAssertEqual(parsed.errors.count, 1)
    }

    func testBindFlags() {
        let parsed = parse("""
        bind=SUPER,a,quit
        binds=SUPER,b,quit
        bindlr=SUPER,c,quit
        bindpc=SUPER,d,quit
        bindslrpc=SUPER,e,quit
        bindx=SUPER,f,quit
        """)
        let b = parsed.config.keyBindings
        XCTAssertEqual(b.count, 5)
        XCTAssertEqual(b[0].flags, [])
        XCTAssertEqual(b[1].flags, [.keysym])
        XCTAssertEqual(b[2].flags, [.locked, .release])
        XCTAssertEqual(b[3].flags, [.passthrough, .allowConflict])
        XCTAssertEqual(b[4].flags, [.keysym, .locked, .release, .passthrough, .allowConflict])
        XCTAssertEqual(parsed.errors.map(\.message.plain), ["Unknown keyword: bindx"])
    }

    func testModifiersIncludingHyper() {
        let parsed = parse("""
        bind=SUPER+SHIFT,a,quit
        bind=ctrl+alt,a,quit
        bind=NONE,F5,quit
        bind=HYPER,h,quit
        chutney_hyper_modifier=ctrl+alt
        bind=hyper,j,quit
        bind=bogus,k,quit
        """)
        let b = parsed.config.keyBindings
        XCTAssertEqual(b.count, 5)
        XCTAssertEqual(b[0].mods, [.superKey, .shift])
        XCTAssertEqual(b[1].mods, [.ctrl, .alt])
        XCTAssertEqual(b[2].mods, [])
        XCTAssertEqual(b[2].keyCodes, [96])
        XCTAssertEqual(b[3].mods, .hyper, "mango's Mod3, not the hyper set")
        XCTAssertEqual(b[4].mods, .hyper)
        XCTAssertEqual(parsed.errors.count, 1)
        XCTAssertEqual(parsed.errors[0].line, 7)
        XCTAssertTrue(parsed.errors[0].message.hasPrefix("Unknown modifier"))
    }

    // mango's option_defs.c keeps sscanf's fields, the last one the rest of the line; parse_func_name
    // joins spawn's and setoption's, and gives spawn_on_empty and toggle_named_scratchpad one field each
    @MainActor
    func testBindingFieldsAreSscanfsAndParseFuncNameJoinsThem() {
        let parsed = parse("""
        bind=SUPER,a,spawn,notify-send "a, b" ,c
        bind=SUPER,b,spawn_shell,echo 1,2,3,4,5,6,7 | cat
        bind=SUPER,c,spawn_on_empty,firefox --new-window a,b,4
        bind=SUPER,d,toggle_named_scratchpad,com.app,none,open -a X,Y
        bind=SUPER,e,killclient,
        bind=SUPER,f,setoption,circle_layout,tile,scroller,grid
        """)
        XCTAssertEqual(parsed.errors, [])
        let d = parsed.config.keyBindings.map(\.dispatch)
        XCTAssertEqual(d[0], Dispatch(name: "spawn", args: ["notify-send \"a", "b\"", "c"]))
        XCTAssertEqual(d[1], Dispatch(name: "spawn_shell", args: ["echo 1", "2", "3", "4", "5,6,7 | cat"]))
        XCTAssertEqual(d[2], Dispatch(name: "spawn_on_empty", args: ["firefox --new-window a", "b", "4"]))
        XCTAssertEqual(d[3], Dispatch(name: "toggle_named_scratchpad", args: ["com.app", "none", "open -a X", "Y"]))
        XCTAssertEqual(d[4], Dispatch(name: "killclient", args: []))
        XCTAssertEqual(d[5], Dispatch(name: "setoption", args: ["circle_layout", "tile", "scroller", "grid"]))

        func arg(_ d: Dispatch) -> Arg {
            var arg = Arg()
            let a = (0..<5).map { $0 < d.args.count ? d.args[$0] : d.name == "setoption" ? "" : "0" }   // as dispatch gives them
            _ = BindingParser.parseFuncName(d.name, &arg, a[0], a[1], a[2], a[3], a[4])
            return arg
        }
        XCTAssertEqual(arg(d[0]).v, "notify-send \"a,b\",c")
        XCTAssertEqual(arg(d[1]).v, "echo 1,2,3,4,5,6,7 | cat")
        XCTAssertEqual(arg(d[2]).v, "firefox --new-window a")
        XCTAssertEqual(arg(d[2]).ui, 0, "parse_tag_mask(\"b\")")
        XCTAssertEqual(arg(d[3]).v3, "open -a X")
        XCTAssertEqual(arg(d[5]).v2, "tile,scroller,grid")
    }

    func testParseDispatch() {
        let parsed = parse("""
        bind=SUPER,a,view, 1 ,0
        bind=SUPER,b,focusdir,left,,x
        bind=SUPER,c,movewin,1,2,3,4,5,,6
        bind=SUPER,d,dwindle_toggle_current_split
        bind=SUPER,e,nonsense,1
        """)
        let d = parsed.config.keyBindings.map(\.dispatch)
        XCTAssertEqual(d[0], Dispatch(name: "view", args: ["1", "0"]))
        XCTAssertEqual(d[1].args, ["left"])
        XCTAssertEqual(d[2].args, ["1", "2", "3", "4", "5,,6"], "the last field is the rest of the line")
        XCTAssertEqual(d[3].name, "dwindle_toggle_current_split")
        XCTAssertEqual(d.count, 4)
        XCTAssertTrue(parsed.errors[0].message.contains("Unknown dispatch in bind"))
        XCTAssertTrue(parsed.errors[0].message.contains("nonsense"))
    }

    func testBindErrors() {
        let parsed = parse("""
        bind=SUPER,a,no_such_dispatcher
        bind=SUPER,NoSuchKeyName,quit
        bind=SUPER,a
        mousebind=SUPER,btn_nothing,quit
        axisbind=SUPER,diagonal,quit
        gesturebind=none,left,x,quit
        """)
        XCTAssertEqual(parsed.config.keyBindings.count, 0)
        XCTAssertEqual(parsed.errors.map(\.line), [1, 2, 3, 4])
        XCTAssertEqual(parsed.config.axisBindings.first?.dir, UInt32(UNDIR))
        XCTAssertTrue(parsed.errors[0].message.contains("Unknown dispatch"))
        XCTAssertTrue(parsed.errors[1].message.contains("Unknown key"))
    }

    func testUnsupportedMediaKeyIsIgnoredSilently() {
        let parsed = parse("""
        bind=NONE,XF86AudioMicMute,spawn,echo mic
        bind=NONE,XF86Calculator,spawn,echo calc
        """)
        XCTAssertEqual(parsed.errors, [])
        XCTAssertEqual(parsed.config.keyBindings.count, 0)
    }

    func testKeyModes() {
        let parsed = parse("""
        bind=SUPER,r,setkeymode,resize
        key_mode=resize
        bind=NONE,Left,resizewin,-10,0
        bind=NONE,Escape,setkeymode,default
        mousebind=SUPER,btn_left,moveresize,curmove
        key_mode=common
        bind=SUPER,q,quit
        """)
        XCTAssertEqual(parsed.errors, [])
        XCTAssertEqual(parsed.config.keyBindings.map(\.mode), ["default", "resize", "resize", "common"])
        XCTAssertEqual(parsed.config.mouseBindings.first?.mode, "resize")
    }

    func testDuplicateConflict() {
        let parsed = parse("""
        bind=SUPER,a,quit
        bind=SUPER,a,killclient
        bindc=SUPER,b,quit
        bindc=SUPER,b,killclient
        bindc=SUPER,c,quit
        bind=SUPER,c,killclient
        bind=SUPER+SHIFT,a,quit
        key_mode=other
        bind=SUPER,a,quit
        key_mode=common
        bind=SUPER,x,quit
        key_mode=other
        bind=SUPER,x,quit
        mousebind=SUPER,btn_left,moveresize,curmove
        mousebind=SUPER,btn_left,moveresize,curresize
        """)
        XCTAssertEqual(parsed.errors.map(\.line), [2, 13, 6, 15], "mango sorts by modifier and key (a, x, c here)\n" + parsed.errors.map(\.description).joined(separator: "\n"))
        XCTAssertTrue(parsed.errors[0].message.hasPrefix("Key binding conflict in keymode default:\n  File \""),
                      parsed.errors[0].message)
        XCTAssertTrue(parsed.errors[0].message.contains("test.conf\", line 1\n"))
        XCTAssertTrue(parsed.errors[0].message.hasSuffix("test.conf\", line 2"))
        XCTAssertEqual(parsed.errors[0].verbosity, .info)
        XCTAssertFalse(parsed.errors[0].reportsLine)
        XCTAssertTrue(parsed.errors[3].message.hasPrefix("mousebind conflict in keymode other:"))
        XCTAssertEqual(parsed.config.keyBindings.count, 10, "conflicting binds are kept like mango")
    }

    // mango same_axisbind_key / same_gesturebind_key: ALLDIR meets every direction, UNDIR only UNDIR

    func testWindowRule() {
        let parsed = parse("""
        window_rule=is_floating:1,app_id:com.apple.systempreferences,width:800,height:0.5,offset_x:-20
        window_rule_once=title:^Picture.in.Picture$,tags:2|3,monitor:name:Built-in.*,no_border:1,animation_type_open:zoom
        window_rule=app_id:x,shield_when_capture:1,global_key_binding:alt-a
        window_rule=app_id:y,bogus_option:1,is_term:1
        """)
        let r = parsed.config.windowRules
        XCTAssertEqual(r.count, 4, "rules with bad options are kept, like mango")
        XCTAssertEqual(r[0].appId, "com.apple.systempreferences")
        XCTAssertEqual(r[0].isfloating, true)
        XCTAssertEqual(r[0].width, 800)
        XCTAssertEqual(r[0].height, 0.5)
        XCTAssertEqual(r[0].offsetX, -20)
        XCTAssertNil(r[0].title)
        XCTAssertFalse(r[0].once)
        XCTAssertTrue(r[1].once)
        XCTAssertEqual(r[1].title, "^Picture.in.Picture$")
        XCTAssertEqual(r[1].tags, 0b110)
        XCTAssertEqual(r[1].monitor, "name:Built-in.*")
        XCTAssertEqual(r[1].noBorder, true)
        XCTAssertEqual(r[1].animationTypeOpen, .zoom)
        XCTAssertEqual(r[2].globalKeyBinding, "alt-a")
        XCTAssertEqual(r[3].isTerm, true)
        XCTAssertEqual(parsed.errors.map(\.line), [4])
        XCTAssertEqual(parsed.errors.first?.message.plain, "Unknown window rule option:bogus_option", "mango's text, no space")

        let bad = parse("window_rule=app_id:y,bogus:1")
        XCTAssertEqual(bad.errors.last?.reportsLine, true, "parse_option returns false")
        XCTAssertEqual(bad.config.windowRules.last?.appId, "y", "mango counts a rule with an unknown field")
        XCTAssertEqual(parse("window_rule_once=app_id:z").config.windowRules.first?.once, true)
    }

    func testTagRule() throws {
        var errors: [ConfigError] = []
        func tagRule(_ v: String) -> ConfigTagRule {
            let p = parse("tag_rule=\(v)")
            errors += p.errors
            return p.config.tagRules[0]
        }
        let r = tagRule("id:3,layout_name:scroller,master_count:200,master_factor:0.6,monitor_name:DELL.*,no_hide:1")
        XCTAssertEqual(r.id, 3)
        XCTAssertEqual(r.layoutName, "scroller")
        XCTAssertEqual(r.masterCount, 99)
        XCTAssertEqual(r.masterFactor, 0.6)
        XCTAssertEqual(r.monitorName, "DELL.*")
        XCTAssertEqual(r.noHide, true)
        XCTAssertEqual(r.openAsFloating, false)

        let all = tagRule("id:*,layout_name:monocle")
        XCTAssertNil(all.id)
        XCTAssertEqual(tagRule("layout_name:grid").id, 0)

        XCTAssertEqual(tagRule("id:1,layout_name:spiral").layoutName, "spiral")
        XCTAssertEqual(errors, [])
    }

    func testUnknownKeyword() {
        let parsed = parse("does_not_exist=1")
        XCTAssertEqual(parsed.errors.map(\.description.plain), ["test.conf:1: Unknown keyword: does_not_exist"])
        XCTAssertEqual(parsed.errors.first?.message, "Unknown keyword: \u{1B}[1m\u{1B}[31mdoes_not_exist\u{1B}[0m", "mango's colours round the value")
    }

    func testConfigOptionsApply() {
        var c = Config()
        XCTAssertTrue(parseOption("gap_inner_horizontal", "12", to: &c))
        XCTAssertEqual(c.gappih, 12)
        XCTAssertTrue(parseOption("smart_gaps", "1", to: &c))
        XCTAssertTrue(c.smartgaps)
        XCTAssertTrue(parseOption("default_master_factor", "0.6", to: &c))
        XCTAssertEqual(c.defaultMfact, 0.6)
        XCTAssertTrue(parseOption("focus_color", "0x112233ff", to: &c))
        XCTAssertEqual(c.focuscolor, parseColor("0x112233ff"))
        XCTAssertTrue(parseOption("animation_curve_move", "0.1,0.2,0.3,0.4", to: &c))
        XCTAssertEqual(c.animationCurveMove, BezierCurve(x1: 0.1, y1: 0.2, x2: 0.3, y2: 0.4))
        XCTAssertTrue(parseOption("animation_type_open", "zoom", to: &c))
        XCTAssertEqual(c.animationTypeOpen, .zoom)
        XCTAssertTrue(parseOption("circle_layout", "tile, scroller,monocle", to: &c))
        XCTAssertEqual(c.circleLayout, ["tile", " scroller", "monocle"])
        XCTAssertTrue(parseOption("scroller_proportion_preset", "0.3,0.6,1", to: &c))
        XCTAssertEqual(c.scrollerProportionPreset, [0.3, 0.6, 1])
        XCTAssertTrue(parseOption("chutney_hyper_modifier", "ctrl+alt", to: &c))
        XCTAssertEqual(c.chutneyHyperModifier, "ctrl+alt")
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
        XCTAssertTrue(ConfigParser.parseOption(&c, "window_rule", "app_id:foo,is_floating:1", 0, baseDirectory: base))
        XCTAssertEqual(c.windowRules.last?.appId, "foo")
        XCTAssertTrue(ConfigParser.parseOption(&c, "bind", "SUPER,a,quit", 0, baseDirectory: base))
        XCTAssertEqual(c.keyBindings.last?.mode, "default")

        XCTAssertTrue(parseOption("blur", "1", to: &c))
        XCTAssertFalse(parseOption("nope", "1", to: &c))
        XCTAssertTrue(parseOption("border_px", "wide", to: &c))
        XCTAssertEqual(c.borderpx, 0)
        XCTAssertTrue(parseOption("circle_layout", "tile,spiral", to: &c))
        XCTAssertEqual(c.circleLayout, ["tile", "spiral"])
        guard !parseOption("focus_color", "0xzz", to: &c) else {
            return XCTFail("expected invalid")
        }
        guard !parseOption("animation_curve_open", "1,2,3", to: &c) else {
            return XCTFail("expected invalid")
        }
        XCTAssertEqual(c.focuscolor, parseColor("0x112233ff"), "an invalid colour leaves the option unchanged")
    }

    func testKeyNames() {
        XCTAssertEqual(KeyNames.keyCodes(forName: "Return"), [36])
        XCTAssertEqual(KeyNames.keyCodes(forName: "return"), [36])
        XCTAssertEqual(KeyNames.keyCodes(forName: "KP_Enter"), [76])
        XCTAssertEqual(KeyNames.keyCodes(forName: "F5"), [96])
        XCTAssertEqual(KeyNames.keyCodes(forName: "f12"), [111])
        XCTAssertEqual(KeyNames.keyCodes(forName: "code:36"), [36])
        XCTAssertEqual(KeyNames.keyCodes(forName: "Super_L"), [55])
        XCTAssertEqual(KeyNames.keyCodes(forName: "Caps_Lock"), [57])
        XCTAssertEqual(KeyNames.keyCodes(forName: "KP_8"), [91])
        XCTAssertEqual(KeyNames.keyCodes(forName: "Left"), [123])
        XCTAssertEqual(KeyNames.keyCodes(forName: "space"), [49])
        XCTAssertEqual(KeyNames.keyCodes(forName: "Print"), [105])
        XCTAssertEqual(KeyNames.keyCodes(forName: "no_such_key"), [])
        XCTAssertEqual(KeyNames.keyCodes(forName: "XF86AudioMicMute"), [])

        let a = KeyNames.keyCodes(forName: "a")
        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(KeyNames.keyCodes(forName: "A"), a)
        XCTAssertEqual(KeyNames.name(forKeyCode: a[0]), "a")
        XCTAssertEqual(KeyNames.keyCodes(forName: "1").count, 1)
        XCTAssertEqual(KeyNames.keyCodes(forName: "minus").count, 1)
        XCTAssertEqual(KeyNames.keyCodes(forName: "backslash").count, 1)

        XCTAssertEqual(KeyNames.name(forKeyCode: 36), "Return")
        XCTAssertEqual(KeyNames.name(forKeyCode: 96), "F5")
        XCTAssertEqual(KeyNames.name(forKeyCode: 300), "code:300")
        XCTAssertFalse(KeyNames.currentLayoutName().isEmpty)
    }

    func testASourceCycleIsReadOnce() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "border_px=3\nsource=b.conf\n".write(to: dir.appendingPathComponent("a.conf"), atomically: true, encoding: .utf8)
        try "gap_inner_horizontal=7\nsource=a.conf\n".write(to: dir.appendingPathComponent("b.conf"), atomically: true, encoding: .utf8)
        let p = ConfigParser.parseConfig(fileAt: dir.appendingPathComponent("a.conf"))
        XCTAssertEqual(p.config.borderpx, 3)
        XCTAssertEqual(p.config.gappih, 7)
        XCTAssertEqual(p.errors.count, 1)
        XCTAssertTrue(p.errors.first?.description.contains("Recursive source") ?? false)
    }
}
