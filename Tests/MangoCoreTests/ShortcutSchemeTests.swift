import XCTest
@testable import Mango
@testable import Port

final class ShortcutSchemeTests: MangoTestCase {
    var shipped: ParsedConfig {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/config.conf")
        return ConfigParser.parseConfig(fileAt: url)
    }

    func testShippedConfigParses() {
        XCTAssertTrue(shipped.errors.isEmpty, "\(shipped.errors)")
    }

    func testMangosBindingsAndThePalettesOnHyper() {
        let binds = shipped.config.keyBindings
        let hyper: Modifiers = .hyper
        XCTAssertEqual(binds.first { $0.dispatch.name == "reload_config" }?.mods, hyper)
        XCTAssertEqual(binds.first { $0.dispatch.name == "tag" && $0.dispatch.arg(0) == "1" }?.mods, hyper.union(.shift))
        for name in ["chutney_keybindings", "chutney_layout_switcher"] {
            XCTAssertEqual(binds.first { $0.dispatch.name == name }?.mods, hyper, name)
        }
    }

    func testReadableRows() {
        let rows = ShortcutFormatter.rows(shipped.config)
        let focusLeft = rows.first { $0.dispatch == "focusdir" && $0.args.first == "left" }
        XCTAssertEqual(focusLeft?.keys, "⌃⌥⌘ ←")
        XCTAssertEqual(focusLeft?.action, "focus left")
        let send3 = rows.first { $0.dispatch == "tag" && $0.args.first == "3" }
        XCTAssertEqual(send3?.keys, "⌃⌥⇧⌘ 3")
        XCTAssertEqual(send3?.action, "send window to tag 3")
        XCTAssertTrue(rows.contains { $0.keys == "⌃⌥⌘ + left drag" && $0.action == "move window" })
    }

    func testGetBindsJSON() {
        let text = ShortcutFormatter.bindsReply([ShortcutRow(mode: "default", keys: "⌃⌥⌘ R", action: "reload config",
                                                             dispatch: "reload_config", args: [])]).serialized
        XCTAssertTrue(text.contains("reload config"), text)
    }
}
