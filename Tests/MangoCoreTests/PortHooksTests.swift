import XCTest
@testable import Mango
@testable import Port

/// Without the port's extensions registered, mango is mango: no extra dispatcher, no
/// colour of the port's own, nothing floats instead of tiling.
@MainActor
final class PortHooksTests: MangoTestCase {
    func testWithoutTheExtensionsMangoIsMango() {
        let r = EngineRig()
        r.server.portHooks = PortHooks()
        r.server.config.chutneyFloatingColor = parseColor("0xff0000ff")
        let c = r.window(900_800, floating: true)
        XCTAssertNotEqual(r.server.getBorderColor(c), r.server.config.chutneyFloatingColor, "chutney_floating_color needs the port")
        XCTAssertNil(r.server.portHooks.extraDispatchers["chutney_focus_app"])
        _ = r.server.dispatch(Dispatch(name: "chutney_focus_app", args: ["com.example.none"]))   // does nothing
    }

    /// chutney_border_unfocused off and chutney_tab_bar_app_icons on do nothing without the port: mango draws
    /// every window's border and no icons; registered, they work.
    func testBorderUnfocusedAndTabIconsNeedThePort() {
        let r = EngineRig()
        r.server.renderBorder = true
        r.server.drawsOverlays = true
        r.server.config.chutneyBorderUnfocused = false
        r.server.config.chutneyTabBarAppIcons = true
        let a = r.window(900_810), _ = r.window(900_811)
        r.server.arrange(r.monitor, .none)
        r.server.clientFocus(a)
        let fake = r.server.system as! FakeWindowSystem
        XCTAssertEqual(fake.borderSpecs.count, 1, "registered: the focused window's border only")
        r.server.portHooks = PortHooks()
        r.server.updateBorders()
        XCTAssertEqual(fake.borderSpecs.count, 2, "without the port: mango's, every window's")
    }

    func testRegisteredTheyWork() {
        let r = EngineRig()
        r.server.config.chutneyFloatingColor = parseColor("0xff0000ff")
        let c = r.window(900_803, floating: true)
        XCTAssertEqual(r.server.getBorderColor(c), r.server.config.chutneyFloatingColor)
        XCTAssertNotNil(r.server.portHooks.extraDispatchers["chutney_focus_app"])
    }

    /// chutney_ignore_apps reaches the watcher when the config is read.
    func testIgnoreAppsIsTakenWhenTheConfigIsRead() {
        let r = EngineRig()
        r.server.config.chutneyIgnoreApps = ["com.example.ignored"]
        for loaded in r.server.portHooks.configLoaded { loaded(r.server) }
        XCTAssertEqual(r.server.mac.watcher.ignoredBundleIds, ["com.example.ignored"])
    }

    /// The port's config keys are exactly its listed extensions, apart from mango's.
    func testThePortsKeysAreItsOwnTable() {
        XCTAssertEqual(Set(PortOptions.setters.keys), Set(MangoCompat.portExtensionOptions.keys))
        XCTAssertTrue(Set(PortOptions.setters.keys).isDisjoint(with: ConfigOptions.mangoSetters.keys))
    }
}

/// chutney_set_proportion_all (port extension): set_proportion for every window of the tag in
/// view, with set_proportion's conditions; without a value, scroller_default_proportion.
@MainActor
final class SetProportionAllTests: MangoTestCase {
    func testEveryWindowOfTheTagInTheScroller() {
        let r = EngineRig()
        r.monitor.current.layout = .scroller
        let a = r.map(1), b = r.map(2), c = r.map(3)
        a.scrollerProportion = 0.69
        b.scrollerProportion = 0.86
        _ = r.server.dispatch(Dispatch(name: "chutney_set_proportion_all", args: ["0.5"]))
        XCTAssertEqual([a, b, c].map(\.scrollerProportion), [0.5, 0.5, 0.5])
        _ = r.server.dispatch(Dispatch(name: "chutney_set_proportion_all"))
        let d = r.monitor.current.settings.scrollerDefaultProportion
        XCTAssertEqual([a, b, c].map(\.scrollerProportion), [d, d, d])
    }

    func testOnlyInTheScroller() {
        let r = EngineRig()
        let a = r.map(1), _ = r.map(2)
        _ = r.server.dispatch(Dispatch(name: "chutney_set_proportion_all", args: ["0.5"]))
        XCTAssertEqual(a.scrollerProportion, 0.9, "unchanged")
    }
}
