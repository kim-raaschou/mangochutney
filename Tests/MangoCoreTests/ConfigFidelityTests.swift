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
        XCTAssertEqual(c.scratchpadWidthRatio, 0)
        XCTAssertEqual(c.scratchpadHeightRatio, 1)
        XCTAssertEqual(c.specialDim, 1)
        XCTAssertEqual(c.specialGappoh, 0)
        XCTAssertEqual(c.specialGappiv, 1000)
        XCTAssertEqual(c.tagAnimationDirection, 1)
        XCTAssertEqual(parse("overcircle_center_ratio=0").config.overcircleCenterRatio, 0.1)
    }

    func testSetoptionClampsToo() {
        var config = Config()
        XCTAssertTrue(parseOption("overcircle_center_ratio", "5", to: &config))
        XCTAssertEqual(config.overcircleCenterRatio, 0.9)
        XCTAssertTrue(parseOption("hotarea_size", "-3", to: &config))
        XCTAssertEqual(config.hotareaSize, 1)
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

    func testHyperIsItsOwnModifierAsInMango() {
        let parsed = ConfigParser.parse(text: """
        bind=HYPER,x,killclient
        bind=HYPER+SHIFT,x,quit
        bind=SUPER+CTRL+ALT,x,quit
        chutney_hyper_modifier=super+ctrl+alt
        """, baseDirectory: nil, fileName: "t.conf")
        XCTAssertEqual(parsed.errors, [], "mango: HYPER (Mod3) and SUPER+CTRL+ALT are two chords")
        XCTAssertEqual(KeyboardOptions.unreachable(parsed.config), ["SUPER+CTRL+ALT,x"],
                       "the port: those keys held are HYPER, so the port says so")
        let clash = ConfigParser.parse(text: """
        bind=HYPER,x,killclient
        bind=hyper,x,quit
        """, baseDirectory: nil, fileName: "t.conf")
        XCTAssertEqual(clash.errors.map(\.line), [2], "reported at the later binding")
    }
}
