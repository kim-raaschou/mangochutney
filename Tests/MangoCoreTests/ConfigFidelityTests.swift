import XCTest
import Foundation
@testable import Mango
@testable import Port

final class ConfigFidelityTests: MangoTestCase {
    private func parse(_ text: String) -> ParsedConfig {
        ConfigParser.parse(text: text, baseDirectory: FileManager.default.temporaryDirectory, fileName: "test.conf")
    }

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    static let docExamples = """
    allow_tearing=1
    animation_curve_close=0.46,1.0,0.29,0.99
    animation_curve_focus=0.46,1.0,0.29,0.99
    animation_curve_move=0.46,1.0,0.29,0.99
    animation_curve_opacity_fade_in=0.46,1.0,0.29,0.99
    animation_curve_opacity_fade_out=0.5,0.5,0.5,0.5
    animation_curve_open=0.46,1.0,0.29,0.99
    animation_curve_open=0.46,1.0,0.29,1
    animation_curve_tag=0.46,1.0,0.29,0.99
    animation_duration_close=300
    animation_duration_focus=0
    animation_duration_move=500
    animation_duration_open=400
    animation_duration_tag=300
    animation_fade_in=1
    animation_fade_out=1
    animation_type_close=slide
    animation_type_open=zoom
    animations=1
    axisbind=SUPER,DOWN,viewtoright_have_client
    axisbind=SUPER,UP,viewtoleft_have_client
    bind=ALT,Return,spawn,foot
    bind=ALT,code:24,killclient
    bind=ALT,q,killclient
    bind=ALT,z,toggle_scratchpad
    bind=NONE,Escape,setkeymode,default
    bind=NONE,Left,resizewin,-10,0
    bind=NONE,Right,resizewin,+10,0
    bind=NONE,XF86AudioLowerVolume,spawn,wpctl set-volume @DEFAULT_SINK@ 5%-
    bind=NONE,XF86AudioMute,spawn,wpctl set-mute @DEFAULT_SINK@ toggle
    bind=NONE,XF86AudioNext,spawn,playerctl next
    bind=NONE,XF86AudioPlay,spawn,playerctl play-pause
    bind=NONE,XF86AudioPrev,spawn,playerctl previous
    bind=NONE,XF86AudioRaiseVolume,spawn,wpctl set-volume @DEFAULT_SINK@ 5%+
    bind=NONE,XF86MonBrightnessDown,spawn,brightnessctl s 2%-
    bind=NONE,XF86MonBrightnessUp,spawn,brightnessctl s +2%
    bind=NONE,XF86MonBrightnessUp,spawn,brightnessctl set +5%
    bind=SHIFT,XF86AudioMute,spawn,wpctl set-mute @DEFAULT_SOURCE@ toggle
    bind=SHIFT,XF86MonBrightnessDown,spawn,brightnessctl s 1%
    bind=SHIFT,XF86MonBrightnessUp,spawn,brightnessctl s 100%
    bind=SUPER+CTRL,s,tag_special_silent
    bind=SUPER+SHIFT,i,restore_minimized
    bind=SUPER+SHIFT,s,tag_special_tag
    bind=SUPER,F,setkeymode,resize
    bind=SUPER,P,spawn_shell,echo "hello" | rofi -dmenu
    bind=SUPER,Q,killclient
    bind=SUPER,i,minimized
    bind=SUPER,n,switch_layout
    bind=SUPER,r,reload_config
    bind=SUPER,s,setlayout,scroller
    bind=SUPER,s,toggle_special_tag
    bind=SUPER,t,setlayout,tile
    bind=alt,h,toggle_named_scratchpad,st-yazi,none,st -c st-yazi -e yazi
    bind=alt,k,toggle_named_scratchpad,none,kitty-scratch,kitty -T kitty-scratch
    bind=alt,shift_l,switch_keyboard_layout
    bind=code:64+code:133,code:24,killclient
    bind=code:64,code:24,killclient
    bind=none,Super_L,spawn,rofi -show run
    bindc=SUPER,a,centerwin
    bindc=SUPER,a,resizewin,+10,0
    bindl=SUPER,L,spawn,swaylock
    bindr=Super,Super_L,spawn,rofi -show run
    binds=ALT,q,killclient
    blur=1
    blur_optimized=0
    blur_optimized=1
    border_color=0x444444ff
    border_radius=0
    border_radius=8
    circle_layout=grid,scroller,tile
    cursor_size=24
    cursor_theme=Adwaita
    deck_tab_mode=1
    default_master_count=1
    default_master_factor=0.55
    dim_enable=1
    dim_focused_color=0x00000000
    dim_unfocused_color=0x0000004d
    drag_tile_to_tile=1
    drop_color=0x8FBA7C55
    dwindle_drop_simple_split=1
    dwindle_horizontal_split=0
    dwindle_preserve_split=0
    dwindle_smart_resize=0
    dwindle_smart_split=0
    dwindle_split_ratio=0.5
    dwindle_vertical_split=0
    edge_scroller_focus_allow_speed=0.0
    edge_scroller_pointer_focus=1
    env=GLFW_IM_MODULE,ibus
    env=GTK_IM_MODULE,fcitx
    env=GTK_IM_MODULE,ibus
    env=QT_IM_MODULE,fcitx
    env=QT_IM_MODULE,ibus
    env=QT_IM_MODULES,wayland;fcitx
    env=SDL_IM_MODULE,fcitx
    fade_in_begin_opacity=0.5
    fade_out_begin_opacity=0.5
    focus_color=0xc66b25ff
    focused_opacity=1.0
    gesturebind=none,down,3,focusdir,down
    gesturebind=none,down,4,toggleoverview
    gesturebind=none,left,3,focusdir,left
    gesturebind=none,left,4,viewnext_have_client
    gesturebind=none,right,3,focusdir,right
    gesturebind=none,right,4,viewprev_have_client
    gesturebind=none,up,3,focusdir,up
    gesturebind=none,up,4,toggleoverview
    key_mode=common
    key_mode=default
    key_mode=resize
    layer_animation_type_close=slide
    layer_animation_type_open=slide
    layer_animations=1
    layer_rule=animation_type_open:slide,animation_type_close:fade,no_blur:1,layer_name:wofi
    layer_rule=animation_type_open:zoom,no_animation:0,layer_name:rofi
    layer_rule=no_animation:1,no_blur:1,layer_name:selection
    layer_rule=no_animation:1,no_shadow:1,layer_name:swaync
    layer_shadows=1
    monitor_rule=make:Chimei Innolux Corporation,model:0x15F5,width:1920,height:1080,refresh:60,x:0,y:0
    monitor_rule=name:HEADLESS-.*,width:1920,height:1080,refresh:60,x:1926,y:0,scale:1,rr:0,vrr:0
    monitor_rule=name:^DP-2$,width:2560,height:1440,refresh:144,x:1920,y:0,primary:1
    monitor_rule=name:^eDP-1$,width:1920,height:1080,refresh:60,x:0,y:10
    monocle_no_border=0
    monocle_no_gap=0
    monocle_right_button_close=0
    monocle_tab_mode=1
    mousebind=NONE,code:273,togglemaximizescreen,0
    mousebind=SUPER+CTRL,btn_right,killclient
    mousebind=SUPER,btn_left,moveresize,curmove
    mousebind=SUPER,btn_right,moveresize,curresize
    new_is_master=1
    no_radius_when_single=0
    numlock_on=1
    repeat_delay=300
    repeat_rate=40
    root_color=0x201b14ff
    root_color=0x323232ff
    scratchpad_color=0x516c93ff
    scratchpad_height_ratio=0.9
    scratchpad_width_ratio=0.8
    scroller_default_proportion=0.9
    scroller_default_proportion_single=1.0
    scroller_focus_center=0
    scroller_prefer_center=0
    scroller_prefer_overspread=1
    scroller_proportion_preset=0.5,0.8,1.0
    scroller_structs=20
    shadow_only_floating=1
    shadows=1
    shadows_blur=15
    shadows_color=0x000000ff
    shadows_position_x=0
    shadows_position_y=0
    shadows_size=12
    smart_gaps=0
    special_dim=0.5
    special_gap_inner_horizontal=10
    special_gap_inner_vertical=10
    special_gap_outer_horizontal=20
    special_gap_outer_vertical=20
    split_color=0xEB441EFF
    switchbind=FOLD_STATE,COMMAND,PARAMETERS
    switchbind=fold,spawn,swaylock -f -c 000000
    switchbind=unfold,spawn,wlr-dpms on
    sync_obj_enable=1
    tag_gather=0
    tag_num=9
    tag_rule=id:*,layout_name:scroller
    tag_rule=id:1,layout_name:scroller
    tag_rule=id:1,layout_name:scroller,scroller_default_proportion_single:0.5,scroller_ignore_proportion_single:0,scroller_default_proportion:0.9,monitor_name:HDMI-A-1
    tag_rule=id:1,monitor_name:eDP-1,layout_name:scroller
    tag_rule=id:1,no_hide:1,layout_name:scroller
    tag_rule=id:2,layout_name:scroller
    tag_rule=id:2,monitor_name:eDP-1,layout_name:scroller
    tag_rule=id:2,no_hide:1,layout_name:scroller
    tag_rule=id:3,monitor_name:eDP-1,no_hide:1,layout_name:scroller
    tag_rule=id:4,monitor_name:eDP-1,no_hide:1,layout_name:scroller
    tag_rule=id:5,layout_name:tile,master_count:2,master_factor:0.6
    tag_rule=id:6,monitor_name:HDMI-A-1,layout_name:monocle,no_render_border:1
    unfocused_opacity=1.0
    urgent_color=0xad401fff
    window_rule=activation_bypass:1,app_id:org.example.App
    window_rule=allow_csd:1,app_id:firefox
    window_rule=confine_pointer:1,app_id:steam_app_526870
    window_rule=confine_pointer:1,is_fullscreen:1,app_id:steam_app_526870
    window_rule=focused_opacity:0.8,app_id:firefox
    window_rule=force_tearing:1,title:Counter-Strike 2
    window_rule=force_tearing:1,title:vkcube
    window_rule=global_key_binding:ctrl+alt-n,app_id:com.obsproject.Studio
    window_rule=global_key_binding:ctrl+alt-o,app_id:com.obsproject.Studio
    window_rule=is_fullscreen:1,app_id:steam_app_526870,title:Satisfactory
    window_rule=is_named_scratchpad:1,app_id:st-yazi
    window_rule=is_named_scratchpad:1,width:1000,height:700,title:kitty-scratch
    window_rule=is_named_scratchpad:1,width:1280,height:800,app_id:st-yazi
    window_rule=is_open_silent:1,app_id:com.obsproject.Studio
    window_rule=is_term:1,app_id:st
    window_rule=is_unmanaged_global:1,app_id:cheese
    window_rule=no_swallow:1,app_id:foot
    window_rule=offset_x:20,offset_y:-30,width:800,height:600,app_id:alacritty
    window_rule=tags:0,app_id:discord
    window_rule=tags:0,app_id:spotify
    window_rule=tags:9,monitor:HDMI-A-1,app_id:discord
    window_rule=unfocused_opacity:0.6,app_id:foot
    window_rule=width:1000,height:900,app_id:yesplaymusic,title:Demons
    xkb_rules_layout=us,de
    xkb_rules_layout=us,us
    xkb_rules_options=caps:escape,ctrl:nocaps
    xkb_rules_options=grp:lalt_lshift_toggle
    xkb_rules_variant=,dvorak
    xkb_rules_variant=dvorak
    zoom_end_ratio=0.8
    zoom_initial_ratio=0.4
    """

    func testEveryDocumentedExampleLoadsWithoutErrors() {
        var count = 0
        for line in Self.docExamples.split(separator: "\n") {
            let parsed = parse(String(line))
            XCTAssertEqual(parsed.errors.map(\.message), [], String(line))
            count += 1
        }
        XCTAssertEqual(count, 213)
    }

    func testShippedConfigFollowsMangosFile() throws {
        let root = ProcessInfo.processInfo.environment["MANGO_SOURCES"] ?? NSHomeDirectory() + "/sources/mango"
        let mangoURL = URL(fileURLWithPath: root + "/assets/config.conf")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: mangoURL.path), "no mango checkout at \(root)")
        func entries(_ text: String, commented: Bool) -> [String] {
            text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n").compactMap { raw in
                var line = raw.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("#") {
                    guard commented else { return nil }
                    line = line.drop { $0 == "#" || $0 == " " }.description
                }
                guard let eq = line.firstIndex(of: "=") else { return nil }
                let key = line[..<eq].trimmingCharacters(in: .whitespaces)
                guard !key.isEmpty, key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return nil }
                let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                if key.hasSuffix("bind") || key.hasPrefix("bind") {
                    let fields = value.split(separator: ",", omittingEmptySubsequences: false)
                    let skip = key == "gesturebind" ? 3 : 2
                    return fields.count > skip ? "\(key):\(fields[skip].trimmingCharacters(in: .whitespaces))" : nil
                }
                return key == "tag_rule" || key == "layer_rule" ? "\(key)=\(value)" : key
            }
        }
        let onHyper = ["bind:", "mousebind:", "axisbind:"]
        func outsideKeys(_ e: [String]) -> [String] { e.filter { x in !onHyper.contains(where: x.hasPrefix) } }
        let mango = outsideKeys(entries(try String(contentsOf: mangoURL, encoding: .utf8), commented: false))
        let port = outsideKeys(entries(try String(contentsOf: packageRoot.appendingPathComponent("Resources/config.conf"), encoding: .utf8), commented: true))
        var rest = port[...]
        var missing: [String] = []
        for e in mango {
            if let i = rest.firstIndex(of: e) { rest = port[(i + 1)...] } else { missing.append(e) }
        }
        XCTAssertEqual(missing, [], "mango entries missing from Resources/config.conf, or out of mango's order")
    }

    func testMangoStockConfigLoadsWithoutErrors() throws {
        let root = ProcessInfo.processInfo.environment["MANGO_SOURCES"]
            ?? NSHomeDirectory() + "/sources/mango"
        let url = URL(fileURLWithPath: root + "/assets/config.conf")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path), "no mango checkout at \(root)")
        let parsed = ConfigParser.parseConfig(fileAt: url)
        XCTAssertEqual(parsed.errors.map(\.description), [])
        XCTAssertGreaterThan(parsed.config.keyBindings.count, 50)
    }

    func testLiveSessionConfigLoadsWithoutErrors() throws {
        var text = try String(contentsOf: packageRoot.appendingPathComponent("Resources/config.conf"), encoding: .utf8)
        let edits = [
            ("focused_opacity=1.0", "focused_opacity=0.1"),
            ("unfocused_opacity=1.0", "unfocused_opacity=0.5"),
            ("default_master_factor=0.55", "default_master_factor=0.62"),
            ("gap_inner_horizontal=5", "gap_inner_horizontal=15"),
            ("gap_inner_vertical=5", "gap_inner_vertical=15"),
            ("gap_outer_horizontal=10", "gap_outer_horizontal=12"),
            ("gap_outer_vertical=10", "gap_outer_vertical=12"),
            ("border_px=4", "border_px=1"),
        ]
        for (old, new) in edits {
            XCTAssertTrue(text.contains("\r\n" + old + "\r\n"), "Resources/config.conf no longer contains \(old)")
            text = text.replacingOccurrences(of: "\r\n" + old + "\r\n", with: "\r\n" + new + "\r\n")
        }
        let parsed = parse(text)
        XCTAssertEqual(parsed.errors.map(\.description), [])
        let c = parsed.config
        XCTAssertEqual(c.focusedOpacity, 0.1)
        XCTAssertEqual(c.unfocusedOpacity, 0.5)
        XCTAssertEqual(c.defaultMfact, 0.62)
        XCTAssertEqual([c.gappih, c.gappiv, c.gappoh, c.gappov], [15, 15, 12, 12])
        XCTAssertEqual(c.borderpx, 1)
    }

    func testClampsOfOptionsConfigClampDoesNotKnow() {
        let c = parse("""
        hotarea_size=0
        overview_gap_inner=5000
        overview_gap_outer=-4
        overcircle_center_ratio=0.95
        drag_corner=9
        border_resize_size=99
        snap_distance=-5
        axis_bind_apply_timeout=5000
        cursor_hide_timeout=99999
        swipe_min_threshold=0
        gesture_swipe_distance=10
        gesture_swipe_cancel_ratio=2
        gesture_swipe_min_speed_to_force=-3
        scratchpad_width_ratio=0
        scratchpad_height_ratio=7
        special_dim=3
        special_gap_outer_horizontal=-1
        special_gap_inner_vertical=2000
        tag_animation_direction=5
        """).config
        XCTAssertEqual(c.hotareaSize, 1)
        XCTAssertEqual(c.overviewgappi, 1000)
        XCTAssertEqual(c.overviewgappo, 0)
        XCTAssertEqual(c.overcircleCenterRatio, 0.9)
        XCTAssertEqual(c.dragCorner, 4)
        XCTAssertEqual(c.borderResizeSize, 50)
        XCTAssertEqual(c.snapDistance, 0)
        XCTAssertEqual(c.axisBindApplyTimeout, 1000)
        XCTAssertEqual(c.cursorHideTimeout, 36000)
        XCTAssertEqual(c.swipeMinThreshold, 1)
        XCTAssertEqual(c.gestureSwipeDistance, 32)
        XCTAssertEqual(c.gestureSwipeCancelRatio, 0.95)
        XCTAssertEqual(c.gestureSwipeMinSpeedToForce, 0)
        XCTAssertEqual(c.scratchpadWidthRatio, 0.1)
        XCTAssertEqual(c.scratchpadHeightRatio, 1)
        XCTAssertEqual(c.specialDim, 1)
        XCTAssertEqual(c.specialGappoh, 0)
        XCTAssertEqual(c.specialGappiv, 1000)
        XCTAssertEqual(c.tagAnimationDirection, 1)
        XCTAssertEqual(parse("overcircle_center_ratio=0").config.overcircleCenterRatio, 0.1)
    }

    func testSetoptionClampsToo() {
        var config = Config()
        XCTAssertEqual(ConfigOptions.parseOption(key: "overcircle_center_ratio", value: "5", to: &config), .applied)
        XCTAssertEqual(config.overcircleCenterRatio, 0.9)
        XCTAssertEqual(ConfigOptions.parseOption(key: "hotarea_size", value: "-3", to: &config), .applied)
        XCTAssertEqual(config.hotareaSize, 1)
    }

    func testNonFiniteNumbersReadAsZero() {
        for bad in ["nan", "inf", "-inf", "1e999", "infinity", "abc"] {
            let parsed = parse("default_master_factor=\(bad)")
            XCTAssertEqual(parsed.errors.count, 0, bad)
            XCTAssertEqual(parsed.config.defaultMfact, 0.1, bad)
        }
        XCTAssertEqual(parse("default_master_factor=.7").config.defaultMfact, 0.7)
        XCTAssertEqual(parse("default_master_factor=0.6f").config.defaultMfact, 0.6)
        XCTAssertEqual(parse("default_master_factor=5.").config.defaultMfact, 0.9, "clamped to 0.9")
        XCTAssertEqual(parse("border_px=2.9").config.borderpx, 2)
    }

    func testDefaultConfigPathIgnoresXDGConfigHome() {
        let previous = getenv("XDG_CONFIG_HOME").map { String(cString: $0) }
        setenv("XDG_CONFIG_HOME", "/tmp/not-mangos-business", 1)
        defer {
            if let previous { setenv("XDG_CONFIG_HOME", previous, 1) } else { unsetenv("XDG_CONFIG_HOME") }
        }
        let path = ConfigParser.defaultConfigURL().path
        XCTAssertEqual(path, NSHomeDirectory() + "/.config/mango/config.conf")
    }

    func testConflictsAreCheckedAfterHyperIsResolved() {
        let ok = ConfigParser.parse(text: """
        bind=HYPER,x,killclient
        bind=HYPER+SHIFT,x,quit
        chutney_hyper_modifier=super+ctrl+alt
        """, baseDirectory: nil, fileName: "t.conf")
        XCTAssertEqual(ok.errors, [])
        let clash = ConfigParser.parse(text: """
        bind=HYPER,x,killclient
        bind=SUPER+CTRL+ALT,x,quit
        chutney_hyper_modifier=super+ctrl+alt
        """, baseDirectory: nil, fileName: "t.conf")
        XCTAssertEqual(clash.errors.map(\.line), [2], "reported at the later binding")
    }

    func testHyperIsResolvedAfterTheWholeFileIsRead() {
        let parsed = parse("""
        bind=HYPER,a,killclient
        mousebind=HYPER,btn_left,moveresize,curmove
        axisbind=HYPER,UP,viewtoleft
        gesturebind=HYPER,left,3,focusdir,left
        chutney_hyper_modifier=super+ctrl
        """)
        XCTAssertEqual(parsed.errors, [])
        let expected: Modifiers = [.superKey, .ctrl]
        XCTAssertEqual(parsed.config.keyBindings.first?.mods, expected)
        XCTAssertEqual(parsed.config.mouseBindings.first?.mods, expected)
        XCTAssertEqual(parsed.config.axisBindings.first?.mods, expected)
        XCTAssertEqual(parsed.config.gestureBindings.first?.mods, expected)
    }
}
