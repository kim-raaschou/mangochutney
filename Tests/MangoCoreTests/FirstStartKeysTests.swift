import XCTest
@testable import Mango
@testable import Port

/// The config a first start writes (not in mango): mango's config.conf with mango's keys on
/// Hyper, and the first lines to try near its end.
final class FirstStartKeysTests: MangoTestCase {
    private var resources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources")
    }

    private func config() throws -> String {
        try String(contentsOf: resources.appendingPathComponent("config.conf"), encoding: .utf8)
    }

    /// mango's key, mouse and scroll bindings are on Hyper ($mod, $mods); none takes Command,
    /// Option or Control alone (a key mode's keys are only held inside it). mango's gestures stay.
    func testMangosKeysAreOnHyper() throws {
        let p = ConfigParser.parseConfig(fileAt: resources.appendingPathComponent("config.conf"))
        XCTAssertEqual(p.errors, [], p.errors.map(\.description).joined(separator: "\n"))
        let lines = try config().components(separatedBy: "\r\n")
        XCTAssertTrue(lines.contains("var=mod,HYPER"))
        XCTAssertTrue(lines.contains("var=mods,HYPER+SHIFT"))
        var mode = "default"
        for line in lines {
            if line.hasPrefix("key_mode=") { mode = String(line.dropFirst("key_mode=".count)) }
            guard mode == "default", ["bind=", "mousebind=", "axisbind="].contains(where: line.lowercased().hasPrefix) else { continue }
            let mods = line.split(separator: "=", maxSplits: 1)[1].split(separator: ",").first.map(String.init) ?? ""
            XCTAssertTrue(["$mod", "$mods", "HYPER"].contains(mods), line)
        }
        let names = p.config.keyBindings.map(\.dispatch.name)
        XCTAssertTrue(names.contains("chutney_toggle_hotkeys_palette"))
        XCTAssertTrue(names.contains("chutney_toggle_layout_palette"))
        XCTAssertEqual(p.config.mouseBindings.count, 2)
        XCTAssertFalse(p.config.gestureBindings.isEmpty)
        XCTAssertEqual(p.config.chutneyHyperKey, "caps_lock")
        XCTAssertEqual(p.config.xkbRulesOptions, "", "Caps Lock as Hyper is chutney_hyper_key's")
    }

    /// The first lines to try, between "Your own settings" and the menu's file: all commented
    /// out, so they change nothing until a # is taken away, and each line is one of mango's keys.
    func testTheFirstLinesToTryAreCommentedOutAndMangos() throws {
        let lines = try config().components(separatedBy: "\r\n")
        guard let own = lines.firstIndex(where: { $0.hasPrefix("# Your own settings") }),
              let end = lines.firstIndex(of: "source_optional=chutney_menu.conf"), own < end else {
            return XCTFail("the first lines to try are gone")
        }
        let block = lines[own..<end].filter { !$0.isEmpty }
        XCTAssertTrue(block.allSatisfy { $0.hasPrefix("#") })
        let tried = block.filter { $0.range(of: #"^# [a-z_]+="#, options: .regularExpression) != nil }
            .map { String($0.dropFirst(2)) }
        XCTAssertEqual(tried.count, 8)
        let p = ConfigParser.parse(text: tried.joined(separator: "\n"), baseDirectory: resources, fileName: "config.conf")
        XCTAssertEqual(p.errors, [], p.errors.map(\.description).joined(separator: "\n"))
        XCTAssertEqual(p.config.borderpx, 8)
        XCTAssertEqual(p.config.tagRules.first?.layoutName, "scroller")
        XCTAssertEqual(p.config.keyBindings.first?.dispatch.name, "spawn")
    }

    /// The first start's Hyper key choice replaces this line in the config it wrote; Caps
    /// Lock until then.
    func testHyperKeyChoiceFindsItsLine() throws {
        let shipped = try config()
        XCTAssertEqual(shipped.components(separatedBy: ConfigFiles.hyperKeyLine).count, 2, "once")
        let chosen = shipped.replacingOccurrences(of: ConfigFiles.hyperKeyLine,
                                                  with: "chutney_hyper_key=right_option\r\nchutney_hyper_tap=escape\r\n")
        let p = ConfigParser.parse(text: chosen, baseDirectory: resources, fileName: "config.conf")
        XCTAssertEqual(p.errors, [])
        XCTAssertEqual(p.config.chutneyHyperKey, "right_option")
        XCTAssertEqual(p.config.chutneyHyperTap, "escape")
    }

    /// The first lines to try come after the theme's line, so a colour of the user's wins.
    func testYourLinesComeAfterTheTheme() throws {
        let lines = try config().components(separatedBy: "\r\n")
        let theme = try XCTUnwrap(lines.firstIndex(of: "source_optional=chutney_theme.conf"))
        let own = try XCTUnwrap(lines.firstIndex { $0.hasPrefix("# Your own settings") })
        let menu = try XCTUnwrap(lines.firstIndex(of: "source_optional=chutney_menu.conf"))
        XCTAssertTrue(theme < own && own < menu)
    }

    /// Continue writes the chosen key into the config just written.
    func testSetHyperKeyWritesTheChoice() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.conf")
        try config().write(to: url, atomically: true, encoding: .utf8)
        ConfigFiles.setHyperKey("f5", tap: "original", configURL: url)
        let p = ConfigParser.parseConfig(fileAt: url)
        XCTAssertEqual(p.config.chutneyHyperKey, "f5")
        XCTAssertEqual(p.config.chutneyHyperTap, "original")
    }

    /// mango's watcher: a file replaced by one with the same text has changed (a new inode).
    func testTheWatcherSeesAFileReplaced() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.conf")
        try "gappih=5\n".write(to: url, atomically: true, encoding: .utf8)
        let before = ConfigWatcher.state(url)
        try "gappih=5\n".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertNotNil(before)
        XCTAssertNotEqual(ConfigWatcher.state(url), before)
        try FileManager.default.removeItem(at: url)
        XCTAssertNil(ConfigWatcher.state(url))
    }
}
