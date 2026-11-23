import XCTest
@testable import Mango
import MangoTestKit

/// mango's src/config/binding_parse.c
final class BindingParseTests: XCTestCase {

    // MARK: parse_mod

    func testUnknownModifiersAreSkipped() {
        XCTAssertEqual(BindingParser.parseMod("SUPER+FOO"), .superKey)
        XCTAssertNil(BindingParser.parseMod("FOO"))
        XCTAssertNil(BindingParser.parseMod(""))
    }

    // MARK: parse_func_name

    func testDispatcherNamesAreCaseSensitive() {
        let port = ConfigParser.port
        ConfigParser.port = FakeKeymap()
        defer { ConfigParser.port = port }

        let c = ConfigParser.parse(text: "bind=SUPER,j,FocusStack,next", baseDirectory: nil, fileName: "t")

        XCTAssertTrue(c.config.keyBindings.isEmpty)
        XCTAssertTrue(c.errors.first?.message.contains("Unknown dispatch") ?? false)
    }
}
