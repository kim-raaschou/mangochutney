import XCTest
import ApplicationServices
@testable import Mango
@testable import Port

/// mango's monitor removal and return (monitor.c, `oldmonname`): windows keep their tags,
/// floating ones are centred, and they go back when their display returns.
final class EngineMonitorChangeTests: MangoTestCase {
    let laptop = Screen(displayID: 1, name: "Built-in", frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                        workArea: CGRect(x: 0, y: 37, width: 1728, height: 1080), scale: 2, isMain: true)
    let external = Screen(displayID: 2, name: "LG", frame: CGRect(x: 1728, y: 0, width: 2560, height: 1440),
                          workArea: CGRect(x: 1728, y: 25, width: 2560, height: 1415), scale: 2, isMain: false)

    @MainActor
    func client(_ server: MangoServer, id: CGWindowID, on m: Monitor, tags: UInt32, floating: Bool, frame: CGRect) -> Client {
        let w = DiscoveredWindow(id: id, pid: getpid(), element: AXUIElementCreateApplication(getpid()), bundleId: "test",
                                 appName: "Test", title: "t", subrole: "AXStandardWindow", isDialog: false,
                                 frame: frame, isMinimized: false, isFullscreen: false,
                                 isAppHidden: false)
        let c = Client(window: w, monitor: m, tags: tags)
        c.isFloating = floating
        server.clients.append(c)
        return c
    }

    @MainActor
    func testWindowsKeepTagsAndGoHomeWhenTheDisplayReturns() throws {
        let server = MangoServer(configURL: URL(fileURLWithPath: "/nonexistent/mango.conf"))
        server.system = FakeWindowSystem(server)
        server.rebuildMonitors(screens: [laptop, external])
        let ext = try XCTUnwrap(server.monitors.first { $0.screen.displayID == 2 })
        let devMode = client(server, id: 10, on: ext, tags: 1 << 8, floating: true,
                             frame: CGRect(x: 2000, y: 300, width: 863, height: 636))
        let editor = client(server, id: 11, on: ext, tags: 1 << 1, floating: false,
                            frame: CGRect(x: 1800, y: 100, width: 1200, height: 900))

        server.rebuildMonitors(screens: [laptop])   // external disconnected
        let lap = try XCTUnwrap(server.monitors.first)
        XCTAssertTrue(devMode.mon === lap)
        XCTAssertEqual(devMode.tags, 1 << 8, "dev mode stays on tag 9")
        XCTAssertEqual(editor.tags, 1 << 1)
        XCTAssertEqual(devMode.floatGeom.midX, lap.screen.workArea.midX, accuracy: 1, "floating: centred")
        XCTAssertEqual(devMode.floatGeom.midY, lap.screen.workArea.midY, accuracy: 1)
        XCTAssertEqual(devMode.oldmonname, 2)

        server.rebuildMonitors(screens: [laptop, external])   // connected again
        XCTAssertEqual(devMode.mon?.screen.displayID, 2, "back home")
        XCTAssertEqual(editor.mon?.screen.displayID, 2)
        XCTAssertEqual(devMode.tags, 1 << 8)
    }

    @MainActor
    func testAWindowMovedByTheUserStaysWhereItWasMoved() throws {
        let server = MangoServer(configURL: URL(fileURLWithPath: "/nonexistent/mango.conf"))
        server.system = FakeWindowSystem(server)
        server.rebuildMonitors(screens: [laptop, external])
        let ext = try XCTUnwrap(server.monitors.first { $0.screen.displayID == 2 })
        let lap = try XCTUnwrap(server.monitors.first { $0.screen.displayID == 1 })
        let c = client(server, id: 12, on: ext, tags: 1, floating: false, frame: CGRect(x: 1800, y: 100, width: 800, height: 600))
        server.rebuildMonitors(screens: [laptop])
        c.oldmonname = lap.screen.displayID   // a drag onto the laptop: pointer_end_grab_client records it (client_update_oldmonname_record)
        server.rebuildMonitors(screens: [laptop, external])
        XCTAssertEqual(c.mon?.screen.displayID, 1, "the user chose the laptop")
    }

    /// A bug in mango (docs/afvigelser.md §6): parse_tagrule gives every window the mfact of
    /// the last monitor's tag. Here each monitor's windows keep their own monitor's.
    @MainActor
    func testAReloadKeepsEachMonitorsOwnMfact() throws {
        let server = MangoServer(configURL: URL(fileURLWithPath: "/nonexistent/mango.conf"))
        server.system = FakeWindowSystem(server)
        server.rebuildMonitors(screens: [laptop, external])
        let lap = try XCTUnwrap(server.monitors.first { $0.screen.displayID == 1 })
        let ext = try XCTUnwrap(server.monitors.first { $0.screen.displayID == 2 })
        let a = client(server, id: 20, on: lap, tags: 1, floating: false, frame: CGRect(x: 0, y: 40, width: 800, height: 600))
        let b = client(server, id: 21, on: ext, tags: 1, floating: false, frame: CGRect(x: 1800, y: 40, width: 800, height: 600))
        server.config.tagRules = ConfigParser.parse(text: """
            tag_rule=id:1,monitor_name:Built-in,master_factor:0.3
            tag_rule=id:1,monitor_name:LG,master_factor:0.7
            """, baseDirectory: nil, fileName: "t").config.tagRules
        for m in server.monitors { m.parseTagrule(config: server.config, clients: server.clientsAll) }
        XCTAssertEqual(a.masterMfactPer, 0.3, accuracy: 0.001)
        XCTAssertEqual(b.masterMfactPer, 0.7, accuracy: 0.001)
    }

    /// mango tag_rule_matches_monitor: make, model and serial must equal wlr_output's, and an
    /// unknown (NULL) value never matches.
    func testTagRuleMatchesMakeModelSerial() {
        var benq = external
        benq.make = "BNQ"; benq.model = "BenQ RD280U"; benq.serial = "J7R0095701Q"
        func rule(_ s: String) -> TagRule {
            ConfigParser.parse(text: "tag_rule=id:1,\(s),master_factor:0.7", baseDirectory: nil, fileName: "t").config.tagRules[0]
        }
        XCTAssertTrue(rule("monitor_make:BNQ").tagRuleMatchesMonitor(benq))
        XCTAssertTrue(rule("monitor_model:BenQ RD280U,monitor_serial:J7R0095701Q").tagRuleMatchesMonitor(benq))
        XCTAssertFalse(rule("monitor_make:DEL").tagRuleMatchesMonitor(benq))
        XCTAssertFalse(rule("monitor_serial:J7R").tagRuleMatchesMonitor(benq))
        XCTAssertFalse(rule("monitor_make:BNQ").tagRuleMatchesMonitor(laptop))
        XCTAssertTrue(rule("monitor_name:LG").tagRuleMatchesMonitor(benq))
    }
}
