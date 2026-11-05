import XCTest
import ApplicationServices
@testable import Mango
@testable import Port

/// The layout kept on disk so a restart of mango does not put every window on the
/// current tag.
final class SavedLayoutTests: MangoTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("mango-layout-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func window(_ id: CGWindowID, tags: UInt32, bundle: String = "com.example", snapshot: [CGWindowID]? = nil) -> SavedLayout.Window {
        SavedLayout.Window(id: id, bundleId: bundle, tags: tags, displayID: 1, homeDisplayID: 2, isFloating: true,
                           isGlobal: false, isOverlay: false, isMinimized: false, isScratchpad: false,
                           isNamedScratchpad: false, floatFrame: CGRect(x: 10, y: 20, width: 300, height: 200),
                           scrollerProportion: 0.5, orderSnapshot: snapshot)
    }

    func testRoundTripInTheSameSession() throws {
        let url = dir.appendingPathComponent("mango/windows.json")
        let saved = SavedLayout(session: "S1", order: [3, 1, 2], windows: [window(1, tags: 1 << 8)], tagsets: ["1": 1 << 2])
        try saved.write(to: url)
        XCTAssertEqual(SavedLayout.load(from: url, session: "S1"), saved)
    }

    func testAFileFromBeforeTagLayoutsAndTilingWereKeptStillLoads() throws {
        let url = dir.appendingPathComponent("windows.json")
        try SavedLayout(session: "S1", order: [], windows: [window(1, tags: 1)], tagsets: [:]).write(to: url)
        let json = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(json.contains("tagLayouts"), "as an older mango wrote it")
        let loaded = SavedLayout.load(from: url, session: "S1")
        XCTAssertNotNil(loaded)
        XCTAssertNil(loaded?.tagLayouts)
    }

    func testAnotherSessionOrABrokenFileIsIgnored() throws {
        let url = dir.appendingPathComponent("windows.json")
        try SavedLayout(session: "S1", order: [], windows: [window(1, tags: 1)], tagsets: [:]).write(to: url)
        XCTAssertNil(SavedLayout.load(from: url, session: "S2"), "window ids from another login session")
        XCTAssertNil(SavedLayout.load(from: url, session: ""), "no session id: nothing is trusted")
        try Data("{".utf8).write(to: url)
        XCTAssertNil(SavedLayout.load(from: url, session: "S1"))
    }

    func testSavedWindowsBecomeDepartedOnes() {
        let saved = SavedLayout(session: "S1", order: [3, 1, 2],
                                windows: [window(1, tags: 1 << 8), window(5, tags: 1, snapshot: [5, 3])], tagsets: [:])
        let d = Dictionary(uniqueKeysWithValues: saved.departed(at: 42))
        XCTAssertEqual(d[1]?.tags, 1 << 8)
        XCTAssertEqual(d[1]?.orderSnapshot, [3, 1, 2], "a managed window uses the saved order")
        XCTAssertEqual(d[5]?.orderSnapshot, [5, 3], "a window that was away keeps its own")
        XCTAssertEqual(d[1]?.bundleId, "com.example")
        XCTAssertEqual(d[1]?.homeDisplayID, 2)
        XCTAssertEqual(d[1]?.at, 42)
    }

    @MainActor
    func testAWindowIsWrittenOnlyWhenSomethingChanged() throws {
        let server = MangoServer(configURL: URL(fileURLWithPath: "/nonexistent/mango.conf"))
        server.system = FakeWindowSystem(server)
        let url = dir.appendingPathComponent("windows.json")
        server.mac.memory.layoutURL = url
        server.started = true
        guard !server.mac.memory.session.isEmpty else { throw XCTSkip("no window server session") }
        server.mac.memory.save(server)
        server.mac.memory.queue.sync {}
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        try FileManager.default.removeItem(at: url)
        server.mac.memory.save(server)   // nothing changed
        server.mac.memory.queue.sync {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    @MainActor
    func discover(_ bundle: String, savedAs savedBundle: String) -> Client? {
        let server = MangoServer(configURL: URL(fileURLWithPath: "/nonexistent/mango.conf"))
        server.system = FakeWindowSystem(server)
        server.rebuildMonitors(screens: [Screen(displayID: 1, name: "Built-in", frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                                            workArea: CGRect(x: 0, y: 37, width: 1728, height: 1080), scale: 2, isMain: true)])
        server.started = true
        server.registerPortExtensions()   // as start() does: the memory joins mango's map
        server.mac.memory.layoutURL = nil
        for (id, w) in SavedLayout(session: "S", order: [], windows: [window(77, tags: 1 << 8, bundle: savedBundle)],
                                   tagsets: [:]).departed(at: CACurrentMediaTime()) {
            server.mac.memory.departed.remember(id, w)
        }
        server.mac.windowDiscovered(DiscoveredWindow(id: 77, pid: getpid(), element: AXUIElementCreateApplication(getpid()),
                                             bundleId: bundle, appName: "Test", title: "t", subrole: "AXStandardWindow",
                                             isDialog: false, frame: CGRect(x: 0, y: 0, width: 400, height: 300),
                                             isMinimized: false, isFullscreen: false, isAppHidden: false))
        return server.clientByIdAll(77)
    }

    @MainActor
    func testASavedWindowGetsItsTagAndFloatingBack() {
        let c = discover("com.example", savedAs: "com.example")
        XCTAssertEqual(c?.tags, 1 << 8)
        XCTAssertEqual(c?.isFloating, true)
        XCTAssertEqual(c?.floatGeom, CGRect(x: 10, y: 20, width: 300, height: 200))
        XCTAssertEqual(c?.oldmonname, 2)
    }

    @MainActor
    func testARestoredIdForAnotherAppIsANewWindow() {
        XCTAssertNotEqual(discover("com.example", savedAs: "com.other")?.tags, 1 << 8)
    }

    func testSavedWindowsDoNotExpireButGoWhenTheWindowServerDropsThem() {
        var store = DepartedWindows()
        let saved = SavedLayout(session: "S", order: [], windows: [window(1, tags: 2), window(2, tags: 4)], tagsets: [:])
        for (id, d) in saved.departed(at: 0) { store.remember(id, d) }
        store.prune(now: DepartedWindows.keepFor * 10)
        XCTAssertEqual(store.entries.count, 2, "an app may not answer for hours")
        XCTAssertTrue(store.hasSavedEntries)
        store.dropSaved(keeping: [2])
        XCTAssertNil(store.entries[1], "window 1 is gone from the window server")
        XCTAssertEqual(store.take(2, now: DepartedWindows.keepFor * 10)?.tags, 4)
    }

    @MainActor
    func testEachDisplayShowsTheTagsItShowed() throws {
        let server = MangoServer(configURL: URL(fileURLWithPath: "/nonexistent/mango.conf"))
        server.system = FakeWindowSystem(server)
        guard !server.mac.memory.session.isEmpty else { throw XCTSkip("no window server session") }
        server.rebuildMonitors(screens: [Screen(displayID: 1, name: "Built-in", frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                                            workArea: CGRect(x: 0, y: 37, width: 1728, height: 1080), scale: 2, isMain: true)])
        let url = dir.appendingPathComponent("windows.json")
        try SavedLayout(session: server.mac.memory.session, order: [], windows: [window(9, tags: 1 << 2)], tagsets: ["1": 1 << 2]).write(to: url)
        server.mac.memory.layoutURL = url
        server.mac.memory.restore(server)
        XCTAssertEqual(server.monitors.first.map { $0.tagset[$0.seltags] }, 1 << 2)
        XCTAssertEqual(server.mac.memory.departed.entries[9]?.tags, 1 << 2)
    }

    /// A tag keeps the layout it was switched to, as on a reload of the config: also when
    /// the tag_rule that set it is gone; one whose rule gives another layout now takes it,
    /// the one in use becoming the previous one.
    @MainActor
    func testEachTagGetsItsLayoutBackUnlessItsRuleChanged() throws {
        let server = MangoServer(configURL: URL(fileURLWithPath: "/nonexistent/mango.conf"))
        server.system = FakeWindowSystem(server)
        guard !server.mac.memory.session.isEmpty else { throw XCTSkip("no window server session") }
        server.rebuildMonitors(screens: [Screen(displayID: 1, name: "Built-in", frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                                            workArea: CGRect(x: 0, y: 37, width: 1728, height: 1080), scale: 2, isMain: true)])
        let m = server.monitors[0]
        m.pertag[1].layout = .monocle
        m.pertag[2].layout = .grid
        m.pertag[2].configLayout = .deck                // a rule set deck then; it is gone now
        m.pertag[3].layout = .grid
        m.pertag[3].configLayout = .deck                // a rule set deck then, and still does
        m.pertag[4].layout = .grid
        m.pertag[4].configLayout = .deck                // now the rule says scroller
        m.tagset[m.seltags ^ 1] = 1 << 4
        m.prevTag = 5
        let saved = server.mac.memory.currentLayout(server)
        XCTAssertEqual(saved.tagLayouts?["1"]?[1], SavedLayout.TagLayout(layout: "monocle",
                                                                         configuredLayout: "tile"))

        let url = dir.appendingPathComponent("windows.json")
        try saved.write(to: url)
        let fresh = MangoServer(configURL: URL(fileURLWithPath: "/nonexistent/mango.conf"))
        fresh.system = FakeWindowSystem(fresh)
        fresh.rebuildMonitors(screens: [server.monitors[0].screen])
        let f = fresh.monitors[0]
        f.pertag[3].configLayout = .deck                // what the config gives now
        f.pertag[4].configLayout = .scroller
        f.pertag[4].layout = .scroller
        fresh.mac.memory.layoutURL = url
        fresh.mac.memory.restore(fresh)
        XCTAssertEqual(f.pertag[1].layout, .monocle)
        XCTAssertEqual(f.pertag[2].layout, .tile, "its rule is gone: tile, as mango's reload")
        XCTAssertEqual(f.pertag[3].layout, .grid, "its rule is unchanged: the layout in use stays")
        XCTAssertEqual(f.pertag[4].layout, .scroller, "its rule changed: the rule's layout")
        XCTAssertEqual(f.tagset[f.seltags ^ 1], 1 << 4, "view goes back to the tags shown before")
        XCTAssertEqual(f.prevTag, 5)
    }
}
