import XCTest
@testable import Mango
@testable import Port
final class PlaceholderTests: MangoTestCase {
    func testTagMask() {
        XCTAssertEqual(TagMask.parseTagMask("1|3"), 0b101)
        XCTAssertEqual(TagMask.parseTagMask("0"), TagMask.special)
        XCTAssertEqual(TagMask.parseTagMask("-1"), TagMask.all)
    }
}
