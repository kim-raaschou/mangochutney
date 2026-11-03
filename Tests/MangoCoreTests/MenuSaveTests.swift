import XCTest
@testable import Mango
@testable import Port

/// chutney_menu_config (port extension): the menu's changes in a file of their own.
final class MenuSaveTests: MangoTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("menusave-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    /// The config reads the file with mango's own source_optional, last; the key only names
    /// where the panel writes, the parser does not read it by itself.
    func testTheFileIsReadBySourceOptionalAndWins() throws {
        let conf = dir.appendingPathComponent("config.conf")
        let menu = dir.appendingPathComponent("menu.conf")
        MenuSave.set("border_px", "5", in: menu)
        try "chutney_menu_config=menu.conf\nborder_px=2\n".write(to: conf, atomically: true, encoding: .utf8)
        XCTAssertEqual(ConfigParser.parseConfig(fileAt: conf).config.borderpx, 2, "not read without the line")
        try "chutney_menu_config=menu.conf\nborder_px=2\nsource_optional=menu.conf\n".write(to: conf, atomically: true, encoding: .utf8)
        XCTAssertEqual(ConfigParser.parseConfig(fileAt: conf).config.borderpx, 5)
    }

    func testOneLinePerKeyAndPerTagRuleField() {
        let menu = dir.appendingPathComponent("menu.conf")
        MenuSave.set("border_px", "3", in: menu)
        MenuSave.set("border_px", "4", in: menu)
        MenuSave.setTagRule(tag: 1, "layout_name", "monocle", in: menu)
        MenuSave.setTagRule(tag: 1, "master_factor", "0.60", in: menu)
        MenuSave.setTagRule(tag: 1, "layout_name", "scroller", in: menu)
        XCTAssertEqual(MenuSave.read(menu), ["border_px=4", "tag_rule=id:1,master_factor:0.60,layout_name:scroller"])
    }

    func testConflictsWithTheConfigAndClearingThem() throws {
        let conf = dir.appendingPathComponent("config.conf")
        try "border_px=2\ngap_inner_horizontal=5\ntag_rule=id:1,layout_name:tile\n".write(to: conf, atomically: true, encoding: .utf8)
        let menu = dir.appendingPathComponent("menu.conf")
        MenuSave.set("border_px", "4", in: menu)
        MenuSave.set("gap_inner_horizontal", "5", in: menu)            // same value: no conflict
        MenuSave.setTagRule(tag: 1, "layout_name", "monocle", in: menu)
        MenuSave.setTagRule(tag: 1, "master_factor", "0.6", in: menu)  // the config does not set it
        let c = MenuSave.conflicts(configURL: conf, menuURL: menu)
        XCTAssertEqual(c.map(\.key), ["border_px", "tag_rule id:1 layout_name"])
        XCTAssertEqual(c.first?.configLine, 1)
        XCTAssertEqual(c.last?.configLine, 3)
    }

    /// mango's own config.conf ends its lines with CRLF: the same value is no conflict.
    func testACRLFConfigIsReadByItsValues() throws {
        let conf = dir.appendingPathComponent("config.conf")
        try "animations=1\r\nborder_px=4\r\n".write(to: conf, atomically: true, encoding: .utf8)
        let menu = dir.appendingPathComponent("menu.conf")
        MenuSave.set("animations", "1", in: menu)
        MenuSave.set("border_px", "3", in: menu)
        let c = MenuSave.conflicts(configURL: conf, menuURL: menu)
        XCTAssertEqual(c.map(\.key), ["border_px"])
        XCTAssertEqual(c.first?.configValue, "4")
        XCTAssertEqual(c.first?.configLine, 2)
    }
}

extension MenuSaveTests {
    /// The menu is compared with every file read before it, in mango's order: chutney.conf's
    /// value wins over config.conf's, and a file read after the menu file does not count.
    func testConflictsFollowTheFilesReadBeforeTheMenu() throws {
        let conf = dir.appendingPathComponent("config.conf")
        try "border_px=2\r\ngap_inner_horizontal=5\r\nsource_optional=chutney.conf\r\n"
            .write(to: conf, atomically: true, encoding: .utf8)
        try "border_px=3\nsource_optional=menu.conf\nsource_optional=later.conf\n"
            .write(to: dir.appendingPathComponent("chutney.conf"), atomically: true, encoding: .utf8)
        try "smart_gaps=0\n".write(to: dir.appendingPathComponent("later.conf"), atomically: true, encoding: .utf8)
        let menu = dir.appendingPathComponent("menu.conf")
        MenuSave.set("border_px", "4", in: menu)
        MenuSave.set("gap_inner_horizontal", "6", in: menu)
        MenuSave.set("smart_gaps", "1", in: menu)
        let c = MenuSave.conflicts(configURL: conf, menuURL: menu)
        XCTAssertEqual(c.map(\.key), ["border_px", "gap_inner_horizontal"])
        XCTAssertEqual(c.map { "\($0.configFile):\($0.configLine)=\($0.configValue)" },
                       ["chutney.conf:1=3", "config.conf:2=5"])
    }

    /// The config watcher skips the panel's own saves; an edit by hand is not one.
    func testOwnWritesAreKnownAndHandEditsAreNot() throws {
        let menu = dir.appendingPathComponent("menu.conf")
        MenuSave.set("smart_gaps", "1", in: menu)
        XCTAssertTrue(MenuSave.isOwnWrite(menu))
        try "smart_gaps=0\n".write(to: menu, atomically: false, encoding: .utf8)
        XCTAssertFalse(MenuSave.isOwnWrite(menu))
    }
}
