import XCTest
@testable import Mango
@testable import Port

/// mango's reset_option (config/reapply.c): a reload re-applies the options in mango's order.
@MainActor
final class ResetOptionTests: MangoTestCase {
    func fake(_ r: EngineRig) -> FakeWindowSystem { r.server.system as! FakeWindowSystem }

    func testAReloadRunsExecButNotExecOnce() {
        let r = EngineRig()
        r.server.config.exec = ["echo a"]
        r.server.config.execOnce = ["echo b"]
        r.server.resetOption()
        r.server.resetOption()
        XCTAssertEqual(fake(r).shelled, ["echo a", "echo a"])
    }

    func testReapplyMasterPutsEveryTagBackToTheDefaults() {
        let r = EngineRig()
        r.server.config.defaultMfact = 0.55
        r.server.config.defaultNmaster = 1
        let pt = r.monitor.pertag
        for i in 0..<Int(PERTAG_SLOTS) { pt.mfacts[i] = 0.3; pt.nmasters[i] = 3 }
        r.server.resetOption()
        for i in 0..<Int(PERTAG_SLOTS) {
            XCTAssertEqual(pt.mfacts[i], 0.55, accuracy: 0.0001)
            XCTAssertEqual(pt.nmasters[i], 1)
        }
    }

    func testReapplyMasterSetsTheGaps() {
        let r = EngineRig()
        r.server.config.gappih = 11
        r.server.config.specialGappov = 13
        r.server.resetOption()
        XCTAssertEqual(r.monitor.gappih, 11)
        XCTAssertEqual(r.monitor.specialGappov, 13)
    }

    func testEnvIsSetAsParsedWithDisplayLast() {
        let r = EngineRig()
        let key = "MANGO_TEST_\(UUID().uuidString.prefix(8))"
        defer { unsetenv(key) }
        r.server.config.envVars = [(key, "~x")]
        r.server.resetOption()
        XCTAssertEqual(ProcessInfo.processInfo.environment[key], "~x", "only ~/ is expanded, and when the config is read")
    }

}
