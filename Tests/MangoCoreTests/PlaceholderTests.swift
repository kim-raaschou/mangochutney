import XCTest
@testable import Mango
@testable import Port
final class PlaceholderTests: MangoTestCase {
    func testTagMask() {
        XCTAssertEqual(ValueParse.parseTagMask("1|3"), 0b101)
        XCTAssertEqual(ValueParse.parseTagMask("0"), TAG0_MASK)
        XCTAssertEqual(ValueParse.parseTagMask("-1"), 0xFFFF_FFFF)
    }
}
