import XCTest
@testable import Mango
import MangoTestKit

/// mango's src/config/reapply.c
@MainActor
final class ReapplyTests: XCTestCase {

    // MARK: parse_tagrule

    func testATagRulesFlagsSurviveAReload() {
        let mango = TestMango("tag_rule=id:2,open_as_floating:1")
        XCTAssertTrue(mango.monitor.pertag.openAsFloating[2])

        mango.server.config = ConfigParser.parse(text: "", baseDirectory: nil, fileName: "t").config
        mango.server.parseTagrule(mango.monitor)

        XCTAssertTrue(mango.monitor.pertag.openAsFloating[2], "left as it was")
    }

    func testARemovedTagRuleSendsTheTagBackToTile() {
        let mango = TestMango("tag_rule=id:2,layout_name:scroller")
        XCTAssertEqual(mango.monitor.pertag.ltidxs[2], .scroller)

        mango.server.config.tagRules = []
        mango.server.parseTagrule(mango.monitor)

        XCTAssertEqual(mango.monitor.pertag.ltidxs[2], .tile)
    }

    // MARK: reset_option

    func testAReloadRunsExecThroughTheShellAndNotExecOnce() throws {
        let mango = TestMango()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.conf")
        try "exec=FOO=1 echo a | cat\nexec_once=echo b\n".write(to: url, atomically: true, encoding: .utf8)
        mango.server.configURL = url

        mango.server.reloadConfig(nil)

        XCTAssertEqual(mango.wlroots.shelled, ["FOO=1 echo a | cat"])
    }
}
