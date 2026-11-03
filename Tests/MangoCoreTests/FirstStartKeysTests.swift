import XCTest
@testable import Mango
@testable import Port

/// The keys a first start begins with (not in mango): mango's (config.conf) or macOS's with
/// mango's on Hyper (config-mac.conf, built by script/mac-config.swift). The built file must
/// follow its two sources; run `make mac-config` when one of them changes.
final class FirstStartKeysTests: MangoTestCase {
    private var resources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources")
    }

    private func resource(_ name: String) throws -> String {
        try String(contentsOf: resources.appendingPathComponent(name), encoding: .utf8)
    }

    /// Lines up to the port's marker.
    private func mangoPart(_ text: String) -> [String] {
        Array(text.components(separatedBy: "\r\n").prefix { !$0.hasPrefix(ConfigFiles.portMarker) })
    }

    func testMangosPartIsTheDefaultsWithTheBindingsCommentedOut() throws {
        let mac = mangoPart(try resource("config-mac.conf"))
            .filter { !$0.hasPrefix("# Mango Chutney: these are on Hyper") }
        let bindings = ["bind=", "mousebind=", "axisbind="]
        let expected = mangoPart(try resource("config.conf")).map { line in
            bindings.contains(where: line.lowercased().hasPrefix) ? "# " + line : line
        }
        XCTAssertEqual(mac, expected, "config-mac.conf is out of date: make mac-config")
        XCTAssertFalse(mac.contains { $0.hasPrefix("bind=") || $0.hasPrefix("mousebind=") || $0.hasPrefix("axisbind=") })
        XCTAssertTrue(mac.contains { $0.hasPrefix("gesturebind=") }, "mango's gestures stay")
    }

    func testTheMacSetOnCapsLock() throws {
        let p = ConfigParser.parseConfig(fileAt: resources.appendingPathComponent("config-mac.conf"))
        XCTAssertEqual(p.errors, [], p.errors.map(\.description).joined(separator: "\n"))
        let lines = try resource("config-mac.conf").components(separatedBy: "\r\n")
        let macBinds = try resource("mac-bindings.conf").components(separatedBy: "\n").filter { $0.hasPrefix("bind=") }
        for b in macBinds { XCTAssertTrue(lines.contains(b), "config-mac.conf is out of date: make mac-config (\(b))") }
        XCTAssertEqual(p.config.keyBindings.count, macBinds.count + 2)   // and Hyper K, Hyper L
        XCTAssertEqual(p.config.keyBindings.prefix(2).map(\.dispatch.name),
                       ["chutney_toggle_hotkeys_palette", "chutney_toggle_layout_palette"])
        XCTAssertEqual(p.config.mouseBindings.count, 2)
        XCTAssertFalse(p.config.gestureBindings.isEmpty)
        XCTAssertEqual(p.config.xkbRulesOptions, "caps:hyper")
    }
}
