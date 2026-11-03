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

    /// start.conf (not in mango), the welcome's first lines to try: all commented out, so it
    /// changes nothing until a # is taken away, and each line is one of mango's keys.
    func testStartConfIsCommentedOutAndEveryLineIsMangos() throws {
        let lines = try resource("start.conf").components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertTrue(lines.allSatisfy { $0.hasPrefix("#") })
        XCTAssertTrue(ConfigParser.parseConfig(fileAt: resources.appendingPathComponent("start.conf")).errors.isEmpty)
        let tried = lines.filter { $0.range(of: #"^# [a-z_]+="#, options: .regularExpression) != nil }
            .map { String($0.dropFirst(2)) }
        XCTAssertEqual(tried.count, 8)
        let p = ConfigParser.parse(text: tried.joined(separator: "\n"), baseDirectory: resources, fileName: "start.conf")
        XCTAssertEqual(p.errors, [], p.errors.map(\.description).joined(separator: "\n"))
        XCTAssertEqual(p.config.borderpx, 8)
        XCTAssertEqual(p.config.tagRules.first?.layoutName, "scroller")
        XCTAssertEqual(p.config.keyBindings.first?.dispatch.name, "spawn")
    }

    /// The first start's "Caps Lock is Hyper" choice removes or puts back these lines in the
    /// config it wrote (config-mac.conf); both must be there to find.
    func testCapsLockChoiceFindsItsLines() throws {
        let mac = try resource("config-mac.conf")
        XCTAssertTrue(mac.contains(ConfigFiles.capsHyperLines))
        XCTAssertTrue(mac.contains(ConfigFiles.hyperComment))
        let off = mac.replacingOccurrences(of: ConfigFiles.capsHyperLines, with: "")
        let p = ConfigParser.parse(text: off, baseDirectory: resources, fileName: "config.conf")
        XCTAssertEqual(p.config.xkbRulesOptions, "", "Caps Lock left alone")
        let on = off.replacingOccurrences(of: ConfigFiles.hyperComment, with: ConfigFiles.hyperComment + ConfigFiles.capsHyperLines)
        XCTAssertEqual(on, mac)
    }
}
