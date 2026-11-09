import XCTest
@testable import Mango
@testable import Port

@MainActor
final class PortHooksTests: MangoTestCase {
    func testWithoutTheExtensionsMangoIsMango() {
        let r = EngineRig()
        r.server.portHooks = PortHooks()
        XCTAssertNil(r.server.portHooks.extraDispatchers["chutney_focus_app"])
        _ = r.server.dispatch(Dispatch(name: "chutney_focus_app", args: ["com.example.none"]))
    }

    func testRegisteredTheyWork() {
        let r = EngineRig()
        XCTAssertNotNil(r.server.portHooks.extraDispatchers["chutney_focus_app"])
    }

    func testThePortsKeysAreItsOwnTable() {
        XCTAssertEqual(Set(PortOptions.setters.keys), Set(MangoCompat.portExtensionOptions.keys))
        XCTAssertTrue(Set(PortOptions.setters.keys).isDisjoint(with: ConfigOptions.mangoSetters.keys))
    }
}

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
