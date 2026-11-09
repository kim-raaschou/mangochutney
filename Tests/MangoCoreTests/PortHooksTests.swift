import XCTest
@testable import Mango
@testable import Port

@MainActor
final class PortHooksTests: MangoTestCase {
    func testWithoutTheExtensionsMangoIsMango() {
        let r = EngineRig()
        r.server.portHooks = PortHooks()
        XCTAssertNil(r.server.portHooks.extraDispatchers["chutney_launch_or_focus"])
        _ = r.server.dispatch(Dispatch(name: "chutney_launch_or_focus", args: ["com.example.none"]))
    }

    func testRegisteredTheyWork() {
        let r = EngineRig()
        XCTAssertNotNil(r.server.portHooks.extraDispatchers["chutney_launch_or_focus"])
    }

    func testThePortsKeysAreItsOwnTable() {
        XCTAssertEqual(Set(PortOptions.setters.keys), Set(MangoCompat.portExtensionOptions.keys))
        XCTAssertTrue(Set(PortOptions.setters.keys).isDisjoint(with: ConfigOptions.mangoSetters.keys))
    }
}

