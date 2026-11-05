import XCTest
@testable import Mango
@testable import Port

final class ConfigParserTests: MangoTestCase {

    private func parse(_ text: String, base: URL? = nil) -> ParsedConfig {
        ConfigParser.parse(text: text, baseDirectory: base ?? FileManager.default.temporaryDirectory,
                           fileName: "test.conf")
    }

    private var defaultConfigURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // MangoCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // package root
            .appendingPathComponent("Resources/config.conf")
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mango-config-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    // MARK: - Shipped config

    /// mango's config without its key, mouse and scroll bindings, and without the port's
    /// marked lines: where config.conf and mango's assets/config.conf are the same.
    private func outsideKeyBindings(_ text: String) -> [String] {
        var lines = text.components(separatedBy: "\r\n")
        if let keys = lines.firstIndex(of: "# Key Bindings"), let gestures = lines.firstIndex(of: "# Gesture Bindings") {
            lines.removeSubrange(keys..<gestures)
        }
        return lines.filter { !$0.hasPrefix("# Mango Chutney:") }
    }

    func testShippedConfigParsesWithoutErrors() throws {
        let url = defaultConfigURL
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), url.path)
        let parsed = ConfigParser.parseConfig(fileAt: url)
        XCTAssertEqual(parsed.errors, [], parsed.errors.map(\.description).joined(separator: "\n"))
        XCTAssertEqual(parsed.sourcedFiles.first?.path, url.standardizedFileURL.path)

        // config.conf is mango's assets/config.conf with mango's keys on Hyper (not in mango),
        // and then the port's keys, from their marker line to the end.
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
        XCTAssertFalse(c.chutneyStyle, "mango's look unless chutney_style is set")
        XCTAssertNil(c.chutneyFloatingColor)
        XCTAssertEqual(c.chutneyIgnoreApps, [])
        let reload = c.keyBindings.first { $0.dispatch.name == "reload_config" }
        XCTAssertEqual(reload?.mods, [.superKey, .ctrl, .alt], "mango's keys on Hyper")
        XCTAssertEqual(reload?.keyName, "r")
        XCTAssertEqual(c.keyBindings.first { $0.dispatch.name == "view" }?.dispatch.args, ["1", "0"], "mango's own arguments")
    }

    /// The port's keys and dispatchers carry the chutney_ prefix; the old macos_ names are
    /// unknown keys.
    func testThePortsNamesCarryItsPrefix() {
        for k in MangoCompat.portExtensionOptions.keys { XCTAssertTrue(k.hasPrefix("chutney_"), k) }
        for d in MangoCompat.portDispatchers { XCTAssertTrue(d.hasPrefix("chutney_"), d) }
        XCTAssertFalse(parse("macos_style=1").errors.isEmpty)
    }

    /// The port's keys, at the end of config.conf. They set no mango key: only chutney_ keys,
    /// the palettes' bindings and the app's own files, read last.
    func testShippedConfigReadsTheMacOSDefaultsLast() throws {
        let parsed = ConfigParser.parseConfig(fileAt: defaultConfigURL)
        XCTAssertEqual(parsed.sourcedFiles.map(\.lastPathComponent), ["config.conf", "chutney_theme.conf", "chutney_menu.conf"])
        let c = parsed.config
        XCTAssertTrue(c.chutneyMenuBar)
        XCTAssertEqual(c.chutneyMenuConfig, "chutney_menu.conf")
        XCTAssertEqual([c.animationDurationMove, c.animationDurationOpen, c.animationDurationTag], [500, 400, 350], "mango's")
        XCTAssertTrue(c.sloppyfocus, "mango's")
        XCTAssertTrue(c.chutneyStyle)
        XCTAssertTrue(c.chutneyTabBarAppIcons)
        XCTAssertTrue(c.chutneyTabBarShortcuts)
        XCTAssertEqual(c.chutneyHyperModifier, "super+ctrl+alt")
        let hotkeys = c.keyBindings.first { $0.dispatch.name == "chutney_toggle_hotkeys_palette" }
        XCTAssertEqual(hotkeys?.mods, [.superKey, .ctrl, .alt], "on the Hyper layer")
        XCTAssertEqual(hotkeys?.keyName, "k")
        XCTAssertEqual(c.xkbRulesOptions, "", "Caps Lock as Hyper is chutney_hyper_key's")
        XCTAssertEqual(c.chutneyHyperKey, "caps_lock")

        let text = try String(contentsOf: defaultConfigURL, encoding: .utf8)
        let port = try XCTUnwrap(text.range(of: ConfigFiles.portMarker))
        for line in text[port.lowerBound...].components(separatedBy: "\r\n") where !line.hasPrefix("#") && line.contains("=") {
            let key = line.prefix { $0 != "=" }
            XCTAssertTrue(key.hasPrefix("chutney_") || key == "source_optional" || line.contains(",chutney_toggle_"),
                          "the port's keys set a mango key: \(line)")
        }
    }

    // MARK: - Lines, comments, quotes

    func testCommentsQuotesAndLineFormat() {
        let parsed = parse("""
        # full comment
           # indented comment

        gap_inner_horizontal = 7   # inline comment
        jump_labels="AB #CD"
        not a valid line
        border_px=3#not a comment because no whitespace before
        """)
        XCTAssertEqual(parsed.config.gappih, 7)
        XCTAssertEqual(parsed.config.jumpLabels, "AB #CD")
        // mango: an indented comment leaves blanks, which sscanf("%[^=]=…") rejects
        XCTAssertEqual(parsed.errors.map(\.line), [2, 6], parsed.errors.map(\.description).joined(separator: "\n"))
        XCTAssertEqual(parsed.errors.last?.line, 6)
        XCTAssertEqual(parsed.errors.first?.file, "test.conf")
        XCTAssertTrue(parsed.errors.first?.message.hasPrefix("Invalid line format") ?? false)
        // `3#not...` is lenient-parsed like atoi.
        XCTAssertEqual(parsed.config.borderpx, 3)
    }

    func testCRLFLineEndings() {
        let parsed = parse("# comment\r\nborder_px=3\r\n\r\nbind=SUPER,a,quit\r\nnope=1\r\n")
        XCTAssertEqual(parsed.config.borderpx, 3)
        XCTAssertEqual(parsed.config.keyBindings.count, 1)
        XCTAssertEqual(parsed.errors.map(\.line), [5])
    }

    func testValueTooLong() {
        let parsed = parse("jump_labels=" + String(repeating: "A", count: 256))
        XCTAssertEqual(parsed.errors.count, 1)
        XCTAssertTrue(parsed.errors[0].message.contains("exceeds 255 bytes"))
        XCTAssertEqual(parsed.config.jumpLabels, Config().jumpLabels)
    }

    func testClampAtEnd() {
        let parsed = parse("border_px=500\ndefault_master_factor=2\ntag_num=0")
        XCTAssertEqual(parsed.errors, [])
        XCTAssertEqual(parsed.config.borderpx, 200)
        XCTAssertEqual(parsed.config.defaultMfact, 0.9)
        XCTAssertEqual(parsed.config.tagNum, 1)
    }

    // MARK: - Variables

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

    // MARK: - source

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
        XCTAssertEqual(parsed.errors[1].message, "Unknown keyword: unknown_thing")
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

    // MARK: - env / exec

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

    // MARK: - Bindings

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
        XCTAssertEqual(parsed.errors.map(\.message), ["Unknown keyword: bindx"])
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
        // `chutney_hyper_modifier=` is resolved after the whole file is read, wherever it appears.
        XCTAssertEqual(b[3].mods, [.ctrl, .alt])
        XCTAssertEqual(b[4].mods, [.ctrl, .alt])
        XCTAssertEqual(parsed.errors.count, 1)
        XCTAssertEqual(parsed.errors[0].line, 7)
        XCTAssertTrue(parsed.errors[0].message.hasPrefix("Unknown modifier"))
    }

    func testSpawnKeepsCommas() {
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
        // Fields are trimmed before rejoining, exactly like mango (the space after the comma is lost).
        XCTAssertEqual(d[0], Dispatch(name: "spawn", args: ["notify-send \"a,b\",c"]))
        XCTAssertEqual(d[1], Dispatch(name: "spawn_shell", args: ["echo 1,2,3,4,5,6,7 | cat"]))
        XCTAssertEqual(d[2], Dispatch(name: "spawn_on_empty", args: ["firefox --new-window a,b", "4"]))
        XCTAssertEqual(d[3], Dispatch(name: "toggle_named_scratchpad", args: ["com.app", "none", "open -a X,Y"]))
        XCTAssertEqual(d[4], Dispatch(name: "killclient", args: []))
        XCTAssertEqual(d[5], Dispatch(name: "setoption", args: ["circle_layout", "tile,scroller,grid"]))
    }

    func testParseDispatch() {
        XCTAssertEqual(try BindingParser.parseFuncName(["view", " 1 ", "0"]).get(), Dispatch(name: "view", args: ["1", "0"]))
        XCTAssertEqual(try BindingParser.parseFuncName(["focusdir", "left", "", "x"]).get().args, ["left"])
        XCTAssertEqual(try BindingParser.parseFuncName(["movewin", "1", "2", "3", "4", "5", "6"]).get().args,
                       ["1", "2", "3", "4", "5,6"])
        XCTAssertEqual(try BindingParser.parseFuncName(["dwindle_toggle_current_split"]).get().name,
                       "dwindle_toggle_current_split")
        guard case .failure(let msg) = BindingParser.parseFuncName(["nonsense", "1"]) else {
            return XCTFail("expected failure")
        }
        XCTAssertTrue(msg.contains("nonsense"))
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
        // mango: an axis direction it does not know is UNDIR and the finger count is atoi
        // ("x" is 0): kept, not errors
        XCTAssertEqual(parsed.errors.map(\.line), [1, 2, 3, 4])
        XCTAssertEqual(parsed.config.axisBindings.first?.isUndir, true)
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
        XCTAssertEqual(parsed.errors.map(\.line), [2, 6, 13, 15], parsed.errors.map(\.description).joined(separator: "\n"))
        XCTAssertTrue(parsed.errors[0].message.hasPrefix("Conflict"))
        XCTAssertTrue(parsed.errors[0].message.contains("test.conf:1"))
        XCTAssertEqual(parsed.config.keyBindings.count, 10, "conflicting binds are kept like mango")
    }

    func testMouseAxisGestureBindings() {
        let parsed = parse("""
        mousebind=SUPER,btn_right,moveresize,curresize
        mousebind=NONE,code:274,togglemaximizescreen,0
        axisbind=SUPER+SHIFT,Down,viewtoright_have_client
        gesturebind=none,up,3,toggleoverview
        """)
        XCTAssertEqual(parsed.errors, [])
        let c = parsed.config
        XCTAssertEqual(c.mouseBindings[0].button, .right)
        XCTAssertEqual(c.mouseBindings[0].dispatch, Dispatch(name: "moveresize", args: ["curresize"]))
        XCTAssertEqual(c.mouseBindings[1].button, .middle)
        XCTAssertEqual(c.axisBindings[0].mods, [.superKey, .shift])
        XCTAssertEqual(c.axisBindings[0].direction, .down)
        XCTAssertEqual(c.gestureBindings[0].fingers, 3)
        XCTAssertEqual(c.gestureBindings[0].direction, .up)
    }

    // MARK: - Rules

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
        XCTAssertEqual(r[0].isFloating, true)
        XCTAssertEqual(r[0].width, 800)
        XCTAssertEqual(r[0].height, 0.5)
        XCTAssertEqual(r[0].offsetX, -20)
        XCTAssertNil(r[0].title)
        XCTAssertFalse(r[0].once)
        XCTAssertTrue(r[1].once)
        XCTAssertEqual(r[1].title, "^Picture.in.Picture$")
        XCTAssertEqual(r[1].tags, 0b110)
        XCTAssertEqual(r[1].monitor, MonitorSpec(name: "Built-in.*"))
        XCTAssertEqual(r[1].noBorder, true)
        XCTAssertEqual(r[1].animationTypeOpen, .zoom)
        XCTAssertEqual(r[2].globalKeyBinding, "alt-a")
        XCTAssertEqual(r[3].isTerm, true)
        XCTAssertEqual(parsed.errors.map(\.line), [4])
        XCTAssertEqual(parsed.errors.first?.message, "Unknown window rule option: bogus_option")

        guard case .failure = RuleParser.parseWindowRule("app_id:y,bogus:1", once: false) else {
            return XCTFail("expected failure")
        }
        XCTAssertEqual(try RuleParser.parseWindowRule("app_id:z", once: true).get().once, true)
    }

    func testTagRule() throws {
        let r = try RuleParser.parseTagRule("id:3,layout_name:scroller,master_count:200,master_factor:0.6,monitor_name:DELL.*,no_hide:1").get()
        XCTAssertEqual(r.id, 3)
        XCTAssertEqual(r.layoutName, "scroller")
        XCTAssertEqual(r.masterCount, 99)
        XCTAssertEqual(r.masterFactor, 0.6)
        XCTAssertEqual(r.monitorName, "DELL.*")
        XCTAssertEqual(r.noHide, true)
        XCTAssertNil(r.openAsFloating)

        let all = try RuleParser.parseTagRule("id:*,layout_name:monocle").get()
        XCTAssertNil(all.id)
        XCTAssertEqual(try RuleParser.parseTagRule("layout_name:grid").get().id, 0)

        // mango keeps a layout name it does not know; it does nothing
        XCTAssertEqual(try RuleParser.parseTagRule("id:1,layout_name:spiral").get().layoutName, "spiral")
    }

    // MARK: - Options

    func testUnknownKeyword() {
        let parsed = parse("does_not_exist=1")
        XCTAssertEqual(parsed.errors, [ConfigError(file: "test.conf", line: 1, message: "Unknown keyword: does_not_exist")])
    }

    func testWaylandOnlyKeysAreIgnored() {
        let parsed = parse("""
        blur=1
        blur_params_radius=5
        shadows=1
        shadows_color=0x000000ff
        layer_animations=1
        xkb_rules_layout=us,de
        repeat_rate=25
        cursor_size=24
        cursor_theme=Adwaita
        trackpad_natural_scrolling=1
        mouse_accel_profile=2
        tap_to_click=1
        drag_lock=1
        hdr_depth=10
        xwayland_persistence=1
        group_bar_height=20
        tab_bar_decorate_font_desc=Sans 10
        title_message_bar_height=52
        jump_label_decorate_fg_color=0xffffffff
        dim_enable=1
        idle_inhibit_ignore_visible=0
        sync_obj_enable=1
        allow_tearing=1
        numlock_on=1
        disable_middle_paste=1
        allow_lock_transparent=1
        touch_enable=1
        button_map=0
        send_events_mode=0
        axis_scroll_factor=1.0
        animation_curve_opacity_fade_in=0.46,1.0,0.29,1
        layer_rule=animation_type_open:zoom,layer_name:rofi
        monitor_rule=name:eDP-1,width:1920,height:1080
        device_rule=name:foo,type:keyboard
        switchbind=fold,spawn,swaylock
        """)
        XCTAssertEqual(parsed.errors, [], parsed.errors.map(\.description).joined(separator: "\n"))
    }

    func testConfigOptionsApply() {
        var c = Config()
        XCTAssertEqual(ConfigOptions.parseOption(key: "gap_inner_horizontal", value: "12", to: &c), .applied)
        XCTAssertEqual(c.gappih, 12)
        XCTAssertEqual(ConfigOptions.parseOption(key: "smart_gaps", value: "1", to: &c), .applied)
        XCTAssertTrue(c.smartgaps)
        XCTAssertEqual(ConfigOptions.parseOption(key: "default_master_factor", value: "0.6", to: &c), .applied)
        XCTAssertEqual(c.defaultMfact, 0.6)
        XCTAssertEqual(ConfigOptions.parseOption(key: "focus_color", value: "0x112233ff", to: &c), .applied)
        XCTAssertEqual(c.focuscolor, parseColor("0x112233ff"))
        XCTAssertEqual(ConfigOptions.parseOption(key: "animation_curve_move", value: "0.1,0.2,0.3,0.4", to: &c), .applied)
        XCTAssertEqual(c.animationCurveMove, BezierCurve(x1: 0.1, y1: 0.2, x2: 0.3, y2: 0.4))
        XCTAssertEqual(ConfigOptions.parseOption(key: "animation_type_open", value: "zoom", to: &c), .applied)
        XCTAssertEqual(c.animationTypeOpen, .zoom)
        XCTAssertEqual(ConfigOptions.parseOption(key: "circle_layout", value: "tile, scroller,monocle", to: &c), .applied)
        // mango's sanitize_string keeps the blank: " scroller" never matches a layout
        XCTAssertEqual(c.circleLayout, ["tile", " scroller", "monocle"])
        XCTAssertEqual(ConfigOptions.parseOption(key: "scroller_proportion_preset", value: "0.3,0.6,1", to: &c), .applied)
        XCTAssertEqual(c.scrollerProportionPreset, [0.3, 0.6, 1])
        XCTAssertEqual(ConfigOptions.parseOption(key: "chutney_ignore_apps", value: "com.a, com.b", to: &c), .applied)
        XCTAssertEqual(ConfigOptions.parseOption(key: "chutney_ignore_apps", value: "com.c,com.a", to: &c), .applied)
        XCTAssertEqual(c.chutneyIgnoreApps, ["com.a", "com.b", "com.c"])
        XCTAssertEqual(ConfigOptions.parseOption(key: "chutney_hyper_modifier", value: "ctrl+alt", to: &c), .applied)
        XCTAssertEqual(c.chutneyHyperModifier, "ctrl+alt")
        XCTAssertEqual(ConfigOptions.parseOption(key: "window_rule", value: "app_id:foo,is_floating:1", to: &c), .applied)
        XCTAssertEqual(c.windowRules.last?.appId, "foo")
        XCTAssertEqual(ConfigOptions.parseOption(key: "bind", value: "SUPER,a,quit", to: &c), .applied)
        XCTAssertEqual(c.keyBindings.last?.mode, "default")

        XCTAssertEqual(ConfigOptions.parseOption(key: "blur", value: "1", to: &c), .ignored)
        XCTAssertEqual(ConfigOptions.parseOption(key: "nope", value: "1", to: &c), .unknown)
        // mango: atoi("wide") is 0; an unknown layout name is kept
        XCTAssertEqual(ConfigOptions.parseOption(key: "border_px", value: "wide", to: &c), .applied)
        XCTAssertEqual(c.borderpx, 0)
        XCTAssertEqual(ConfigOptions.parseOption(key: "circle_layout", value: "tile,spiral", to: &c), .applied)
        XCTAssertEqual(c.circleLayout, ["tile", "spiral"])
        guard case .invalid = ConfigOptions.parseOption(key: "focus_color", value: "0xzz", to: &c) else {
            return XCTFail("expected invalid")
        }
        guard case .invalid = ConfigOptions.parseOption(key: "animation_curve_open", value: "1,2,3", to: &c) else {
            return XCTFail("expected invalid")
        }
        XCTAssertEqual(c.focuscolor, parseColor("0x112233ff"), "an invalid colour leaves the option unchanged")
    }

    // MARK: - KeyNames

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

        // Letters go through the current layout; `a` sits at code 0 on every Latin layout
        // except AZERTY, so only require a resolvable, case-insensitive, round-tripping code.
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

    /// A bug in mango (docs/afvigelser.md §6): a file that sources itself, directly or
    /// through another, is read once and reported; mango reads it until it runs out of stack.
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
