import XCTest
@testable import Mango
@testable import Port
import MangoTestKit

/// mango's own judgement of a config. Each file in Tests/MangoFacit/configs was checked by mango 0.18.5
/// (`mango -c <file> -p`, Tests/MangoFacit/record); read by our parser with the macOS port's side of
/// the config, as our `mango -p` reads it, it must give the same errors and the same exit.
final class ConfigFacitTests: XCTestCase {

    func testEveryConfigIsJudgedAsMango() throws {
        XCTAssertFalse(ConfigFacit.all.isEmpty)
        for name in ConfigFacit.all {
            let mango = try ConfigFacit(name)
            let expected = mango.expected
            let ours = ConfigFacit.ours(mango.url, port: MacConfigPort())
            for i in 0..<max(expected.count, ours.errors.count) {
                let m = i < expected.count ? expected[i].description : "nothing"
                let o = i < ours.errors.count ? ours.errors[i].description : "nothing"
                if m != o { XCTFail("\(name) error \(i + 1): mango \(m), ours \(o)") }
            }
            XCTAssertEqual(ours.exit, mango.exit, "\(name): exit")
        }
    }
}
