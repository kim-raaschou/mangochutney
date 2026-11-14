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
        for p in r.monitor.pertag { p.settings.mfact = 0.3; p.settings.nmaster = 3 }
        r.server.resetOption()
        for p in r.monitor.pertag {
            XCTAssertEqual(p.settings.mfact, 0.55, accuracy: 0.0001)
            XCTAssertEqual(p.settings.nmaster, 1)
        }
    }

    func testReapplyMasterSetsTheGaps() {
        let r = EngineRig()
        r.server.config.gappih = 11
        r.server.config.specialGappov = 13
        r.server.resetOption()
        XCTAssertEqual(r.monitor.gaps.ih, 11)
        XCTAssertEqual(r.monitor.specialGaps.ov, 13)
    }

    func testEnvIsSetAsParsedWithDisplayLast() {
        let r = EngineRig()
        let key = "MANGO_TEST_\(UUID().uuidString.prefix(8))"
        defer { unsetenv(key) }
        r.server.config.envVars = [(key, "~x")]
        r.server.resetOption()
        XCTAssertEqual(ProcessInfo.processInfo.environment[key], "~x", "only ~/ is expanded, and when the config is read")
    }

    func testTheTagRulesAreReappliedAfterTheMasterReset() {
        let r = EngineRig()
        r.server.config.defaultMfact = 0.55
        var rule = TagRule()
        rule.id = 2
        rule.masterFactor = 0.7
        r.server.config.tagRules = [rule]
        r.server.resetOption()
        XCTAssertEqual(r.monitor.pertag[2].settings.mfact, 0.7, accuracy: 0.0001)
        XCTAssertEqual(r.monitor.pertag[1].settings.mfact, 0.55, accuracy: 0.0001)
    }
}
