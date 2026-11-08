import XCTest
@testable import Mango
@testable import Port

final class MenuSaveTests: MangoTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("menusave-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

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
}

extension MenuSaveTests {
    func testOwnWritesAreKnownAndHandEditsAreNot() throws {
        let menu = dir.appendingPathComponent("menu.conf")
        MenuSave.set("smart_gaps", "1", in: menu)
        XCTAssertTrue(MenuSave.isOwnWrite(menu))
        try "smart_gaps=0\n".write(to: menu, atomically: false, encoding: .utf8)
        XCTAssertFalse(MenuSave.isOwnWrite(menu))
    }
}
